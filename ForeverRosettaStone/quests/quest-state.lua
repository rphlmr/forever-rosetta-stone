local _, Addon = ...

local transitions = {
    open = {
        ["panel.close"] = { target = "collapsed" },
        ["focus.enter"] = { target = "reading" },
    },
    collapsed = {
        ["panel.open"] = { target = "open" },
        ["bookmark.focus"] = { target = "bookmarkFocused" },
    },
    bookmarkFocused = {
        ["panel.open"] = { target = "open", effect = "panel.focus" },
        ["bookmark.blur"] = { target = "collapsed" },
    },
    reading = {
        ["panel.close"] = { target = "collapsed" },
        ["focus.leave"] = { target = "open" },
    },
}

function Addon:CreateQuestState()
    return { mode = "unavailable" }
end

function Addon:TransitionQuestInteraction(current, event)
    if event.type == "reset" then
        return current.mode == "hidden" and current or { mode = "hidden" }
    end

    if event.type == "present" then
        local contexts = { gossip = true, greeting = true, detail = true, progress = true, reward = true }

        if not event.source or not contexts[event.context] or not self:IsReadableEntityID(event.questID) then
            return current
        end

        if current.source == event.source and current.questID == event.questID and current.context == event.context then
            return current
        end

        -- Without auto-open, a new NPC screen offers the bookmark until the reader is opened once.
        local mode = (event.autoOpen ~= false or current.mode == "visible") and "visible" or "dismissed"
        return { mode = mode, source = event.source, questID = event.questID, context = event.context }
    end

    if event.type == "dismiss" and current.mode == "visible" then
        return { mode = "dismissed", source = current.source, questID = current.questID, context = current.context }
    end

    return current
end

function Addon:IsPanelCollapsed()
    return self.current.mode == "collapsed" or self.current.mode == "bookmarkFocused"
end

-- Reading follows Blizzard's focus callbacks; it never captures controller buttons.
function Addon:Transition(current, event, questID)
    if event == "input.reset" then
        local modes = { reading = "open", bookmarkFocused = "collapsed" }
        return { mode = modes[current.mode] or current.mode, questID = current.questID }, "controller.reset"
    end

    if event == "map.close" then
        return self:CreateQuestState()
    end

    if event == "quest.select" then
        if not self:IsFeatureEnabled("questPanel") or type(questID) ~= "number" or questID <= 0 then
            return self:CreateQuestState()
        end

        if current.questID == questID then
            return current, "quest.refresh"
        end

        if current.mode == "reading" then return { mode = "reading", questID = questID } end
        if self:IsFeatureEnabled("questAutoOpen") or current.mode == "open" then
            return { mode = "open", questID = questID }
        end
        -- Without auto-open, a newly shown quest keeps the bookmark until the reader opens it.
        return { mode = current.mode == "bookmarkFocused" and "bookmarkFocused" or "collapsed", questID = questID }
    end

    if current.mode == "unavailable" then
        return current
    end

    local transition = transitions[current.mode][event]

    if transition then
        return { mode = transition.target, questID = current.questID }, transition.effect
    end

    return current
end
