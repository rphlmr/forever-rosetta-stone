"""Exercise structured tooltip rows without matching their native text."""

import unittest

from lupa.lua51 import LuaRuntime


class IdOnlyRowTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        self.lua.execute(b'''
            canaccessallvalues = function() return true end
            GetLocale = function() return 'deDE' end
            Enum = {TooltipDataLineType = {ItemName = 22, SpellName = 13, FlavorText = 37,
                ItemSpellTriggerOnUse = 44, ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46}}
            targetLocale = 'frFR'
            item = {description = 'Target flavor', effects = {}}
            spell = {rank = 'Target rank'}
            ForeverRosettaStoneDB = {
                GetItemDetails = function() return item end,
                GetItemRules = function() return {effects = item.effects} end,
                GetSpellDetails = function() return spell end,
                GetSpellRules = function() return nil end,
                GetItemSourceDetails = function() error('Native item lookup') end,
                GetSpellSourceDetails = function() error('Native spell lookup') end,
            }
            addon = {itemTooltipLabels = {}, GetTargetLocale = function() return targetLocale end}
            addon.TranslateLiveTooltipLine = function() return nil end
            assert(loadfile('ForeverRosettaStone/tooltips/spell-live-values.lua'))('addon', addon)
            assert(loadfile('ForeverRosettaStone/tooltips/tooltip-descriptions.lua'))('addon', addon)
            local font = {GetText = function() return 'Native title' end,
                GetFont = function() return 'font', 12, '' end, GetTextScale = function() return 1 end,
                GetTextColor = function() return 1, 1, 1 end}
            local renderedFont = {SetFont = function() end, SetTextScale = function() end}
            render = function(kind, line)
                rows = {}
                local source = {GetLeftLine = function() return font end}
                if kind == 'talent' then
                    source.NumLines = function() return 1 end
                    source.GetRightLine = function() return {GetText = function() return line.rightText end,
                        GetTextColor = font.GetTextColor, GetFont = font.GetFont, GetTextScale = font.GetTextScale} end
                end
                local tip = {AddLine = function(_, left) rows[#rows + 1] = {left = left} end,
                    AddDoubleLine = function(_, left, right) rows[#rows + 1] = {left = left, right = right} end,
                    NumLines = function() return #rows end, GetLeftLine = function() return renderedFont end}
                local title = {type = kind == 'item' and 22 or 13, leftText = 'Native title',
                    rightText = kind ~= 'item' and line.rightText or nil}
                addon:FillEnglishTooltip({tip = tip, source = source, kind = kind, id = 123, name = 'Target title',
                    data = {lines = kind == 'item' and {title, line} or {title}}})
            end
        ''')

    def test_flavor_full_tooltip_and_missing_translation(self):
        self.lua.execute(b'''
            for _, locale in ipairs({'enUS', 'frFR'}) do
                targetLocale = locale
                render('item', {type = 37, leftText = 'Unrelated native flavor'})
                assert(rows[2].left == 'Target flavor')
                item.description = nil
                render('item', {type = 37, leftText = 'Unrelated native flavor'})
                assert(rows[2].left == 'Unrelated native flavor')
                item.description = 'Target flavor'
            end
        ''')

    def test_verified_spell_header_rank_and_unmapped_talent_rank(self):
        self.lua.execute(b'''
            for _, locale in ipairs({'enUS', 'frFR'}) do
                targetLocale = locale
                for _, kind in ipairs({'spell', 'talent'}) do
                    render(kind, {rightText = 'Unrelated native rank'})
                    assert(rows[1].right == (kind == 'spell' and 'Target rank' or 'Unrelated native rank'))
                    spell.rank = nil
                    render(kind, {rightText = 'Unrelated native rank'})
                    assert(rows[1].right == 'Unrelated native rank')
                    spell.rank = 'Target rank'
                end
                local line = {type = 13, rightText = 'Unrelated native rank'}
                local _, right = addon:GetLocalizedTooltipLine(line, 'talent', 123, locale)
                assert(right == 'Target rank')
            end
        ''')

    def test_untyped_rows_do_not_claim_a_rank(self):
        self.lua.execute(b'''
            ForeverRosettaStoneDB.GetSpellSourceDetails = function() return nil end
            local _, right = addon:GetLocalizedTooltipLine({type = 0, rightText = 'Native'}, 'spell', 123, 'frFR')
            assert(right == nil)
        ''')

    def test_effect_trigger_must_match_the_linked_spell(self):
        self.lua.execute(b'''
            addon.englishTooltipFormats = {ITEM_SPELL_TRIGGER_ONUSE = 'Use:',
                ITEM_SPELL_TRIGGER_ONEQUIP = 'Equip:', ITEM_SPELL_TRIGGER_ONPROC = 'Proc:'}
            addon.TranslateLiveSpellDescription = function(_, id, locale, native)
                assert(id == 456)
                assert(native == 'Native effect')
                return 'Target effect'
            end
            for key, value in pairs(addon.englishTooltipFormats) do _G[key] = value end
            for trigger = 0, 2 do
                item.effects = {{spellID = 456, triggerType = trigger}}
                local prefix = ({'Use:', 'Equip:', 'Proc:'})[trigger + 1]
                local row = {type = 44 + trigger, spellID = 456, leftText = prefix .. ' Native effect'}
                assert(addon:GetEnglishTooltipLine({}, row, 'item', 123) == prefix .. ' Target effect')
                row.type = 44 + ((trigger + 1) % 3)
                assert(addon:GetEnglishTooltipLine({}, row, 'item', 123) == nil)
                targetLocale = 'enUS'
                render('item', row)
                assert(rows[2].left == row.leftText)
                row.spellID = nil
                assert(addon:GetEnglishTooltipLine({}, row, 'item', 123) == nil)
                render('item', row)
                assert(rows[2].left == row.leftText)
                row.spellID, row.type = 456, 44 + trigger
                item.effects[2] = {spellID = 456, triggerType = trigger}
                render('item', row)
                assert(rows[2].left == row.leftText)
            end
        ''')


if __name__ == '__main__':
    unittest.main()
