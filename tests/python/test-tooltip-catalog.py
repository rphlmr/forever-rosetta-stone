"""Exercise conditional tooltips against the shipped database, not miniature spell fixtures."""

import sys

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

lua = LuaRuntime(encoding=None)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
load_database(lua)
lua.execute(b'''
canaccessallvalues = function(...) return true end
GetLocale = function() return "frFR" end
local known = { [668] = true, [672] = true, [9078] = true, [9077] = true }
C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end }
local Addon = {}
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
Addon.itemTooltipLabels = {}
Enum = { TooltipDataLineType = { SpellName = 13, SpellDescription = 34 } }
assert(ForeverRosettaStoneDB:GetSpellName(1293657, "enUS") == "Languages")
assert(loadfile("ForeverRosettaStone/tooltips/client-labels.lua"))("ForeverRosettaStone", Addon)
CheckCapturedDescription = function(id, native, english, locale)
    GetLocale = function() return locale end
    local translated = Addon:GetEnglishTooltipLine({ lines = { { type = 34 } } },
        { leftText = native, type = 34 }, "spell", id)
    -- Catalog escape sequences represent paragraph boundaries, not spaces.
    english = english:gsub("\\r\\n", "\\n"):gsub("\\r", "\\n")
        :gsub("[ \\t]+", " "):gsub(" *\\n *", "\\n"):gsub("^%s+", ""):gsub("%s+$", "")
    assert(translated == english, "Catalog capture failed for spell " .. id .. " from " .. locale
        .. ": " .. tostring(translated) .. " ~= " .. english)
end
CheckMissingCapturedDescription = function()
    local row = {type=34,leftText="Unrecognized native description 149"}
    assert(Addon:GetEnglishTooltipLine({}, row, "spell", 970) == nil)
    local value, _, incomplete = Addon:GetLocalizedTooltipLine(row, "spell", 970, "deDE")
    assert(value == nil and incomplete)
end
''')
# Native text retained from the equipped build-70938 campaign profile.
lua.globals().CheckCapturedDescription(
    970, "Un mot des ténèbres qui inflige 149 points de dégâts d'Ombre en 21 sec.".encode(),
    b'A word of darkness that causes 149 Shadow damage over 21 sec.', b'frFR')
lua.globals().CheckMissingCapturedDescription()
spells = load_catalog(ROOT, 'spells')['catalogs']['spells']
checked = 0

for spell_id, spell in spells.items():
    locales = spell.get('locales', {})
    english = locales.get('enUS', {}).get('description')
    if not english or '$' in english:
        continue

    for locale, record in locales.items():
        native = record.get('description')
        origin = record.get('translationMetadata', {}).get('fields', {}).get('description', {}).get('origin')
        if locale == 'enUS' or origin != 'original' or not native or '$' in native:
            continue

        lua.globals().CheckCapturedDescription(int(spell_id), native.encode(), english.encode(), locale.encode())
        checked += 1

print(f'PASS: {checked} original localized literal spell templates through native capture; no static fallback')
assert checked > 0, 'The catalog scan must exercise real descriptions'
print('PASS: shipped titles and original catalog descriptions use the live engine')
