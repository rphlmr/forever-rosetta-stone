local _, Addon = ...

local function FindTrackerRecipe(frame)
    while frame do
        if frame:IsForbidden() then return end
        if ProfessionsRecipeTracker and frame.parentModule == ProfessionsRecipeTracker then
            local id = frame.id
            if canaccessallvalues(id) and type(id) == "number" and Addon:IsReadableEntityID(math.abs(id)) then
                return frame, math.abs(id)
            end
            return
        end
        frame = frame:GetParent()
    end
end

local function FindListEntry(frame)
    local row, entry
    while frame do
        if frame:IsForbidden() then return end
        if frame == ProfessionsFrame then
            if not entry then return end
            local data = entry.data or entry
            if data.recipeInfo then
                local info = data.recipeInfo
                if Professions and Professions.GetHighestLearnedRecipe then
                    info = Professions.GetHighestLearnedRecipe(info) or info
                end
                if Addon:IsReadableEntityID(info.recipeID) then return row, info.recipeID end
            elseif data.categoryInfo and Addon:IsReadableEntityID(data.categoryInfo.categoryID) then
                return row, data.categoryInfo.categoryID, "category"
            end
            return
        end
        if not entry and frame.GetElementData then
            local data = frame:GetElementData()
            if canaccessallvalues(data) and type(data) == "table" then row, entry = frame, data end
        end
        frame = frame:GetParent()
    end
end

local function RecipeName(id, locale)
    return ForeverRosettaStoneDB:GetSpellName(id, locale)
end

local function TrackerLines(source, id)
    local lines = {}
    if not ProfessionsUtil or not ProfessionsUtil.GetRecipeSchematic then return lines end
    local schematic = ProfessionsUtil.GetRecipeSchematic(id, source.id < 0)
    if not schematic then return lines end
    local slots = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        if ProfessionsUtil.IsReagentSlotRequired(slot) then
            if ProfessionsUtil.IsReagentSlotModifyingRequired(slot) then table.insert(slots, 1, slot)
            else slots[#slots + 1] = slot end
        end
    end
    for _, slot in ipairs(slots) do
        local reagent = slot.reagents and slot.reagents[1]
        local name
        if reagent and ProfessionsUtil.IsReagentSlotBasicRequired(slot) then
            if Addon:IsReadableEntityID(reagent.itemID) then
                name = ForeverRosettaStoneDB:GetItemName(reagent.itemID, Addon:GetTargetLocale())
                    or C_Item.GetItemInfo(reagent.itemID)
            elseif Addon:IsReadableEntityID(reagent.currencyID) then
                local currency = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
                name = currency and currency.name
            end
        elseif slot.slotInfo then
            name = slot.slotInfo.slotText
        end
        if name then
            local quantity
            if slot.IsVariableQuantityReagent and slot:IsVariableQuantityReagent(reagent) then
                local minimum, maximum = slot:GetVariableQuantityRange(reagent)
                quantity = minimum .. "-" .. maximum
            else
                local required = slot:GetQuantityRequired(reagent)
                local current = ProfessionsUtil.AccumulateReagentsInPossession(slot.reagents)
                quantity = current .. " / " .. required
            end
            lines[#lines + 1] = "- " .. quantity .. " " .. name
        end
    end
    return lines
end

local function Hide(kind)
    local tip = Addon[kind .. "Tooltip"]
    if tip then
        Addon:ClearStackedTooltip(GameTooltip, false, tip)
        tip:Hide()
    end
    Addon[kind .. "TooltipKey"] = nil
end

local function Update(kind, find, activeFrame, tracker)
    local source, id, entryKind
    local enabled = Addon:IsFeatureEnabled(kind .. "Tooltip")
        or (not tracker and Addon:IsFeatureEnabled("recipeCategoryTooltip"))
    if not Addon:IsTooltipBlocked() and enabled then
        source, id, entryKind = Addon:GetTooltipFocus(find, activeFrame)
    end
    local title
    local feature = entryKind == "category" and "recipeCategoryTooltip" or kind .. "Tooltip"
    if source and source:IsVisible() and Addon:IsFeatureEnabled(feature) then
        if entryKind == "category" then
            title = ForeverRosettaStoneDB:GetProfessionCategoryName(id, Addon:GetTargetLocale())
        else title = RecipeName(id, Addon:GetTargetLocale()) end
    end
    if not title then Hide(kind); return end
    local rows = tracker and Addon.preferences.tooltipCoverage ~= "name" and TrackerLines(source, id) or {}
    local native = not GameTooltip:IsForbidden() and GameTooltip:IsShown()
        and find(GameTooltip:GetOwner()) == source
    local key = tostring(id) .. ":" .. tostring(entryKind) .. ":" .. Addon:GetTargetLocale()
        .. ":" .. title .. ":" .. tostring(native) .. ":" .. table.concat(rows, "\n")
    local tip = Addon[kind .. "Tooltip"]
    if not tip then
        tip = Addon:CreateCompanionTooltip("ForeverRosettaStone" .. kind .. "Tooltip")
        Addon[kind .. "Tooltip"] = tip
    end
    if not tip:IsShown() or not tip:IsOwned(source) or Addon[kind .. "TooltipKey"] ~= key then
        tip:SetOwner(source, "ANCHOR_NONE")
        tip:ClearLines()
        if native then Addon:SetCompanionTooltipTitle(tip, title, 1, 0.82, 0)
        else Addon:SetStandaloneTooltipTitle(tip, title, 1, 0.82, 0) end
        for _, text in ipairs(rows) do tip:AddLine(text, 1, 1, 1, true) end
        Addon[kind .. "TooltipKey"] = key
    end
    if native and Addon:GetTooltipPresentation(GameTooltip) ~= "separate" then
        Addon:FillStackedTooltip(GameTooltip, tip, kind .. ":" .. key)
        return
    end
    Addon:ClearStackedTooltip(GameTooltip, false, tip)
    local anchor = native and GameTooltip or source
    local component = Addon:GetTooltipComponent(kind)
    local policy = component.placementProfiles[native and "native" or "standalone"][Addon:GetTooltipInputMode()]
    Addon:AnchorCompanionTooltip(tip, anchor, policy.GetSide(anchor))
    tip:SetClampedToScreen(true)
    tip:Show()
    local occupied = { Addon:GetTooltipRect(source) }
    if not GameTooltip:IsForbidden() and GameTooltip:IsShown() then
        occupied[#occupied + 1] = Addon:GetTooltipRect(GameTooltip)
    end
    Addon:PlaceCompanionTooltip(tip, anchor, occupied, false, tracker and not native and source.HeaderText or nil, policy)
end

function Addon:UpdateRecipeTrackerTooltip()
    Update("recipeTracker", FindTrackerRecipe, ObjectiveTrackerFrame, true)
end

function Addon:UpdateRecipeListTooltip()
    Update("recipeList", FindListEntry, ProfessionsFrame, false)
end

for _, kind in ipairs({ "recipeTracker", "recipeList" }) do
    local componentKind = kind
    local side = kind == "recipeTracker" and function() return "left" end or Addon.TooltipSideRules.right
    Addon:RegisterNameTooltipComponent({
        kind = kind,
        GetName = RecipeName,
        defaultContext = "standalone",
        placementProfiles = Addon:CreateTooltipPlacementProfiles({
            name = kind,
            contexts = { standalone = {}, native = {
                mouse = { sideRules = { Addon.TooltipSideRules.owner, Addon.TooltipSideRules.screen } },
                gamepad = { sideRules = { Addon.TooltipSideRules.owner, Addon.TooltipSideRules.screen } },
            } },
            mouse = { sideRules = { side } }, gamepad = { sideRules = { side } },
        }),
        Update = function()
            if componentKind == "recipeTracker" then Addon:UpdateRecipeTrackerTooltip()
            else Addon:UpdateRecipeListTooltip() end
        end,
        Hide = function() Hide(componentKind) end,
    })
end
