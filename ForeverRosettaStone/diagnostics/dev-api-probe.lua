local _, Addon = ...

-- Loaded only by local development manifests.
function Addon:RunAPIProbe(expression)
    local report = {
        expression = expression,
        limits = "All readable returned fields; no depth or field-count truncation; cycles, restricted values "
            .. "and opaque objects are marked. Hidden engine data is not enumerable.",
    }
    local chunk, reason = loadstring("return " .. expression, "=Forever Rosetta Stone API probe")
    if not chunk then
        report.error = reason
    else
        local function Pack(...) return { n = select("#", ...), ... } end
        local results = Pack(pcall(chunk))
        if not results[1] then
            report.error = results[2]
        else
            report.returnCount, report.values = results.n - 1, {}
            for index = 2, results.n do
                local value = results[index]
                if not canaccessallvalues(value) then
                    report.values[index - 1] = { type = "restricted", value = "<restricted>" }
                else
                    report.values[index - 1] = {
                        type = type(value), value = value == nil and "<nil>" or value,
                    }
                end
            end
        end
    end
    self:ShowDebugConsole(self:FormatDebugReport("Forever Rosetta Stone · API probe", report))
end

