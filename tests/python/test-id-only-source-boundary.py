"""Tooltip rows use structured IDs rather than native entity text."""

import unittest

from lupa.lua51 import LuaRuntime


class TooltipSourceBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        self.lua.execute(b'''
            canaccessallvalues = function(...) return true end
            GetLocale = function() return 'frFR' end
            Enum = {TooltipDataLineType = {
                SpellDescription = 34, ItemSpellTriggerOnUse = 44, FlavorText = 37,
                SpellName = 13, EquipSlot = 21,
            }}
            local spell = {description = 'Choose:$?s987654[\\n$@spellname987655]'}
            local item = {classID = 1, subclassID = 2, effects = {{spellID = 987654, triggerType = 0}}}
            ForeverRosettaStoneDB = {
                GetSpellDetails = function(_, id, locale)
                    if id == 987654 then return spell end
                end,
                GetItemDetails = function(_, id, locale)
                    if id == 987653 then return item end
                end,
                GetItemRules = function(_, id)
                    if id == 987653 then return item end
                end,
                GetSpellRules = function() return nil end,
                GetSharedTextsByUsage = function() return {} end,
            }
            setmetatable(ForeverRosettaStoneDB, {__index = function(_, key)
                error('Unexpected source or reverse lookup: ' .. key)
            end})
            addon = {itemSubclasses = {}, itemTooltipLabels = {}, englishTooltipFormats = {},
                tooltipFormatsByLocale = {deDE = {}}}
            assert(loadfile('ForeverRosettaStone/tooltips/spell-live-values.lua'))('addon', addon)
            assert(loadfile('ForeverRosettaStone/tooltips/tooltip-descriptions.lua'))('addon', addon)
        ''')

    def test_untyped_entity_rows_and_missing_data_preserve_native(self):
        self.lua.execute(b'''
            for _, kind in ipairs({'item', 'spell', 'quest'}) do
                local row = {type = 999, leftText = 'native entity text'}
                assert(addon:GetEnglishTooltipLine({}, row, kind, 987653) == nil)
                assert(addon:GetLocalizedTooltipLine(row, kind, 987653, 'deDE', {}) == nil)
            end
            local row = {type = 44, spellID = 987999, leftText = 'native effect'}
            assert(addon:GetEnglishTooltipLine({}, row, 'item', 987653) == nil)
            assert(addon:GetLocalizedTooltipLine(row, 'item', 987653, 'deDE', {}) == nil)
        ''')

    def test_split_spell_list_does_not_match_native_names(self):
        self.lua.execute(b'''
            local first = {type = 34, leftText = 'native heading'}
            local second = {type = 34, leftText = 'native spell name'}
            local data = {lines = {first, second}}
            assert(addon:GetEnglishTooltipLine(data, first, 'spell', 987654) == nil)
            assert(addon:GetLocalizedTooltipLine(second, 'spell', 987654, 'deDE', data) == nil)
            second.type = 0
            assert(addon:GetEnglishTooltipLine(data, first, 'spell', 987654) == nil)
            assert(addon:GetLocalizedTooltipLine(first, 'spell', 987654, 'deDE', data) == nil)
        ''')

    def test_missing_capture_preserves_native_for_spells_and_items(self):
        self.lua.execute(b'''
            local spell = {type = 34, leftText = 'unrelated native text'}
            assert(addon:GetEnglishTooltipLine({lines = {spell}}, spell, 'spell', 987654) == nil)
            addon.englishTooltipFormats.ITEM_SPELL_TRIGGER_ONUSE = 'Use:'
            local effect = {type = 44, spellID = 987654, leftText = 'unrelated native effect'}
            assert(addon:GetEnglishTooltipLine({}, effect, 'item', 987653) == nil)
        ''')

    def test_talent_rendered_rows_do_not_inherit_types_from_text(self):
        self.lua.execute(b'''
            local function font(text)
                return {GetText = function() return text end, GetTextColor = function() return 1, 1, 1 end,
                    GetFont = function() return 'font', 12 end, GetTextScale = function() return 1 end,
                    SetFont = function() end, SetTextScale = function() end}
            end
            local sourceLines = {font('title'), font('duplicate'), font('duplicate'), font('different')}
            local source = {NumLines = function() return #sourceLines end,
                GetLeftLine = function(_, index) return sourceLines[index] end}
            local output = {}
            local tip = {AddLine = function(_, text) output[#output + 1] = text end,
                NumLines = function() return #output end, GetLeftLine = function() return font('') end}
            local seen = {}
            addon.TranslateLiveSpellDescription = function(_, id, locale, text)
                assert(id == 987654)
                seen[#seen + 1] = text
            end
            addon:FillEnglishTooltip({kind = 'talent', id = 987654, name = 'target title', tip = tip,
                source = source, data = {lines = {
                    {type = 13, leftText = 'title'},
                    {type = 34, leftText = 'duplicate'},
                    {type = 34, leftText = 'not rendered'},
                }}})
            assert(#seen > 0 and #output >= 4)
            assert(output[2] == 'duplicate' and output[3] == 'duplicate' and output[4] == 'different')
            for _, text in ipairs(seen) do assert(type(text) == 'string') end
        ''')


if __name__ == '__main__':
    unittest.main()
