"""Check the coverage-selected tooltip inventory and the captured-tooltip gap report."""

import csv
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


coverage = load_module('prepare_tooltip_coverage', ROOT / 'tools/source-scan/prepare_tooltip_coverage.py')
gaps = load_module('report_tooltip_gaps', ROOT / 'tools/source-scan/report_tooltip_gaps.py')
campaign = load_module('prepare_tooltip_campaign', ROOT / 'tools/source-scan/prepare_tooltip_campaign.py')
importer = load_module('import_client_api_fixture', ROOT / 'tools/source-scan/import_client_api_fixture.py')


def write_csv(path, rows):
    with path.open('w', encoding='utf-8', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=sorted({key for row in rows for key in row}))
        writer.writeheader()
        writer.writerows(rows)


class TooltipGapToolTests(unittest.TestCase):
    def test_campaign_reuses_examples_and_retains_unloaded_ids(self):
        report = {'groups': [
            {'kind': 'spell', 'exampleIds': [1, 2], 'pattern': 'A'},
            {'kind': 'spell', 'exampleIds': [2, 3], 'pattern': 'B'},
            {'kind': 'item', 'exampleIds': [4], 'pattern': 'C'}], 'notLoaded': {'spell': [9]}}
        self.assertEqual(campaign.select(report, 1), {'spell': [2, 9], 'item': [4]})
        self.assertEqual(campaign.select(report, 2), {'spell': [1, 2, 3, 9], 'item': [4]})

    def test_prepared_campaign_replaces_default_api_inventory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'catalogs/globalstrings').mkdir(parents=True)
            report = root / 'report.json'
            report.write_text(json.dumps({'clientLocale': 'frFR', 'run': 7, 'groups': [
                {'kind': 'spell', 'pattern': 'A', 'exampleIds': [598]}], 'notLoaded': {'item': [1205]}}))
            output = root / 'campaign'
            output.mkdir()
            manifest = campaign.prepare(report, output, root=root)
            from lupa.lua51 import LuaRuntime
            lua = LuaRuntime()
            lua.execute('probe = {}')
            addon = output / 'rosetta-tooltip-check'
            for name in ('cases.lua', 'api-sample.lua'):
                lua.execute('assert(loadstring(...))("probe", probe)', (addon / name).read_text())
            lua.execute('assert(#probe.cases.api.ids.spell == 1 and probe.cases.api.ids.spell[1] == 598); '
                        'assert(#probe.cases.api.ids.item == 1 and probe.cases.api.ids.item[1] == 1205); '
                        'assert(probe.cases.api.ids.quest == nil)')
            self.assertEqual(manifest['candidateGroups'], 1)
            self.assertEqual(len(manifest['reportSha256']), 64)

    def test_aura_replay_uses_captured_instance_getter_and_spell_identity(self):
        calls = {'C_UnitAuras.GetAuraDataByAuraInstanceID': {'"player", 12': {
            'status': 'ok', 'returnCount': 1, 'values': {1: {'spellId': 6074, 'name': 'Rénovation'}}}}}
        replay = gaps.Replay('frFR', {}, calls)
        replay.lua.execute(b'''
            local aura,unit = ReplayAddon:GetTooltipAuraData({GetProcessingTooltipInfo = function()
                return {getterName='GetUnitAuraByAuraInstanceID',getterArgs={'player',12}}
            end})
            assert(aura.spellId==6074 and unit=='player')
        ''')
        data = {'type': 7, 'id': 12, 'lines': [{'type': 0, 'leftText': 'Rénovation'}]}
        processing = {'getterName': 'GetUnitAuraByAuraInstanceID', 'getterArgs': ['player', 12]}
        rows, failure, _ = replay.run('spell', 6074, data, 'enUS', processing)
        self.assertIsNone(failure)
        self.assertEqual(rows, [])

    def test_replay_uses_captured_schematic_for_reagent_translation(self):
        calls = {'C_TradeSkillUI.GetRecipeSchematic': {'7418, false': {'status': 'ok', 'returnCount': 1,
            'values': {1: {'recipeID': 7418, 'reagentSlotSchematics': {1: {'reagents': {1: {'itemID': 10940}}}}}}}}}
        replay = gaps.Replay('frFR', {'SPELL_REAGENTS': 'Composants : '}, calls)
        replay.lua.execute(br'''
            ReplayAddon.GetClientLabel = function(_,key) if key=='SPELL_REAGENTS' then return 'Reagents: ' end end
            local result, incomplete = ReplayAddon:GetSpellRequirementTranslations({id=7418, data={lines={
                {type=0, leftText='Composants : Poussi\195\168re \195\169trange (7)'}
            }}}, 'enUS')
            local count=0
            for line,text in pairs(result) do
                assert(text=='Reagents: Strange Dust (7)',text)
                assert(not incomplete[line]); count=count+1
            end
            assert(count==1)
        ''')

    def test_targeted_report_keeps_repeated_ids_in_distinct_contexts(self):
        line_types = {name: index for index, name in enumerate(gaps.LINE_TYPES)}
        def sample(text):
            return {'kind': 'hover', 'context': {'form': {'status': 'ok', 'values': {1: 3}}},
                    'details': {'dataType': 'Spell', 'entityID': 598,
                        'dependencies': {'C_TradeSkillUI.GetRecipeSchematic': {'598, false': {
                            'status': 'ok', 'returnCount': 1, 'values': {1: '<nil>'}}}},
                        'data': {'type': 1, 'id': 598, 'lines': {
                            1: {'type': line_types['SpellName'], 'leftText': 'Châtiment'},
                            2: {'type': 0, 'leftText': text}}}}}
        capture = {'schemaVersion': 1, 'runs': {1: {'profile': 'cible', 'label': 'normal',
            'stoppedReason': 'manual stop', 'locale': {'values': {1: 'frFR'}},
            'samples': {1: sample('Premier texte inconnu'), 2: sample('Second texte inconnu')}}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'capture.lua'
            path.write_text('RosettaTooltipCheckData = ' + importer.to_lua(capture), encoding='utf-8')
            result = gaps.report(path, targets=['enUS'], kinds=('spell',))
        self.assertEqual(result['observations'], 2)
        self.assertEqual(result['rendered'], 2)
        self.assertEqual(result['incomplete'], 2)
        self.assertEqual(result['errorCount'], 0)
        self.assertEqual(result['recipeSchematicEvidence'], {'ok: no schematic': 2})
        self.assertEqual(len(result['provenance']['captureSha256']), 64)

    def test_token_shapes_drop_ids_and_amounts(self):
        shapes = coverage.token_shapes('Deals $s1 to $m2 over $d. ${$m1/-1000} sec, $lpoint:points;, '
                                       '$ghis:her;, $?s1234[a][b] $@spellname668 $1308027d |4min:mins;')
        self.assertEqual(shapes, {'$s', '$m', '$d', '${$m/-}', '$l:2', '$g:2', '$?s', '$@spellname', '$d',
                                  '|4plural'})

    def test_selection_covers_rare_features_first_and_is_stable(self):
        features = {'common': set(range(1, 100)), 'rare': {7, 8}, 'single': {42}}
        chosen = coverage.select(features, 3, 'seed', 'spell')
        self.assertEqual(chosen, coverage.select(features, 3, 'seed', 'spell'))
        self.assertTrue({7, 8, 42} <= set(chosen), 'Every candidate of an under-covered feature is kept')
        self.assertLessEqual(len(chosen), 3 + 3, 'Shared IDs count for every feature they carry')
        report = coverage.coverage(features, chosen, 3)
        self.assertEqual(report['underCovered'], {'rare': 2, 'single': 1})

    def test_prepare_selects_client_ids_with_owned_records(self):
        with tempfile.TemporaryDirectory() as directory:
            root, wago = Path(directory) / 'repo', Path(directory) / 'wago'
            for kind, ids in (('spells', (1, 2, 3, 9)), ('items', (10, 11, 12)), ('globalstrings', ())):
                (root / 'catalogs' / kind).mkdir(parents=True)
                for entity_id in ids:
                    (root / 'catalogs' / kind / f'{entity_id}.json').write_text(
                        json.dumps({'tooltipData': {'maxStacks': 5} if entity_id == 3 else {}}))
            (root / 'catalogs/globalstrings/1.json').write_text(json.dumps({'key': 'CORPSE'}))
            wago.mkdir()
            build = '1.60.1.70938'
            write_csv(wago / f'Spell.{build}.enUS.csv', [
                {'ID': 1, 'Description_lang': 'Deals $s1.', 'AuraDescription_lang': '', 'NameSubtext_lang': 'Rank 2'},
                {'ID': 2, 'Description_lang': 'Lasts $d.', 'AuraDescription_lang': '', 'NameSubtext_lang': ''},
                {'ID': 3, 'Description_lang': '', 'AuraDescription_lang': 'Stacks.', 'NameSubtext_lang': ''},
                {'ID': 50, 'Description_lang': 'Heals $s1 health over $d.', 'AuraDescription_lang': '',
                 'NameSubtext_lang': ''}])
            write_csv(wago / f'SpellName.{build}.enUS.csv', [{'ID': i, 'Name_lang': 'x'} for i in (1, 2, 3, 50)])
            write_csv(wago / f'SpellMisc.{build}.enUS.csv', [
                {'ID': 1, 'SpellID': 1, 'Attributes_0': 64, 'CastingTimeIndex': 1, 'RangeIndex': 1,
                 'DurationIndex': 0, 'SchoolMask': 1}])
            write_csv(wago / f'ItemSparse.{build}.enUS.csv', [
                {'ID': 10, 'AllowableClass': 2, 'InventoryType': 6, 'Bonding': 1, 'OverallQualityID': 3,
                 'StatModifier_bonusStat_0': 7, 'StatPercentEditor_0': 100, 'ItemSet': 0, 'Description_lang': ''},
                {'ID': 11, 'AllowableClass': -1, 'InventoryType': 0, 'Bonding': 0, 'OverallQualityID': 1,
                 'StatModifier_bonusStat_0': -1, 'StatPercentEditor_0': 0, 'ItemSet': 5, 'Description_lang': 'Old.'}])
            write_csv(wago / f'Item.{build}.enUS.csv', [{'ID': 10, 'ClassID': 4, 'SubclassID': 4},
                                                         {'ID': 11, 'ClassID': 0, 'SubclassID': 0}])
            write_csv(wago / f'ItemEffect.{build}.enUS.csv', [{'ID': 1, 'TriggerType': 0, 'SpellID': 1, 'Charges': -1,
                                                               'CoolDownMSec': 0, 'CategoryCoolDownMSec': 0}])
            write_csv(wago / f'ItemXItemEffect.{build}.enUS.csv', [{'ID': 1, 'ItemEffectID': 1, 'ItemID': 11}])
            output = root / 'out'
            output.mkdir()
            counts = coverage.prepare(output, wago, 1, 'seed', 60, root)
            sample = json.loads((output / 'sample.json').read_text())
            self.assertEqual(sample['ids']['spell'], [1, 2, 3], 'Only owned IDs present in the client build')
            self.assertEqual(sample['ids']['item'], [10, 11], 'Item 12 is not in the client build')
            self.assertEqual(sample['mode'], 'coverage')
            features = json.loads((output / 'features.json').read_text())
            for name in ('passive', 'subtext:Rank #', 'owned:maxStacks', 'aura', 'description:$s'):
                self.assertIn(name, features['spell'])
            for name in ('classes:1', 'stat:7', 'set', 'flavor', 'effect:0', 'effect:0:charges-', 'effect:0:$s'):
                self.assertIn(name, features['item'])
            self.assertEqual(counts['globals']['sampled'], 1)
            api_sample = (output / 'rosetta-tooltip-check/api-sample.lua').read_text()
            self.assertIn('mode = "coverage"', api_sample)

    def test_gap_hooks_match_the_shipping_renderer_once(self):
        source = (ROOT / 'ForeverRosettaStone/tooltips/tooltip-descriptions.lua').read_text(encoding='utf-8')
        for old, _ in gaps.GAP_HOOKS:
            self.assertEqual(source.count(old), 1, old)
        self.assertEqual(source.count('incomplete = true'), 4,
                         'A new incomplete condition needs a GAP_HOOKS entry')
        self.assertEqual(gaps.pattern('|cffffffffRequiert 1 234 points|r (12,5 %)'), 'Requiert # points (# %)')

    def test_report_groups_unmatched_rows_and_skips_unloaded_tooltips(self):
        line_types = {name: index for index, name in enumerate(gaps.LINE_TYPES)}
        loading = "Récupération des informations de l'objet"

        def tooltip(*lines):
            return {'status': 'ok', 'returnCount': 1, 'values': {1: {'type': 0, 'lines': {
                index: line for index, line in enumerate(lines, 1)}}}}

        calls = {'C_TooltipInfo.GetItemByID': {
            '6948': tooltip({'type': line_types['ItemName'], 'leftText': 'Pierre de foyer'},
                            {'type': line_types['None'], 'leftText': 'Une ligne inconnue 12'}),
            '6949': tooltip({'type': line_types['ItemName'], 'leftText': 'Autre'},
                            {'type': line_types['None'], 'leftText': 'Une ligne inconnue 7'}),
            '6950': tooltip({'type': line_types['ItemName'], 'leftText': 'Ensemble'},
                            {'type': line_types['None'], 'leftText': loading}),
        }, 'C_TooltipInfo.GetSpellByID': {'123': {'status': 'error', 'error': 'Not available'}}}
        capture = {'schemaVersion': 1, 'runs': {1: {
            'profile': 'api', 'stoppedReason': 'api complete',
            'locale': {'status': 'ok', 'values': {1: 'frFR'}},
            'samples': {1: {'kind': 'api', 'details': {'calls': calls,
                                                         'globals': {'RETRIEVING_ITEM_INFO': loading}}}}}}}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'rosetta-tooltip-check.lua'
            path.write_text('RosettaTooltipCheckData = ' + importer.to_lua(capture) + '\n', encoding='utf-8')
            result = gaps.report(path, targets=['enUS'], kinds=('item',))
        self.assertEqual(result['notLoaded'], {'item': [6950]})
        self.assertEqual(result['errorCount'], 0)
        self.assertEqual(result['unavailableTooltips'][0]['status'], 'error')
        self.assertEqual(result['incomplete'], 2)
        group = result['groups'][0]
        self.assertEqual((group['pattern'], group['ids'], group['lineType'], group['reason']),
                         ('Une ligne inconnue #', 2, 'None', 'left kept'))
        self.assertIn('Une ligne inconnue #', gaps.markdown(result))


if __name__ == '__main__':
    unittest.main()
