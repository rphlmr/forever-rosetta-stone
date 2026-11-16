local _, Addon = ...

Addon:RegisterNameTooltipComponent({
    kind = "minimapQuest",
    defaultContext = "minimap",
    GetName = function(id, locale)
        local quest = ForeverRosettaStoneDB:GetQuest(id, locale)
        return quest and quest.title
    end,
    ResolveData = function(_, data)
        if data.type ~= Enum.TooltipDataType.MinimapMouseover then return end
        for _, line in ipairs(data.lines or {}) do
            if Addon:IsReadableEntityID(line.questID) then
                return line.questID, line.leftColor
            end
        end
    end,
})
