local _, Addon = ...

local function FindQuestOffer(frame)
    local row, id = frame
    while frame and frame ~= GossipFrame do
        if frame:IsForbidden() then return end
        if not id then
            local element = frame.GetElementData and frame:GetElementData()
            local info = canaccessallvalues(element) and type(element) == "table" and element.info
            id = frame.questID or (canaccessallvalues(info) and type(info) == "table" and info.questID)
            if id then row = frame end
        end
        frame = frame:GetParent()
    end
    if GossipFrame and frame == GossipFrame and Addon:IsReadableEntityID(id) then return row, id end
end

function Addon:UpdateQuestOfferTooltip()
    local tip, source, id = self.questOfferTooltip

    if self.questInteractionReader and self.questInteractionReader.frame:IsShown() then
        if tip then tip:Hide() end
        return
    end

    if not self:IsTooltipBlocked() and self:IsFeatureEnabled("questOfferTooltip") then
        source, id = self:GetTooltipFocus(FindQuestOffer, GossipFrame)
    end
    local started = source and self:BeginBenchmarkSample()
    local quest = source and source:IsVisible() and self:GetQuest(id)
    if source then self:RecordDebugSurface(source, "questOffer", id, "gossip", nil, quest) end

    local title = quest and self:FormatQuestText(quest.title, id)
    if not title then
        if tip then tip:Hide() end
        return
    end

    if not tip then
        tip = self:CreateCompanionTooltip("ForeverRosettaStoneQuestOfferTooltip")
        self.questOfferTooltip = tip
    end

    tip:SetOwner(source, "ANCHOR_NONE")
    tip:ClearLines()
    self:SetStandaloneTooltipTitle(tip, title, 1, 0.82, 0)
    self:ApplyTooltipTranslationFont(tip, self:GetTargetLocale())
    local policy = self:GetTooltipComponent("questOffer").SelectPlacementPolicy(source)
    self:AnchorCompanionTooltip(tip, source, policy.GetSide(source))
    tip:SetClampedToScreen(true)
    tip:Show()
    self:PlaceCompanionTooltip(tip, source, nil, false, nil, policy)
    self:EndBenchmarkSample("quest.offer", id, started, tip:IsShown())
end

Addon:RegisterNameTooltipComponent({
    kind = "questOffer",
    defaultContext = "gossip",
    GetName = function(id, locale)
        local quest = ForeverRosettaStoneDB:GetQuest(id, locale)
        return quest and quest.title
    end,
    Update = function() Addon:UpdateQuestOfferTooltip() end,
    Hide = function()
        if Addon.questOfferTooltip then Addon.questOfferTooltip:Hide() end
    end,
})
