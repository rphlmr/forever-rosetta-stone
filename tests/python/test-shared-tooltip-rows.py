"""Captured shared labels must reach the whole-tooltip renderer, not just format helpers."""

import json
import re
import unittest

from lupa.lua51 import LuaRuntime
from database_harness import ROOT


class SharedTooltipRowsTests(unittest.TestCase):
    def load_all_tooltip_formats(self):
        lua = LuaRuntime(encoding=None)
        lua.execute(b'''
            canaccessallvalues = function() return true end
            GetLocale = function() return sourceLocale end
            Enum = {TooltipDataLineType = {ItemSpellTriggerOnEquip = 45}}
            addon = {itemTooltipLabels = {}, itemSubclasses = {}}
            ForeverRosettaStoneDB = {GetItemRules = function() return nil end}
        ''')
        addon = lua.globals().addon
        for name in ('database/item-data', 'tooltips/english-tooltip-formats',
                     'tooltips/localized-tooltip-formats', 'database/localized-item-data'):
            lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', addon)
        for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
            lua.execute(path.read_bytes(), b'addon', addon)
        for name in ('tooltips/tooltip-extra-formats', 'tooltips/item-stat-formats', 'tooltips/tooltip-descriptions'):
            lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', addon)
        return lua, addon

    def test_all_item_stat_formats_cover_every_supported_target(self):
        keys = json.loads((ROOT / 'tests/fixtures/item-stat-globalstring-keys.json').read_text())['requiredKeys']
        directions = json.loads((ROOT / 'tests/fixtures/item-stat-language-directions.json').read_text())
        _, addon = self.load_all_tooltip_formats()
        for locale in directions['targetLocales']:
            for key in keys:
                with self.subTest(locale=locale, key=key):
                    self.assertTrue(addon[b'tooltipFormatsByLocale'][locale.encode()][key.encode()])

    def test_every_official_source_to_every_target_keeps_values_and_stat_meaning(self):
        fixture = json.loads((ROOT / 'tests/fixtures/item-stat-language-directions.json').read_text())
        lua, addon = self.load_all_tooltip_formats()
        comma_locales = {'frFR', 'deDE', 'esES', 'esMX', 'itIT', 'ptBR', 'ruRU', 'ukUA',
                         'plPL', 'csCZ', 'daDK', 'svSE', 'hrHR', 'trTR'}
        def render(format, arguments, locale):
            def substitute(match):
                if match.group() == '%%': return '%'
                value = arguments[int(match[1]) - 1]
                text = f'{value:.{match[2]}f}' if match[2] else str(value)
                return text.replace('.', ',') if locale in comma_locales else text
            return re.sub(r'%(\d+)\$(?:\.(\d+))?[df]|%%', substitute, format)
        for source in fixture['officialSourceLocales']:
            lua.globals().sourceLocale = source.encode()
            lua.globals().DECIMAL_SEPERATOR = b',' if source in comma_locales else b'.'
            lua.globals().LARGE_NUMBER_SEPERATOR = b' '
            for case in fixture['cases']:
                lua.globals()[case['key'].encode()] = case['sourceFormats'][source].encode()
                native = render(case['sourceFormats'][source], case['arguments'], source)
                line = lua.table_from({b'type': 45, b'leftText': native.encode()})
                for target in fixture['targetLocales']:
                    with self.subTest(source=source, target=target, key=case['key']):
                        result = addon.GetLocalizedTooltipLine(addon, line, b'item', 987654, target.encode())
                        actual = result[0] if isinstance(result, tuple) else result
                        expected = render(case['targetFormats'][target], case['arguments'], target)
                        self.assertEqual(actual, expected.encode())

    def test_official_item_stat_format_family_has_no_missing_english_keys(self):
        fixture = json.loads((ROOT / 'tests/fixtures/item-stat-globalstring-keys.json').read_text())
        lua = LuaRuntime(encoding=None)
        addon = lua.table()
        lua.execute((ROOT / 'ForeverRosettaStone/tooltips/english-tooltip-formats.lua').read_bytes(), b'addon', addon)
        for key in fixture['requiredKeys']:
            with self.subTest(key=key):
                self.assertTrue(addon[b'englishTooltipFormats'][key.encode()], 'Missing official stat format: ' + key)

    def test_weapon_spell_power_stat_uses_shared_client_format(self):
        lua = LuaRuntime(encoding=None)
        lua.execute(b'''
            canaccessallvalues = function() return true end
            GetLocale = function() return 'frFR' end
            Enum = {TooltipDataLineType = {ItemSpellTriggerOnEquip = 45}}
            addon = {itemTooltipLabels = {}, itemSubclasses = {}}
            ForeverRosettaStoneDB = {GetItemRules = function() return nil end}
        ''')
        addon = lua.globals().addon
        for name in ('tooltips/english-tooltip-formats', 'tooltips/localized-tooltip-formats',
                     'tooltips/tooltip-descriptions'):
            lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', addon)
        lua.globals().TOOLTIP_ITEM_STAT_SPELL_POWER_INCREASE = (
            'Équipé : augmente les dégâts et les soins des sorts et effets magiques de %1$d au maximum.'.encode())
        for line_type in (0, 45):
            for item_id, amount in ((11287, 1), (11288, 2), (987654, 73)):
                native = f'Équipé : augmente les dégâts et les soins des sorts et effets magiques de {amount} au maximum.'
                line = lua.table_from({b'type': line_type, b'leftText': native.encode()})
                result = addon.GetEnglishTooltipLine(addon, lua.table(), line, b'item', item_id)
                actual = result[0] if isinstance(result, tuple) else result
                self.assertEqual(actual, f'Equip: Increases damage and healing done by magical spells and effects by up to {amount}.'.encode())

    def test_captured_equipment_and_spell_labels_translate(self):
        lua = LuaRuntime(encoding=None)
        lua.execute(b'''
            canaccessallvalues = function() return true end
            GetLocale = function() return 'frFR' end
            Enum = {TooltipDataLineType = {EquipSlot = 21, SpellDescription = 34, SpellName = 13}}
            ForeverRosettaStoneDB = {GetItemRules = function() return nil end}
            addon = {}
        ''')
        addon = lua.globals().addon
        for name in ('database/item-data', 'tooltips/english-tooltip-formats',
                     'tooltips/localized-tooltip-formats', 'database/localized-item-data',
                     'tooltips/tooltip-descriptions'):
            lua.execute((ROOT / ('ForeverRosettaStone/' + name + '.lua')).read_bytes(), b'addon', addon)
        fixture = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())
        for key, values in fixture['strings'].items():
            lua.globals()[key.encode()] = values['frFR'].encode()
        for kind, native, expected in (
            ('item', 'Jambes', 'Legs'), ('item', 'Armure : 37', '37 Armor'),
            ('item', 'Durabilité 35 / 35', 'Durability 35 / 35'),
            ('spell', 'portée de 8-35 m.', '8-35 yd range'),
            ('spell', '1,6 s de recharge', '1.6 sec cooldown'),
            ('item', 'Vitesse 1,90', 'Speed 1.90'),
        ):
            with self.subTest(kind=kind, native=native):
                line = lua.table_from({b'type': 0, b'leftText': native.encode()})
                actual = addon.GetLocalizedTooltipLine(addon, line, kind.encode(), 1, b'enUS')
                self.assertEqual(actual[0] if isinstance(actual, tuple) else actual, expected.encode())


if __name__ == '__main__':
    unittest.main()
