local Addon, context = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
Addon:SetTooltipMode("separate")
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local function show()
    GameTooltip:Show()
    context.flushTimers()
end
local function emit(source, data, body)
    source:ClearLines()
    source.processingInfo = source.processingInfo or {}
    source.processingInfo.tooltipData = data
    local lineType = data.type == Enum.TooltipDataType.Quest and Enum.TooltipDataLineType.QuestTitle
        or data.type == Enum.TooltipDataType.Toy and Enum.TooltipDataLineType.ItemName
        or data.type == Enum.TooltipDataType.Unit and Enum.TooltipDataLineType.UnitName
        or Enum.TooltipDataLineType.SpellName
    source:AddLine("Native title")
    for _, callback in ipairs(context.lineCallbacks[lineType] or {}) do
        callback(source, { type = lineType, lineIndex = 1 })
    end
    if body then
        data.lines = { { type = lineType, lineIndex = 1, leftText = "Native title" } }
        for _, row in ipairs(body) do
            if row.rightText then source:AddDoubleLine(row.leftText, row.rightText)
            else source:AddLine(row.leftText) end
            row.lineIndex = source:NumLines()
            data.lines[#data.lines + 1] = row
            for _, callback in ipairs(context.lineCallbacks[TooltipDataProcessor.AllTypes] or {}) do callback(source, row) end
        end
    else source:AddLine("Native details") end
    for _, callback in ipairs(context.callbacks) do callback(source, data) end
end
local function prepare(owner, getter, args)
    GameTooltip:Hide()
    GameTooltip.processingInfo = getter and { getterName = getter, getterArgs = args or {} }
    GameTooltip.left, GameTooltip.top = 700, 800
    GameTooltip:SetSize(200, 300)
    GameTooltip:SetOwner(owner or UIParent, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 70)
    GameTooltip:SetText("Texte natif")
end
Addon:SetTargetLocale("enUS")
GetLocale = function() return "frFR" end
SettingsPanel:Hide()
GameMenuFrame:Hide()
Addon.errorDialog.frame:Hide()
WorldMapFrame:Hide()

prepare()
GameTooltip.top = 400
emit(GameTooltip, { type = Enum.TooltipDataType.Unit, guid = "Creature-0-1-0-1-658-000001", lines = {} })
show()
local spec = Addon.nameTooltips[GameTooltip]
equal(spec.kind, "npc", "creature GUID identifies the NPC component")
equal(spec.id, 658, "NPC lookup uses the creature ID")
equal(spec.tip:GetLeftLine(1):GetText(), "Sten Stoutarm", "NPC translation retains its separate plain title")
equal(GameTooltip.lines[2], "Native details", "NPC details stay unchanged")
equal(spec.tip.points[1][1], "BOTTOMLEFT", "NPC translation sits above the bottom-right native tooltip")
equal(spec.tip.points[1][3], "TOPLEFT", "NPC translation joins the native tooltip's top edge")
equal(select(2, spec.tip:GetLeftLine(1):GetFont()),
    select(2, GameTooltip:GetLeftLine(1):GetFont()), "NPC translation matches title size")
equal(spec.tip:IsShown(), true, "NPC uses the shared horizontal companion")
equal(spec.tip:GetWidth() * spec.tip:GetEffectiveScale(), GameTooltip:GetWidth() * GameTooltip:GetEffectiveScale(),
    "NPC translation matches the original tooltip's width")
GameTooltip:SetWidth(260)
show()
equal(spec.tip:GetWidth(), 260, "NPC width follows native tooltip resizing")
GameTooltip:SetHeight(100)
spec.tip:SetHeight(40)
GameTooltip.left, GameTooltip.top = 500, 500
ShoppingTooltip1:Hide()
ShoppingTooltip2:Hide()
show()
for _, position in ipairs({
    { "top", "BOTTOMLEFT", "TOPLEFT" },
    { "left", "TOPRIGHT", "TOPLEFT" },
    { "right", "TOPLEFT", "TOPRIGHT" },
    { "bottom", "TOPLEFT", "BOTTOMLEFT" },
}) do
    Addon:SetNpcTooltipPosition(position[1])
    equal(spec.tip:IsShown(), true, "NPC position remains visible: " .. position[1])
    equal(spec.tip.points[1][1], position[2], "NPC position updates immediately: " .. position[1])
    equal(spec.tip.points[1][2], GameTooltip, "NPC position follows the native tooltip: " .. position[1])
    equal(spec.tip.points[1][3], position[3], "NPC position uses the native edge: " .. position[1])
end
GameTooltip.left, GameTooltip.top = 500, 500
show()
equal(spec.tip.points[1][2], GameTooltip, "NPC position follows the moved native tooltip")
Addon:SetNpcTooltipPosition("top")
do
    local icon = GameTooltip:CreateTexture()
    icon:Show()
    Addon:SetTranslationOnly(true)
    emit(GameTooltip, { type = Enum.TooltipDataType.Unit, guid = "Creature-0-1-0-1-658-000001" }, {})
    show()
    equal(GameTooltip:GetAlpha(), 0, "a decorative NPC icon does not bring back the original tooltip")
    equal(spec.tip:GetLeftLine(1):GetText(), "Sten Stoutarm", "decorated NPC tooltips start with the translation")
    local nativeTitle = GameTooltip:GetLeftLine(1)
    nativeTitle:SetAlpha(0.75)
    GameTooltip:FadeOut()
    equal(GameTooltip:GetAlpha(), 0, "the native world-tooltip fade cannot reveal the original")
    equal(spec.tip:GetAlpha(), 0, "the translated tooltip stops drawing at the end of the hover")
    GameTooltip:SetAlpha(0.5)
    equal(nativeTitle:GetAlpha(), 0, "the native title stays masked when the fade engine changes root opacity")
    equal(icon:GetAlpha(), 0, "native decorations also stay masked during the fade")
    GameTooltip:Fire("OnUpdate", 0.01)
    equal(GameTooltip:GetAlpha(), 0, "subsequent native fade frames also stay invisible")
    GameTooltip:Show()
    equal(spec.tip:GetAlpha(), 1, "hovering the same NPC again restores the translation")
    equal(GameTooltip:GetAlpha(), 0, "re-entering the hover still hides the original")
    equal(nativeTitle:GetAlpha(), 0.75, "a new native Show restores the original region opacity")
    GameTooltip:FadeOut()
    Addon:ClearStackedTooltip(GameTooltip, true)
    equal(nativeTitle:GetAlpha(), 0, "clearing the replacement before the native fade finishes keeps the native title masked")
    GameTooltip:Hide()
    equal(nativeTitle:GetAlpha(), 0.75, "native Hide restores the region opacity for the next tooltip")
    equal(icon:GetAlpha(), 1, "native Hide restores the original decoration opacity")
    equal(spec.tip:IsShown(), false, "native fade completion cleans up the translated tooltip")
    equal(GameTooltip:GetAlpha(), 1, "native fade completion restores opacity for the next tooltip")
    icon:Hide()
    nativeTitle:SetAlpha(1)
    Addon:SetTranslationOnly(false)
end
emit(GameTooltip, { type = Enum.TooltipDataType.Unit, guid = "Player-1-00000001", lines = {} })
equal(VisibleTooltipLines(GameTooltip), 2, "players do not receive creature translations")
emit(GameTooltip, { type = Enum.TooltipDataType.Unit, guid = { secret = true }, lines = {} })
equal(spec.kind, nil, "secret unit GUIDs are skipped")
emit(GameTooltip, { type = Enum.TooltipDataType.Unit, guid = "Creature-0-1-0-1-999999999-000001", lines = {} })
equal(VisibleTooltipLines(GameTooltip), 2, "unknown NPCs do not display stale names")

prepare(UIParent, "GetTalent", { 134370 })
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 17783, lines = {} })
show()
equal(spec.kind, "talent", "native talent getter distinguishes talents from action-bar spells")
equal(spec.id, 17783, "talent uses the native spell ID instead of the incompatible live talent ID")
equal(spec.tip.lines[1], "Fel Concentration", "talent translation has a separate title")
ClientApi.InstallGlobals("frFR", {"SPELL_PASSIVE"})
prepare(UIParent, "GetTalent", { 134370 })
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 17783 }, { { type = 0, leftText = SPELL_PASSIVE } })
show()
equal(spec.kind, "talent", "full tooltip preserves talent feature routing")
equal(spec.tip.lines[2], "Passive", "shared talent labels translate without inferring entity prose")
do
    local getLocale, getClientLabel = GetLocale, Addon.GetClientLabel
    GetLocale = function() return "enUS" end
    Addon.GetClientLabel = function(_, key, locale) return ForeverRosettaStoneDB:GetGlobalStringByKey(key, locale) end
    Addon:SetTargetLocale("frFR")
    Addon:SetTranslationOnly(true)
    prepare(UIParent, "GetTalent", { 134370 })
    emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 17783 }, {})
    local points, preceding = "Spend 15 more points in Holy Talents", "Requires all preceding talents"
    local border = GameTooltip.NineSlice
    local previousAtlas, previousAlpha = border.Center:GetAtlas(), border:GetAlpha()
    border.Center:SetAtlas("talent-tooltip-center")
    border:SetAlpha(0.8)
    GameTooltip:AddLine("Rank 0/5")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Passive")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(points, 1, 0, 0)
    GameTooltip:AddLine(preceding, 1, 0, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine("Addon label", "Addon value")
    show()
    equal(GameTooltip:GetAlpha(), 0, "translation-only replaces the talent tooltip")
    equal(spec.tip.NineSlice.Center:GetAtlas(), "talent-tooltip-center", "replacement inherits the native backdrop atlas")
    equal(spec.tip.NineSlice:GetAlpha(), 0.8, "replacement inherits the native backdrop opacity")
    equal(border.Center:GetAtlas(), "talent-tooltip-center", "replacement leaves the native backdrop untouched")
    border.Center:SetAtlas(previousAtlas)
    border:SetAlpha(previousAlpha)
    equal(GameTooltip:GetLeftLine(7):GetText(), points, "the native tooltip retains its point requirement")
    equal(GameTooltip:GetLeftLine(8):GetText(), preceding, "the native tooltip retains its preceding-talent requirement")
    local extraRows = 0
    for index = 1, spec.tip:NumLines() do
        local text = spec.tip:GetLeftLine(index):GetText()
        if text == "Addon label" then extraRows = extraRows + 1 end
        equal((text == points or text == preceding) and text or nil, nil,
            "translation-only omits the same purchase requirements as stacked")
    end
    equal(extraRows, 1, "the talent renderer retains an unrelated addon row once")
    equal(spec.tip:GetLeftLine(3):GetText(), " ", "the rank and talent details retain their spacer")
    equal(spec.tip:GetLeftLine(5):GetText(), " ", "a spacer preceding retained addon content remains")
    equal(spec.tip:GetLeftLine(6):GetText(), "Addon label", "purchase-only spacers are removed before the addon content")
    emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 17783 }, {})
    GameTooltip:AddLine("Rank 0/5")
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(points, 1, 0, 0)
    GameTooltip:AddLine(preceding, 1, 0, 0)
    GameTooltip:AddLine(" ")
    show()
    equal(spec.tip:NumLines(), 3, "the translated talent retains only its title, rank and incomplete notice")
    equal(spec.tip:GetLeftLine(3):GetText(), Addon:GetIncompleteTranslationNotice(),
        "the incomplete notice immediately follows the talent details when prerequisites are removed")
    GameTooltip:Hide()
    Addon:SetTranslationOnly(false)
    GetLocale = getLocale
    Addon.GetClientLabel = getClientLabel
    Addon:SetTargetLocale("enUS")
end
prepare(UIParent, "GetTalent", { 134370 })
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 17783, lines = {} })
show()
local nativeRebuild = GameTooltip.RebuildFromTooltipInfo
function GameTooltip:RebuildFromTooltipInfo()
    emit(self, self.processingInfo.tooltipData)
end
Addon:SetFeatureEnabled("talentTooltip", false)
equal(VisibleTooltipLines(GameTooltip), 2, "talent switch removes the translation independently")
Addon:SetFeatureEnabled("talentTooltip", true)
equal(spec.tip.lines[1], "Fel Concentration", "talent switch restores the translation")
GameTooltip.RebuildFromTooltipInfo = nativeRebuild
local talentButton = CreateFrame("Button", nil, UIParent)
talentButton.talentFrame = {}
function talentButton:GetSpellID() return 17783 end
function talentButton:SetTooltipInternal()
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Native talent title")
    EventRegistry:TriggerEvent("TalentDisplay.TooltipHook", self)
    GameTooltip:AddLine("Native talent details")
end
prepare(talentButton)
talentButton:SetTooltipInternal()
show()
equal(spec.kind, "talent", "native manually rendered talents also use their component")
equal(spec.tip:GetText(), "Fel Concentration", "manual talent translation uses a separate tooltip")
equal(GameTooltip.lines[2], "Native talent details", "manual talent details stay native")
Addon:SetFeatureEnabled("talentTooltip", false)
equal(VisibleTooltipLines(GameTooltip), 2, "manual talent rebuild removes disabled translation")
Addon:SetFeatureEnabled("talentTooltip", true)
equal(spec.tip:GetText(), "Fel Concentration", "manual talent translation is restored")
for index = 1, 3 do show() end
equal(VisibleTooltipLines(GameTooltip), 2, "manual talent show callbacks never append translated rows")

prepare(UIParent, "GetMountBySpellID", { 458 })
emit(GameTooltip, { type = Enum.TooltipDataType.Mount, id = 999999999, lines = {} })
show()
equal(spec.kind, "mount", "collection mount uses the mount component")
equal(spec.id, 458, "mount lookup uses the getter's spell ID rather than a mount row ID")
equal(spec.tip.lines[1], "Brown Horse", "mount name comes from the real spell DB")
prepare(UIParent, "GetToyByItemID", { 5626 })
emit(GameTooltip, { type = Enum.TooltipDataType.Toy, id = 5626, lines = {} })
show()
equal(spec.kind, "item", "collection toy IDs use the item component")
equal(spec.tip.lines[1], "Skullchipper", "toy uses a separate translated item tooltip")
equal(spec.tip:IsShown(), true, "toy replaces the previous entity's companion")

C_PetJournal = { GetPetInfoBySpeciesID = function(id)
    if id == 43 then return "Chat tigré orange", nil, nil, 7382 end
    return "Espèce inconnue", nil, nil, 999999999
end }
BattlePetTooltip.left, BattlePetTooltip.top = 300, 700
BattlePetTooltip:SetSize(260, 122)
BattlePetToolTip_Show(43)
context.hooks.BattlePetToolTip_Show(43)
local pet = Addon.nameTooltips[BattlePetTooltip]
equal(pet.kind, "pet", "native battle-pet tooltip has its own companion")
equal(pet.tip:GetText(), "Orange Tabby", "pet species maps to a real catalog creature")
equal(pet.tip.template, "GameTooltipTemplate", "pet companion stays native")
context.hooks.BattlePetToolTip_Show(999999999)
equal(pet.tip:IsShown(), false, "missing species names keep the original pet tooltip alone")
BattlePetTooltip:Hide()

local previousClientLabel = Addon.GetClientLabel
Addon.GetClientLabel = function(_, key, locale) return ForeverRosettaStoneDB:GetGlobalStringByKey(key, locale) end
local previousTradeSkillUI, previousItemInfoInstant = C_TradeSkillUI, C_Item.GetItemInfoInstant
local previousReagents, previousTotems = SPELL_REAGENTS, SPELL_TOTEMS
ClientApi.InstallGlobals("frFR", {"SPELL_REAGENTS", "SPELL_TOTEMS"})
C_TradeSkillUI = {
    GetRecipeSchematic = function(id, recraft)
        assert(id == 7418 and recraft == false, "requirements belong to the displayed recipe ID")
        return { recipeID = id, reagentSlotSchematics = { { reagents = { { itemID = 10940 } } } } }
    end,
    GetRecipeRequirements = function() error("Tool translation uses owned category IDs") end,
}
C_Item.GetItemInfoInstant = function(value)
    assert(value == "Bâtonnet runique en cuivre", "only a client-owned recipe tool is resolved")
    error("Tool translation must not depend on the item-name cache")
end
prepare()
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 7418 }, {
    { leftText = "Outils : |cffff2020Bâtonnet runique en cuivre|r" },
    { leftText = "Composants : |n|cffff2020Poussière étrange|r (7)" },
})
show()
spec = Addon.nameTooltips[GameTooltip]
equal(spec.tip.lines[2], "Tools: |cffff2020Runed Copper Rod|r", "recipe tools translate with native requirement colors")
equal(spec.tip.lines[3], "Reagents: |n|cffff2020Strange Dust|r (7)", "recipe reagents translate with native quantities and colors")
equal(#spec.tip.lines, 3, "known recipe requirements have no incomplete footer")
Addon.GetClientLabel = previousClientLabel
C_TradeSkillUI, C_Item.GetItemInfoInstant = previousTradeSkillUI, previousItemInfoInstant
SPELL_REAGENTS, SPELL_TOTEMS = previousReagents, previousTotems

local nativeTitle = GameTooltip.TextLeft1
local nativeFont = { nativeTitle:GetFont() }
local nativeColor = { nativeTitle:GetTextColor() }
local nativeShadow = { nativeTitle:GetShadowColor() }
local nativeShadowOffset = { nativeTitle:GetShadowOffset() }
local nativeSpacing, nativeAlpha = nativeTitle:GetSpacing(), GameTooltip:GetAlpha()
local nativeBackground = { GameTooltip.NineSlice:GetCenterColor() }
local nativeBorder = { GameTooltip.NineSlice:GetBorderColor() }
nativeTitle:SetFont("Fonts/Minimap.ttf", 12, "OUTLINE")
nativeTitle:SetTextColor(1, 0.82, 0, 1)
nativeTitle:SetShadowColor(0, 0, 0, 0.8)
nativeTitle:SetShadowOffset(2, -2)
nativeTitle:SetSpacing(1)
GameTooltip:SetAlpha(0.85)
GameTooltip.NineSlice:SetCenterColor(0.02, 0.03, 0.04, 0.9)
GameTooltip.NineSlice:SetBorderColor(0.8, 0.7, 0.5, 1)
prepare(UIParent, "GetMinimapMouseover")
emit(GameTooltip, { type = Enum.TooltipDataType.MinimapMouseover, lines = {
    { leftText = "Tailleur chez les nains" },
} })
show()
equal(spec.kind, nil, "a title-only minimap marker stays native")
equal(spec.tip:IsShown(), false, "a title-only minimap marker has no companion")
emit(GameTooltip, { type = Enum.TooltipDataType.MinimapMouseover, lines = {
    { questID = 179, leftText = "Tailleur chez les nains" },
} })
show()
equal(spec.kind, "minimapQuest", "a supplied quest ID resolves to a quest component")
equal(spec.id, 179, "minimap uses the supplied quest ID")
equal(spec.tip:GetText(), "Dwarven Outfitters",
    "minimap quest title contains no addon logo")
equal(spec.tip.points[1][1], "TOPLEFT", "minimap quest translation sits on the right")
equal(spec.tip.points[1][3], "TOPRIGHT", "minimap quest translation uses horizontal placement")
equal(GameTooltip.points[1][1], "BOTTOMRIGHT", "minimap quest translation preserves the native anchor")
equal(select(1, spec.tip.TextLeft1:GetFont()), "Fonts/Minimap.ttf", "minimap companion uses the native font face")
equal(select(2, spec.tip.TextLeft1:GetFont()), 12, "minimap companion uses the native font size")
equal(select(3, spec.tip.TextLeft1:GetFont()), "OUTLINE", "minimap companion uses the native font flags")
equal(spec.tip.titleColor[2], 0.82, "minimap companion inherits the rendered title color without data colors")
equal(select(4, spec.tip.TextLeft1:GetShadowColor()), 0.8, "companion inherits native shadow opacity")
equal(select(1, spec.tip.TextLeft1:GetShadowOffset()), 2, "companion inherits native shadow offset")
equal(spec.tip.TextLeft1:GetSpacing(), 1, "companion inherits native line spacing")
equal(spec.tip:GetAlpha(), 0.85, "companion inherits native tooltip opacity")
equal(select(2, spec.tip.NineSlice:GetCenterColor()), 0.03, "companion inherits native background color")
equal(select(4, spec.tip.NineSlice:GetCenterColor()), 0.9, "companion inherits native background opacity")
equal(select(1, spec.tip.NineSlice:GetBorderColor()), 0.8, "companion inherits native border color")
equal(select(2, nativeTitle:GetFont()), 12, "matching a tooltip leaves the source font untouched")
nativeTitle:SetFont(unpack(nativeFont))
nativeTitle:SetTextColor(unpack(nativeColor))
nativeTitle:SetShadowColor(unpack(nativeShadow))
nativeTitle:SetShadowOffset(unpack(nativeShadowOffset))
nativeTitle:SetSpacing(nativeSpacing)
GameTooltip:SetAlpha(nativeAlpha)
GameTooltip.NineSlice:SetCenterColor(unpack(nativeBackground))
GameTooltip.NineSlice:SetBorderColor(unpack(nativeBorder))
emit(GameTooltip, { type = Enum.TooltipDataType.MinimapMouseover, lines = { { leftText = "Unknown marker" } } })
equal(spec.tip:IsShown(), false, "unknown minimap titles do not retain another quest")
emit(GameTooltip, { type = Enum.TooltipDataType.MinimapMouseover, lines = { { questID = 179 } } })
equal(spec.id, 179, "minimap uses a supplied quest ID when available")

MinimapCluster = { ZoneTextButton = CreateFrame("Button", nil, UIParent) }
local previousLocationMap, previousExploration = C_Map, C_MapExplorationInfo
C_Map = {
    GetBestMapForUnit = function() return 1426 end,
    GetMapInfo = function(id)
        if id == 1426 then return { mapID = 1426, name = "Dun Morogh", mapType = 3, parentMapID = 0 } end
        return previousLocationMap.GetMapInfo(id)
    end,
    GetPlayerMapPosition = function() return { x = 0.29, y = 0.68 } end,
    GetAreaInfo = function(id) if id == 132 then return "Vallée des Frigères" end end,
}
C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return { 132 } end }
local locationMap, locationExploration = C_Map, C_MapExplorationInfo
GetZoneText = function() return "Dun Morogh" end
GetSubZoneText = function() return "Vallée des Frigères" end
prepare(MinimapCluster.ZoneTextButton)
function MinimapCluster.ZoneTextButton:OnEnter()
    GameTooltip:ClearLines()
    GameTooltip:GetLeftLine(1):SetFont("Fonts/Zone.ttf", 16, "OUTLINE")
    GameTooltip:GetLeftLine(1):SetTextScale(0.9)
    GameTooltip:AddLine(GetZoneText())
    if GetSubZoneText() ~= "" and GetSubZoneText() ~= GetZoneText() then
        local line = GameTooltip:GetLeftLine(GameTooltip:NumLines() + 1)
        line:SetFont("Fonts/Subzone.ttf", 12, "")
        line:SetTextScale(0.8)
        GameTooltip:AddLine(GetSubZoneText())
    end
    GameTooltip:AddLine("Carte du monde (M)")
    GameTooltip:Show()
end
MinimapCluster.ZoneTextButton:OnEnter()
context.flushTimers()
equal(spec.kind, "minimapLocation", "minimap zone heading is recognized by its native owner")
equal(GameTooltip.lines[1], "Dun Morogh", "zone stays first")
equal(GameTooltip.lines[2], "Vallée des Frigères", "native subzone stays second")
equal(GameTooltip.lines[3], "Carte du monde (M)", "World Map hint stays native and last")
equal(spec.tip:GetText(), "Dun Morogh", "zone appears once in the separate translated tooltip")
equal(spec.tip.lines[1], "Coldridge Valley", "subzone follows the translated zone without a logo")
equal(select(2, spec.tip:GetLeftLine(1):GetFont()), 16, "zone translation matches zone font size")
equal(select(2, spec.tip:GetLeftLine(2):GetFont()), 12, "subzone translation matches subzone font size")
equal(spec.tip:GetLeftLine(1):GetTextScale(), 0.9, "zone translation matches zone text scale")
equal(spec.tip:GetLeftLine(2):GetTextScale(), 0.8, "subzone translation matches subzone text scale")
equal(spec.tip:IsShown(), true, "location has a separate stacked companion")
equal(spec.tip.points[1][1], "TOPLEFT", "minimap location translation sits right of the native tooltip")
equal(GameTooltip.points[1][1], "BOTTOMRIGHT", "minimap location preserves the native anchor")
spec.tip.accurateLines = true
Addon:SetTooltipMode("stacked")
equal(GameTooltip:GetLeftLine(3):GetText(), "Carte du monde (M)", "Stacked preserves the native map hint")
equal(GameTooltip:GetLeftLine(6):GetText(), "Dun Morogh", "Stacked includes the translated zone")
equal(GameTooltip:GetLeftLine(7):GetText(), "Coldridge Valley", "Stacked includes the translated subzone")
local locationRows = VisibleTooltipLines(GameTooltip)
for index = 1, 3 do show() end
equal(VisibleTooltipLines(GameTooltip), locationRows, "repeated layouts do not duplicate stacked location rows")
Addon:SetFeatureEnabled("minimapLocationTooltip", false)
equal(VisibleTooltipLines(GameTooltip), 3, "disabling location translations restores native rows")
Addon:SetFeatureEnabled("minimapLocationTooltip", true)
equal(VisibleTooltipLines(GameTooltip), locationRows, "enabling location translations restores the stacked block")
Addon:SetTooltipMode("separate")
equal(GameTooltip:GetLeftLine(1):GetText(), "Dun Morogh", "separate mode restores the native zone")
equal(GameTooltip:GetLeftLine(2):GetText(), "Vallée des Frigères", "separate mode restores the native subzone")
equal(spec.tip:IsShown(), true, "separate mode restores the companion")
for index = 1, 3 do show() end
equal(VisibleTooltipLines(GameTooltip), 3, "repeated shows do not insert native location rows")
Addon:SetFeatureEnabled("minimapLocationTooltip", false)
equal(VisibleTooltipLines(GameTooltip), 3, "disabling location translation rebuilds native content only")
Addon:SetFeatureEnabled("minimapLocationTooltip", true)
equal(spec.tip:IsShown(), true, "enabling location translation restores the separate tooltip")
local knownSubzone = GetSubZoneText
GetSubZoneText = function() return "Unresolved subzone" end
MinimapCluster.ZoneTextButton:OnEnter()
context.flushTimers()
equal(spec.tip:IsShown(), true, "an unresolved second native line does not hide the known zone")
equal(spec.tip:GetText(), "Dun Morogh", "the resolved zone remains in the translated tooltip")
equal(GameTooltip:GetLeftLine(2):GetText(), "Unresolved subzone", "unknown native subzone remains unchanged")
Addon:SetTooltipMode("stacked")
equal(GameTooltip:GetLeftLine(6):GetText(), "Dun Morogh", "stacked mode also retains the resolved zone")
Addon:SetTooltipMode("separate")
GetSubZoneText = knownSubzone
GetZoneText = function() return "Unknown zone" end
MinimapCluster.ZoneTextButton:OnEnter()
context.flushTimers()
equal(spec.tip:GetText(), "Coldridge Valley",
    "missing zone translation does not prevent the subzone translation")
GetSubZoneText = function() return "Unknown zone" end
MinimapCluster.ZoneTextButton:OnEnter()
context.flushTimers()
equal(VisibleTooltipLines(GameTooltip), 2, "unknown zone and identical subzone add no translation")
equal(spec.tip:IsShown(), false, "unknown locations hide the translated tooltip")
GetZoneText = function() return "Dun Morogh" end
GetSubZoneText = function() return "" end
MinimapCluster.ZoneTextButton:OnEnter()
context.flushTimers()
equal(VisibleTooltipLines(GameTooltip), 2, "empty subzone leaves native zone and map hint only")
equal(spec.tip:GetText(), "Dun Morogh", "empty subzone produces one translated location title")
GameTooltip:Hide()
GameTooltip:GetLeftLine(1):SetFont(unpack(nativeFont))
GameTooltip:GetLeftLine(1):SetTextScale(1)
C_Map, C_MapExplorationInfo = previousLocationMap, previousExploration

local active, selected = SmartNavigation.activeFrame, SmartNavigation.currentButton
QuestObjectiveTracker = {}
ObjectiveTrackerFrame = CreateFrame("Frame", nil, UIParent)
local block = CreateFrame("Frame", nil, ObjectiveTrackerFrame)
block.parentModule, block.id = QuestObjectiveTracker, 7900
block.left, block.top = 1200, 850
block:SetSize(250, 100)
local header = CreateFrame("Button", nil, block)
block.HeaderText = CreateFrame("FontString", nil, block)
block.HeaderText.left, block.HeaderText.top = 1200, 844
block.HeaderText:SetSize(250, 18)
block.poiButton = CreateFrame("Button", nil, block)
block.poiButton.left, block.poiButton.top = 1165, 849
block.poiButton:SetSize(28, 28)
local getObjectives = C_QuestLog.GetQuestObjectives
local current = 2
C_QuestLog.GetQuestObjectives = function(id)
    if id == 7900 then return {{ type = "item", numFulfilled = current, numRequired = 7 }} end
    return getObjectives(id)
end
context.setMouseFoci({ header })
Addon:UpdateQuestTrackerTooltip()
local tracker = Addon.questTrackerTooltip
equal(tracker:GetLeftLine(2):GetText(), ForeverRosettaStoneDB:GetQuest(7900, "enUS").title, "tracker uses the actual tracked quest")
equal(tracker.points[1][1], "TOPRIGHT", "right-side tracker uses its inward placement strategy")
equal(tracker.points[1][2], block.poiButton, "tracker anchors to the left of the quest button")
equal(tracker.points[1][4], -2, "tracker leaves a small gap before the quest button")
equal(tracker.points[1][5], -5, "tracker top aligns with the quest title relative to the button")
context.setMouseFoci({ block.poiButton })
block.left, block.HeaderText.left = 1670, 1670
block.poiButton.left = 1635
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), true, "hovering the quest question mark shows a translation at the right screen edge")
equal(tracker.points[1][1], "TOPRIGHT", "right-edge tracker translation grows into available space")
equal(block:GetLeft(), 1670, "tracker placement never moves the native quest block")
block.left, block.HeaderText.left = 100, 100
block.poiButton.left = 65
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), false, "tracker hides when its requested left placement cannot fit on screen")
equal(block:GetLeft(), 100, "left placement never shifts the quest block to make room")
block.left, block.HeaderText.left = 1200, 1200
block.poiButton.left = 1165
context.setMouseFoci({ header })
tracker.top, tracker.TextLeft1.top = 700, 690
Addon:UpdateQuestTrackerTooltip()
equal(tracker.points[1][5], 5, "tracker text alignment accounts for the tooltip's native title inset")
block:SetScale(0.8)
Addon:UpdateQuestTrackerTooltip()
equal(math.abs(tracker.points[1][5] - 5) < 0.001, true, "tracker title alignment follows the native block scale")
block:SetScale(1)
local poiButton = block.poiButton
block.poiButton = nil
Addon:UpdateQuestTrackerTooltip()
equal(tracker.points[1][2], block, "quests without a POI button use their block edge")
block.poiButton = poiButton
tracker.top, tracker.TextLeft1.top = nil, nil
equal(tracker.lines[#tracker.lines]:find("2/7", 1, true) ~= nil, true, "tracker reads live progress")
equal(#tracker.lines, 3, "tracker objectives immediately follow the translation label and quest title")
equal(tracker.lines[3]:find("- ", 1, true), 1, "there is no blank row between the quest title and objectives")
equal(tracker.lines[1]:find("Traduit en anglais", 1, true) ~= nil, true,
    "standalone tracker identifies the FRS target in the game language")
equal(tracker.lines[1]:find("media\\icon", 1, true) ~= nil, true, "standalone tracker includes the Rosetta logo")
equal(tracker.lines[1]:find("media\\flags", 1, true), nil, "standalone tracker contains no country flag")
current = 3
Addon:UpdateQuestTrackerTooltip()
equal(tracker.lines[#tracker.lines]:find("3/7", 1, true) ~= nil, true, "tracker refreshes current progress")
local isComplete = C_QuestLog.IsComplete
local trackerClientLabel = Addon.GetClientLabel
Addon.GetClientLabel = function(_, key, locale) return ForeverRosettaStoneDB:GetGlobalStringByKey(key, locale) end
C_QuestLog.IsComplete = function(id) return id == 7900 or isComplete(id) end
Addon:UpdateQuestTrackerTooltip()
equal(#tracker.lines, 3, "completed tracker has the same compact spacing as an incomplete tracker")
equal(tracker.lines[3], "Ready for turn-in", "completed status uses the native turn-in GlobalString")
GameTooltip:SetOwner(header, "ANCHOR_NONE")
GameTooltip:SetText("Quête suivie")
GameTooltip:SetSize(200, 150)
GameTooltip.left, GameTooltip.top = 600, 1060
GameTooltip:Show()
Addon:UpdateQuestTrackerTooltip()
equal(tracker.points[1][2], GameTooltip, "tracker stacks with its own native hover tooltip when present")
equal(tracker.points[1][1], "TOPLEFT", "tracker translation sits right of its native hover tooltip")
equal(GameTooltip.left, 600, "tracker leaves the native tooltip at its original position")
equal(#tracker.lines, 1, "native tracker enhancements omit the standalone label and blank rows")
GameTooltip:Hide()
Addon:UpdateQuestTrackerTooltip()
equal(#tracker.lines, 3, "hiding the native tooltip restores exactly one standalone translation label")
Addon:UpdateQuestTrackerTooltip()
equal(#tracker.lines, 3, "repeated standalone refreshes do not accumulate labels")
C_QuestLog.IsComplete = isComplete
Addon.GetClientLabel = trackerClientLabel
context.setMouseFoci({})
SmartNavigation.activeFrame, SmartNavigation.currentButton = ObjectiveTrackerFrame, header
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), true, "controller-focused tracker quests are supported")
local forbiddenFocus = CreateFrame("Button", nil, UIParent)
function forbiddenFocus:IsForbidden() return true end
function forbiddenFocus:GetParent() error("forbidden focus must not be traversed") end
function forbiddenFocus:GetElementData() error("forbidden focus data must not be read") end
local forbiddenChild = CreateFrame("Button", nil, forbiddenFocus)
SmartNavigation.activeFrame = WorldMapFrame
context.setMouseFoci({ forbiddenFocus })
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), false, "forbidden spell focus hides an old tracker companion")
context.setMouseFoci({ forbiddenChild, header })
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), true, "forbidden ancestor is skipped without losing another valid mouse focus")
context.setMouseFoci({})
SmartNavigation.activeFrame, SmartNavigation.currentButton = ObjectiveTrackerFrame, forbiddenChild
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), false, "controller focus with a forbidden ancestor is ignored")
SmartNavigation.activeFrame = WorldMapFrame
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), false, "leaving tracker focus hides its companion")
context.setMouseFoci({ header })
block.id = 999999999
Addon:UpdateQuestTrackerTooltip()
equal(tracker:IsShown(), false, "recycled tracker blocks cannot retain stale quests")
block.id = 7900
C_QuestLog.GetQuestObjectives = getObjectives

GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
local offer = CreateFrame("Button", nil, GossipFrame)
offer.left, offer.top = 400, 700
offer:SetSize(300, 32)
local offerID = 179
function offer:GetElementData() return { info = { questID = offerID } } end
context.setMouseFoci({ offer })
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:GetLeftLine(2):GetText(), "Dwarven Outfitters", "offered NPC quest title uses its ScrollBox quest ID")
equal(Addon.questOfferTooltip.lines[1]:find("Traduit en anglais", 1, true) ~= nil, true,
    "standalone offered quests identify their translation locale")
equal(Addon.questOfferTooltip:GetOwner(), offer, "quest offer companion belongs to the native row")
local questOfferElement = offer.GetElementData
for _, element in ipairs({ 179, "gossip option", true, { info = 179 }, { info = "gossip" }, { secret = true } }) do
    function offer:GetElementData() return element end
    Addon:UpdateQuestOfferTooltip()
    equal(Addon.questOfferTooltip:IsShown(), false, "non-quest gossip rows clear the quest tooltip without crashing")
    context.setMouseFoci({})
    SmartNavigation.activeFrame, SmartNavigation.currentButton = GossipFrame, offer
    Addon:UpdateQuestOfferTooltip()
    equal(Addon.questOfferTooltip:IsShown(), false, "controller selection safely ignores non-quest gossip data")
    context.setMouseFoci({ offer })
end
offer.GetElementData = questOfferElement
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:IsShown(), true, "quest offers still resolve after a non-quest gossip row")
context.setMouseFoci({})
SmartNavigation.activeFrame, SmartNavigation.currentButton = GossipFrame, offer
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:IsShown(), true, "controller-focused NPC quest offers are supported")
SmartNavigation.activeFrame = WorldMapFrame
context.setMouseFoci({ forbiddenFocus })
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:IsShown(), false, "quest offers also skip forbidden spell focus")
context.setMouseFoci({ forbiddenChild, offer })
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:IsShown(), true, "quest offer lookup continues after a forbidden ancestor")
context.setMouseFoci({})
SmartNavigation.activeFrame, SmartNavigation.currentButton = GossipFrame, forbiddenChild
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:IsShown(), false, "quest offers ignore forbidden controller ancestors")
SmartNavigation.currentButton = offer
offerID = 999999999
Addon:UpdateQuestOfferTooltip()
equal(Addon.questOfferTooltip:IsShown(), false, "recycled NPC quest rows do not display old titles")
SmartNavigation.activeFrame, SmartNavigation.currentButton = active, selected
context.setMouseFoci({})
GossipFrame:Hide()

local previousGossipInfo = C_GossipInfo
local auction = { gossipOptionID = 96916, orderIndex = 0, name = "Hôtel des ventes" }
local trainer = { gossipOptionID = 96904, orderIndex = 13, name = "Maître de profession" }
local gossipOptions = { trainer, auction }
C_GossipInfo = {
    GetOptions = function() return gossipOptions end,
    GetActiveQuests = function() return {} end,
    GetAvailableQuests = function() return {} end,
}
GossipFrame:Show()
local gossipRow = CreateFrame("Button", nil, GossipFrame)
gossipRow.left, gossipRow.top = 400, 700
gossipRow:SetSize(300, 32)
local gossipElement, gossipOrder, gossipText = { info = auction }, 0, auction.name
function gossipRow:GetElementData() return gossipElement end
function gossipRow:GetID() return gossipOrder end
function gossipRow:GetText() return gossipText end
context.setMouseFoci({ gossipRow })
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "Auction House", "gossip tooltip uses stable option IDs, not API array order")
equal(Addon.gossipOptionTooltip:GetOwner(), gossipRow, "gossip translation belongs to the native option row")
gossipElement = 1
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "Auction House", "numeric gossip elements resolve the live zero-based orderIndex")
gossipOrder, gossipText = 13, trainer.name
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "Profession Trainer", "sparse orderIndex is not used as an array offset")
context.setMouseFoci({})
SmartNavigation.activeFrame, SmartNavigation.currentButton = GossipFrame, gossipRow
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), true, "controller-focused gossip options receive translations")
gossipOptions = { auction, trainer }
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "Profession Trainer", "reordered live options keep their identity")
gossipText = "Different option"
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "recycled numeric rows with different text do not reuse a translation")
gossipElement = { info = { gossipOptionID = 96904, name = "Stale option" } }
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "stale structured row data must match the live option")
gossipElement = { info = auction }
gossipOptions = { trainer }
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "options removed from the live menu clear their tooltip")
local unknownOption = { gossipOptionID = 999999999, orderIndex = 0, name = "Unknown option" }
gossipElement, gossipOptions = { info = unknownOption }, { unknownOption }
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "uncataloged options preserve native text without guessing")
unknownOption.icon = 132057
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "I need a ride.",
    "an uncataloged flight option gets the shared label by its native icon")
unknownOption.gossipOptionID = nil
gossipOrder, gossipText = unknownOption.orderIndex, unknownOption.name
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "I need a ride.",
    "a flight option with no ID still gets the shared label")
auction.icon = 132057
gossipElement, gossipOptions = { info = auction }, { auction }
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "Auction House",
    "an explicit option translation takes priority over its icon")
auction.icon = nil
gossipElement, gossipOptions = { info = auction }, { auction, auction }
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "ambiguous options do not display a guessed translation")
gossipOptions = { auction }
Addon.preferences.features.gossipOptionTooltip = false
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "gossip translation respects its feature toggle")
Addon.preferences.features.gossipOptionTooltip = true
Addon:SetTargetLocale("deDE")
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:GetLeftLine(2):GetText(), "Auktionshaus", "gossip translation follows the target locale")
Addon:SetTargetLocale("enUS")
GossipFrame:Hide()
Addon:UpdateGossipOptionTooltip()
equal(Addon.gossipOptionTooltip:IsShown(), false, "closing the menu hides the gossip translation")
C_GossipInfo = previousGossipInfo
SmartNavigation.activeFrame, SmartNavigation.currentButton = active, selected
context.setMouseFoci({})

Enum.TooltipDataLineType.QuestTitle = 17
ClientApi.InstallGlobals("frFR", {"QUEST_TOOLTIP_REQUIREMENTS"})
ItemRefTooltip:SetOwner(UIParent, "ANCHOR_NONE")
ItemRefTooltip:SetText("Protection du troupeau")
ItemRefTooltip:SetSize(200, 250)
ItemRefTooltip.left, ItemRefTooltip.top = 700, 700
local questSummary = "Sur demande de Rudra Amberstill, tuer Vagash et rapporter un de ses crocs à la ferme des Amberstill."
emit(ItemRefTooltip, { type = Enum.TooltipDataType.Quest, id = 314 }, {
    { leftText = questSummary }, { leftText = "" }, { leftText = "Conditions :" }, { leftText = " - 1 x Croc de Vagash" },
})
ItemRefTooltip:Show()
context.flushTimers()
local linkedQuest = Addon.nameTooltips[ItemRefTooltip]
equal(linkedQuest.kind, "quest", "chat quest links use their own quest component")
equal(linkedQuest.tip:IsShown(), true, "chat quest translations work without an open World Map")
equal(linkedQuest.tip.lines[1], "Protecting the Herd", "chat quest title is translated without a logo or level")
equal(linkedQuest.tip.lines[2], ForeverRosettaStoneDB:GetQuest(314, "enUS").summary, "full chat quest summary uses the owned translation")
equal(linkedQuest.tip.lines[4], "Requirements:", "shared quest requirements heading translates")
equal(linkedQuest.tip.lines[5], " - 1 x Fang of Vagash", "chat requirements translate the owned item and preserve the native count")
equal(#linkedQuest.tip.lines, 5, "fully translated chat quests have no incomplete footer")
equal(linkedQuest.tip.points[1][3], "TOPRIGHT", "chat quest translations sit right of the native tooltip")
equal(VisibleTooltipLines(ItemRefTooltip), 5, "chat quest translation leaves native content unchanged")
ItemRefTooltip.left = 1000
ItemRefTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -100, 100)
context.flushTimers()
equal(linkedQuest.tip.points[1][2], ItemRefTooltip, "moving a chat link keeps its translation attached")
equal(linkedQuest.tip.points[1][3], "TOPRIGHT", "moving chat links retain Native | FRS ordering")
Addon:SetFeatureEnabled("questTooltip", false)
equal(linkedQuest.tip:IsShown(), false, "quest tooltip preference also controls chat quest links")
Addon:SetFeatureEnabled("questTooltip", true)
equal(linkedQuest.tip:IsShown(), true, "enabling quest translations restores the chat link")
-- Coverage and layout are independent: full quest fields must work in both layouts.
local function refreshQuestLink(id, body)
    emit(ItemRefTooltip, { type = Enum.TooltipDataType.Quest, id = id }, body)
    ItemRefTooltip:Show()
    context.flushTimers()
    linkedQuest = Addon.nameTooltips[ItemRefTooltip]
end
local herdBody = { { leftText = questSummary }, { leftText = "" }, { leftText = "Conditions :" },
    { leftText = " - 1 x Croc de Vagash" } }
Addon.preferences.tooltipCoverage = "name"
refreshQuestLink(314, herdBody)
equal(linkedQuest.tip:GetText(), "Protecting the Herd", "name-only quest links keep their translated title")
equal(#linkedQuest.tip.lines, 0, "name-only quest links add no summary or requirement rows")
Addon.preferences.tooltipCoverage = "full"
refreshQuestLink(314, herdBody)
equal(linkedQuest.tip.lines[2], ForeverRosettaStoneDB:GetQuest(314, "enUS").summary,
    "switching back to full restores the translated quest summary")
refreshQuestLink(314, {
    { leftText = questSummary }, { leftText = "Conditions :" }, { leftText = " - 7 x Croc de Vagash" },
    { leftText = "Une condition inconnue" },
})
context.flushTimers()
equal(linkedQuest.tip.lines[4], " - 7 x Fang of Vagash", "link quantities come from the displayed row")
equal(linkedQuest.tip.lines[5], "Une condition inconnue", "unknown requirements preserve native text")
equal(linkedQuest.tip.lines[6], Addon:GetIncompleteTranslationNotice(), "unknown rows retain the incomplete notice")
local jasperlode = ForeverRosettaStoneDB:GetQuest(76, "frFR")
refreshQuestLink(76, {
    { leftText = jasperlode.summary }, { leftText = "" }, { leftText = "Conditions :" },
    { leftText = " - Explorer la mine Veine-de-jaspe" },
})
context.flushTimers()
equal(linkedQuest.tip.lines[2], ForeverRosettaStoneDB:GetQuest(76, "enUS").summary,
    "Jasperlode full link translates its summary")
equal(linkedQuest.tip.lines[5], " - Scout through the Jasperlode Mine",
    "single event requirement uses the quest event translation without quest-log progress")
equal(#linkedQuest.tip.lines, 5, "Jasperlode has no incomplete footer")
local objectiveQuest = ForeverRosettaStoneDB:GetQuest(943, "frFR")
local targetObjectives = ForeverRosettaStoneDB:GetQuest(943, "enUS").objectiveLines
local objectiveBody = { { leftText = "Conditions :" } }
for _, objective in ipairs(objectiveQuest.objectiveLines) do
    objectiveBody[#objectiveBody + 1] = { leftText = " - " .. objective.text
        :gsub("{current}", "3"):gsub("{required}", "9") }
end
local translatedObjectives = Addon:GetQuestLinkTranslations({ id = 943, data = { lines = objectiveBody } }, "enUS")
for index, objective in ipairs(targetObjectives) do
    equal(translatedObjectives[objectiveBody[index + 1]], " - " .. objective.text
        :gsub("{current}", "3"):gsub("{required}", "9"),
        "multiple objective templates preserve the displayed progress at index " .. index)
end
Addon:SetTargetLocale("deDE")
Addon:UpdateNameTooltip(ItemRefTooltip, "quest", 76)
context.flushTimers()
linkedQuest = Addon.nameTooltips[ItemRefTooltip]
equal(linkedQuest.tip.lines[2], ForeverRosettaStoneDB:GetQuest(76, "deDE").summary,
    "full quest links also translate to a non-English target")
Addon:SetTargetLocale("enUS")
Addon:SetTooltipMode("stacked")
Addon:UpdateNameTooltip(ItemRefTooltip, "quest", 76)
context.flushTimers()
local combinedQuest = table.concat(ItemRefTooltip.lines, "\n")
equal(combinedQuest:find(ForeverRosettaStoneDB:GetQuest(76, "enUS").summary, 1, true) ~= nil, true,
    "stacked quest links include the translated summary")
equal(combinedQuest:find(" - Scout through the Jasperlode Mine", 1, true) ~= nil, true,
    "stacked quest links include the translated event requirement")
Addon:SetTooltipMode("separate")
emit(ItemRefTooltip, { type = Enum.TooltipDataType.Quest, id = 999999999, lines = {} })
equal(linkedQuest.tip:IsShown(), false, "unknown chat quests hide previous translations")
emit(ItemRefTooltip, { type = Enum.TooltipDataType.Quest, id = { secret = true }, lines = {} })
equal(linkedQuest.kind, nil, "secret chat quest IDs are ignored")
ItemRefTooltip:Hide()

local native = CreateFrame("Frame", nil, UIParent)
native:SetSize(200, 200)
native.left, native.top = 400, 500
native:SetPoint("CENTER", UIParent, "CENTER", 10, 20)
local tip = Addon:CreateCompanionTooltip("ForeverRosettaStonePlacementTest")
tip:SetOwner(native, "ANCHOR_NONE")
tip:SetText("Position")
tip:SetSize(180, 80)
local function placement(expectedPoint, expectedRelative)
    local rect = Addon:PlaceCompanionTooltip(tip, native)
    equal(rect ~= nil, true, "the horizontal placement fits")
    equal(tip.points[1][1], expectedPoint, "chosen companion anchor")
    equal(tip.points[1][3], expectedRelative, "chosen native edge")
    equal(rect.left >= 8 and rect.right <= UIParent:GetWidth() - 8
        and rect.bottom >= 8 and rect.top <= UIParent:GetHeight() - 8, true, "companion stays inside the screen")
    equal(native.points[1][1], "CENTER", "placement never changes native anchors")
    equal(native.points[1][4], 10, "placement never moves the native frame")
end
placement("TOPLEFT", "TOPRIGHT")
UIParent:SetSize(1000, 800)
native.left = 800
equal(Addon:PlaceCompanionTooltip(tip, native), nil, "no room on the right hides the translation without moving the original")
equal(native.left, 800, "right-edge placement leaves the native position unchanged")
UIParent:SetWidth(400)
native.left = 100
tip:SetWidth(250)
equal(Addon:PlaceCompanionTooltip(tip, native), nil, "row-attached tooltips never switch to another side")
UIParent:SetSize(1000, 800)
native.left, native.top = 400, 790
native:SetClampRectInsets(2, 3, 25, -4)
Addon.nameTooltips[native] = { group = { native } }
local stacked = Addon:PlaceCompanionTooltip(tip, native)
equal(stacked ~= nil, true, "the complete horizontal stack fits near the top edge")
equal(stacked.left, native:GetRight() + 2, "translation appears right of the original with a small gap")
equal(native:GetLeft(), 400, "native tooltip retains its original horizontal position")
equal(stacked.top <= 800 and native:GetBottom() >= 0, true, "both tooltips remain inside the screen")
equal(tip.points[1][1], "TOPLEFT", "translation remains on the right near the top edge")
equal(native.points[1][1], "CENTER", "screen-space reservation preserves the native anchor")
equal(select(1, native:GetClampRectInsets()), 2, "placement does not change native clamp insets")
Addon:PlaceCompanionTooltip(tip, native)
equal(native:GetLeft(), 400, "repeated layout does not move the native tooltip")
tip:SetWidth(300)
Addon:PlaceCompanionTooltip(tip, native)
equal(native:GetLeft(), 400, "resizing leaves the native tooltip where the client placed it")
tip:Hide()
equal(select(3, native:GetClampRectInsets()), 25, "hiding restores the native top inset")
equal(select(2, native:GetClampRectInsets()), 3, "hiding restores the native right inset")
equal(native:IsClampedToScreen(), false, "hiding restores the native clamping flag")
equal(native:GetLeft(), 400, "hiding restores the native tooltip's original position")
tip:SetHeight(80)
tip:SetWidth(180)
native.left = 800
native.protected = true
Addon.nameTooltips[native].kind = "item"
native.GetOwner = function() return UIParent end
native.GetAnchorType = function() return "ANCHOR_RIGHT" end
stacked = Addon:PlaceCompanionTooltip(tip, native)
equal(stacked ~= nil, true, "right-edge fallback supports protected native tooltips")
equal(stacked.left, 618, "right-edge fallback places the translation on the available left side")
equal(native:GetLeft(), 800, "right-edge fallback never moves the native tooltip")
Addon:PlaceCompanionTooltip(tip, native)
equal(native:GetLeft(), 800, "repeated fallback layout preserves native placement")
tip:Hide()
equal(native:GetLeft(), 800, "closing the exception restores the native position")
Addon.nameTooltips[native].kind = "item"
native.GetOwner = function() return UIParent end
native.GetAnchorType = function() return "ANCHOR_LEFT" end
native.left = 100
stacked = Addon:PlaceCompanionTooltip(tip, native)
equal(stacked.left, 302, "left-edge fallback places the translation on the available right side")
equal(native:GetLeft(), 100, "left-edge fallback never moves the native tooltip")
Addon:PlaceCompanionTooltip(tip, native)
equal(native:GetLeft(), 100, "repeated left-edge fallback preserves native placement")
equal(tip.sourcePlacements, nil, "automatic companions do not retain native placement snapshots")
equal(Addon:TransitionTooltipSources(tip, "sources.place", {
    { source = native, left = 282, top = native:GetTop() },
}), true, "explicit group placement retains its restoration contract")
local combatBeforeRestore = InCombatLockdown
InCombatLockdown = function() return true end
tip:Hide()
equal(tip.sourcePlacements ~= nil, true, "combat keeps the snapshot when protected native restoration is blocked")
equal(native:GetLeft(), 282, "blocked restoration leaves protected native placement untouched")
InCombatLockdown = combatBeforeRestore
Addon:RestoreTooltipSources()
equal(tip.sourcePlacements, nil, "combat-end cleanup clears the retained placement snapshot")
equal(native:GetLeft(), 100, "combat-end cleanup restores the original left-edge position")
Addon.nameTooltips[native].kind = nil
native.GetOwner, native.GetAnchorType = nil, nil
native.protected = false
tip:SetWidth(250)
native.left = 0
stacked = Addon:PlaceCompanionTooltip(tip, native)
equal(stacked.left, 202, "left-edge placement keeps the translation to the right")
equal(native:GetLeft(), 0, "left-edge placement preserves native coordinates")
tip:Hide()
native.left = 950
Addon.nameTooltips[native].kind = "item"
native.GetAnchorType = function() return "ANCHOR_RIGHT" end
stacked = Addon:PlaceCompanionTooltip(tip, native)
equal(stacked.left, 698, "wider translations use the available left side")
equal(stacked.right + 2, native:GetLeft(), "right-edge fallback retains the gap beside the unmoved native tooltip")
tip:Hide()
equal(native:GetLeft(), 950, "closing an edge pair restores the original native position")
Addon.nameTooltips[native].kind = nil
native.GetAnchorType = nil
Addon:PlaceCompanionTooltip(tip, native, { { left = 0, right = 1000, top = 800, bottom = 0 } })
equal(tip:IsShown(), false, "colliding stacks stay hidden")
tip:SetHeight(900)
equal(Addon:PlaceCompanionTooltip(tip, native), nil, "a stack taller than the screen is refused")
tip:SetHeight(80)
native.left = 400
native.protected = true
local isInCombat = InCombatLockdown
InCombatLockdown = function() return true end
native.SetClampRectInsets = function() error("native clamp insets must not be changed") end
native.SetClampedToScreen = function() error("native clamping must not be changed") end
local placementOwner = {}
equal(Addon:TransitionTooltipSources(placementOwner, "unknown"), false, "unknown placement events are refused")
equal(Addon:TransitionTooltipSources(placementOwner, "sources.restore"), false, "restore without a placement is refused")
equal(Addon:TransitionTooltipSources(placementOwner, "sources.place", {
    { source = native, left = 100, top = 500 },
}), false, "protected originals refuse repositioning without any writes")
equal(placementOwner.sourcePlacements, nil, "refused placement keeps its original state")
equal(Addon:PlaceCompanionTooltip(tip, native) ~= nil, true, "protected originals can have independent translated tooltips")
tip:Hide()
native.SetClampRectInsets, native.SetClampedToScreen = nil, nil
native.protected = false
InCombatLockdown = isInCombat
native:SetScale(0.8)
tip:SetScale(0.8)
native.top = 1000
stacked = Addon:PlaceCompanionTooltip(tip, native)
equal(stacked ~= nil and stacked.top <= 800, true, "scaled native and translated tooltips share the screen")
equal(math.abs(stacked.left - 2 - native:GetRight() * native:GetEffectiveScale()) < 0.001, true,
    "scaled stacking preserves the shared horizontal gap")
tip:Hide()
native:SetScale(1)
tip:SetScale(1)
Addon.nameTooltips[native] = nil
UIParent:SetSize(1920, 1080)
GameTooltip.processingInfo = nil
GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
GameTooltip:Hide()

local blockedFrame = setmetatable({ IsForbidden = function() return true end }, {
    __index = function(_, key) error("forbidden frame field accessed: " .. key) end,
})
local blockedChild = CreateFrame("Button", nil, blockedFrame)
WorldMapFrame:Show()
QuestScrollFrame:Show()
GameTooltip:SetOwner(blockedChild, "ANCHOR_NONE")
GameTooltip:Show()
context.setMouseFoci({ blockedChild })
SmartNavigation.activeFrame, SmartNavigation.currentButton = WorldMapFrame, blockedChild
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.lifecycle, "ready", "full update ignores forbidden hover ancestors without suspending")
equal(Addon.tooltip:IsShown(), false, "blocked quest owner leaves no quest companion")
equal(Addon.locationTooltip:IsShown(), false, "blocked location owner leaves no location companion")
context.setMouseFoci({ blockedFrame })
Addon:UpdateQuestTrackerTooltip()
Addon:UpdateQuestOfferTooltip()
equal(Addon.lifecycle, "ready", "quest scans do not inspect forbidden frame fields")
Addon.panel:Show()
Addon:UpdateRewardTooltips()
Addon:UpdateRewardTooltips(blockedFrame)
equal(Addon.rewardTooltips[1]:IsShown(), false, "forbidden reward focus is ignored")
SmartNavigation.activeFrame, SmartNavigation.currentButton = Addon.panel, blockedFrame
Addon:SyncControllerFocus()
equal(Addon.lifecycle, "ready", "controller sync does not inspect forbidden focus fields")
EventRegistry:TriggerEvent("TalentDisplay.TooltipHook", blockedFrame)
GameTooltip:SetOwner(blockedFrame, "ANCHOR_NONE")
emit(GameTooltip, { type = Enum.TooltipDataType.Unit, guid = "Player-1-1", lines = {} })
equal(Addon.lifecycle, "ready", "talent resolution ignores forbidden tooltip owners and event buttons")
local isForbidden, getOwner = GameTooltip.IsForbidden, GameTooltip.GetOwner
GameTooltip.IsForbidden = function() return true end
GameTooltip.GetOwner = function() error("forbidden tooltip owner must not be read") end
Addon:ShowTranslationTooltip()
Addon:UpdateNameTooltip(GameTooltip, "spell", 133)
equal(Addon:GetTooltipRect(GameTooltip), nil, "forbidden tooltip geometry is not read")
GameTooltip.IsForbidden, GameTooltip.GetOwner = isForbidden, getOwner
context.setMouseFoci({})
SmartNavigation.activeFrame, SmartNavigation.currentButton = active, selected
GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
GameTooltip:Hide()
Addon.panel:Hide()

spec.tip.accurateLines = true
local preview = Addon.settingsPanel.TooltipPreview
Addon:OpenSettings()
preview.translated.accurateLines = true
local setPreviewItem = preview.native.SetItemByID
function preview.native:SetItemByID(id)
    setPreviewItem(self, id)
    for _, callback in ipairs(context.callbacks) do callback(self, self:GetPrimaryTooltipData()) end
end
for _, coverage in ipairs({ "name", "full" }) do
    Addon:SetTooltipCoverage(coverage)
    for _, mode in ipairs({ "stacked", "separate" }) do
        Addon:SetTooltipMode(mode)
        prepare()
        emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 133 }, {
            { type = 0, leftText = SPELL_PASSIVE },
        })
        show()
        equal(Addon.lifecycle, "ready", "layout and coverage switch without pausing: " .. mode .. coverage)
        if mode == "stacked" then
            equal(GameTooltip:GetLeftLine(1):GetText(), "Native title", "stacked preserves native title")
            equal(GameTooltip:GetLeftLine(2):GetText(), SPELL_PASSIVE, "stacked preserves native details")
            equal(GameTooltip:GetLeftLine(4):GetText():find("Traduit en anglais", 1, true) ~= nil, true,
                "stacked header labels the translation in the selected FRS language")
            equal(GameTooltip:GetLeftLine(5):GetText(), "Fireball", "translation follows the header without a blank row")
            equal(VisibleTooltipLines(GameTooltip), coverage == "full" and 6 or 5, "stacked respects translation coverage")
            if coverage == "full" then
                equal(GameTooltip:GetLeftLine(6):GetText(), "Passive", "shared full details translate")
            end
            local count = VisibleTooltipLines(GameTooltip)
            show()
            equal(VisibleTooltipLines(GameTooltip), count, "stacked repeated layouts do not append duplicates")
        else
            equal(VisibleTooltipLines(GameTooltip), 2, "separate retains original native rows")
            equal(spec.tip:GetLeftLine(1):GetText(), "Fireball", "separate renders the translated name")
            equal(spec.tip:NumLines(), coverage == "full" and 2 or 1, "separate respects coverage")
            if coverage == "full" then
                equal(spec.tip:GetLeftLine(2):GetText(), "Passive", "separate shared details translate")
            end
        end
        SettingsPanel:Show()
        Addon:RefreshSettingsUI()
        equal(preview.native:IsShown(), true, "settings preview remains visible alongside live tooltips")
        equal(preview.translated:IsShown(), mode == "separate", "preview uses selected layout")
        if mode == "stacked" then
            equal(preview.native:NumLines(), coverage == "full" and 6 or 5,
                "preview shares stacked coverage")
        else
            equal(preview.translated:NumLines(), coverage == "full" and 2 or 1,
                "preview shares separate coverage")
        end
        SettingsPanel:Hide()
        Addon:SetTooltipMode("separate")
        equal(VisibleTooltipLines(GameTooltip), 2, "leaving any embedded layout removes appended rows")
        equal(GameTooltip:GetLeftLine(1):GetText(), "Native title", "mode changes restore native text")
        GameTooltip:Hide()
    end
end
Addon:SetTooltipCoverage("full")
prepare()
local showModeTooltip = GameTooltip.Show
function GameTooltip:Show()
    self:SetHeight(VisibleTooltipLines(self) * 20)
    return showModeTooltip(self)
end
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 133 }, { { type = 0, leftText = SPELL_PASSIVE } })
show()
Addon:SetTooltipMode("stacked")
equal(GameTooltip:GetHeight(), 120, "selecting Stacked immediately expands the visible native tooltip")
Addon:SetStackedTranslationFirst(true)
equal(Addon.stackedTooltips[GameTooltip].block:GetLeftLine(2):GetText(), "Fireball",
    "spell tooltips use the shared translation-first setting")
equal(VisibleTooltipLines(GameTooltip), 2, "the spell's original rows remain visible below the translation")
Addon:SetStackedTranslationFirst(false)
local stackedHeader = GameTooltip:GetLeftLine(4)
equal(stackedHeader:GetJustifyH(), "LEFT", "translation header is left aligned")
equal(select(2, stackedHeader:GetFont()) < select(2, GameTooltip:GetLeftLine(1):GetFont()), true,
    "translation label is smaller than the native text")
equal(select(1, stackedHeader:GetTextColor()), 0.65, "translation label uses subdued gray text")
equal(stackedHeader:GetText():find("media\\icon:14:14:0:1", 1, true) ~= nil, true,
    "header logo uses the common icon height and vertical offset")
equal(stackedHeader:GetText():find("media\\flags", 1, true), nil, "header contains no country flag")
equal(stackedHeader:GetText():find("chevron", 1, true), nil, "translation header has no chevron")
local gameLocale = GetLocale
local localeSource = CreateFrame("GameTooltip", "RosettaHeaderLocaleTest", UIParent, "GameTooltipTemplate")
local localeTranslation = CreateFrame("GameTooltip", nil, UIParent, "GameTooltipTemplate")
localeSource.accurateLines, localeTranslation.accurateLines = true, true
for _, example in ipairs({
    { "enUS", "frFR", "Translated into French" },
    { "frFR", "enUS", "Traduit en anglais" },
    { "frFR", "deDE", "Traduit en allemand" },
    { "deDE", "ukUA", "Übersetzt in Ukrainisch" },
    { "enGB", "frFR", "Translated into French" },
    { "unknown", "enUS", "Translated into English" },
}) do
    GetLocale = function() return example[1] end
    Addon:SetTargetLocale(example[2])
    localeSource:SetText("Native title")
    localeTranslation:SetText("Translated title")
    Addon:FillStackedTooltip(localeSource, localeTranslation, example[1])
    local label = localeSource:GetLeftLine(3):GetText()
    equal(label, "|TInterface\\AddOns\\ForeverRosettaStone\\media\\icon:14:14:0:1|t " .. example[3],
        "header uses the game language to identify the FRS target: " .. example[1] .. "/" .. example[2])
    Addon:ClearStackedTooltip(localeSource)
    localeTranslation:ClearLines()
    Addon:SetStandaloneTooltipTitle(localeTranslation, "Translated title", 1, 0.82, 0)
    local header = localeTranslation:GetLeftLine(1)
    equal(header:GetText(), label, "standalone and stacked tooltips share the same localized identity line")
    equal(select(2, header:GetFont()), select(2, localeTranslation:GetLeftLine(2):GetFont()) * 0.8,
        "standalone identity line uses the same smaller text as the stacked header")
end
GetLocale = gameLocale
Addon:SetTargetLocale("enUS")
localeSource:Hide()
Addon:SetTooltipMode("separate")
equal(GameTooltip:GetHeight(), 40, "leaving Stacked immediately restores native tooltip height without reload")
equal(spec.tip:IsShown(), true, "selecting Separate immediately shows the companion")
for _, mode in ipairs({ "stacked", "separate", "stacked", "separate" }) do
    Addon.settings.tooltipMode:SetValue(mode)
    equal(Addon.lifecycle, "ready", "live display changes keep the addon running: " .. mode)
    if mode == "stacked" then
        equal(GameTooltip:GetHeight(), 120, "selecting Stacked after Separate immediately resizes the tooltip")
    else
        equal(GameTooltip:GetHeight(), 40, "selecting Separate restores the native rows immediately")
        equal(spec.tip:IsShown(), true, "Separate immediately restores its companion")
    end
end
GameTooltip.Show = showModeTooltip
Addon:SetTooltipMode("stacked")
prepare()
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 133 }, { { type = 0, leftText = SPELL_PASSIVE } })
show()
Addon:SetTooltipMode("separate")
GameTooltip:GetRightLine(1):SetJustifyH("RIGHT")
GameTooltip:GetLeftLine(2):SetWordWrap(true)
Addon:SetTooltipMode("stacked")
Addon:SetTooltipMode("separate")
equal(GameTooltip:GetLeftLine(2):CanWordWrap(), true, "stacked cleanup preserves native wrapping")
equal(GameTooltip:GetRightLine(1):GetJustifyH(), "RIGHT", "stacked cleanup preserves native right alignment")
Addon:SetTooltipMode("stacked")
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 999999999 })
equal(VisibleTooltipLines(GameTooltip), 2, "native rebuild removes old stacked rows before an unknown spell")
equal(Addon.stackedTooltips[GameTooltip], nil, "native rebuild discards stale stacked rendering state")
local previousArmor, previousDelta = ARMOR, ITEM_DELTA_DESCRIPTION
ClientApi.InstallGlobals("frFR", {"ARMOR", "ITEM_DELTA_DESCRIPTION"})
prepare()
emit(GameTooltip, { type = Enum.TooltipDataType.Item, id = 117 }, {})
show()
GameTooltip:AddLine(" ")
GameTooltip:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0, true)
GameTooltip:AddLine("|cff00ff00+35|r Armure", 1, 1, 1)
show()
local rendered = RenderedTooltipRows(GameTooltip)
equal(rendered[3], ITEM_DELTA_DESCRIPTION,
    "late native comparison summary appears before the translation header")
equal(rendered[4], "|cff00ff00+35|r Armure",
    "late native delta keeps its signed value and color before the translation")
equal(rendered[6]:find("Traduit en anglais", 1, true) ~= nil, true,
    "translation header follows the complete native comparison block")
equal(rendered[#rendered], "|cff00ff00+35|r Armor",
    "translated comparison summary remains in the translated block")
local comparisonCount = #rendered
show()
equal(#RenderedTooltipRows(GameTooltip), comparisonCount, "repeated layouts do not duplicate comparison summaries")
Addon:SetTooltipMode("separate")
equal(#RenderedTooltipRows(GameTooltip), 4, "leaving Stacked preserves the late native comparison rows")
Addon:SetTooltipMode("stacked")
equal(#RenderedTooltipRows(GameTooltip), comparisonCount, "returning to Stacked includes each comparison block once")
equal(#context.eventCallbacks.TOOLTIP_SHOW_ITEM_COMPARISON, 1,
    "comparison events retain only the native listener, without the FRS callback that caused gamepad taint")
for _, pair in ipairs({
    { GameTooltip, ShoppingTooltip1, ShoppingTooltip2 },
    { ItemRefTooltip, ItemRefShoppingTooltip1, ItemRefShoppingTooltip2 },
}) do
    local primary, comparison = pair[1], pair[2]
    local previousShoppingTooltips = primary.shoppingTooltips
    primary.shoppingTooltips = { comparison, pair[3] }
    if primary == ItemRefTooltip then
        primary:SetOwner(UIParent, "ANCHOR_NONE")
        emit(primary, { type = Enum.TooltipDataType.Item, id = 117 }, {})
        primary:Show()
        context.flushTimers()
    end
    TooltipComparisonManager.tooltip = primary
    local equippedCount
    for refresh = 1, 3 do
        TooltipComparisonManager.buildItemTooltip = function()
            emit(comparison, { type = Enum.TooltipDataType.Item, id = 147 }, {})
            comparison:Show()
            equal(Addon.stackedTooltips[comparison], nil,
                "native comparison Show does not render before the stat summary: " .. refresh)
            comparison:AddLine(" ")
            comparison:AddLine(ITEM_DELTA_DESCRIPTION, 1, 0.82, 0, true)
            comparison:AddLine("|cff00ff00+35|r Armure", 1, 1, 1)
            if Addon.preferences.translationOnly then
                comparison:AddDoubleLine("Addon label", "Addon value")
                comparison:CreateTexture():Show()
            end
            return true
        end
        TooltipComparisonManager:SetItemTooltip(true)
        equal(Addon.stackedTooltips[comparison] ~= nil, true,
            "comparison translation is restored before returning to the client, without a timer or anchor call")
        equal(comparison:GetLeftLine(3):GetText(), ITEM_DELTA_DESCRIPTION,
            "completed comparison keeps native stat changes above the translation")
        equal(comparison:GetLeftLine(6):GetText():find("Traduit en anglais", 1, true) ~= nil, true,
            "comparison renders the translation after the complete native block")
        equippedCount = equippedCount or VisibleTooltipLines(comparison)
        context.flushTimers()
        equal(VisibleTooltipLines(comparison), equippedCount,
            "repeated native comparison rebuilds keep the completed tooltip height stable")
        GameTooltip_ShowCompareItem(primary)
        equal(Addon.stackedTooltips[comparison] ~= nil, true,
            "comparison translation is present before the native comparison call returns, without a layout tick")
        equal(VisibleTooltipLines(comparison), equippedCount,
            "native comparison rebuilds retain their translated height in the same frame")
        context.flushTimers()
    end
    Addon:SetStackedTranslationFirst(true)
    GameTooltip_ShowCompareItem(primary)
    local original = Addon.stackedTooltips[primary]
    local equipped = Addon.stackedTooltips[comparison]
    equal(original and original.block and original.block:IsShown(), true, "item translation is shown first")
    equal(equipped and equipped.block and equipped.block:IsShown(), true, "equipped item translation is shown first")
    equal(comparison:GetLeftLine(3):GetText(), ITEM_DELTA_DESCRIPTION,
        "translation-first preserves the original stat summary")
    local padding = select(4, comparison:GetPadding())
    GameTooltip_ShowCompareItem(primary)
    equal(select(4, comparison:GetPadding()), padding, "comparison rebuilds reserve space for a single translation")
    Addon:SetStackedTranslationFirst(false)
    equal(select(4, comparison:GetPadding()), 0, "leaving translation-first removes extra top padding")
    for _, mode in ipairs({ "stacked", "separate" }) do
        Addon:SetTooltipMode(mode)
        Addon:SetTranslationOnly(true)
        GameTooltip_ShowCompareItem(primary)
        local replacement = Addon.stackedTooltips[comparison].owner
        equal(primary:GetAlpha(), 0, "the hovered item's original is hidden in " .. mode)
        equal(comparison:GetAlpha(), 0, "the equipped item's original is hidden in " .. mode)
        equal(select(2, replacement:GetPoint(1)), comparison, "the translation takes the equipped tooltip's slot")
        equal(replacement:GetLeftLine(1):GetText():find("Traduit en", 1, true), nil,
            "the translated comparison starts without an FRS header")
        equal(replacement:GetLeftLine(replacement:NumLines() - 2):GetText(), "|cff00ff00+35|r Armor",
            "translation-only keeps the translated stat differences")
        equal(replacement:GetLeftLine(replacement:NumLines()):GetText(), "Addon label",
            "decorated addon data remains below the translated comparison")
        equal(replacement:GetRightLine(replacement:NumLines()):GetText(), "Addon value",
            "the addon row keeps both columns through the comparison renderer")
        local mainTip = Addon.stackedTooltips[primary].owner
        local mainLeft, mainTop = mainTip.left, mainTip.top
        local compareLeft, compareTop = comparison.left, comparison.top
        mainTip.left, mainTip.top = 700, 600
        comparison.left, comparison.top = 640, 600
        Addon:LayoutNameTooltipGroup(Addon.nameTooltips[primary].group)
        local point, anchor, relative, gap = replacement:GetPoint(1)
        equal(anchor, mainTip, "the comparison positions against the visible translation")
        equal(point, "TOPRIGHT", "the left comparison anchors from its right edge")
        equal(relative, "TOPLEFT", "the left comparison sits outside the primary tooltip")
        equal(gap < 0, true, "comparison translations use a non-overlapping gap")
        comparison.left = primary:GetLeft() + 60
        Addon:LayoutNameTooltipGroup(Addon.nameTooltips[primary].group)
        point, anchor, relative, gap = replacement:GetPoint(1)
        equal(anchor, mainTip, "the right comparison also positions against the visible translation")
        equal(point, "TOPLEFT", "the right comparison anchors from its left edge")
        equal(relative, "TOPRIGHT", "the right comparison sits outside the primary tooltip")
        equal(gap > 0, true, "right-side comparison translations keep a non-overlapping gap")
        mainTip.left, mainTip.top = mainLeft, mainTop
        comparison.left, comparison.top = compareLeft, compareTop
        Addon:SetTranslationOnly(false)
        equal(comparison:GetAlpha(), 1, "disabling translation-only restores the original comparison")
    end
    Addon:SetTooltipMode("stacked")
    TooltipComparisonManager.tooltip, TooltipComparisonManager.buildItemTooltip = nil, nil
    primary.shoppingTooltips = previousShoppingTooltips
    comparison:Hide()
    if primary == ItemRefTooltip then primary:Hide() end
end
ARMOR, ITEM_DELTA_DESCRIPTION = previousArmor, previousDelta
C_Map, C_MapExplorationInfo = locationMap, locationExploration
GetZoneText = function() return "Dun Morogh" end
GetSubZoneText = function() return "Vallée des Frigères" end
prepare(MinimapCluster.ZoneTextButton)
MinimapCluster.ZoneTextButton:OnEnter()
context.flushTimers()
equal(GameTooltip:GetLeftLine(3):GetText(), "Carte du monde (M)", "stacked minimap keeps the native hint third")
equal(GameTooltip:GetLeftLine(6):GetText(), "Dun Morogh", "stacked minimap includes the translated zone")
equal(GameTooltip:GetLeftLine(7):GetText(), "Coldridge Valley", "stacked minimap includes the translated subzone")
Addon:SetTooltipMode("separate")
C_Map, C_MapExplorationInfo = previousLocationMap, previousExploration
Addon:SetTooltipCoverage("name")
prepare()
GameTooltip:ClearLines()
GameTooltip:AddLine("Actuellement équipé")
GameTooltip:AddLine("Nom de l'objet")
GameTooltip.processingInfo = { tooltipData = { type = Enum.TooltipDataType.Item, id = 25, lines = {
    { type = Enum.TooltipDataLineType.ItemName, lineIndex = 2, leftText = "Nom de l'objet" },
} } }
spec.data = GameTooltip.processingInfo.tooltipData
Addon:UpdateNameTooltip(GameTooltip, "item", 25)
show()
equal(GameTooltip:GetLeftLine(1):GetText(), "Actuellement équipé", "Name only does not translate the comparison header")
equal(spec.tip:GetLeftLine(1):GetText(), "Worn Shortsword", "Name only translates the item after its native header")
Addon:SetTooltipCoverage("full")
Addon:SetTooltipMode("stacked")
Addon:SetTargetLocale("deDE")
Addon:OpenSettings()
Addon:RefreshTooltipPreview()
equal(preview.native:GetLeftLine(4):GetText():find("Traduit en allemand", 1, true) ~= nil, true,
    "live preview updates the localized header when the translation language changes")
equal(preview.native:GetLeftLine(5):GetText(), ForeverRosettaStoneDB:GetItemName(117, "deDE"),
    "live preview reads the selected language from the real catalog")
Addon:SetTargetLocale("enUS")
Addon:SetTooltipMode("separate")

prepare()
emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 133 }, { { type = 0, leftText = SPELL_PASSIVE } })
show()
for _, mode in ipairs({ "stacked", "separate", "stacked", "separate" }) do
    SettingsPanel:Show()
    equal(not Addon:IsTooltipBlocked(), true, "opening settings permits live translations")
    equal(spec.tip:IsShown(), true, "opening settings preserves the existing separate translation")
    Addon.settings.tooltipMode:SetValue(mode)
    if mode == "stacked" then
        equal(GameTooltip:GetLeftLine(5):GetText(), "Fireball", "settings changes the visible tooltip to Stacked")
    else
        equal(spec.tip:IsShown(), true, "settings changes the visible tooltip to Separate")
    end
    prepare()
    emit(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 133 }, { { type = 0, leftText = SPELL_PASSIVE } })
    show()
    equal(Addon.lifecycle, "ready", "hovering with settings open keeps translation running: " .. mode)
    if mode == "stacked" then
        equal(GameTooltip:GetLeftLine(5):GetText(), "Fireball", "hover with settings open renders Stacked")
    else
        equal(spec.tip:IsShown(), true, "hover with settings open renders Separate")
    end
    SettingsPanel:Hide()
    Addon:SetTooltipMode("separate")
end
local savedPreviewWidth, savedPreviewHeight = preview:GetWidth(), preview:GetHeight()
local savedPreviewPosition = Addon.preferences.npcTooltipPosition
preview:SetSize(420, 180)
Addon:OpenSettings()
Addon:SetTooltipMode("separate")
local anchors = { left = "TOPRIGHT", right = "TOPLEFT", top = "BOTTOMLEFT", bottom = "TOPLEFT" }
for _, side in ipairs({ "left", "right", "top", "bottom" }) do
    Addon:SetNpcTooltipPosition(side)
    local native, translated = preview.native, preview.translated
    equal(translated.points[1][1], anchors[side], "preview follows the selected translation side: " .. side)
    local horizontal = side == "left" or side == "right"
    local width = horizontal and native:GetWidth() + translated:GetWidth() + 8
        or math.max(native:GetWidth(), translated:GetWidth())
    local height = horizontal and math.max(native:GetHeight(), translated:GetHeight())
        or native:GetHeight() + translated:GetHeight() + 8
    equal(width * native:GetScale() <= preview:GetWidth() - 24 + 0.001, true,
        "preview reserves width for both tooltips: " .. side)
    equal(height * native:GetScale() <= preview:GetHeight() - 24 + 0.001, true,
        "preview reserves height for both tooltips: " .. side)
    if side == "left" then
        equal(native.points[1][4] >= translated:GetWidth() + 8, true,
            "left preview moves the original inward to leave room for its translation")
    end
end
preview:SetSize(savedPreviewWidth, savedPreviewHeight)
Addon:SetNpcTooltipPosition(savedPreviewPosition)
SettingsPanel:Hide()
preview.native.SetItemByID = setPreviewItem

WorldMapFrame:Show()
local mapPin = CreateFrame("Button", nil, WorldMapFrame)
mapPin.pinTemplate = "QuestPinTemplate"
function mapPin:GetQuestID() return 943 end
function mapPin:GetMap() return WorldMapFrame end
local accurateNativeLines, accurateQuestLines = GameTooltip.accurateLines, Addon.tooltip.accurateLines
GameTooltip.accurateLines, Addon.tooltip.accurateLines = true, true
Addon:SetTooltipMode("stacked")
local mapLineCount
for refresh = 1, 5 do
    GameTooltip:SetOwner(mapPin, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:SetText("Native map quest")
    GameTooltip:AddLine("Native objective")
    GameTooltip:AddLine("Toggle Focus on Quest")
    GameTooltip:AddLine("Toggle Quest Details")
    GameTooltip:Show()
    local saved = Addon.stackedTooltips[GameTooltip]
    equal(saved ~= nil, true, "map rebuild restores translation before the next timer tick: " .. refresh)
    equal(#saved.rows, 4, "map translation follows all native objectives and controller commands")
    equal(GameTooltip:GetLeftLine(7):GetText(), "The Absent Minded Prospector",
        "map rebuild immediately restores the translated title")
    mapLineCount = mapLineCount or VisibleTooltipLines(GameTooltip)
    equal(VisibleTooltipLines(GameTooltip), mapLineCount, "repeated map rebuilds keep the final line count stable")
    context.flushTimers()
    Addon:ShowTranslationTooltip()
    equal(VisibleTooltipLines(GameTooltip), mapLineCount, "deferred layout and polling do not duplicate map translation")
end
GameTooltip:Show()
equal(VisibleTooltipLines(GameTooltip), mapLineCount, "repeated Show without a rebuild does not duplicate map translation")
Addon:SetFeatureEnabled("mapQuestTooltip", false)
GameTooltip:Show()
equal(VisibleTooltipLines(GameTooltip), 4, "native Show respects disabled map translations")
Addon:SetFeatureEnabled("mapQuestTooltip", true)
Addon:SetTooltipMode("separate")
GameTooltip:Show()
equal(VisibleTooltipLines(GameTooltip), 4, "Separate keeps the map tooltip's native rows")
equal(Addon.tooltip:IsShown(), true, "Separate restores the companion immediately on native Show")
do
    local show = Addon.tooltip.Show
    local getProgressText = Addon.GetProgressText
    local progress = ""
    function Addon:GetProgressText(id)
        if id == mapPin:GetQuestID() then return progress end
        return getProgressText(self, id)
    end
    local layoutPasses, renderedRows = 0
    function Addon.tooltip:Show()
        layoutPasses = layoutPasses + 1
        renderedRows = VisibleTooltipLines(self)
        show(self)
    end
    Addon:SetTranslationOnly(true)
    local initialLayoutPasses = layoutPasses
    equal(renderedRows, 1, "translation-only lays out the map quest title")
    equal(GameTooltip:GetAlpha(), 0, "translation-only hides the original map quest rendering")
    progress = "Stone of Relu: 0/1"
    Addon:ShowTranslationTooltip()
    equal(renderedRows, 2, "a new objective row is laid out while the translated quest tooltip is already shown")
    equal(Addon.tooltip:GetLeftLine(2):GetText(), "- Stone of Relu: 0/1", "the objective is rendered below its title")
    equal(layoutPasses, initialLayoutPasses + 1, "updated map quest progress relayouts the translated tooltip once")
    Addon:ShowTranslationTooltip()
    equal(layoutPasses, initialLayoutPasses + 1, "polling unchanged objectives keeps the cached layout")
    Addon.tooltip.Show, Addon.GetProgressText = show, getProgressText
    Addon:SetTranslationOnly(false)
end
Addon:SetTooltipMode("stacked")
GameTooltip:Hide()
equal(Addon.stackedTooltips[GameTooltip], nil, "leaving a map pin clears the embedded translation")
do
    local questList = QuestMapFrame.QuestsFrame.ScrollFrame
    questList:Show()
    local row = CreateFrame("Button", nil, questList)
    local owner = CreateFrame("Button", nil, row)
    Addon:SetTranslationOnly(true)
    for _, quest in ipairs({ { 943, "The Absent Minded Prospector" }, { 399, "Humble Beginnings" } }) do
        row.info = { questID = quest[1] }
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:SetText("Native quest title")
        GameTooltip:AddLine("Native controller controls")
        GameTooltip:Show()
        equal(GameTooltip:GetAlpha(), 0, "quest-list navigation hides the original before the next tick")
        equal(Addon.tooltip:GetLeftLine(1):GetText(), quest[2], "the pooled quest row resolves its current translated title")
        equal(GameTooltip:GetLeftLine(2):GetText(), "Native controller controls", "the native controller hints stay intact")
    end
    row.info.questID = 999999999
    GameTooltip:ClearLines()
    GameTooltip:SetText("Untranslated quest")
    GameTooltip:Show()
    equal(GameTooltip:GetAlpha(), 1, "a quest without a translation keeps the original visible")
    equal(Addon.tooltip:IsShown(), false, "a quest without a translation clears the old replacement")
    Addon:SetTranslationOnly(false)
    GameTooltip:Hide()
end
GameTooltip.accurateLines, Addon.tooltip.accurateLines = accurateNativeLines, accurateQuestLines
WorldMapFrame:Hide()
Addon:SetTooltipMode("separate")

do
    local oldWidth, oldHeight = UIParent:GetSize()
    local oldScale = UIParent:GetScale()
    UIParent:SetSize(1920, 1080)
    UIParent:SetScale(0.711111)
    local source = CreateFrame("Frame", nil, UIParent)
    source:SetSize(300, 90)
    local companion = Addon:CreateCompanionTooltip(nil)
    companion:SetOwner(source, "ANCHOR_NONE")
    local policy = { GetSide = function() return "left" end }
    for _, scale in ipairs({ 0.64, 0.711111, 0.8, 0.85, 0.9, 1 }) do
        source:SetScale(scale / UIParent:GetEffectiveScale())
        companion:SetScale(scale / UIParent:GetEffectiveScale())
        source.left, source.top = 1000 / scale, 100 / scale
        for height = 80, 240 do
            companion:SetSize(280, height)
            local bounds = Addon:PlaceCompanionTooltip(companion, source, nil, false, nil, policy)
            equal(bounds ~= nil, true, "fractional-scale companion fits near the bottom: " .. scale .. "/" .. height)
            equal(companion:IsShown(), true, "fitting companion remains visible at fractional coordinates")
        end
    end
    local obstacle = { left = 700, right = 1000, bottom = 0, top = 300 }
    equal(Addon:PlaceCompanionTooltip(companion, source, { obstacle }, false, nil, policy), nil,
        "placement tolerance does not permit a real overlap")
    companion:Hide()
    UIParent:SetScale(oldScale)
    UIParent:SetSize(oldWidth, oldHeight)
end

return checks
