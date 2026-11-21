local _, Addon = ...

-- Release highlights: use a setting ID for a checkbox, or "listID.choiceValue" for a radio.
-- Remove the entry when the option should no longer be advertised as new.
local newSettings = {
    ["tooltipPresentation.above"] = true,
    ["tooltipPresentation.replacement"] = true,
}

Addon.features = {
    { id = "taxiNodeTooltip", name = "Flight map destinations", group = "Locations",
        description = "Shows the destination name and “You are here” at the current flight point." },
    { id = "recipeTrackerTooltip", name = "Tracked recipes", group = "Professions",
        description = "Show translated recipe names and live reagent counts when hovering tracked recipes in any profession." },
    { id = "recipeListTooltip", name = "Recipe list", group = "Professions",
        description = "Show translated recipe names when hovering the recipe list in any profession." },
    { id = "recipeCategoryTooltip", name = "Recipe sections", group = "Professions",
        description = "Show translated section names when hovering profession recipe categories." },
    { id = "questPanel", name = "Quest panel", group = "Quests",
        description = "Show translated quest text beside map details and NPC quest windows. Map details include a bookmark and controller navigation." },
    { id = "questAutoOpen", name = "Auto-open quest details and offers", group = "Quests",
        description = "Automatically open the translation for map quest details and NPC quest offers. When off, use the bookmark." },
    { id = "questGreetingAutoOpen", name = "Auto-open NPC greetings", group = "Quests", defaultFrom = "questAutoOpen",
        description = "Automatically open the translated dialogue when you talk to an NPC. When off, use the bookmark." },
    { id = "questProgressAutoOpen", name = "Auto-open quest progress dialogue", group = "Quests", defaultFrom = "questAutoOpen",
        description = "Automatically open the translation when an NPC asks about an active quest. When off, use the bookmark." },
    { id = "questRewardAutoOpen", name = "Auto-open quest turn-in dialogue", group = "Quests", defaultFrom = "questAutoOpen",
        description = "Automatically open the translation on the quest turn-in screen. When off, use the bookmark." },
    { id = "questTooltip", name = "Quest-list tooltips", group = "Quests",
        description = "Show quest-list and chat-link translations using the selected tooltip display." },
    { id = "mapQuestTooltip", name = "Map quest tooltips", group = "Quests",
        description = "Show the translated quest title and live objectives beside quest markers on the World Map." },
    { id = "rewardComparison", name = "Reward comparisons", group = "Quests",
        description = "Compare reward items using translated names. English also has binding and equipment labels. Requires the Quest panel to be enabled." },
    { id = "itemTooltip", name = "Item tooltips", group = "Items",
        description = "Show translated item tooltips on the same side of the hovered item as the original, including comparisons." },
    { id = "spellTooltip", name = "Spell tooltips", group = "Spells",
        description = "Show translated spell tooltips on the same side of the hovered spell as the original, using live game values." },
    { id = "auraTooltip", name = "Buffs and debuffs", group = "Spells", defaultFrom = "spellTooltip",
        description = "Translate active buffs and debuffs, including effect details and remaining time when available." },
    { id = "talentTooltip", name = "Talent tooltips", group = "Talents",
        description = "Show translated talent names and descriptions on the same side of the hovered talent as the original." },
    { id = "npcTooltip", name = "NPC tooltips", group = "NPCs",
        description = "Show translated creature names stacked or in a separate tooltip at your chosen position. Player and custom pet names stay native." },
    { id = "playerTooltip", name = "Player tooltips", group = "Character",
        description = "Translate player class, race, and level. Player names and unavailable translations stay native." },
    { id = "gossipOptionTooltip", name = "NPC dialogue options", group = "NPCs",
        description = "Show translated dialogue options when hovering or focusing an NPC menu entry with a known option ID." },
    { id = "questTrackerTooltip", name = "Quest tracker", group = "Quests",
        description = "Show a translated quest summary and live progress on the inward side of the hovered or focused tracker quest." },
    { id = "questOfferTooltip", name = "NPC quest offers", group = "Quests",
        description = "Show a translated quest title beside hovered or focused quests in an NPC's quest list." },
    { id = "minimapQuestTooltip", name = "Minimap quests", group = "Quests",
        description = "Show a translated title beside minimap quest markers with a known ID or unique catalog title." },
    { id = "minimapLocationTooltip", name = "Minimap location", group = "Locations",
        description = "Show translated zone and subzone names using the selected tooltip display." },
    { id = "mountTooltip", name = "Mount tooltips", group = "Collections",
        description = "Show translated mount names and summon tooltips using their native spell IDs." },
    { id = "petTooltip", name = "Companion pet tooltips", group = "Collections",
        description = "Show translated species names where the native pet's creature ID exists in the NPC catalog." },
    { id = "appearanceTooltip", name = "Appearance tooltips", group = "Collections",
        description = "Translate appearance names and shared tooltip labels using the displayed source item's ID." },
    { id = "appearanceSlotTooltip", name = "Appearance categories", group = "Collections",
        description = "Show translated equipment category names, such as Chest and Shoulders, when hovering appearance category buttons." },
    { id = "activityTooltip", name = "Group finder activities", group = "Locations",
        description = "Show translated dungeon, battleground and zone names when hovering or focusing group finder activities." },
    { id = "locationTooltip", name = "Quest location headers", group = "Locations",
        description = "Show translated location names when you hover or focus a location header in the quest list." },
    { id = "mapLocationLabel", name = "Map hover names", group = "Locations",
        description = "Show a translated name beneath the native location name when exploring the World Map." },
    { id = "mapDropdown", name = "Map dropdown names", group = "Locations",
        description = "Show translated names beside hovered or controller-focused places in map navigation dropdowns." },
    { id = "trackingMenu", name = "Minimap tracking options", group = "Locations",
        description = "Show translated tracking options on hover or controller focus. Service labels support English; tracking spells use the selected language." },
    { id = "mapContext", name = "Viewed map location", group = "Locations",
        description = "Identify the map you are viewing with a location path above the map's place name." },
    { id = "playerLocation", name = "Character location", group = "Locations",
        description = "Append the translated location name in white when the native character-coordinate line names your location." },
    { id = "bookPanel", name = "Book panel", group = "Books",
        description = "Show the translated book title and page beside the native reading window, with a bookmark and controller navigation." },
    { id = "bookAutoOpen", name = "Open book translation automatically", group = "Books",
        description = "Open the book translation as soon as a book or readable object opens. When off, use the bookmark to open it." },
    { id = "bookTooltip", name = "Book tooltips", group = "Books",
        description = "Show the translated book title when hovering a readable object in the world." },
    { id = "characterStatTooltip", name = "Character stat tooltips", group = "Character",
        description = "Translate character stats and resistances with the client's live values, using the selected tooltip display." },
}

local featureByID = {}
for _, feature in ipairs(Addon.features) do featureByID[feature.id] = feature end
local npcTooltipPositions = { top = true, left = true, right = true, bottom = true }
local tooltipModes = { stacked = true, separate = true }
local tooltipNameOptions = {
    item = true, spell = true, aura = true, talent = true, mount = true, pet = true,
    appearance = true, npc = true, quest = true, mapQuest = true, questTracker = true, recipeTracker = true, characterStat = true,
}
for kind in pairs(tooltipNameOptions) do newSettings[kind .. "Tooltip.name"] = true end

function Addon:LoadPreferences()
    if type(ForeverRosettaStoneSettings) ~= "table" then ForeverRosettaStoneSettings = {} end
    if type(ForeverRosettaStoneSettings.features) ~= "table" then ForeverRosettaStoneSettings.features = {} end

    self.preferences = ForeverRosettaStoneSettings
    self:LoadErrorLog()
    local angle = self.preferences.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = 135 end
    self.preferences.minimapAngle = angle % 360
    if not tooltipModes[self.preferences.tooltipMode] then self.preferences.tooltipMode = "stacked" end
    if type(self.preferences.translationOnly) ~= "boolean" then self.preferences.translationOnly = false end
    if type(self.preferences.stackedTranslationFirst) ~= "boolean" then self.preferences.stackedTranslationFirst = false end
    local legacyNameOnly = self.preferences.tooltipCoverage == "name"
    local names = self.preferences.tooltipNameOnly
    if type(names) ~= "table" then
        names = {}
        self.preferences.tooltipNameOnly = names
    end
    names.taxiNode = nil
    local questNameOnly = names.quest
    if type(questNameOnly) ~= "boolean" then questNameOnly = legacyNameOnly end
    for _, kind in ipairs({ "mapQuest", "questTracker" }) do
        if type(names[kind]) ~= "boolean" then names[kind] = questNameOnly end
    end
    for kind in pairs(tooltipNameOptions) do
        if type(names[kind]) ~= "boolean" then
            names[kind] = legacyNameOnly and kind ~= "characterStat"
        end
    end
    -- Player names are never translated. The legacy setting hid the entire player companion.
    if legacyNameOnly then self.preferences.features.playerTooltip = false end
    self.preferences.tooltipCoverage = nil
    if type(self.preferences.translationHeader) ~= "boolean" then self.preferences.translationHeader = true end
    if not npcTooltipPositions[self.preferences.npcTooltipPosition] then self.preferences.npcTooltipPosition = "top" end

    if not ForeverRosettaStoneDB:GetLocales()[self.preferences.locale] then self.preferences.locale = "enUS" end
    ForeverRosettaStoneDB:LoadLocale(self.preferences.locale)

    for _, feature in ipairs(self.features) do
        if type(self.preferences.features[feature.id]) ~= "boolean" then
            self.preferences.features[feature.id] = not feature.defaultFrom or self.preferences.features[feature.defaultFrom]
        end
    end
end

function Addon:GetTargetLocale()
    return self.preferences.locale
end

function Addon:GetLanguageName()
    return ForeverRosettaStoneDB:GetLocales()[self:GetTargetLocale()]
end

function Addon:SetTargetLocale(locale)
    assert(ForeverRosettaStoneDB:GetLocales()[locale], "Unknown Forever Rosetta Stone language: " .. tostring(locale))
    ForeverRosettaStoneDB:LoadLocale(locale)
    if self.benchmark and self.benchmark.state == "recording" and locale ~= "enUS" then
        self:StopBenchmark("translation language changed")
    end
    self.preferences.locale = locale
    self.contentKey, self.tooltipKey = nil, nil
    self:RefreshSettingsUI()

    if self.lifecycle == "ready" then
        self:Run("change translation language", function() self:RefreshFeatures() end)
    end
end

function Addon:IsFeatureEnabled(id)
    return self.preferences.features[id]
end

function Addon:SetTooltipPresentation(mode)
    assert(mode == "above" or mode == "below" or mode == "separate" or mode == "replacement",
        "Unknown tooltip presentation: " .. tostring(mode))
    self.preferences.translationOnly = mode == "replacement"
    if mode ~= "replacement" then
        self.preferences.tooltipMode = mode == "separate" and "separate" or "stacked"
        if mode ~= "separate" then self.preferences.stackedTranslationFirst = mode == "above" end
    end
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then self:Run("change tooltip presentation", self.RefreshFeatures, self) end
end

function Addon:SetTooltipMode(mode)
    assert(tooltipModes[mode], "Unknown tooltip mode: " .. tostring(mode))
    self.preferences.tooltipMode = mode
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("change tooltip mode", function()
            self:RefreshFeatures()
        end)
    end
end

function Addon:SetNpcTooltipPosition(position)
    assert(npcTooltipPositions[position], "Unknown NPC tooltip position: " .. tostring(position))
    self.preferences.npcTooltipPosition = position
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("change NPC tooltip position", function() self:RefreshNameTooltips() end)
    end
end

function Addon:SetStackedTranslationFirst(enabled)
    assert(type(enabled) == "boolean", "Stacked translation order setting must be boolean")
    self.preferences.stackedTranslationFirst = enabled
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("change stacked tooltip order", function() self:RefreshFeatures() end)
    end
end

function Addon:SetTranslationOnly(enabled)
    assert(type(enabled) == "boolean", "Translation-only setting must be boolean")
    self.preferences.translationOnly = enabled
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("change translation-only display", function() self:RefreshFeatures() end)
    end
end

function Addon:GetTooltipCategory(kind, data)
    local auraType = kind == "spell" and Enum.TooltipDataType.UnitAura
    if auraType and canaccessallvalues(data) and type(data) == "table"
        and canaccessallvalues(data.type) and data.type == auraType then
        return "aura"
    end
    return kind
end

function Addon:GetTooltipCoverage(kind, data)
    return self.preferences.tooltipNameOnly[self:GetTooltipCategory(kind, data)] and "name" or "full"
end

function Addon:SetTooltipNameOnly(kind, enabled)
    assert(tooltipNameOptions[kind], "Unknown tooltip category: " .. tostring(kind))
    assert(type(enabled) == "boolean", "Tooltip name-only setting must be boolean")
    self.preferences.tooltipNameOnly[kind] = enabled
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("change tooltip coverage", function() self:RefreshFeatures() end)
    end
end

function Addon:SetTranslationHeader(enabled)
    assert(type(enabled) == "boolean", "Translation header setting must be boolean")
    self.preferences.translationHeader = enabled
    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("change translation header", function() self:RefreshFeatures() end)
    end
end

function Addon:RefreshFeatures()
    self:HideNameTooltips()
    self:RefreshSelection()
    self:ShowMapLocationLabel()
    self:ShowMapContext()
    self:ShowTranslationTooltip()
    self:UpdateRewardTooltips()
    self:RefreshNameTooltips()
    self:UpdateQuestTrackerTooltip()
    self:UpdateQuestInteraction()
    self:UpdateQuestOfferTooltip()
    self:UpdateGossipOptionTooltip()

    self.mapMenuTooltip:Hide()
    self.mapMenuTooltip:SetWindow(nil)
end

function Addon:SetFeatureEnabled(id, enabled)
    assert(featureByID[id], "Unknown Forever Rosetta Stone feature: " .. tostring(id))
    assert(type(enabled) == "boolean", "Forever Rosetta Stone feature settings must be boolean")
    self.preferences.features[id] = enabled
    self:RefreshSettingsUI()

    if self.lifecycle == "ready" then
        self:Run("apply feature settings", function() self:RefreshFeatures() end)
    end
end

function Addon:ResetFeatureSettings()
    for _, feature in ipairs(self.features) do self.preferences.features[feature.id] = true end
    self.preferences.locale = "enUS"
    self.preferences.npcTooltipPosition = "top"
    self.preferences.tooltipMode = "stacked"
    self.preferences.translationOnly = false
    self.preferences.stackedTranslationFirst = false
    for kind in pairs(tooltipNameOptions) do self.preferences.tooltipNameOnly[kind] = false end
    self.preferences.translationHeader = true
    self.contentKey, self.tooltipKey = nil, nil

    self:RefreshSettingsUI()
    if self.lifecycle == "ready" then
        self:Run("restore feature defaults", function() self:RefreshFeatures() end)
    end
end

function Addon:RefreshSettingsUI()
    local nativeChange = false
    for _, setting in pairs(self.settings or {}) do
        if setting:IsLocked() then nativeChange = true; break end
    end
    -- Native Settings notifies controls after its proxy setter returns and unlocks.
    if not nativeChange then
        for _, setting in pairs(self.settings or {}) do setting:NotifyUpdate() end
    end
    self:RefreshRadioLists()
    if self.liveSettings and self.liveSettings:IsShown() then self.liveSettings:Refresh() end
    self:RefreshTooltipPreview()
end

-- Inline radio lists show every choice at once without a popup, so controller focus stays native.
local RADIO_TEXTURE = [[Interface\Buttons\UI-RadioButton]]
local RADIO_ATLAS, RADIO_SELECTED_ATLAS = "common-dropdown-tickradial", "common-dropdown-icon-radialtick-yellow"
-- Native rows put labels at the indent and controls at CENTER - 80; choices share that column.
-- SmartNavigation locates each native control at its row's LEFT edge (SetSmartNavCursorAnchor), so
-- the first choice of every grid row uses the same anchor and D-pad up/down flows through native rows.
local RADIO_ROW_HEIGHT, RADIO_TOP, RADIO_INDENT, RADIO_CONTROL_OFFSET = 22, 4, 37, 80

-- Choices after the first column have no native row beside them; continue vertically from the
-- first choice of their grid row when their own column ends.
local function NavigateFromRowStart(list, index, direction, step)
    return function()
        local columns = list.columns
        if list.buttons[index + step * columns] then return nil end
        local rowStart = list.buttons[index - (index - 1) % columns]
        local nextInfo = SmartNavigation:GetButtonInfoInDirection(rowStart, direction)
        return nextInfo and nextInfo.button or true
    end
end

-- Illustrative catalog records used only inside Settings. Look them up in both
-- languages so the example follows the client's language and the hovered choice.
local function SpellSample(id, field)
    return function(db, locale)
        local details = db:GetSpellDetails(id, locale)
        local body = details and details[field]
        return db:GetSpellName(id, locale), body and not body:find("$", 1, true) and body or nil
    end
end

local function NameSample(method, id)
    return function(db, locale) return (db[method](db, id, locale)) end
end

local function QuestSample(db, locale)
    local quest = db:GetQuest(783, locale)
    if quest then return quest.title, quest.summary end
end

local function ItemSample(db, locale)
    return db:GetItemName(19019, locale), db:GetGlobalStringByKey("INVTYPE_WEAPON", locale), "ffff8000"
end

local areaSample = NameSample("GetAreaName", 9)
local samples = {
    spellTooltip = SpellSample(1953, "description"), talentTooltip = SpellSample(12043, "description"),
    auraTooltip = SpellSample(130, "auraDescription"), petTooltip = SpellSample(4055, "description"),
    mountTooltip = SpellSample(458, "description"), itemTooltip = ItemSample, appearanceTooltip = ItemSample,
    npcTooltip = function(db, locale) return db:GetNpcName(1247, locale), db:GetNpcSubName(1247, locale) end,
    characterStatTooltip = function(_, locale)
        local labels = Addon.characterStatFormats[locale]
        if labels then return labels.STAT_ARMOR, labels.STAT_ARMOR_TOOLTIP and labels.STAT_ARMOR_TOOLTIP:format(15) end
    end,
    recipeTrackerTooltip = function(db, locale)
        local reagent = db:GetItemName(2996, locale)
        return db:GetSpellName(7623, locale), reagent and ("- 1 / 3 " .. reagent)
    end,
    questTooltip = QuestSample, mapQuestTooltip = QuestSample, questTrackerTooltip = QuestSample,
    questPanel = QuestSample, rewardComparison = ItemSample,
    recipeListTooltip = NameSample("GetSpellName", 7623), recipeCategoryTooltip = NameSample("GetProfessionCategoryName", 2426),
    activityTooltip = NameSample("GetActivityName", 799), gossipOptionTooltip = NameSample("GetGossipOptionName", 95414),
    bookTooltip = NameSample("GetBookName", 16),
    bookPanel = function(db, locale)
        local body = db:GetBookPage(16, locale)
        return db:GetBookName(16, locale), body and body:match("^[^\r\n]+")
    end,
    trackingMenu = NameSample("GetSpellName", 2383),
    playerTooltip = function(db, locale)
        local _, _, classID = UnitClass("player")
        return UnitName("player"), classID and db:GetClassName(classID, locale)
    end,
    appearanceSlotTooltip = NameSample("GetGlobalStringByKey", "CHESTSLOT"),
    taxiNodeTooltip = function(db, locale)
        local locationHint = db:GetGlobalStringByKey("TAXINODEYOUAREHERE", locale)
        return db:GetTaxiNodeName(2, locale), locationHint
    end,
    locationTooltip = areaSample, mapLocationLabel = areaSample, mapDropdown = areaSample, playerLocation = areaSample,
    minimapLocationTooltip = function(db, locale) return db:GetAreaName(12, locale), db:GetAreaName(9, locale) end,
    locale = ItemSample, tooltipPresentation = ItemSample, translationHeader = ItemSample,
}
samples.mapContext = samples.minimapLocationTooltip
samples.questOfferTooltip = function(db, locale) return (QuestSample(db, locale)) end
samples.minimapQuestTooltip = samples.questOfferTooltip
samples.npcTooltipPosition = samples.npcTooltip

local function SampleBlock(sample, locale, withDetails)
    local name, detail, color = sample(ForeverRosettaStoneDB, locale)
    if not name then return end
    local title = "|c" .. (color or "ffffffff") .. name .. "|r"
    return withDetails and detail and (title .. "\n" .. detail) or title
end

function Addon:GetOptionPreview(id, value)
    local sample = samples[id]
    if not sample then return end
    local locale = id == "locale" and value or Addon:GetTargetLocale()
    local mode = Addon:GetTooltipPresentation() or "below"
    if id == "tooltipPresentation" then mode = value end
    if id == "npcTooltipPosition" then mode = "separate" end
    local native = SampleBlock(sample, GetLocale(), true)
    local translated = value ~= "off" and (value ~= false or id == "translationHeader") and SampleBlock(sample, locale, value ~= "name")
    local header = Addon.preferences.translationHeader
    if id == "translationHeader" then header = value end
    if translated and mode ~= "replacement" and header then
        local caption = locale == Addon:GetTargetLocale() and Addon:GetTooltipTranslationLabel()
            or ForeverRosettaStoneDB:GetLocales()[locale]
        translated = caption .. "\n" .. translated
    end
    return native, translated, mode
end

local function OptionHelp(id, value, hint, split)
    local native, translated, mode = Addon:GetOptionPreview(id, value)
    if not native and not translated then return hint end
    local blocks = { hint, "|cffaaaaaa" .. Addon:SettingsText("preview") .. "|r" }
    if translated and mode == "above" then blocks[#blocks + 1] = translated end
    if native and (mode ~= "replacement" or not translated) then blocks[#blocks + 1] = native end
    if split and translated and mode == "separate" then return table.concat(blocks, "\n\n"), translated end
    if translated and mode ~= "above" then blocks[#blocks + 1] = translated end
    return table.concat(blocks, "\n\n")
end

local function ShowOptionHelp(owner, id, label, value, hint)
    local tip = Addon:GetWidgetTooltip()
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:SetText(label, 1, 1, 1)
    local help, separate = OptionHelp(id, value, hint, true)
    tip:AddLine(help, nil, nil, nil, true)
    tip:Show()
    local companion = tip.optionPreview
    if separate then
        if not companion then
            companion = Addon:CreateCompanionTooltip("ForeverRosettaStoneOptionPreview", tip)
            tip.optionPreview = companion
            tip:HookScript("OnHide", function() companion:Hide() end)
        end
        local position = id == "npcTooltipPosition" and value or
            (id == "npcTooltip" and Addon.preferences.npcTooltipPosition) or "bottom"
        local anchors = { top = {"BOTTOM", "TOP", 0, 4}, bottom = {"TOP", "BOTTOM", 0, -4},
            left = {"RIGHT", "LEFT", -4, 0}, right = {"LEFT", "RIGHT", 4, 0} }
        local anchor = anchors[position]
        companion:SetOwner(tip, "ANCHOR_NONE")
        companion:ClearAllPoints()
        companion:SetPoint(anchor[1], tip, anchor[2], anchor[3], anchor[4])
        companion:ClearLines()
        for line in (separate .. "\n"):gmatch("(.-)\n") do
            companion:AddLine(line ~= "" and line or " ", 1, 1, 1, true)
        end
        companion:Show()
    elseif companion then
        companion:Hide()
    end
end

function Addon:CreateRadioList(id, label, hint, choices, getValue, setValue, isEnabled, columns)
    local list = CreateFrame("Frame", nil, UIParent)
    list:Hide()
    list.choices, list.getValue, list.isEnabled, list.columns = choices, getValue, isEnabled, columns
    list.label = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    list.label:SetPoint("LEFT", list, "TOPLEFT", RADIO_INDENT, -RADIO_TOP - RADIO_ROW_HEIGHT / 2)
    list.label:SetJustifyH("LEFT")
    list.label:SetWordWrap(false)
    list.label:SetText(label)
    list.hint = hint
    list.buttons = {}
    -- Blizzard menus draw radios with these atlases; older clients keep the classic texture.
    local modernRadio = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(RADIO_ATLAS) ~= nil
    for index, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, list)
        SmartNavigation_MarkFrameIgnored(button)
        button.value = choice.value
        button.radio = button:CreateTexture(nil, "ARTWORK")
        button.radio:SetPoint("LEFT", -3, 0)
        if modernRadio then
            button.radio:SetAtlas(RADIO_ATLAS, true)
            button.dot = button:CreateTexture(nil, "ARTWORK", nil, 1)
            button.dot:SetAtlas(RADIO_SELECTED_ATLAS, true)
            button.dot:SetPoint("TOPLEFT", button.radio, "TOPLEFT")
        else
            button.radio:SetTexture(RADIO_TEXTURE)
            button.radio:SetSize(16, 16)
        end
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("LEFT", button.radio, "RIGHT", 1, 0)
        if newSettings[id .. "." .. choice.value] then
            local badge = CreateFrame("Frame", nil, button, "NewFeatureLabelTemplate")
            badge:EnableMouse(false)
            SmartNavigation_MarkFrameIgnored(badge)
            badge:SetSize(1, 1)
            badge:Show()
            button.newBadge = badge
        else
            button.text:SetPoint("RIGHT", -4, 0)
        end
        button.text:SetJustifyH("LEFT")
        button.text:SetWordWrap(false)
        button.text:SetText(choice.label)
        button:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]])
        local function Choose()
            if isEnabled and not isEnabled() then return end
            self:Run("choose " .. id, function() setValue(choice.value) end)
        end
        button:SetScript("OnClick", Choose)
        button.OnSmartNavClick = Choose
        button:SetScript("OnEnter", function()
            button:LockHighlight()
            ShowOptionHelp(list, id, choice.label, choice.value, choice.hint or hint)
        end)
        button:SetScript("OnLeave", function()
            button:UnlockHighlight()
            Addon:GetWidgetTooltip():Hide()
        end)
        list.buttons[index] = button
    end
    list.navigationRows = {}
    for index, button in ipairs(list.buttons) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        if column == 0 then
            local navigationRow = CreateFrame("Frame", nil, list)
            navigationRow:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -RADIO_TOP - row * RADIO_ROW_HEIGHT)
            navigationRow:SetSize(1, RADIO_ROW_HEIGHT)
            SmartNavigation_MarkFrameIgnored(navigationRow)
            list.navigationRows[row + 1] = navigationRow
            SmartNavigation_SetCustomCursorAnchorPointForFrame(button, CreateAnchor("RIGHT", navigationRow, "LEFT", 30))
        else
            SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.UP,
                NavigateFromRowStart(list, index, SMART_NAV_INPUT_DIRECTION.UP, -1))
            SmartNavigation_AddJumpNavigationOverride(button, SMART_NAV_INPUT_DIRECTION.DOWN,
                NavigateFromRowStart(list, index, SMART_NAV_INPUT_DIRECTION.DOWN, 1))
        end
    end
    list:SetScript("OnSizeChanged", function(_, width)
        self:LayoutRadioList(list, width)
        self:QueueRadioListLayout(list)
    end)
    list:SetScript("OnShow", function() self:QueueRadioListLayout(list) end)
    list:SetScript("OnHide", function()
        for _, button in ipairs(list.buttons) do SmartNavigation_MarkFrameIgnored(button) end
    end)
    self.radioLists = self.radioLists or {}
    self.radioLists[id] = list
    return list
end

function Addon:QueueRadioListLayout(list)
    if list.layoutPending then return end
    list.layoutPending = true
    C_Timer.After(0, function()
        list.layoutPending = nil
        if list:IsVisible() then self:LayoutRadioList(list) end
    end)
end

function Addon:LayoutRadioList(list, listWidth)
    listWidth = listWidth or list:GetWidth()
    if listWidth <= 0 then
        for _, button in ipairs(list.buttons) do SmartNavigation_MarkFrameIgnored(button) end
        return
    end
    local left = listWidth / 2 - RADIO_CONTROL_OFFSET
    local width = (listWidth - left - 20) / list.columns
    if width <= 0 then return end
    list.label:SetPoint("RIGHT", list, "TOPLEFT", left - 8, -RADIO_TOP - RADIO_ROW_HEIGHT / 2)
    for index, button in ipairs(list.buttons) do
        local column, row = (index - 1) % list.columns, math.floor((index - 1) / list.columns)
        button:ClearAllPoints()
        button:SetSize(width, RADIO_ROW_HEIGHT)
        button:SetPoint("TOPLEFT", list, "TOPLEFT", left + column * width, -RADIO_TOP - row * RADIO_ROW_HEIGHT)
        if button.newBadge then
            local badgeWidth = button.newBadge.Label:GetStringWidth()
            local room = width - button.radio:GetWidth() - badgeWidth - 12
            button.text:SetWidth(math.min(button.text:GetUnboundedStringWidth() + 1, math.max(1, room)))
            button.newBadge:SetPoint("CENTER", button.text, "RIGHT", 5 + badgeWidth / 2, 0)
        end
        -- Native settings sorts focusable children by GetTop before deferred anchors resolve.
        if list:IsVisible() and button:GetLeft() and button:GetTop() then
            SmartNavigation_ClearIgnoreStatus(button)
        else
            SmartNavigation_MarkFrameIgnored(button)
        end
    end
end

function Addon:RefreshRadioLists()
    for _, list in pairs(self.radioLists or {}) do
        local current = list.getValue()
        local enabled = not list.isEnabled or list.isEnabled()
        list:SetAlpha(enabled and 1 or 0.5)
        for _, button in ipairs(list.buttons) do
            local selected = button.value == current
            button.selected = selected
            if button.dot then
                button.dot:SetShown(selected)
            else
                button.radio:SetTexCoord(selected and 0.25 or 0, selected and 0.5 or 0.25, 0, 1)
            end
            button:SetEnabled(enabled)
        end
    end
end

function Addon:AttachRadioList(host, id)
    local list = self.radioLists[id]
    list:SetParent(host)
    -- Lists are created under UIParent; draw them in the settings row's strata, not behind the panel.
    list:SetFrameStrata(host:GetFrameStrata())
    list:SetFrameLevel(host:GetFrameLevel() + 1)
    list:ClearAllPoints()
    list:SetAllPoints(host)
    list:Show()
    self:LayoutRadioList(list)
    -- Settings may resolve the pooled host's anchors after OnShow returns.
    self:QueueRadioListLayout(list)
    self:RefreshRadioLists()
end

function Addon:AttachSettingsPreview(host)
    local panel = self.settingsPanel
    SmartNavigation_MarkFrameFocusable(host)
    SmartNavigation_SetCustomCursorAnchorPointForFrame(host, CreateAnchor("RIGHT", host, "LEFT", 0, 0))
    panel:SetParent(host)
    panel:ClearAllPoints()
    panel:SetAllPoints(host)
    panel:Show()
    self:RefreshTooltipPreview()
    self:QueueTooltipPreviewRefresh()
end

function Addon:CreateSettingsUI()
    if self.settingsCategory then self:RefreshSettingsUI(); return end

    local category, layout = Settings.RegisterVerticalLayoutCategory("Forever Rosetta Stone")
    self.settingsCategory = category
    self.settings = {}
    self.liveSettingsGroups = {}
    local function Group(label)
        table.insert(self.liveSettingsGroups, { label = label, rows = {} })
    end
    local function Register(category, id, name, default, getValue, setValue)
        local valueType = Settings.VarType[type(default) == "boolean" and "Boolean"
            or type(default) == "number" and "Number" or "String"]
        local setting = Settings.RegisterProxySetting(category, "ForeverRosettaStone_" .. id,
            valueType, name, default, getValue, setValue)
        self.settings[id] = setting
        table.insert(self.liveSettingsGroups[#self.liveSettingsGroups].rows, { id = id, name = name, setting = setting })
        return setting
    end
    -- Native addon dropdown popups taint the client's shared controller focus on opening.
    -- Lists use inline radio rows; two-value choices use native checkboxes.
    local function RadioList(template, columns, id, label, hint, default, choices, getValue, setValue, isEnabled)
        Register(category, id, label, default, getValue, setValue)
        self:CreateRadioList(id, label, hint, choices, getValue, setValue, isEnabled, columns)
        local initializer = Settings.CreatePanelInitializer(template, { list = id })
        if initializer.AddSearchTags then initializer:AddSearchTags(label) end
        layout:AddInitializer(initializer)
        return initializer
    end
    local function Checkbox(category, id, setting, description)
        local initializer = Settings.CreateCheckbox(category, setting, description)
        if samples[id] then
            initializer.GetTooltip = function() return OptionHelp(id, setting:GetValue(), description) end
        end
        return initializer
    end
    local Text = function(key) return self:SettingsText(key) end
    local function TooltipChoices(feature, kind, label, description)
        local function Read()
            if not self:IsFeatureEnabled(feature.id) then return "off" end
            return self:GetTooltipCoverage(kind)
        end
        local function Apply(mode)
            assert(mode == "off" or mode == "name" or mode == "full", "Unknown tooltip mode")
            self.preferences.tooltipNameOnly[kind] = mode == "name"
            self:SetFeatureEnabled(feature.id, mode ~= "off")
        end
        RadioList("ForeverRosettaStoneMode_" .. kind, 3, feature.id, label, description, "full", {
            { value = "off", label = Text("modeOff"), hint = Text("offHint") },
            { value = "name", label = Text("modeName"), hint = Text("nameOnlyHint") },
            { value = "full", label = Text("modeFull"), hint = description },
        }, Read, Apply)
    end
    local names, languages = ForeverRosettaStoneDB:GetLocales(), {}
    for locale, name in pairs(names) do
        if locale:sub(1, 2) ~= GetLocale():sub(1, 2) then languages[#languages + 1] = { value = locale, label = name } end
    end
    table.sort(languages, function(a, b) return a.label == b.label and a.value < b.value or a.label < b.label end)
    Group(Text("translation"))
    local liveButton = CreateSettingsButtonInitializer(Text("liveSettings"), OPEN or Text("liveSettings"),
        function() self:OpenLiveSettings() end, Text("liveHint"), true)
    liveButton.showNew = true
    layout:AddInitializer(liveButton)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(self:DebugText("title")))
    layout:AddInitializer(CreateSettingsButtonInitializer(self:DebugText("inspect"), self:DebugText("inspect"),
        function() self:ToggleDebugInspection() end, self:DebugText("inspectHint"), true))
    layout:AddInitializer(CreateSettingsButtonInitializer(self:DebugText("title"), self:SettingsText("openConsole"),
        function()
            HideUIPanel(SettingsPanel)
            self:RunDebugCommand("")
        end, self:DebugText("inspectHint") .. "\n" .. self:DebugText("reportHint"), true))
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(Text("translation")))
    RadioList("ForeverRosettaStoneSettingsLanguageListTemplate", 2, "locale", Text("language"), Text("languageHint"), "enUS", languages,
        function() return self:GetTargetLocale() end,
        function(value) self:SetTargetLocale(value) end)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(Text("tooltipLayout")))
    RadioList("ForeverRosettaStoneSettingsPresentationListTemplate", 1, "tooltipPresentation",
        Text("translation"), Text("belowOriginal"), "below", {
            { value = "below", label = Text("belowOriginal") },
            { value = "above", label = Text("aboveOriginal"), hint = Text("stackedTranslationFirstHint") },
            { value = "separate", label = Text("separate"), hint = Text("separateHint") },
            { value = "replacement", label = Text("translationOnly"), hint = Text("translationOnlyHint") },
        }, function() return self:GetTooltipPresentation() end, function(value) self:SetTooltipPresentation(value) end)
    local positions = {}
    for index, position in ipairs({ "top", "left", "right", "bottom" }) do
        positions[index] = { value = position, label = Text(position) }
    end
    RadioList("ForeverRosettaStoneSettingsPositionListTemplate", 4, "npcTooltipPosition", Text("npcPosition"), Text("npcPositionHint"), "top", positions,
        function() return self.preferences.npcTooltipPosition end,
        function(value) self:SetNpcTooltipPosition(value) end,
        function() return self:GetTooltipPresentation() == "separate" end)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(Text("tooltipContent")))
    local header = Register(category, "translationHeader", Text("translationHeader"), true,
        function() return self.preferences.translationHeader end,
        function(value) self:SetTranslationHeader(value) end)
    local headerControl = Checkbox(category, "translationHeader", header, Text("translationHeaderHint"))
    headerControl:AddModifyPredicate(function() return not self.preferences.translationOnly end)
    headerControl:AddEvaluateStateCVar(self.settings.tooltipPresentation:GetVariable())

    local panel = CreateFrame("Frame", "ForeverRosettaStoneSettingsPanel", UIParent)
    panel:Hide()
    SmartNavigation_MarkFrameIgnored(panel)
    self.settingsPanel = panel
    local preview = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
    preview:SetAllPoints(panel)
    preview:SetClipsChildren(true)
    panel.TooltipPreview = preview
    preview.native = self:CreateCompanionTooltip("ForeverRosettaStonePreviewNative", preview)
    preview.translated = self:CreateCompanionTooltip("ForeverRosettaStonePreviewTranslated", preview)
    preview.native:SetFrameStrata("HIGH")
    preview.translated:SetFrameStrata("HIGH")
    preview.native:SetClampedToScreen(false)
    preview.translated:SetClampedToScreen(false)
    hooksecurefunc(preview.native, "ClearLines", function()
        if self.tooltipRendering ~= preview.native then self:ClearStackedTooltip(preview.native, true) end
    end)
    preview.native:HookScript("OnHide", function() self:ClearStackedTooltip(preview.native, true) end)
    panel:SetScript("OnShow", function() self:QueueTooltipPreviewRefresh() end)
    panel:SetScript("OnHide", function()
        preview.native:Hide()
        preview.translated:Hide()
    end)
    preview:SetScript("OnSizeChanged", function() self:QueueTooltipPreviewRefresh() end)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(self:SettingsText("preview")))
    layout:AddInitializer(Settings.CreatePanelInitializer("ForeverRosettaStoneSettingsPreviewTemplate", {}))

    local parentFeatures = {
        questAutoOpen = "questPanel", questGreetingAutoOpen = "questPanel",
        questProgressAutoOpen = "questPanel", questRewardAutoOpen = "questPanel",
        rewardComparison = "questPanel", bookAutoOpen = "bookPanel",
    }
    self.liveSettingParents = parentFeatures
    local featureControls = {}
    for _, group in ipairs({ "Quests", "Items", "Spells", "Talents", "NPCs", "Locations", "Collections", "Character", "Professions", "Books" }) do
        Group(self:SettingsGroupName(group))
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(self:SettingsGroupName(group)))
        for _, feature in ipairs(self.features) do
            if feature.group == group then
                local name, description = self:FeatureText(feature)
                local kind = feature.id:match("^(.-)Tooltip$")
                if tooltipNameOptions[kind] then
                    TooltipChoices(feature, kind, name, description)
                else
                    local setting = Register(category, feature.id, name, true,
                        function() return self:IsFeatureEnabled(feature.id) end,
                        function(value) self:SetFeatureEnabled(feature.id, value) end)
                    local control = Checkbox(category, feature.id, setting, description)
                    featureControls[feature.id] = control
                    local parent = parentFeatures[feature.id]
                    if parent then
                        control:SetParentInitializer(featureControls[parent], function() return self:IsFeatureEnabled(parent) end)
                        control:AddEvaluateStateCVar(self.settings[parent]:GetVariable())
                    end
                end
            end
        end
    end

    Settings.RegisterAddOnCategory(category)
    local settingsList = SettingsPanel:GetSettingsList()
    local defaults = settingsList and settingsList.Header and settingsList.Header.DefaultsButton
    local nativeDefaults = defaults and defaults:GetScript("OnClick")
    local scrollState = "native"
    local function SyncControllerScroll()
        if InCombatLockdown() then return end
        local selected = SettingsPanel:GetCurrentCategory()
        local ownCategory = SettingsPanel:IsShown() and selected and selected:GetID() == category:GetID()
        local list = SettingsPanel:GetSettingsList()
        if ownCategory and list and list.ScrollBox then
            SmartNavigation:SetScrollFrameForFrame(SettingsPanel, list.ScrollBox)
            scrollState = "addon"
        elseif scrollState == "addon" then
            SmartNavigation:SetScrollFrameForFrame(SettingsPanel, nil)
            scrollState = "native"
        end
    end
    local function addonDefaults()
        self:Run("confirm addon settings reset", function() self:ShowSettingsResetDialog() end)
    end
    local function SyncDefaults()
        local selected = SettingsPanel:GetCurrentCategory()
        local ownCategory = SettingsPanel:IsShown() and selected and selected:GetID() == category:GetID()
        if defaults then defaults:SetScript("OnClick", ownCategory and addonDefaults or nativeDefaults) end
        SyncControllerScroll()
    end
    hooksecurefunc(SettingsPanel, "DisplayCategory", SyncDefaults)
    hooksecurefunc(SettingsPanel, "FocusContainer", SyncControllerScroll)
    SettingsPanel:HookScript("OnShow", SyncDefaults)
    SettingsPanel:HookScript("OnHide", function()
        if defaults then defaults:SetScript("OnClick", nativeDefaults) end
        SyncControllerScroll()
    end)
    self:RefreshSettingsUI()
end

function Addon:ShowSettingsResetDialog()
    if InCombatLockdown() then return end
    if not self.settingsResetDialog then
        local overlay = CreateFrame("Frame", "ForeverRosettaStoneSettingsReset", UIParent)
        overlay:Hide()
        overlay:SetAllPoints(SettingsPanel)
        overlay:SetFrameStrata("DIALOG")
        overlay:SetFrameLevel(SettingsPanel:GetFrameLevel() + 100)
        overlay:EnableMouse(true)
        local window = CreateFrame("Frame", nil, overlay, "DialogBorderOpaqueTemplate")
        window:ClearAllPoints()
        window:SetPoint("TOP", SettingsPanel, "TOP", 0, -30)
        window:SetSize(338, 116)
        local text = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOPLEFT", 16, -12)
        text:SetPoint("TOPRIGHT", -16, -12)
        text:SetWordWrap(true)
        text:SetText(self:SettingsText("resetPrompt"))
        local accept = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        accept:SetSize(128, 22)
        accept:SetPoint("BOTTOMLEFT", 20, 14)
        accept:SetText(self:SettingsText("resetAccept"))
        local cancel = CreateFrame("Button", nil, window, "UIPanelButtonTemplate")
        cancel:SetSize(128, 22)
        cancel:SetPoint("BOTTOMRIGHT", -20, 14)
        cancel:SetText(CANCEL)
        local function Close() overlay:Hide() end
        accept:SetScript("OnClick", function()
            self:Run("restore addon settings", function() self:ResetFeatureSettings() end)
            Close()
        end)
        cancel:SetScript("OnClick", Close)
        accept.OnSmartNavClick = accept:GetScript("OnClick")
        cancel.OnSmartNavClick = Close
        SmartNavigation_AddBidirectionalJumpNavigationOverride(accept, SMART_NAV_INPUT_DIRECTION.RIGHT, cancel)
        local focusArrow = window:CreateTexture(nil, "OVERLAY")
        focusArrow:SetSize(28, 28)
        focusArrow:SetAtlas("gamepad-largecursor-white")
        focusArrow:SetVertexColor(1, 0.82, 0)
        focusArrow:Hide()
        window.SmartNavigationOnSelect = function(_, button)
            focusArrow:Hide()
            if not button then return end
            focusArrow:ClearAllPoints()
            focusArrow:SetPoint("RIGHT", button, "LEFT", 8, 0)
            focusArrow:Show()
        end
        window.SmartNavigationCloseHandler = function() Close(); return true end
        window.FocusGamepad = function() self:ClearGamepadTarget(window) end
        local acceptIcon = GamepadMode.AddGamepadIconToButton(accept, GAMEPAD_FACE_BOTTOM)
        local cancelIcon = GamepadMode.AddGamepadIconToButton(cancel, GAMEPAD_FACE_RIGHT)
        self.settingsResetDialog = { frame = overlay, window = window, accept = accept, cancel = cancel }
        overlay:SetScript("OnShow", function()
            GamepadMode.SetGamepadIconShown(acceptIcon, InputUtil.IsGamepadUIEnabled())
            GamepadMode.SetGamepadIconShown(cancelIcon, InputUtil.IsGamepadUIEnabled())
            if InputUtil.IsGamepadUIEnabled() then
                GamepadMode.FrameControlsManager:FrameShown(window)
            end
        end)
        overlay:SetScript("OnHide", function()
            local categoryID = self.settingsResetDialog.categoryID
            focusArrow:Hide()
            GamepadMode.FrameControlsManager:FrameHidden(window)
            SmartNavigation:RemovePanelInfo(window)
            C_Timer.After(0, function()
                local selected = SettingsPanel:GetCurrentCategory()
                if overlay:IsShown() or not SettingsPanel:IsShown() or not InputUtil.IsGamepadUIEnabled()
                    or InCombatLockdown() or not selected or selected:GetID() ~= categoryID then return end
                self:Run("return to addon settings", function()
                    local manager = GamepadMode.FrameControlsManager
                    manager:FrameHidden(SettingsPanel)
                    manager:FrameShown(SettingsPanel)
                    securecallfunction(Settings.OpenToCategory, categoryID)
                end)
            end)
        end)
        SettingsPanel:HookScript("OnHide", Close)
        table.insert(UISpecialFrames, "ForeverRosettaStoneSettingsReset")
    end
    self.settingsResetDialog.categoryID = SettingsPanel:GetCurrentCategory():GetID()
    self.settingsResetDialog.frame:Show()
end

-- This window is outside UIPanelWindows so the native radial can still open game panels.
function Addon:OpenLiveSettings()
    if InCombatLockdown() then return end
    if SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if GameMenuFrame and GameMenuFrame:IsShown() then HideUIPanel(GameMenuFrame) end
    if self.liveSettings then self.liveSettings:Show(); return end

    local window = CreateFrame("Frame", "ForeverRosettaStoneLiveSettings", UIParent, "PortraitFrameTemplateNoCloseButton")
    self.liveSettings = window
    window:Hide()
    window:SetSize(528, 300)
    window:SetPoint("RIGHT", UIParent, "RIGHT", -16, 0)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:RegisterForDrag("LeftButton")
    window:SetScript("OnDragStart", function() window:StartMoving() end)
    window:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    window:SetTitle("Forever Rosetta Stone")
    window:SetPortraitToAsset([[Interface\AddOns\ForeverRosettaStone\media\icon]])
    local function Button(label, width, action, template)
        local button = CreateFrame("Button", nil, window, template or "UIPanelButtonTemplate")
        button:SetSize(width, 24)
        if label then button:SetText(label) end
        button:SetScript("OnClick", action)
        button.OnSmartNavClick = action
        return button
    end
    local close = Button(nil, 26, function() window:Hide() end, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    Button(self:DebugText("inspect"), 182, function() self:ToggleDebugInspection() end)
        :SetPoint("TOPLEFT", 68, -39)
    Button(self:SettingsText("openConsole"), 182, function() self:RunDebugCommand("") end)
        :SetPoint("TOPRIGHT", -20, -39)
    local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -80)
    local page, controls = 1, {}
    local function Turn(step)
        page = (page - 1 + step) % #self.liveSettingsGroups + 1
        window:Refresh()
    end
    Button("<", 36, function() Turn(-1) end):SetPoint("TOPLEFT", 26, -75)
    Button(">", 36, function() Turn(1) end):SetPoint("TOPRIGHT", -20, -75)

    function window:Refresh()
        local group = Addon.liveSettingsGroups[page]
        title:SetText(group.label)
        self:SetHeight(126 + #group.rows * 30)
        for index, row in ipairs(group.rows) do
            local button = controls[index]
            if not button then
                local function Change(step)
                    local current = Addon.liveSettingsGroups[page].rows[index]
                    local list = Addon.radioLists[current.id]
                    local value = current.setting:GetValue()
                    if list then
                        for i, choice in ipairs(list.choices) do
                            if choice.value == value then
                                current.setting:SetValue(list.choices[(i - 1 + step) % #list.choices + 1].value)
                                break
                            end
                        end
                    else
                        current.setting:SetValue(not value)
                    end
                end
                button = Button("", 180, function() Change(1) end)
                button.previous = Button("<", 30, function() Change(-1) end)
                button.previous:SetPoint("RIGHT", button, "LEFT", -4, 0)
                button.following = Button(">", 30, function() Change(1) end)
                button.following:SetPoint("LEFT", button, "RIGHT", 4, 0)
                local function Hover(owner, step)
                    local row = Addon.liveSettingsGroups[page].rows[index]
                    local list = Addon.radioLists[row.id]
                    local value = row.setting:GetValue()
                    if list then
                        for i, choice in ipairs(list.choices) do
                            if choice.value == value then
                                local hovered = list.choices[(i - 1 + step) % #list.choices + 1]
                                ShowOptionHelp(owner, row.id, hovered.label, hovered.value, hovered.hint or list.hint)
                                return
                            end
                        end
                    else
                        local feature = featureByID[row.id]
                        local hint = feature and select(2, Addon:FeatureText(feature)) or Addon:SettingsText("translationHeaderHint")
                        ShowOptionHelp(owner, row.id, row.name, value, hint)
                    end
                end
                for step, control in pairs({ [-1] = button.previous, [0] = button, [1] = button.following }) do
                    control:SetScript("OnEnter", function(owner) Hover(owner, step) end)
                    control:SetScript("OnLeave", function() Addon:GetWidgetTooltip():Hide() end)
                end
                button.label = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                button.label:SetPoint("LEFT", window, "TOPLEFT", 22, -119 - (index - 1) * 30)
                button.label:SetPoint("RIGHT", window, "TOPRIGHT", -276, -119 - (index - 1) * 30)
                button.label:SetJustifyH("LEFT")
                controls[index] = button
            end
            local value = row.setting:GetValue()
            local list = Addon.radioLists[row.id]
            local label = value and Addon:SettingsText("liveOn") or Addon:SettingsText("modeOff")
            if list then
                for _, choice in ipairs(list.choices) do
                    if choice.value == value then label = choice.label; break end
                end
            end
            local parent = Addon.liveSettingParents[row.id]
            local enabled = (not parent or Addon:IsFeatureEnabled(parent))
                and (not list or not list.isEnabled or list.isEnabled())
                and (row.id ~= "translationHeader" or not Addon.preferences.translationOnly)
            button:ClearAllPoints()
            button:SetWidth(list and 180 or 248)
            button:SetPoint("TOPRIGHT", list and -54 or -20, -107 - (index - 1) * 30)
            button.previous:SetShown(list ~= nil)
            button.following:SetShown(list ~= nil)
            button.previous:SetEnabled(enabled)
            button.following:SetEnabled(enabled)
            button:SetEnabled(enabled)
            button.label:SetText(row.name)
            button.label:SetAlpha(enabled and 1 or 0.5)
            button:SetText(label)
            button:Show()
            button.label:Show()
        end
        for index = #group.rows + 1, #controls do
            controls[index]:Hide()
            controls[index].label:Hide()
            controls[index].previous:Hide()
            controls[index].following:Hide()
        end
    end
    local registered = false
    local function Sync()
        if InCombatLockdown() then return end
        local active = window:IsShown() and InputUtil.IsGamepadUIEnabled()
        if active == registered then return end
        registered = active
        if active then GamepadMode.FrameControlsManager:FrameShown(window, false, true)
        else
            GamepadMode.FrameControlsManager:FrameHidden(window)
            SmartNavigation:RemovePanelInfo(window)
        end
    end
    window.FocusGamepad = function() Addon:ClearGamepadTarget(window) end
    window.SmartNavigationCloseHandler = function() window:Hide(); return true end
    local arrow = window:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(26, 26)
    arrow:SetAtlas("gamepad-largecursor-white")
    arrow:Hide()
    window.SmartNavigationOnSelect = function(_, button)
        arrow:Hide()
        if button then
            arrow:ClearAllPoints()
            arrow:SetPoint("RIGHT", button, "LEFT", 5, 0)
            arrow:Show()
        end
    end
    window.UnfocusGamepad = function() arrow:Hide() end
    window:SetScript("OnShow", function() window:Refresh(); Sync() end)
    window:SetScript("OnHide", function() arrow:Hide(); Sync() end)
    window:RegisterEvent("PLAYER_REGEN_ENABLED")
    window:SetScript("OnEvent", Sync)
    InputUtil.RegisterForInterfaceTransitions(window, Sync)
    window:Show()
end

function Addon:OpenSettings()
    if self.errorDialog and self.errorDialog.console then self.errorDialog.frame:Hide() end
    securecallfunction(Settings.OpenToCategory, self.settingsCategory:GetID())
end
