"""Map hover identity uses cursor-scoped client IDs, independent of client language."""

from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata


class MapHoverLocationTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        install_metadata(self.lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        self.api = load_database(self.lua)
        self.lua.execute(b'''
            canaccessallvalues = function(...)
                for i=1,select('#',...) do
                    local v=select(i,...)
                    if type(v)=='table' and v.restricted then return false end
                end
                return true
            end
            GetLocale = function() error('Use live client names, not catalog source-locale matching') end
            addon = {GetTargetLocale=function() return targetLocale end,
                IsReadableEntityID=function(_,id) return canaccessallvalues(id) and type(id)=='number'
                    and id>0 and id==math.floor(id) end}
            targetLocale, focused, cursorX, cursorY = 'frFR', true, 0.749, 0.482
            WorldMapFrame = {IsCanvasMouseFocus=function() return focused end,
                GetMapID=function() return 1429 end,
                GetNormalizedCursorPosition=function() return cursorX,cursorY end}
            CreateVector2D = function(x,y) return {x=x,y=y} end
            candidates, names = {12,86}, {[12]='Elwynn Forest', [86]='Stone Cairn Lake'}
            C_Map = {GetAreaInfo=function(id) return names[id] end,
                GetMapInfoAtPosition=function() return {mapID=1429,name='Elwynn Forest'} end}
            C_MapExplorationInfo = {GetExploredAreaIDsAtPosition=function(mapID,position)
                assert(mapID==1429 and position.x==cursorX and position.y==cursorY)
                return candidates
            end}
        ''')
        self.lua.execute((ROOT / 'ForeverRosettaStone/quests/quest-data.lua').read_bytes(), b'FRS', self.lua.globals().addon)

    def resolve(self, text=b'Stone Cairn Lake'):
        addon = self.lua.globals().addon
        return addon.GetHoveredMapLocationName(addon, text)

    def test_english_subzone_translates_when_the_hovered_uimap_is_the_current_map(self):
        # Names/IDs are owned AreaTable records; the visible English name is in the screenshot.
        self.assertEqual(self.api.GetAreaName(self.api, 86, b'enUS'), b'Stone Cairn Lake')
        self.assertEqual(self.resolve(), self.api.GetAreaName(self.api, 86, b'frFR'))
        self.assertEqual(self.resolve(), b'Lac du Cairn')

    def test_french_client_uses_the_same_live_id_binding(self):
        self.lua.execute(b"targetLocale='enUS'; names[86]='Lac du Cairn'")
        self.assertEqual(self.resolve(b'Lac du Cairn'), b'Stone Cairn Lake')

    def test_gamepad_mode_uses_the_same_pointer_as_the_native_area_label(self):
        self.lua.execute(b'''
            targetLocale, names[86] = 'enUS', 'Lac du Cairn'
            InputUtil = {IsGamepadUIEnabled=function() return controllerEnabled end}
            WorldMapFrame.HasGamepadCursorInput=function() return gamepadInput end
            WorldMapFrame.IsCanvasMouseFocusOrPinFocus=function() return mouseFocus end
            WorldMapFrame.GetNormalizedGamepadCursorPosition=function() return 0.73,0.606 end
            C_MapExplorationInfo.GetExploredAreaIDsAtPosition=function(mapID,position)
                assert(mapID==1429)
                if position.x==0.73 and position.y==0.606 then return {86} end
                assert(position.x==cursorX and position.y==cursorY)
                return {12}
            end
        ''')
        for setup, expected in (
            (b'controllerEnabled,gamepadInput,mouseFocus=true,true,true', b'Stone Cairn Lake'),
            (b'gamepadInput,mouseFocus=false,false', b'Stone Cairn Lake'),
            (b'mouseFocus=true', None),
            (b'controllerEnabled,mouseFocus=false,false', None),
        ):
            with self.subTest(setup=setup):
                self.lua.execute(setup)
                self.assertEqual(self.resolve(b'Lac du Cairn'), expected)

    def test_duplicate_ids_are_safe_but_distinct_matching_areas_are_ambiguous(self):
        self.lua.execute(b'candidates={86,12,86}')
        self.assertEqual(self.resolve(), b'Lac du Cairn')
        self.lua.execute(b"candidates={86,16522}; names[16522]='Stone Cairn Lake'")
        self.assertIsNone(self.resolve())

    def test_missing_target_or_unrelated_poi_keeps_native_text(self):
        self.assertIsNone(self.resolve(b'Unrelated point of interest'))
        self.lua.execute(b'ForeverRosettaStoneDB.GetAreaName=function() return nil end')
        self.assertIsNone(self.resolve())

    def test_unavailable_area_api_does_not_break_map_child_fallback(self):
        self.lua.execute(b'''
            C_MapExplorationInfo.GetExploredAreaIDsAtPosition=function() error('Unavailable') end
            C_Map.GetMapInfoAtPosition=function() return {mapID=1437,name='Wetlands'} end
        ''')
        self.assertEqual(self.resolve(b'Wetlands'), self.api.GetMapName(self.api, 1437, b'frFR'))

    def test_off_canvas_and_restricted_or_invalid_coordinates_remain_native(self):
        for setup in (b'focused=false', b'cursorX={restricted=true}', b'cursorY=2', b'cursorX=0/0'):
            with self.subTest(setup=setup):
                self.lua.execute(b'focused,cursorX,cursorY=true,0.749,0.482; ' + setup)
                self.assertIsNone(self.resolve())


if __name__ == '__main__':
    unittest.main()
