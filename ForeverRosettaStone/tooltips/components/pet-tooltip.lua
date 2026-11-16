local _, Addon = ...

Addon:RegisterNameTooltipComponent({
    kind = "pet",
    defaultContext = "collection",
    supportsFullText = true,
    GetName = function(speciesID, locale)
        local spellID = type(speciesID) == "string" and speciesID:match("^spell:(%d+)$")
        if spellID then return ForeverRosettaStoneDB:GetSpellName(tonumber(spellID), locale) end
        if not C_PetJournal or not C_PetJournal.GetPetInfoBySpeciesID then return end
        local _, _, _, creatureID = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
        if Addon:IsReadableEntityID(creatureID) then return ForeverRosettaStoneDB:GetNpcName(creatureID, locale) end
    end,
    ResolveData = function(source, data)
        local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
        if not canaccessallvalues(info) or type(info) ~= "table" or info.getterName ~= "GetCompanionPet" then return end
        if data.type == Enum.TooltipDataType.Spell and Addon:IsReadableEntityID(data.id) then
            return "spell:" .. data.id
        end
        local args = info.getterArgs
        if not canaccessallvalues(args) or type(args) ~= "table" or not canaccessallvalues(args[1])
            or not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then return end
        local speciesID = C_PetJournal.GetPetInfoByPetID(args[1])
        if Addon:IsReadableEntityID(speciesID) then return speciesID end
    end,
    Install = function()
        if not BattlePetToolTip_Show or not BattlePetTooltip then return end
        hooksecurefunc("BattlePetToolTip_Show", function(speciesID)
            if Addon.lifecycle == "ready" and Addon:IsReadableEntityID(speciesID) then
                Addon:Run("pet tooltip", Addon.UpdateNameTooltip, Addon, BattlePetTooltip, "pet", speciesID)
            end
        end)
    end,
})
