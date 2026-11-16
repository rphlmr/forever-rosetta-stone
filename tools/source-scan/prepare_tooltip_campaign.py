#!/usr/bin/env python3
"""Prepare a bounded recapture campaign from a tooltip gap report; never install or collect."""

import argparse
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from prepare_api_sample import global_keys, write_probe_copy
from import_client_api_fixture import to_lua
from tools.catalogs.catalog_storage import dump_json


def select(report, per_group):
    """Reuse selected IDs across groups; example IDs are candidates, not exhaustive coverage."""
    groups = report.get('groups', [])
    frequency = Counter((g['kind'], entity_id) for g in groups for entity_id in g['exampleIds'])
    selected = {'spell': set(), 'item': set()}
    for group in sorted(groups, key=lambda g: (len(g['exampleIds']), g['kind'], g['pattern'])):
        kind = group['kind']
        candidates = set(group['exampleIds'])
        remaining = min(per_group, len(candidates)) - len(candidates & selected[kind])
        ranked = sorted(candidates - selected[kind], key=lambda entity_id: (-frequency[kind, entity_id], entity_id))
        selected[kind].update(ranked[:max(0, remaining)])
    for kind, ids in report.get('notLoaded', {}).items():
        selected[kind].update(ids)
    return {kind: sorted(ids) for kind, ids in selected.items()}


def prepare(report_path, output, per_group=2, root=ROOT):
    report = json.loads(report_path.read_text(encoding='utf-8'))
    selection = select(report, per_group)
    # Existing calibration cases stay available for gear profiles; the API pass is bounded.
    counts = {kind: {'sampled': len(ids)} for kind, ids in selection.items()}
    sample = {'mode': 'targeted-gaps', 'perGroup': per_group,
              'reportSha256': hashlib.sha256(report_path.read_bytes()).hexdigest()}
    write_probe_copy(output, selection, global_keys(root), sample, 60, counts)
    addon = output / 'rosetta-tooltip-check'
    path = addon / 'api-sample.lua'
    source = path.read_text(encoding='utf-8')
    # Clear the base API inventory before extending it, including unrelated quests and maps.
    source = source.replace('local api = Probe.cases.api',
                            'local api = Probe.cases.api\napi.ids = {spell = {}, item = {}}')
    path.write_text(source, encoding='utf-8')
    manifest = json.loads((output / 'sample.json').read_text(encoding='utf-8'))
    manifest.update(sourceReport=str(report_path), sourceClientLocale=report['clientLocale'],
                    sourceRun=report['run'], candidateGroups=len(report['groups']),
                    recaptureNotLoaded=report.get('notLoaded', {}),
                    coverage='Selected examples of known gap groups, not all entities or character states')
    (output / 'sample.json').write_text(dump_json(manifest), encoding='utf-8')
    return manifest


def prepare_fixture(fixture_path, output):
    """Recapture the complete frozen inventory and stable getter arguments in another locale."""
    fixture = json.loads(fixture_path.read_text(encoding='utf-8'))
    selected, exact = {'spell': set(), 'item': set()}, {}
    keys = set()
    for snapshot in fixture['globals'].values():
        keys.update(snapshot)
    for run in fixture['runs']:
        for sample in run['samples']:
            details = sample['details']
            if sample['kind'] == 'api':
                for kind, api in (('spell', 'C_TooltipInfo.GetSpellByID'), ('item', 'C_TooltipInfo.GetItemByID')):
                    selected[kind].update(map(int, details['calls'].get(api, {})))
            elif sample['kind'] == 'hover':
                kind = {'Spell': 'spell', 'UnitAura': 'spell', 'Item': 'item'}.get(details.get('dataType'))
                if kind and isinstance(details.get('entityID'), int):
                    selected[kind].add(details['entityID'])
                info = details.get('processingInfo', {}).get('values', {}).get('1')
                if not isinstance(info, dict) or info.get('getterName') not in (
                        'GetTraitEntry', 'GetRecipeResultItem', 'GetRecipeReagentItem'):
                    continue
                args = info.get('getterArgs') or {}
                values = [args.get(str(i), '<nil>') for i in range(1, args.get('n', len(args)) + 1)]
                if any(value in ('<restricted>', '<function>') for value in values):
                    continue
                api = 'C_TooltipInfo.' + info['getterName']
                arguments = {i: value for i, value in enumerate(values, 1) if value != '<nil>'}
                arguments['n'] = len(values)
                exact[api, json.dumps(values)] = {'api': api, 'args': arguments}
    selection = {kind: sorted(ids) for kind, ids in selected.items()}
    sample = {'mode': 'paired-capture', 'fixtureSha256': hashlib.sha256(fixture_path.read_bytes()).hexdigest()}
    counts = {kind: {'sampled': len(ids)} for kind, ids in selection.items()}
    write_probe_copy(output, selection, sorted(keys), sample, 90, counts)
    path = output / 'rosetta-tooltip-check/api-sample.lua'
    source = path.read_text().replace('local api = Probe.cases.api',
                                    'local api = Probe.cases.api\napi.ids = {spell = {}, item = {}}')
    source += '\napi.exactCalls = ' + to_lua([exact[key] for key in sorted(exact)]) + '\n'
    path.write_text(source)
    manifest = json.loads((output / 'sample.json').read_text())
    manifest.update(sourceFixture=str(fixture_path), sourceCapture=fixture['source'], exactGetterCalls=len(exact))
    (output / 'sample.json').write_text(dump_json(manifest))
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--report', type=Path)
    inputs.add_argument('--fixture', type=Path, help='Recapture all IDs and stable getter arguments from a frozen campaign')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--per-group', default=2, type=int)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / 'datasources/imports').resolve()) or output.exists():
        parser.error('--output must be a new directory under datasources/imports/')
    if args.per_group <= 0:
        parser.error('--per-group must be positive')
    output.mkdir(parents=True)
    result = prepare_fixture(args.fixture, output) if args.fixture else prepare(args.report, output, args.per_group)
    print(f"Prepared {result['counts']}: {output}")


if __name__ == '__main__':
    main()
