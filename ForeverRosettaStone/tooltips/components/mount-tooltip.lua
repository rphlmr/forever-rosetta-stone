local _, Addon = ...

Addon:RegisterNameTooltipComponent({
    kind = "mount",
    supportsFullText = true,
    defaultContext = "collection",
    GetName = function(spellID, locale) return ForeverRosettaStoneDB:GetSpellName(spellID, locale) end,
    ResolveData = function(source)
        local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
        if canaccessallvalues(info) and type(info) == "table" and info.getterName == "GetMountBySpellID"
            and canaccessallvalues(info.getterArgs) and type(info.getterArgs) == "table" then
            local spellID = info.getterArgs[1]
            if Addon:IsReadableEntityID(spellID) then return spellID end
        end
    end,
})
