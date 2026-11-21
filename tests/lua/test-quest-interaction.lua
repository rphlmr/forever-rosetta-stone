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
    local source = Addon:GetTargetLocale() == "frFR" and "deDE" or "frFR"
    GetLocale = function() return source end
    UnitSex = function() return 3 end
    db.GetQuestDialogue = function(_, questID, _, language)
        if questID ~= 179 then return end
        return {
            { key = "female", npcID = 197, stage = "progress", playerSex = 3,
                text = language == source and "Texte natif" or "Translated progress" },
            { key = "male", npcID = 197, stage = "progress", playerSex = 2,
                text = language == source and "Texte natif" or "Other variant" },
        }
    end
    check(Addon:MatchQuestDialogue(197, 179, "progress", " Texte natif ") == "Translated progress",
        "catalog dialogue matches the client text and character variant")
    check(not Addon:MatchQuestDialogue(198, 179, "progress", "Texte natif")
        and not Addon:MatchQuestDialogue(197, 179, "complete", "Texte natif")
        and not Addon:MatchQuestDialogue(197, 179, "progress", "Un autre texte"),
        "catalog dialogue refuses unmatched NPC, phase and wording")
    db.GetQuestDialogue, UnitSex, GetLocale = lookup, unitSex, locale
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
    GetLocale, Addon.GetTargetLocale, UnitSex = oldLocale, oldTarget, oldSex
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
    GetLocale, Addon.GetTargetLocale, UnitGUID = getLocale, getTargetLocale, getUnitGUID
    UnitSex = getUnitSex
    C_GossipInfo.GetText, C_GossipInfo.GetOptions, C_GossipInfo.GetActiveQuests = getText, getOptions, getActiveQuests
end
check(Addon:TransitionQuestInteraction(hidden, { type = "dismiss" }) == hidden, "hidden refuses dismissal")
check(Addon:TransitionQuestInteraction(hidden, { type = "present", questID = 179, context = "gossip" }) == hidden,
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
-- NPC greeting prose and gossip options have no owned translation source, and a translated quest
-- title alone does not justify a companion: greetings show neither the reader nor its bookmark.
Addon:UpdateQuestInteraction()
check(not (Addon.questInteractionReader and Addon.questInteractionReader.frame:IsShown()),
    "gossip greeting never opens the reader")
check(not (Addon.questInteractionBookmark and Addon.questInteractionBookmark:IsShown()),
    "gossip greeting shows no FRS bookmark")
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
        local partial, _, missing = Addon:GetCatalogDialogueSections(0, "gossip")
        check(missing and partial and partial[2].text == ForeverRosettaStoneDB:GetGossipOptionName(auction.gossipOptionID, locale),
            "known menu options remain available for an NPC without a catalog greeting")
        local reset = { gossipOptionID = 97311, icon = 132053, name = "Je voudrais oublier mes talents d’héritage ou de classe." }
        local directions = { gossipOptionID = 99999999, icon = 132053, name = "Maître de Classe" }
        GossipFrame.gossipOptions = { reset, directions }
        local shared = Addon:GetCatalogDialogueSections(0, "gossip")
        check(shared and shared[2].text == "I wish to unlearn my class or legacy talents."
            and shared[3].text == "Class Trainer",
            "the NPC reader uses shared options even without a known NPC or option ID")
        check(Addon:GetGossipOptionTranslation(reset, locale) == shared[2].text,
            "Joshua's reset option uses the same lookup as the gossip tooltip")
        GossipFrame.gossipOptions = { auction, bank, trainer, unknown }
        local savedLocale = Addon.preferences.locale
        Addon.preferences.locale = "frFR"
        GetLocale = function() return "enUS" end
        UnitGUID = function(unit) if unit == "npc" then return "Creature-0-6867-0-2-5595-EA631DAB78" end end
        C_GossipInfo.GetText = function() return "What do ye need directions to?" end
        local guard = Addon:GetCatalogDialogueSections(0, "gossip")
        check(guard and guard[1].text == "Où voulez-vous aller ?",
            "the Ironforge guard's Forever greeting wins over the identical shared source text")
        Addon.preferences.locale = savedLocale
        GetLocale = function() return "frFR" end
        UnitGUID = function(unit) if unit == "npc" then return "Creature-0-1-0-4-274781-ABCD" end end
        C_GossipInfo.GetText = function() return "Native greeting without a matching translation" end
        Addon.preferences.features.questAutoOpen = true
        Addon:UpdateQuestInteraction()
        local reader = Addon.questInteractionReader
        check(reader.frame:IsShown() and reader.options:GetText() == "Options"
            and reader.body.lastSections[1].text == Addon:GetMissingTranslationMessage("gossip"),
            "an owned NPC with a missing greeting offers the fallback and Options")
        reader.options:Fire("OnClick")
        reader.options.contextMenu.entries[2].onClick()
        local dialog = Addon.questReport
        check(dialog.state == "ready" and dialog.record.gossip.options[2].gossipOptionID == bank.gossipOptionID
            and dialog.record.gossip.text == C_GossipInfo.GetText(),
            "the dialogue report includes the original text and option IDs")
        dialog.frame:Hide()
        Addon:SendQuestInteraction({ type = "reset" })
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
    Addon.questInteractionContentProvider = function(source, id, context)
        if source == GossipFrame and id == 0 and context == "gossip" then
            return { { text = "Translated greeting", gap = 0 } }, "first-greeting"
        end
    end
    Addon.preferences.features.questAutoOpen = true
    local savedOptions = C_GossipInfo.GetOptions
    local flight = { gossipOptionID = 97329, orderIndex = 0, name = "Je dois voyager.", icon = 132057 }
    C_GossipInfo.GetOptions = function() return { flight } end
    local option = CreateFrame("Button", nil, nativeViewport)
    option:SetText(flight.name)
    option.left, option.top = 30, 690
    option:SetSize(278, 20)
    function option:GetElementData() return { info = flight } end
    local quest = CreateFrame("Button", nil, nativeViewport)
    quest.questID = 179
    quest.left, quest.top = 30, 665
    quest:SetSize(278, 20)
    controls.setMouseFoci({ option, quest })
    Addon:UpdateGossipOptionTooltip()
    Addon:UpdateQuestOfferTooltip()
    local optionTip, offerTip = Addon.gossipOptionTooltip, Addon.questOfferTooltip
    check(optionTip:IsShown() and offerTip:IsShown(),
        "both focused native rows offer tooltips while the translation reader is closed")
    local optionShow, offerShow = optionTip.Show, offerTip.Show
    local shows = 0
    optionTip.Show = function(self) shows = shows + 1; optionShow(self) end
    offerTip.Show = function(self) shows = shows + 1; offerShow(self) end
    Addon:UpdateTooltipComponents()
    check(shows == 0 and not optionTip:IsShown() and not offerTip:IsShown(),
        "automatic reader opening hides both native row tooltips without showing either again")
    optionTip.Show, offerTip.Show = optionShow, offerShow

    local gossipReader = Addon.questInteractionReader
    local gossipBookmark = Addon.questInteractionBookmark
    check(gossipReader.frame:IsShown() and gossipReader.options:IsShown(),
        "a translated greeting offers the same Options button as the missing greeting")
    local _, _, _, barX, barY = gossipReader.body.frame.ScrollBar:GetPoint(1)
    check(barX == 314 and barY == -68, "the shared reader keeps the gossip scrollbar alignment")
    gossipReader.frame.CloseButton:Fire("OnClick")
    check(not gossipReader.frame:IsShown() and GossipFrame:IsShown() and gossipBookmark:IsShown(),
        "the gossip close button collapses to the shared bookmark")
    Addon:UpdateTooltipComponents()
    check(gossipBookmark:IsShown() and not gossipReader.frame:IsShown(), "refresh preserves gossip dismissal")
    check(optionTip:IsShown() and offerTip:IsShown(), "native row tooltips return when the reader is closed")
    gossipBookmark:Fire("OnClick")
    check(gossipReader.frame:IsShown() and not optionTip:IsShown() and not offerTip:IsShown(),
        "opening the bookmark immediately hides both native row tooltips")
    gossipReader.frame.CloseButton:Fire("OnClick")
    C_GossipInfo.GetOptions = savedOptions
    controls.setMouseFoci({})
    controls.setGamepad(true)
    Addon:UpdateQuestInteraction()
    local manager = GamepadMode.FrameControlsManager
    manager:FrameHidden(gossipBookmark.host)
    manager:FrameShown(gossipBookmark.host, false, true)
    gossipBookmark:Fire("OnClick")
    check(gossipReader.frame:IsShown() and manager.focusedFrame == gossipReader.frame,
        "reopening a greeting hands focus to the shared reader")
    gossipReader.options.contextMenu = nil
    gossipReader.options:Fire("OnClick")
    check(not gossipReader.options.contextMenu and Addon.questReport.state == "ready",
        "controller Options opens the dialogue report directly")
    Addon.questReport.frame:Hide()
    check(manager.focusedFrame == gossipReader.frame, "the dialogue report returns controller focus to the reader")
    check(gossipReader.frame.SmartNavigationCloseHandler() and gossipBookmark:IsShown() and GossipFrame:IsShown(),
        "Back on the greeting reader returns to its bookmark")
    controls.setGamepad(false)
    Addon.preferences.features.questGreetingAutoOpen = false
    Addon:SendQuestInteraction({ type = "reset" })
    Addon:UpdateQuestInteraction()
    check(not gossipReader.frame:IsShown() and gossipBookmark:IsShown(),
        "the greeting checkbox independently leaves the starting dialogue on its bookmark")
    Addon.preferences.features.questGreetingAutoOpen = true
    Addon.preferences.features.questAutoOpen = false
    Addon.questInteractionContentProvider = nil
end
GossipFrame:Hide()
QuestFrame:Show()
QuestFrameDetailPanel:Hide(); QuestFrameProgressPanel:Hide(); QuestFrameRewardPanel:Hide()
QuestFrameGreetingPanel:Show()
GetNumActiveQuests = function() return 1 end
GetNumAvailableQuests = function() return 0 end
GetActiveQuestID = function() return 179 end
Addon:UpdateQuestInteraction()
check(not (Addon.questInteractionReader and Addon.questInteractionReader.frame:IsShown())
    and not (Addon.questInteractionBookmark and Addon.questInteractionBookmark:IsShown()),
    "legacy quest greeting never opens the reader or bookmark")
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
    GetLocale = function() return source end
    UnitSex = function() return 2 end
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-0-0-0-197-1" or nil end
    GetQuestText = function() return "Native offer variant" end
    database.GetQuestDialogue = function(_, questID, _, language)
        if questID == 179 then
            return { { key = "offer", npcID = 197, stage = "accept",
                text = language == source and "Native offer variant" or "Translated offer variant" } }
        end
    end
    Addon:UpdateQuestInteraction()
    check(reader.body.lastSections[2].text == "Translated offer variant",
        "matching NPC offer takes precedence over the generic quest description")
    GetQuestText = function() return "A different offer" end
    Addon:UpdateQuestInteraction()
    check(reader.body.lastSections[2].text:find("What do we have here", 1, true),
        "an unmatched offer keeps the translated quest description")
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
local previousProgressChild = QuestProgressScrollChildFrame
local previousRequiredItems = QuestProgressRequiredItemsText
local previousProgressText = QuestProgressText
local previousTurnInItems = TURN_IN_ITEMS
local previousQuestItemInfo = GetQuestItemInfo
ClientApi.InstallGlobals("frFR", { "TURN_IN_ITEMS" })
QuestProgressScrollChildFrame = CreateFrame("Frame", nil, QuestFrame)
QuestProgressScrollChildFrame.left, QuestProgressScrollChildFrame.top = 30, 550
QuestProgressRequiredItemsText = RewardText(TURN_IN_ITEMS, 30, 460)
QuestProgressText = nativeRewards.ItemReceiveText
local requiredItem = CreateFrame("Button", nil, QuestProgressScrollChildFrame)
requiredItem.left, requiredItem.top = 30, 438
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
check(FindRewardText(Addon:GetClientLabel("TURN_IN_ITEMS", Addon:GetTargetLocale()), customReader),
    "progress companion mirrors the translated requirements header")
local requiredName = ForeverRosettaStoneDB:GetItemName(750, Addon:GetTargetLocale())
check(requiredName and FindRewardText(requiredName, customReader) and FindRewardText("8", customReader),
    "progress companion translates the required item and copies its live count")
check(not FindRewardText("Native receive", customReader), "progress mirror omits the native dialogue")
customReader.frame:Hide()
QuestProgressScrollChildFrame, QuestProgressRequiredItemsText = previousProgressChild, previousRequiredItems
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
