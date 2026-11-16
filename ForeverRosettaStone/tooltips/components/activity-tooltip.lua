local _, Addon = ...

local function FindActivity(frame)
    local source, id
    while frame and frame ~= LFGListingFrame do
        if frame:IsForbidden() then return end
        local element = frame.GetElementData and frame:GetElementData()
        if not canaccessallvalues(element) then return end
        if type(element) == "table" and element.GetData then element = element:GetData() end
        if canaccessallvalues(element) and type(element) == "table" and canaccessallvalues(element.activityID)
            and Addon:IsReadableEntityID(element.activityID) and not id then source, id = frame, element.activityID end
        frame = frame:GetParent()
    end
    if frame == LFGListingFrame then return source, id end
end

Addon:RegisterNameTooltipComponent({
    kind = "activity",
    defaultContext = "groupFinder",
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetActivityName(id, locale) end,
    Update = function()
        local source, id
        if LFGListingFrame and LFGListingFrame:IsShown() and not Addon:IsTooltipBlocked()
            and Addon:IsFeatureEnabled("activityTooltip") then
            source, id = Addon:GetTooltipFocus(FindActivity, LFGListingFrame)
        end
        local name = id and ForeverRosettaStoneDB:GetActivityName(id, Addon:GetTargetLocale())
        local tip = Addon.activityTooltip
        if not name or not source:IsVisible() then
            if tip then tip:Hide() end
            return
        end
        if not tip then
            tip = Addon:CreateCompanionTooltip("ForeverRosettaStoneActivityTooltip")
            Addon.activityTooltip = tip
        end
        tip:SetOwner(source, "ANCHOR_NONE")
        tip:ClearLines()
        Addon:SetStandaloneTooltipTitle(tip, name, 1, 0.82, 0)
        local policy = Addon:GetTooltipComponent("activity").SelectPlacementPolicy(source)
        Addon:AnchorCompanionTooltip(tip, source, policy.GetSide(source))
        tip:SetClampedToScreen(true)
        tip:Show()
        Addon:PlaceCompanionTooltip(tip, source, nil, false, nil, policy)
    end,
    Hide = function() if Addon.activityTooltip then Addon.activityTooltip:Hide() end end,
})
