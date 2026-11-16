local Addon, context = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

equal(Addon.StartBenchmark, nil, "release has no benchmark implementation")
equal(Addon.BenchmarkCommand, nil, "release has no benchmark command")
local previousLocale = Addon:GetTargetLocale()
SlashCmdList.FOREVERROSETTASTONE("bench start")
equal(Addon.benchmark, nil, "release command cannot start a capture")
equal(Addon:GetTargetLocale(), previousLocale, "release command preserves the language")
Addon.errorDialog.frame:Hide()
local runtimeMethods = {}
for _, name in ipairs({ "BeginBenchmarkSample", "EndBenchmarkSample", "StopBenchmark" }) do
    runtimeMethods[name] = Addon[name]
end
assert(loadfile("ForeverRosettaStone/diagnostics/dev-benchmark.lua"))("ForeverRosettaStone", Addon)

local now, clock, clockCalls, memoryCalls = 0, 0, 0, 0
local timers = {}
GetLocale = function() return "frFR" end
GetTime = function() return now end
GetBuildInfo = function() return "1.60.1", "70862", "date", 16001 end
debugprofilestop = function() clock = clock + 0.01; clockCalls = clockCalls + 1; return clock end
UpdateAddOnMemoryUsage = function() memoryCalls = memoryCalls + 1 end
GetAddOnMemoryUsage = function(name) assert(name == "ForeverRosettaStone"); return 100 + memoryCalls end
C_Timer.NewTimer = function(seconds, callback)
    local timer = { seconds = seconds, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end

equal(Addon:TransitionBenchmark("idle", "stop"), "idle", "idle refuses stop")
equal(Addon:TransitionBenchmark("idle", "report"), "idle", "idle has no report")
equal(Addon:TransitionBenchmark("idle", "start"), "recording", "start enters recording")
equal(Addon:TransitionBenchmark("recording", "start"), "recording", "duplicate start is refused")
equal(Addon:TransitionBenchmark("recording", "timeout"), "ready", "timeout finishes capture")
equal(Addon:TransitionBenchmark("ready", "stop"), "ready", "completed capture refuses another stop")
equal(Addon:BeginBenchmarkSample(), nil, "sampling is disabled by default")
equal(clockCalls, 0, "inactive sampling never reads the clock")
equal(memoryCalls, 0, "inactive benchmark never samples memory")

Addon:SetTargetLocale("frFR")
SlashCmdList.FOREVERROSETTASTONE("bench start")
equal(Addon.benchmark.state, "recording", "slash command starts capture")
equal(Addon:GetTargetLocale(), "enUS", "capture temporarily selects English")
equal(Addon.benchmark.clientLocale, "frFR", "capture retains the French client locale")
equal(timers[1].seconds, 90, "capture has a hard ninety-second limit")
local session = Addon.benchmark
equal(Addon:StartBenchmark(), false, "second start has no effects")
equal(Addon.benchmark, session, "second start preserves current samples")
equal(#timers, 1, "second start does not add a timer")
equal(session.previousLocale, "frFR", "second start cannot overwrite the original language")

context.tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
GameTooltip:Show()
context.tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 133)
GameTooltip:Show()
context.tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 999999999)
WorldMapFrame:Show()
QuestMapFrame.DetailsFrame:Show()
context.setSelected(399)
Addon:RefreshSelection()
equal(session.stats["item.lookup"].count > 0, true, "real item hovers record lookups")
equal(session.stats["item.tooltip"].count > 0, true, "item samples include native companion updates")
equal(session.stats["item.tooltip"].maxMs >= session.stats["item.lookup"].maxMs, true,
    "companion timing includes the underlying DB lookup")
equal(session.stats["spell.lookup"].count >= 2, true, "spell hits and misses are measured")
equal(session.stats["spell.tooltip"].count >= 2, true, "spell UI updates are measured")
equal(session.stats["quest.lookup"].count > 0, true, "quest DB lookups are measured")
equal(session.stats["quest.panel"].count > 0, true, "real quest panel refreshes are measured")

for index = 1, 200 do
    Addon:EndBenchmarkSample("bounded.test", index, Addon:BeginBenchmarkSample(), true)
end
equal(#session.samples, 128, "capture retains at most 128 raw samples")
equal(session.stats["bounded.test"].count, 200, "aggregates continue after sample cap")
now = 12
SlashCmdList.FOREVERROSETTASTONE("bench stop")
equal(Addon.benchmark.state, "ready", "stop produces a report")
equal(Addon:GetTargetLocale(), "frFR", "stop restores the previous translation language")
equal(timers[1].cancelled, true, "manual stop cancels the deadline")
equal(Addon.benchmark.stats, nil, "completed captures release sample tables")
local report = Addon.benchmark.report
equal(report:find("Client locale: frFR | Forever Rosetta Stone locale: enUS", 1, true) ~= nil, true, "report identifies both languages")
equal(report:find("Duration: 12.00 s", 1, true) ~= nil, true, "report records wall time")
equal(report:find("spell.lookup:", 1, true) ~= nil, true, "report includes operation aggregates")
equal(report:find("Page cache:", 1, true) ~= nil, true, "report includes native DB profiling")
equal(report:find("GameTooltip/manual", 1, true) ~= nil, true, "report identifies the native tooltip source")
equal(report:find("No forced GC.", 1, true) ~= nil, true, "report explains memory limitations")
context.flushTimers()
equal(Addon.errorDialog.frame:IsShown(), true, "stop opens the copyable report after chat completes")
equal(Addon.errorDialog.editBox:GetText(), report, "copyable dialog contains the full benchmark")
Addon.errorDialog.frame:Hide()
local calls = clockCalls
Addon:GetQuest(399)
context.tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 133)
equal(Addon:BeginBenchmarkSample(), nil, "completed captures disable sampling")
equal(clockCalls, calls, "normal UI and DB work read no profiling clocks after stop")
equal(Addon:StopBenchmark(), false, "double stop is harmless")

Addon:StartBenchmark()
local second = Addon.benchmark
timers[1].callback()
equal(Addon.benchmark, second, "old timeout cannot stop a later capture")
now = 102
timers[2].callback()
equal(Addon.benchmark.state, "ready", "deadline stops capture")
equal(Addon:GetTargetLocale(), "frFR", "deadline restores the language")
equal(Addon.benchmark.report:find("Stop reason: time limit", 1, true) ~= nil, true, "timeout reason is reported")

Addon:StartBenchmark()
Addon:SetTargetLocale("deDE")
equal(Addon.benchmark.state, "ready", "switching away from English stops capture")
equal(Addon:GetTargetLocale(), "deDE", "explicit language choice wins after restoration")
Addon:StartBenchmark()
Addon:Restart()
equal(Addon.benchmark.state, "ready", "reset stops capture")
equal(Addon:GetTargetLocale(), "deDE", "reset restores the previous language")
equal(Addon.lifecycle, "ready", "reset preserves addon operation")
Addon:StartBenchmark()
Addon:Suspend("benchmark test", "injected error")
equal(Addon.benchmark.state, "ready", "addon errors stop capture")
equal(Addon:GetTargetLocale(), "deDE", "addon errors restore the previous language")
equal(Addon:StartBenchmark(), false, "paused addons refuse new captures")
Addon:Restart()
equal(Addon.lifecycle, "ready", "addon recovers after captured error")
Addon:StartBenchmark()
for _, frame in ipairs(context.frames) do
    if frame.events.PLAYER_LOGOUT then frame:Fire("OnEvent", "PLAYER_LOGOUT") end
end
equal(Addon.benchmark.state, "ready", "logout stops capture before saved preferences are written")
equal(Addon:GetTargetLocale(), "deDE", "logout restores the previous language")
local current = Addon.benchmark
local snapshot = UpdateAddOnMemoryUsage
UpdateAddOnMemoryUsage = function() error("injected snapshot error") end
equal(pcall(Addon.StartBenchmark, Addon), false, "snapshot failure aborts capture setup")
equal(Addon.benchmark, current, "failed setup preserves the completed report")
equal(Addon:GetTargetLocale(), "deDE", "failed setup leaves the language unchanged")
UpdateAddOnMemoryUsage = snapshot
local refresh = Addon.RefreshFeatures
Addon.RefreshFeatures = function() error("injected startup refresh error") end
local started = Addon:StartBenchmark()
equal(started, false, "capture cannot report recording after a failed startup refresh")
equal(Addon.benchmark.state, "ready", "startup refresh error stops capture")
equal(Addon:GetTargetLocale(), "deDE", "startup refresh error restores the previous language")
Addon.RefreshFeatures = refresh
Addon:Restart()
equal(Addon.lifecycle, "ready", "addon recovers from a capture startup error")
Addon:SetTargetLocale("enUS")
GameTooltip:Hide()

for _, name in ipairs({ "TransitionBenchmark", "StartBenchmark", "ShowBenchmarkReport", "BenchmarkCommand" }) do
    Addon[name] = nil
end
for name, method in pairs(runtimeMethods) do Addon[name] = method end
Addon.benchmark = nil
return checks
