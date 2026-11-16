local _, Addon = ...

local function CaptureAppearance(source, appearanceData)
    if Addon.lifecycle ~= "ready" or not source or source:IsForbidden() or not Addon.nameTooltips[source]
        or not canaccessallvalues(appearanceData) or type(appearanceData) ~= "table" then return end
    local sources = appearanceData.sources
    if type(sources) ~= "table" or #sources == 0 then return end
    local index = appearanceData.selectedIndex
        and CollectionWardrobeUtil.GetValidIndexForNumSources(appearanceData.selectedIndex, #sources)
        or CollectionWardrobeUtil.GetDefaultSourceIndex(sources, appearanceData.primarySourceID)
    local entry = sources[index]
    -- Hidden visuals have no backing item and must not borrow another source's name.
    for _, candidate in ipairs(sources) do if candidate.isHideVisual then return end end
    local info = entry and C_TransmogCollection.GetSourceInfo(entry.sourceID)
    local itemID = info and info.itemID
    if not Addon:IsReadableEntityID(itemID) then return end
    Addon:ClearStackedTooltip(source)
    local lines = {}
    for lineIndex = 1, source:NumLines() do
        local left, right = source:GetLeftLine(lineIndex), source:GetRightLine(lineIndex)
        local leftText, rightText = left and left:GetText(), right and right:GetText()
        if not canaccessallvalues(leftText, rightText) then return end
        lines[#lines + 1] = {lineIndex = lineIndex, leftText = leftText, rightText = rightText,
            type = lineIndex == 1 and Enum.TooltipDataLineType.ItemName or 0}
    end
    Addon.nameTooltips[source].data = {type = Enum.TooltipDataType.Item, id = itemID, lines = lines}
    Addon:UpdateNameTooltip(source, "appearance", itemID)
end

Addon:RegisterNameTooltipComponent({
    kind = "appearance",
    defaultContext = "collection",
    supportsFullText = true,
    GetName = function(id, locale)
        return ForeverRosettaStoneDB:GetItemName(id, locale)
    end,
    Install = function()
        local appearanceHooked
        local function InstallHooks()
            if not appearanceHooked and CollectionWardrobeUtil and CollectionWardrobeUtil.SetAppearanceTooltip then
                hooksecurefunc(CollectionWardrobeUtil, "SetAppearanceTooltip", function(source, data)
                    Addon:Run("appearance tooltip", CaptureAppearance, source, data)
                end)
                appearanceHooked = true
            end
            return appearanceHooked
        end
        if InstallHooks() then return end
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(frame)
            if InstallHooks() then frame:UnregisterAllEvents() end
        end)
    end,
})

Addon:RegisterNameTooltipComponent({
    kind = "appearanceSlot",
    defaultContext = "collection",
    GetName = function(key, locale) return Addon:GetClientLabel(key, locale) end,
    Install = function()
        -- XML copies mixin methods onto buttons before ADDON_LOADED. Hook the native
        -- tooltip setter so already-created and subsequently pooled buttons are covered.
        hooksecurefunc(GameTooltip, "SetText", function(source, text)
            if Addon.lifecycle ~= "ready" or Addon.tooltipRendering or source:IsForbidden()
                or not WardrobeCollectionFrame or not canaccessallvalues(text) then return end
            local owner = source:GetOwner()
            if not owner or owner:IsForbidden() then return end
            local key = owner.slot
            if not canaccessallvalues(key) or type(key) ~= "string" then return end
            local frame = owner
            while frame and frame ~= WardrobeCollectionFrame do
                if frame:IsForbidden() then return end
                frame = frame:GetParent()
            end
            if frame ~= WardrobeCollectionFrame then return end
            local native = _G[key]
            if not canaccessallvalues(native) or native ~= text then return end
            Addon:Run("appearance category tooltip", Addon.UpdateNameTooltip, Addon,
                source, "appearanceSlot", key)
        end)
    end,
})
