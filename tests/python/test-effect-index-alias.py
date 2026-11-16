"""Verify default-effect binding against the retained Russian spell template."""

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata


lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
load_database(lua)
resolve = lua.execute(b'''
canaccessallvalues = function() return true end
GetLocale = function() return "ruRU" end
DECIMAL_SEPERATOR, LARGE_NUMBER_SEPERATOR = ",", ""
Enum = { TooltipDataLineType = {} }
local addon = {}
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", addon)
local source = ForeverRosettaStoneDB:GetSpellDetails(18126, "ruRU")
local target = ForeverRosettaStoneDB:GetSpellDetails(18126, "enUS")
assert(source and source.description and source.description:find("$/1000;S", 1, true))
assert(target and target.description and target.description:find("$/1000;S1", 1, true))
return function(native)
    return addon:GetLocalizedTooltipLine({ leftText = native }, "spell", 18126, "enUS")
end
''')

for native_value, expected_value in (('0,5', '0.5'), ('2', '2')):
    native = f'Уменьшение времени наложения заклинания беса "Огненная стрела" на {native_value} сек.'
    expected = f"Reduces the casting time of your Imp's Firebolt spell by {expected_value} sec."
    result = resolve(native.encode())
    translated = result[0] if isinstance(result, tuple) else result
    assert translated is None, (native, expected, result)

print('PASS: real ruRU spell 18126 does not bind effect values from untyped native text')
