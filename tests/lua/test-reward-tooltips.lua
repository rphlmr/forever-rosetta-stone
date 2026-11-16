local Addon, page, sources, setMouseFoci, setStyle, press = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local function color(red, green, blue)
    return { GetRGB = function() return red, green, blue end }
end

Enum.TooltipDataLineType = { ItemName = 22, SpellName = 13, UnitName = 2, ItemBinding = 20, EquipSlot = 21, ItemLevel = 31, None = 0 }
Enum.TooltipComparisonMethod = { Single = 0, WithBothHands = 1, WithBagMainHandItem = 2, WithBagOffHandItem = 3 }
ClientApi.InstallGlobals("frFR", {"EQUIPPED", "IF_EQUIPPED_TOGETHER"})
for key in pairs(Addon.itemTooltipLabels) do _G[key] = "fr:" .. key end
ClientApi.InstallGlobals("frFR", {"ITEM_BIND_ON_PICKUP", "ITEM_SOULBOUND", "INVTYPE_2HWEAPON"})
local types = Enum.TooltipDataLineType
local function itemData(id, name, binding, slot, subclass)
    return {
        id = id, hyperlink = "item:" .. id,
        lines = {
            { type = types.ItemName, leftText = name, leftColor = color(0.12, 1, 0) },
            { type = types.ItemLevel, leftText = "Niveau d'objet 20" },
            { type = types.ItemBinding, leftText = binding },
            { type = types.EquipSlot, leftText = slot, rightText = subclass,
                leftColor = color(1, 0, 0), rightColor = color(1, 1, 1) },
            { type = types.None, leftText = "Dégâts : 36 - 55", rightText = "Vitesse 3,50" },
            { type = types.None, leftText = "+6 Force" },
        },
    }
end
local axe = itemData(5626, "Broie-crâne", ITEM_BIND_ON_PICKUP, INVTYPE_2HWEAPON, "Hache")
local staff = itemData(15397, "Bâton d'Oakthrush", ITEM_SOULBOUND, INVTYPE_2HWEAPON, "Bâton")
local sword = itemData(5627, "Lame de relique", ITEM_SOULBOUND, INVTYPE_2HWEAPON, "Épée")
local comparison = { method = 0, item = { guid = "equipped-staff" }, additionalItems = {} }
local equippedData = staff
local rewardData = axe
local equipLoc, classID, subclassID = "INVTYPE_2HWEAPON", 2, 1
local reads = 0
C_Item = {
    GetItemInfoInstant = function(id)
        local subclass = id == 15397 and 10 or (id == 5627 and 7 or subclassID)
        return id, nil, nil, equipLoc, nil, classID, subclass
    end,
}
C_TooltipInfo = {
    GetQuestLogItem = function(rewardType, index, questID, collectionText)
        assert(rewardType == "choice" and index == 2, "comparison reads the selected source reward")
        assert(questID == 943 and collectionText == false, "comparison reads the displayed quest without extras")
        reads = reads + 1
        return rewardData
    end,
    GetItemByGUID = function(guid)
        assert(guid == "equipped-staff", "comparison preserves the equipped instance GUID")
        return equippedData
    end,
    GetHyperlink = function(link) assert(link == "item:5627"); return sword end,
}
C_TooltipComparison = {
    GetItemComparisonInfo = function(item)
        assert(item.hyperlink == "item:5626", "native engine compares the actual reward hyperlink")
        return comparison
    end,
    CompareItem = function() error("addon must not call protected CompareItem") end,
}
local button = page.rewardButtons[2]
local originalWidth, originalHeight = UIParent:GetSize()
local activeFrame, selectedButton = SmartNavigation.activeFrame, SmartNavigation.currentButton
UIParent:SetSize(2000, 1200)
button.left, button.top = 1100, 700
for _, tip in ipairs(Addon.rewardTooltips) do tip:SetSize(180, 72) end
local nativeOwner, nativeTitle = GameTooltip:GetOwner(), GameTooltip:GetText()
local primary, equipped, secondary = unpack(Addon.rewardTooltips)
setMouseFoci({button.Icon})
setStyle("0")
button:Fire("OnEnter")
equal(button.mouseEnabled, true, "item rewards are mouse accessible")
equal(primary:IsShown(), true, "reward hover shows its compact tooltip")
equal(primary:GetOwner(), button, "reward tooltip belongs to Rosetta reward button")
equal(primary:GetLeftLine(2):GetText(), "Skullchipper", "reward name follows the translation label")
equal(select(2, primary:GetLeftLine(2):GetTextColor()), 1, "reward tooltip preserves item quality color")
equal(#primary.lines, 4, "translation label and title precede binding and equipment fields")
equal(primary.lines[1], Addon:GetTooltipTranslationLabel(), "standalone reward tooltips use the shared translation label")
equal(primary.lines[3], "Binds when picked up", "binding is translated")
equal(primary.lines[4].left, "Two-Hand", "equipment slot is translated")
equal(primary.lines[4].right, "Axe", "weapon type is translated")
equal(primary.lines[4].colors[1], 1, "unusable slot preserves native red")
equal(primary.lines[4].colors[2], 0, "unusable slot retains native restriction color")
equal(equipped:GetLeftLine(2):GetText(), "Oakthrush Staff", "equipped example name is translated")
equal(equipped.lines[3], "Soulbound", "equipped binding uses current instance state")
equal(equipped.lines[4].right, "Staff", "equipped item has its own translated type")
equal(equipped.CompareHeader.Label:GetText(), "Équipé", "equipped label stays in client language")
equal(equipped.points[1][2], primary, "equipped comparison follows reward horizontally")
equal(equipped.points[1][3], "TOPRIGHT", "comparison top edges align")
equal(secondary:IsShown(), false, "unused comparison tooltip is hidden")
SettingsPanel:Show()
equal(primary:IsShown(), true, "opening settings preserves reward tooltips")
Addon:UpdateRewardTooltips(button)
equal(primary:IsShown(), true, "reward tooltips remain available with settings open")
SettingsPanel:Hide()
equal(GameTooltip:GetOwner(), nativeOwner, "comparison does not take over native tooltip")
equal(GameTooltip:GetText(), nativeTitle, "comparison leaves native tooltip content intact")
equal(SmartNavigation:GetCurrentButton(), selectedButton, "hover cannot steal controller selection")
local hidden = 0
Addon:HookScript(button, "OnHide", function() hidden = hidden + 1 end)
page:RefreshNativeLayout()
equal(hidden, 0, "reward refresh does not hide a focused card")
Addon.input:Fire("OnUpdate", 0.2)
equal(primary:IsShown(), true, "periodic layout refresh keeps comparison visible")
equal(hidden, 0, "periodic layout refresh does not flicker reward hover")
button:Fire("OnLeave")
equal(primary:IsShown(), false, "leaving reward hides its tooltip")
equal(equipped:IsShown(), false, "leaving reward hides equipped comparison")
setMouseFoci({})
setStyle("1")
Addon:RefreshSelection()
press("PADRTRIGGER")
SmartNavigation:SelectButton(button)
Addon.input:Fire("OnUpdate", 0.2)
equal(primary:IsShown(), true, "controller reward selection shows comparison")
equal(Addon.current.questID, 943, "comparison leaves quest selection unchanged")
comparison.additionalItems = {{ hyperlink = "item:5627" }}
comparison.method = Enum.TooltipComparisonMethod.WithBothHands
Addon:UpdateRewardTooltips()
equal(secondary:GetLeftLine(2):GetText(), "Relic Blade", "native two-item comparison shows the second item")
equal(secondary.CompareHeader.Label:GetText(), EQUIPPED, "both-hand comparison uses native equipped label")
comparison.method = Enum.TooltipComparisonMethod.WithBagOffHandItem
Addon:UpdateRewardTooltips()
equal(secondary.CompareHeader.Label:GetText(), IF_EQUIPPED_TOGETHER, "paired bag comparison keeps native header meaning")
UIParent:SetSize(1000, 800)
button.left = 1900
Addon:UpdateRewardTooltips()
equal(equipped.points[1][4], Addon:GetTooltipGap(equipped), "reward comparison uses the shared tooltip gap")
local groupRight = primary.points[1][4] + 3 * 180 * primary:GetEffectiveScale()
equal(groupRight <= UIParent:GetWidth(), true, "comparison row moves together to fit the screen")
UIParent:SetSize(2000, 1200)
button.left = 1100
comparison = nil
Addon:UpdateRewardTooltips()
equal(primary:IsShown(), true, "unequipped slot still shows reward details")
equal(equipped:IsShown(), false, "equipment removal clears old comparison")
comparison = { method = 0, item = { guid = "equipped-staff" }, additionalItems = {} }
equippedData = nil
Addon:UpdateRewardTooltips()
equal(equipped:IsShown(), false, "pending equipped item data cannot leave stale tooltip")
equippedData = staff
Addon.input:Fire("OnUpdate", 0.2)
equal(equipped:IsShown(), true, "native data becoming available refreshes equipped comparison")

for key, expected in pairs(Addon.itemTooltipLabels) do
    if key:sub(1, 5) == "ITEM_" then
        axe.lines[3].leftText = _G[key]
        Addon:UpdateRewardTooltips()
        equal(primary.lines[3], expected, "binding variant " .. key)
    elseif key:sub(1, 8) == "INVTYPE_" then
        equipLoc = key
        axe.lines[4].leftText = _G[key]
        Addon:UpdateRewardTooltips()
        equal(primary.lines[4].left, expected, "equipment slot variant " .. key)
    end
end
equipLoc = "INVTYPE_2HWEAPON"
axe.lines[3].leftText, axe.lines[4].leftText = ITEM_BIND_ON_PICKUP, INVTYPE_2HWEAPON
for itemClass, names in pairs(Addon.itemSubclasses) do
    classID = itemClass
    for subclass, expected in pairs(names) do
        subclassID = subclass
        Addon:UpdateRewardTooltips()
        equal(primary.lines[4].right, expected, "item class " .. itemClass .. " subtype " .. subclass)
    end
end
classID, subclassID = 2, 1
axe.lines[3].type = types.None
Addon:UpdateRewardTooltips()
equal(#primary.lines, 3, "unbound item has equipment and translation label without an invented binding line")
equal(primary.lines[3].left, "Two-Hand", "equipment remains visible without binding")
axe.lines[3].type = types.ItemBinding
classID, subclassID = 999, 999
Addon:UpdateRewardTooltips()
equal(primary.lines[4].right, "Hache", "unrecognized item types keep the native label")
classID, subclassID = 2, 1
axe.lines[3].leftText = "New client binding variant"
Addon:UpdateRewardTooltips()
equal(primary.lines[3], "New client binding variant", "unrecognized binding stays readable in client language")
axe.lines[3].leftText = ITEM_BIND_ON_PICKUP
rewardData = nil
Addon:UpdateRewardTooltips()
equal(primary:IsShown(), false, "missing reward data clears all comparison tooltips")
rewardData = axe
Addon:UpdateRewardTooltips()
GameMenuFrame:Show()
Addon:UpdateRewardTooltips()
equal(primary:IsShown(), false, "game menu suppresses reward tooltips")
GameMenuFrame:Hide()
Addon:UpdateRewardTooltips(button)
local rewardLeft = MapQuestInfoRewardsFrame.left
MapQuestInfoRewardsFrame.left = nil
page:RefreshNativeLayout()
equal(button:IsShown(), false, "missing native reward layout cannot retain old cards")
equal(primary:IsShown(), false, "missing native reward layout clears comparison")
MapQuestInfoRewardsFrame.left = rewardLeft
page:RefreshNativeLayout()
Addon:UpdateRewardTooltips(button)
sources[2].objectType = "currency"
page:RefreshNativeLayout()
equal(primary:IsShown(), false, "recycling selected reward as currency immediately clears tooltip")
equal(button.mouseEnabled, false, "non-item cards are not interactive")
sources[2].objectType = "item"
page:RefreshNativeLayout()
Addon:UpdateRewardTooltips(button)
Addon.panel:Hide()
equal(primary:IsShown(), false, "closing Rosetta immediately clears comparisons")
equal(equipped:IsShown(), false, "closing Rosetta clears equipped names")
Addon.panel:Show()
Addon:HideRewardTooltips()
setMouseFoci({})
setStyle("1")
SmartNavigation.activeFrame, SmartNavigation.currentButton = activeFrame, selectedButton
UIParent:SetSize(originalWidth, originalHeight)
equal(reads > 0, true, "tooltips use native quest reward data")

return checks
