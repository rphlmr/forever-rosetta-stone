local Addon = {}
local loader, statHook
CreateFrame = function()
    loader = {
        RegisterEvent = function() end,
        SetScript = function(self, _, callback) self.callback = callback end,
        UnregisterAllEvents = function(self) self.unregistered = true end,
    }
    return loader
end
canaccessallvalues = function(value) return value ~= "secret" end
date = function() return "test" end
GetTime = function() return 1 end
GetLocale = function() return "frFR" end
hooksecurefunc = function(name, callback)
    assert(name == "PaperDollFrame_SetLabelAndText")
    assert(not statHook, "install only once")
    statHook = callback
end
local function Text(value)
    return { GetText = function() return value end, GetTextColor = function() return 1, 1, 0 end }
end
GameTooltip = {
    IsForbidden = function() return false end,
    IsShown = function() return true end,
    IsOwned = function(self, frame) return self.owner == frame end,
    GetName = function() return "GameTooltip" end,
    NumLines = function() return 1 end,
    GetLeftLine = function() return Text("Live resistance explanation 25") end,
    GetRightLine = function() return Text(nil) end,
}
assert(loadfile("ForeverRosettaStone/diagnostics/dev-debug.lua"))("ForeverRosettaStone", Addon)
loader:callback("ADDON_LOADED", "ForeverRosettaStone")
assert(not loader.unregistered, "wait for late-loaded character UI")
PaperDollFrame_SetLabelAndText = function() end
loader:callback("ADDON_LOADED", "Blizzard_UIPanels_Game")
assert(loader.unregistered and statHook)
local function Row(label)
    return {
        Label = Text(label), Value = Text("25"), numericValue = 25,
        tooltip = "Resistance 25", tooltip2 = "secret", tooltip3 = "Extra explanation",
        IsForbidden = function() return false end,
        GetName = function() return nil end,
        HookScript = function(self, event, callback)
            assert(event == "OnEnter" and not self.hover, "hook each pooled row once")
            self.hover = callback
        end,
    }
end
local row = Row("Résistance au feu")
statHook(row)
statHook(row)
local session = ForeverRosettaStoneDevTrace.sessions[1]
row:hover()
assert(#session.events == 0, "ignore tooltips owned by another frame")
GameTooltip.owner = row
row:hover()
local entry = session.events[1]
assert(entry.event == "character.stat.hover" and entry.label == "Résistance au feu")
assert(entry.numericValue == 25 and entry.locale == "frFR")
assert(entry.tooltip2 == "<restricted>" and entry.tooltip3 == "Extra explanation")
assert(entry.nativeLines[1].left == "Live resistance explanation 25")
assert(entry.nativeLines[1].leftColor[3] == 0)
row.Label = Text("Dégâts")
row.tooltip = nil
row:hover()
assert(session.events[2].label == "Dégâts", "read current pooled row and specialized tooltip output")
for _ = 3, 12001 do row:hover() end
assert(#session.events == 12000 and session.truncated and session.droppedEvents == 1)
assert(not session.traceError)
print("PASS: stat hover capture, late loading, pooled rows, resistance, rendered text, restricted values, trace limit")
