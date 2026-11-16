"""Prepare verified quest target mappings and matrix context from a local capture."""

import argparse
import copy
import difflib
import hashlib
import json
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from datasources.lua_data import assignments
from tools.catalogs.catalog_storage import get_digest, load_catalog, load_entity


def read_assignment(path, name):
    values = list(assignments(Path(path).read_text(), [(name,)]))
    if len(values) != 1 or not isinstance(values[0][1], dict):
        raise ValueError('Expected one literal ' + name)
    return values[0][1]


def sequence(value):
    if not isinstance(value, dict) or set(value) != set(range(1, len(value) + 1)):
        raise ValueError('Expected contiguous client indices')
    return [value[index] for index in range(1, len(value) + 1)]


def match_targets(quest, rows, lookup, locales):
    targets = []
    for row in rows:
        if row['type'] == 'reputation':
            if any(type(row.get(key)) is not int or row[key] < 0 for key in ('numFulfilled', 'numRequired')):
                return None, 'missing or inconsistent objective counter'
            ranks = ('Hated', 'Hostile', 'Unfriendly', 'Neutral', 'Friendly', 'Honored', 'Revered', 'Exalted')
            text = row.get('text')
            prefix = re.fullmatch(r'([^/]+) / ([^ ]+) (.+)', text) if isinstance(text, str) else None
            if not prefix or prefix[1] not in ranks or prefix[2] not in ranks:
                return None, 'unrecognized reputation objective wording'
            matches = set()
            for candidate in quest.get('objectiveTargets', {}).get('reputation', []):
                entity = lookup('faction', candidate['id']) or {}
                if entity.get('locales', {}).get('enUS', {}).get('name') == prefix[3]:
                    matches.add(candidate['id'])
            if len(matches) != 1:
                return None, 'reputation label has no unique quest-linked identity'
            identity = next(iter(matches))
            targets.append({'kind': 'faction', 'id': identity, 'type': 'reputation'})
            continue
        kind = 'item' if row['type'] == 'item' else 'npc' if row['type'] == 'monster' else None
        if not kind:
            return None, 'unsupported objective type'
        if any(type(row.get(key)) is not int or row[key] < 0 for key in ('numFulfilled', 'numRequired')):
            return None, 'missing or inconsistent objective counter'
        prefix = re.match(r'^\s*(\d+)\s*/\s*(\d+)\s*(.*?)\s*$', row['text'])
        if not prefix or (int(prefix[1]), int(prefix[2])) != (row.get('numFulfilled'), row.get('numRequired')):
            return None, 'missing or inconsistent objective counter'
        label = prefix[3]
        if kind == 'npc':
            suffix = next((ending for ending in (' slain', ' destroyed') if label.endswith(ending)), None)
            if not suffix:
                return None, 'unverified NPC objective wording'
            label = label[:-len(suffix)]
        if not label:
            return None, 'missing objective label'
        matches = set()
        for candidate in quest.get('objectiveTargets', {}).get(kind, []):
            entity = lookup(kind, candidate['id']) or {}
            if entity.get('locales', {}).get('enUS', {}).get('name') == label:
                matches.add(candidate['id'])
        if len(matches) != 1:
            return None, 'objective label has no unique quest-linked identity'
        identity = next(iter(matches))
        entity = lookup(kind, identity)
        if any(not entity.get('locales', {}).get(locale, {}).get('name') for locale in locales):
            return None, 'missing target name translation'
        target = {'kind': kind, 'id': identity}
        if kind == 'npc':
            target['type'] = 'monster'
        targets.append(target)
    return targets, None


def match_target_rows(quest, rows, lookup, locales):
    """Match rows independently; indices always come from the captured row order."""
    verified, unresolved = {}, []
    for index, row in enumerate(rows, 1):
        targets, reason = match_targets(quest, [row], lookup, locales)
        if reason:
            unresolved.append({'index': index, 'reason': reason})
        else:
            verified[index] = targets[0]
    return verified, unresolved


def indexed_targets(targets):
    indexed = {}
    for position, target in enumerate(targets or [], 1):
        index = target.get('index', position)
        if type(index) is not int or index < 1 or index in indexed:
            raise ValueError('Invalid or duplicate existing objective index')
        indexed[index] = {key: value for key, value in target.items() if key != 'index'}
    return indexed


def comparison_rows(data, queue, results):
    """Select completed observations only after checking their identity and row consistency."""
    selected = {}
    comparisons = data.get('comparisons')
    if comparisons is None:
        return selected
    for comparison in sequence(comparisons):
        if not isinstance(comparison, dict):
            raise ValueError('Invalid comparison')
        if comparison.get('status') != 'complete':
            continue
        identity = comparison.get('questID')
        result = results.get(identity)
        if (type(identity) is not int or not result or result.get('status') != 'loadedWithObjectives'
                or result.get('loadSuccess') is not True or comparison.get('queueHash') != queue['hash']
                or comparison.get('build') != data['build'] or comparison.get('locale') != data['locale']):
            raise ValueError('Comparison identity conflict: ' + str(identity))
        dependencies = sequence(comparison.get('dependencies'))
        candidates = queue.get('itemDependencies', {}).get(identity)
        if (candidates is None or [entry.get('id') for entry in dependencies if isinstance(entry, dict)] != sequence(candidates)
                or any(not isinstance(entry, dict) or entry.get('status') not in ('loaded', 'failed', 'timeout', 'requestError', 'alreadyCached')
                       for entry in dependencies)):
            raise ValueError('Comparison dependency conflict: ' + str(identity))
        before, after = comparison.get('before'), comparison.get('after')
        if not isinstance(before, dict) or not isinstance(after, dict) or before.get('readSuccess') is not True or after.get('readSuccess') is not True:
            raise ValueError('Comparison read failed: ' + str(identity))
        snapshots = [sequence(result.get('rows')), sequence(before.get('rows')), sequence(after.get('rows'))]
        if not snapshots[0] or any(len(rows) != len(snapshots[0]) for rows in snapshots):
            raise ValueError('Comparison row conflict: ' + str(identity))
        for original, first, last in zip(*snapshots):
            if any(not isinstance(row, dict) for row in (original, first, last)):
                raise ValueError('Comparison row conflict: ' + str(identity))
            for key in ('type', 'numFulfilled', 'numRequired'):
                if key not in original or original[key] != first.get(key) or original[key] != last.get(key):
                    raise ValueError('Comparison row conflict: ' + str(identity))
            labels = set()
            for row in (original, first, last):
                text = row.get('text')
                if not isinstance(text, str):
                    raise ValueError('Comparison row conflict: ' + str(identity))
                match = re.match(r'^\s*\d+\s*/\s*\d+\s*(.*?)\s*$', text)
                label = match.group(1) if match else text.strip()
                if row.get('type') == 'monster' and label == 'slain':
                    label = ''
                if label:
                    labels.add(label)
            if len(labels) > 1:
                raise ValueError('Comparison label conflict: ' + str(identity))
        if identity in selected and selected[identity] != snapshots[2]:
            raise ValueError('Comparison observation conflict: ' + str(identity))
        selected[identity] = snapshots[2]
    return selected


def prepare(capture, queue_path, variable, output, root=ROOT):
    output = Path(output)
    if not output.resolve().is_relative_to((Path(root) / 'datasources/imports').resolve()):
        raise ValueError('Import outputs must stay under datasources/imports')
    raw = Path(capture).read_bytes()
    data = read_assignment(capture, variable)
    queue = read_assignment(queue_path, 'RosettaQuestProbeQueue')
    ids = sequence(queue['ids'])
    if len(set(ids)) != len(ids) or any(type(value) is not int or value <= 0 for value in ids):
        raise ValueError('Invalid queue IDs')
    quests = {str(value): load_entity(root, 'quests', value) for value in ids}
    if (data.get('schemaVersion') != 1 or data.get('locale') != 'enUS'
            or data.get('queueHash') != queue['hash'] or data.get('catalogHash') != queue['catalogHash']
            or get_digest(quests) != queue['catalogHash']):
        raise ValueError('Capture identity, locale or queued catalog fingerprints do not match')
    if not isinstance(data.get('build'), str) or not re.fullmatch(r'\d+', data['build']):
        raise ValueError('Missing client build')
    results = {key: value for key, value in data['results'].items() if value is not None}
    if (set(results) != set(ids) or data.get('nextIndex') != len(ids) + 1
            or any(not isinstance(value, dict) for value in results.values())):
        raise ValueError('Incomplete or out-of-scope capture')
    compared = comparison_rows(data, queue, results)
    locales = load_catalog(root, 'quests', ids={})['locales']
    cache = {}

    def lookup(kind, identity):
        key = kind, identity
        if key not in cache:
            cache[key] = load_entity(root, {'item': 'items', 'npc': 'npcs', 'faction': 'factions'}[kind], identity)
        return cache[key]

    digest = hashlib.sha256(raw).hexdigest()
    fixture = {'source': 'clientCapture', 'sourceBuild': data['build'], 'sourceLocale': data['locale'],
               'sourceFileSha256': digest, 'queueHash': queue['hash'], 'quests': {}}
    patch = ['*** Begin Patch\n']
    report = {'statuses': dict(Counter(value['status'] for value in results.values())),
              'changed': [], 'skipped': [], 'observedQuests': 0, 'observedRows': 0,
              'comparisonQuests': sorted(compared), 'rowResults': []}
    for identity in sorted(results):
        result = results[identity]
        if result['status'] != 'loadedWithObjectives':
            continue
        quest = quests[str(identity)]
        if (not quest or result.get('loadSuccess') is not True
                or result.get('title') != quest.get('locales', {}).get('enUS', {}).get('title')):
            raise ValueError('Quest identity conflict: ' + str(identity))
        rows = compared.get(identity) or sequence(result['rows'])
        if not rows or any(not isinstance(row, dict) or not isinstance(row.get('type'), str)
                           or not isinstance(row.get('text'), str) for row in rows):
            raise ValueError('Invalid objective rows: ' + str(identity))
        fixture['quests'][str(identity)] = {
            'titleSha256': hashlib.sha256(result['title'].encode()).hexdigest(),
            'types': [row['type'] for row in rows],
        }
        report['observedQuests'] += 1
        report['observedRows'] += len(rows)
        verified, unresolved = match_target_rows(quest, rows, lookup, locales)
        existing = indexed_targets(quest.get('clientObjectiveTargets'))
        for index in list(verified):
            target = verified[index]
            reason = None
            if index in existing and existing[index] != target:
                reason = 'existing verified target mapping differs'
            for localized in quest['locales'].values():
                for line in localized.get('objectiveLines', []):
                    if line['index'] == index and line['type'] != rows[index - 1]['type']:
                        reason = 'existing objective type differs'
            if reason:
                unresolved.append({'index': index, 'reason': reason})
                del verified[index]
        merged = dict(existing)
        if existing and not all(index in verified for index in existing):
            for index in sorted(set(verified) - set(existing)):
                unresolved.append({'index': index, 'reason': 'existing mapping provenance could not be reverified'})
                del verified[index]
        merged.update(verified)
        report['rowResults'].append({'id': identity, 'verified': sorted(verified),
                                     'unresolved': sorted(unresolved, key=lambda row: row['index'])})
        if unresolved:
            report['skipped'].append({'id': identity, 'reason': 'one or more rows unresolved',
                                      'rows': sorted(unresolved, key=lambda row: row['index'])})
        if merged == existing:
            continue
        ordered = sorted(merged)
        if ordered == list(range(1, len(rows) + 1)) and not any(merged[index]['kind'] == 'faction' for index in ordered):
            targets = [merged[index] for index in ordered]
        else:
            targets = [dict(index=index, **merged[index]) for index in ordered]
        after = copy.deepcopy(quest)
        after['clientObjectiveTargets'] = targets
        after['clientObjectiveTargetsMetadata'] = {
            'source': 'clientCapture', 'sourceBuild': data['build'], 'sourceLocale': 'enUS',
            'sourceFileSha256': digest,
        }
        path = Path(root) / 'catalogs/quests' / (str(identity) + '.json')
        before = path.read_text()
        updated = json.dumps(after, ensure_ascii=False, indent=2) + '\n'
        diff = list(difflib.unified_diff(before.splitlines(True), updated.splitlines(True)))[2:]
        patch.append('*** Update File: ' + path.relative_to(root).as_posix() + '\n')
        patch.extend('@@\n' if line.startswith('@@ ') else line for line in diff)
        report['changed'].append(identity)
    patch.append('*** End Patch\n')
    output.mkdir(parents=True, exist_ok=False)
    (output / 'updates.patch').write_text(''.join(patch))
    (output / 'client-objectives.json').write_text(json.dumps(fixture, indent=2) + '\n')
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture', type=Path, required=True)
    parser.add_argument('--queue', type=Path, required=True)
    parser.add_argument('--variable', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = prepare(args.capture, args.queue, args.variable, args.output)
    print(f'{len(report["changed"])} proposed catalog mappings; {report["observedQuests"]} observed quests; '
          f'{report["observedRows"]} indexed rows. Review patches before applying.')
