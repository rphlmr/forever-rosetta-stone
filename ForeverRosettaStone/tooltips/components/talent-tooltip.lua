local _, Addon = ...

local function GetTalentSpell(source)
    if source:IsForbidden() or not source.GetOwner then return end
    local owner = source:GetOwner()
    if owner and not owner:IsForbidden() and owner.talentFrame and owner.GetSpellID then
        local spellID = owner:GetSpellID()
        if Addon:IsReadableEntityID(spellID) then return spellID end
    end
end

Addon:RegisterNameTooltipComponent({
    kind = "talent",
    supportsFullText = true,
    defaultContext = "talentTree",
    placementProfiles = Addon.talentTooltipPlacements,
    GetName = function(spellID, locale) return ForeverRosettaStoneDB:GetSpellName(spellID, locale) end,
    ResolveData = function(source, data)
        local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
        if data.type == Enum.TooltipDataType.Spell and info
            and (info.getterName == "GetTalent" or info.getterName == "GetTraitEntry")
            and Addon:IsReadableEntityID(data.id) then return data.id end
        return GetTalentSpell(source)
    end,
    Install = function()
        EventRegistry:RegisterCallback("TalentDisplay.TooltipHook", function(_, button)
            if Addon.lifecycle ~= "ready" or button:IsForbidden() or not button.GetSpellID then return end
            Addon:Run("talent tooltip", function()
                local spellID = button:GetSpellID()
                if Addon:IsReadableEntityID(spellID) then Addon:UpdateNameTooltip(GameTooltip, "talent", spellID) end
            end)
        end, Addon)
    end,
})
