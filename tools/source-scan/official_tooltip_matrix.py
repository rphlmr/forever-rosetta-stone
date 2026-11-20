#!/usr/bin/env python3
"""Audit native tooltip fixtures and all official-locale directions using labelled derived inputs."""
import argparse
from collections import Counter, defaultdict
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
import time

from audit_tooltip_hovers import restore
import report_tooltip_gaps as gaps
from derived_tooltip_rows import derive
from replay_aura_campaign import first
from roundtrip_tooltip_campaign import normalized_rows, quantities, rendered_rows

sys.path.insert(0, str(gaps.ROOT))
from tools.catalogs.official_text import OFFICIAL_LOCALES


def visible(rows):
    return [{'left': {'status': 'ok', 'values': {1: row.get('leftText', '')}},
             'right': {'status': 'ok', 'values': {1: row.get('rightText', '')}}}
            for row in gaps.sequence(rows) or []]


def renderer_calls(calls, context):
    names = ('GetBindLocation', 'UnitSex', 'UnitFactionGroup', 'UnitLevel',
             'C_TradeSkillUI.GetRecipeSchematic', 'C_UnitAuras.GetAuraDataByIndex',
             'C_UnitAuras.GetAuraDataByAuraInstanceID')
    return {key: value for key, value in gaps.context_calls(calls, context).items() if key in names}


def observations(directory):
    """Keep provenance for every observation, including unavailable inputs and repeated surfaces."""
    directory = directory.resolve()
    for path in sorted(directory.glob('*.json')):
        payload = path.read_bytes()
        capture = restore(json.loads(payload))
        locale = capture.get('source', {}).get('locale')
        if locale not in OFFICIAL_LOCALES:
            continue
        source = {'fixture': str(path.relative_to(gaps.ROOT)), 'sha256': hashlib.sha256(payload).hexdigest()}
        if 'runs' not in capture:
            if not isinstance(capture.get('data'), dict):
                continue
            data = capture['data']
            kind = {0: 'item', 1: 'spell', 2: 'npc', 7: 'aura'}.get(data.get('type'))
            if kind:
                entity = data.get('id')
                if kind == 'npc':
                    match = re.match(r'^(Creature|Vehicle)-[^-]+-[^-]+-[^-]+-[^-]+-(\d+)-', data.get('guid', ''))
                    entity = int(match[2]) if match else None
                    if data.get('guid', '').startswith('Player-'):
                        kind, entity = 'player', data['guid']
                yield dict(source=source, locale=locale, kind=kind, id=entity, data=data,
                           globals={}, calls={}, processing=capture.get('processingInfo'),
                           visible=visible(capture.get('visible', {})) or None, unit=capture.get('unit'),
                           types=capture.get('enumDefinitions', {}).get('dataTypes'))
            continue
        for run in capture['runs']:
            for sample in run['samples']:
                details = sample['details']
                origin = dict(source, run=run['run'], sample=sample['sample'], sampleKind=sample['kind'])
                labels = (capture.get('globals', {}).get(details.get('globalsRef'), {})
                          if 'globalsRef' in details else run.get('globals', {}))
                base = dict(source=origin, locale=locale, globals=labels, unit=None, types=run.get('tooltipTypes'))
                calls = renderer_calls(details.get('calls', details.get('dependencies', {})), sample.get('context'))
                if sample['kind'] == 'api':
                    for entry in gaps.api_observations(details['calls'], run.get('tooltipTypes')):
                        yield dict(base, kind=entry['kind'], id=entry['id'], data=entry['data'], calls=calls,
                                   processing=entry['processingInfo']['values'][1], visible=None)
                elif sample['kind'] == 'hover':
                    data = details['data']
                    kind = {0: 'item', 1: 'spell', 2: 'npc', 7: 'aura'}.get(data.get('type'), 'unsupported')
                    entity = details.get('entityID', data.get('id'))
                    if kind == 'npc':
                        match = re.match(r'^(Creature|Vehicle)-[^-]+-[^-]+-[^-]+-[^-]+-(\d+)-', data.get('guid', ''))
                        entity = int(match[2]) if match else None
                        if data.get('guid', '').startswith('Player-'):
                            kind, entity = 'player', data['guid']
                    yield dict(base, kind=kind, id=entity, data=data, calls=calls,
                               processing=first(details.get('processingInfo')), visible=gaps.captured_visible_rows(details),
                               unit=details.get('unit'))
                elif sample['kind'] == 'aura':
                    aura = first(details.get('byInstance'))
                    data = first(details.get('tooltip'))
                    args = details.get('tooltipArguments', {})
                    if not isinstance(aura, dict) or not isinstance(data, dict) or args.get(2) != aura.get('auraInstanceID'):
                        yield dict(base, kind='aura', id=None, unavailable='Missing or inconsistent captured aura instance')
                        continue
                    # Unit tokens are the collector's actual ASCII WoW unit arguments.
                    key = json.dumps(args[1], ensure_ascii=False) + ', ' + str(args[2])
                    calls['C_UnitAuras.GetAuraDataByAuraInstanceID'] = {key: details['byInstance']}
                    if isinstance(details.get('unitSex'), dict):
                        calls['UnitSex'] = {json.dumps(args[1], ensure_ascii=False): details['unitSex']}
                    yield dict(base, kind='aura', id=aura['spellId'], data=data, calls=calls,
                               processing={'getterName': details['tooltipGetter'].rsplit('.', 1)[1], 'getterArgs': args}, visible=None)


def stable(value):
    if isinstance(value, dict):
        return {str(key): stable(child) for key, child in sorted(value.items(), key=lambda pair: str(pair[0]))
                if key not in ('dataInstanceID', 'leftColor', 'rightColor')}
    if isinstance(value, list):
        return [stable(child) for child in value]
    return value


def fingerprint(observation):
    data = observation.get('data', {})
    if observation['kind'] not in ('npc', 'player') and 'guid' in data:
        data = {key: value for key, value in data.items() if key != 'guid'}
    calls = observation.get('calls', {})
    state = {key: value for key, value in calls.items() if not key.startswith('C_TradeSkillUI.')}
    schematic = calls.get('C_TradeSkillUI.GetRecipeSchematic', {}).get(f"{observation['id']}, false")
    state['schematic'] = schematic
    info = observation.get('processing') or {}
    value = {'locale': observation['locale'], 'kind': observation['kind'], 'id': observation['id'],
             'data': data, 'visible': observation.get('visible'), 'calls': state,
             'getter': info.get('getterName'), 'arguments': info.get('getterArgs'), 'unit': observation.get('unit')}
    return hashlib.sha256(json.dumps(stable(value), ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def derived_context(replay, observation, locale):
    """Only localized API labels change, through the same captured IDs' owned records."""
    calls = {key: value for key, value in observation['calls'].items() if not key.startswith('C_UnitAuras.')}
    if 'GetBindLocation' in calls:
        calls['GetBindLocation'] = copy.deepcopy(calls['GetBindLocation'])
        for response in calls['GetBindLocation'].values():
            values = response.get('values', {})
            if response.get('status') == 'ok' and isinstance(values.get(1), str):
                translated = replay.database.TranslateLocationLabel(replay.database, values[1].encode(),
                    observation['locale'].encode(), locale.encode())
                if translated:
                    values[1] = translated.decode()
    for api, responses in observation['calls'].items():
        if api.startswith('C_UnitAuras.'):
            calls[api] = copy.deepcopy(responses)
            for response in calls[api].values():
                aura = first(response)
                if isinstance(aura, dict) and type(aura.get('spellId')) is int and 'name' in aura:
                    name = replay.database.GetSpellName(replay.database, aura['spellId'], locale.encode())
                    if name:
                        aura['name'] = name.decode()
    unit = copy.deepcopy(observation.get('unit'))
    if unit:
        for api, getter, index in [('UnitCreatureType', replay.database.GetCreatureTypeName, 2),
                                   ('UnitClass', replay.database.GetClassName, 3)]:
            response = unit.get('apis', {}).get(api)
            values = (response or {}).get('values', {})
            if type(values.get(index)) is int:
                value = getter(replay.database, values[index], locale.encode())
                if value:
                    values[1] = value.decode()
        race = unit.get('apis', {}).get('UnitRace', {}).get('values', {})
        sex = unit.get('apis', {}).get('UnitSex', {}).get('values', {}).get(1)
        if isinstance(race.get(1), str) and type(race.get(3)) is int:
            addon = replay.lua.globals().ReplayAddon
            translated = addon.TranslateUnitRaceName(addon, race[3], race[1].encode(),
                observation['locale'].encode(), locale.encode(), sex)
            if translated:
                race[1] = translated.decode()
        corpse = replay.lua.globals().ReplayAddon.GetClientLabel(replay.lua.globals().ReplayAddon, b'CORPSE', locale.encode())
        if corpse:
            unit['corpseLabel'] = corpse.decode()
    return calls, unit


def cache_catalog(replay, labels=None):
    # A matrix uses the same generated packs in every VM. Share only scalar text
    # and ID pairs across VMs; keep all Lua tables inside their owning runtime.
    if labels is None:
        labels = {}
    lookup_label = replay.database.GetGlobalStringByKey
    local_table = replay.lua.table_from

    def label(database, key, locale):
        pair = (key, locale)
        if pair not in labels:
            labels[pair] = lookup_label(database, key, locale) or (None, None)
        return local_table(labels[pair])

    # The snapshot's owned catalogs are immutable. Cache their query results only;
    # captured client APIs and renderer behaviour keep their real implementations.
    replay.lua.execute(b'''
local database = ForeverRosettaStoneDB
local label = ...
local labels = {}
database.GetGlobalStringByKey = function(self, key, locale)
    if type(key) ~= "string" or type(locale) ~= "string" then return end
    local byKey = labels[locale]
    if not byKey then byKey = {}; labels[locale] = byKey end
    local pair = byKey[key]
    if not pair then
        pair = label(self, key, locale)
        byKey[key] = pair
    end
    if pair[2] then return pair[1], pair[2] end
end
for _, key in ipairs({"GetSpellDetails", "GetItemDetails", "GetSpellRules", "GetItemRules",
    "GetSpellName", "GetItemName", "GetNpcName", "GetNpcSubName", "GetNpcFactionID", "GetQuest",
    "GetGlobalStringKeysByText", "GetHolidayName", "GetItemLimitCategoryName",
    "GetFactionName", "GetAreaName", "GetClassName", "GetCreatureTypeName",
    "GetShapeshiftFormName", "GetTotemCategoryName", "GetLockTypeName", "GetItemSubclassName"}) do
    local original, cache = database[key], {}
    if original then
        database[key] = function(self, id, locale)
            local lookup = tostring(id) .. "\\001" .. tostring(locale)
            if cache[lookup] then return cache[lookup].value end
            local value = original(self, id, locale)
            cache[lookup] = {value = value}
            return value
        end
    end
end
local original, cache = ReplayAddon.GetClientLabel, {}
ReplayAddon.GetClientLabel = function(self, key, locale)
    local lookup = key .. "\\001" .. locale
    if cache[lookup] then return cache[lookup].value end
    local value = original(self, key, locale)
    cache[lookup] = {value = value}
    return value
end
''', label)


def read_rendered(replay):
    try:
        return rendered_rows(replay), None
    except UnicodeDecodeError as error:
        examples = []
        for row in replay.lua.globals().ReplayLastRendered.values():
            for side in (b'left', b'right'):
                value = row[side]
                if isinstance(value, bytes):
                    try:
                        value.decode()
                    except UnicodeDecodeError:
                        examples.append(value.hex())
        return None, f'Invalid UTF-8 renderer output: {error}; bytes={examples[:2]}'


def copied_rows(value):
    if isinstance(value, bytes):
        return value.decode()
    if hasattr(value, 'items'):
        return gaps.clean({copied_rows(key): copied_rows(child) for key, child in value.items()})
    return value


def run(directory, output, limit=None, focus_locale=None, case_keys=None, locales=None):
    return run_observations(observations(directory), output, limit, focus_locale, case_keys, locales)


def run_observations(captures, output, limit=None, focus_locale=None, case_keys=None, locales=None):
    started = time.monotonic()
    locales = sorted(set(locales) if locales is not None else OFFICIAL_LOCALES)
    if len(locales) < 2 or not set(locales) <= OFFICIAL_LOCALES:
        raise ValueError('Select at least two official locales')
    if focus_locale is not None and focus_locale not in locales:
        raise ValueError('The focused locale must belong to the selected official locales')
    cases, native_count, inventories = {}, 0, Counter()
    for observation in captures:
        native_count += 1
        inventories[observation['locale']] += 1
        key = fingerprint(observation)
        if key in cases:
            cases[key]['sources'].append(observation['source'])
        else:
            cases[key] = dict(observation, sources=[observation['source']])
    if case_keys is not None and not set(case_keys).issubset(cases):
        raise ValueError('Requested case fingerprints are absent from the native corpus')
    selected = [(key, observation) for key, observation in cases.items() if case_keys is None or key in case_keys]
    if limit:
        selected = selected[:limit]
    native_replays, reverse, label_keys = {}, {}, {}
    catalog_labels = {}
    for locale in locales:
        replay = gaps.Replay(locale, {})
        cache_catalog(replay, catalog_labels)
        for key in ('DECIMAL_SEPERATOR', 'LARGE_NUMBER_SEPERATOR'):
            value = replay.lua.globals().ReplayAddon.GetClientLabel(replay.lua.globals().ReplayAddon, key.encode(), locale.encode())
            if value is not None:
                replay.lua.globals()[key.encode()] = value
        reverse[locale] = replay
    counts, native_status, by_direction, groups, outcomes = Counter(), Counter(), defaultdict(Counter), {}, []
    by_path = defaultdict(Counter)
    failures = []

    def record(observation, source, target, status, rows=None, error=None, before=None, after=None, evidence=None,
               generation=None):
        if source not in locales or target not in locales:
            return
        if focus_locale is not None and focus_locale not in (source, target):
            return
        counts[status] += 1
        by_direction[source + '>' + target][status] += 1
        path = ('native_to_target' if source == observation['locale'] else
                'return_to_native' if target == observation['locale'] else 'cross_target')
        by_path[path][status] += 1
        outcome['byPath'].setdefault(path, Counter())[status] += 1
        if status not in ('passed', 'text_difference_values_preserved'):
            event = {'case': outcome['key'], 'source': source, 'target': target,
                     'status': status, 'kind': observation['kind'], 'id': observation['id'],
                     'originLocale': observation['locale'], 'path': path,
                     'reference': observation['sources'][0]}
            for field, value in [('rows', rows), ('error', error), ('before', before), ('after', after),
                                 ('evidence', evidence), ('generationProvenance', generation)]:
                if value is not None:
                    event[field] = value
            failures.append(event)
            pattern = tuple((row.get('reason'), row.get('lineType'), gaps.pattern(row.get('text'))) for row in rows or [])
            key = (source, target, status, observation['kind'], pattern, error)
            group = groups.setdefault(key, {'source': source, 'target': target, 'status': status,
                'kind': observation['kind'], 'count': 0, 'exampleIDs': [], 'rows': rows, 'error': error,
                'reference': observation['sources'][0]})
            group['count'] += 1
            if observation['id'] not in group['exampleIDs'] and len(group['exampleIDs']) < 8:
                group['exampleIDs'].append(observation['id'])
            if before is not None:
                group.setdefault('exampleValues', {'before': before, 'after': after})

    for number, (key, observation) in enumerate(selected, 1):
        if number % 25 == 1:
            print(json.dumps({'case': number, 'total': len(selected), 'seconds': round(time.monotonic()-started, 1), 'counts': dict(counts)}), flush=True)
        locale, kind, entity = observation['locale'], observation['kind'], observation['id']
        outcome = {'key': key, 'locale': locale, 'kind': kind, 'id': entity, 'sources': observation['sources'], 'byPath': {}}
        outcomes.append(outcome)
        if entity is None or 'data' not in observation:
            status = 'not_applicable' if kind == 'npc' else 'missing_native_context'
            outcome['nativeStatus'] = status; native_status[status] += 1; continue
        if kind == 'aura' and not any(name.startswith('C_UnitAuras.') for name in observation['calls']):
            outcome['nativeStatus'] = 'missing_native_context'; native_status['missing_native_context'] += 1; continue
        if kind == 'unsupported':
            outcome['nativeStatus'] = 'unsupported'; native_status['unsupported'] += 1; continue
        data = gaps.clean(observation['data'])
        processing = gaps.clean(observation.get('processing'))
        if any('Récupération des informations' in row.get('leftText', '') or 'Retrieving item information' in row.get('leftText', '')
               for row in data.get('lines', [])):
            outcome['nativeStatus'] = 'loading'; native_status['loading'] += 1; continue
        label_identity = id(observation['globals'])
        if label_identity not in label_keys:
            label_keys[label_identity] = hashlib.sha256(json.dumps(stable(observation['globals']), ensure_ascii=False).encode()).hexdigest()
        label_key = label_keys[label_identity]
        replay_key = (locale, label_key)
        if replay_key not in native_replays:
            labels = {key: value for key, value in observation['globals'].items() if value != '<nil>'}
            native_replays[replay_key] = gaps.Replay(locale, labels, tooltip_types=observation.get('types'))
            cache_catalog(native_replays[replay_key], catalog_labels)
        native = native_replays[replay_key]
        native.install_calls(observation['calls'], observation.get('unit'))
        input_rows = [{'left': row.get('leftText'), 'right': row.get('rightText')} for row in data['lines']]
        # Structured price rows can have no text at all. Canonicalize the native
        # layout through the same renderer before comparing displayed quantities;
        # the original captured data stays unchanged and remains the source input.
        _, baseline_error, _ = native.run('spell' if kind == 'aura' else kind, entity, data, locale,
            processing, observation.get('visible'), observation.get('unit'))
        if not baseline_error:
            baseline, encoding_error = read_rendered(native)
            if baseline is not None:
                input_rows = baseline
        states = {locale: {'data': data, 'rows': input_rows, 'visible': observation.get('visible')}}
        generation = {}
        outcome['nativeStatus'] = 'replayed'; native_status['replayed'] += 1
        render_kind = 'spell' if kind == 'aura' else kind
        for target in locales:
            if target == locale:
                continue
            rows, error, name = native.run(render_kind, entity, data, target, processing, observation.get('visible'), observation.get('unit'))
            if rows or error or not name:
                context = gaps.missing_player_context(native, render_kind, entity, data, observation['calls'], target, rows) if not error else []
                status = ('native_error' if error else 'missing_catalog' if not name
                          else 'missing_captured_player_context' if context else 'native_incomplete')
                generation[target] = {'reason': 'native_translation_failed', 'status': status}
                record(observation, locale, target, status, rows, error, evidence=context or None)
                continue
            translated, encoding_error = read_rendered(native)
            if encoding_error:
                record(observation, locale, target, 'native_invalid_utf8', error=encoding_error)
                continue
            record(observation, locale, target, 'passed')
            bindings = copied_rows(native.lua.globals().ReplayOutputBindings)
            source_data = data
            if kind in ('npc', 'player'):
                source_data = dict(data, lines=copied_rows(native.lua.globals().ReplayLastSourceRows))
                states[locale] = {'data': source_data,
                    'rows': input_rows,
                    'visible': observation.get('visible')}
            if kind in ('npc', 'player'):
                if len(translated) != len(source_data['lines']):
                    generation[target] = {'reason': 'unsupported_unit_row_alignment'}
                    continue
                derived = copy.deepcopy(source_data)
                for line, text in zip(derived['lines'], translated):
                    for field, side in [('leftText', 'left'), ('rightText', 'right')]:
                        if text[side] is None: line.pop(field, None)
                        else: line[field] = text[side]
            else:
                suppressions = copied_rows(native.lua.globals().ReplaySuppressions)
                derived, issue = derive(source_data, translated, bindings, suppressions,
                    visible_surface=(processing or {}).get('getterName') in ('GetTraitEntry', 'GetTalent')
                        and observation.get('visible') is not None)
                if issue:
                    generation[target] = dict(issue, sourceRows=len(source_data['lines']), translatedRows=len(translated))
                    continue
            derived_visible = [{'left': {'status': 'ok', 'values': {1: row['left'] or '<nil>'}},
                                'right': {'status': 'ok', 'values': {1: row['right'] or '<nil>'}}}
                               for row in translated]
            provenance = []
            for binding, row in zip(bindings, translated):
                original = binding.get('originalIndex')
                if isinstance(original, int) and 0 < original <= len(data['lines']):
                    provenance.append({'sourceRow': original, 'nativeRow': data['lines'][original - 1],
                                       'generatedRow': row})
            states[target] = {'data': derived, 'rows': translated, 'visible': derived_visible,
                'generation': {'decoderProofs': copied_rows(native.lua.globals().ReplayDecoderProofs),
                               'rowProvenance': provenance}}
        outcome['generatedLocales'] = sorted(set(states) - {locale})
        outcome['generationGaps'] = generation
        expected_rows = {}
        for source in locales:
            if source == locale:
                continue
            if source not in states:
                for target in locales:
                    if target != source:
                        record(observation, source, target, 'blocked_source_generation',
                               evidence=generation.get(source, {'reason': 'source_unavailable'}))
                continue
            replay = reverse[source]
            calls, unit = derived_context(replay, observation, source)
            replay.install_calls(calls, unit)
            for target in locales:
                if target == source:
                    continue
                if focus_locale is not None and focus_locale not in (source, target):
                    continue
                rows, error, name = replay.run(render_kind, entity, states[source]['data'], target,
                    processing, visible=states[source]['visible'], unit=unit)
                if rows or error or not name:
                    context = gaps.missing_player_context(replay, render_kind, entity, states[source]['data'], calls, target, rows) if not error else []
                    record(observation, source, target, 'derived_error' if error else 'missing_catalog' if not name
                           else 'missing_captured_player_context' if context else 'derived_incomplete', rows, error,
                           evidence=context or None,
                           generation=states[source].get('generation') if target == locale else None)
                    continue
                returned, encoding_error = read_rendered(replay)
                if encoding_error:
                    record(observation, source, target, 'derived_invalid_utf8', error=encoding_error)
                    continue
                # Compare with the independently rendered native-to-target direction where
                # available. Differences are candidates for review, not automatically bugs.
                expected = states.get(target)
                if expected:
                    if target not in expected_rows:
                        globals_ = reverse[target].lua.globals()
                        decimal = (globals_.DECIMAL_SEPERATOR or b'.').decode()
                        grouping = (globals_.LARGE_NUMBER_SEPERATOR or b'').decode()
                        expected_rows[target] = (decimal, grouping, quantities(expected['rows'], decimal, grouping),
                                                 normalized_rows(expected['rows']))
                    decimal, grouping, before, normalized = expected_rows[target]
                    after = quantities(returned, decimal, grouping)
                    if before != after:
                        record(observation, source, target, 'numeric_difference', before=before, after=after,
                               evidence={'expected': expected['rows'], 'returned': returned})
                        continue
                    if normalized != normalized_rows(returned):
                        record(observation, source, target, 'text_difference_values_preserved')
                        continue
                record(observation, source, target, 'passed')
    directions = 2 * (len(locales) - 1) if focus_locale else len(locales) * (len(locales) - 1)
    report = {'schemaVersion': 1, 'officialLocales': locales, 'directionsPerCase': directions,
        'focusLocale': focus_locale,
        'selectedCaseKeys': sorted(case_keys) if case_keys is not None else None,
        'nativeObservations': native_count, 'nativeObservationsByLocale': dict(inventories),
        'uniqueNativeCases': len(cases), 'selectedCases': len(selected), 'nativeStatus': dict(native_status),
        'counts': dict(counts), 'byDirection': {key: dict(value) for key, value in sorted(by_direction.items())},
        'byPath': {key: dict(value) for key, value in sorted(by_path.items())},
        'groups': sorted(groups.values(), key=lambda group: -group['count']), 'cases': outcomes, 'failures': failures,
        'elapsedSeconds': round(time.monotonic()-started, 2),
        'limitations': ['Derived inputs are FRS output, not native target-client captures.',
            'Row alignment gaps block generation and never count as passed directions.',
            'Numeric differences require triage for valid unit conversions and token identity.',
            'Roundtrips do not prove linguistic accuracy or correct localization of live place names.']}
    output.mkdir(parents=True, exist_ok=False)
    (output/'report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({key: report[key] for key in ('nativeObservations','uniqueNativeCases','selectedCases','nativeStatus','counts','elapsedSeconds')}), flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, default=gaps.ROOT/'tests/fixtures/tooltip-campaign')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--focus-locale', choices=sorted(OFFICIAL_LOCALES),
                        help='Count only directions involving this locale; render native dependencies as needed')
    parser.add_argument('--case-keys', type=Path, help='JSON list of native case fingerprints to recheck')
    parser.add_argument('--locales', nargs='+', choices=sorted(OFFICIAL_LOCALES),
                        help='Count selected official-locale directions; retain every native capture as a dependency')
    args = parser.parse_args()
    if not args.output.resolve().is_relative_to((gaps.ROOT/'datasources/imports').resolve()):
        parser.error('Reports belong under datasources/imports/')
    run(args.fixtures, args.output, args.limit, args.focus_locale,
        set(json.loads(args.case_keys.read_text())) if args.case_keys else None, args.locales)


if __name__ == '__main__':
    main()
