"""Exercise active aura text capture, ID boundaries and ancillary rows against built catalogs."""

import unittest

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata


class StructuredAuraTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        install_metadata(self.lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        load_database(self.lua)
        self.lua.execute(b'''
            canaccessallvalues = function(...)
                for index = 1, select('#', ...) do
                    local value = select(index, ...)
                    if type(value) == 'table' and value.secret then return false end
                end
                return true
            end
            sourceLocale, targetLocale, now, tooltipUnit = 'enUS', 'frFR', 100, 'player'
            GetLocale = function() return sourceLocale end
            GetTime = function() return now end
            Enum = {TooltipDataType = {Spell = 1, UnitAura = 7}, TooltipDataLineType = {SpellName = 13}}
            addon = {itemTooltipLabels = {}}
            addon.RegisterNameTooltipComponent = function() end
            addon.IsReadableEntityID = function(_, value)
                return type(value) == 'number' and value > 0
            end
            addon.GetTargetLocale = function() return targetLocale end
            for _, path in ipairs({'tooltips/english-tooltip-formats.lua', 'tooltips/localized-tooltip-formats.lua',
                'database/localized-item-data.lua'}) do
                assert(loadfile('ForeverRosettaStone/' .. path))('addon', addon)
            end
            for _, locale in ipairs({'cs-cz', 'da-dk', 'hr-hr', 'it-it', 'pl-pl', 'sv-se', 'tr-tr', 'uk-ua'}) do
                assert(loadfile('ForeverRosettaStone/locales/tooltips/' .. locale .. '.lua'))('addon', addon)
            end
            for _, path in ipairs({'tooltips/tooltip-extra-formats.lua', 'tooltips/spell-live-values.lua',
                'tooltips/tooltip-descriptions.lua', 'tooltips/components/spell-tooltip.lua'}) do
                assert(loadfile('ForeverRosettaStone/' .. path))('addon', addon)
            end
            aura = {spellId = 1243, points = {4}, dispelName = 'Magic', expirationTime = 3160, timeMod = 1}
            C_UnitAuras = {GetAuraDataByIndex = function() return aura end}
            local font = {
                GetFont = function() return 'native', 12, '' end,
                GetTextScale = function() return 1 end,
                GetTextColor = function() return 1, 0.82, 0 end,
            }
            local rowFont = {SetFont = function() end, SetTextScale = function() end}
            local source = {
                GetProcessingTooltipInfo = function()
                    return {getterName = 'GetUnitBuff', getterArgs = {tooltipUnit, 1}}
                end,
                GetLeftLine = function() return font end,
            }
            render = function(id, nativeLines)
                rows = {}
                local tip = {
                    AddLine = function(_, left) rows[#rows + 1] = {left = left} end,
                    AddDoubleLine = function(_, left, right) rows[#rows + 1] = {left = left, right = right} end,
                    NumLines = function() return #rows end,
                    GetLeftLine = function() return rowFont end,
                }
                addon:FillEnglishTooltip({source = source, tip = tip, kind = 'spell', id = id,
                    name = ForeverRosettaStoneDB:GetSpellName(id, targetLocale),
                    data = {type = 7, lines = nativeLines or {
                        {type = 13, leftText = 'Unrecognizable native title', rightText = 'Unknown dispel label'},
                        {leftText = 'Unrecognizable native description 999.'},
                        {leftText = 'Unrecognizable native timer 999.'},
                    }}})
                return rows
            end
        ''')

    def test_food_aura_translation_is_complete_without_live_points(self):
        # Food 433 models the screenshot wording; its actual screenshot ID is unknown.
        self.lua.execute('''
            sourceLocale, targetLocale = 'frFR', 'enUS'
            aura = {spellId=433, name='Nourriture', points={}, expirationTime=108, timeMod=1}
            render(433, {
                {type=0,lineIndex=1,leftText='Nourriture'},
                {type=0,lineIndex=2,leftText='Rend 2 points de vie par seconde.'},
                {type=0,lineIndex=3,leftText='8 secondes restantes'},
            })
            assert(#rows==3 and rows[1].left=='Food')
            assert(rows[2].left=='Restores 2 health per second.')
            assert(rows[3].left=='8 seconds remaining')
        '''.encode())

    def test_text_amounts_override_missing_or_stale_points(self):
        self.lua.execute(b'''
            for _, points in ipairs({{}, {999}, {secret=true}}) do
                aura.points=points
                render(1243, {
                    {type=13,leftText='Power Word: Fortitude'},
                    {leftText='Increases Stamina by 6.'},
                })
                assert(#rows==2 and rows[2].left:find('6',1,true))
                assert(not rows[2].left:find('999',1,true))
            end
        ''')

    def test_every_target_locale_uses_its_catalog_aura_template(self):
        self.lua.execute(b'''
            aura={spellId=433,points={}}
            for locale in pairs(ForeverRosettaStoneDB:GetLocales()) do
                targetLocale=locale
                render(433, {{type=13,leftText='Food'}, {leftText='Restores 2 health per second.'}})
                local target=ForeverRosettaStoneDB:GetSpellDetails(433,locale).auraDescription
                local expected=target:gsub('%$/5;s1','2')
                assert(#rows==2 and rows[2].left==expected,locale..': '..tostring(rows[2].left))
            end
        ''')

    def test_native_mismatch_and_unknown_values_are_incomplete(self):
        self.lua.execute(b'''
            for _, text in ipairs({'Unknown native wording 6.','Increases Stamina by unknown.'}) do
                render(1243, {{type=13,leftText='Title'}, {leftText=text}})
                assert(#rows==3 and rows[2].left==text)
                assert(rows[3].left=='Some lines are not translated yet.')
            end
        ''')

    def test_timers_translate_without_recomputing_expiration(self):
        self.lua.execute(b'''
            aura.expirationTime={secret=true}
            render(1243, {{type=13,leftText='Title'}, {leftText='Increases Stamina by 4.'},
                {leftText='51 minutes remaining'}})
            assert(#rows==3 and rows[3].left=='51 minutes restantes')
            render(1243, {{type=13,leftText='Title'}, {leftText='Increases Stamina by 4.'},
                {leftText='13 |4second:seconds; remaining'}})
            assert(#rows==3 and rows[3].left=='13 secondes restantes')
        ''')

    def test_native_description_gap_before_timer_is_preserved(self):
        self.lua.execute(r'''
            sourceLocale, targetLocale = 'frFR', 'enUS'
            aura = {spellId=1229741, name='Avantages du camp'}
            local body='Obtention des avantages de camp suivants :\n\nBougie d’encens : Intelligence augmentée de 2.'
            local expected='Gained the following camp benefits:\n\nIncense Candle: Intellect increased by 2.'
            for _, gap in ipairs({'\n\n', '\r\n\r\n', ''}) do
                render(1229741, {
                    {type=13,leftText='Avantages du camp'},
                    {leftText=body..gap},
                    {leftText='45 minutes restantes'},
                })
                local padding=gap~='' and '\n\n' or ''
                assert(#rows==3 and rows[2].left==expected..padding)
                assert(rows[3].left=='45 minutes remaining')
            end
        '''.encode())


if __name__ == '__main__':
    unittest.main()
