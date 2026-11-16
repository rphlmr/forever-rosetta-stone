local _, Addon = ...

local function ReadableTable(value)
    return canaccessallvalues(value) and type(value) == "table"
end

local function FindGossipOption(frame)
    if not GossipFrame or not GossipFrame:IsShown() or not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    local options = C_GossipInfo.GetOptions()
    if not ReadableTable(options) then return end
    local row, id
    while frame and frame ~= GossipFrame do
        if frame:IsForbidden() then return end
        if not row then
            local element = frame.GetElementData and frame:GetElementData()
            local info = ReadableTable(element) and element.info
            local optionID = ReadableTable(info) and info.gossipOptionID
            local order = frame.GetID and frame:GetID()
            local text = frame.GetText and frame:GetText()
            -- Some client rows expose only a numeric element. Their button ID is
            -- orderIndex, not the option ID or the position in GetOptions().
            if canaccessallvalues(optionID, order, text) and not frame.questID
                and not (ReadableTable(info) and info.questID) then
                for _, option in ipairs(options) do
                    if ReadableTable(option) and Addon:IsReadableEntityID(option.gossipOptionID) then
                        local matches = optionID and optionID == option.gossipOptionID and info.name == option.name
                        if not optionID and type(order) == "number" and type(text) == "string" then
                            matches = order == option.orderIndex and text == option.name
                        end
                        if matches then
                            if row then return end
                            row, id = frame, option.gossipOptionID
                        end
                    end
                end
            end
        end
        frame = frame:GetParent()
    end
    if frame == GossipFrame then return row, id end
end

function Addon:UpdateGossipOptionTooltip()
    local tip, source, id = self.gossipOptionTooltip
    if not self:IsTooltipBlocked() and self:IsFeatureEnabled("gossipOptionTooltip")
        and not (self.questInteractionReader and self.questInteractionReader.frame:IsShown()) then
        source, id = self:GetTooltipFocus(FindGossipOption, GossipFrame)
    end
    local name = source and source:IsVisible() and ForeverRosettaStoneDB:GetGossipOptionName(id, self:GetTargetLocale())
    if source then self:RecordDebugSurface(source, "gossipOption", id, "gossip", nil, name) end
    if not name then
        if tip then tip:Hide() end
        return
    end
    if not tip then
        tip = self:CreateCompanionTooltip("ForeverRosettaStoneGossipOptionTooltip")
        self.gossipOptionTooltip = tip
    end
    tip:SetOwner(source, "ANCHOR_NONE")
    tip:ClearLines()
    self:SetStandaloneTooltipTitle(tip, name, 1, 0.82, 0)
    local policy = self:GetTooltipComponent("gossipOption").SelectPlacementPolicy(source)
    self:AnchorCompanionTooltip(tip, source, policy.GetSide(source))
    tip:SetClampedToScreen(true)
    tip:Show()
    self:PlaceCompanionTooltip(tip, source, nil, false, nil, policy)
end

Addon:RegisterNameTooltipComponent({
    kind = "gossipOption",
    defaultContext = "gossip",
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetGossipOptionName(id, locale) end,
    Update = function() Addon:UpdateGossipOptionTooltip() end,
    Hide = function()
        if Addon.gossipOptionTooltip then Addon.gossipOptionTooltip:Hide() end
    end,
})
