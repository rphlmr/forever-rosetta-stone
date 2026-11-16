local Addon, tooltipData, callbacks, flushTimers = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
Addon:SetTooltipMode("separate")
local checks = 0
-- The client's automatic aura tooltip is tracked like any native tooltip, in its own group.
local buffSpec = Addon.nameTooltips[BuffFrameTooltip]
assert(buffSpec and #buffSpec.group == 1 and buffSpec.group[1] == BuffFrameTooltip,
    "BuffFrameTooltip must be a tracked tooltip source")
local sources = { GameTooltip, ShoppingTooltip1, ShoppingTooltip2,
    ItemRefTooltip, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 }
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local function prepare(source)
    for _, other in ipairs(sources) do other:Hide() end
    source:SetOwner(UIParent, "ANCHOR_CURSOR")
    source:SetText("Nom français")
    source:SetSize(200, 300)
    source.left, source.top = 400, 800
    source:ClearAllPoints()
    source:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 70)
    local primary = Addon.nameTooltips[source].group[1]
    if primary ~= source then
        source.left = 800
        primary:SetOwner(UIParent, "ANCHOR_CURSOR")
        primary:SetText("Comparaison")
        primary:SetSize(200, 300)
        primary.left, primary.top = 100, 800
        tooltipData(primary, Enum.TooltipDataType.Item, 5626)
        primary:Show()
        flushTimers()
    end
end
local function show(source)
    source:Show()
    flushTimers()
    assert(Addon.lifecycle == "ready", table.concat(Addon.errors, "\n"))
    return Addon.nameTooltips[source].tip
end
local function title(source)
    local tip = Addon.nameTooltips[source].tip
    return tip.lines[1] or tip:GetText()
end

SettingsPanel:Hide()
GameMenuFrame:Hide()
if Addon.errorDialog then Addon.errorDialog.frame:Hide() end
WorldMapFrame:Hide()
Addon:SetTargetLocale("enUS")
Addon:SetFeatureEnabled("itemTooltip", true)
Addon:SetFeatureEnabled("spellTooltip", true)

prepare(GameTooltip)
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
local tip = show(GameTooltip)
equal(title(GameTooltip), "Skullchipper", "item title has no addon icon")
equal(VisibleTooltipLines(GameTooltip), 2, "native tooltip receives no translated rows")
equal(GameTooltip.lines[1], "Native title", "native title stays first")
equal(GameTooltip.lines[2], "Native details", "native body stays unchanged")
equal(tip:IsShown(), true, "translated item tooltip is always separate")
equal(tip.points[1][1], "TOPLEFT", "translation sits right of the native tooltip")
equal(tip.points[1][3], "TOPRIGHT", "translation joins the native tooltip's right edge")
equal(select(2, tip:GetLeftLine(1):GetFont()), 14, "translated title matches the native title font")

GameTooltip.default = 1
GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
GameTooltip.left = 1600
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(tip.points[1][1], "TOPRIGHT", "default bottom-right item tooltips extend left")
equal(GameTooltip:GetLeft(), 1600, "the default item policy preserves the native screen anchor")
equal(Addon:GetTooltipPlacementPolicy(GameTooltip).name, "item", "registry selects the item strategy")
local mode = Addon:GetTooltipInputMode()
local spellPolicy = Addon.spellTooltipPlacements.default[mode]
local talentPolicy = Addon.talentTooltipPlacements.talentTree[mode]
local comparisonPolicy = Addon.itemComparisonPlacements.default[mode]
local itemPolicy = Addon.itemTooltipPlacements.default[mode]
local spellSide, talentSide, comparisonSide = spellPolicy.GetSide(GameTooltip), talentPolicy.GetSide(GameTooltip), comparisonPolicy.GetSide(GameTooltip)
local itemSide = itemPolicy.GetSide
itemPolicy.GetSide = function() return "right" end
equal(spellPolicy.GetSide(GameTooltip), spellSide, "changing item placement cannot change spell rules")
equal(talentPolicy.GetSide(GameTooltip), talentSide, "changing item placement cannot change talent rules")
equal(comparisonPolicy.GetSide(GameTooltip), comparisonSide, "changing a single item policy cannot change comparisons")
local otherMode = mode == "mouse" and "gamepad" or "mouse"
equal(Addon.itemTooltipPlacements.default[otherMode].GetSide(GameTooltip), "left", "changing one input mode leaves the other mode isolated")
equal(Addon.itemTooltipPlacements.bag[mode].GetSide(GameTooltip), "left", "changing one screen context leaves bag placement isolated")
itemPolicy.GetSide = itemSide
GameTooltip.default = nil
prepare(GameTooltip)
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
tip = show(GameTooltip)

local hovered = CreateFrame("Button", nil, UIParent)
hovered:SetSize(40, 40)
hovered.left, hovered.top = 950, 600
for _, tooltipType in ipairs({ Enum.TooltipDataType.Item, Enum.TooltipDataType.Spell }) do
    local id = tooltipType == Enum.TooltipDataType.Item and 5626 or 133
    GameTooltip:SetOwner(hovered, "ANCHOR_NONE")
    tooltipData(GameTooltip, tooltipType, id)
    tip = show(GameTooltip)
    equal(tip.points[1][1], "TOPRIGHT", "a native tooltip left of the hovered button gets a left companion")
    equal(tip.points[1][3], "TOPLEFT", "the left companion joins the native left edge")
    equal(GameTooltip:GetLeft(), 400, "left companions preserve native placement when there is room")
    hovered.left = 100
    Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
    equal(tip.points[1][1], "TOPLEFT", "a native tooltip right of the hovered button gets a right companion")
    hovered.left = 950
end
GameTooltip:SetOwner(UIParent, "ANCHOR_LEFT")
equal(Addon:GetCompanionTooltipSide(GameTooltip), "left", "explicit left anchors work without an owner rectangle")
GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
equal(Addon:GetCompanionTooltipSide(GameTooltip), "right", "explicit right anchors work without an owner rectangle")
local getCursorPosition = GetCursorPosition
GetCursorPosition = function() return 1000, 600 end
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
equal(Addon:GetCompanionTooltipSide(GameTooltip), "left", "cursor anchors use the cursor as their target")
GetCursorPosition = getCursorPosition
GameTooltip:SetOwner(hovered, "ANCHOR_NONE")
GameTooltip.left = 20
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(tip:IsShown(), true, "left-edge companion remains visible")
equal(GameTooltip:GetLeft(), 20 + tip:GetWidth() + Addon.TOOLTIP_GAP,
    "left-edge native tooltip moves inward to make room for its companion")
equal(tip.points[1][1], "TOPRIGHT", "left-edge companion stays outside the native tooltip")
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(GameTooltip:GetLeft(), 20 + tip:GetWidth() + Addon.TOOLTIP_GAP,
    "left-edge placement does not accumulate movement")
prepare(GameTooltip)
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
tip = show(GameTooltip)

ClientApi.InstallGlobals("frFR", {"ARMOR_TEMPLATE"})
GameTooltip:GetLeftLine(2):SetFont("BodyFont", 11, "OUTLINE")
GameTooltip:GetLeftLine(2):SetTextColor(0.4, 0.5, 0.6)
GameTooltip:GetRightLine(2):SetTextColor(1, 0.1, 0.1)
local nativeBody = { { type = 0, leftText = "Armure : 12", rightText = "Armure : 2",
    leftColor = { r = 0.4, g = 0.5, b = 0.6 }, rightColor = { r = 1, g = 0.1, b = 0.1 } } }
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 2210, nil, nativeBody)
tip = show(GameTooltip)
equal(tip.lines[2].left, "12 Armor", "shared armor labels translate in body rows")
equal(tip.lines[2].right, "2 Armor", "shared armor labels translate in the right column")
equal(tip.lines[2].colors[1], 0.4, "full tooltip preserves native body color")
equal(tip.lines[2].colors[4], 1, "full tooltip preserves right-hand requirement color")
equal(select(2, tip:GetLeftLine(2):GetFont()), 11, "full tooltip matches body font size")
GameTooltip:GetLeftLine(2):SetFont("Fonts/FRIZQT__.TTF", 14, "")
GameTooltip:GetLeftLine(2):SetTextColor(1, 1, 1)
GameTooltip:GetRightLine(2):SetTextColor(1, 1, 1)

for _, source in ipairs(sources) do
    prepare(source)
    tooltipData(source, Enum.TooltipDataType.Item, 5626)
    local companion = show(source)
    for index = 1, 5 do
        source:Show()
        source:SetSize(200 + index, 300 + index)
        flushTimers()
    end
    equal(title(source), "Skullchipper", "comparison and chat tooltips get a plain translated title")
    equal(#source.lines, 2, "show and resize do not insert native rows")
    equal(companion.points[1][3], "TOPRIGHT", "every native tooltip places its translation on the right")
    equal(source.points[1][1], "BOTTOMRIGHT", "stacking preserves the game's anchor")
    equal(source.points[1][4], -10, "stacking preserves the game's anchor offset")
    tooltipData(source, Enum.TooltipDataType.Item, 11511)
    show(source)
    equal(title(source), "Cenarion Beacon", "rebuilding replaces the previous translation")
end

prepare(GameTooltip)
for index, source in ipairs({ GameTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
    source:SetOwner(UIParent, "ANCHOR_NONE")
    source:SetText("Comparaison")
    source:SetSize(200, 300)
    source.left, source.top = 500 + (index - 1) * 200, 1040
    tooltipData(source, Enum.TooltipDataType.Item, 5626)
    source:Show()
end
flushTimers()
local companionCount = 0
for _, source in ipairs({ GameTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
    local companion = Addon.nameTooltips[source].tip
    if companion and companion:IsShown() then companionCount = companionCount + 1 end
end
equal(companionCount, 3, "each comparison object has its own translated companion")
local comparisonSources = { GameTooltip, ShoppingTooltip1, ShoppingTooltip2 }
for index = 2, #comparisonSources do
    local previous, current = comparisonSources[index - 1], comparisonSources[index]
    equal(current:GetLeft(), previous:GetRight(), "comparison row keeps native tooltips adjacent")
end
equal(Addon.nameTooltips[GameTooltip].tip.points[1][1], "TOPRIGHT", "leftmost native gets an outer left translation")
equal(GameTooltip:GetLeft(), 304, "comparison row shifts inside the left edge while retaining its native order")
GameTooltip.protected = true
local originalCombat = InCombatLockdown
InCombatLockdown = function() return true end
GameTooltip.SetClampRectInsets = function() error("protected tooltip must not be changed in combat") end
GameTooltip.SetClampedToScreen = function() error("protected tooltip must not be changed in combat") end
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
for _, source in ipairs(comparisonSources) do
    equal(Addon.nameTooltips[source].tip:IsShown(), true,
        "a previously placed comparison remains visible during combat")
end
GameTooltip.SetClampRectInsets, GameTooltip.SetClampedToScreen = nil, nil
InCombatLockdown = originalCombat
Addon:HideNameTooltips()
GameTooltip.left, ShoppingTooltip1.left, ShoppingTooltip2.left = 1300, 1500, 1700
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(Addon.nameTooltips[GameTooltip].tip:IsShown(), true,
    "protected native comparison tooltips can be positioned outside combat")
equal(GameTooltip:GetLeft(), 696, "right-edge comparisons reserve the native outer edge for the complete row")
local lastTip = Addon.nameTooltips[ShoppingTooltip2].tip
equal(ShoppingTooltip2:GetRight() + 2 * (Addon.TOOLTIP_GAP + lastTip:GetWidth()), 1900,
    "the final comparison companion ends at the original native edge")
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(GameTooltip:GetLeft(), 696, "comparison layout does not accumulate movement")
GameTooltip:SetWidth(220)
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(GameTooltip:GetLeft(), 694, "resizing updates the complete comparison row width")
GameTooltip:SetWidth(200)
Addon:HideNameTooltips()
GameTooltip.left, ShoppingTooltip1.left, ShoppingTooltip2.left = 500, 700, 900
UIParent:SetWidth(800)
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
for _, source in ipairs(comparisonSources) do
    equal(Addon.nameTooltips[source].tip:IsShown(), false, "an oversized comparison row hides its companions")
end
equal(ShoppingTooltip1:GetLeft(), 700, "an oversized comparison row restores native positions")
UIParent:SetWidth(1920)
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
GameTooltip:Hide()
equal(ShoppingTooltip1:GetLeft(), 700, "closing the comparison group restores native placement")
GameTooltip.protected = false

prepare(GameTooltip)
GameTooltip.protected = true
InCombatLockdown = function() return true end
GameTooltip.SetClampRectInsets = function() error("protected tooltip must not be changed in combat") end
GameTooltip.SetClampedToScreen = function() error("protected tooltip must not be changed in combat") end
for index, source in ipairs({ GameTooltip, ShoppingTooltip1 }) do
    source:SetOwner(UIParent, "ANCHOR_RIGHT")
    source:SetText("Comparaison")
    source:SetSize(200, 300)
    source.left, source.top = index == 1 and 400 or 800, 800
    tooltipData(source, Enum.TooltipDataType.Item, 5626)
    source:Show()
end
flushTimers()
local combatTip = Addon.nameTooltips[GameTooltip].tip
equal(combatTip:IsShown(), true, "combat comparison shows the protected primary translation")
equal(Addon.nameTooltips[ShoppingTooltip1].tip:IsShown(), true,
    "combat comparison shows the movable comparison translation")
equal(GameTooltip:GetLeft(), 400, "combat comparison keeps the protected primary in place")
equal(ShoppingTooltip1:GetLeft(), 800, "combat comparison preserves native spacing when outer translations fit")
ShoppingTooltip1.protected = true
GameTooltip.left = 50
ShoppingTooltip1.left, ShoppingTooltip1.clamped = 850, false
combatTip:SetHeight(100)
Addon.nameTooltips[ShoppingTooltip1].tip:SetHeight(100)
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(combatTip:IsShown(), true, "combat shows a separate row when protected tooltips cannot be interleaved")
equal(Addon.nameTooltips[ShoppingTooltip1].tip:IsShown(), true, "combat fallback includes both translations")
equal(combatTip.points[1][2], GameTooltip, "combat fallback stays anchored to its native tooltip")
equal(Addon.nameTooltips[ShoppingTooltip1].tip.points[1][2], ShoppingTooltip1,
    "combat fallback anchors each translation to its own native tooltip")
equal(combatTip.points[1][5], combatTip:GetHeight() + Addon.TOOLTIP_GAP,
    "combat fallback uses the space above the native tooltips")
GameTooltip.top, ShoppingTooltip1.top = 1040, 1040
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(combatTip.points[1][5], -GameTooltip:GetHeight() - Addon.TOOLTIP_GAP,
    "combat fallback uses the space below when there is no room above")
GameTooltip.top, ShoppingTooltip1.top = 800, 800
combatTip:SetHeight(500)
Addon.nameTooltips[ShoppingTooltip1].tip:SetHeight(500)
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(combatTip:IsShown(), false, "combat fallback hides when neither row fits on screen")
combatTip:SetHeight(100)
Addon.nameTooltips[ShoppingTooltip1].tip:SetHeight(100)
ShoppingTooltip1.protected = false
GameTooltip.SetClampRectInsets, GameTooltip.SetClampedToScreen = nil, nil
GameTooltip.protected = false
InCombatLockdown = originalCombat
Addon:RestoreTooltipSources()
GameTooltip.left = 400
ShoppingTooltip1.left = 400 + GameTooltip:GetWidth()
GameTooltip.protected, ShoppingTooltip1.protected = true, true
InCombatLockdown = function() return true end
GameTooltip.SetClampRectInsets = function() error("protected tooltip must not be changed in combat") end
ShoppingTooltip1.SetClampRectInsets = GameTooltip.SetClampRectInsets
Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
equal(combatTip:IsShown(), true, "already aligned protected tooltips need no repositioning in combat")
equal(Addon.nameTooltips[ShoppingTooltip1].tip:IsShown(), true,
    "both aligned protected comparisons retain their translations")
GameTooltip.SetClampRectInsets, ShoppingTooltip1.SetClampRectInsets = nil, nil
GameTooltip.protected, ShoppingTooltip1.protected = false, false
InCombatLockdown = originalCombat
GameTooltip:Hide()
equal(Addon.nameTooltips[ShoppingTooltip1].tip:IsShown(), false,
    "closing the primary comparison closes its translated companions")
ShoppingTooltip1:Hide()

prepare(ItemRefTooltip)
for index, source in ipairs({ ItemRefTooltip, ItemRefShoppingTooltip1 }) do
    source:SetOwner(hovered, "ANCHOR_NONE")
    source:SetText("Comparaison")
    source:SetSize(200, 300)
    source.left, source.top = 20 + (index - 1) * 400, 800
    tooltipData(source, Enum.TooltipDataType.Item, 5626)
    source:Show()
end
flushTimers()
local chatTip = Addon.nameTooltips[ItemRefTooltip].tip
local chatComparisonTip = Addon.nameTooltips[ItemRefShoppingTooltip1].tip
equal(chatTip:IsShown(), true, "chat item companion remains visible at the left edge")
equal(chatComparisonTip:IsShown(), true, "chat comparison companion remains visible at the left edge")
equal(ItemRefTooltip:GetLeft(), Addon.TOOLTIP_GAP * 2 + chatTip:GetWidth(),
    "chat comparison row moves inside the left edge")
equal(chatTip.points[1][1], "TOPRIGHT", "chat item companion stays outside its native tooltip")
equal(chatComparisonTip.points[1][1], "TOPLEFT", "rightmost chat comparison gets an outer right translation")
equal(ItemRefShoppingTooltip1:GetLeft() - ItemRefTooltip:GetRight(), 200,
    "chat comparison preserves native spacing while sliding inside the left edge")
ItemRefTooltip:Hide()

prepare(GameTooltip)
tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 133)
tip = show(GameTooltip)
equal(title(GameTooltip), "Fireball", "spell translation uses a separate plain title")
Addon:SetFeatureEnabled("spellTooltip", false)
equal(tip:IsShown(), false, "disabling spells hides the companion")
equal(VisibleTooltipLines(GameTooltip), 2, "disabling spells preserves native content")
Addon:SetFeatureEnabled("spellTooltip", true)
equal(title(GameTooltip), "Fireball", "enabling spells restores the companion")
Addon:SetTargetLocale("frFR")
equal(title(GameTooltip), ForeverRosettaStoneDB:GetSpellName(133, "frFR"),
    "full translations in other languages retain their catalog titles")
equal(VisibleTooltipLines(GameTooltip), 2, "other target languages do not insert a subtitle")
Addon:SetTargetLocale("enUS")
tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 999999999)
equal(tip:IsShown(), false, "unknown spells hide stale companions")
tooltipData(GameTooltip, Enum.TooltipDataType.Item, { secret = true })
equal(Addon.nameTooltips[GameTooltip].kind, nil, "inaccessible IDs are ignored")
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
show(GameTooltip)
local nativeShow = GameTooltip.Show
local emptyShows = 0
function GameTooltip:Show()
    if self:NumLines() == 0 then emptyShows = emptyShows + 1 end
    return nativeShow(self)
end
GameTooltip:ClearLines()
equal(tip:IsShown(), true, "native refresh preserves the displayed translation until content is ready")
equal(Addon.nameTooltips[GameTooltip].name, nil, "native clearing removes translation metadata")
equal(Addon.nameTooltips[GameTooltip].group.lifecycle.value, "building", "native clear enters the rebuilding phase")
equal(emptyShows, 0, "clearing native rows never forces an empty native Show")
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
show(GameTooltip)
equal(tip:IsShown(), true, "completed native refresh retains a visible translation")
equal(emptyShows, 0, "native refresh does not flash an empty tooltip")
GameTooltip.Show = nativeShow
GameTooltip:Hide()
equal(tip:IsShown(), false, "leaving the tooltip performs the hide transition")

prepare(GameTooltip)
GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
GameTooltip.left, GameTooltip.top = 1700, 800
GameTooltip:SetSize(200, 100)
tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 2973)
tip = show(GameTooltip)
local placedLeft = GameTooltip:GetLeft()
local nativeSetInsets = GameTooltip.SetClampRectInsets
local clampWrites = 0
function GameTooltip:SetClampRectInsets(...)
    clampWrites = clampWrites + 1
    return nativeSetInsets(self, ...)
end
for index = 1, 6 do
    tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 2973)
    equal(tip:IsShown(), true, "action-bar refresh keeps its previous translation while rebuilding")
    show(GameTooltip)
    equal(GameTooltip:GetLeft(), placedLeft, "action-bar refresh keeps the placed native tooltip stable")
    equal(tip:IsShown(), true, "action-bar refresh finishes with its translation visible")
end
equal(clampWrites, 0, "unchanged refreshes do not restore or reapply native placement")
GameTooltip:Hide()
equal(GameTooltip:GetLeft(), 1700, "source hide restores the native anchor once")
equal(clampWrites, 1, "source hide owns the single placement restoration")
GameTooltip.SetClampRectInsets = nativeSetInsets

prepare(GameTooltip)
local pair = { GameTooltip, ShoppingTooltip1 }
for index, source in ipairs(pair) do
    source:SetOwner(UIParent, "ANCHOR_RIGHT")
    source:SetSize(200, 100)
    source.left, source.top = index == 1 and 1500 or 1000, 800
    tooltipData(source, Enum.TooltipDataType.Item, index == 1 and 2654 or 147)
    source:Show()
end
flushTimers()
local comparisonLeft = { GameTooltip:GetLeft(), ShoppingTooltip1:GetLeft() }
local setInsets = { GameTooltip.SetClampRectInsets, ShoppingTooltip1.SetClampRectInsets }
local comparisonWrites = 0
for index, source in ipairs(pair) do
    local set = setInsets[index]
    source.SetClampRectInsets = function(self, ...)
        comparisonWrites = comparisonWrites + 1
        return set(self, ...)
    end
end
for refresh = 1, 6 do
    for index, source in ipairs(pair) do
        tooltipData(source, Enum.TooltipDataType.Item, index == 1 and 2654 or 147)
        equal(Addon.nameTooltips[source].tip:IsShown(), true, "comparison rebuild preserves the translated row")
        source:Show()
    end
    flushTimers()
    for index, source in ipairs(pair) do
        equal(source:GetLeft(), comparisonLeft[index], "comparison refresh preserves native row placement")
        equal(Addon.nameTooltips[source].tip:IsShown(), true, "comparison refresh retains each translation")
    end
end
equal(comparisonWrites, 0, "unchanged comparison refreshes do not restore and reapply the row")
GameTooltip:Hide()
equal(GameTooltip:GetLeft(), 1500, "closing comparisons restores the primary native position")
equal(ShoppingTooltip1:GetLeft(), 1000, "closing comparisons restores the compared native position")
for index, source in ipairs(pair) do source.SetClampRectInsets = setInsets[index] end

prepare(GameTooltip)
local oldArmor, oldSummary, oldMultiple = ARMOR, ITEM_DELTA_DESCRIPTION, ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION
ClientApi.InstallGlobals("frFR", {"ARMOR", "ITEM_DELTA_DESCRIPTION", "ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION"})
for index, source in ipairs(pair) do
    source:SetOwner(UIParent, "ANCHOR_NONE")
    source:SetSize(200, 100)
    source.left, source.top = index == 1 and 1000 or 800, 800
    tooltipData(source, Enum.TooltipDataType.Item, index == 1 and 2654 or 147)
end
ShoppingTooltip1.CompareHeader.Label:SetText(EQUIPPED)
ShoppingTooltip1.CompareHeader:Show()
ShoppingTooltip1:AddLine(" ")
ShoppingTooltip1:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0, true)
ShoppingTooltip1:AddLine("|cff00ff00+35|r Armure", 1, 1, 1)
show(GameTooltip)
local equippedTip = show(ShoppingTooltip1)
equal(GameTooltip:GetLeft(), 698, "comparison row grows away from the hovered item")
equal(ShoppingTooltip1:GetLeft(), 498, "equipped tooltip retains its position beside the hovered native tooltip")
equal(GameTooltip:GetRight() + Addon.TOOLTIP_GAP + Addon.nameTooltips[GameTooltip].tip:GetWidth(), 1200,
    "the outer translated edge inherits the original native anchor")
equal(equippedTip.points[1][1], "TOPRIGHT", "equipped translation sits outside the native equipped tooltip")
equal(Addon.nameTooltips[GameTooltip].tip.points[1][1], "TOPLEFT", "hovered translation sits outside the native hovered tooltip")
equal(equippedTip.CompareHeader:IsShown(), true, "translated equipped items have a native comparison header")
equal(equippedTip.CompareHeader.Label:GetText(), "Equipped", "equipped header uses the target language")
equal(equippedTip.lines[#equippedTip.lines - 1],
    "If you replace this item, the following stat changes will occur:", "late native comparison summary is translated")
equal(equippedTip.lines[#equippedTip.lines], "|cff00ff00+35|r Armor", "delta preserves the client value and inline color")
equal(equippedTip:GetLeftLine(#equippedTip.lines - 1):GetTextColor(), 1, "summary preserves its native color")
for locale in pairs(ForeverRosettaStoneDB:GetLocales()) do
    Addon:SetTargetLocale(locale)
    equal(type(Addon:TranslateComparisonText(EQUIPPED)), "string", "every supported language has an equipped label")
    equal(type(Addon:TranslateComparisonText(ITEM_DELTA_DESCRIPTION)), "string", "every supported language has a delta summary")
    equal(type(Addon:TranslateComparisonText("|cffff0000-12|r Armure")), "string", "every supported language translates armor deltas")
end
Addon:SetTargetLocale("enUS")
ShoppingTooltip1:GetLeftLine(ShoppingTooltip1:NumLines()):SetText("|cff00ff00+41|r Armure")
show(ShoppingTooltip1)
equal(equippedTip.lines[#equippedTip.lines], "|cff00ff00+41|r Armor", "comparison refresh uses updated native delta values")
Addon:SetTooltipMode("stacked")
local lastStacked = ShoppingTooltip1:NumLines()
while lastStacked > 1 and ShoppingTooltip1:GetLeftLine(lastStacked):GetText() == "" do lastStacked = lastStacked - 1 end
equal(ShoppingTooltip1:GetLeftLine(lastStacked):GetText(),
    "|cff00ff00+41|r Armor", "Stacked includes the completed native stat changes")
local fillNameTooltip, redundantFills = Addon.FillNameTooltip, 0
Addon.FillNameTooltip = function(self, spec)
    redundantFills = redundantFills + 1
    return fillNameTooltip(self, spec)
end
for _ = 1, 10 do
    Addon:LayoutNameTooltipGroup(Addon.nameTooltips[GameTooltip].group)
    flushTimers()
end
Addon.FillNameTooltip = fillNameTooltip
equal(redundantFills, 0, "unchanged stacked comparison layouts never rebuild translated content")
Addon:SetTooltipMode("separate")
ShoppingTooltip1.CompareHeader:Hide()
show(ShoppingTooltip1)
equal(equippedTip.CompareHeader:IsShown(), false, "native header disappearance clears the translated header")
ARMOR, ITEM_DELTA_DESCRIPTION, ITEM_DELTA_MULTIPLE_COMPARISON_DESCRIPTION = oldArmor, oldSummary, oldMultiple

prepare(GameTooltip)
local getDetails, getSpellName = ForeverRosettaStoneDB.GetSpellDetails, ForeverRosettaStoneDB.GetSpellName
local getClientLocale = GetLocale
GetLocale = function() return "frFR" end
local descriptionType = Enum.TooltipDataLineType.SpellDescription
Enum.TooltipDataLineType.SpellDescription = 34
ForeverRosettaStoneDB.GetSpellDetails = function(self, id, ...)
    if id == 1293712 then
        return { description = "You are proficient in the use of the following armor types:$?s9078[\n$@spellname9078][]$?s9077[\n$@spellname9077][]" }
    end
    return getDetails(self, id, ...)
end
ForeverRosettaStoneDB.GetSpellName = function(self, id, locale)
    if id == 1293712 then return "Armor Proficiency" end
    if id == 9078 then return locale == "frFR" and "Tissu" or "Cloth" end
    if id == 9077 then return locale == "frFR" and "Cuir" or "Leather" end
    return getSpellName(self, id, locale)
end
tooltipData(GameTooltip, Enum.TooltipDataType.Spell, 1293712, nil, {
    { type = 34, leftText = "Vous maîtrisez l’utilisation des types d’armure suivants :", leftColor = { r = 1, g = 0.82, b = 0 } },
    { type = 0, leftText = "Tissu", leftColor = { r = 1, g = 1, b = 1 } },
    { type = 0, leftText = "Cuir", leftColor = { r = 1, g = 1, b = 1 } },
})
GameTooltip:GetLeftLine(2):SetTextColor(1, 0.82, 0)
GameTooltip:GetLeftLine(3):SetTextColor(1, 1, 1)
GameTooltip:GetLeftLine(4):SetTextColor(1, 1, 1)
tip = show(GameTooltip)
equal(tip.lines[2], "Vous maîtrisez l’utilisation des types d’armure suivants :", "split spell list introduction stays native")
equal(tip.lines[3], "Tissu", "untyped armor list entries stay native")
equal(tip.lines[4], "Cuir", "native armor list order is preserved")
local _, introductionGreen, introductionBlue = tip:GetLeftLine(2):GetTextColor()
local _, armorGreen, armorBlue = tip:GetLeftLine(3):GetTextColor()
equal(introductionGreen, 0.82, "spell introduction retains native yellow")
equal(introductionBlue, 0, "spell introduction retains its native blue channel")
equal(armorGreen, 1, "armor list keeps native white rather than introduction yellow")
equal(armorBlue, 1, "armor list retains its native blue channel")
ForeverRosettaStoneDB.GetSpellDetails, ForeverRosettaStoneDB.GetSpellName = getDetails, getSpellName
GetLocale = getClientLocale
Enum.TooltipDataLineType.SpellDescription = descriptionType

local callbackCount = #callbacks
Addon:Restart()
equal(Addon.lifecycle, "ready", "reset succeeds with separate tooltips")
equal(#callbacks, callbackCount, "reset does not duplicate data callbacks")
prepare(GameTooltip)
tooltipData(GameTooltip, Enum.TooltipDataType.Item, 5626)
show(GameTooltip)
equal(title(GameTooltip), "Skullchipper", "translation works after addon reset")
for _, source in ipairs(sources) do
    source:Hide()
    source.lastTooltipRequest = nil
end

return checks
