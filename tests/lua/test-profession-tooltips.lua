local Addon, setFocus = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
equal(ForeverRosettaStoneDB:GetProfessionCategoryName(2586, "enUS"), "Belts",
    "profession sections load from the generated English catalog")
equal(ForeverRosettaStoneDB:GetProfessionCategoryName(2586, "frFR"), "Ceintures",
    "profession sections load their official localized names")
equal(ForeverRosettaStoneDB:GetProfessionCategoryName(2586, "daDK"), "Bælter",
    "community language category translations are included in the generated data")
local previous = { ProfessionsFrame, ProfessionsRecipeTracker, Professions, ProfessionsUtil, C_TradeSkillUI }
local getCategory = ForeverRosettaStoneDB.GetProfessionCategoryName
local getSpell, getItem = ForeverRosettaStoneDB.GetSpellName, ForeverRosettaStoneDB.GetItemName
local count, recipe = 0, 700001
ForeverRosettaStoneDB.GetSpellName = function(_, id, locale)
    if id == recipe and locale == "enUS" then return "Translated recipe" end
end
ForeverRosettaStoneDB.GetItemName = function(_, id)
    if id == 700002 then return "Translated reagent" end
end
ProfessionsFrame = CreateFrame("Frame", nil, UIParent)
ProfessionsRecipeTracker = {}
Professions = { GetHighestLearnedRecipe = function(info)
    return { recipeID = info.recipeID + 1 }
end }
local slot = { reagents = {{ itemID = 700002 }}, GetQuantityRequired = function() return 3 end }
local missing = { reagents = {{ itemID = 700003 }}, GetQuantityRequired = function() return 1 end }
ProfessionsUtil = {
    GetRecipeSchematic = function(id, recraft)
        equal(id, recipe, "tracker normalizes the recipe ID")
        return { reagentSlotSchematics = { slot, missing } }
    end,
    IsReagentSlotRequired = function() return true end,
    IsReagentSlotModifyingRequired = function() return false end,
    IsReagentSlotBasicRequired = function() return true end,
    AccumulateReagentsInPossession = function() return count end,
}
C_Item = C_Item or {}
local originalItemInfo = C_Item.GetItemInfo
C_Item.GetItemInfo = function(id) return id == 700003 and "Native reagent" or "Other reagent" end
Addon:SetTargetLocale("enUS")
Addon:SetTooltipMode("separate")
Addon:SetTooltipNameOnly("recipeTracker", false)
SettingsPanel:Hide()
GameMenuFrame:Hide()
WorldMapFrame:Hide()
GameTooltip:Hide()
local block = CreateFrame("Frame", nil, ObjectiveTrackerFrame)
block.parentModule, block.id = ProfessionsRecipeTracker, recipe
block.left, block.top = 1200, 850
block:SetSize(250, 100)
local header = CreateFrame("Button", nil, block)
setFocus({ header })
Addon:UpdateRecipeTrackerTooltip()
local tip = Addon.recipeTrackerTooltip
equal(tip:IsShown(), true, "tracked recipes show a translation")
equal(tip.lines[2], "Translated recipe", "tracker translates the recipe title")
equal(tip.lines[3], "- 0 / 3 Translated reagent", "tracker uses structured quantities and translated items")
equal(tip.lines[4], "- 0 / 1 Native reagent", "missing item translations retain native names")
equal(tip.points[1][1], "TOPRIGHT", "tracker uses inward quest placement")
count = 2
Addon:UpdateRecipeTrackerTooltip()
equal(tip.lines[3], "- 2 / 3 Translated reagent", "bag changes refresh quantities")
block.id = -recipe
Addon:UpdateRecipeTrackerTooltip()
equal(tip:IsShown(), true, "recraft IDs are supported")
Addon:SetTooltipNameOnly("recipeTracker", true)
Addon:UpdateRecipeTrackerTooltip()
equal(#tip.lines, 2, "tracker respects name-only coverage")
Addon:SetTooltipNameOnly("recipeTracker", false)
local row = CreateFrame("Button", nil, ProfessionsFrame)
row.left, row.top = 500, 800
row:SetSize(250, 25)
row.GetElementData = function() return { data = { recipeInfo = { recipeID = recipe - 1 } } } end
setFocus({ row })
Addon:UpdateRecipeTrackerTooltip()
equal(tip:IsShown(), false, "tracker tooltip closes outside the tracker")
Addon:UpdateRecipeListTooltip()
local listTip = Addon.recipeListTooltip
equal(listTip:IsShown(), true, "profession list rows show translated names")
equal(listTip.lines[2], "Translated recipe", "list resolves the displayed learned rank")
equal(#listTip.lines, 2, "list only shows the name even with full coverage")
Professions.GetHighestLearnedRecipe = function(info) return info end
Addon:UpdateRecipeListTooltip()
equal(listTip:IsShown(), false, "missing recipe translations hide stale names")
ForeverRosettaStoneDB.GetProfessionCategoryName = function(_, id)
    if id == 700004 then return "Translated category" end
end
row.GetElementData = function() return { data = { categoryInfo = { categoryID = 700004 } } } end
Addon:UpdateRecipeListTooltip()
equal(listTip.lines[2], "Translated category", "section titles translate using category IDs")
equal(#listTip.lines, 2, "section tooltips contain only the translated name")
Addon:SetFeatureEnabled("recipeCategoryTooltip", false)
Addon:UpdateRecipeListTooltip()
equal(listTip:IsShown(), false, "section hovers have an independent setting")
Addon:SetFeatureEnabled("recipeCategoryTooltip", true)
Addon:SetFeatureEnabled("recipeListTooltip", false)
Addon:UpdateRecipeListTooltip()
equal(listTip:IsShown(), true, "sections still work when recipe name hovers are disabled")
Addon:SetFeatureEnabled("recipeListTooltip", true)
listTip.accurateLines = true
Addon:SetTooltipMode("stacked")
GameTooltip:Hide()
GameTooltip.processingInfo = nil
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
GameTooltip:ClearLines()
GameTooltip:AddLine("Native category")
GameTooltip:Show()
Addon:UpdateRecipeListTooltip()
equal(listTip:IsShown(), false, "native category tooltips use stacked mode")
equal(GameTooltip.lines[1], "Native category", "stacked mode preserves the native section name")
equal(GameTooltip.lines[VisibleTooltipLines(GameTooltip)], "Translated category", "stacked mode adds the translation")
Addon:UpdateRecipeListTooltip()
equal(GameTooltip.lines[VisibleTooltipLines(GameTooltip)], "Translated category", "repeated polling retains the translation")
Addon:SetStackedTranslationFirst(true)
Addon:UpdateRecipeListTooltip()
local block = Addon.stackedTooltips[GameTooltip].block
equal(block:GetLeftLine(2):GetText(), "Translated category", "profession sections use the shared translation-first setting")
equal(VisibleTooltipLines(GameTooltip), 1, "translation-first leaves the native profession rows in place")
setFocus({})
Addon:UpdateRecipeListTooltip()
equal(block:IsShown(), false, "leaving the recipe hides the translated block")
equal(select(4, GameTooltip:GetPadding()), 0, "leaving the recipe removes its translation padding")
equal(VisibleTooltipLines(GameTooltip), 1, "leaving a section restores its native tooltip")
GameTooltip:Hide()
Addon:SetStackedTranslationFirst(false)
Addon:SetTooltipMode("separate")
setFocus({ header })
Addon:SetFeatureEnabled("recipeTrackerTooltip", false)
Addon:UpdateRecipeTrackerTooltip()
equal(tip:IsShown(), false, "tracked recipes respect their feature setting")
Addon:SetFeatureEnabled("recipeTrackerTooltip", true)
setFocus({})
Addon:UpdateRecipeListTooltip()
equal(listTip:IsShown(), false, "leaving a recipe hides its tooltip")
ForeverRosettaStoneDB.GetProfessionCategoryName = getCategory
C_Item.GetItemInfo = originalItemInfo
ForeverRosettaStoneDB.GetSpellName, ForeverRosettaStoneDB.GetItemName = getSpell, getItem
ProfessionsFrame, ProfessionsRecipeTracker, Professions, ProfessionsUtil, C_TradeSkillUI = unpack(previous)
return checks
