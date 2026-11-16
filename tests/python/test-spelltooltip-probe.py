"""Check a sanitized native GetSpellDescription capture against available targets."""

import json

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata


fixture = json.loads((ROOT / 'tests/fixtures/spell-description-probe-70862.json').read_text())
client_strings = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())['strings']
assert fixture['product'] == 'wowf' and fixture['build'] == '1.60.1.70862'
assert fixture['sourceAPI'] == 'C_Spell.GetSpellDescription' and fixture['sourceLocale'] == 'frFR'
assert fixture['descriptions']['348779'] is False and fixture['descriptions']['1245130'] is False

lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
database = load_database(lua)
for key, values in client_strings.items():
    if values.get('frFR'):
        lua.globals()[key.encode()] = values['frFR'].encode()

lua.execute(b'''
canaccessallvalues = function() return true end
GetLocale = function() return "frFR" end
Enum = { TooltipDataLineType = { SpellName = 13, SpellDescription = 34 } }
local addon = {}
for _, path in ipairs({ "database/item-data.lua", "tooltips/english-tooltip-formats.lua", "tooltips/localized-tooltip-formats.lua",
    "database/localized-item-data.lua", "tooltips/spell-live-values.lua", "tooltips/tooltip-descriptions.lua" }) do
    assert(loadfile("ForeverRosettaStone/" .. path))("ForeverRosettaStone", addon)
end
ProbeAddon = addon
ResolveProbe = function(native, locale)
    return addon:GetLocalizedTooltipLine({ leftText = native, type = 34 }, "spell", 1238122, locale,
        { lines = { { type = 13 }, { type = 34 } } })
end
RenderProbe = function(native)
    local lines = {}
    local font = {
        GetFont = function() return "native", 12, "" end,
        GetTextScale = function() return 1 end,
        GetTextColor = function() return 1, 1, 1 end,
    }
    local tip = {
        AddLine = function(_, text) lines[#lines + 1] = text end,
        NumLines = function() return #lines end,
        GetLeftLine = function() return { SetFont = function() end, SetTextScale = function() end } end,
    }
    addon.GetTargetLocale = function() return "enUS" end
    addon:FillEnglishTooltip({ tip = tip, source = { GetLeftLine = function() return font end },
        kind = "spell", id = 1238122, name = "Spell", data = { lines = {
            { type = 13 }, { type = 34, leftText = native },
        } } })
    return lines
end
''')
addon = lua.globals().ProbeAddon
for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
    lua.execute(path.read_bytes(), b'ForeverRosettaStone', addon)


def get_details(locale):
    return database.GetSpellDetails(database, 1238122, locale)


native = fixture['descriptions']['1238122']
resolved, missing = [], []
for locale in sorted(database.GetLocales(database)):
    details = get_details(locale)
    template = details[b'description'] if details else None
    if not template:
        missing.append(locale.decode())
        continue

    result = lua.globals().ResolveProbe(native.encode(), locale)
    translated = result[0] if isinstance(result, tuple) else result
    if locale == b'frFR':
        assert translated == native.encode(), (locale, result)
    else:
        assert translated is None, (locale, result)
    resolved.append(locale.decode())

assert 'enUS' in resolved and 'frFR' in resolved
rendered = lua.globals().RenderProbe(native.encode())
assert rendered[2] == native.encode(), 'Unavailable structured values must preserve the native parent description'
assert rendered[3] == addon.GetIncompleteTranslationNotice(addon)
unexpected = native + 'Bondit derrière une cible adverse.'
result = lua.globals().ResolveProbe(unexpected.encode(), b'enUS')
translated = result[0] if isinstance(result, tuple) else result
assert translated is None, ('Unexpected visible child text must not be discarded', result)
rendered = lua.globals().RenderProbe(unexpected.encode())
assert rendered[2] == unexpected.encode(), 'The unmatched native text must remain visible'
assert rendered[3] == addon.GetIncompleteTranslationNotice(addon), 'Unmatched visible text must receive a warning'
print(f'PASS: captured parent description fallback for {len(resolved)} available targets; '
      f'{len(missing)} target descriptions missing; unexpected child text retained')
