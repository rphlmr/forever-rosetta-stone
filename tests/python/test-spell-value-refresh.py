"""Verify numeric refreshes preserve prose and reject ambiguous trait data."""

import copy
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import runpy
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
refresh = runpy.run_path(str(ROOT / 'tools/catalogs/refresh-spell-values.py'))
from tools.catalogs.spell_render_context import spell_render_context


class SpellValueRefreshTests(unittest.TestCase):
    def test_duration_dependencies_require_family_and_mask_and_supported_operation(self):
        def family(sid, group, mask):
            return {'SpellID': str(sid), 'SpellClassSet': str(group),
                    **{f'SpellClassMask_{part}': str(mask if part == 0 else 0) for part in range(4)}}
        effect = {'SpellID': '902', 'EffectIndex': '0', 'DifficultyID': '0', 'Effect': '6',
                  'EffectAura': '107', 'EffectMiscValue_0': '1', 'EffectBasePointsF': '3000',
                  **{f'EffectSpellClassMask_{part}': str(8 if part == 0 else 0) for part in range(4)}}
        tables = {'SpellMisc': [{'SpellID': '901', 'SchoolMask': '32', 'DifficultyID': '0'}],
                  'SpellClassOptions': [family(901, 6, 8), family(902, 6, 0)], 'SpellEffect': [effect]}
        self.assertEqual(spell_render_context(901, tables), {'schoolMask': 32, 'durationModifiers': [
            {'operation': 'add', 'spellID': 902, 'effectIndex': 0}]})
        tables['SpellClassOptions'][1]['SpellClassSet'] = '7'
        self.assertEqual(spell_render_context(901, tables), {'schoolMask': 32})
        tables['SpellClassOptions'][1]['SpellClassSet'] = '6'
        effect['EffectSpellClassMask_0'] = '16'
        self.assertEqual(spell_render_context(901, tables), {'schoolMask': 32})
        effect['EffectSpellClassMask_0'] = '8'
        effect['EffectAura'] = '108'
        with self.assertRaisesRegex(ValueError, 'Unsupported'):
            spell_render_context(901, tables)

    def setUp(self):
        self.entity = {
            'locales': {'enUS': {'description': 'Value $s1.'}, 'frFR': {'description': 'Valeur $s1.'}},
            'tooltipData': {'sourceDescriptions': {'deDE': 'Wert $s1.'},
                            'effects': [{'index': 0, 'basePoints': 2, 'radius': 50}]},
        }
        self.row = {column: '0' for column in refresh['EFFECT_FIELDS'].values()}
        self.row.update(ID='1', DifficultyID='0', EffectBasePointsF='7', Effect='6')
        self.effects = {42: [self.row]}
        self.levels = {42: [{'ID': '2', 'DifficultyID': '0', 'BaseLevel': '6', 'SpellLevel': '6', 'MaxLevel': '16'}]}

    def test_numeric_update_preserves_translations_sources_and_unrelated_fields(self):
        before = copy.deepcopy(self.entity)
        result = refresh['refresh_entity'](self.entity, 42, self.effects, self.levels, {}, replace_existing=True)
        self.assertEqual(self.entity, before)
        self.assertEqual(result['locales'], before['locales'])
        self.assertEqual(result['tooltipData']['sourceDescriptions'], before['tooltipData']['sourceDescriptions'])
        self.assertEqual(result['tooltipData']['effects'][0]['basePoints'], 7)
        self.assertEqual(result['tooltipData']['effects'][0]['radius'], 50)
        self.assertEqual(result['tooltipData']['spellLevel'], 6)

    def test_ambiguous_traits_and_missing_default_rows_are_not_applied(self):
        with self.assertRaisesRegex(ValueError, 'review required'):
            refresh['refresh_entity'](self.entity, 42, self.effects, self.levels, {})

        self.row['EffectBasePointsF'] = '2'
        for candidates in ([{'error': 'Missing node'}], [{}, {}]):
            with self.assertRaises(ValueError):
                refresh['refresh_entity'](self.entity, 42, self.effects, self.levels, {(42, 0): candidates})

        self.row['DifficultyID'] = '1'
        with self.assertRaises(ValueError):
            refresh['refresh_entity'](self.entity, 42, self.effects, self.levels, {})

    def test_rank_values_come_from_curve_points(self):
        tables = {
            'TraitDefinition': [{'ID': '11', 'SpellID': '42'}],
            'TraitNodeEntry': [{'ID': '12', 'TraitDefinitionID': '11', 'MaxRanks': '2'}],
            'TraitNodeXTraitNodeEntry': [{'ID': '13', 'TraitNodeEntryID': '12', 'TraitNodeID': '14'}],
            'TraitNode': [{'ID': '14'}],
            'TraitDefinitionEffectPoints': [{'ID': '15', 'TraitDefinitionID': '11', 'EffectIndex': '0',
                                             'OperationType': '0', 'CurveID': '16'}],
            'CurvePoint': [{'ID': '17', 'CurveID': '16', 'Pos_0': '1', 'Pos_1': '13'},
                           {'ID': '18', 'CurveID': '16', 'Pos_0': '2', 'Pos_1': '29'}],
        }
        result = refresh['index_traits'](tables, '1.60.1.70888')[(42, 0)][0]
        self.assertEqual(result['curvePoints'], [{'rank': 1, 'value': 13}, {'rank': 2, 'value': 29}])
        self.assertEqual(result['nodeID'], 14)
        tables['CurvePoint'].pop()
        self.assertIn('error', refresh['index_traits'](tables, '1.60.1.70888')[(42, 0)][0])

    def test_missing_scalar_fields_use_unique_rows_and_keep_zero_values(self):
        tables = {
            'SpellAuraOptions': {42: [{'ID': '1', 'DifficultyID': '0', 'CumulativeAura': '0',
                                       'ProcChance': '25', 'ProcCharges': '2'}]},
            'SpellTargetRestrictions': {42: [{'ID': '2', 'DifficultyID': '0', 'MaxTargets': '3'}]},
            'SpellMisc': {42: [{'ID': '3', 'DifficultyID': '0', 'RangeIndex': '4'}]},
            'SpellRange': {4: [{'ID': '4', 'RangeMax_0': '30', 'RangeMax_1': '30'}]},
        }
        provenance = {table: {'sourceBuild': 'test'} for table in tables}
        before = copy.deepcopy(self.entity)
        fill = refresh['fill_missing_spell_fields']
        result = fill(self.entity, 42, tables, provenance)
        self.assertEqual(self.entity, before)
        self.assertEqual(result['locales'], before['locales'])
        for field, value in (('maxStacks', 0), ('procChance', 25), ('procCharges', 2),
                             ('maxTargets', 3), ('rangeMax', 30)):
            self.assertEqual(result['tooltipData'][field], value)
            self.assertEqual(result['tooltipData'][field + 'SourceMetadata'], {'sourceBuild': 'test'})
        self.entity['tooltipData']['procCharges'] = 7
        result = fill(self.entity, 42, tables, provenance)
        self.assertEqual(result['tooltipData']['procCharges'], 7)
        self.assertNotIn('procChargesSourceMetadata', result['tooltipData'])

        tables['SpellAuraOptions'][42] *= 2
        tables['SpellTargetRestrictions'][42][0]['DifficultyID'] = '1'
        tables['SpellRange'][4][0]['RangeMax_1'] = '40'
        result = fill(before, 42, tables, provenance)
        for field in ('maxStacks', 'procChance', 'procCharges', 'maxTargets', 'rangeMax'):
            self.assertNotIn(field, result['tooltipData'])

    def test_missing_scalar_rows_never_infer_defaults(self):
        tables = {table: {} for table in refresh['SPELL_FIELD_TABLES']}
        result = refresh['fill_missing_spell_fields'](self.entity, 42, tables, {})
        self.assertEqual(result, self.entity)
        entity = {'locales': {'enUS': {'name': 'No numeric source'}}}
        self.assertEqual(refresh['fill_missing_spell_fields'](entity, 42, tables, {}), entity)

    def test_missing_effect_levels_use_rows_including_zero_and_preserve_existing(self):
        row = {**self.row, 'EffectBasePointsF': '2', 'Effect': '6'}
        second = {**row, 'ID': '9', 'EffectIndex': '1', 'EffectBasePointsF': '0'}
        entity = {'locales': {'enUS': {'description': '$s2'}}, 'tooltipData': {
            'effects': [{'index': 0, 'effectType': 6, 'basePoints': 2, 'radius': 50}],
            'baseLevel': 6}}
        provenance = {'effects': {'sourceBuild': 'test'}, 'levels': {'sourceBuild': 'test'}}
        before = copy.deepcopy(entity)
        fill = refresh['fill_missing_effect_levels']
        result = fill(entity, 42, {42: [row, second]}, self.levels, provenance, {})
        self.assertEqual(entity, before)
        self.assertEqual(result['tooltipData']['effects'][0]['radius'], 50)
        self.assertEqual(result['tooltipData']['effects'][1]['basePoints'], 0)
        self.assertEqual(result['tooltipData']['effects'][1]['chainTargets'], 0)
        self.assertNotIn('periodMs', result['tooltipData']['effects'][1])
        self.assertEqual(result['tooltipData']['spellLevel'], 6)
        self.assertEqual(result['tooltipData']['effectValuesSourceMetadata'], provenance['effects'])
        self.assertEqual(result['tooltipData']['spellLevelSourceMetadata'], provenance['levels'])

        self.assertEqual(fill(entity, 42, {}, {}, provenance, {}), entity)
        conflict = {**row, 'EffectBasePointsF': '3'}
        skipped = []
        result = fill(entity, 42, {42: [conflict, second]}, self.levels, provenance, {}, skipped)
        self.assertEqual(result, entity)

        self.assertIn('dependent levels', skipped[0]['field'])
        result = fill(entity, 42, {42: [row, second, second]}, {}, provenance, {})
        self.assertEqual(result, entity)
        result = fill(entity, 42, {42: [row]}, {42: self.levels[42] * 2}, provenance, {})
        self.assertNotIn('spellLevel', result['tooltipData'])
        entity['tooltipData']['baseLevel'] = 7
        result = fill(entity, 42, {42: [row]}, self.levels, provenance, {})
        self.assertNotIn('spellLevel', result['tooltipData'])

        entity = {'tooltipData': {'effects': []}}
        skipped = []
        result = fill(entity, 42, {42: [second]}, {}, provenance,
                      {(42, 1): [{'definitionID': 5}]}, skipped)
        self.assertEqual(result, entity)
        self.assertEqual(skipped[0]['field'], 'effects.1')
        result = fill(entity, 42, {42: [second]}, {}, provenance,
                      {(42, 1): [{'error': 'ambiguous'}]})
        self.assertEqual(result, entity)

    def test_effect_level_provenance_only_names_value_source(self):
        hashes = {table: table + '-hash' for table in refresh['EFFECT_LEVEL_TABLES']}
        provenance = refresh['effect_level_provenance']('1.60.1.70938', hashes)
        self.assertEqual(provenance['effects']['sourceFileSha256'], {'SpellEffect': hashes['SpellEffect']})
        self.assertEqual(provenance['levels']['sourceFileSha256'], {'SpellLevels': hashes['SpellLevels']})
        self.assertEqual(provenance['effects']['sourceBuild'], '1.60.1.70938')

    def test_missing_values_require_unambiguous_unscaled_source_rows(self):
        entity = copy.deepcopy(self.entity)
        entity['tooltipData']['effects'][0].update(effectType=6, auraType=0)
        del entity['tooltipData']['effects'][0]['radius']
        self.row.update(EffectRadiusIndex_0='0', EffectRadiusIndex_1='13', EffectAuraPeriod='2000')
        misc = {42: [{'DifficultyID': '0', 'DurationIndex': '3'}]}
        radii = {13: {'ID': '13', 'Radius': '10', 'RadiusMax': '10', 'RadiusPerLevel': '0'}}
        durations = {3: {'ID': '3', 'Duration': '5000', 'MaxDuration': '5000',
                         'DurationPerLevel': '0', 'DurationPerResource': '0'}}
        fill = refresh['fill_missing_tooltip_values']
        provenance = {'radius': {'sourceBuild': 'test'}, 'period': {'sourceBuild': 'test'},
                      'duration': {'sourceBuild': 'test'}}
        result = fill(entity, 42, self.effects, misc, radii, durations, provenance)
        self.assertEqual(result['tooltipData']['effects'][0]['radius'], 10)
        self.assertEqual(result['tooltipData']['effects'][0]['periodMs'], 2000)
        self.assertEqual(result['tooltipData']['durationMs'], 5000)
        self.assertNotIn('radius', entity['tooltipData']['effects'][0])
        self.row['EffectRadiusIndex_0'] = '14'
        durations[3]['DurationPerResource'] = '1'
        result = fill(entity, 42, self.effects, misc, radii, durations, provenance)
        self.assertNotIn('radius', result['tooltipData']['effects'][0])
        self.assertNotIn('durationMs', result['tooltipData'])
        entity['tooltipData']['effects'][0]['periodMs'] = 7
        self.assertEqual(fill(entity, 42, self.effects, misc, radii, durations, provenance)
                         ['tooltipData']['effects'][0]['periodMs'], 7)
        self.row['EffectRadiusIndex_0'] = '0'
        entity['tooltipData']['effects'][0]['effectType'] = 9
        self.assertNotIn('radius', fill(entity, 42, self.effects, misc, radii, durations, provenance)
                         ['tooltipData']['effects'][0])

    def test_existing_radius_must_match_before_claiming_entity_provenance(self):
        entity = copy.deepcopy(self.entity)
        entity['tooltipData']['effects'] = [
            {'index': 0, 'effectType': 6, 'auraType': 0, 'radius': 50},
            {'index': 1, 'effectType': 6, 'auraType': 0},
        ]
        first = {**self.row, 'EffectRadiusIndex_0': '0', 'EffectRadiusIndex_1': '13'}
        second = {**first, 'ID': '2', 'EffectIndex': '1'}
        effects = {42: [first, second]}
        radii = {13: {'ID': '13', 'Radius': '10', 'RadiusMax': '10', 'RadiusPerLevel': '0'}}
        provenance = {'radius': {'sourceBuild': 'test'}, 'period': {'sourceBuild': 'test'},
                      'duration': {'sourceBuild': 'test'}}
        fill = refresh['fill_missing_tooltip_values']
        result = fill(entity, 42, effects, {}, radii, {}, provenance)
        self.assertNotIn('radius', result['tooltipData']['effects'][1])
        self.assertNotIn('radiusSourceMetadata', result['tooltipData'])
        self.assertEqual(result['tooltipData']['effects'][0]['radius'], 50)
        entity['tooltipData']['effects'][0]['radius'] = 10
        result = fill(entity, 42, effects, {}, radii, {}, provenance)
        self.assertEqual(result['tooltipData']['effects'][1]['radius'], 10)
        self.assertEqual(result['tooltipData']['radiusSourceMetadata'], provenance['radius'])


if __name__ == '__main__':
    unittest.main()
