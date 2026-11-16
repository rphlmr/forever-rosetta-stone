"""Regression coverage from the user's real tooltips, including appended talent ranks."""
import importlib.util
import copy
import json
import re
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
spec = importlib.util.spec_from_file_location('captured_gap_report', ROOT / 'tools/source-scan/report_tooltip_gaps.py')
gaps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gaps)


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


class CapturedTooltipCampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-frFR.json').read_text()))

    def sample(self, run, sample):
        return next(s for r in self.capture['runs'] if r['run'] == run for s in r['samples'] if s['sample'] == sample)

    def replay(self, sample, target='enUS'):
        details = sample['details']
        globals_ = {k: v for k, v in self.capture['globals'][details['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('frFR', globals_, gaps.context_calls(details.get('dependencies', {}), sample.get('context')))
        info = details.get('processingInfo', {}).get('values', {}).get(1)
        rows, failure, _ = replay.run('item' if details['dataType'] == 'Item' else 'spell', details['entityID'],
            gaps.clean(details['data']), target, gaps.clean(info), gaps.captured_visible_rows(details))
        self.assertIsNone(failure)
        rendered = replay.lua.globals().ReplayLastRendered
        texts = [(r[b'left'] or b'').decode() for r in rendered.values()]
        return replay, rows, texts

    def test_current_and_next_talent_rank_translate_from_the_captured_native_blocks(self):
        sample = self.sample(10, 120)
        replay, rows, texts = self.replay(sample)
        self.assertEqual(rows, [], texts)
        self.assertIn('Increases the duration of your Shadow Word: Pain spell by 3 sec.', texts)
        self.assertIn('Increases the duration of your Shadow Word: Pain spell by 6 sec.', texts)
        self.assertFalse(any('Traduit en anglais' in text for text in texts))

    def test_english_description_on_french_client_uses_the_same_owned_spell(self):
        _, rows, texts = self.replay(self.sample(10, 112))
        self.assertEqual(rows, [], texts)
        self.assertTrue(any('2% increased damage' in text for text in texts))

    def test_real_compound_talent_translates_owned_child_blocks_and_color_only_conditions(self):
        captured = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/talent-1238122-frFR.json').read_text()))
        original = copy.deepcopy(captured)
        visible = [{'left': {'status': 'ok', 'values': {1: row.get('leftText', '')}},
                    'right': {'status': 'ok', 'values': {1: row.get('rightText', '')}}}
                   for row in captured['visible'].values()]
        replay = gaps.Replay('frFR', {})
        missing, error, _ = replay.run('spell', captured['data']['id'], gaps.clean(captured['data']), 'enUS',
                                       captured['processingInfo'], visible)
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        texts = [(row[b'left'] or b'').decode() for row in replay.lua.globals().ReplayLastRendered.values()]
        self.assertIn('Feral Charge (Cat)', texts)
        self.assertIn('Leap behind an enemy.', texts)
        self.assertTrue(any('Requires Bear Form, Dire Bear Form' in text and '4 sec.' in text for text in texts))
        self.assertEqual(captured, original)

    def test_observed_conditional_ranges_colors_precision_and_unlimited_durations(self):
        api = next(r for r in self.capture['runs'] if r['run'] == 8)['samples'][0]
        d = api['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], api.get('context')))
        for entity_id in (7799, 3110, 1302309, 440212, 1226116, 1231654, 400614, 417141, 407988, 1307234,
                          435167, 458481, 458436, 10614, 20177):
            with self.subTest(id=entity_id):
                data = gaps.clean(d['calls']['C_TooltipInfo.GetSpellByID'][str(entity_id)]['values'][1])
                rows, failure, _ = replay.run('spell', entity_id, data, 'enUS')
                self.assertIsNone(failure)
                descriptions = [row for row in rows if row['lineType'] == 'SpellDescription']
                self.assertEqual(descriptions, [])

    def test_every_captured_crafter_row_translates_without_changing_the_player_name(self):
        checked = 0
        for run in self.capture['runs']:
            for sample in run['samples']:
                d = sample['details']
                if sample['kind'] != 'hover' or d.get('dataType') != 'Item':
                    continue
                creator = [re.sub(r'\|c[0-9a-fA-F]{8}|\|r', '', r.get('leftText', ''))
                           for r in d.get('data', {}).get('lines', {}).values()]
                creator = [text for text in creator if text.startswith('<Artisan :')]
                if not creator:
                    continue
                with self.subTest(sample=sample['sample']):
                    checked += 1
                    _, rows, texts = self.replay(sample, 'deDE')
                    self.assertFalse(any('Artisan :' in row['text'] for row in rows), texts)
                    for native in creator:
                        self.assertTrue(any(native.split(': ', 1)[1].rstrip('>') in text for text in texts))
        self.assertGreater(checked, 0)

    def test_captured_forms_embedded_items_container_slots_and_multiline_costs(self):
        api = next(r for r in self.capture['runs'] if r['run'] == 8)['samples'][0]
        d = api['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], api.get('context')))
        selected = {'spell': (1079, 9493, 14903, 407988, 5229, 20253, 20658, 6470, 3855, 1329555, 15633),
                    'item': (12700, 22250, 5441, 277115, 122270, 251723, 280740, 270868)}
        for kind, ids in selected.items():
            for entity_id in ids:
                with self.subTest(kind=kind, id=entity_id):
                    data = gaps.clean(d['calls'][gaps.APIS[kind]][str(entity_id)]['values'][1])
                    rows, failure, _ = replay.run(kind, entity_id, data, 'enUS')
                    self.assertIsNone(failure)
                    self.assertEqual(rows, [])

    def test_actual_recipe_chat_link_preserves_the_created_food_values_and_reagent(self):
        _, rows, texts = self.replay(self.sample(11, 1))
        self.assertEqual(rows, [], texts)
        self.assertTrue(any('Longjaw Mud Snapper' in text for text in texts))
        self.assertTrue(any('Raw Longjaw Mud Snapper' in text for text in texts))
        food = next(text for text in texts if '530' in text)
        for quantity in ('530', '24', '10', '15', '5'):
            self.assertIn(quantity, food)

    def test_recaptured_context_restrictions_inline_references_and_tooltip_surfaces(self):
        sample = self.sample(12, 1)
        d = sample['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], sample.get('context')))
        selected = {'item': {6948, 15200, 211318, 211326, 273878, 276539, 275975, 275979, 21196,
                             4636, 13875, 17324, 17353, 18268, 22165, 22239, 34085, 34086},
                    'spell': {1315212, 436536, 419417, 1314923, 1238122, 407632,
                              1252237, 16987, 19669, 15286, 15487, 15407, 402174, 10060, 401859,
                              3674, 14284, 459619, 1254546, 1303015, 1329, 400589, 459611, 461297, 974,
                              8027, 8030}}
        checked = 0
        for observation in gaps.api_observations(d['calls']):
            kind, entity_id = observation['kind'], observation['id']
            if entity_id not in selected[kind]:
                continue
            with self.subTest(kind=kind, id=entity_id, api=observation['api'], args=observation['arguments']):
                rows, failure, _ = replay.run(kind, entity_id, gaps.clean(observation['data']), 'enUS',
                    gaps.clean(observation['processingInfo']['values'][1]))
                self.assertIsNone(failure)
                self.assertEqual(rows, [])
                if kind == 'spell' and entity_id == 1238122:
                    texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
                    self.assertIn('Feral Charge (Cat)', texts)
                    self.assertIn('Leap behind an enemy.', texts)
                    self.assertTrue(any('4 sec.' in text for text in texts))
                checked += 1
        self.assertGreater(checked, sum(map(len, selected.values())))

    def test_unlearned_talents_omit_purchase_conditions_and_preserve_rank_and_descriptions(self):
        run = next(r for r in self.capture['runs'] if r['run'] == 13)
        retained = 0
        for sample in run['samples']:
            with self.subTest(id=sample['details']['entityID']):
                d = sample['details']
                native = copy.deepcopy(d['visible'])
                _, rows, texts = self.replay(sample)
                self.assertEqual(rows, [], texts)
                self.assertIn('Rank 0/5', texts)
                for index, row in d['previousRenderedTranslation'].items():
                    expected = row.get('leftText', '')
                    if index <= 5 and expected.strip():
                        self.assertIn(expected, texts)
                for source in d['retainedNativeRows']:
                    retained += 1
                    self.assertNotIn(source['row']['leftText'], texts)
                self.assertEqual(d['visible'], native)
        self.assertEqual(retained, 2)

    def test_english_preceding_talent_condition_is_omitted_from_french_translation(self):
        screenshot = json.loads((ROOT / 'tests/fixtures/tooltip-campaign/preceding-talents-screenshot-enUS.json').read_text())
        sample = next(s for r in self.capture['runs'] if r['run'] == 13 for s in r['samples']
                      if s['details']['entityID'] == 14901)
        details = sample['details']
        # Use recorded English output for the talent body and the screenshot's actual
        # prerequisite rows. The screenshot has no structured spell identity of its own.
        english_rows = [row for index, row in details['previousRenderedTranslation'].items() if index <= 5]
        texts = [row.get('leftText', '') for row in english_rows] + screenshot['nativePurchaseRows']
        visible = [{'left': {'status': 'ok', 'values': {1: text}}} for text in texts]
        before = copy.deepcopy(visible)
        replay = gaps.Replay('enUS', {})
        for key in ('TOOLTIP_TALENT_RANK', 'SPELL_PASSIVE'):
            label = replay.database.GetGlobalStringByKey(replay.database, key.encode(), b'enUS')
            replay.lua.globals()[key.encode()] = label[0] if isinstance(label, tuple) else label
        info = gaps.clean(details['processingInfo']['values'][1])
        rows, failure, _ = replay.run('spell', details['entityID'], gaps.clean(details['data']), 'frFR', info, visible)
        self.assertIsNone(failure)
        self.assertEqual(rows, [])
        translated = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
        self.assertIn('Direction spirituelle', translated)
        self.assertIn('Rang 0/5', translated)
        self.assertTrue(any('5' in text and '1' in text and 'Esprit' in text for text in translated))
        for text in screenshot['nativePurchaseRows'] + screenshot['translatedPurchaseRowsBefore']:
            self.assertNotIn(text, translated)
        self.assertEqual(visible, before)

    def test_mount_screenshot_riding_gate_stays_native_with_owned_localized_labels(self):
        # Screenshot text, with the mount's identity supplied by its owned catalog record.
        variants = ('typed', 'untyped', 'leading_blank')
        for source, target, variant in ((s, t, v) for s, t in (('enUS', 'frFR'), ('frFR', 'enUS')) for v in variants):
            with self.subTest(source=source, target=target, variant=variant):
                replay = gaps.Replay(source, {})
                db = replay.database
                name = db.GetSpellName(db, 1309208, source.encode())
                description = db.GetSpellDetails(db, 1309208, source.encode())[b'description']
                label = db.GetGlobalStringByKey(db, b'SPELL_FAILED_JOURNEYMAN_RIDING_REQUIREMENT', source.encode())
                gate = label[0] if isinstance(label, tuple) else label
                self.assertTrue(gate, 'The riding requirement must exist in the shipping database')
                types = replay.lua.globals().Enum[b'TooltipDataLineType']
                lines = [{'type': types[b'SpellName'], 'leftText': name.decode()},
                         {'type': types[b'SpellDescription'], 'leftText': description.decode()},
                         {'leftText': gate.decode()}]
                if variant != 'typed':
                    lines[0].pop('type')
                if variant == 'leading_blank':
                    lines.insert(0, {'leftText': ''})
                visible = [{'left': {'status': 'ok', 'values': {1: row['leftText']}}} for row in lines]
                before = copy.deepcopy(visible)
                translated_name = db.GetSpellName(db, 1309208, target.encode())
                ok, failure, _ = replay.render(b'mount', 1309208, translated_name, target.encode(),
                    replay.to_lua({'lines': lines}), None, replay.to_lua(visible))
                self.assertTrue(ok, failure)
                texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
                self.assertEqual(len(texts), 3 if variant == 'leading_blank' else 2, texts)
                if variant == 'leading_blank':
                    self.assertEqual(texts[1], '', 'Native spacing stays intact')
                self.assertEqual(texts[0], translated_name.decode())
                expected = db.GetSpellDetails(db, 1309208, target.encode())[b'description'].decode()
                self.assertEqual(texts[-1], expected)
                self.assertEqual(visible, before)

    def test_captured_campaign_has_no_untranslated_rows(self):
        replay, replay_globals = None, None
        failures, unavailable, native_tokens, unavailable_context, checked = [], [], [], [], 0
        source_locale = self.capture['source']['locale']
        targets = os.environ.get('FRS_CAPTURE_TARGETS', 'frFR' if source_locale == 'enUS' else 'enUS').split(',')
        default_runs = ','.join(str(run['run']) for run in self.capture['runs'])
        selected_runs = set(map(int, os.environ.get('FRS_CAPTURE_RUNS', default_runs).split(',')))
        for run in self.capture['runs']:
            if run['run'] not in selected_runs:
                continue
            for sample in run['samples']:
                details = sample['details']
                if sample['kind'] not in ('api', 'hover'):
                    continue
                globals_ = {k: v for k, v in self.capture['globals'][details['globalsRef']].items() if v != '<nil>'}
                if replay is None or replay_globals != details['globalsRef']:
                    replay = gaps.Replay(source_locale, globals_, tooltip_types=run['tooltipTypes'])
                    replay_globals = details['globalsRef']
                calls = details.get('calls', details.get('dependencies', {}))
                replay.install_calls(gaps.context_calls(calls, sample.get('context')))
                if sample['kind'] == 'api':
                    observations = [(o['kind'], o['id'], o['data'], o['processingInfo']['values'][1], None)
                                    for o in gaps.api_observations(calls, run['tooltipTypes'])]
                else:
                    kind = 'item' if details['dataType'] == 'Item' else 'spell'
                    info = details.get('processingInfo', {}).get('values', {}).get(1)
                    observations = [(kind, details['entityID'], details['data'], info,
                                     gaps.captured_visible_rows(details))]
                for kind, entity_id, data, info, visible in observations:
                    data = gaps.clean(data)
                    marker = globals_.get('RETRIEVING_ITEM_INFO')
                    if marker and any(marker in row.get('leftText', '') for row in data['lines']):
                        unavailable.append((run['run'], entity_id))
                        continue
                    symbols = gaps.native_token_rows(data)
                    if symbols:
                        native_tokens.append({'run': run['run'], 'sample': sample['sample'], 'kind': kind,
                                              'id': entity_id, 'rows': symbols})
                    for target in targets:
                        rows, failure, _ = replay.run(kind, entity_id, data, target, gaps.clean(info), visible)
                        checked += 1
                        if rows or failure:
                            context = gaps.missing_player_context(replay, kind, entity_id, data,
                                gaps.context_calls(calls, sample.get('context')), target, rows) if not failure else []
                            if context:
                                unavailable_context.append({'run': run['run'], 'sample': sample['sample'],
                                    'kind': kind, 'id': entity_id, 'target': target, 'rows': rows,
                                    'status': 'missing_captured_context', 'requiredContext': context})
                                continue
                            failures.append({'run': run['run'], 'sample': sample['sample'], 'kind': kind,
                                'id': entity_id, 'target': target, 'error': failure, 'rows': rows})
        report = {'checked': checked, 'unavailableCapture': unavailable, 'failures': failures,
                  'missingCapturedContext': unavailable_context,
                  'nativeUnresolvedTokens': native_tokens}
        output = os.environ.get('FRS_CAPTURE_REPORT')
        if output:
            Path(output).write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        self.assertEqual(len(failures), 0, f'{len(failures)} incomplete captured renders; first failures: {failures[:4]}')


class EnglishCapturedTooltipCampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-enUS.json').read_text()))

    test_captured_campaign_has_no_untranslated_rows = CapturedTooltipCampaignTests.test_captured_campaign_has_no_untranslated_rows

    def test_real_korean_recipe_preserves_complete_utf8_profession_labels(self):
        sample = self.capture['runs'][0]['samples'][0]
        details = sample['details']
        globals_ = {key: value for key, value in self.capture['globals'][details['globalsRef']].items() if value != '<nil>'}
        replay = gaps.Replay('enUS', globals_, gaps.context_calls(details['calls'], sample.get('context')))
        data = gaps.clean(details['calls'][gaps.APIS['spell']]['19669']['values'][1])
        missing, error, _ = replay.run('spell', 19669, data, 'koKR')
        self.assertIsNone(error)
        self.assertEqual(missing, [])
        texts = [(row[b'left'] or b'').decode() for row in replay.lua.globals().ReplayLastRendered.values()]
        self.assertIn('요구 사항: 대장기술 (250)', texts)

    def test_reported_talents_preserve_values_and_translate_backing_spell_requirements(self):
        d = self.capture['runs'][0]['samples'][0]['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        for entity_id in (408498, 16190, 1322605, 17877, 1310687):
            with self.subTest(id=entity_id):
                observed = restore(json.loads((ROOT / f'tests/fixtures/tooltip-campaign/talent-{entity_id}-enUS.json').read_text()))
                before = copy.deepcopy(observed)
                replay = gaps.Replay('enUS', globals_)
                visible = [{'left': {'status': 'ok', 'values': {1: row.get('leftText', '')}},
                            'right': {'status': 'ok', 'values': {1: row.get('rightText', '')}}}
                           for row in observed['visible'].values()]
                rows, failure, _ = replay.run('spell', entity_id, gaps.clean(observed['data']), 'frFR',
                                              gaps.clean(observed['processingInfo']), visible)
                self.assertIsNone(failure)
                self.assertEqual(rows, [])
                texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
                if entity_id == 408498:
                    self.assertTrue(any('28' in text and '20' in text and '30' in text for text in texts), texts)
                elif entity_id == 16190:
                    self.assertTrue(any('Totem d’eau' in text for text in texts), texts)
                    self.assertFalse(any('Tools:' in text for text in texts), texts)
                elif entity_id == 1322605:
                    self.assertTrue(any('Forme de félin' in text for text in texts), texts)
                    self.assertTrue(any('201' in text and '40' in text for text in texts), texts)
                elif entity_id == 17877:
                    self.assertFalse(any('Soul Shard' in text or 'Reagents:' in text for text in texts), texts)
                else:
                    self.assertTrue(any('Arme à distance' in text for text in texts), texts)
                    self.assertFalse(any('Requires Ranged Weapon' in text for text in texts), texts)
                self.assertEqual(observed, before)

    def test_reported_server_item_uses_owned_classification_and_comparison_labels(self):
        observed = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/pants-286569-enUS.json').read_text()))
        d = self.capture['runs'][0]['samples'][0]['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('enUS', globals_)
        visible = [{'left': {'status': 'ok', 'values': {1: row['leftText']}},
                    'right': {'status': 'ok', 'values': {1: row.get('rightText', '')}}}
                   for row in observed['visible'].values()]
        rows, failure, _ = replay.run('item', observed['data']['id'], gaps.clean(observed['data']), 'frFR',
                                      gaps.clean(observed['processingInfo']), visible)
        self.assertIsNone(failure)
        self.assertEqual(rows, [])
        rendered = list(replay.lua.globals().ReplayLastRendered.values())
        self.assertTrue(any(row[b'right'] == b'Tissu' for row in rendered))
        # The native FR cache supplies this exact name for the same owned item ID.
        self.assertEqual(rendered[0][b'left'], 'Jambières d’oiseau de feu'.encode())
        addon = replay.lua.globals().ReplayAddon
        replay.lua.execute((ROOT / 'ForeverRosettaStone/tooltips/tooltip-comparisons.lua').read_bytes(), b'FRS', addon)
        native = '+17 Fire Damage'  # Visible comparison row in the supplied screenshot.
        translated = addon.TranslateComparisonText(addon, native.encode())
        self.assertEqual(translated, '+17 Dégâts de feu'.encode())
        self.assertIsNone(addon.TranslateComparisonText(addon, b'+17 Unknown damage'))

    def test_reported_lockbox_translates_its_owned_lock_requirement(self):
        observed = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/lockbox-4637-enUS.json').read_text()))
        before = copy.deepcopy(observed)
        d = self.capture['runs'][0]['samples'][0]['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('enUS', globals_)
        visible = [{'left': {'status': 'ok', 'values': {1: row['leftText']}}}
                   for row in observed['visible'].values()]
        rows, failure, _ = replay.run('item', observed['data']['id'], gaps.clean(observed['data']), 'frFR',
                                      gaps.clean(observed['processingInfo']), visible)
        self.assertIsNone(failure)
        self.assertEqual(rows, [])
        texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
        self.assertTrue(any('Crochetage' in text and '175' in text for text in texts), texts)
        self.assertFalse(any('Requires Pick Lock' in text for text in texts), texts)
        self.assertEqual(observed, before)

    def test_unresolved_symbols_in_real_client_rows_are_preserved_verbatim(self):
        sample = self.capture['runs'][0]['samples'][0]
        d = sample['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('enUS', globals_, gaps.context_calls(d['calls'], sample.get('context')))
        token = re.compile(r'\$\{[^}]+\}(?:\.\d+)?|\$<[A-Za-z0-9_]+>|\$(?:\d+)?[A-Za-z_]+[0-9]*')
        for entity_id in (1254546, 1303015, 1329, 400589, 459611, 461297, 974):
            with self.subTest(id=entity_id):
                data = gaps.clean(d['calls'][gaps.APIS['spell']][str(entity_id)]['values'][1])
                native = '\n'.join(row.get('leftText', '') for row in data['lines'])
                rows, failure, _ = replay.run('spell', entity_id, data, 'frFR')
                self.assertIsNone(failure)
                self.assertEqual(rows, [])
                translated = '\n'.join((r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values())
                self.assertTrue(token.findall(native))
                self.assertEqual(sorted(token.findall(translated)), sorted(token.findall(native)))

    def test_reported_recipe_translates_its_owned_created_item_block(self):
        observed = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/recipe-9513-enUS.json').read_text()))
        before = copy.deepcopy(observed)
        sample = self.capture['runs'][0]['samples'][0]
        globals_ = {k: v for k, v in self.capture['globals'][sample['details']['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('enUS', globals_)
        visible = [{'left': {'status': 'ok', 'values': {1: row['leftText']}}}
                   for row in observed['visible'].values()]
        rows, failure, _ = replay.run('spell', observed['data']['id'], gaps.clean(observed['data']), 'frFR',
                                      gaps.clean(observed['processingInfo']), visible)
        self.assertIsNone(failure)
        self.assertEqual(rows, [])
        texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
        self.assertTrue(any('Thé de chardon' in text for text in texts), texts)
        self.assertFalse(any('Thistle Tea' in text or 'Use:' in text or 'Rogue' in text for text in texts), texts)
        self.assertTrue(any('100' in text and '5' in text for text in texts), texts)
        self.assertEqual(observed, before)

        # A corrupt explicit nested owner must not fall back to the recipe's
        # unique catalog output and translate an unrelated embedded block.
        invalid = copy.deepcopy(observed['data'])
        marker = next(row for row in invalid['lines'].values() if row.get('type') == 19)
        marker['tooltipID'] = -1
        rows, failure, _ = replay.run('spell', invalid['id'], gaps.clean(invalid), 'frFR',
                                      gaps.clean(observed['processingInfo']), visible)
        self.assertIsNone(failure)
        self.assertTrue(any(row['lineType'] == 'ItemName' for row in rows), rows)

    def test_captured_ranges_magnitudes_requirements_and_mounts_translate_to_french(self):
        sample = self.capture['runs'][0]['samples'][0]
        d = sample['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('enUS', globals_, gaps.context_calls(d['calls'], sample.get('context')))
        for kind, entity_id in [('spell', 3110), ('spell', 7799), ('spell', 459619),
                                ('spell', 3674), ('spell', 14284), ('item', 12351), ('item', 13086)]:
            with self.subTest(kind=kind, id=entity_id):
                data = gaps.clean(d['calls'][gaps.APIS[kind]][str(entity_id)]['values'][1])
                rows, failure, _ = replay.run(kind, entity_id, data, 'frFR')
                self.assertIsNone(failure)
                self.assertEqual(rows, [])


class LegacyCapturedAPITooltipCampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-frFR-legacy-api.json').read_text()))

    test_captured_campaign_has_no_untranslated_rows = CapturedTooltipCampaignTests.test_captured_campaign_has_no_untranslated_rows

    def test_missing_static_globals_visible_gender_and_bind_location_use_real_evidence(self):
        for run_id, kind, entity_id in ((3, 'spell', 16757), (3, 'item', 1205),
                                       (7, 'spell', 10139), (7, 'spell', 693),
                                       (7, 'spell', 419417), (7, 'item', 6948)):
            with self.subTest(run=run_id, kind=kind, id=entity_id):
                sample = next(r for r in self.capture['runs'] if r['run'] == run_id)['samples'][0]
                d = sample['details']
                globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
                replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], sample.get('context')))
                data = gaps.clean(d['calls'][gaps.APIS[kind]][str(entity_id)]['values'][1])
                original = copy.deepcopy(data)
                rows, failure, _ = replay.run(kind, entity_id, data, 'enUS')
                self.assertIsNone(failure)
                self.assertEqual(rows, [])
                self.assertEqual(data, original)
                if entity_id in (419417, 6948):
                    texts = [(row[b'left'] or b'').decode()
                             for row in replay.lua.globals().ReplayLastRendered.values()]
                    self.assertTrue(any('Goldshire' in text for text in texts), texts)

    def test_gender_neutral_source_without_player_context_stays_incomplete(self):
        sample = next(r for r in self.capture['runs'] if r['run'] == 7)['samples'][0]
        d = sample['details']
        globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
        replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], sample.get('context')))
        data = gaps.clean(d['calls'][gaps.APIS['spell']]['10138']['values'][1])
        rows, failure, _ = replay.run('spell', 10138, data, 'enUS')
        self.assertIsNone(failure)
        self.assertTrue(rows, 'A neutral French phrase cannot determine an English gender branch')

    def test_focus_costs_native_hotfix_and_direct_set_membership_from_captures(self):
        for run_id, kind, entity_id in ((5, 'spell', 1264741), (5, 'spell', 1265843),
                                         (7, 'spell', 16342), (5, 'item', 273930)):
            with self.subTest(run=run_id, kind=kind, id=entity_id):
                sample = next(r for r in self.capture['runs'] if r['run'] == run_id)['samples'][0]
                d = sample['details']
                globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
                replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], sample.get('context')))
                data = gaps.clean(d['calls'][gaps.APIS[kind]][str(entity_id)]['values'][1])
                rows, failure, _ = replay.run(kind, entity_id, data, 'enUS')
                self.assertIsNone(failure)
                self.assertEqual(rows, [])
                texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
                if entity_id == 16342:
                    self.assertTrue(any('33 to 102' in text for text in texts), texts)
                elif kind == 'item':
                    self.assertTrue(any('Grimstitch Armor (0/0)' in text for text in texts), texts)
                    self.assertTrue(any(text.startswith('(2) Set:') for text in texts), texts)

    def test_old_lockbox_and_set_rows_are_covered_by_real_source_relationships(self):
        for run_id, entity_id in ((7, 13918), (5, 16688)):
            with self.subTest(run=run_id, id=entity_id):
                sample = next(r for r in self.capture['runs'] if r['run'] == run_id)['samples'][0]
                d = sample['details']
                globals_ = {k: v for k, v in self.capture['globals'][d['globalsRef']].items() if v != '<nil>'}
                replay = gaps.Replay('frFR', globals_, gaps.context_calls(d['calls'], sample.get('context')))
                data = gaps.clean(d['calls'][gaps.APIS['item']][str(entity_id)]['values'][1])
                rows, failure, _ = replay.run('item', entity_id, data, 'enUS')
                self.assertIsNone(failure)
                self.assertEqual(rows, [])
                texts = [(r[b'left'] or b'').decode() for r in replay.lua.globals().ReplayLastRendered.values()]
                if entity_id == 16688:
                    self.assertTrue(any(text.startswith('(2) Set:') for text in texts), texts)
                    self.assertFalse(any('Ensemble' in text for text in texts), texts)


class RemainingCapturedTooltipCampaignTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/four-remaining-cases-enUS.json').read_text()))

    test_captured_campaign_has_no_untranslated_rows = CapturedTooltipCampaignTests.test_captured_campaign_has_no_untranslated_rows

    def test_four_source_relationships_translate_both_actual_client_languages(self):
        french = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-frFR-legacy-api.json').read_text()))
        expected = {('spell', 5938), ('item', 22289), ('item', 271904), ('item', 34087)}
        verified = {'enUS': [], 'frFR': []}
        for capture, run_id, locale, target in ((self.capture, 13, 'enUS', 'frFR'),
                                               (french, 5, 'frFR', 'enUS'),
                                               (french, 7, 'frFR', 'enUS')):
            sample = next(r for r in capture['runs'] if r['run'] == run_id)['samples'][0]
            details = sample['details']
            original = copy.deepcopy(details)
            globals_ = {k: v for k, v in capture['globals'][details['globalsRef']].items() if v != '<nil>'}
            replay = gaps.Replay(locale, globals_, gaps.context_calls(details['calls'], sample.get('context')))
            checked = []
            for observation in gaps.api_observations(details['calls']):
                key = observation['kind'], observation['id']
                if key not in expected:
                    continue
                with self.subTest(locale=locale, api=observation['api'], entity=key):
                    rows, failure, _ = replay.run(*key, gaps.clean(observation['data']), target,
                                                  gaps.clean(observation['processingInfo']['values'][1]))
                    self.assertIsNone(failure)
                    self.assertEqual(rows, [])
                checked.append(key)
            verified[locale].extend(checked)
            self.assertEqual(details, original)
        for locale, checked in verified.items():
            with self.subTest(locale=locale):
                self.assertEqual(set(checked), expected)
                self.assertEqual(len(checked), 7, 'Keep all captured spell, item and hyperlink surfaces')


class AllCapturedHoverTests(unittest.TestCase):
    def test_every_original_hover_is_accounted_for_without_inventing_api_returns(self):
        from audit_tooltip_hovers import audit
        capture = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-frFR-all-hovers.json').read_text()))
        original = copy.deepcopy(capture)
        report = audit(capture)
        self.assertEqual(report['total'], 680)
        self.assertEqual(len({(row['run'], row['sample']) for row in report['observations']}), 680)
        self.assertEqual(report['counts'], {'passed': 581, 'missing_context': 98, 'not_applicable': 1})
        missing = [row for row in report['observations'] if row['status'] == 'missing_context']
        self.assertTrue(all(row['kind'] == 'aura' and row['missing'] for row in missing))
        self.assertEqual(sum(bool(row['descriptionChecks']) for row in missing), 97)
        self.assertEqual(capture, original)


if __name__ == '__main__':
    unittest.main()
