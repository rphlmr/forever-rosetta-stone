#!/usr/bin/env python3
"""Propose capture-backed item description row rules without changing catalogs."""

import argparse
import csv
import difflib
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import dump_json, get_digest, load_entity, read_json
from datasources.lua_data import assignments


def sequence(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and set(value) == set(range(1, len(value) + 1)):
        return [value[k] for k in range(1, len(value) + 1)]
    raise ValueError('Expected a captured sequence')


def equivalent(actual, expected):
    if isinstance(expected, list):
        try:
            values = sequence(actual)
        except ValueError:
            return False
        return len(values) == len(expected) and all(equivalent(a, b) for a, b in zip(values, expected))
    if isinstance(expected, dict):
        return isinstance(actual, dict) and set(actual) == set(expected) and all(
            equivalent(actual[k], v) for k, v in expected.items())
    return type(actual) is type(expected) and actual == expected


def prepare(queue, capture, session_id, item_ids, prefix, expected_build, root=ROOT):
    if queue.get('schemaVersion') != 1 or queue.get('hash') != get_digest({k: v for k, v in queue.items() if k != 'hash'}):
        raise ValueError('Invalid queue hash')
    sessions = sequence(capture.get('sessions'))
    session = sessions[int(session_id) - 1] if str(session_id).isdigit() and 0 < int(session_id) <= len(sessions) else {}
    if (capture.get('schemaVersion') != 1 or session.get('locale') != 'enUS'
            or session.get('queueHash') != queue['hash'] or session.get('catalogHash') != queue.get('catalogHash')
            or str(session.get('build')) != expected_build.rsplit('.', 1)[-1]):
        raise ValueError('Capture session does not match queue, locale or build')
    jobs = queue.get('profiles', {}).get('enUS', {}).get('jobs', [])
    if any(job.get('kind') not in ('items', 'spells') or job.get('talentIds') for job in jobs):
        raise ValueError('Only explicit item/spell queues are supported')
    records = {}
    for job in jobs:
        key = f"{job['kind']}/{job['id']}"
        if key in records:
            raise ValueError('Duplicate queue job')
        records[key] = load_entity(root, job['kind'], job['id'])
        if records[key] is None:
            raise ValueError('Missing queued catalog record')
    if get_digest(records) != queue['catalogHash']:
        raise ValueError('Queued catalog snapshot changed')
    results = sequence(session.get('results'))
    if session.get('nextIndex') != len(jobs) + 1 or len(results) != len(jobs):
        raise ValueError('Incomplete captured queue')
    if any(not equivalent(result.get('job'), job) for result, job in zip(results, jobs)):
        raise ValueError('Captured job identity does not match queue')
    proposals = []
    for item_id in item_ids:
        matching_jobs = [j for j in jobs if j.get('kind') == 'items' and j.get('id') == item_id]
        observed = [r for r in results if r.get('job', {}).get('kind') == 'items' and r['job'].get('id') == item_id]
        if len(matching_jobs) != 1 or len(observed) != 1:
            raise ValueError(f'Expected one job and capture for item {item_id}')
        result = observed[0]
        capture_job = result['job']
        if (result.get('status') != 'captured' or sequence(capture_job.get('fields')) != matching_jobs[0].get('fields')
                or result.get('values', {}).get('tooltip', {}).get('id') != item_id
                or 'description' not in matching_jobs[0].get('fields', [])):
            raise ValueError(f'Invalid job or capture for item {item_id}')
        item = records[f'items/{item_id}']
        tooltip = item.get('tooltipData', {})
        if 'descriptionRow' in tooltip or 'descriptionRowSourceMetadata' in tooltip:
            raise ValueError(f'Existing binding for item {item_id}')
        body = item.get('locales', {}).get('enUS', {}).get('description')
        if not isinstance(body, str) or not body.strip() or not isinstance(prefix, str) or not prefix.strip():
            raise ValueError(f'Missing source description or prefix for item {item_id}')
        lines = sequence(result.get('values', {}).get('tooltip', {}).get('lines'))
        candidates = [line for line in lines if type(line.get('type')) is int and line['type'] == 38]
        if len(candidates) != 1 or candidates[0].get('leftText') != prefix + ' ' + body:
            raise ValueError(f'Ambiguous or mismatching learn row for item {item_id}')
        spell_id = candidates[0].get('spellID')
        links = [e for e in tooltip.get('effects', []) if e.get('spellID') == spell_id and e.get('triggerType') == 6]
        if type(spell_id) is not int or spell_id <= 0 or len(links) != 1:
            raise ValueError(f'Missing or ambiguous trigger link for item {item_id}')
        proposals.append({'id': item_id, 'item': item, 'spellID': spell_id,
                          'ownedHash': get_digest(item), 'descriptionSha256': hashlib.sha256(body.encode()).hexdigest()})
    return proposals


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--queue', required=True, type=Path)
    parser.add_argument('--capture', required=True, type=Path)
    parser.add_argument('--session', required=True)
    parser.add_argument('--ids', required=True, nargs='+', type=int)
    parser.add_argument('--global-strings', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--patch', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    if len(set(args.ids)) != len(args.ids) or any(i <= 0 for i in args.ids):
        parser.error('IDs must be distinct positive integers')
    manifest = read_json(args.manifest)
    entries = [r for r in manifest.get('results', []) if r.get('table') == 'GlobalStrings'
               and r.get('locale') == 'enUS' and r.get('file') == args.global_strings.name]
    expected_build = manifest.get('build')
    if (not isinstance(expected_build, str) or not expected_build.rsplit('.', 1)[-1].isdigit() or len(entries) != 1
            or hashlib.sha256(args.global_strings.read_bytes()).hexdigest() != entries[0].get('sha256')):
        raise ValueError('Unverified English GlobalStrings snapshot')
    with args.global_strings.open(newline='', encoding='utf-8') as handle:
        prefixes = [r['TagText_lang'] for r in csv.DictReader(handle) if r['BaseTag'] == 'ITEM_SPELL_TRIGGER_ONUSE']
    if len(prefixes) != 1:
        raise ValueError('Expected one English use prefix')
    queue = read_json(args.queue)
    parsed = list(assignments(args.capture.read_text(encoding='utf-8'), [('RosettaSourceProbeData',)]))
    if len(parsed) != 1 or not isinstance(parsed[0][1], dict):
        raise ValueError('Expected one literal RosettaSourceProbeData assignment')
    capture = parsed[0][1]
    proposals = prepare(queue, capture, args.session, args.ids, prefixes[0], expected_build)
    capture_hash = hashlib.sha256(args.capture.read_bytes()).hexdigest()
    patch = ['*** Begin Patch\n']
    report = []
    for proposal in proposals:
        item = proposal['item']
        before = dump_json(item)
        item['tooltipData']['descriptionRow'] = {'lineType': 'ItemSpellTriggerLearn', 'spellID': proposal['spellID'], 'triggerType': 6}
        item['tooltipData']['descriptionRowSourceMetadata'] = {'source': 'clientCapture', 'sourceBuild': expected_build,
            'sourceLocale': 'enUS', 'captureSha256': capture_hash, 'sourceDescriptionSha256': proposal['descriptionSha256']}
        after = dump_json(item)
        diff = list(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True), n=3))
        patch.append(f"*** Update File: catalogs/items/{proposal['id']}.json\n")
        patch.extend('@@\n' if line.startswith('@@ ') else line for line in diff[2:])
        report.append({k: proposal[k] for k in ('id', 'spellID', 'ownedHash', 'descriptionSha256')})
    patch.append('*** End Patch\n')
    for path in (args.patch, args.report):
        if path.exists() or not path.resolve().is_relative_to((ROOT / 'datasources/imports').resolve()):
            raise ValueError('Outputs must be new files under datasources/imports')
    args.patch.write_text(''.join(patch), encoding='utf-8')
    args.report.write_text(dump_json({'queueHash': queue['hash'], 'captureSha256': capture_hash, 'items': report}), encoding='utf-8')


if __name__ == '__main__':
    main()
