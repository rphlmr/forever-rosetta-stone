local Addon = { lifecycle = "ready" }
canaccessallvalues = function(value)
    return not (type(value) == "table" and value.restricted)
end
assert(loadfile("ForeverRosettaStone/diagnostics/diagnostics.lua"))("ForeverRosettaStone", Addon)
Addon.DebugText = function(_, key) return key end
Addon.ShowDebugConsole = function(self, report) self.report = report end
local calls = 0
C_TooltipInfo = { GetHyperlink = function(link)
    calls = calls + 1
    assert(link == "spell:430", "case and quoted arguments must be preserved")
    return { id = 430, lines = { { leftText = "Native API result" } } }
end }
Addon.GetCommandHelp = function() return "" end
assert(Addon.RunAPIProbe == nil, "release does not contain an API evaluator")
Addon:RunDebugCommand('dump C_TooltipInfo.GetHyperlink("spell:430")')
Addon:RunDebugCommand('/dump C_TooltipInfo.GetHyperlink("spell:430")')
assert(calls == 0, "release commands never evaluate Lua")
assert(loadfile("ForeverRosettaStone/diagnostics/dev-api-probe.lua"))("ForeverRosettaStone", Addon)
Addon:RunDebugCommand('dump C_TooltipInfo.GetHyperlink("spell:430")')
assert(calls == 1 and Addon.report:find("id = 430", 1, true))
assert(Addon.report:find("Native API result", 1, true))
assert(Addon.report:find("returnCount = 1", 1, true))
Addon:RunDebugCommand('/dump (function() return nil, false, 430, nil end)()')
assert(Addon.report:find("returnCount = 4", 1, true))
assert(Addon.report:find('type = "boolean"', 1, true) and Addon.report:find("value = false", 1, true))
local _, nilCount = Addon.report:gsub("<nil>", "")
assert(nilCount == 2, "both leading and trailing nil results must be preserved")
Addon:RunDebugCommand('dump (function() end)()')
assert(Addon.report:find("returnCount = 0", 1, true))
Addon:RunDebugCommand('dump C_TooltipInfo.GetHyperlink(')
assert(Addon.report:find("error =", 1, true) and calls == 1)
Addon:RunDebugCommand('dump MissingAPI()')
assert(Addon.report:find("error =", 1, true) and Addon.report:find("MissingAPI", 1, true))
assert(Addon.lifecycle == "ready", "an API experiment error must not suspend the addon")
ProbeResult = { restricted = true }
Addon:RunDebugCommand('dump ProbeResult')
assert(Addon.report:find('type = "restricted"', 1, true))
ProbeResult = {}; ProbeResult.self = ProbeResult
Addon:RunDebugCommand('dump ProbeResult')
assert(Addon.report:find("<cycle>", 1, true))
ProbeResult = {}; for index = 1, 101 do ProbeResult[index] = index end
Addon:RunDebugCommand('dump ProbeResult')
assert(Addon.report:find("101 = 101", 1, true) and not Addon.report:find("<truncated>", 1, true))
local long = string.rep("X", 600)
Addon:RunDebugCommand('dump "' .. long .. '"')
assert(Addon.report:find(long, 1, true), "console input and output must exceed chat length")
print("PASS: console API expressions, all return values, errors, long input and complete readable output")
