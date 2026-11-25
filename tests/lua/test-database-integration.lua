local Addon = ...
local checks = 0
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local originalObjectives = C_QuestLog.GetQuestObjectives
local questID = 7900
local quest = assert(ForeverRosettaStoneDB:GetQuest(questID, Addon:GetTargetLocale()))
local template = assert(quest.objectiveLines[1])
local originalText = template.text
local live = { { type = "item", text = "Peau : 2/7", numFulfilled = 2, numRequired = 7 } }
C_QuestLog.GetQuestObjectives = function(id)
    if id == questID then return live end
    return originalObjectives(id)
end
local expected = originalText:gsub("{current}", "2"):gsub("{required}", "7")
equal(Addon:GetProgressText(questID), expected, "real DB templates use live counts and requirements")
equal(template.text, originalText, "rendering never mutates shared DB text")
equal(live[1].text, "Peau : 2/7", "rendering never changes the native objective")
live[1].type = "monster"
equal(Addon:GetProgressText(questID), "Peau : 2/7", "a mismatched client index retains native text")
live[2] = { type = "item", text = "Objectif sans traduction" }
equal(Addon:GetProgressText(questID), "Peau : 2/7\nObjectif sans traduction", "unmapped indices retain native text")
equal(Addon:FormatQuestText("Hello <name>! $N $B<class>"), "Hello Rosetta! Rosetta \nMage",
    "player placeholders render without editing the stored source")
C_QuestLog.GetQuestObjectives = originalObjectives

local wolfMeat = { type = "item", text = "Viande de loup coriace : 8/8", numFulfilled = 8, numRequired = 8 }
C_QuestLog.GetQuestObjectives = function(id)
    if id == 179 then return { wolfMeat } end
    return originalObjectives(id)
end
equal(Addon:GetProgressText(179), "Tough Wolf Meat: 8/8", "quest 179 translates its live item objective")
wolfMeat.numFulfilled = 3
equal(Addon:GetProgressText(179), "Tough Wolf Meat: 3/8", "quest 179 keeps the current client count")
equal(wolfMeat.text, "Viande de loup coriace : 8/8", "translation never changes native objective text")
C_QuestLog.GetQuestObjectives = originalObjectives

local surveyGear = { type = "item", text = "Equipement d'analyse de Scrimshank : 2/5", numFulfilled = 2, numRequired = 5 }
local unmappedQuestID = 99999999
local originalGetQuest = Addon.GetQuest
Addon.GetQuest = function(self, id)
    if id == unmappedQuestID then return { title = "Unmapped fixture", objectiveLines = {} } end
    return originalGetQuest(self, id)
end
C_QuestLog.GetQuestObjectives = function(id)
    if id == unmappedQuestID then return { surveyGear } end
    return originalObjectives(id)
end
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "unindexed item names stay native")
equal(surveyGear.text, "Equipement d'analyse de Scrimshank : 2/5", "matching preserves native text")
surveyGear.text = "Equipement d'analyse de Scrimshank : 1/5"
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "mismatched displayed counts retain native text")
surveyGear.text = "|cffffffffEquipement d'analyse de Scrimshank|r : 2/5"
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "markup does not create an unsafe match")
surveyGear.text = "Equipement d'analyse de Scrimshank : 2 of 5"
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "unrecognized count format retains native text")
surveyGear.text = "Equipement d'analyse de Scrimshank : 2/5"
surveyGear.type = "monster"
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "item name matching never translates another objective type")
surveyGear.type = "item"
surveyGear.text = "Patron : Gilet rouge en tisse-mage : 2/5"
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "unindexed item names with colons stay native")
surveyGear.numRequired = nil
equal(Addon:GetProgressText(unmappedQuestID), surveyGear.text, "missing live counts retain native text")
C_QuestLog.GetQuestObjectives = originalObjectives
Addon.GetQuest = originalGetQuest

local getClientLocale, getTargetLocale = GetLocale, Addon.GetTargetLocale
local targetLocale, nativeLocale, deliveryID
local deliveryCases = 0
local targetLocaleCount = 0
for _ in pairs(ForeverRosettaStoneDB:GetLocales()) do
    targetLocaleCount = targetLocaleCount + 1
end
GetLocale = function() return nativeLocale end
Addon.GetTargetLocale = function() return targetLocale end
local deliveryObjective = { type = "log", numFulfilled = 0, numRequired = 1 }
C_QuestLog.GetQuestObjectives = function(id)
    if id == deliveryID then return { deliveryObjective } end
    return originalObjectives(id)
end
for _, id in ipairs({ 233, 234 }) do
    deliveryID = id
    for _, sourceLocale in ipairs({ "enUS", "frFR" }) do
        nativeLocale = sourceLocale
        local source = assert(ForeverRosettaStoneDB:GetQuest(id, sourceLocale))
        deliveryObjective.text = Addon:FormatQuestText(source.summary, id, sourceLocale)
        for locale in pairs(ForeverRosettaStoneDB:GetLocales()) do
            targetLocale = locale
            local translatedQuest = Addon:GetQuest(id)
            local progress = Addon:GetProgressText(id)
            if translatedQuest then
                local summary = Addon:FormatQuestText(translatedQuest.summary, id)
                equal(progress, deliveryObjective.text, "unmapped summary stays native: " .. id .. ":" .. sourceLocale .. ":" .. locale)
                local sections = Addon:GetQuestPageSections({
                    questID = id, title = translatedQuest.title, objectives = summary,
                    progress = progress, description = translatedQuest.description,
                })
                equal(sections[3].text, progress == summary and "" or progress,
                    "quest page omits only an identical summary: " .. id .. ":" .. locale)
            else
                equal(progress, "", "quest without translation has no companion progress")
            end
            equal(deliveryObjective.text, source.summary, "summary reuse never mutates the native objective")
            deliveryCases = deliveryCases + 1
        end
    end
end
equal(deliveryCases, 4 * targetLocaleCount, "delivery summaries cover both quests and client languages in every target locale")
GetLocale, Addon.GetTargetLocale = getClientLocale, getTargetLocale
C_QuestLog.GetQuestObjectives = originalObjectives

return checks
