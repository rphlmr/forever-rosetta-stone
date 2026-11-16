local Addon, callbacks, flushTimers = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end
local previous = {}
local keys = { "GetLocale", "UnitGUID", "UnitRace", "UnitClass", "UnitLevel", "UnitSex", "UnitIsPlayer", "UnitFactionGroup", "GetGuildInfo" }
for _, key in ipairs(keys) do previous[key] = _G[key] end
local oldGetUnit = GameTooltip.GetUnit
local oldLocale, oldMode, oldCoverage = Addon:GetTargetLocale(), Addon.preferences.tooltipMode, Addon.preferences.tooltipCoverage
local oldEnabled = Addon:IsFeatureEnabled("playerTooltip")
local oldNpcEnabled = Addon:IsFeatureEnabled("npcTooltip")
local guid, raceID, classID, level, sex = "Player-42-ABCDEF", 1, 3, 25, 2
local nativeFaction = "Alliance"
local nativeGuild
GetLocale = function() return "enUS" end
UnitGUID = function() return guid end
UnitRace = function() return "Human", "Human", raceID end
UnitClass = function() return "Hunter", "HUNTER", classID end
UnitLevel = function() return level end
UnitSex = function() return sex end
UnitIsPlayer = function() return true end
UnitFactionGroup = function() return "Alliance", nativeFaction end
GetGuildInfo = function() return nativeGuild end
GameTooltip.GetUnit = function() return "Native", "nameplate4" end
Addon:SetTargetLocale("frFR")
Addon:SetTooltipMode("separate")
Addon:SetTooltipCoverage("full")
Addon:SetFeatureEnabled("playerTooltip", true)

local function show(extraText, guildText)
    SettingsPanel:Hide()
    GameMenuFrame:Hide()
    if Addon.errorDialog then Addon.errorDialog.frame:Hide() end
    GameTooltip:Hide()
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:SetSize(240, 160)
    GameTooltip.left, GameTooltip.top = 400, 300
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 70)
    GameTooltip:ClearLines()
    local data = { type = Enum.TooltipDataType.Unit, guid = "Player-42-ABCDEF", lines = {
        { type = Enum.TooltipDataLineType.UnitName, leftText = "Native Player-Realm", lineIndex = 1 },
        { type = 0, leftText = "Level 25 Human (Player)", lineIndex = 2 },
        { type = 0, leftText = "Hunter", lineIndex = 3 },
        { type = 0, leftText = extraText or "Untranslated guild", lineIndex = 4 },
    } }
    if guildText then table.insert(data.lines, 2, { type = 0, leftText = guildText }) end
    for index, row in ipairs(data.lines) do row.lineIndex = index end
    for _, row in ipairs(data.lines) do GameTooltip:AddLine(row.leftText) end
    GameTooltip.processingInfo = { tooltipData = data }
    for _, callback in ipairs(callbacks) do callback(GameTooltip, data) end
    GameTooltip:Show()
    flushTimers()
    return Addon.nameTooltips[GameTooltip].tip
end

local tip = show()
assert(Addon.lifecycle == "ready", tostring(Addon.errors[#Addon.errors]))
assert(Addon.nameTooltips[GameTooltip].kind == "player", "player identity must resolve before rendering")
assert(Addon.nameTooltips[GameTooltip].name == "Native Player-Realm", "player native name must resolve before rendering")
equal(tip:IsShown(), true, "player tooltip has a translated companion")
equal(tip.lines[1], "Native Player-Realm", "player name and realm stay verbatim")
equal(tip.lines[2], "Niveau 25 Humain (Joueur)", "level and race use owned target formats and race ID")
equal(tip.lines[3], "Chasseur", "player class uses its live class ID")
equal(tip:NumLines(), 3, "unrecognized extra rows stay outside the picked player block")
equal(GameTooltip.lines[1], "Native Player-Realm", "separate mode preserves the native name")
tip = show("Alliance")
equal(tip.lines[4], "Alliance", "player allegiance stays native")
equal(tip:NumLines(), 4, "native player allegiance is not a missing translation")
nativeGuild = "Synthetic guild"
tip = show("Alliance", nativeGuild)
equal(tip.lines[2], nativeGuild, "the player's guild name stays verbatim")
equal(tip:NumLines(), 5, "a confirmed guild name is not an incomplete translation")
nativeGuild = "Hunter"
tip = show("Alliance", nativeGuild)
equal(tip.lines[2], "Hunter", "a guild named like the native class is never translated")
equal(tip.lines[4], "Chasseur", "a matching guild name cannot suppress the actual class translation")
nativeGuild = nil
tip = show("Alliance", "Synthetic guild")
equal(tip:NumLines(), 4, "a missing guild API result cannot classify an unknown row as a guild")
nativeFaction = "Synthetic allegiance"
tip = show(nativeFaction)
equal(tip:NumLines(), 4, "allegiance exemption follows the live unit API instead of a name allowlist")
nativeFaction = "Alliance"
UnitFactionGroup = nil
tip = show("Alliance")
equal(tip:NumLines(), 3, "unidentified extra rows stay outside the picked player block")
UnitFactionGroup = function() return "Alliance", nativeFaction end
Addon:SetFeatureEnabled("npcTooltip", false)
tip = show()
equal(tip:IsShown(), true, "player translation is independent of the NPC setting")
Addon:SetFeatureEnabled("npcTooltip", oldNpcEnabled)
sex = 3
Addon:SetTargetLocale("esES")
tip = show()
equal(tip.lines[2], "Nivel 25 Humana (Jugador)", "female race variants use UnitSex and owned native text")
sex = 2
Addon:SetTargetLocale("frFR")
Addon:SetTooltipCoverage("name")
tip = show()
equal(tip:IsShown(), false, "name-only coverage does not duplicate unchanged player names")
Addon:SetTooltipCoverage("full")
raceID, classID = 99999999, 99999999
tip = show("Alliance")
equal(tip.lines[2], "Level 25 Human (Player)", "missing race translation preserves the complete native row")
equal(tip.lines[3], "Hunter", "missing class translation preserves the native class")
equal(tip:NumLines(), 5, "missing race or class still reports incomplete translation")
raceID, classID, level = 1, 3, 26
tip = show()
equal(tip.lines[2], "Level 25 Human (Player)", "a mismatching live level cannot translate a stale row")
guid = "Player-42-123456"
tip = show()
equal(tip:IsShown(), false, "recycled unit tokens cannot translate another player's tooltip")
guid, level = "Player-42-ABCDEF", 25
Addon:SetTooltipMode("stacked")
show()
local translated = false
for _, text in ipairs(GameTooltip.lines) do
    if text == "Niveau 25 Humain (Joueur)" then translated = true end
end
equal(translated, true, "stacked mode includes translated player details")
Addon:SetFeatureEnabled("playerTooltip", false)
tip = show()
equal(tip:IsShown(), false, "unit tooltip setting disables player translation")
GameTooltip:Hide()
Addon:SetTargetLocale(oldLocale)
Addon:SetTooltipMode(oldMode)
Addon:SetTooltipCoverage(oldCoverage)
Addon:SetFeatureEnabled("playerTooltip", oldEnabled)
GameTooltip.GetUnit = oldGetUnit
for _, key in ipairs(keys) do _G[key] = previous[key] end
return checks
