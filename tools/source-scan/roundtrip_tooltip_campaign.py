#!/usr/bin/env python3
"""Generate explicitly derived reverse cases from a bounded native spell capture."""
import argparse
from collections import Counter
import copy
from decimal import Decimal
import json
from pathlib import Path
import re

from audit_tooltip_hovers import restore
import report_tooltip_gaps as gaps


def rendered_rows(replay):
    return [{side: row[side.encode()].decode() if row[side.encode()] is not None else None
             for side in ('left', 'right')}
            for row in replay.lua.globals().ReplayLastRendered.values()]


def normalized_rows(rows):
    def normalize(value):
        return re.sub(r'\s+', ' ', (value or '').replace('’', "'")).strip()
    return [(normalize(row.get('left')), normalize(row.get('right'))) for row in rows]


def quantities(rows, decimal, grouping, magnitudes=None):
    values = []
    for row in rows:
        # Preserve the distinction between nonbreaking number grouping and spaces
        # separating independent quantities before normalizing other whitespace.
        left, right = (re.sub(r'(?<=\d)[\u00a0\u202f](?=\d{3}(?:\D|$))', '', row.get(side) or '')
                       for side in ('left', 'right'))
        left, right = (re.sub(r'\s+', ' ', text) for text in (left, right))
        text = left + ' ' + right
        # Texture dimensions, atlas coordinates and hyperlink IDs are metadata,
        # not displayed quantities. Keep the link's visible label only.
        text = re.sub(r'\|T.*?\|t|\|A.*?\|a|\|H.*?\|h|\|[cC][0-9a-fA-F]{8}|\|cn[A-Za-z0-9_]+:|\|[rRh]', '', text)
        text = re.sub(r'\|[47]([^;]+);', lambda match: match[1].split(':')[0], text)
        # Only remove valid grouping boundaries, never arbitrary punctuation in a number.
        if grouping:
            grouping = re.sub(r'\s+', ' ', grouping)
            text = re.sub(r'(?<=\d)' + re.escape(grouping) + r'(?=\d{3}(?:\D|$))', '', text)
        if decimal != '.':
            text = text.replace(decimal, '.')
        for label, exponent in (magnitudes or {}).items():
            text = re.sub(r'([+-]?\d+(?:\.\d+)?) ' + re.escape(label) + r'(?: de)?(?=\W|$)',
                          lambda match: format(Decimal(match[1]).scaleb(exponent), 'f'), text)
        numbers = []
        for literal in re.findall(r'(?<!\d)[+-]?\d+(?:\.\d+)?', text):
            number = Decimal(literal)
            canonical = format(number, 'f')
            if '.' in canonical:
                canonical = canonical.rstrip('0').rstrip('.')
            numbers.append('0' if number == 0 else canonical)
        if numbers:
            values.append(numbers)
    return values


def roundtrip(capture, run_index, spell_ids, targets=None):
    run = next(run for run in capture['runs'] if run['run'] == run_index)
    sample = next(sample for sample in run['samples'] if sample['kind'] == 'api')
    details = sample['details']
    locale = capture['source']['locale']
    globals_ = {key: value for key, value in capture['globals'][details['globalsRef']].items() if value != '<nil>'}
    calls = gaps.context_calls(details['calls'], sample.get('context'))
    native = gaps.Replay(locale, globals_, calls, run['tooltipTypes'])
    targets = targets or native.targets()
    reverse, derived_globals = {}, {}
    for target in targets:
        replay = gaps.Replay(target, {}, calls, run['tooltipTypes'])
        labels = {}
        for key in ('DECIMAL_SEPERATOR', 'LARGE_NUMBER_SEPERATOR'):
            value = replay.lua.globals().ReplayAddon.GetClientLabel(
                replay.lua.globals().ReplayAddon, key.encode(), target.encode())
            if value is not None:
                replay.lua.globals()[key.encode()] = value
                labels[key] = value.decode()
        reverse[target], derived_globals[target] = replay, labels
    decimal = native.lua.globals().ReplayAddon.GetClientLabel(
        native.lua.globals().ReplayAddon, b'DECIMAL_SEPERATOR', locale.encode()).decode()
    grouping = native.lua.globals().ReplayAddon.GetClientLabel(
        native.lua.globals().ReplayAddon, b'LARGE_NUMBER_SEPERATOR', locale.encode()).decode()
    results = []
    for entity_id in spell_ids:
        response = details['calls'][gaps.APIS['spell']][str(entity_id)]
        if response.get('status') != 'ok':
            raise ValueError(f'No readable native capture for spell {entity_id}')
        data = gaps.clean(response['values'][1])
        if data.get('type') != run['tooltipTypes']['Spell'] or data.get('id') != entity_id:
            raise ValueError('A reverse spell case requires a captured spell owner')
        original = [{'left': row.get('leftText'), 'right': row.get('rightText')} for row in data['lines']]
        for target in targets:
            result = {'id': entity_id, 'source': locale, 'target': target,
                      'origin': 'derived-from-native-capture', 'native': original}
            results.append(result)
            rows, error, _ = native.run('spell', entity_id, data, target)
            if rows or error:
                result.update(status='forward_failed', rows=rows, error=error)
                continue
            translated = rendered_rows(native)
            result['translated'] = translated
            if len(translated) != len(data['lines']):
                result.update(status='unsupported_layout')
                continue
            derived = copy.deepcopy(data)
            for row, text in zip(derived['lines'], translated):
                for field, side in (('leftText', 'left'), ('rightText', 'right')):
                    if text[side] is None:
                        row.pop(field, None)
                    else:
                        row[field] = text[side]
            result['derivedData'] = derived
            rows, error, _ = reverse[target].run('spell', entity_id, derived, locale)
            returned = rendered_rows(reverse[target])
            result['returned'] = returned
            if rows or error:
                result.update(status='reverse_failed', rows=rows, error=error)
            elif quantities(original, decimal, grouping) != quantities(returned, decimal, grouping):
                result.update(status='value_difference')
            else:
                result.update(status='passed' if normalized_rows(original) == normalized_rows(returned)
                              else 'text_difference_values_preserved')
    return {'sourceCapture': capture['source'], 'sourceRun': run_index,
            'scope': {'nativeCases': len(spell_ids), 'targets': targets},
            'derivedLocaleContext': {'origin': 'owned-catalog', 'labels': derived_globals},
            'counts': dict(Counter(row['status'] for row in results)), 'cases': results,
            'limitation': 'Reverse inputs are FRS output, not native target-client captures. '
                          'Preserved quantities and successful translation do not prove linguistic correctness.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--run', required=True, type=int)
    parser.add_argument('--spells', nargs='+', required=True, type=int)
    parser.add_argument('--targets', nargs='+')
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    result = roundtrip(restore(json.loads(args.capture.read_text())), args.run, args.spells, args.targets)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(result['counts']))


if __name__ == '__main__':
    main()
