local _, Addon = ...

local function FindQuestBlock(frame)
    while frame do
        if frame:IsForbidden() then return end
        if QuestObjectiveTracker and frame.parentModule == QuestObjectiveTracker then
            if Addon:IsReadableEntityID(frame.id) then return frame, frame.id end
            return
        end
        frame = frame:GetParent()
    end
end

local function HasNativeTooltip(source)
    return not GameTooltip:IsForbidden() and GameTooltip:IsShown()
        and FindQuestBlock(GameTooltip:GetOwner()) == source
end

local function FillTooltip(tip, _, title, red, green, blue, spec)
    local quest = Addon:GetQuest(spec.id)
    if spec.standalone then Addon:SetStandaloneTooltipTitle(tip, title, red, green, blue)
    else Addon:SetCompanionTooltipTitle(tip, title, red, green, blue) end
    if Addon.preferences.tooltipCoverage == "name" then return end
    if C_QuestLog.IsComplete(spec.id) then
        local turnIn = Addon:GetQuestTurnInText(spec.id)
        if turnIn then tip:AddLine(turnIn, 1, 1, 1, true) end
    else
        for line in Addon:GetProgressText(spec.id):gmatch("[^\n]+") do tip:AddLine("- " .. line, 1, 1, 1, true) end
    end
end

function Addon:UpdateQuestTrackerTooltip()
    local tip = self.questTrackerTooltip
    local source, id
    if not self:IsTooltipBlocked() and self:IsFeatureEnabled("questTrackerTooltip") then
        source, id = self:GetTooltipFocus(FindQuestBlock, ObjectiveTrackerFrame)
    end
    local started = source and self:BeginBenchmarkSample()
    local quest = source and source:IsVisible() and self:GetQuest(id)
    if source then self:RecordDebugSurface(source, "questTracker", id, "tracker", nil, quest) end

    local title = quest and self:FormatQuestText(quest.title, id)
    if not title then
        if tip then
            self:ClearStackedTooltip(GameTooltip, false, tip)
            tip:Hide()
        end
        return
    end

    if not tip then
        tip = self:CreateCompanionTooltip("ForeverRosettaStoneQuestTrackerTooltip")
        self.questTrackerTooltip = tip
    end

    local readyForTurnIn = C_QuestLog.IsComplete(id)
    local progress = readyForTurnIn and "" or self:GetProgressText(id)
    local native = HasNativeTooltip(source)
    local key = id .. ":" .. self:GetTargetLocale() .. ":" .. tostring(readyForTurnIn) .. ":" .. progress
        .. ":" .. tostring(native)
    if not tip:IsShown() or not tip:IsOwned(source) or self.questTrackerTooltipKey ~= key then
        tip:SetOwner(source, "ANCHOR_NONE")
        tip:ClearLines()
        FillTooltip(tip, source, title, 1, 0.82, 0,
            { id = id, standalone = not native })
        self.questTrackerTooltipKey = key
    end

    if native and self:GetTooltipPresentation(GameTooltip) ~= "separate" then
        self:FillStackedTooltip(GameTooltip, tip, "tracker:" .. key .. ":" .. self.preferences.tooltipCoverage)
        return
    end
    local anchor = native and GameTooltip or source.poiButton or source
    local occupied = { self:GetTooltipRect(source), self:GetTooltipRect(anchor) }
    if not GameTooltip:IsForbidden() and GameTooltip:IsShown() then
        occupied[#occupied + 1] = self:GetTooltipRect(GameTooltip)
    end
    local policy = self:GetTooltipComponent("questTracker").SelectPlacementPolicy(source)
    self:AnchorCompanionTooltip(tip, anchor, policy.GetSide(anchor))
    tip:SetClampedToScreen(true)
    tip:Show()
    self:PlaceCompanionTooltip(tip, anchor, occupied, false, not native and source.HeaderText or nil, policy)
    self:EndBenchmarkSample("quest.tracker", id, started, tip:IsShown())
end

Addon:RegisterNameTooltipComponent({
    kind = "questTracker",
    defaultContext = "tracker",
    placementProfiles = Addon.questTrackerTooltipPlacements,
    GetPlacementContext = function(source) return HasNativeTooltip(source) and "tracker" or "standalone" end,
    FillTooltip = FillTooltip,
    GetName = function(id, locale)
        local quest = ForeverRosettaStoneDB:GetQuest(id, locale)
        return quest and quest.title
    end,
    Update = function() Addon:UpdateQuestTrackerTooltip() end,
    Hide = function()
        if Addon.questTrackerTooltip then Addon.questTrackerTooltip:Hide() end
        Addon.questTrackerTooltipKey = nil
    end,
})
