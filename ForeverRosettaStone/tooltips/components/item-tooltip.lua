local _, Addon = ...

Addon:RegisterNameTooltipComponent({
    kind = "item",
    supportsFullText = true,
    placementProfiles = Addon.itemTooltipPlacements,
    GetPlacementContext = function(source)
        local spec = Addon.nameTooltips[source]
        local primary = spec and spec.group[1] or source
        if primary == ItemRefTooltip then return "chatLink" end
        local primarySpec = Addon.nameTooltips[primary]
        local getter = primarySpec and primarySpec.getterName
        if getter == "GetBagItem" then return "bag" end
        if getter == "GetInventoryItem" then return "equipment" end
        if getter == "GetAction" then return "actionBar" end
        return "default"
    end,
    SelectPlacementPolicy = function(source)
        local group = Addon.nameTooltips[source].group
        local context = Addon:GetTooltipComponent("item").GetPlacementContext(source)
        local mode = Addon:GetTooltipInputMode()
        for index = 2, #group do
            if group[index]:IsVisible() then return Addon.itemComparisonPlacements[context][mode] end
        end
        return Addon.itemTooltipPlacements[context][mode]
    end,
    AfterFill = function(spec, presentation) Addon:FillTooltipComparison(spec, presentation) end,
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetItemName(id, locale) end,
    ResolveData = function(_, data)
        if (data.type == Enum.TooltipDataType.Item or data.type == Enum.TooltipDataType.Toy)
            and Addon:IsReadableEntityID(data.id) then return data.id end
    end,
})
