local Addon, context = ...
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local previousLocale, previousTarget = GetLocale, Addon:GetTargetLocale()
local previousGamepad, previousFoci = InputUtil.IsGamepadUIEnabled, GetMouseFoci
local previousActive, previousButton = SmartNavigation.activeFrame, SmartNavigation.currentButton
local previousAccurateLines, previousLocationLines = GameTooltip.accurateLines, Addon.locationTooltip.accurateLines
GameTooltip.accurateLines, Addon.locationTooltip.accurateLines = true, true
local oldFeatures = {}
for key, value in pairs(Addon.preferences.features) do oldFeatures[key] = value; Addon.preferences.features[key] = true end
GetLocale = function() return "frFR" end
Addon:SetTargetLocale("enUS")
SettingsPanel:Hide()
GameMenuFrame:Hide()
local function captured(kind, id)
    local entry = Addon.debugPicker.byID[kind .. ":" .. id]
    check(entry ~= nil, kind .. " has a capture for " .. id)
    check(entry.source and entry.surfaces and entry.inputMode, kind .. " includes surface and input evidence")
    return entry
end

for _, gamepad in ipairs({ false, true }) do
    InputUtil.IsGamepadUIEnabled = function() return gamepad end
    GetMouseFoci = function() return {} end
    Addon:RunDebugCommand("pick")
    GameTooltip.processingInfo = nil
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:SetText("Junior Herbalism Trainer")
    GameTooltip:Show()
    check(captured("tooltip", "Junior Herbalism Trainer").lines[1].leftText == "Junior Herbalism Trainer",
        "manual minimap service tooltips retain their displayed text without an entity ID")
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.Unit,
        guid = "Creature-0-1-0-1-658-000001", lines = { { leftText = "Sten" } } })
    check(captured("npc", 658).name == "Sten", "NPC identity comes from the GUID and retains native text")
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.Quest, id = 179, lines = {} })
    captured("quest", 179)
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.MinimapMouseover,
        lines = { { questID = 179, leftText = "Quest" } } })
    captured("minimapQuest", 179)
    local previousAura, previousAuras = Enum.TooltipDataType.UnitAura, C_UnitAuras
    Enum.TooltipDataType.UnitAura = 9999
    C_UnitAuras = { GetAuraDataByIndex = function() return { spellId = 133 } end }
    GameTooltip.processingInfo = { getterName = "GetUnitAura", getterArgs = { "player", 1 } }
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.UnitAura, id = 22, lines = {} })
    captured("spell", 133)
    Enum.TooltipDataType.UnitAura, C_UnitAuras = previousAura, previousAuras
    GameTooltip.processingInfo = { getterName = "GetTalent", getterArgs = {} }
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.Spell, id = 133, lines = {} })
    captured("talent", 133)
    GameTooltip.processingInfo = { getterName = "GetMountBySpellID", getterArgs = { 458 } }
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.Mount, lines = {} })
    captured("mount", 458)
    GameTooltip.processingInfo = nil
    context.hooks.BattlePetToolTip_Show(43)
    captured("pet", 43)
    Addon:RecordDebugTooltip(GameTooltip, { type = Enum.TooltipDataType.Toy, id = 25, lines = {} })
    captured("item", 25)
    local oldPosition, oldAreaInfo, oldExploration = C_Map.GetPlayerMapPosition, C_Map.GetAreaInfo, C_MapExplorationInfo
    local oldBestMap = C_Map.GetBestMapForUnit
    C_Map.GetBestMapForUnit = function() return 1426 end
    C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.29, 0.68 end } end
    C_Map.GetAreaInfo = function(id)
        if id == 1 then return GetZoneText() end
        if id == 132 then return GetSubZoneText() end
    end
    C_MapExplorationInfo = { GetExploredAreaIDsAtPosition = function() return { 1, 132 } end }
    GameTooltip:SetOwner(MinimapCluster.ZoneTextButton, "ANCHOR_NONE")
    MinimapCluster.ZoneTextButton:OnEnter()
    captured("minimapLocation", GetZoneText())
    local minimap = captured("minimapLocation", GetZoneText())
    check(minimap.lines[1].leftText ~= nil, "minimap location capture retains native tooltip lines")
    context.flushTimers()
    local minimapSpec = Addon.nameTooltips[GameTooltip]
    minimapSpec.tip.accurateLines = true
    Addon:FillNameTooltip(minimapSpec)
    local renderedMinimap = captured("minimapLocation", minimapSpec.id)
    check(renderedMinimap.renderedTranslation and #renderedMinimap.renderedTranslation.lines > 0,
        "minimap location capture retains the rendered translated tooltip")
    C_Map.GetPlayerMapPosition, C_Map.GetAreaInfo, C_MapExplorationInfo = oldPosition, oldAreaInfo, oldExploration
    C_Map.GetBestMapForUnit = oldBestMap

    local row = CreateFrame("Frame", nil, UIParent)
    context.hooks.PaperDollFrame_SetLabelAndText(row, HEALTH, "103")
    GameTooltip:SetOwner(row, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:SetText(HEALTH)
    GameTooltip:AddLine("103")
    GameTooltip:Show()
    context.flushTimers()
    local stat = Addon.nameTooltips[GameTooltip]
    captured("characterStat", stat.id)

    WorldMapFrame:Show()
    Addon:ShowMapContext()
    captured("map", WorldMapFrame:GetMapID())
    captured("playerLocation", C_Map.GetBestMapForUnit("player"))
    local label = context.nativeAreaLabel
    label.Name:SetText("Hurlevent")
    label:Show()
    Addon:ShowMapLocationLabel()
    captured("area", "Hurlevent")
    local menu = context.createMapMenu(context.mapMenuArrow, { "Bois de la Pénombre" })
    menu.elements[1]:Enter(context.menuRow)
    captured("mapDropdown", "Bois de la Pénombre")
    local tracking = context.createMapMenu(UIParent, { "Banquier" }, "MENU_MINIMAP_TRACKING", { { index = 1 } })
    tracking.elements[1]:Enter(context.menuRow)
    captured("trackingMenu", "Banquier")
    QuestMapFrame.QuestsFrame.ScrollFrame:Show()
    SmartNavigation.activeFrame, SmartNavigation.currentButton = WorldMapFrame, context.locationHeader
    GetMouseFoci = function() return gamepad and {} or { context.locationHeader } end
    Addon:ShowLocationTooltip()
    check(captured("area", "Hurlevent").surfaces.locationTooltip ~= nil, "location headers are captured by mouse or native gamepad focus")
    local area = captured("area", "Hurlevent")
    check(area.surfaces.locationTooltip.native.title == "Hurlevent"
        and area.surfaces.locationTooltip.native.questLogIndex == context.locationHeader.questLogIndex
        and area.surfaces.locationTooltip.native.questLogInfo.isHeader == true
        and area.surfaces.locationTooltip.renderedTranslation == nil,
        "name-only quest-area headers retain native text without a fabricated translation")
    check(area.surfaces.mapLocationLabel.native.name == "Hurlevent"
        and area.surfaces.mapLocationLabel.translated.name == nil,
        "name-only map labels retain native text without a fabricated translation")
    area.surfaces.locationTooltip, area.surfaces.mapLocationLabel = nil, nil
    Addon.preferences.features.locationTooltip, Addon.preferences.features.mapLocationLabel = false, false
    Addon:ShowLocationTooltip()
    Addon:ShowMapLocationLabel()
    check(area.surfaces.locationTooltip ~= nil, "inspection captures quest-area headers with translation disabled")
    check(area.surfaces.mapLocationLabel ~= nil, "inspection captures map-area labels with translation disabled")
    check(not Addon.locationTooltip:IsShown(), "capture does not enable a disabled area translation")
    Addon.preferences.features.locationTooltip, Addon.preferences.features.mapLocationLabel = true, true
    local questRow = CreateFrame("Button", nil, QuestMapFrame.QuestsFrame.ScrollFrame)
    questRow.questID = 179
    SmartNavigation.currentButton = questRow
    GetMouseFoci = function() return gamepad and {} or { questRow } end
    GameTooltip:SetOwner(questRow, "ANCHOR_NONE")
    GameTooltip:SetText("Quest")
    GameTooltip:Show()
    Addon:ShowTranslationTooltip()
    check(captured("quest", 179).surfaces.questTooltip, "quest list tooltip has its own surface evidence")
    local pin = CreateFrame("Button", nil, WorldMapFrame)
    pin.pinTemplate = "QuestPinTemplate"
    pin.GetMap = function() return WorldMapFrame end
    pin.GetQuestID = function() return 179 end
    GameTooltip:SetOwner(pin, "ANCHOR_NONE")
    Addon:ShowTranslationTooltip()
    check(captured("quest", 179).surfaces.mapQuestTooltip, "map pin keeps separate context for the same quest")

    local rewardGetter = C_TooltipInfo.GetQuestLogItem
    C_TooltipInfo.GetQuestLogItem = function()
        return { id = 25, lines = { { type = Enum.TooltipDataLineType.ItemName, leftText = "Reward" } } }
    end
    Addon.panel:Show()
    local reward = CreateFrame("Button", nil, Addon.panel)
    reward.left, reward.top = 100, 500
    reward.rewardSource = CreateFrame("Button", nil, UIParent)
    reward.rewardSource.objectType, reward.rewardSource.type = "item", "choice"
    reward.rewardSource:SetID(2)
    Addon:UpdateRewardTooltips(reward)
    check(captured("item", 25).surfaces.rewardComparison, "reward comparisons retain the real native item data")
    C_TooltipInfo.GetQuestLogItem = rewardGetter

    local block = CreateFrame("Frame", nil, ObjectiveTrackerFrame)
    block.parentModule, block.id = QuestObjectiveTracker, 179
    SmartNavigation.activeFrame, SmartNavigation.currentButton = ObjectiveTrackerFrame, block
    GetMouseFoci = function() return gamepad and {} or { block } end
    Addon:UpdateQuestTrackerTooltip()
    captured("questTracker", 179)

    local oldGossip, oldGossipInfo = GossipFrame, C_GossipInfo
    GossipFrame = CreateFrame("Frame", nil, UIParent)
    GossipFrame:SetSize(338, 496)
    GossipFrame.left, GossipFrame.top = 20, 800
    C_GossipInfo = { GetAvailableQuests = function() return { { questID = 179 } } end,
        GetActiveQuests = function() return {} end }
    local offer = CreateFrame("Button", nil, GossipFrame)
    offer.questID = 179
    if Addon.questInteractionReader then Addon.questInteractionReader.frame:Hide() end
    SmartNavigation.activeFrame, SmartNavigation.currentButton = GossipFrame, offer
    GetMouseFoci = function() return gamepad and {} or { offer } end
    Addon:UpdateQuestOfferTooltip()
    captured("questOffer", 179)
    WorldMapFrame:Hide()
    Addon:UpdateQuestInteraction()
    captured("questInteraction", 179)
    Addon:SendQuestInteraction({ type = "reset" })
    GossipFrame, C_GossipInfo = oldGossip, oldGossipInfo
    check(Addon.debugPicker.captureError == nil, "all capture paths complete without errors")
    Addon:MoveDebugPicker("stop")
    for index, entry in ipairs(Addon.debugPicker.entries) do
        Addon.errorDialog.pickedButtons[index]:OnSmartNavClick()
        check(Addon.errorDialog.report:find("capturedTooltip", 1, true), entry.kind .. " has an inspectable controller report")
    end
    Addon:RunDebugCommand("clear")
    Addon.errorDialog.frame:Hide()
end

for locale, strings in pairs(Addon.debugTranslations) do
    GetLocale = function() return locale end
    check(#strings == #Addon.debugTranslations.enUS, locale .. " has every console translation")
    check(Addon:DebugText("title") ~= nil and Addon:DebugText("saved") ~= nil, locale .. " includes report instructions")
    check(Addon:GetCommandHelp():find("/frs npc 8956", 1, true), locale .. " keeps command syntax usable")
end
GetLocale = function() return "frFR" end
Addon:RunDebugCommand("")
check(Addon.errorDialog.title:GetText():find("Diagnostic et signalement", 1, true), "console follows French client with English target translations")
Addon:RunDebugCommand("status")
check(Addon.errorDialog.report:find("Comportement attendu", 1, true), "issue instructions follow the client language")
check(not Addon.errorDialog.report:find("Expected behavior", 1, true), "French reporting does not fall back to English UI prose")
Addon.errorDialog.frame:Hide()
GetLocale, InputUtil.IsGamepadUIEnabled, GetMouseFoci = previousLocale, previousGamepad, previousFoci
SmartNavigation.activeFrame, SmartNavigation.currentButton = previousActive, previousButton
Addon.preferences.features = oldFeatures
Addon:SetTargetLocale(previousTarget)
GameTooltip.accurateLines, Addon.locationTooltip.accurateLines = previousAccurateLines, previousLocationLines
return checks
