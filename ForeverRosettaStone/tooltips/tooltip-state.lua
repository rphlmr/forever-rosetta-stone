local _, Addon = ...

function Addon:CreateTooltipLifecycle(primary, visible)
    local sources = {}
    for source, shown in pairs(visible) do sources[source] = shown and "ready" or "hidden" end
    return { value = visible[primary] and "visible" or "hidden", primary = primary, sources = sources, ticket = 0 }
end

local function CopyState(state)
    local nextState = { value = state.value, primary = state.primary, ticket = state.ticket, sources = {} }
    for source, phase in pairs(state.sources) do nextState.sources[source] = phase end
    return nextState
end

local function BeginLayout(state, visible)
    state.ticket = state.ticket + 1
    if state.sources[state.primary] == "building" then
        state.value = "building"
        return state, {}
    end
    if not visible[state.primary] then
        state.value = "cleaning"
        return state, { { type = "cleanup", nativeCleared = true, clearIdentity = true } }
    end
    for source, phase in pairs(state.sources) do
        if phase == "building" and visible[source] then
            state.value = "building"
            return state, {}
        end
    end
    state.value = "rendering"
    return state, { { type = "render" } }
end

local function Schedule(state, effects)
    if state.value ~= "scheduled" then
        state.value, state.ticket = "scheduled", state.ticket + 1
        effects[#effects + 1] = { type = "schedule", ticket = state.ticket }
    end
    return state, effects
end

-- Native callbacks describe the source; only accepted transitions may render or restore frames.
function Addon:TransitionTooltipLifecycle(state, event)
    if event.type == "reset" and state.value ~= "cleaning" then
        local nextState = CopyState(state)
        nextState.value, nextState.ticket = "cleaning", nextState.ticket + 1
        return nextState, { { type = "cleanup", nativeCleared = false, clearIdentity = false } }
    end
    if state.value == "cleaning" then
        if event.type ~= "cleanup.complete" then return state, {} end
        local nextState = CopyState(state)
        nextState.value = "hidden"
        for source in pairs(nextState.sources) do nextState.sources[source] = "hidden" end
        return nextState, {}
    end
    if state.value == "rendering" then
        if event.type ~= "layout.complete" then return state, {} end
        local nextState = CopyState(state)
        if not event.visible[state.primary] then
            nextState.value = "cleaning"
            return nextState, { { type = "cleanup", nativeCleared = true, clearIdentity = true } }
        end
        nextState.value = "visible"
        return nextState, {}
    end

    if event.type == "native.clear" or event.type == "native.data" then
        local nextState = CopyState(state)
        nextState.sources[event.source] = "building"
        if nextState.value ~= "scheduled" then nextState.value = "building" end
        return nextState, { { type = event.type == "native.data" and "resolve.data" or "clear.source",
            source = event.source, data = event.data } }
    end
    if event.type == "native.hidden" then
        local nextState = CopyState(state)
        nextState.sources[event.source] = "hidden"
        if event.source == state.primary then
            nextState.value, nextState.ticket = "cleaning", nextState.ticket + 1
            return nextState, { { type = "cleanup", nativeCleared = true, clearIdentity = true } }
        end
        return Schedule(nextState, { { type = "clear.source", source = event.source } })
    end
    if event.type == "native.shown" then
        local nextState = CopyState(state)
        nextState.sources[event.source] = "ready"
        local effects = { { type = "resolve.owner", source = event.source } }
        if event.immediate then
            local rendered, layoutEffects = BeginLayout(nextState, event.visible)
            for _, effect in ipairs(layoutEffects) do effects[#effects + 1] = effect end
            return rendered, effects
        end
        return Schedule(nextState, effects)
    end
    if event.type == "layout.request" then return Schedule(CopyState(state), {}) end
    if event.type == "layout.now" then return BeginLayout(CopyState(state), event.visible) end
    if event.type == "layout.tick" and state.value == "scheduled" and event.ticket == state.ticket then
        return BeginLayout(CopyState(state), event.visible)
    end
    return state, {}
end
