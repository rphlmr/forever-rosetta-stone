local Addon, flushTimers = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local oldFrame, oldButton, oldAPI = TaxiFrame, TaxiButton17, C_TaxiMap
local oldMap, oldType = GetTaxiMapID, TaxiNodeGetType
local oldLabel = Addon.GetClientLabel
Addon.GetClientLabel = function(_, key, language) return ForeverRosettaStoneDB:GetGlobalStringByKey(key, language) end
local header = Addon.preferences.translationHeader
local mode, locale, coverage = Addon.preferences.tooltipMode, Addon:GetTargetLocale(), Addon.preferences.tooltipCoverage
TaxiFrame = CreateFrame("Frame", nil, UIParent)
local routeMap = CreateFrame("Frame", nil, TaxiFrame)
TaxiButton17 = CreateFrame("Button", nil, routeMap)
TaxiButton17:SetID(17)
local nodes = { { slotIndex = 17, nodeID = 4 } }
C_TaxiMap = { GetAllTaxiNodes = function(mapID)
    equal(mapID, 1415, "flight lookup uses the currently open taxi map")
    return nodes
end }
GetTaxiMapID = function() return 1415 end
local status = "CURRENT"
TaxiNodeGetType = function(slot) equal(slot, 17, "status uses the session slot"); return status end
Addon:SetTargetLocale("enUS")
Addon:SetTooltipCoverage("full")
Addon:SetTranslationHeader(true)
Addon:SetTooltipMode("separate")
GameTooltip:Hide()
GameTooltip.processingInfo = nil
GameTooltip.left, GameTooltip.top = 500, 700
GameTooltip:SetSize(260, 90)
local nativeName = "Colline des sentinelles, marche de l'Ouest"
local nativeDetail = "Vous êtes ici"
local function show()
    GameTooltip:Hide()
    GameTooltip:ClearLines()
    GameTooltip:SetOwner(TaxiButton17, "ANCHOR_RIGHT")
    GameTooltip:AddLine(nativeName)
    GameTooltip:AddLine(nativeDetail)
    GameTooltip:Show()
    flushTimers()
end
show()
local spec = Addon.nameTooltips[GameTooltip]
equal(spec.kind, "taxiNode", "native flight tooltip resolves its owner")
equal(spec.id, 4, "session slot resolves to the TaxiNodes ID, not button ID")
equal(spec.name, ForeverRosettaStoneDB:GetTaxiNodeName(4, "enUS"), "flight name comes from its owned catalog ID")
equal(spec.name ~= nil, true, "flight node has an official translation")
equal(spec.tip:IsShown(), true, "separate mode shows the flight translation")
equal(spec.tip:GetLeftLine(2):GetText(), "You are here", "current node uses the owned client label")
equal(GameTooltip:GetLeftLine(1):GetText(), "Colline des sentinelles, marche de l'Ouest", "native destination stays intact")
nodes = { { slotIndex = 17, nodeID = 2 } }
status = "REACHABLE"
nativeName, nativeDetail = "Hurlevent, Elwynn", "99|A:coin-copper:14:14:2:0|a"
show()
equal(spec.id, 2, "reused taxi slot resolves the new destination ID")
equal(spec.name, "Stormwind, Elwynn", "reachable destination uses its official English name")
equal(GameTooltip:GetLeftLine(2):GetText(), nativeDetail, "flight price remains native")
equal(spec.tip:NumLines(), 1, "destination translation does not duplicate prices or current-node status")
Addon:SetTooltipMode("stacked")
show()
equal(Addon.stackedTooltips[GameTooltip] ~= nil, true, "stacked mode embeds flight translation")
local count = GameTooltip:NumLines()
GameTooltip:Show()
flushTimers()
equal(GameTooltip:NumLines(), count, "repeated Show does not duplicate translation")
Addon:SetFeatureEnabled("taxiNodeTooltip", false)
show()
equal(spec.name, nil, "flight feature opt-out is honored")
Addon:SetFeatureEnabled("taxiNodeTooltip", true)
nodes = { secret = true }
show()
equal(spec.kind, nil, "restricted node lists preserve native text")
nodes = { { slotIndex = 18, nodeID = 4 } }
show()
equal(spec.kind, nil, "a missing slot never falls back to its title or list position")
nodes = { { slotIndex = 17, nodeID = 4 }, { slotIndex = 17, nodeID = 2 } }
show()
equal(spec.kind, nil, "ambiguous slots preserve native text")
nodes = { { slotIndex = 17, nodeID = 999999999 } }
show()
equal(spec.name, nil, "missing catalog data preserves native text")
nodes = { { slotIndex = 17, nodeID = 4 } }
TaxiFrame:Hide()
show()
equal(spec.kind, nil, "closed taxi map cannot identify another tooltip")
GameTooltip:Hide()
TaxiFrame, TaxiButton17, C_TaxiMap = oldFrame, oldButton, oldAPI
GetTaxiMapID, TaxiNodeGetType = oldMap, oldType
Addon.GetClientLabel = oldLabel
Addon:SetTargetLocale(locale)
Addon:SetTooltipCoverage(coverage)
Addon:SetTranslationHeader(header)
Addon:SetTooltipMode(mode)
return checks
