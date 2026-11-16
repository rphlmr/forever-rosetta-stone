local _, Addon = ...

Addon.features = {
    { id = "taxiNodeTooltip", name = "Flight map destinations", group = "Locations",
        description = "Translate flight map destination names using the hovered flight node ID. Prices and route information stay native." },
    { id = "recipeTrackerTooltip", name = "Tracked recipes", group = "Professions",
        description = "Show translated recipe names and live reagent counts when hovering tracked recipes in any profession." },
    { id = "recipeListTooltip", name = "Recipe list", group = "Professions",
        description = "Show translated recipe names when hovering the recipe list in any profession." },
    { id = "recipeCategoryTooltip", name = "Recipe sections", group = "Professions",
        description = "Show translated section names when hovering profession recipe categories." },
    { id = "questPanel", name = "Quest panel", group = "Quests",
        description = "Show translated quest text beside map details and NPC quest windows. Map details include a bookmark and controller navigation." },
    { id = "questAutoOpen", name = "Open translation automatically", group = "Quests",
        description = "Open the quest translation as soon as quest details or an NPC quest window appear. When off, use the bookmark to open it." },
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
    { id = "talentTooltip", name = "Talent tooltips", group = "Talents",
        description = "Show translated talent names and descriptions on the same side of the hovered talent as the original." },
    { id = "npcTooltip", name = "NPC tooltips", group = "NPCs",
        description = "Show translated creature names stacked or in a separate tooltip at your chosen position. Player and custom pet names stay native." },
    { id = "playerTooltip", name = "Player tooltips", group = "Character",
        description = "Translate player class, race, and level with full-text tooltips enabled. Player names and unavailable translations stay native." },
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
local tooltipCoverages = { name = true, full = true }

function Addon:LoadPreferences()
    if type(ForeverRosettaStoneSettings) ~= "table" then ForeverRosettaStoneSettings = {} end
    if type(ForeverRosettaStoneSettings.features) ~= "table" then ForeverRosettaStoneSettings.features = {} end

    self.preferences = ForeverRosettaStoneSettings
    self:LoadErrorLog()
    local angle = self.preferences.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = 135 end
    self.preferences.minimapAngle = angle % 360
    if not tooltipModes[self.preferences.tooltipMode] then self.preferences.tooltipMode = "stacked" end
    if not tooltipCoverages[self.preferences.tooltipCoverage] then self.preferences.tooltipCoverage = "full" end
    if type(self.preferences.translationHeader) ~= "boolean" then self.preferences.translationHeader = true end
    if not npcTooltipPositions[self.preferences.npcTooltipPosition] then self.preferences.npcTooltipPosition = "top" end

    if not ForeverRosettaStoneDB:GetLocales()[self.preferences.locale] then self.preferences.locale = "enUS" end
    ForeverRosettaStoneDB:LoadLocale(self.preferences.locale)

    for _, feature in ipairs(self.features) do
        if type(self.preferences.features[feature.id]) ~= "boolean" then
            self.preferences.features[feature.id] = true
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

function Addon:SetTooltipCoverage(coverage)
    assert(tooltipCoverages[coverage], "Unknown tooltip coverage: " .. tostring(coverage))
    self.preferences.tooltipCoverage = coverage
    self.tooltipKey, self.questTrackerTooltipKey = nil, nil
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
    self:UpdateQuestOfferTooltip()

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
    self.preferences.tooltipCoverage = "full"
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

function Addon:CreateRadioList(id, label, hint, choices, getValue, setValue, isEnabled, columns)
    local list = CreateFrame("Frame", nil, UIParent)
    list:Hide()
    list.choices, list.getValue, list.isEnabled, list.columns = choices, getValue, isEnabled, columns
    list.label = list:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    list.label:SetPoint("LEFT", list, "TOPLEFT", RADIO_INDENT, -RADIO_TOP - RADIO_ROW_HEIGHT / 2)
    list.label:SetJustifyH("LEFT")
    list.label:SetWordWrap(false)
    list.label:SetText(label)
    list.buttons = {}
    -- Blizzard menus draw radios with these atlases; older clients keep the classic texture.
    local modernRadio = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(RADIO_ATLAS) ~= nil
    for index, choice in ipairs(choices) do
        local button = CreateFrame("Button", nil, list)
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
        button.text:SetPoint("RIGHT", -4, 0)
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
            Addon:GetWidgetTooltip():SetOwner(list, "ANCHOR_RIGHT")
            Addon:GetWidgetTooltip():SetText(label, 1, 1, 1)
            Addon:GetWidgetTooltip():AddLine(hint, nil, nil, nil, true)
            Addon:GetWidgetTooltip():Show()
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
    if listWidth <= 0 then return end
    local left = listWidth / 2 - RADIO_CONTROL_OFFSET
    local width = (listWidth - left - 20) / list.columns
    if width <= 0 then return end
    list.label:SetPoint("RIGHT", list, "TOPLEFT", left - 8, -RADIO_TOP - RADIO_ROW_HEIGHT / 2)
    for index, button in ipairs(list.buttons) do
        local column, row = (index - 1) % list.columns, math.floor((index - 1) / list.columns)
        button:ClearAllPoints()
        button:SetSize(width, RADIO_ROW_HEIGHT)
        button:SetPoint("TOPLEFT", list, "TOPLEFT", left + column * width, -RADIO_TOP - row * RADIO_ROW_HEIGHT)
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
    local function Register(category, id, name, default, getValue, setValue)
        local valueType = Settings.VarType[type(default) == "boolean" and "Boolean"
            or type(default) == "number" and "Number" or "String"]
        local setting = Settings.RegisterProxySetting(category, "ForeverRosettaStone_" .. id,
            valueType, name, default, getValue, setValue)
        self.settings[id] = setting
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
    local function Toggle(category, id, name, default, onValue, offValue, getValue, setValue, description)
        Register(category, id, name, default and onValue or offValue, getValue, setValue)
        local setting = Register(category, id .. "Enabled", name, default,
            function() return getValue() == onValue end,
            function(enabled) setValue(enabled and onValue or offValue) end)
        return Settings.CreateCheckbox(category, setting, description)
    end
    local Text = function(key) return self:SettingsText(key) end
    local names, languages = ForeverRosettaStoneDB:GetLocales(), {}
    for locale, name in pairs(names) do
        if locale:sub(1, 2) ~= GetLocale():sub(1, 2) then languages[#languages + 1] = { value = locale, label = name } end
    end
    table.sort(languages, function(a, b) return a.label == b.label and a.value < b.value or a.label < b.label end)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(Text("translation")))
    RadioList("ForeverRosettaStoneSettingsLanguageListTemplate", 2, "locale", Text("language"), Text("languageHint"), "enUS", languages,
        function() return self:GetTargetLocale() end,
        function(value) self:SetTargetLocale(value) end)
    Toggle(category, "tooltipMode", Text("separate"), false, "separate", "stacked",
        function() return self.preferences.tooltipMode end,
        function(value) self:SetTooltipMode(value) end,
        Text("separateHint"))
    Toggle(category, "tooltipCoverage", Text("fullText"), true, "full", "name",
        function() return self.preferences.tooltipCoverage end,
        function(value) self:SetTooltipCoverage(value) end,
        Text("fullTextHint"))
    local header = Register(category, "translationHeader", Text("translationHeader"), true,
        function() return self.preferences.translationHeader end,
        function(value) self:SetTranslationHeader(value) end)
    Settings.CreateCheckbox(category, header, Text("translationHeaderHint"))
    local positions = {}
    for index, position in ipairs({ "top", "left", "right", "bottom" }) do
        positions[index] = { value = position, label = Text(position) }
    end
    RadioList("ForeverRosettaStoneSettingsPositionListTemplate", 4, "npcTooltipPosition", Text("npcPosition"), Text("npcPositionHint"), "top", positions,
        function() return self.preferences.npcTooltipPosition end,
        function(value) self:SetNpcTooltipPosition(value) end,
        function() return self.preferences.tooltipMode == "separate" end)

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

    for _, group in ipairs({ "Quests", "Items", "Spells", "Talents", "NPCs", "Locations", "Collections", "Character", "Professions", "Books" }) do
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(self:SettingsGroupName(group)))
        for _, feature in ipairs(self.features) do
            if feature.group == group then
                local name, description = self:FeatureText(feature)
                local setting = Register(category, feature.id, name, true,
                    function() return self:IsFeatureEnabled(feature.id) end,
                    function(value) self:SetFeatureEnabled(feature.id, value) end)
                Settings.CreateCheckbox(category, setting, description)
            end
        end
    end

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(self:DebugText("title")))
    layout:AddInitializer(CreateSettingsButtonInitializer(self:DebugText("title"), self:SettingsText("openConsole"),
        function()
            HideUIPanel(SettingsPanel)
            self:RunDebugCommand("")
        end, self:DebugText("inspectHint") .. "\n" .. self:DebugText("reportHint"), true))
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
                    Settings.OpenToCategory(categoryID)
                end)
            end)
        end)
        SettingsPanel:HookScript("OnHide", Close)
        table.insert(UISpecialFrames, "ForeverRosettaStoneSettingsReset")
    end
    self.settingsResetDialog.categoryID = SettingsPanel:GetCurrentCategory():GetID()
    self.settingsResetDialog.frame:Show()
end

function Addon:OpenSettings()
    if self.errorDialog and self.errorDialog.console then self.errorDialog.frame:Hide() end
    Settings.OpenToCategory(self.settingsCategory:GetID())
end
