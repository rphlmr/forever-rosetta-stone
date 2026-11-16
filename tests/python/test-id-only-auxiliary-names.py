"""Auxiliary tooltips do not identify entities by their native names."""

import unittest

from lupa.lua51 import LuaRuntime


class AuxiliaryNamesTests(unittest.TestCase):
    def test_structured_ids_and_native_fallbacks(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('''
            local components = {}
            Addon = {
                RegisterNameTooltipComponent = function(_, component) components[component.kind] = component end,
                IsReadableEntityID = function(_, id) return type(id) == "number" and id > 0 end,
                GetTargetLocale = function() return "enUS" end,
                GetIncompleteTranslationNotice = function() return "Some lines are not translated yet." end,
                npcTooltipSourceLocales = {},
                npcTooltipData = { frFR = { pvp = "JcJ", formats = {} },
                    enUS = { pvp = "PvP", formats = {} } },
                npcTooltipClassifications = {},
            }
            canaccessallvalues = function(...) return true end
            GetLocale = function() return "frFR" end
            Enum = { TooltipDataType = { MinimapMouseover = 1, Unit = 2 },
                TooltipDataLineType = { UnitType = 3 } }
            ForeverRosettaStoneDB = {
                GetNpcFactionID = function(_, id) assert(id == 812345); return nil end,
                GetFactionSourceName = function() error("native faction lookup") end,
                GetFactionName = function() error("faction translation") end,
                GetCreatureTypeName = function(_, id) assert(id == 27); return "Creature type" end,
            }
            assert(loadfile("ForeverRosettaStone/tooltips/components/minimap-quest-tooltip.lua"))(nil, Addon)
            assert(loadfile("ForeverRosettaStone/tooltips/components/npc-tooltip.lua"))(nil, Addon)

            local resolve = components.minimapQuest.ResolveData
            local color = { r = 0.5 }
            local id, actualColor = resolve(nil, { type = 1, lines = {
                { leftText = "Same native title" }, { questID = 812345, leftColor = color },
            } })
            assert(id == 812345 and actualColor == color)
            assert(resolve(nil, { type = 1, lines = { { leftText = "Same native title" } } }) == nil)

            UnitGUID = function() return "Creature-0-0-0-0-812345-0" end
            UnitCreatureType = function() return "Native type", 27 end
            UnitIsPlayer = function() return false end
            local rows = {}
            local font = { GetTextColor = function() return 1, 1, 1 end,
                GetFont = function() return "font", 12, "" end, GetTextScale = function() return 1 end }
            local source = { GetLeftLine = function() return font end, GetUnit = function() return nil, "target" end }
            local tip = {
                AddLine = function(_, text) rows[#rows + 1] = text end,
                NumLines = function() return #rows end,
                GetLeftLine = function() return { SetFont = function() end, SetTextScale = function() end } end,
            }
            Addon:FillNpcTooltip({ tip = tip, source = source, id = 812345, name = "Translated NPC",
                data = { guid = "Creature-0-0-0-0-812345-0", lines = {
                    { leftText = "Native NPC" }, { leftText = "Native faction" },
                    { type = 3, leftText = "Native type" }, { leftText = "JcJ" },
                } } })
            assert(rows[1] == "Translated NPC" and rows[2] == "Creature type")
            assert(rows[3] == "PvP" and #rows == 3,
                "Unknown extras stay outside the picked unit fields and do not claim a translation")
        ''')


if __name__ == '__main__':
    unittest.main()
