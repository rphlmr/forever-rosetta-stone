"""Check hotfix values and preserve untyped live descriptions without matching them."""

import sys

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

spells = load_catalog(ROOT, 'spells')['catalogs']['spells']
lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
load_database(lua)
resolve = lua.execute(b'''
canaccessallvalues = function(...) return true end
GetLocale = function() return "enUS" end
Enum = {TooltipDataLineType = {SpellName = 13, SpellDescription = 34}}
ForeverRosettaStoneDB.GetSpellSourceDetails = function() error("Native text lookup must not run") end
local Addon = {}
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
return function(id, native)
    local line = {leftText = native}
    assert(Addon:GetLocalizedTooltipLine(line, "spell", id, "frFR") == nil,
        "Untyped hotfix text must not be used to select a translation")
    return Addon:GetEnglishTooltipLine({}, line, "spell", id)
end
''')

for damage, interval, duration, speed in ((60, 1, 6, 100), (73, 2, 9, 150)):
    native = (
        f'Tears the target apart from within for {duration} sec, inflicting {damage} Shadow damage every '
        f'{interval} sec. While channeling, your Siphon Life, Corruption, and Bane of Agony effects on '
        f'the target deal their periodic damage {speed}% faster.'
    )
    rendered, _ = resolve(1316697, native.encode())
    assert rendered == native.encode(), (rendered, native)

for bonus in (4, 8, 12):
    native = (
        'Increases the damage done or health drained by your Drain Life, Drain Soul, and Wrack spells '
        f'by {bonus}% per each of your Corruption, Siphon Life, and Bane of Agony effects active on the '
        f'target, up to a maximum increase of {bonus * 3}%.'
    )
    rendered, _ = resolve(17804, native.encode())
    assert rendered == native.encode(), (rendered, native)

wrack = spells['1316697']
assert 'enGB' not in wrack['locales']
assert 'periodic damage by $s2%' in wrack['locales']['enUS']['auraDescription']
assert 'sourceBuild' not in wrack['locales']['enUS']['translationMetadata']['fields']['description']
for locale in ('daDK', 'hrHR', 'svSE'):
    assert all(token in wrack['locales'][locale]['description'] for token in ('$d', '$s1', '$t', '$s2'))
    assert wrack['locales'][locale]['translationMetadata']['fields']['description']['origin'] == 'ai'

for spell_id, base in (('3110', 6), ('7799', 11), ('7800', 15), ('7801', 18)):
    assert spells[spell_id]['tooltipData']['effects'][0]['basePoints'] == base
    assert 'referenceUpdates' not in spells[spell_id]

print('PASS: hotfix values and untyped native damage, timing, speed, and three talent ranks')
