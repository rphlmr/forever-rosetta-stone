"""Resolve native zone/subzone names using live candidates and target-only DB pages."""

import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime

from database_harness import install_metadata, load_database, read_metadata


ROOT = Path(__file__).resolve().parents[2]


class PlayerLocationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        self.counts = install_metadata(self.lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        self.api = load_database(self.lua)
        self.lua.execute(b'''
            zone, subzone = 'Live zone wording', 'Live town wording'
            candidates = {132, 77}
            names = {[132] = 'Live valley wording', [77] = 'Live town wording'}
            canaccessallvalues = function(value)
                return not (type(value) == 'table' and value.restricted)
            end
            GetLocale = function() error('Stored native locale matching must not be used') end
            GetZoneText = function() return zone end
            GetSubZoneText = function() return subzone end
            C_Map = {
                GetBestMapForUnit = function() return 1426 end,
                GetMapInfo = function() return {name = 'Live zone wording', mapID = 1426} end,
                GetPlayerMapPosition = function() return {x = 0.29, y = 0.68} end,
                GetAreaInfo = function(id) return names[id] end,
            }
            C_MapExplorationInfo = {GetExploredAreaIDsAtPosition = function() return candidates end}
            ForeverRosettaStoneDB.TranslateAreaName = function() error('Stored source names must not be used') end
        ''')

    def resolve(self, locale=b'frFR'):
        return self.api.GetPlayerLocation(self.api, locale)

    def test_both_areas_use_live_names_and_separate_id_namespaces(self):
        location = self.resolve()
        self.assertEqual(location[b'zone'][b'uiMapID'], 1426)
        self.assertIsNone(location[b'zone'][b'areaID'])
        self.assertEqual(location[b'zone'][b'name'], b'Dun Morogh')
        self.assertEqual(location[b'subzone'][b'areaID'], 77)
        self.assertEqual(location[b'subzone'][b'name'], b'Courbenclume')
        self.assertEqual(location[b'subzone'][b'status'], b'resolved')
        self.assertFalse(any(b'Source_' in pack for pack in self.counts['packs']))

    def test_anvilmar_capture_with_empty_subzone(self):
        self.lua.execute(b"zone = names[77]; subzone = ''")
        location = self.resolve()
        self.assertEqual(location[b'zone'][b'areaID'], 77)
        self.assertEqual(location[b'zone'][b'name'], b'Courbenclume')
        self.assertEqual(location[b'subzone'][b'status'], b'empty')

    def test_source_independence_for_every_target_locale(self):
        for locale in self.api.GetLocales(self.api):
            with self.subTest(locale=locale):
                location = self.resolve(locale)
                self.assertEqual(location[b'subzone'][b'areaID'], 77)
                self.assertEqual(location[b'subzone'][b'name'], self.api.GetAreaName(self.api, 77, locale))
                self.assertEqual(location[b'zone'][b'name'], self.api.GetMapName(self.api, 1426, locale))

    def test_candidate_order_and_repeated_ids_do_not_select_the_area(self):
        self.lua.execute(b'candidates = {77, 132, 77}')
        self.assertEqual(self.resolve()[b'subzone'][b'areaID'], 77)

    def test_distinct_matching_candidates_are_ambiguous(self):
        self.lua.execute(b'names[132] = subzone')
        area = self.resolve()[b'subzone']
        self.assertEqual(area[b'status'], b'ambiguous')
        self.assertIsNone(area[b'areaID'])
        self.assertIsNone(area[b'name'])

    def test_missing_translation_does_not_fall_back_to_english(self):
        self.lua.execute(b'ForeverRosettaStoneDB.GetAreaName = function() return nil end')
        area = self.resolve()[b'subzone']
        self.assertEqual(area[b'areaID'], 77)
        self.assertEqual(area[b'status'], b'missingTranslation')
        self.assertIsNone(area[b'name'])

    def test_unavailable_or_restricted_native_data_remains_unresolved(self):
        self.lua.execute(b'names[77] = {restricted = true}; candidates = {{restricted = true}, 77}')
        self.assertEqual(self.resolve()[b'subzone'][b'status'], b'unresolved')
        self.lua.execute(b'C_Map = nil; C_MapExplorationInfo = nil')
        self.assertEqual(self.resolve()[b'zone'][b'status'], b'unresolved')
        self.assertIsNone(self.resolve(b'unknown'))

    def test_returned_location_is_a_fresh_snapshot(self):
        location = self.resolve()
        self.lua.execute(b"subzone = 'Other place'; candidates = {}")
        self.assertEqual(location[b'subzone'][b'areaID'], 77)
        self.assertEqual(self.resolve()[b'subzone'][b'status'], b'unresolved')

    def test_minimap_consumes_shared_resolver_and_preserves_two_lines(self):
        self.lua.execute(b'''
            addon = {
                GetTargetLocale = function() return 'frFR' end,
                RegisterNameTooltipComponent = function(self, value) self.component = value end,
                SetCompanionTooltipTitle = function(_, tip, text) tip:AddLine(text) end,
                CopyQuestTextStyle = function() end,
            }
            assert(loadfile('ForeverRosettaStone/tooltips/components/minimap-location-tooltip.lua'))('addon', addon)
            tip = {
                lines = {}, AddLine = function(self, text) self.lines[#self.lines + 1] = text end,
                GetLeftLine = function() return {SetTextScale = function() end} end,
            }
            source = {GetLeftLine = function() return {
                GetTextColor = function() return 1, 1, 1 end, GetTextScale = function() return 1 end,
            } end}
            assert(addon.component.GetName(subzone, 'frFR') == 'Courbenclume')
            addon.component.FillTooltip(tip, source)
            assert(#tip.lines == 2 and tip.lines[1] == 'Dun Morogh' and tip.lines[2] == 'Courbenclume')
            zone = subzone
            tip.lines = {}
            addon.component.FillTooltip(tip, source)
            assert(#tip.lines == 1 and tip.lines[1] == 'Courbenclume')
        ''')


if __name__ == '__main__':
    unittest.main()
