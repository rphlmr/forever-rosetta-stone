local _, Addon = ...

local function Readable(value, kind)
    return canaccessallvalues(value) and type(value) == kind
end

local function Normalize(text)
    return (text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
        :gsub("|n", "\n"):gsub("\194\160", " "):gsub("\226\128\175", " ")
        :gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
        :gsub("[ \t\r\n\v\f]+", " "):gsub("^ +", ""):gsub(" +$", ""))
end

local function Escape(text)
    return (text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"))
end

local function SameEquipmentRequirement(addon, expected, actual)
    if Normalize(expected) == Normalize(actual) then return true end
    if not addon.TranslateOwnedTooltipFormat then return false end
    -- The client's spaced/unspaced equipment formats can differ in punctuation.
    -- Canonicalize only those owned formats, keeping the complete mask label.
    local sources, natives = {}, {}
    for _, key in ipairs({"SPELL_EQUIPPED_ITEM", "SPELL_EQUIPPED_ITEM_NOSPACE"}) do
        local function Keep(value) return value ~= "" and value or nil end
        local source = addon:TranslateOwnedTooltipFormat(expected, key, "enUS", Keep)
        local native = addon:TranslateOwnedTooltipFormat(actual, key, "enUS", Keep)
        if source then sources[Normalize(source)] = true end
        if native then natives[Normalize(native)] = true end
    end
    for value in pairs(sources) do if natives[value] then return true end end
    return false
end

-- Requirements are identified by the displayed recipe's live schematic, not a
-- catalog-wide name lookup. Native counts, colors and unavailable names stay live.
function Addon:GetSpellRequirementTranslations(spec, locale)
    local translated, incomplete = {}, {}
    local rules = spec.kind ~= "item" and ForeverRosettaStoneDB:GetSpellRules(spec.id) or nil
    local recipes, recipeSet = {}, {}
    local function Recipe(id)
        if self:IsReadableEntityID(id) and not recipeSet[id] then recipeSet[id], recipes[#recipes + 1] = true, id end
    end
    if spec.kind == "item" then
        local item = ForeverRosettaStoneDB:GetItemRules(spec.id)
        for _, id in ipairs(item and item.recipeSpellIDs or {}) do Recipe(id) end
        for _, effect in ipairs(item and item.effects or {}) do
            if effect.triggerType == 6 then Recipe(effect.spellID) end
        end
    else Recipe(spec.id) end
    if self.TranslateOwnedTooltipFormat then
        for _, line in ipairs(spec.data.lines or {}) do
            if line.type == Enum.TooltipDataLineType.UsageRequirement and Readable(line.leftText, "string") then
                local function Names(text, ids, getter)
                    if type(getter) ~= "function" then return end
                    local result, used = {}, {}
                    for part in (text .. ","):gmatch("(.-),") do
                        part = Normalize(part)
                        local found, target
                        for _, formID in ipairs(ids or {}) do
                            local source = getter(ForeverRosettaStoneDB, formID, GetLocale())
                            if Readable(source, "string") and Normalize(source) == part then
                                if found then return end
                                found, target = formID, getter(ForeverRosettaStoneDB, formID, locale)
                            end
                        end
                        if not found or used[found] or not Readable(target, "string") then return end
                        used[found], result[#result + 1] = true, target
                    end
                    return #result > 0 and table.concat(result, ", ") or nil
                end
                for _, key in ipairs({ "SPELL_REQUIRED_FORM", "SPELL_REQUIRED_FORM_NOSPACE", "ITEM_REQ_SKILL" }) do
                    local text = self:TranslateOwnedTooltipFormat(line.leftText, key, locale, function(value)
                        return Names(value, rules and rules.requiredForms, ForeverRosettaStoneDB.GetShapeshiftFormName)
                            or Names(value, rules and rules.requiredItemSubclasses, ForeverRosettaStoneDB.GetItemSubclassName)
                    end)
                    if text then translated[line] = text; break end
                end
                if not translated[line] and rules and Readable(line.requirementType, "number") then
                    local shared = rules.equipmentRequirementSources
                        and rules.equipmentRequirementSources[line.requirementType]
                    local own = line.requirementType == rules.equipmentRequirementType
                    local sourceID = own and spec.id or shared and shared[GetLocale()]
                    local targetID = own and spec.id or shared and shared[locale]
                    local source = sourceID and ForeverRosettaStoneDB:GetSpellDetails(sourceID, GetLocale())
                    local target = targetID and ForeverRosettaStoneDB:GetSpellDetails(targetID, locale)
                    source, target = source and source.equipmentRequirement, target and target.equipmentRequirement
                    if Readable(source, "string") and Readable(target, "string")
                        and SameEquipmentRequirement(self, source, line.leftText) then translated[line] = target end
                end
            end
        end
    end
    local rows, section = {}, nil
    for _, line in ipairs(spec.data.lines or {}) do
        if canaccessallvalues(line.type) and Readable(line.leftText, "string") then
            local colon = line.leftText:find(":", 1, true)
            local fullWidth = line.leftText:find("：", 1, true)
            local ending = fullWidth and (not colon or fullWidth < colon) and fullWidth + #"：" - 1 or colon
            local prefix = ending and line.leftText:sub(1, ending)
            local heading
            for _, key in ipairs({ "SPELL_TOTEMS", "SPELL_REAGENTS" }) do
                local native = _G[key]
                if canaccessallvalues(native) and native == nil and self.GetClientLabel then
                    native = self:GetClientLabel(key, GetLocale())
                end
                if prefix and Readable(native, "string") and Normalize(prefix) == Normalize(native) then
                    heading, section = key, key
                end
            end
            if Enum.TooltipDataLineType.SpellDescription and line.type == Enum.TooltipDataLineType.SpellDescription then
                section = nil
            end
            if section then rows[#rows + 1] = { line = line, heading = heading, prefix = prefix, section = section }
            elseif spec.kind == "item" and #recipes > 0 and line.type == Enum.TooltipDataLineType.None then
                rows[#rows + 1] = { line = line, section = "SPELL_REAGENTS" }
            end
        end
    end
    if #rows == 0 then return translated, incomplete end
    local candidates = { SPELL_TOTEMS = {}, SPELL_REAGENTS = {} }
    local function Candidate(key, source, target)
        if not Readable(source, "string") or not Readable(target, "string") then return end
        source = source:gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
        local previous = candidates[key][source]
        if previous ~= nil and previous ~= target then candidates[key][source] = false
        else candidates[key][source] = target end
    end
    local function AddItem(key, id)
        if not self:IsReadableEntityID(id) then return end
        local source = ForeverRosettaStoneDB:GetItemName(id, GetLocale())
        local target = ForeverRosettaStoneDB:GetItemName(id, locale)
        Candidate(key, source, target)
    end
    for _, recipeID in ipairs(recipes) do
        if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
            local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
            if ok and Readable(schematic, "table") and Readable(schematic.recipeID, "number") and schematic.recipeID == recipeID
                and Readable(schematic.reagentSlotSchematics, "table") then
                for _, slot in ipairs(schematic.reagentSlotSchematics) do
                    if Readable(slot, "table") and Readable(slot.reagents, "table") then
                        for _, reagent in ipairs(slot.reagents) do
                            if Readable(reagent, "table") then AddItem("SPELL_REAGENTS", reagent.itemID) end
                        end
                    end
                end
            end
        end
        -- Categories and direct items are separate ID namespaces; neither requires an inventory scan.
        local recipeRules = ForeverRosettaStoneDB:GetSpellRules(recipeID)
        for _, itemID in ipairs(recipeRules and recipeRules.requiredToolItems or {}) do AddItem("SPELL_TOTEMS", itemID) end
        for _, itemID in ipairs(recipeRules and recipeRules.requiredReagentItems or {}) do AddItem("SPELL_REAGENTS", itemID) end
        for _, categoryID in ipairs(recipeRules and recipeRules.requiredToolCategories or {}) do
            local source = ForeverRosettaStoneDB:GetTotemCategoryName(categoryID, GetLocale())
            local target = ForeverRosettaStoneDB:GetTotemCategoryName(categoryID, locale)
            Candidate("SPELL_TOTEMS", source, target)
        end
    end
    for _, row in ipairs(rows) do
        local text, heading = row.line.leftText, ""
        local missingHeading = false
        if row.heading then
            local label = self:GetClientLabel(row.heading, locale)
            -- Parts are matched after the native heading, so a target heading with a full-width
            -- colon never becomes part of the first name.
            heading, text = label and Normalize(label) or row.prefix, text:sub(#row.prefix + 1)
            missingHeading = not label and GetLocale() ~= locale
        end
        local changed, unresolved = heading ~= (row.heading and row.prefix or ""), missingHeading
        text = text:gsub("([^,\n]+)", function(part)
            local body = Normalize(part):gsub("^[ \t\r\n]+", "")
            if not row.heading then body = body:gsub("^.-: *", "") end
            for source, target in pairs(candidates[row.section]) do
                if target and (body == Normalize(source) or body:match("^" .. Escape(Normalize(source)) .. " %([%d/ ]+%)$")) then
                    local canonical = part:gsub("\226\128\153", "'"):gsub("\226\128\152", "'")
                    local replaced, count = canonical:gsub(Escape(source), function() return target end)
                    if count > 0 then changed = true; return replaced end
                end
            end
            if body:find("[%a\128-\255]") then unresolved = true end
            return part
        end)
        if changed then
            translated[row.line], incomplete[row.line] = heading .. text, unresolved
        end
    end
    return translated, incomplete
end

local playerAuraGUID, playerAuraIdentities = nil, {}
local auraCacheEvents

local function AuraResolution(reason)
    if Addon.RecordAuraResolution then Addon:RecordAuraResolution(reason) end
end

function Addon:RefreshPlayerAuraIdentities()
    if InCombatLockdown and InCombatLockdown() then return end
    if not UnitGUID or not C_UnitAuras or type(C_UnitAuras.GetUnitAuras) ~= "function" then return end
    local guidOK, guid = pcall(UnitGUID, "player")
    if not guidOK or not Readable(guid, "string") then return end
    local identities = {}
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        local ok, auras = pcall(C_UnitAuras.GetUnitAuras, "player", filter)
        if not ok or not Readable(auras, "table") then return end
        for _, aura in ipairs(auras) do
            if Readable(aura, "table") and self:IsReadableEntityID(aura.auraInstanceID)
                and self:IsReadableEntityID(aura.spellId) then
                identities[aura.auraInstanceID] = aura.spellId
            end
        end
    end
    playerAuraGUID, playerAuraIdentities = guid, identities
    AuraResolution("cache-refreshed")
end

local function KnownAuraIdentity(unit, instance)
    if not UnitGUID or not Addon:IsReadableEntityID(instance) then return end
    local ok, guid = pcall(UnitGUID, unit)
    if ok and Readable(guid, "string") and guid == playerAuraGUID then
        return playerAuraIdentities[instance]
    end
end

local function CachedAuraResult(unit, instance, aura)
    local known = KnownAuraIdentity(unit, instance)
    if not known then return end
    AuraResolution("resolved-cached")
    local result = { spellId = known }
    if Readable(aura, "table") then
        if Readable(aura.name, "string") then result.name = aura.name end
        if Readable(aura.dispelName, "string") then result.dispelName = aura.dispelName end
    end
    return result, unit
end

function Addon:GetTooltipAuraData(source)
    local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
    if canaccessallvalues(info) and info == nil and source.GetPrimaryTooltipInfo then
        info = source:GetPrimaryTooltipInfo()
    end
    if not canaccessallvalues(info) then AuraResolution("tooltip-info-restricted"); return end
    if type(info) ~= "table" then AuraResolution("tooltip-info-unavailable"); return end
    local name, args = info.getterName, info.getterArgs
    if not canaccessallvalues(name, args) then AuraResolution("getter-info-restricted"); return end
    if type(name) ~= "string" or type(args) ~= "table" then AuraResolution("getter-info-unavailable"); return end
    local unit, index, filter = args[1], args[2], args[3]
    if not canaccessallvalues(unit) then
        AuraResolution("getter-unit-restricted"); AuraResolution("getter-arguments-restricted"); return
    end
    if not canaccessallvalues(index) then
        AuraResolution("getter-aura-key-restricted"); AuraResolution("getter-arguments-restricted"); return
    end
    if type(unit) ~= "string" or type(index) ~= "number" then
        AuraResolution("getter-arguments-unavailable"); return
    end
    if not C_UnitAuras then AuraResolution("aura-api-unavailable"); return end

    local getter, byIndex
    if name == "GetUnitAura" or name == "GetUnitBuff" or name == "GetUnitDebuff" then
        getter = C_UnitAuras.GetAuraDataByIndex
        byIndex = true
        if not canaccessallvalues(filter) then
            AuraResolution("getter-filter-restricted"); AuraResolution("getter-arguments-restricted"); return
        end
        if filter ~= nil and type(filter) ~= "string" then AuraResolution("getter-arguments-unavailable"); return end
        if name == "GetUnitBuff" then filter = filter or "HELPFUL" end
        if name == "GetUnitDebuff" then filter = filter or "HARMFUL" end
    elseif name == "GetUnitAuraByAuraInstanceID" or name == "GetUnitBuffByAuraInstanceID"
        or name == "GetUnitDebuffByAuraInstanceID" then
        getter = C_UnitAuras.GetAuraDataByAuraInstanceID
    else
        AuraResolution("getter-unsupported")
        return
    end
    if type(getter) ~= "function" then AuraResolution("aura-getter-unavailable"); return end
    local ok, aura
    if byIndex then ok, aura = pcall(getter, unit, index, filter)
    else ok, aura = pcall(getter, unit, index) end
    if not ok then
        AuraResolution("aura-lookup-failed")
        -- Native tooltip info still supplies the exact public instance. A blocked lookup must
        -- not discard an identity already observed for that same player and instance.
        if not byIndex and InCombatLockdown and InCombatLockdown() then return CachedAuraResult(unit, index) end
        return
    end
    if not canaccessallvalues(aura) then
        AuraResolution("aura-data-restricted")
        if not byIndex and InCombatLockdown and InCombatLockdown() then return CachedAuraResult(unit, index) end
        return
    end
    if type(aura) ~= "table" then AuraResolution("aura-unavailable"); return end
    if canaccessallvalues(aura.spellId) then
        if Addon:IsReadableEntityID(aura.spellId) then AuraResolution("resolved-live"); return aura, unit end
        AuraResolution("spell-id-unavailable")
        return
    end
    local instance
    if byIndex then instance = aura.auraInstanceID else instance = index end
    if not canaccessallvalues(instance) then AuraResolution("aura-instance-restricted"); return end
    local cached = CachedAuraResult(unit, instance, aura)
    if cached then return cached, unit end
    AuraResolution("no-confirmed-cached-identity")
end

Addon:RegisterNameTooltipComponent({
    kind = "spell",
    supportsFullText = true,
    placementProfiles = Addon.spellTooltipPlacements,
    GetPlacementContext = function(source)
        local spec = Addon.nameTooltips[source]
        if spec and spec.getterName == "GetAction" then return "actionBar" end
        if spec and spec.getterName == "GetSpellBookItem" then return "spellbook" end
        return "default"
    end,
    GetName = function(id, locale) return ForeverRosettaStoneDB:GetSpellName(id, locale) end,
    Install = function()
        if not auraCacheEvents then
            -- The listener survives addon resets; dispatch through the current addon lifecycle.
            auraCacheEvents = CreateFrame("Frame")
            auraCacheEvents:RegisterEvent("UNIT_AURA")
            auraCacheEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
            auraCacheEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
            auraCacheEvents:SetScript("OnEvent", function(_, event, unit)
                if event == "PLAYER_REGEN_DISABLED" then AuraResolution("combat-entered"); return end
                if event ~= "UNIT_AURA" or Readable(unit, "string") and unit == "player" then
                    Addon:Run("refresh known player auras", Addon.RefreshPlayerAuraIdentities, Addon)
                end
            end)
        end
        Addon:RefreshPlayerAuraIdentities()
    end,
    ResolveData = function(source, data)
        if not canaccessallvalues(data) then AuraResolution("tooltip-data-restricted"); return end
        if not canaccessallvalues(data.type) then AuraResolution("tooltip-type-restricted"); return end
        if data.type == Enum.TooltipDataType.Spell and Addon:IsReadableEntityID(data.id) then return data.id end
        if Enum.TooltipDataType.UnitAura and data.type == Enum.TooltipDataType.UnitAura then
            local aura = Addon:GetTooltipAuraData(source)
            return aura and aura.spellId
        end
    end,
    ResolveOwner = function(source)
        if not source.GetSpell then return end
        local spec = Addon.nameTooltips[source]
        if spec.kind and spec.kind ~= "spell" then return end
        local data = source:GetPrimaryTooltipData()
        if data and data.type ~= Enum.TooltipDataType.Spell then return end
        local _, spellID = source:GetSpell()
        if Addon:IsReadableEntityID(spellID) then return spellID end
    end,
})
