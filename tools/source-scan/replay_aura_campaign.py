#!/usr/bin/env python3
"""Replay every automatic or hovered aura sample with its own captured instance context."""
import argparse
from collections import Counter
import json
from pathlib import Path

from audit_tooltip_hovers import restore
import report_tooltip_gaps as gaps


def first(response):
    if response and response.get('status') == 'ok':
        return (response.get('values') or {}).get(1)


def replay_capture(capture, target='frFR'):
    results = []
    for run in capture['runs']:
        locale = first(run['locale'])
        replay = gaps.Replay(locale, run['globals'], tooltip_types=run['tooltipTypes'])
        for sample in run['samples']:
            details = sample['details']
            result = {'run': run['run'], 'sample': sample['sample'], 'kind': sample['kind']}
            results.append(result)
            if sample['kind'] == 'aura':
                aura, indexed = first(details.get('byInstance')), first(details.get('aura'))
                data = first(details.get('tooltip'))
                arguments = details.get('tooltipArguments') or {}
                unit, instance = arguments.get(1), arguments.get(2)
                if (not isinstance(aura, dict) or not isinstance(indexed, dict)
                    or type(aura.get('spellId')) is not int or aura['spellId'] <= 0
                    or aura.get('spellId') != indexed.get('spellId')
                    or aura.get('auraInstanceID') != indexed.get('auraInstanceID')
                    or type(instance) is not int or instance != aura.get('auraInstanceID')
                    or unit != details.get('unit') or not isinstance(unit, str)
                    or details.get('tooltipGetter') != 'C_TooltipInfo.GetUnitAuraByAuraInstanceID'
                    or not isinstance(data, dict)):
                    result.update(status='missing_context', reason='Missing or inconsistent captured aura instance')
                    continue
                entity = aura['spellId']
                key = replay.fixture.Key(unit.encode(), instance).decode()
                calls = {'C_UnitAuras.GetAuraDataByAuraInstanceID': {key: details['byInstance']}}
                if isinstance(details.get('unitSex'), dict):
                    calls['UnitSex'] = {replay.fixture.Key(unit.encode()).decode(): details['unitSex']}
                # This descriptor records the API call made by the collector. It does not
                # claim a captured UI frame, and does not fabricate any API return or native text.
                processing = {'getterName': details['tooltipGetter'].rsplit('.', 1)[1],
                              'getterArgs': gaps.clean(arguments)}
                visible = None
            elif sample['kind'] == 'hover' and details.get('dataType') == 'UnitAura':
                entity, data = details.get('entityID'), details.get('data')
                calls = details.get('dependencies', {})
                processing = gaps.clean(first(details.get('processingInfo')))
                visible = gaps.captured_visible_rows(details)
            else:
                result.update(status='unsupported', reason='Not an aura sample')
                continue
            if type(entity) is not int or not isinstance(data, dict) or not data.get('lines'):
                result.update(status='missing_context', reason='No readable captured spell owner or tooltip rows')
                continue
            replay.install_calls(gaps.context_calls(calls, sample.get('context')))
            rows, error, name = replay.run('spell', entity, gaps.clean(data), target, processing, visible)
            rendered = [(row[b'left'] or b'').decode()
                        for row in replay.lua.globals().ReplayLastRendered.values()]
            result.update(id=entity, status='error' if error else 'incomplete' if rows else 'passed',
                          rows=rows, error=error, rendered=rendered)
            if not name:
                result.update(status='missing_catalog')
    return {'source': capture['source'], 'target': target, 'total': len(results),
            'counts': dict(Counter(row['status'] for row in results)), 'observations': results}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--target', default='frFR')
    args = parser.parse_args()
    result = replay_capture(restore(json.loads(args.capture.read_text())), args.target)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'total': result['total'], 'counts': result['counts']}))


if __name__ == '__main__':
    main()
