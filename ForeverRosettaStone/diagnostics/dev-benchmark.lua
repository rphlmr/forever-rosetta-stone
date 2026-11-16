local addonName, Addon = ...

local transitions = {
    idle = { start = { target = "recording", effect = "start" } },
    recording = { stop = { target = "ready", effect = "stop" }, timeout = { target = "ready", effect = "stop" } },
    ready = { start = { target = "recording", effect = "start" }, report = { target = "ready", effect = "report" } },
}
local CAPTURE_SECONDS, SAMPLE_LIMIT = 90, 128

function Addon:TransitionBenchmark(state, event)
    local transition = transitions[state][event]

    if transition then return transition.target, transition.effect end

    return state
end

local function SnapshotMemory()
    UpdateAddOnMemoryUsage()
    return { addonKiB = GetAddOnMemoryUsage(addonName), luaKiB = collectgarbage("count") }
end

function Addon:BeginBenchmarkSample()
    if self.benchmark and self.benchmark.state == "recording" then return debugprofilestop() end
end

function Addon:EndBenchmarkSample(category, id, started, found, source)
    local session = self.benchmark

    if not started or not session or session.state ~= "recording" then return end

    local elapsed = debugprofilestop() - started
    local stats = session.stats[category]

    if not stats then
        stats = { count = 0, totalMs = 0, maxMs = 0, firstMs = elapsed, firstID = id }
        session.stats[category] = stats
    end

    stats.count, stats.totalMs = stats.count + 1, stats.totalMs + elapsed

    if elapsed >= stats.maxMs then stats.maxMs, stats.slowestID = elapsed, id end

    if #session.samples < SAMPLE_LIMIT then
        local info = source and source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
        local context = source and ((source:GetName() or "anonymous") .. "/" .. (info and info.getterName or "manual"))
        session.samples[#session.samples + 1] = { category, id, elapsed, found, context }
    end
end

local function FormatReport(session, ending, profile, reason)
    local lines = {
        "Forever Rosetta Stone benchmark",
        "Client locale: " .. session.clientLocale .. " | Forever Rosetta Stone locale: enUS",
        "Build: " .. session.build .. " | Addon: " .. session.version,
        "Catalog: " .. ForeverRosettaStoneDB.catalogVersion,
        string.format("Duration: %.2f s | Stop reason: %s", GetTime() - session.started, reason),
        string.format("Addon-attributed Lua memory: %.1f -> %.1f KiB (%+.1f)",
            session.memory.addonKiB, ending.addonKiB, ending.addonKiB - session.memory.addonKiB),
        string.format("Global Lua heap: %.1f -> %.1f KiB (%+.1f)",
            session.memory.luaKiB, ending.luaKiB, ending.luaKiB - session.memory.luaKiB),
        "Memory includes capture overhead; global heap includes other addons. No forced GC.",
        "TOC/client-side metadata memory is not included in addon Lua attribution.",
        string.format("Page cache: %d hits, %d misses | Native decodes: %d | CBOR bytes: %d",
            profile.pageHits, profile.pageMisses, profile.decodes, profile.decodedBytes),
        string.format("Decode totals: base64 %.3f ms | inflate %.3f ms | CBOR %.3f ms",
            profile.base64Ms, profile.inflateMs, profile.cborMs),
        "", "Timings: count | average us | max us (ID) | first observed us (ID)",
        "First observed does not necessarily mean cache-cold. UI timings are Lua updates, not GPU rendering.",
        "UI timings include their DB lookups; categories must not be summed.",
        "found: lookup/tooltip means catalog text available; layout means companion shown.",
    }
    local categories = {}

    for category in pairs(session.stats) do categories[#categories + 1] = category end

    table.sort(categories)

    for _, category in ipairs(categories) do
        local stats = session.stats[category]
        lines[#lines + 1] = string.format("%s: %d | %.2f | %.2f (%s) | %.2f (%s)", category, stats.count,
            stats.totalMs / stats.count * 1000, stats.maxMs * 1000, tostring(stats.slowestID),
            stats.firstMs * 1000, tostring(stats.firstID))
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Initial samples (maximum " .. SAMPLE_LIMIT .. "): category | ID | us | found | native frame/getter"

    for _, sample in ipairs(session.samples) do
        lines[#lines + 1] = string.format("%s | %s | %.2f | %s | %s", sample[1], tostring(sample[2]),
            sample[3] * 1000, tostring(sample[4]), sample[5] or "")
    end

    return table.concat(lines, "\n")
end

function Addon:StartBenchmark()
    if self.lifecycle ~= "ready" then return false, "reset the addon before starting a benchmark." end

    local state = self.benchmark and self.benchmark.state or "idle"
    local nextState, effect = self:TransitionBenchmark(state, "start")

    if not effect then return false, "a benchmark is already recording." end

    local _, build = GetBuildInfo()
    local session = { state = nextState, stats = {}, samples = {}, clientLocale = GetLocale(),
        build = tostring(build), version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "unknown",
        previousLocale = self:GetTargetLocale(), started = GetTime() }
    session.memory = SnapshotMemory()
    session.timer = C_Timer.NewTimer(CAPTURE_SECONDS, function()
        if self.benchmark == session then
            self:Run("benchmark timeout", self.StopBenchmark, self, "time limit", "timeout")
        end
    end)
    self.benchmark = session
    ForeverRosettaStoneDB:StartProfiling()
    self:SetTargetLocale("enUS")

    if self.benchmark ~= session or session.state ~= "recording" then
        return false, "capture stopped after an addon error; use /frs error for details."
    end

    print("Forever Rosetta Stone benchmark recording in English for up to 90 seconds. Hover items/spells and open quests; /frs bench stop ends capture.")

    return true
end

function Addon:StopBenchmark(reason, event)
    local session = self.benchmark

    if not session then return false end

    local nextState, effect = self:TransitionBenchmark(session.state, event or "stop")

    if not effect then return false end

    session.state = nextState
    session.timer:Cancel()
    local profile = ForeverRosettaStoneDB:StopProfiling()
    local ending = SnapshotMemory()
    local report = FormatReport(session, ending, profile, reason or "manual")
    self.benchmark = { state = nextState, report = report }
    self:SetTargetLocale(session.previousLocale)
    print("Forever Rosetta Stone benchmark stopped. Use /frs bench report to copy the results.")

    return true
end

function Addon:ShowBenchmarkReport()
    local state = self.benchmark and self.benchmark.state or "idle"
    local _, effect = self:TransitionBenchmark(state, "report")

    if effect then
        self:ShowDiagnosticReport("Benchmark report", self.benchmark.report)
    else
        print("Forever Rosetta Stone: stop a benchmark capture before opening its report.")
    end
end

function Addon:BenchmarkCommand(command)
    if command == "start" then
        local started, reason = self:StartBenchmark()
        if not started then print("Forever Rosetta Stone: " .. reason) end
    elseif command == "stop" then
        if self:StopBenchmark() then C_Timer.After(0, function() self:ShowBenchmarkReport() end) end
    elseif command == "report" then
        C_Timer.After(0, function() self:ShowBenchmarkReport() end)
    else
        print("Forever Rosetta Stone: /frs bench start | stop | report")
    end
end
