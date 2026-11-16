#!/usr/bin/env python3
"""Account for every real hover, keeping unsupported and incomplete inputs visible."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

import report_tooltip_gaps as gaps


def restore(value):
    if isinstance(value, list):
        return [restore(child) for child in value]
    if not isinstance(value, dict):
        return value
    result = {}
    for key, child in value.items():
        if key in ('calls', 'dependencies'):
            result[key] = {api: {arguments: restore(response) for arguments, response in responses.items()}
                           for api, responses in child.items()}
        else:
            result[int(key) if key.isdigit() else key] = restore(child)
    return result


def audit(capture, target='enUS'):
    # The enum itself was captured in this file, on the same client build.
    types = next(run['tooltipTypes'] for run in capture['runs'] if run.get('tooltipTypes'))
    kinds = {types[key]: value for key, value in
             (('Item', 'item'), ('Spell', 'spell'), ('Unit', 'npc'), ('UnitAura', 'aura'))}
    replays, results = {}, []
    for run in capture['runs']:
        for sample in run['samples']:
            if sample['kind'] != 'hover':
                raise ValueError('Hover inventory contains a non-hover sample')
            details = sample['details']
            data = gaps.clean(details['data'])
            kind = kinds.get(data.get('type'), 'unsupported')
            result = {'run': run['run'], 'sample': sample['sample'], 'kind': kind,
                      'id': data.get('id'), 'status': 'unsupported'}
            results.append(result)
            if kind == 'aura':
                result.update(status='missing_context',
                              missing=['C_UnitAuras return for the exact hovered aura instance'])
                key = details['globalsRef']
                if key not in replays:
                    replays[key] = gaps.Replay('frFR', capture['globals'][key], tooltip_types=types)
                replay = replays[key]
                replay.install_calls(gaps.context_calls(details.get('dependencies', {}), sample.get('context')))
                decoder = replay.lua.globals().ReplayAddon.TranslateLiveSpellDescription
                matches = []
                # Exercise the decoder with captured text, without fabricating the missing aura API.
                # This is partial evidence only: ownership resolution and the full renderer remain unvalidated.
                for first in range(1, len(data['lines'])):
                    for last in range(first, min(len(data['lines']), first + 16)):
                        native = '\n'.join(row.get('leftText', '') for row in data['lines'][first:last + 1])
                        translated = decoder(replay.lua.globals().ReplayAddon, data['id'], target.encode(),
                                             native.encode(), b'auraDescription')
                        if translated:
                            matches.append({'first': first + 1, 'last': last + 1,
                                            'native': native, 'translated': translated.decode()})
                result['descriptionChecks'] = matches
                continue
            if kind == 'unsupported':
                result['reason'] = 'No shipping tooltip component for this captured data type'
                continue
            if kind == 'npc':
                guid = data.get('guid', '')
                match = re.match(r'^(Creature|Vehicle)-[^-]+-[^-]+-[^-]+-[^-]+-(\d+)-', guid)
                if not match:
                    result.update(status='not_applicable',
                                  reason='The shipping NPC component handles Creature and Vehicle GUIDs only')
                    continue
                entity_id = int(match[2])
            else:
                identities = [details.get('entityID'), data.get('id')]
                response = details.get('item' if kind == 'item' else 'spell', {})
                if response.get('status') == 'ok':
                    identities.append(response.get('values', {}).get(3 if kind == 'item' else 2))
                identities = {value for value in identities if type(value) is int and value > 0}
                if len(identities) != 1:
                    result.update(status='missing_context', missing=['Unambiguous captured entity ID'])
                    continue
                entity_id = identities.pop()
            result['id'] = entity_id
            key = details['globalsRef']
            globals_ = {k: v for k, v in capture['globals'][key].items() if v != '<nil>'}
            if key not in replays:
                replays[key] = gaps.Replay('frFR', globals_, tooltip_types=types)
            replay = replays[key]
            unit = details.get('unit') if kind == 'npc' else None
            calls = details.get('dependencies', {})
            replay.install_calls(gaps.context_calls(calls, sample.get('context')), unit)
            info = gaps.clean(details.get('processingInfo', {}).get('values', {}).get(1))
            rows, error, name = replay.run(kind, entity_id, data, target, info,
                                           gaps.captured_visible_rows(details), unit)
            result.update(status='error' if error else 'incomplete' if rows else 'passed',
                          rows=rows, error=error)
            if not name:
                result.update(status='missing_catalog', missing=['Owned target entity name'])
    return {'source': capture['source'], 'target': target, 'total': len(results),
            'counts': dict(Counter(row['status'] for row in results)), 'observations': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = audit(restore(json.loads(args.capture.read_text())))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'total': result['total'], 'counts': result['counts']}))


if __name__ == '__main__':
    main()
