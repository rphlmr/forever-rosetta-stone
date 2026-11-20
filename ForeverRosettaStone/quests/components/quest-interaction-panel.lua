local _, Addon = ...

local autoOpenSettings = {
    detail = "questAutoOpen",
    gossip = "questGreetingAutoOpen",
    greeting = "questGreetingAutoOpen",
    progress = "questProgressAutoOpen",
    reward = "questRewardAutoOpen",
}

local profiles = Addon:CreateTooltipPlacementProfiles({
    name = "questInteraction",
    contexts = { gossip = {}, greeting = {}, detail = {}, progress = {}, reward = {} },
    mouse = { sideRules = { Addon.TooltipSideRules.screen } },
    gamepad = { sideRules = { Addon.TooltipSideRules.screen } },
})

local function ResolveGreeting(source, context)
    -- A greeting is its own screen, even when it lists exactly one quest.
    return source, 0, context
end

-- Quests listed by the NPC greeting, in native order: active first, then available.
local function GetGreetingQuests(context)
    local quests = {}
    local function Add(questID, title, active)
        quests[#quests + 1] = { questID = questID, title = title, active = active }
    end
    if context == "gossip" then
        for _, info in ipairs(C_GossipInfo.GetActiveQuests()) do Add(info.questID, info.title, true) end
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests()) do Add(info.questID, info.title, false) end
    elseif context == "greeting" then
        for index = 1, GetNumActiveQuests() do Add(GetActiveQuestID(index), GetActiveTitle(index), true) end
        for index = 1, GetNumAvailableQuests() do
            Add(select(5, GetAvailableQuestInfo(index)), GetAvailableTitle(index), false)
        end
    end
    return quests
end

function Addon:GetQuestInteractionSections(id, quest)
    local sections = {}
    local function Add(source, text, gap)
        if text and text ~= "" then
            sections[#sections + 1] = { source = source or QuestInfoDescriptionText, text = text, gap = gap or 5 }
        end
    end
    -- Native client text belongs to the quest the NPC frame is showing, never to another ID.
    local active = GetQuestID and GetQuestID() == id
    local function Format(field, native)
        return quest and self:FormatQuestText(quest[field], id) or active and native and native() or nil
    end
    Add(QuestInfoTitleHeader, Format("title", GetTitleText), 0)
    Add(QuestInfoDescriptionText, Format("description", GetQuestText))
    Add(QuestInfoObjectivesHeader, self:GetClientLabel("QUEST_OBJECTIVES", self:GetTargetLocale()) or QUEST_OBJECTIVES, 20)
    Add(QuestInfoObjectivesText, Format("summary", GetObjectiveText))
    return sections
end

-- The parchment texture drawn by the visible native screen.
function Addon:GetQuestInteractionBackground(source)
    if source and source == GossipFrame then return source.Background end
    for _, panel in ipairs({ QuestFrameDetailPanel, QuestFrameProgressPanel, QuestFrameRewardPanel,
        QuestFrameGreetingPanel }) do
        if panel and panel:IsVisible() then return panel.Bg end
    end
end

-- The built-in catalog supplies quest offers. Other screens require a content provider
-- that can match the native dialogue.
function Addon:HasQuestInteractionTranslation(id, quest, context)
    if context ~= "detail" or not quest then return false end
    for _, field in ipairs({ "title", "description", "summary" }) do
        if self:FormatQuestText(quest[field], id) then return true end
    end
    return false
end

function Addon:ResolveQuestInteraction()
    if QuestFrame and QuestFrame:IsVisible() then
        for _, screen in ipairs({
            { frame = QuestFrameDetailPanel, context = "detail" },
            { frame = QuestFrameProgressPanel, context = "progress" },
            { frame = QuestFrameRewardPanel, context = "reward" },
        }) do
            if screen.frame and screen.frame:IsVisible() then return QuestFrame, GetQuestID(), screen.context end
        end

        if QuestFrameGreetingPanel and QuestFrameGreetingPanel:IsVisible() then
            return ResolveGreeting(QuestFrame, "greeting")
        end
    end

    if GossipFrame and GossipFrame:IsVisible() then return ResolveGreeting(GossipFrame, "gossip") end
end

function Addon:SendQuestInteraction(event)
    self.questInteractionState = self:TransitionQuestInteraction(self.questInteractionState or { mode = "hidden" }, event)

    if self.questInteractionState.mode ~= "visible" and self.questInteractionReader then
        self.questInteractionReader.frame:Hide()
        self.questInteractionReader:ReleaseController()
        self.questInteractionReader.contentKey = nil
    end
end

-- Native reading windows drive the controller through their own bindings, so a bookmark is its
-- own controller frame: the right trigger reaches it, and Select opens the reader with focus.
-- onOpen(focus) runs when the bookmark is clicked; focus is true when it was reached by controller.
function Addon:CreateInteractionBookmark(name, onOpen)
    local host = self:NewFrame("Frame", name .. "Host", UIParent)
    local bookmark
    bookmark = self:CreateQuestBookmark(host, name, function() onOpen(bookmark.registered == true) end)
    bookmark.host = host
    bookmark:SetPoint("TOPLEFT", host, "TOPLEFT")
    bookmark.usesGamepadFocus = true
    local prompt = self:NewFrame("Frame", nil, bookmark, "InputIconTextureFrameTemplate")
    bookmark.gamepadPrompt = prompt
    prompt:SetSize(20, 20)
    prompt:SetPoint("TOP", bookmark.Icon, "BOTTOM", 0, -13)
    prompt:SetInputKey("PADRTRIGGER")
    prompt:Hide()

    function bookmark:ReleaseController()
        if not self.registered then return end
        self:SetGamepadFocus(false)
        prompt:Hide()
        if InCombatLockdown() then return end
        self.registered = nil
        GamepadMode.FrameControlsManager:FrameHidden(host)
        SmartNavigation:RemovePanelInfo(host)
    end
    function bookmark:SyncController()
        if not InputUtil.IsGamepadUIEnabled() or not self:IsVisible() then
            self:ReleaseController()
        elseif not self.registered and not InCombatLockdown() then
            self.registered = true
            self:SetGamepadFocus(false)
            GamepadMode.FrameControlsManager:FrameShown(host, false, false)
        end
    end
    -- Attach beside a native window, above it, at a fixed offset from its top-right corner.
    function bookmark:Attach(source, offsetY)
        host:SetParent(source)
        host:SetScale(1)
        host:SetFrameStrata(source:GetFrameStrata())
        host:SetFrameLevel(source:GetFrameLevel() + 30)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", source, "TOPRIGHT", -2, offsetY)
        host:SetSize(self:GetSize())
    end
    host.FocusGamepad = self:Wrap("focus bookmark " .. name, function()
        if bookmark.registered and not InCombatLockdown() then
            SmartNavigation:SetTargetButtonForFrame(host, bookmark)
            bookmark:SetGamepadFocus(true)
        end
    end)
    host.UnfocusGamepad = self:Wrap("leave bookmark " .. name, function()
        bookmark:SetGamepadFocus(false)
    end)
    host.SmartNavigationCloseHandler = self:Wrap("close bookmark " .. name, function()
        if not bookmark.registered or InCombatLockdown() or SmartNavigation:GetActiveFrame() ~= host
            or SmartNavigation:GetCurrentButton() ~= bookmark then return false end
        local source = host:GetParent()
        if not source or not source:IsVisible() then return false end
        HideUIPanel(source)
        if source:IsVisible() then return false end
        bookmark:Hide()
        return true
    end, false)
    self:HookScript(bookmark, "OnHide", function() bookmark:ReleaseController() end)
    return bookmark
end

function Addon:GetQuestInteractionBookmark()
    if self.questInteractionBookmark then return self.questInteractionBookmark end
    self.questInteractionBookmark = self:CreateInteractionBookmark("ForeverRosettaStoneInteractionBookmark", function(focus)
        self.questInteractionState.mode = "visible"
        self:UpdateQuestInteraction()
        local reader = self.questInteractionReader
        if focus and reader then
            reader:ReleaseController()
            reader:SyncController(true)
        end
    end)
    return self.questInteractionBookmark
end

function Addon:UpdateQuestInteraction()
    local source, id, context

    if self:IsFeatureEnabled("questPanel") and not self:IsTooltipBlocked()
        and not SettingsPanel:IsShown() and not WorldMapFrame:IsShown() then
        source, id, context = self:ResolveQuestInteraction()
    end

    local quest = self:IsReadableEntityID(id) and self:GetQuest(id)
    if source and id == 0 then
        for _, entry in ipairs(GetGreetingQuests(context)) do
            if self:IsReadableEntityID(entry.questID) then
                self:RecordDebugSurface(source, "questInteraction", entry.questID, context, nil, self:GetQuest(entry.questID))
            end
        end
    elseif source and id then
        self:RecordDebugSurface(source, "questInteraction", id, context, nil, quest)
    end

    local sections, dialogueKey, missing
    local hasCatalogText = source and self:HasQuestInteractionTranslation(id, quest, context)
    if source then
        sections, dialogueKey, missing = self:GetCatalogDialogueSections(id, context)
        if (not sections or missing) and self.questInteractionContentProvider
            and not (hasCatalogText and self:FormatQuestText(quest.description, id)) then
            local provided, key = self.questInteractionContentProvider(source, id, context)
            if provided then sections, dialogueKey, missing = provided, key, nil end
        end
    end
    if not sections and hasCatalogText then
        sections = self:GetQuestInteractionSections(id, quest)
    end
    if not sections and source and self:IsReadableEntityID(id) then
        sections = { { source = QuestInfoDescriptionText, text = self:GetMissingTranslationMessage("quest"), gap = 0 } }
        missing = true
    end

    if not sections then
        self:SendQuestInteraction({ type = "reset" })
        if self.questInteractionBookmark then self.questInteractionBookmark:Hide() end
        return
    end

    self:SendQuestInteraction({ type = "present", source = source, questID = id, context = context,
        dialogueKey = dialogueKey, autoOpen = self:IsFeatureEnabled(autoOpenSettings[context]) })

    local bookmark = self:GetQuestInteractionBookmark()
    bookmark:Attach(source, -76)
    bookmark:SetShown(self.questInteractionState.mode == "dismissed")
    bookmark:SyncController()
    if self.questInteractionState.mode ~= "visible" then return end

    if not self.questInteractionReader then self.questInteractionReader = self:CreateQuestInteractionReader() end

    local policy = profiles[context][self:GetTooltipInputMode()]
    self.questInteractionReader:Layout(source, policy, self:GetQuestInteractionBackground(source))
    if self.questOfferTooltip and self.questOfferTooltip:IsShown() then self.questOfferTooltip:Hide() end
    if self.gossipOptionTooltip and self.gossipOptionTooltip:IsShown() then self.gossipOptionTooltip:Hide() end
    self.questInteractionReader:ShowSections(id, context, sections, dialogueKey, missing)
end

Addon:RegisterNameTooltipComponent({
    kind = "questInteraction",
    defaultContext = "gossip",
    placementProfiles = profiles,
    supportsFullText = true,
    GetName = function(id, locale)
        local quest = ForeverRosettaStoneDB:GetQuest(id, locale)
        return quest and quest.title
    end,
    GetPlacementContext = function() return Addon.questInteractionState and Addon.questInteractionState.context or "gossip" end,
    Update = function() Addon:UpdateQuestInteraction() end,
    Hide = function() Addon:SendQuestInteraction({ type = "reset" }) end,
})
