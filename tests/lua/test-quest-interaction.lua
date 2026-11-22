local Addon, controls = ...
local ClientApi = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
if not Addon.GetClientLabel then
    assert(loadfile("ForeverRosettaStone/tooltips/client-labels.lua"))("ForeverRosettaStone", Addon)
end
local checks = 0
local function check(value, label)
    assert(value, label)
    checks = checks + 1
end

local old = { GossipFrame = GossipFrame, C_GossipInfo = C_GossipInfo, GetQuestID = GetQuestID }
local oldActiveCount, oldAvailableCount = GetNumActiveQuests, GetNumAvailableQuests
local oldActiveID, oldAvailableInfo = GetActiveQuestID, GetAvailableQuestInfo
local getObjectives = C_QuestLog.GetQuestObjectives
local mapShown = WorldMapFrame:IsShown()
WorldMapFrame:Hide()
SettingsPanel:Hide()
GameMenuFrame:Hide()
Addon.preferences.features.questPanel = true
controls.setMouseFoci({})
controls.setGamepad(false)

GossipFrame = CreateFrame("Frame", nil, UIParent)
GossipFrame:SetSize(338, 496)
GossipFrame.left, GossipFrame.top = 20, 800
local available, active = {}, { { questID = 179 } }
C_GossipInfo = {
    GetAvailableQuests = function() return available end,
    GetActiveQuests = function() return active end,
    SelectOption = function() end,
    SelectOptionByIndex = function() end,
}
QuestFrame = CreateFrame("Frame", nil, UIParent)
QuestFrame:SetSize(338, 496)
QuestFrame.left, QuestFrame.top = 20, 800
QuestFrameDetailPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameProgressPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameRewardPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameGreetingPanel = CreateFrame("Frame", nil, QuestFrame)
QuestFrameDetailPanel.Bg = QuestFrameDetailPanel:CreateTexture(nil, "BACKGROUND")
QuestFrameDetailPanel.Bg:SetAtlas("QuestBG-Parchment")
QuestFrameDetailPanel.Bg:SetSize(305, 422)
QuestFrameDetailPanel.Bg.left, QuestFrameDetailPanel.Bg.top = 27, 738
QuestFrame:Hide()
GetQuestID = function() return 179 end
local original = {}
for _, name in ipairs({ "GetTitleText", "GetQuestText", "GetObjectiveText", "GetProgressText", "GetRewardText",
    "GetGreetingText", "GetActiveTitle", "GetAvailableTitle", "QUEST_OBJECTIVES" }) do
    original[name] = _G[name]
end
GetTitleText = function() return "Native quest" end
GetQuestText = function() return "Native offer" end
GetObjectiveText = function() return "Native objectives" end
GetProgressText = function() return "Native progress question" end
GetRewardText = function() return "Native completion speech" end
GetGreetingText = function() return "Native legacy greeting" end
GetActiveTitle = function() return "Native active title" end
GetAvailableTitle = function() return "Native available title" end
QUEST_OBJECTIVES = "Objectives"
C_GossipInfo.GetText = function() return "Hé ! Vous m'avez l'air d'être costaud." end
C_GossipInfo.GetOptions = function() return { { name = "Native gossip option" } } end
local fulfilled = 8
C_QuestLog.GetQuestObjectives = function(id)
    if id == 179 then
        return { { type = "item", text = "Viande de loup coriace: " .. fulfilled .. "/8", numFulfilled = fulfilled, numRequired = 8 } }
    end

    return getObjectives(id)
end

local hidden = { mode = "hidden" }
do
    local db = ForeverRosettaStoneDB
    local lookup, unitSex, locale = db.GetQuestDialogue, UnitSex, GetLocale
    local getTarget = Addon.GetTargetLocale
    local source = Addon:GetTargetLocale() == "frFR" and "deDE" or "frFR"
    local alternate, missingSource, missingTarget
    GetLocale = function() return source end
    Addon.GetTargetLocale = function() return source == "frFR" and "deDE" or "frFR" end
    UnitSex = function() return 3 end
    db.GetQuestDialogue = function(_, questID, _, language)
        if questID ~= 179 then return end
        if language == source and missingSource then return end
        local rows = {
            { key = "female", npcID = 197, stage = "progress", playerSex = 3,
                text = language == source and "Texte natif" or "Translated progress" },
            { key = "male", npcID = 197, stage = "progress", playerSex = 2,
                text = language == source and "Texte natif" or "Other variant" },
        }
        if alternate and (language == "enUS" or not missingTarget) then
            rows[#rows + 1] = { key = "alternate", npcID = 197, stage = "progress", playerSex = 3,
                text = language == source and "Variante native" or alternate }
        end
        return rows
    end
    check(Addon:MatchQuestDialogue(197, 179, "progress", "Un autre texte") == "Translated progress",
        "a quest, NPC, phase and player variant can identify dialogue without matching wording")
    missingSource = true
    check(Addon:MatchQuestDialogue(197, 179, "progress", "Un autre texte") == "Translated progress",
        "an unambiguous quest line translates even with no catalog wording for the client language")
    missingSource = false
    check(not Addon:MatchQuestDialogue(198, 179, "progress", "Texte natif")
        and not Addon:MatchQuestDialogue(197, 179, "complete", "Texte natif"),
        "catalog dialogue refuses unmatched NPC and phase")
    alternate = "Translated progress"
    check(Addon:MatchQuestDialogue(197, 179, "progress", "Un autre texte") == "Translated progress",
        "quest variants with identical translations do not need to match the native text")
    alternate = "Alternate translation"
    check(Addon:MatchQuestDialogue(197, 179, "progress", " Variante native ") == "Alternate translation"
        and not Addon:MatchQuestDialogue(197, 179, "progress", "Un autre texte"),
        "the client text resolves competing quest variants")
    missingTarget = true
    check(not Addon:MatchQuestDialogue(197, 179, "progress", "Un autre texte"),
        "canonical quest variants count even when one locale has fewer entries")
    db.GetQuestDialogue, UnitSex, GetLocale = lookup, unitSex, locale
    Addon.GetTargetLocale = getTarget
end
do
    local oldLocale, oldTarget, oldSex = GetLocale, Addon.GetTargetLocale, UnitSex
    UnitSex = function() return 2 end
    GetLocale = function() return "frFR" end
    Addon.GetTargetLocale = function() return "enUS" end
    local native = [[Allez-donc, mon ami, sans tarder hâtez-vous !
Pour que notre breuvage, fidèle à mes dosages,
Tienne plus de la bière que d’un mauvais ragoût,
Il me manque du houblon pour en faire le brassage.]]
    local poem = Addon:MatchQuestDialogue(239, 117, "progress", native)
    check(poem and poem:gsub(" +\n", "\n") == [[Hurry, my friend, move with haste
In order for our rich lager to taste
More like beer and less like stew,
Hops are needed to make the brew.]], "Thunderbrew progress renders four English verses from the captured French")
    local turnIn = "Merci, ce repas tombe vraiment à pic ! Ça creuse, de protéger Comté-du-Lac des orcs et des gnolls !"
    check(Addon:MatchQuestDialogue(464, 129, "complete", turnIn)
        == "Thanks, I could really use the meal.  Guarding Lakeshire from the orcs and gnolls is tough work!",
        "Guard Parker's captured French turn-in dialogue resolves to the existing English translation")
    check(Addon:MatchQuestDialogue(464, 129, "complete", turnIn:gsub("Comté%-du%-Lac", "Lakeshire"))
        == "Thanks, I could really use the meal.  Guarding Lakeshire from the orcs and gnolls is tough work!",
        "changing the native location name does not hide the single known turn-in translation")
    GetLocale, Addon.GetTargetLocale, UnitSex = oldLocale, oldTarget, oldSex
end
do
    local getLocale, getTarget, getSex, getGuid, getGreeting =
        GetLocale, Addon.GetTargetLocale, UnitSex, UnitGUID, GetGreetingText
    GetLocale = function() return "frFR" end
    Addon.GetTargetLocale = function() return "enUS" end
    UnitSex = function() return 2 end
    UnitGUID = function() return "Creature-0-24074-0-14158044-1070-E19578FC96" end
    GetGreetingText = function()
        return "Plus loin, après le pont, vous trouverez la ville de Comté-du-Lac. Mais ne vous attendez pas à y trouver un endroit paisible. Si vous cherchez l’aventure, alors croyez-moi, vous l’avez trouvée !"
    end
    local activeCount, availableCount = GetNumActiveQuests, GetNumAvailableQuests
    GetNumActiveQuests = function() return 0 end
    GetNumAvailableQuests = function() return 0 end
    local sections, _, missing = Addon:GetCatalogDialogueSections(nil, "greeting")
    check(sections and not missing and sections[1].text:find("Lakeshire", 1, true)
        and sections[1].text:find("lad", 1, true), "Feldon's captured greeting resolves to the English male variant")
    UnitSex = function() return 3 end
    local female, _, femaleMissing = Addon:GetCatalogDialogueSections(nil, "greeting")
    check(female and not femaleMissing and female[1].text:find("Lakeshire", 1, true)
        and female[1].text:find("lass", 1, true), "Feldon's greeting selects the English female variant")
    GetLocale, Addon.GetTargetLocale, UnitSex, UnitGUID, GetGreetingText =
        getLocale, getTarget, getSex, getGuid, getGreeting
    GetNumActiveQuests, GetNumAvailableQuests = activeCount, availableCount
end
do
    local getLocale, getTargetLocale, getUnitGUID = GetLocale, Addon.GetTargetLocale, UnitGUID
    local getUnitSex = UnitSex
    local getText, getOptions, getActiveQuests = C_GossipInfo.GetText, C_GossipInfo.GetOptions, C_GossipInfo.GetActiveQuests
    GetLocale = function() return "enUS" end
    Addon.GetTargetLocale = function() return "trTR" end
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-33177-1-576977-3934-5C27864BF2" or nil end
    UnitSex = function() return 2 end
    C_GossipInfo.GetText = function() return "As the wind on the plains, you are always welcome here." end
    C_GossipInfo.GetActiveQuests = function() return {} end
    C_GossipInfo.GetOptions = function()
        return {
            { gossipOptionID = 96520, orderIndex = 2, icon = 132052, name = "Make this inn your home." },
            { gossipOptionID = 96519, orderIndex = 3, icon = 132060, name = "Let me browse your goods." },
            { gossipOptionID = 96518, orderIndex = 5, icon = 132053, name = "Tell me about dungeons I could explore." },
        }
    end
    local database = ForeverRosettaStoneDB
    check(database:GetNpcName(3244, "trTR") == "Büyük Ovagezgini", "Turkish Greater Plainstrider uses the community name")
    local dialogue = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(dialogue and #dialogue == 4, "Boorand's Turkish dialogue has no missing-options warning")
    check(dialogue[2].text == "Bu hanı evim yapmak istiyorum."
        and dialogue[3].text == "Mallarına bakmak istiyorum."
        and dialogue[4].text == "Keşfedebileceğim zindanlardan bahseder misin?",
        "Boorand's three visible options are translated in Turkish")
    GetLocale = function() return "frFR" end
    Addon.GetTargetLocale = function() return "enUS" end
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-37733-0-3383502-6740-8EA63345E2" or nil end
    C_GossipInfo.GetText = function()
        return "Bienvenue dans mon auberge, voyageur épuisé. Que puis-je faire pour vous ?"
    end
    local innOptions = {
        { gossipOptionID = 96506, orderIndex = 2, icon = 132052, name = "Faites de cette auberge votre foyer." },
        { gossipOptionID = 96505, orderIndex = 3, icon = 132060, name = "Permettez-moi de jeter un oeil à vos biens." },
        { gossipOptionID = 96504, orderIndex = 5, icon = 132053, name = "Parlez-moi des donjons que je pourrais explorer." },
    }
    C_GossipInfo.GetOptions = function() return innOptions end
    local inn = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(inn and #inn == 4 and inn[2].text == "Make this inn your home."
        and inn[3].text == "Let me browse your goods." and inn[4].text == "Tell me about dungeons I could explore.",
        "Allison's captured menu translates all three options without a missing-options warning")
    check(not Addon:GetGossipOptionTranslation({ icon = 132053, name = innOptions[3].name }, "enUS"),
        "an unbound gossip option keeps its label even when its wording is familiar")
    C_GossipInfo.GetText = function() return "Souhaitez-vous explorer l'un de ces donjons ?" end
    C_GossipInfo.GetOptions = function()
        return {
            { gossipOptionID = 96727, orderIndex = 2, icon = 132053, name = "Mortemines" },
            { gossipOptionID = 139088, orderIndex = 1, icon = 132053, name = "Ruines de Lordaeron" },
            { gossipOptionID = 139084, orderIndex = 0, icon = 132053, name = "La salle des Thanes" },
        }
    end
    local dungeons = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(dungeons and #dungeons == 4 and dungeons[1].text == "Are you interested in exploring one of these dungeons?"
        and dungeons[2].text == "Deadmines" and dungeons[3].text == "Ruins of Lordaeron"
        and dungeons[4].text == "Hall of Thanes", "All three options in Allison's dungeon list translate")

    local followUp = { gossipOptionID = 139082, orderIndex = 0, icon = 132053,
        name = "Pourriez-vous m'en dire davantage sur cet endroit ?" }
    C_GossipInfo.GetOptions = function() return { followUp } end
    C_GossipInfo.GetText = function()
        return "L’ancien royaume de Lordaeron est une région dangereuse. Usez de prudence si vous osez vous aventurer sur les terres désolées des clairières de Tirisfal. S’il le faut, trouvez Fossoyeuse et ses cours supérieures."
    end
    local lordaeron = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(lordaeron and #lordaeron == 2 and lordaeron[1].text:find("The old kingdom of Lordaeron is perilous.", 1, true)
        and lordaeron[2].text == "Can you tell me more about this place?", "Allison's Lordaeron hint and question translate")
    followUp.gossipOptionID = 95948
    C_GossipInfo.GetText = function()
        return "Les Mortemines se trouvent au-dessous de Ruisselune dans le sud de la marche de l'Ouest."
    end
    local deadmines = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(deadmines and #deadmines == 2 and deadmines[1].text:find("beneath Moonbrook", 1, true)
        and deadmines[2].text == lordaeron[2].text, "Allison's Deadmines menu reuses the observed follow-up question")

    followUp.gossipOptionID = 139083
    C_GossipInfo.GetText = function()
        return "La salle des Thanes est scellée. Ceux qui n’ont pas audience avec le roi Magni Barbe-de-Bronze doivent obtenir sa confiance et son accord pour s’aventurer dans les profondeurs du Vieux Forgefer."
    end
    local thanes = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(thanes and #thanes == 2 and thanes[1].text:find("The Hall of Thanes is sealed off.", 1, true)
        and thanes[2].text == lordaeron[2].text, "Allison's Hall of Thanes hint and follow-up translate")

    -- The selector reads the known option ID and the next event identifies the terminal screen.
    Addon:InstallNpcGossipTracking()
    C_GossipInfo.SelectOptionByIndex(followUp.orderIndex)
    C_GossipInfo.GetText = function() error("NPC resolution must not read client prose") end
    C_GossipInfo.GetOptions = function() return {} end
    Addon.npcGossipTracking:Fire("OnEvent", "GOSSIP_SHOW")
    local thanesLore = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(thanesLore and #thanesLore == 1 and thanesLore[1].text:find("immense geodes crown the chamber", 1, true),
        "the selected Hall of Thanes option resolves the next screen without reading its text")
    Addon.npcGossipTracking:Fire("OnEvent", "GOSSIP_CLOSED")
    local reopened, _, reopenedMissing = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(not reopened, "closing gossip discards the selected route")

    UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-0-4-999999-ABCD" end
    local menuOption = { gossipOptionID = 139084, icon = 132053, name = "Changed client label" }
    local unknownOption = { gossipOptionID = 999999999, icon = 132053, name = "Kraal de Tranchebauge" }
    C_GossipInfo.GetOptions = function() return { menuOption, unknownOption } end
    local sharedMenu = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(sharedMenu and #sharedMenu == 4 and sharedMenu[1].text == dungeons[1].text
        and sharedMenu[3].text == "Hall of Thanes" and sharedMenu[4].text == unknownOption.name,
        "another NPC reuses known IDs and an unknown ID keeps its native label")
    C_GossipInfo.GetOptions = function() return { menuOption, followUp } end
    local _, _, ambiguous = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(ambiguous, "different routes in the same menu leave ambiguous prose native")

    UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-0-4-2455-ABCD" end
    local bankOption = { gossipOptionID = 95532, icon = 132050, name = "J'aimerais regarder le contenu de mon coffre." }
    C_GossipInfo.GetOptions = function() return { bankOption } end
    local bank, _, bankMissing = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(bank and bankMissing and bank[1].text == "I would like to check my deposit box.",
        "Olivia's verified bank option translates without guessing between her greetings")
    bankOption.gossipOptionID = 999999999
    check(not Addon:GetGossipOptionTranslation(bankOption, "enUS"),
        "an unknown bank option ID does not match by native label")
    GetLocale = function() return "enUS" end
    Addon.GetTargetLocale = function() return "trTR" end
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-0-4-1573-ABCD" end
    C_GossipInfo.GetText = function() return "An unexpected introduction" end
    C_GossipInfo.GetOptions = function() return {} end
    local introduction = "Wildhammer cücelerinin binekleri hızlı olabilir ama Aerie Peak grifonları Büyük Demirhane’nin sıcağına dayanabilir mi? Hiç sanmıyorum!"
    local vendor = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(vendor and vendor[1].text == introduction,
        "a single service NPC introduction translates without matching the live text")
    C_GossipInfo.GetText = function() return nil end
    vendor = Addon:GetCatalogDialogueSections(nil, "gossip")
    check(vendor and vendor[1].text == introduction,
        "the service NPC introduction translates when the client returns no text")
    GetLocale, Addon.GetTargetLocale, UnitGUID = getLocale, getTargetLocale, getUnitGUID
    UnitSex = getUnitSex
    C_GossipInfo.GetText, C_GossipInfo.GetOptions, C_GossipInfo.GetActiveQuests = getText, getOptions, getActiveQuests
end
check(Addon:TransitionQuestInteraction(hidden, { type = "dismiss" }) == hidden, "hidden refuses dismissal")
check(Addon:TransitionQuestInteraction(hidden, { type = "present", questID = 179, context = "detail" }) == hidden,
    "selection without a native source cannot become visible")
check(Addon:TransitionQuestInteraction(hidden, { type = "present", source = GossipFrame,
    questID = 179, context = "unknown" }) == hidden, "unknown screen cannot become visible")

local manual = Addon:TransitionQuestInteraction(hidden, { type = "present", source = QuestFrame,
    questID = 179, context = "detail", autoOpen = false })
check(manual.mode == "dismissed", "without auto-open a new NPC screen starts on the bookmark")
check(Addon:TransitionQuestInteraction(manual, { type = "present", source = QuestFrame, questID = 179,
    context = "reward", autoOpen = false }).mode == "dismissed", "without auto-open the next NPC screen stays closed")
check(Addon:TransitionQuestInteraction({ mode = "visible", source = QuestFrame, questID = 179, context = "progress" },
    { type = "present", source = QuestFrame, questID = 179, context = "reward", autoOpen = false }).mode == "dismissed",
    "a disabled turn-in stays on the bookmark after visible progress")
check(Addon:TransitionQuestInteraction({ mode = "visible", source = QuestFrame, questID = 179, context = "progress" },
    { type = "present", source = QuestFrame, questID = 179, context = "progress", dialogueKey = "refresh",
        autoOpen = false }).mode == "visible", "a manually reopened screen stays visible when its text refreshes")
Addon.preferences.features.questAutoOpen = false
check(Addon:Transition(Addon:CreateQuestState(), "quest.select", 179).mode == "collapsed",
    "without auto-open the journal starts on its bookmark")
check(Addon:Transition({ mode = "collapsed", questID = 179 }, "quest.select", 399).mode == "collapsed",
    "without auto-open another journal quest keeps the bookmark")
check(Addon:Transition({ mode = "open", questID = 179 }, "quest.select", 399).mode == "open",
    "an opened journal reader follows the selected quest")
local function CheckNoNpcCompanion(label)
    local reader, bookmark = Addon.questInteractionReader, Addon.questInteractionBookmark
    check(not (reader and reader.frame:IsShown()) and not (bookmark and bookmark:IsShown()), label)
end
Addon:UpdateQuestInteraction()
CheckNoNpcCompanion("gossip with a listed quest has no translation window or bookmark")
do
    local nativeViewport = CreateFrame("Frame", nil, GossipFrame)
    nativeViewport.left, nativeViewport.top = GossipFrame:GetLeft() + 8, GossipFrame:GetTop() - 65
    nativeViewport:SetSize(300, 403)
    local nativeBar = CreateFrame("Frame", nil, GossipFrame)
    nativeBar.left, nativeBar.top = GossipFrame:GetLeft() + 314, GossipFrame:GetTop() - 68
    nativeBar:SetSize(8, 397)
    GossipFrame.GreetingPanel = { ScrollBox = nativeViewport, ScrollBar = nativeBar }
    do
        local getOptions, savedActive = C_GossipInfo.GetOptions, active
        local auction = { gossipOptionID = 95419, orderIndex = 0, name = "Hôtel des ventes" }
        local bank = { gossipOptionID = 95418, orderIndex = 1, name = "Banque de Forgefer" }
        local trainer = { gossipOptionID = 95408, orderIndex = 11, name = "Maître de profession" }
        local unknown = { orderIndex = 16, name = "Native option without a translation" }
        local apiOptions = { trainer, bank, auction, unknown }
        active = {}
        C_GossipInfo.GetOptions = function() return apiOptions end
        GossipFrame.gossipOptions = { auction, bank, trainer, unknown }

        local greeting = CreateFrame("Frame", nil, nativeViewport)
        greeting.GreetingText = greeting:CreateFontString()
        greeting.GreetingText.top = 710
        greeting.GreetingText:SetHeight(16)
        local rows = { greeting }
        for index, option in ipairs(GossipFrame.gossipOptions) do
            local row = CreateFrame("Button", nil, nativeViewport)
            row.top = 674 - (index - 1) * 18
            row:SetHeight(18)
            row:SetText(option.name)
            row.GetElementData = function() return { info = option } end
            rows[#rows + 1] = row
        end
        function nativeViewport:ForEachFrame(callback)
            for index = #rows, 1, -1 do callback(rows[index]) end
        end

        local locale = Addon:GetTargetLocale()
        local dialogue = Addon:CreateQuestDialogueSections("Translated greeting", "gossip")
        check(dialogue[2].text == Addon:GetMissingTranslationMessage("gossipOptions"),
            "a partly translated menu explains missing options once")
        check(dialogue[3].text == ForeverRosettaStoneDB:GetGossipOptionName(auction.gossipOptionID, locale)
            and dialogue[4].text == ForeverRosettaStoneDB:GetGossipOptionName(bank.gossipOptionID, locale)
            and dialogue[5].text == ForeverRosettaStoneDB:GetGossipOptionName(trainer.gossipOptionID, locale)
            and dialogue[6].text == unknown.name,
            "guard options use catalog translations in native display order, with native text for unknown options")
        check(dialogue[3].gap == 20 and dialogue[4].gap == 0 and dialogue[5].gap == 0 and dialogue[6].gap == 0,
            "guard options start after the native greeting gap and stay adjacent")

        local getText, getLocale, unitGUID = C_GossipInfo.GetText, GetLocale, UnitGUID
        local unitSex, unitName = UnitSex, UnitName
        GetLocale = function() return "frFR" end
        UnitSex = function() return 2 end
        UnitName = function(unit) return unit == "npc" and "Garde royale de fer" or "Player" end
        UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-0-4-274781-ABCD" end end
        C_GossipInfo.GetText = function() return "Où voulez-vous aller ?" end
        local catalogSections = Addon:GetCatalogDialogueSections(0, "gossip")
        check(catalogSections and catalogSections[1].text == "What do ye need directions to?",
            "the captured Ironforge greeting reuses directions instead of flight dialogue")
        UnitGUID = function() return "Creature-0-1-0-4-99999999-ABCD" end
        C_GossipInfo.GetText = function() return "Un accueil inconnu" end
        local reused = Addon:GetCatalogDialogueSections(0, "gossip")
        check(reused and reused[1].text == catalogSections[1].text,
            "another guard can reuse the route associated with the same option IDs")
        local reset = { gossipOptionID = 97311, icon = 132053, name = "Je voudrais oublier mes talents d’héritage ou de classe." }
        local directions = { gossipOptionID = 99999999, icon = 132053, name = "Maître de Classe" }
        GossipFrame.gossipOptions = { reset, directions }
        C_GossipInfo.GetOptions = function() return GossipFrame.gossipOptions end
        local shared = Addon:GetCatalogDialogueSections(0, "gossip")
        check(shared and shared[1].text == "I wish to unlearn my class or legacy talents."
            and shared[2].text == directions.name,
            "the NPC reader translates the known reset ID and leaves an unknown option native")
        check(Addon:GetGossipOptionTranslation(reset, locale) == shared[1].text,
            "Joshua's reset option uses the same lookup as the gossip tooltip")
        GossipFrame.gossipOptions = { auction, bank, trainer, unknown }
        local savedLocale = Addon.preferences.locale
        Addon.preferences.locale = "frFR"
        GetLocale = function() return "enUS" end
        UnitGUID = function(unit) if unit == "npc" then return "Creature-0-6867-0-2-5595-EA631DAB78" end end
        C_GossipInfo.GetText = function() return "What do ye need directions to?" end
        local guard = Addon:GetCatalogDialogueSections(0, "gossip")
        check(guard and guard[1].text == "Où voulez-vous aller ?",
            "the Ironforge guard's verified option IDs select the Forever greeting")
        Addon.preferences.locale = savedLocale
        GetLocale = function() return "frFR" end
        UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-0-4-274781-ABCD" end end
        local unknownMenu = { { orderIndex = 0 }, { gossipOptionID = 95532, orderIndex = 1 } }
        C_GossipInfo.GetOptions = function() return unknownMenu end
        C_GossipInfo.GetText = function() return "Native greeting without a verified route" end
        Addon.preferences.features.questAutoOpen = true
        Addon:UpdateQuestInteraction()
        CheckNoNpcCompanion("service gossip has no companion even with owned translations")
        local flags, util = Enum.GossipOptionRecFlags, FlagsUtil
        Enum.GossipOptionRecFlags = { QuestLabelPrepend = 4 }
        FlagsUtil = { IsSet = function(value, flag) return math.floor(value / flag) % 2 == 1 end }
        unknownMenu[2].flags = 4
        Addon:UpdateQuestInteraction()
        CheckNoNpcCompanion("a quest-marked option still belongs to the native gossip menu")
        Enum.GossipOptionRecFlags, FlagsUtil = flags, util
        C_GossipInfo.GetText, GetLocale, UnitGUID = getText, getLocale, unitGUID
        UnitSex, UnitName = unitSex, unitName

        local flight = { gossipOptionID = 98541, orderIndex = 0, name = "Un vol, s’il vous plaît.", icon = 132057 }
        GossipFrame.gossipOptions = { flight }
        dialogue = Addon:CreateQuestDialogueSections("Translated greeting", "gossip")
        check(#dialogue == 2 and dialogue[2].text == "I need a ride.",
            "a different flight option ID shares the label without a missing-translation notice")

        nativeViewport.ForEachFrame = nil
        GossipFrame.gossipOptions = nil
        C_GossipInfo.GetOptions, active = getOptions, savedActive
    end
    local getOptions = C_GossipInfo.GetOptions
    local flight = { gossipOptionID = 97329, orderIndex = 0, name = "Je dois voyager." }
    C_GossipInfo.GetOptions = function() return { flight } end
    local option = CreateFrame("Button", nil, nativeViewport)
    option:SetText(flight.name)
    option.left, option.top = 30, 690
    option:SetSize(278, 20)
    function option:GetElementData() return { info = { gossipOptionID = flight.gossipOptionID } } end
    local quest = CreateFrame("Button", nil, nativeViewport)
    quest.questID = 179
    quest.left, quest.top = 30, 665
    quest:SetSize(278, 20)
    controls.setMouseFoci({ option, quest })
    Addon:UpdateTooltipComponents()
    CheckNoNpcCompanion("updating a mixed menu does not open the quest companion")
    check(Addon.gossipOptionTooltip:IsShown() and Addon.questOfferTooltip:IsShown(),
        "both focused native rows retain their translation tooltips")
    C_GossipInfo.GetOptions = getOptions
    controls.setMouseFoci({})
end
GossipFrame:Hide()
QuestFrame:Show()
QuestFrameDetailPanel:Hide(); QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide()
QuestFrameGreetingPanel:Show()
GetNumActiveQuests = function() return 1 end
GetNumAvailableQuests = function() return 0 end
GetActiveQuestID = function() return 179 end
do
    local originalRow, originalHeading = QuestTitleButton1, CurrentQuestsText
    local row = CreateFrame("Button", nil, QuestFrameGreetingPanel)
    local heading = QuestFrameGreetingPanel:CreateFontString()
    local nativeTitle = "|cff40c040[17]|r Native active title"
    row:SetText(nativeTitle)
    QuestTitleButton1 = row
    CurrentQuestsText = heading
    local sections = Addon:CreateQuestDialogueSections("Translated greeting", "greeting")
    check(sections[2].text == Addon:GetClientLabel("CURRENT_QUESTS", Addon:GetTargetLocale())
        and sections[2].source == heading,
        "translated quest groups show their heading in the target locale with the native heading style")
    check(sections[3].text == Addon:GetQuest(179).title and sections[3].source == row:GetFontString()
        and row:GetText() == nativeTitle,
        "translated quest titles use the native row font without inheriting the level prefix color")
    QuestTitleButton1, CurrentQuestsText = originalRow, originalHeading
end
Addon:UpdateQuestInteraction()
CheckNoNpcCompanion("a legacy quest greeting with a listed quest has no companion")
QuestFrameGreetingPanel:Hide()

-- A quest screen with translated text is the companion's vehicle from here on.
QuestFrameDetailPanel:Show()
Addon.preferences.features.questAutoOpen = false
Addon:UpdateQuestInteraction()
check(Addon.questInteractionState.mode == "dismissed" and Addon.questInteractionBookmark:IsShown()
    and not (Addon.questInteractionReader and Addon.questInteractionReader.frame:IsShown()),
    "without auto-open NPC windows only show the bookmark")
Addon.preferences.features.questAutoOpen = true
Addon:SendQuestInteraction({ type = "reset" })
check(Addon:Transition(Addon:CreateQuestState(), "quest.select", 179).mode == "open", "auto-open is the default")
Addon:UpdateQuestInteraction()
local reader = Addon.questInteractionReader
check(reader.frame:IsShown() and Addon.questInteractionState.questID == 179, "translated quest offer shows companion reader")
local point, source, relative = reader.frame:GetPoint(1)
check(source == QuestFrame and point == "TOPLEFT" and relative == "TOPRIGHT", "reader anchors beside the quest window")
check(select(4, reader.frame:GetPoint(1)) == 0, "companion touches original panel")
check(reader.frame.PortraitContainer:IsShown() == false, "companion omits NPC portrait")
check(reader.parchment:IsShown() and reader.parchment:GetAtlas() == "QuestBG-Parchment",
    "companion draws the native parchment atlas")
local _, _, _, parchmentX, parchmentY = reader.parchment:GetPoint(1)
check(parchmentX == 7 and parchmentY == -62 and reader.parchment:GetWidth() == 305
    and reader.parchment:GetHeight() == 422, "companion parchment keeps native offset and size")
QuestFrame.Inset = CreateFrame("Frame", nil, QuestFrame, "InsetFrameTemplate")
QuestFrame.Inset.left, QuestFrame.Inset.top = 24, 740
QuestFrame.Inset:SetSize(328, 410)
Addon:UpdateQuestInteraction()
local inset = reader.frame.questInset
local _, insetParent, _, insetX, insetY = inset:GetPoint(1)
check(inset:IsShown() and inset.template == "InsetFrameTemplate" and insetParent == reader.frame
    and insetX == 4 and insetY == -60 and inset:GetWidth() == 328 and inset:GetHeight() == 410,
    "companion uses the native inset behind its parchment and scrollbar")
QuestFrame.Inset:Hide()
Addon:UpdateQuestInteraction()
check(not inset:IsShown(), "hidden native inset clears the companion background")
local sections = reader.body.lastSections
Addon:UpdateQuestInteraction()
check(reader.body.lastSections == sections, "stable polling does not rebuild text or reset reading")
fulfilled = 7
Addon:UpdateQuestInteraction()
check(reader.body.lastSections == sections, "journal counts cannot change offer content")
Addon:SendQuestInteraction({ type = "dismiss" })
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown() and Addon.questInteractionState.mode == "dismissed", "polling respects dismissal")
check(Addon.questInteractionBookmark:IsShown(), "dismissed companion exposes bookmark on original")
Addon.questInteractionBookmark:Fire("OnClick")
check(reader.frame:IsShown() and not Addon.questInteractionBookmark:IsShown(), "bookmark reopens companion")
controls.setGamepad(true)
Addon:SendQuestInteraction({ type = "dismiss" })
Addon:UpdateQuestInteraction()
local bookmark, bookmarkManager = Addon.questInteractionBookmark, GamepadMode.FrameControlsManager
local bookmarkTooltip = Addon:GetWidgetTooltip()
check(bookmark.registered, "a dismissed reader's bookmark joins controller navigation")
check(bookmark.gamepadPrompt:IsShown() and bookmark.gamepadPrompt.inputKey == "PADRTRIGGER",
    "a reachable NPC bookmark shows the right trigger")
local _, promptAnchor, _, promptX = bookmark.gamepadPrompt:GetPoint(1)
check(promptAnchor == bookmark.Icon and promptX == 0, "bookmark hints align with the Rosetta Stone icon")
bookmarkManager:FrameHidden(bookmark.host)
bookmarkManager:FrameShown(bookmark.host, false, true)
check(bookmark.gamepadPrompt:IsShown() and bookmark.gamepadPrompt.inputKey == GAMEPAD_FACE_BOTTOM,
    "the focused NPC bookmark shows only the select glyph")
check(SmartNavigation:GetCurrentButton() == bookmark, "focusing the bookmark frame selects the bookmark")
check(bookmarkTooltip:IsShown() and bookmarkTooltip:IsOwned(bookmark)
    and bookmarkTooltip:GetText() == Addon:GetOpenPanelLabel(), "controller focus shows the reopen tooltip")
bookmarkManager:FrameHidden(bookmark.host)
check(not bookmarkTooltip:IsShown(), "leaving the bookmark hides its tooltip")
bookmarkManager:FrameShown(bookmark.host, false, true)
bookmark:Fire("OnClick")
check(reader.frame:IsShown() and not bookmark:IsShown() and not bookmark.registered
    and bookmarkManager.focusedFrame == reader.frame, "A on the bookmark opens the reader with controller focus")
check(not bookmarkTooltip:IsShown(), "opening the reader clears the bookmark tooltip")
Addon:SendQuestInteraction({ type = "dismiss" })
Addon:UpdateQuestInteraction()
check(not bookmark.host.SmartNavigationCloseHandler() and QuestFrame:IsShown(),
    "an unfocused bookmark leaves the native panel open")
bookmarkManager:FrameHidden(bookmark.host)
bookmarkManager:FrameShown(bookmark.host, false, true)
check(bookmark.host.SmartNavigationCloseHandler() and not QuestFrame:IsShown()
    and not bookmark.registered and not bookmark.gamepadPrompt:IsShown(),
    "Back on the focused bookmark closes the native panel and releases the bookmark")
controls.setGamepad(false)
Addon:UpdateQuestInteraction()
check(Addon.questInteractionState.mode == "hidden", "closing NPC clears selection")
QuestFrame:Show()
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown(), "new NPC interaction can open again")
GetQuestID = function() return 999999999 end
Addon:SendQuestInteraction({ type = "reset" })
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown() and reader.frame.title == "Forever Rosetta Stone"
    and reader.options:IsShown() and reader.options:GetText() == "Options",
    "an untranslated quest opens a reportable missing page")
GetQuestID = function() return 179 end
Addon:UpdateQuestInteraction()
controls.setGamepad(true)
Addon:UpdateQuestInteraction()
local component = Addon:GetTooltipComponent("questInteraction")
check(component.SelectPlacementPolicy(QuestFrame).inputMode == "gamepad", "NPC reader selects isolated gamepad configuration")
check(reader.registered == true, "gamepad reader registers with native panel navigation")
GamepadMode.FrameControlsManager:FrameHidden(reader.frame)
GamepadMode.FrameControlsManager:FrameShown(reader.frame, false, true)
check(SmartNavigation.scrollFrames[reader.frame] == reader.body.frame, "native focus enables gamepad scrolling")
reader.frame.SmartNavigationCloseHandler()
check(not reader.frame:IsShown() and not reader.registered, "native Back dismisses and unregisters the reader")
controls.setGamepad(false)
Addon:SendQuestInteraction({ type = "reset" })
QuestFrameDetailPanel:Hide()
QuestFrameGreetingPanel:Hide()
-- Missing progress and completion prose is reportable from the corresponding NPC screen.
local savedProgress, savedReward = GetProgressText, GetRewardText
GetProgressText = function() return "Native progress" end
GetRewardText = function() return "Native completion" end
for _, screen in ipairs({ { QuestFrameProgressPanel, "progress" }, { QuestFrameRewardPanel, "reward" } }) do
    QuestFrameDetailPanel:Hide(); QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide()
    screen[1]:Show()
    Addon:UpdateQuestInteraction()
    check(reader.frame:IsShown() and reader.frame.title == "Forever Rosetta Stone"
        and reader.options:IsShown() and reader.options:GetText() == "Options",
        screen[2] .. " opens a reportable missing page")
    reader.options.contextMenu = nil
    reader.options:Fire("OnClick")
    local menu = reader.options.contextMenu
    check(menu and menu.entries[2].label == Addon:SettingsText("questBugged"),
        "missing " .. screen[2] .. " uses the same quest options menu")
    menu.entries[2].onClick()
    local dialog = Addon.questReport
    local native = dialog.record.interaction
    check(native.screen == screen[2] and dialog.record.questID == 179
        and (native.progress == "Native progress" or native.completion == "Native completion"),
        "report stores the quest phase and its native text")
    dialog.frame:Hide()
end
GetProgressText, GetRewardText = savedProgress, savedReward
Addon.preferences.features.questProgressAutoOpen = false
QuestFrameRewardPanel:Hide()
QuestFrameProgressPanel:Show()
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown() and Addon.questInteractionBookmark:IsShown(),
    "progress remains collapsed even when the previous turn-in was visible")
Addon.questInteractionBookmark:Fire("OnClick")
check(reader.frame:IsShown(), "the progress bookmark still reopens the reader")
QuestFrameProgressPanel:Hide()
QuestFrameRewardPanel:Show()
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown(), "disabling progress preserves turn-in auto-open")
Addon.preferences.features.questRewardAutoOpen = false
QuestFrameRewardPanel:Hide()
QuestFrameProgressPanel:Show()
Addon.preferences.features.questProgressAutoOpen = true
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown(), "disabling turn-in preserves progress auto-open")
QuestFrameProgressPanel:Hide()
QuestFrameRewardPanel:Show()
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown() and Addon.questInteractionBookmark:IsShown(),
    "the turn-in checkbox independently leaves the reward screen on its bookmark")
Addon.preferences.features.questRewardAutoOpen = true
QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide(); QuestFrameDetailPanel:Show()
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown() and Addon.questInteractionState.context == "detail", "native offer screen owns the reader")
check(reader.body.lastSections[2].text:find("What do we have here", 1, true), "offer starts with description")
check(reader.body.lastSections[3].text == (Addon:GetClientLabel("QUEST_OBJECTIVES", Addon:GetTargetLocale()) or QUEST_OBJECTIVES), "offer has native objectives header")
check(not table.concat((function()
    local text = {}; for _, section in ipairs(reader.body.lastSections) do text[#text + 1] = section.text end
    return text
end)(), " "):find("7/8", 1, true), "offer excludes accepted quest progress")
do
    local database = ForeverRosettaStoneDB
    local lookup, locale, sex, guid, questText = database.GetQuestDialogue, GetLocale, UnitSex, UnitGUID, GetQuestText
    local target = Addon:GetTargetLocale()
    local source = target == "enUS" and "frFR" or "enUS"
    local ambiguous
    GetLocale = function() return source end
    UnitSex = function() return 2 end
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-0-0-0-197-1" or nil end
    GetQuestText = function() return "Native offer variant" end
    database.GetQuestDialogue = function(_, questID, _, language)
        if questID == 179 then
            local offers = { { key = "offer", npcID = 197, stage = "accept",
                text = language == source and "Native offer variant" or "Translated offer variant" } }
            if ambiguous then
                offers[2] = { key = "second", npcID = 197, stage = "accept",
                    text = language == source and "Other native offer" or "Other translated offer" }
            end
            return offers
        end
    end
    Addon:UpdateQuestInteraction()
    check(reader.body.lastSections[2].text == "Translated offer variant",
        "matching NPC offer takes precedence over the generic quest description")
    GetQuestText = function() return "A different offer" end
    Addon:UpdateQuestInteraction()
    check(reader.body.lastSections[2].text == "Translated offer variant",
        "an unambiguous offer translates independently of the live wording")
    GetQuestText = function() return nil end
    Addon:UpdateQuestInteraction()
    check(reader.body.lastSections[2].text == "Translated offer variant",
        "an unambiguous offer translates when the live text is unavailable")
    ambiguous = true
    Addon:UpdateQuestInteraction()
    check(reader.body.lastSections[2].text:find("What do we have here", 1, true),
        "an ambiguous offer keeps the translated quest description")
    database.GetQuestDialogue, GetLocale, UnitSex, UnitGUID, GetQuestText = lookup, locale, sex, guid, questText
    Addon:UpdateQuestInteraction()
end
local _, anchor = reader.frame:GetPoint(1)
check(anchor == QuestFrame, "quest window owns companion placement")
check(reader.options:IsShown() and reader.frame.CloseButton:IsShown(), "quest screens offer Options beside the mouse X")
reader.options:Fire("OnClick")
local npcMenu = reader.options.contextMenu
check(npcMenu and npcMenu.entries[2].label == Addon:SettingsText("questBugged"), "NPC Options opens the journal menu")
npcMenu.entries[2].onClick()
check(Addon.questReport.state == "waiting" and Addon.questReport.record.questID == 179,
    "NPC Options reports the quest shown by the native screen")
reader.options.contextMenu = nil
reader.options:Fire("OnClick")
check(reader.options.contextMenu == nil, "Options cannot stack a menu over an open report")
Addon.questReport.frame:Hide()
check(Addon.questReport.state == "closed", "closing the report leaves the NPC reader in place")
local npcManager = GamepadMode.FrameControlsManager
controls.setGamepad(true)
Addon:UpdateQuestInteraction()
npcManager:FrameHidden(reader.frame)
npcManager:FrameShown(reader.frame, false, true)
check(SmartNavigation:GetCurrentButton() == nil, "NPC reader opens without selecting Options")
reader:SyncTarget()
check(SmartNavigation:GetCurrentButton() == nil, "NPC refresh does not restore automatic selection")
SmartNavigation:SelectButton(reader.options)
reader:SyncTarget()
check(SmartNavigation:GetCurrentButton() == reader.options, "NPC refresh preserves explicit navigation")
check(not reader.frame.CloseButton:IsShown(), "gamepad hides the X in favour of native Back")
reader.options.contextMenu = nil
reader.options:Fire("OnClick")
check(reader.options.contextMenu == nil and Addon.questReport.state == "waiting",
    "controller Options opens the report directly, without a tainting context menu")
Addon.questReport.frame:Hide()
check(npcManager.focusedFrame == reader.frame, "closing the report returns controller focus to the NPC reader")
controls.setGamepad(false)
Addon:UpdateQuestInteraction()
check(reader.frame.CloseButton:IsShown(), "mouse mode restores the X")
local originalRewards = QuestInfoRewardsFrame
local nativeRewards = CreateFrame("Frame", nil, QuestFrame)
nativeRewards.left, nativeRewards.top = 30, 550
nativeRewards:SetSize(278, 90)
local function RewardText(text, x, y)
    local region = nativeRewards:CreateFontString(nil, "ARTWORK")
    region:SetText(text)
    region.left, region.top = x, y
    region:SetSize(200, 18)
    function region:GetObjectType() return "FontString" end
    function region:GetJustifyV() return "TOP" end
    return region
end
nativeRewards.Header = RewardText("Native rewards", 30, 550)
nativeRewards.ItemReceiveText = RewardText("Native receive", 30, 525)
local xp = RewardText("40", 30, 500)
local previousExperience = EXPERIENCE_COLON
ClientApi.InstallGlobals("frFR", {"EXPERIENCE_COLON"})
local xpLabel = RewardText(EXPERIENCE_COLON, 30, 480)
local previousSpellHeader = REWARD_SPELL
ClientApi.InstallGlobals("frFR", {"REWARD_SPELL"})
local spellHeader = RewardText(REWARD_SPELL, 30, 460)
local spellReward = CreateFrame("Button", nil, nativeRewards)
spellReward.left, spellReward.top, spellReward.rewardSpellID = 30, 440, 688
spellReward:SetSize(150, 40)
spellReward.Name = RewardText("Invocation d'un diablotin", 70, 435)
function spellReward:GetRegions() return self.Name end
function spellReward:GetChildren() return end
function nativeRewards:GetRegions() return self.Header, self.ItemReceiveText, xp, xpLabel, spellHeader end
function nativeRewards:GetChildren() return spellReward end
QuestInfoRewardsFrame = nativeRewards
Addon:UpdateQuestInteraction()
local function FindRewardText(text, target)
    for _, region in ipairs({(target or reader).body.child:GetChildren()}) do
        if region:IsShown() and region:GetText() == text then return region end
    end
end
local spellName = ForeverRosettaStoneDB:GetSpellName(688, Addon:GetTargetLocale())
check(spellName and FindRewardText(spellName), "NPC spell rewards show the catalog spell name")
-- The English source fits on one line, while the French name exceeds the card.
local getSpellName = ForeverRosettaStoneDB.GetSpellName
ForeverRosettaStoneDB.GetSpellName = function() return "Invocation d'un diablotin" end
spellReward.Name:SetText("Summon Imp")
spellReward.NameFrame = spellReward:CreateTexture()
spellReward.NameFrame.left, spellReward.NameFrame.top = 65, 440
spellReward.NameFrame:SetSize(100, 40)
Addon:UpdateQuestInteraction()
local wrappedName = FindRewardText("Invocation d'un diablotin")
local rewardScale = nativeRewards:GetEffectiveScale() / reader.body.child:GetEffectiveScale()
check(wrappedName and wrappedName:CanWordWrap()
    and wrappedName:GetUnboundedStringWidth() > wrappedName:GetWidth()
    and wrappedName:GetWidth() <= (spellReward.NameFrame:GetRight() - spellReward.Name:GetLeft()) * rewardScale
    and wrappedName:GetHeight() <= spellReward.NameFrame:GetHeight() * rewardScale,
    "long translated names wrap inside the native reward card")
ForeverRosettaStoneDB.GetSpellName = getSpellName
spellReward.Name:SetText("Invocation d'un diablotin")
Addon:UpdateQuestInteraction()
check(FindRewardText(Addon:GetClientLabel("REWARD_SPELL", Addon:GetTargetLocale())),
    "spell reward headers translate by their GlobalString key")
local spellButton
for _, child in ipairs({reader.body.child:GetChildren()}) do
    if child.rewardSource == spellReward and child:IsShown() then spellButton = child end
end
check(spellButton ~= nil, "mirrored spell rewards get a hover target")
spellButton.left, spellButton.top = 40, 300 -- mock frames resolve only explicit screen rects
local spellSource, rewardTip = Addon.rewardSpellSource, Addon.rewardTooltips[1]
local previousCoverage = Addon.preferences.tooltipNameOnly.quest
Addon.preferences.tooltipNameOnly.quest = true
spellSource.SetSpellByID = function(tip, id)
    tip.processingInfo = { tooltipData = { type = Enum.TooltipDataType.Spell, id = id, lines = {} } }
    tip:Show()
end
local function RewardTitle()
    return rewardTip:IsShown() and rewardTip.TextLeft1 and rewardTip.TextLeft1:GetText()
end
spellButton:Fire("OnEnter")
check(rewardTip:GetAlpha() == 1 and spellSource:GetAlpha() == 0, "only the spell measurement source is transparent")
check(RewardTitle() == spellName and not GameTooltip:IsOwned(spellButton),
    "hovering a mirrored spell shows only the translated reward tooltip, like the journal")
spellButton:Fire("OnLeave")
check(not rewardTip:IsShown() and not spellSource:IsShown(), "leaving a mirrored spell hides its tooltip")
local previousActive, previousCurrent = SmartNavigation.activeFrame, SmartNavigation.currentButton
controls.setGamepad(true)
Addon:UpdateQuestInteraction()
SmartNavigation.activeFrame, SmartNavigation.currentButton = reader.frame, spellButton
Addon:UpdateRewardTooltips()
check(RewardTitle() == spellName, "gamepad focus on a mirrored spell shows its translated tooltip")
reader:SyncTarget()
local selectPrompt, backPrompt = reader.footer.prompts[1], reader.footer.prompts[2]
check(not selectPrompt.icon:IsShown() and not selectPrompt.text:IsShown() and backPrompt.icon:IsShown(),
    "read-only reward focus shows Back without Select")
SmartNavigation.currentButton = nil
reader:SyncTarget()
check(not selectPrompt.icon:IsShown(), "reading the quest does not advertise a Select action")
local _, _, _, anchorX, anchorY = rewardTip:GetPoint(1)
local tipScale = spellButton:GetEffectiveScale() / UIParent:GetEffectiveScale()
check(math.abs(anchorX - (spellButton:GetLeft() + spellButton:GetWidth()) * tipScale) < 0.01
    and math.abs(anchorY - spellButton:GetTop() * tipScale) < 0.01,
    "reward tooltips anchor like native ANCHOR_RIGHT, at the button's top-right corner")
SmartNavigation.currentButton = reader.options
reader:SyncTarget()
check(selectPrompt.icon:IsShown() and selectPrompt.text:IsShown(), "Options focus advertises Select")
Addon:UpdateRewardTooltips()
check(not rewardTip:IsShown(), "moving gamepad focus away hides the reward tooltip")
SmartNavigation.activeFrame, SmartNavigation.currentButton = previousActive, previousCurrent
controls.setGamepad(false)
Addon.preferences.tooltipNameOnly.quest = previousCoverage
check(FindRewardText(Addon:GetQuestLabel("rewards")), "NPC reward mirror translates its native header")
check(FindRewardText("40"), "NPC reward mirror preserves live XP")
check(FindRewardText(Addon:GetClientLabel("EXPERIENCE_COLON", Addon:GetTargetLocale())),
    "native reward labels translate by their GlobalString key")
check(not FindRewardText("Expérience :"), "translated reward labels replace the native wording")
xp:SetText("170")
Addon:UpdateQuestInteraction()
check(not FindRewardText("40") and FindRewardText("170"), "reward values refresh without stale XP")
check(nativeRewards.Header:GetText() == "Native rewards", "reward mirroring never overwrites native text")

local customReader = reader
local dialogue = { { text = "Translated turn-in dialogue", gap = 0 } }
customReader.body:SetSections({
    { text = "Translated gossip option", gap = 23, indent = 19, rowHeight = 20,
        icon = { atlas = "test-gossip-atlas", width = 16, height = 16, x = -2 } },
})
local _, _, _, rowTextX, rowTextY = customReader.body.sections[1]:GetPoint(1)
local _, _, _, rowIconX, rowIconY = customReader.body.rowIcons[1]:GetPoint(1)
check(rowTextY == rowIconY and rowTextY == -43 and rowTextX == 24 and rowIconX == 3,
    "gossip option text and icon share a center line after the native gap")
customReader:ShowSections(783, "reward", dialogue)
check(not customReader.body.rowIcons[1]:IsShown(), "reusing the body clears old gossip icons")
check(FindRewardText("170", customReader), "turn-in companion mirrors live XP")
local previousProgressChild, previousProgressScroll = QuestProgressScrollChildFrame, QuestProgressScrollFrame
local previousProgressTitle = QuestProgressTitleText
local previousRequiredItems = QuestProgressRequiredItemsText
local previousProgressText = QuestProgressText
local previousTurnInItems = TURN_IN_ITEMS
local previousQuestItemInfo = GetQuestItemInfo
ClientApi.InstallGlobals("frFR", { "TURN_IN_ITEMS" })
QuestProgressScrollChildFrame = CreateFrame("Frame", nil, QuestFrame)
QuestProgressScrollChildFrame.left, QuestProgressScrollChildFrame.top = 30, 550
QuestProgressScrollFrame = CreateFrame("Frame", nil, QuestFrame)
QuestProgressScrollFrame.top = 550
function QuestProgressScrollFrame:GetScrollChild() return QuestProgressScrollChildFrame end
QuestProgressTitleText = RewardText("Native progress title", 40, 540)
QuestProgressRequiredItemsText = RewardText(TURN_IN_ITEMS, 40, 460)
QuestProgressText = nativeRewards.ItemReceiveText
local requiredItem = CreateFrame("Button", nil, QuestProgressScrollChildFrame)
requiredItem.left, requiredItem.top = 37, 438
requiredItem:SetSize(150, 40)
requiredItem:SetID(1)
requiredItem.type, requiredItem.objectType = "required", "item"
requiredItem.Name = RewardText("Viande de loup coriace", 72, 436)
requiredItem.Count = RewardText("8", 60, 422)
function requiredItem:GetRegions() return self.Name, self.Count end
function requiredItem:GetChildren() return end
GetQuestItemInfo = function(kind, index)
    if kind == "required" and index == 1 then return nil, nil, 8, nil, nil, 750 end
    return previousQuestItemInfo(kind, index)
end
function QuestProgressScrollChildFrame:GetRegions() return QuestProgressRequiredItemsText, QuestProgressText end
function QuestProgressScrollChildFrame:GetChildren() return requiredItem end
customReader:ShowSections(783, "progress", dialogue)
local requiredHeader = FindRewardText(Addon:GetClientLabel("TURN_IN_ITEMS", Addon:GetTargetLocale()), customReader)
local progressScale = QuestProgressScrollChildFrame:GetEffectiveScale() / customReader.body.child:GetEffectiveScale()
check(requiredHeader and select(4, requiredHeader:GetPoint(1)) == select(4, customReader.body.sections[1]:GetPoint(1)),
    "required items header shares the text inset despite the extra inset of the native scroll child")
local requiredButton
for _, child in ipairs({customReader.body.child:GetChildren()}) do
    if child.rewardSource == requiredItem and child:IsShown() then requiredButton = child end
end
check(requiredButton and math.abs(select(4, requiredButton:GetPoint(1)) - (5 - 3 * progressScale)) < 0.01,
    "required item hover target keeps its native offset from the progress title")
local requiredName = ForeverRosettaStoneDB:GetItemName(750, Addon:GetTargetLocale())
check(requiredName and FindRewardText(requiredName, customReader) and FindRewardText("8", customReader),
    "progress companion translates the required item and copies its live count")
check(not FindRewardText("Native receive", customReader), "progress mirror omits the native dialogue")
customReader.frame:Hide()
QuestProgressScrollChildFrame, QuestProgressRequiredItemsText = previousProgressChild, previousRequiredItems
QuestProgressScrollFrame, QuestProgressTitleText = previousProgressScroll, previousProgressTitle
QuestProgressText, TURN_IN_ITEMS = previousProgressText, previousTurnInItems
GetQuestItemInfo = previousQuestItemInfo

QuestInfoRewardsFrame:Hide()
Addon:UpdateQuestInteraction()
check(not FindRewardText("170") and reader.body.spacerHeight == 0, "hidden native rewards clear the mirror")
QuestInfoRewardsFrame = originalRewards
EXPERIENCE_COLON = previousExperience
REWARD_SPELL = previousSpellHeader
-- Our first line starts where the native title starts, independent of native scrolling.
local previousScroll, previousTitle = QuestDetailScrollFrame, QuestInfoTitleHeader
QuestDetailScrollFrame = CreateFrame("Frame", nil, QuestFrame)
QuestDetailScrollFrame.left, QuestDetailScrollFrame.top = 25, 735
local scrollChild = CreateFrame("Frame", nil, QuestDetailScrollFrame)
scrollChild.left, scrollChild.top = 25, 755
function QuestDetailScrollFrame:GetScrollChild() return scrollChild end
QuestInfoTitleHeader = scrollChild:CreateFontString(nil, "ARTWORK")
QuestInfoTitleHeader.left, QuestInfoTitleHeader.top = 30, 745
Addon:UpdateQuestInteraction()
local _, _, _, bodyX, bodyY = reader.body.frame:GetPoint(1)
-- Native title: scroll top -65 from the window, title 10 below the scroll child top; our first
-- line sits 10 below the body top and 5 right of its left edge.
check(bodyX == 10 - 5 and bodyY == -65 - 10 + 10, "reader text starts at the native title position")
local _, barAnchor, _, _, barY = reader.body.frame.ScrollBar:GetPoint(1)
check(barAnchor ~= reader.body.frame and barY == 9,
    "without a native scroll bar ours keeps its parchment position instead of following the raised text")
QuestDetailScrollFrame.ScrollBar = CreateFrame("Frame", nil, QuestDetailScrollFrame)
QuestDetailScrollFrame.ScrollBar.left, QuestDetailScrollFrame.ScrollBar.top = 330, 732
QuestDetailScrollFrame.ScrollBar:SetSize(10, 400)
reader.body.frame.ScrollBar:ClearAllPoints()
Addon:UpdateQuestInteraction()
local _, nativeBarAnchor, _, nativeBarX, nativeBarY = reader.body.frame.ScrollBar:GetPoint(1)
check(nativeBarAnchor == reader.frame and nativeBarX == 310 and nativeBarY == -68,
    "our scroll bar sits exactly where the native one does")
QuestDetailScrollFrame, QuestInfoTitleHeader = previousScroll, previousTitle
QuestFrameDetailPanel:Hide()
QuestFrameGreetingPanel:Show()
Addon:UpdateQuestInteraction()
CheckNoNpcCompanion("returning from an open quest offer to the NPC greeting clears the companion")
QuestFrameGreetingPanel:Hide()
QuestFrameDetailPanel:Show()
Addon:UpdateQuestInteraction()
check(reader.frame:IsShown(), "selecting a quest from the native greeting opens its companion again")
GetQuestID = function() return 0 end
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "invalid native quest ID clears reader instead of reusing map selection")
GetQuestID = function() return 179 end
Addon:UpdateQuestInteraction()
QuestFrame.left = UIParent:GetWidth() - 338
Addon:UpdateQuestInteraction()
local rightPoint, rightAnchor, rightRelative = reader.frame:GetPoint(1)
check(rightPoint == "TOPRIGHT" and rightAnchor == QuestFrame and rightRelative == "TOPLEFT",
    "right-side NPC windows place the reader inward without moving native frames")
SettingsPanel:Show()
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "settings block NPC reader")
SettingsPanel:Hide()
Addon:UpdateQuestInteraction()
WorldMapFrame:Show()
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "map reader and NPC reader cannot overlap")
WorldMapFrame:Hide()
Addon.preferences.features.questPanel = false
Addon:UpdateQuestInteraction()
check(not reader.frame:IsShown(), "quest panel preference disables NPC reader without reload")

QuestFrame:Hide()
QuestFrame, QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel, QuestFrameGreetingPanel = nil, nil, nil, nil, nil
GossipFrame, C_GossipInfo, GetQuestID = old.GossipFrame, old.C_GossipInfo, old.GetQuestID
GetNumActiveQuests, GetNumAvailableQuests = oldActiveCount, oldAvailableCount
GetActiveQuestID, GetAvailableQuestInfo = oldActiveID, oldAvailableInfo
C_QuestLog.GetQuestObjectives = getObjectives
for name, value in pairs(original) do _G[name] = value end
Addon.preferences.features.questPanel = true
Addon:SendQuestInteraction({ type = "reset" })
WorldMapFrame:SetShown(mapShown)

return checks
