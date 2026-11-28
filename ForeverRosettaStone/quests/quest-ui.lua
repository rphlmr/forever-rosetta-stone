local _, Addon = ...

local ICON = [[Interface\AddOns\ForeverRosettaStone\media\icon]]
local SHELL_INSETS = { left = 8, right = 28, top = 26, bottom = 6 }
local PANEL_GAP = -14
local MAP_BORDER_CLEAR = 12
local TITLE_ICON_SIZE, TITLE_ICON_GAP, TITLE_INSET = 16, 3, 35
local STRATA_ORDER = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local SHELL_BORDER = { left = 8, top = 16 }

local function ResolveLocationHeader(owner, questList)
    local header, name

    while owner and owner ~= questList do
        if owner:IsForbidden() then return end
        if not header and owner.questLogIndex then
            local info = C_QuestLog.GetInfo(owner.questLogIndex)

            if info and info.isHeader then
                header, name = owner, Addon:GetQuestHeaderLocationName(info)
            end
        end

        owner = owner:GetParent()
    end

    if owner == questList and header and header:IsVisible() then return header, name end
end

local function GetPanelBounds(frame)
    local border = frame.NineSlice
    local topLeft = border and border.TopLeftCorner or frame
    local bottomRight = border and border.BottomRightCorner or frame
    local left, top = topLeft:GetLeft(), topLeft:GetTop()
    local right, bottom = bottomRight:GetRight(), bottomRight:GetBottom()

    local scale = frame:GetEffectiveScale()
    if not canaccessallvalues(left, top, right, bottom, scale) or not (left and top and right and bottom) then return end

    return { left = left * scale, right = right * scale, top = top * scale, bottom = bottom * scale }
end

function Addon:CreateQuestBookmark(parent, name, onClick)
    local button = Addon:NewFrame("Button", name, parent, "LargeSideTabButtonTemplate")
    button.Icon:SetTexture(ICON)
    button.Icon:SetSize(32, 32)
    button.Icon:SetTexCoord(0, 1, 0, 1)
    button:SetChecked(false)
    Addon:SetScript(button, "OnClick", onClick or function() Addon:OpenPanel() end)
    local function ShowOpenTooltip(owner)
        local tooltip = Addon:GetWidgetTooltip()
        tooltip:SetOwner(owner, "ANCHOR_RIGHT")
        tooltip:SetText(Addon:GetOpenPanelLabel())
        tooltip:Show()
    end
    local function HideOpenTooltip(owner)
        local tooltip = Addon:GetWidgetTooltip()
        if tooltip:IsOwned(owner) then tooltip:Hide() end
    end
    function button:SetGamepadFocus(focused)
        local visible = self:IsVisible()
        if focused and visible then ShowOpenTooltip(self) else HideOpenTooltip(self) end
        if self.gamepadPrompt then
            self.gamepadPrompt:SetInputKey(focused and GAMEPAD_FACE_BOTTOM or "PADRTRIGGER")
            self.gamepadPrompt:SetShown(self.registered == true and visible)
        end
    end
    Addon:SetScript(button, "OnEnter", function(owner)
        if owner.usesGamepadFocus and InputUtil.IsGamepadUIEnabled() then return end
        ShowOpenTooltip(owner)
    end)
    Addon:SetScript(button, "OnLeave", function(owner)
        if owner.usesGamepadFocus and InputUtil.IsGamepadUIEnabled() then return end
        HideOpenTooltip(owner)
    end)
    Addon:SetScript(button, "OnHide", function(owner)
        owner:InitializeIconAnchoring()
        owner:SetChecked(false)
        HideOpenTooltip(owner)
    end)

    return button
end

-- Leatrix's simple map anchors the native close button to a title bar spanning
-- the canvas and quest log. The hidden Blizzard border keeps its old size.
local function GetSimpleMapEdge(playerLocationLabel)
    local border, canvas = WorldMapFrame.BorderFrame, WorldMapFrame.ScrollContainer
    if not canvas or not border or not border.CloseButton or WorldMapFrame.NavBar:IsShown() then return end

    local _, title = border.CloseButton:GetPoint(1)
    if not title or not title:IsVisible() or title:GetParent() ~= WorldMapFrame then return end
    local point, relative, relativePoint = title:GetPoint(1)
    if point ~= "BOTTOMLEFT" or relative ~= canvas or relativePoint ~= "TOPLEFT" then return end

    local bottomFrame = canvas
    local footer = playerLocationLabel and playerLocationLabel:GetParent():GetParent()
    if footer and footer:IsVisible() then
        local anchor, owner, corner = footer:GetPoint(1)
        if anchor == "TOPLEFT" and owner == canvas and corner == "BOTTOMLEFT" then bottomFrame = footer end
    end
    local bounds = GetPanelBounds(title)
    local bottom, scale = bottomFrame:GetBottom(), bottomFrame:GetEffectiveScale()
    if not bounds or not canaccessallvalues(bottom, scale) or not bottom then return end
    bounds.bottom = bottom * scale
    if bounds.top > bounds.bottom then return title, bounds end
end

local function GetMapEdge(playerLocationLabel)
    local title, bounds = GetSimpleMapEdge(playerLocationLabel)
    if title then return title, bounds end
    local border = WorldMapFrame.BorderFrame
    local mini = WorldMapFrame.MiniBorderFrame
    if border and border:IsShown() and not (mini and mini:IsShown()) then
        return border
    end

    return mini or border or WorldMapFrame
end

function Addon:HasClippedQuestActions()
    local button = QuestMapFrame.DetailsFrame.AbandonButton
    local bottom = button and button:GetBottom()
    if not canaccessallvalues(bottom) or not bottom then return false end
    local edge, simpleMapBounds = GetMapEdge(self.playerLocationLabel)
    local boundary = simpleMapBounds and WorldMapFrame.ScrollContainer or edge
    local mapBottom, scale = boundary:GetBottom(), boundary:GetEffectiveScale()
    if not canaccessallvalues(mapBottom, scale) or not mapBottom then return false end
    local center = (bottom + button:GetHeight() / 2) * button:GetEffectiveScale()
    return center < math.max(0, mapBottom * scale)
end

-- Shared by the journal panel and the NPC interaction reader: translation label with the FRS logo.
function Addon:SetupQuestPanelTitle(panel)
    panel.PortraitContainer:Hide()
    panel:SetTitle(self:GetTranslationLanguageLabel())
    panel:SetTitleOffsets(TITLE_INSET, -TITLE_INSET)
    local title = panel.TitleContainer.TitleText
    title:SetTextColor(1, 0.82, 0)
    title:SetJustifyH("CENTER")
    title:ClearAllPoints()
    title:SetPoint("CENTER", panel.TitleContainer, "CENTER", (TITLE_ICON_SIZE + TITLE_ICON_GAP) / 2, -1)
    local portrait = panel.TitleContainer:CreateTexture(nil, "ARTWORK")
    portrait:SetTexture(ICON)
    portrait:SetSize(TITLE_ICON_SIZE, TITLE_ICON_SIZE)
    portrait:ClearAllPoints()
    portrait:SetPoint("RIGHT", title, "LEFT", -TITLE_ICON_GAP, 0)
    panel.TitleIcon = portrait
end

function Addon:FitQuestPanelTitle(panel)
    local title = panel.TitleContainer.TitleText
    title:SetWidth(math.min(title:GetStringWidth(),
        panel:GetWidth() - 2 * TITLE_INSET - TITLE_ICON_SIZE - TITLE_ICON_GAP))
end

-- Books and NPC interactions open beside a native reading window.
function Addon:CreateSideReader(name, dismiss)
    local frame = self:NewFrame("Frame", name, UIParent, "ForeverRosettaStoneQuestPanelTemplate")
    self:SetupQuestPanelTitle(frame)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:Hide()

    local content = self:NewFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -68)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 26)
    local background = content:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("QuestDetailsBackgrounds", true)
    background:SetAllPoints()
    local body = self:CreateNativeQuestBody(content, 278)
    body.frame:ClearAllPoints()
    body.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -8)
    body.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -5, 10)
    local close = self:NewFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors")
    frame.CloseButton = close
    self:SetScript(close, "OnClick", dismiss)
    return { frame = frame, body = body, content = content, background = background }
end

function Addon:CreateUI()
    local panel = self:NewFrame("Frame", "ForeverRosettaStoneQuestPanel", UIParent,
        "ForeverRosettaStoneQuestPanelTemplate")
    self:SetupQuestPanelTitle(panel)
    panel:SetSize(QuestMapFrame.DetailsFrame:GetWidth() + SHELL_INSETS.left + SHELL_INSETS.right,
        QuestMapFrame.DetailsFrame:GetHeight() + SHELL_INSETS.top + SHELL_INSETS.bottom)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:Hide()
    self:SetScript(panel, "OnShow", function() PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN) end)
    self:SetScript(panel, "OnHide", function() PlaySound(SOUNDKIT.IG_QUEST_LOG_CLOSE) end)

    local close = self:NewFrame("Button", nil, panel, "UIPanelCloseButtonDefaultAnchors")
    self:SetScript(close, "OnClick", function() self:Send("panel.close") end)
    panel.CloseButton = close

    local content = self:NewFrame("Frame", nil, panel)
    content:SetPoint("TOPLEFT", panel, "TOPLEFT", SHELL_INSETS.left, -SHELL_INSETS.top)
    content:SetSize(QuestMapFrame.DetailsFrame:GetSize())
    panel.Content = content
    local page = self:CreateQuestPage(content)
    local rim = self:NewFrame("Frame", nil, content, "QuestLogBorderFrameTemplate")
    rim:ClearAllPoints()
    rim:SetPoint("TOPLEFT", content, "TOPLEFT", -3, 4)
    rim:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 3, 17)
    panel.BorderFrame = rim

    local header = self:NewFrame("Frame", nil, content)
    header:SetHeight(52)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -1, 0)
    panel.Header = header
    local headerBackground = header:CreateTexture(nil, "BORDER")
    headerBackground:SetAtlas("questlog-reward-top-frame", true)
    headerBackground:SetPoint("TOPLEFT")

    local report = self:NewFrame("Button", nil, header, "UIPanelButtonTemplate")
    report:SetSize(110, 22)
    report:SetPoint("TOPRIGHT", header, "TOPRIGHT", -10, -10)
    report:SetText("Options")
    self:SetScript(report, "OnClick", function(owner) self:ShowQuestOptions(owner) end)
    report:Hide()
    panel.ReportButton = report

    local toggle = self:CreateQuestBookmark(QuestMapFrame.DetailsFrame, "ForeverRosettaStoneQuestToggle")
    toggle:SetClampedToScreen(true)
    toggle:Hide()

    self.panel, self.page, self.toggle = panel, page, toggle
    self.tooltip = self:CreateCompanionTooltip("ForeverRosettaStoneTranslationTooltip")
    self.tooltip:Hide()
    self.locationTooltip = self:CreateCompanionTooltip("ForeverRosettaStoneLocationTooltip")
    self.locationTooltip:SetClampedToScreen(true)
    self.locationTooltip:Hide()
    self.mapMenuTooltip = self:CreateCompanionTooltip("ForeverRosettaStoneMapMenuTooltip")
    self.mapMenuTooltip:SetClampedToScreen(true)
    self.mapMenuTooltip:Hide()
    local mapLabel = self:NewFrame("Frame", "ForeverRosettaStoneMapLocationLabel", WorldMapFrame)
    mapLabel:SetSize(1, 1)
    mapLabel.Text = mapLabel:CreateFontString(nil, "OVERLAY")
    mapLabel.Text:SetPoint("TOP")
    mapLabel.Text:SetJustifyH("CENTER")
    mapLabel.Text:SetWordWrap(false)
    mapLabel:Hide()
    self.mapLocationLabel = mapLabel
    local context = self:NewFrame("Frame", "ForeverRosettaStoneMapContextLabel", WorldMapFrame)
    context:SetSize(1, 1)
    context:EnableMouse(false)
    context.Text = context:CreateFontString(nil, "OVERLAY")
    context.Text:SetPoint("BOTTOM")
    context.Text:SetJustifyH("CENTER")
    context.Text:SetWordWrap(false)
    context:Hide()
    self.mapContextLabel = context

    for _, overlay in ipairs(WorldMapFrame.overlayFrames) do
        if overlay.PlayerCoords then
            local suffix = self:NewFrame("Frame", "ForeverRosettaStonePlayerLocation", overlay.PlayerCoords)
            suffix:SetSize(1, 1)
            suffix:SetPoint("LEFT", overlay.PlayerCoords.Label, "RIGHT", 0, 0)
            suffix.Text = suffix:CreateFontString(nil, "OVERLAY")
            suffix.Text:SetPoint("LEFT")
            suffix.Text:SetWordWrap(false)
            suffix:Hide()
            self.playerLocationLabel = suffix
            break
        end
    end
end

function Addon:ShowMapContext()
    local context, suffix = self.mapContextLabel, self.playerLocationLabel

    if not WorldMapFrame:IsShown() then
        context:Hide()
        suffix:Hide()
        return
    end

    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if self:IsDebugPicking() and info then self:RecordDebugSurface(WorldMapFrame, "map", mapID, "mapContext", info,
        ForeverRosettaStoneDB:GetMapName(mapID, self:GetTargetLocale())) end
    local path = {}

    while info do
        table.insert(path, 1, ForeverRosettaStoneDB:GetMapName(info.mapID, self:GetTargetLocale())
            or info.name)

        if info.mapType <= Enum.UIMapType.Continent or info.parentMapID == 0 then break end

        info = C_Map.GetMapInfo(info.parentMapID)
    end

    context:Hide()
    if self:IsFeatureEnabled("mapContext") and not SettingsPanel:IsShown() and #path > 0 then
        for provider in pairs(WorldMapFrame.dataProviders) do
            local native = provider.Label
            if native and native.Name then
                context:SetScale(native:GetEffectiveScale() / WorldMapFrame:GetEffectiveScale())
                context:SetFrameStrata(native:GetFrameStrata())
                context:SetFrameLevel(native:GetFrameLevel() + 1)
                context:ClearAllPoints()
                context:SetPoint("BOTTOM", native.Name, "TOP", 0, 8)
                self:CopyQuestTextStyle(context.Text, native.Description, self:GetTargetLocale())
                context.Text:SetTextColor(native.Name:GetTextColor())
                context.Text:SetWidth(WorldMapFrame:GetCanvasContainer():GetWidth()
                    * WorldMapFrame:GetCanvasContainer():GetEffectiveScale() / context:GetEffectiveScale() - 32)
                context.Text:SetText(table.concat(path, " - "))
                context:Show()
                break
            end
        end
    end

    local native = suffix:GetParent()
    local playerMapID = C_Map.GetBestMapForUnit("player")
    local playerInfo = playerMapID and C_Map.GetMapInfo(playerMapID)
    local name = playerInfo and ForeverRosettaStoneDB:GetMapName(playerMapID, self:GetTargetLocale())
    local sourceText = native.Label and native.Label:GetText()
    if playerInfo and native:IsVisible() then
        self:RecordDebugSurface(native, "playerLocation", playerMapID, "playerLocation", sourceText, name)
    end

    if self:IsFeatureEnabled("playerLocation") and native:IsVisible() and name and sourceText
        and type(playerInfo.name) == "string" and sourceText:find(playerInfo.name, 1, true) then
        self:CopyQuestTextStyle(suffix.Text, native.Label, self:GetTargetLocale())
        suffix.Text:SetTextColor(1, 1, 1)
        suffix.Text:SetText(" - " .. name)
        suffix:Show()
    else
        suffix:Hide()
    end
end

local trackingLabels = {
    Auctioneer = "Auctioneer", Banker = "Banker", Battlemaster = "Battlemaster",
    TaxiNode = "Flight Master", Innkeeper = "Innkeeper", Mailbox = "Mailbox",
    TrainerClass = "Class Trainer", TrainerProfession = "Profession Trainers",
    Repair = "Repair", Stablemaster = "Stable Master", TrivialQuests = "Low Level Quests",
}

function Addon:GetTrackingMenuName(description)
    local info = description:GetData()
    if type(info) ~= "table" or not info.index then return end

    local locale = self:GetTargetLocale()
    local name = info.spellID and ForeverRosettaStoneDB:GetSpellName(info.spellID, locale)
    if name then return name end
    if locale ~= "enUS" then return end

    local filter = C_Minimap.GetTrackingFilter(info.index)
    if not filter then return end

    for key, label in pairs(trackingLabels) do
        if filter.filterID == Enum.MinimapTrackingFilter[key] then return label end
    end
end

function Addon:RegisterMapMenuTranslations()
    local function RegisterMenu(tag, feature, getName, isOwner)
        Menu.ModifyMenu(tag, self:Wrap("menu translations", function(owner, root)
            if owner and owner:IsForbidden() then return end
            if isOwner and not isOwner(owner) then return end
            root:SetTooltipFrame(self.mapMenuTooltip)
            local currentRow
            root:AddMenuReleasedCallback(self:Wrap("menu closed", function()
                if self.mapMenuTooltipRow == currentRow then
                    self.refreshMapMenuTooltip, self.mapMenuTooltipRow = nil, nil
                end
                currentRow = nil
                self.mapMenuTooltip:Hide()
                self.mapMenuTooltip:SetWindow(nil)
            end))

            local function HookElements(parent)
                for _, description in parent:EnumerateElementDescriptions() do
                    local function Render(row)
                        self.mapMenuTooltip:Hide()
                        if row:IsForbidden() or not row:IsVisible() or not self:IsFeatureEnabled(feature)
                            or self:IsTooltipBlocked() then return end

                        local name = getName(description)
                        local nativeText = MenuUtil.GetElementText(description)
                        if nativeText then self:RecordDebugSurface(row, feature, nativeText, feature, nativeText, name) end
                        if not name then return end

                        MenuUtil.ShowTooltipEx(row, self.mapMenuTooltip, function(tip)
                            tip:SetOwner(row, "ANCHOR_NONE")
                            tip:SetWindow(row:GetWindow())
                            self:AnchorCompanionTooltip(tip, row)
                            tip:ClearLines()
                            self:SetStandaloneTooltipTitle(tip, name, 1, 0.82, 0)
                            self:ApplyTooltipTranslationFont(tip, self:GetTargetLocale())
                        end)
                        self:PlaceCompanionTooltip(self.mapMenuTooltip, row, nil, true)
                    end
                    description:HookOnEnter(self:Wrap("menu hover", function(row)
                        currentRow = row
                        self.mapMenuTooltipRow = row
                        self.refreshMapMenuTooltip = function() Render(row) end
                        Render(row)
                    end))
                    description:HookOnLeave(self:Wrap("menu leave", function(row)
                        if self.mapMenuTooltipRow == row then
                            self.refreshMapMenuTooltip, self.mapMenuTooltipRow = nil, nil
                        end
                        if currentRow == row then currentRow = nil end
                    end))
                    HookElements(description)
                end
            end
            HookElements(root)
        end))
    end

    RegisterMenu("MENU_MINIMAP_BATTLEFIELD", "mapDropdown", function(description)
        return self:GetClientMapLocationName(MenuUtil.GetElementText(description))
    end, function(owner)
        -- NavigationBar shares this tag with unrelated menus.
        while owner and owner ~= WorldMapFrame.NavBar do
            if owner:IsForbidden() then return false end
            owner = owner:GetParent()
        end
        return owner ~= nil
    end)
    RegisterMenu("MENU_MINIMAP_TRACKING", "trackingMenu", function(description)
        return self:GetTrackingMenuName(description)
    end)
end

function Addon:Layout()
    local edge, simpleMapBounds = GetMapEdge(self.playerLocationLabel)
    local details = QuestMapFrame.DetailsFrame
    for _, frame in ipairs({ self.panel, self.toggle }) do
        frame:SetScale(details:GetEffectiveScale() / frame:GetParent():GetEffectiveScale())
        frame:SetFrameStrata(WorldMapFrame:GetFrameStrata())
    end

    self.panel:SetAlpha(WorldMapFrame:GetAlpha())

    local lore = _G.SpokenPlacesPanel
    local beside = lore and lore:IsVisible() and lore or edge
    local frontLevel = WorldMapFrame:GetFrameLevel()
    local frontStrata = WorldMapFrame:GetFrameStrata()
    for _, neighbor in ipairs({ edge, beside, details }) do
        for _, layer in pairs({ neighbor, neighbor.NineSlice, neighbor.TitleContainer }) do
            frontLevel = math.max(frontLevel, layer:GetFrameLevel())
            local strata = layer:GetFrameStrata()
            if STRATA_ORDER[strata] > STRATA_ORDER[frontStrata] then frontStrata = strata end
        end
    end
    local panelLevel = frontLevel + 20
    self.panel:SetFrameStrata(frontStrata)
    self.panel:SetFrameLevel(panelLevel)
    self.panel:SetFrameLevelsFromBaseLevel(panelLevel)
    self.toggle:SetFrameLevel(details:GetFrameLevel() + 1)
    local mapBounds = simpleMapBounds or GetPanelBounds(edge)
    local besideBounds = beside == edge and mapBounds or GetPanelBounds(beside)
    local nativeTop = details:GetTop()

    if not (mapBounds and besideBounds and nativeTop) then return end

    local panelScale = self.panel:GetEffectiveScale()
    local shellLayout = NineSliceUtil.GetLayout(self.panel.layoutType)
    local gap = beside == edge and (simpleMapBounds and 0 or PANEL_GAP)
        or (besideBounds.left - mapBounds.right) / panelScale
    local shellTop = mapBounds.top - SHELL_BORDER.top * panelScale
    local border = beside.NineSlice
    local mapPadding = beside == edge and not simpleMapBounds and not (border and border.BottomRightCorner)
        and MAP_BORDER_CLEAR or 0
    local offsetX = (besideBounds.right - beside:GetRight() * beside:GetEffectiveScale()) / panelScale
        + gap + SHELL_BORDER.left - mapPadding
    local offsetY = (shellTop - beside:GetTop() * beside:GetEffectiveScale()) / panelScale
    self.panel:ClearAllPoints()
    local panelWidth = details:GetWidth() + SHELL_INSETS.left + SHELL_INSETS.right
    local screenRight = UIParent:GetWidth() * UIParent:GetEffectiveScale()
    if simpleMapBounds and besideBounds.right + (gap + SHELL_BORDER.left + panelWidth) * panelScale > screenRight then
        -- Screen clamping on the right would push the reader over the native quest controls.
        self.panel:SetPoint("TOPRIGHT", details, "TOPLEFT", -SHELL_INSETS.left,
            (shellTop - nativeTop * details:GetEffectiveScale()) / panelScale)
    else
        self.panel:SetPoint("TOPLEFT", beside, "TOPRIGHT", offsetX, offsetY)
    end

    local contentTop = (nativeTop * details:GetEffectiveScale() - shellTop) / panelScale
    local shellBottom = mapBounds.bottom
    if simpleMapBounds and details.BorderFrame and details.BorderFrame:IsVisible() then
        -- The native quest border ends above the action buttons, which the reader doesn't draw.
        local rimBottom, rimScale = details.BorderFrame:GetBottom(), details.BorderFrame:GetEffectiveScale()
        if canaccessallvalues(rimBottom, rimScale) and rimBottom
            and rimBottom * rimScale < nativeTop * details:GetEffectiveScale() then
            shellBottom = math.max(shellBottom, rimBottom * rimScale - SHELL_INSETS.bottom * panelScale)
        end
    end
    local shellHeight = (shellTop - shellBottom) / panelScale + shellLayout.BottomRightCorner.y
    self.panel.Content:SetSize(details:GetSize())
    self.panel.Content:ClearAllPoints()
    self.panel.Content:SetPoint("TOPLEFT", self.panel, "TOPLEFT", SHELL_INSETS.left,
        contentTop)
    self.panel:SetSize(panelWidth, shellHeight)
    self.page.bottomLimit = shellLayout.BottomRightCorner.y - shellHeight + SHELL_INSETS.bottom - contentTop
    self:FitQuestPanelTitle(self.panel)

    if details.BorderFrame then
        self:CopyQuestFrameLayout(self.panel.BorderFrame, details.BorderFrame, nil, self.page.bottomLimit)
    end

    local loreToggle = _G.SpokenPlacesPanelToggle
    self.toggle:ClearAllPoints()

    if loreToggle and loreToggle:IsVisible() then
        local toggleLeft = (mapBounds.right - loreToggle:GetLeft() * loreToggle:GetEffectiveScale()) / panelScale
        self.toggle:SetPoint("TOPLEFT", loreToggle, "BOTTOMLEFT", toggleLeft - 2, -8)
    else
        local toggleLeft = (mapBounds.right - edge:GetRight() * edge:GetEffectiveScale()) / panelScale
        self.toggle:SetPoint("TOPLEFT", edge, "TOPRIGHT", toggleLeft - 2, -88)
    end

    self.page:RefreshNativeLayout()
end

function Addon:Render()
    local current = self.current
    local started = (current.mode == "open" or current.mode == "reading") and self:BeginBenchmarkSample() or nil
    local quest = current.questID and self:GetQuest(current.questID)
    local missingText = not quest and self:GetMissingQuestText()
    self.panel:SetTitle(quest and self:GetTranslationLanguageLabel() or "Forever Rosetta Stone")
    local visible = current.mode == "open" or current.mode == "reading"
    if visible then self:RecordDebugSurface(self.panel, "quest", current.questID, "questPanel", nil, quest) end
    self.panel:SetShown(visible)
    self.toggle:SetShown(self:IsPanelCollapsed())
    self.panel.ReportButton:SetShown(visible)

    if current.mode == "unavailable" then return end

    self:Layout()
    local progress = quest and self:GetProgressText(current.questID) or ""
    local contentKey = current.questID .. ":" .. self:GetTargetLocale() .. ":" .. progress

    if self.contentKey ~= contentKey then
        local title, objectives, description
        if quest then
            title = self:FormatQuestText(quest.title, current.questID)
            objectives = self:FormatQuestText(quest.summary, current.questID)
            description = self:FormatQuestText(quest.description, current.questID)
            if not title and C_QuestLog.GetTitleForQuestID then
                title = C_QuestLog.GetTitleForQuestID(current.questID)
            end
            if (not objectives or not description) and C_QuestLog.GetLogIndexForQuestID
                and C_QuestLog.GetQuestIDForLogIndex and GetQuestLogQuestText then
                local index = C_QuestLog.GetLogIndexForQuestID(current.questID)
                if type(index) == "number" and index > 0
                    and C_QuestLog.GetQuestIDForLogIndex(index) == current.questID then
                    local nativeDescription, nativeObjectives = GetQuestLogQuestText(index)
                    objectives = objectives or nativeObjectives
                    description = description or nativeDescription
                end
            end
        end
        self.page:Show({
            questID = current.questID,
            missing = not quest,
            title = quest and (title or "") or missingText.title,
            objectives = quest and (objectives or "") or missingText.summary,
            progress = quest and progress or (missingText.questID .. current.questID),
            reward = not quest and missingText.beer or nil,
            description = quest and (description or "") or missingText.description,
        })
        self.page.body:ScrollTo(0)
        self.contentKey = contentKey
    end
    self:EndBenchmarkSample("quest.panel", current.questID, started, quest ~= nil)
end

function Addon:ShowMapLocationLabel()
    local frame = self.mapLocationLabel
    if not frame then return end

    local enabled = self:IsFeatureEnabled("mapLocationLabel")
    if (enabled or self:IsDebugPicking()) and WorldMapFrame:IsShown() then
        for provider in pairs(WorldMapFrame.dataProviders) do
            local native = provider.Label
            local nativeName = native and native.Name and native.Name:GetText()
            local description = native and native.Description and native.Description:GetText()
            local name = nativeName and self:GetHoveredMapLocationName(nativeName)
            if nativeName and native:IsVisible() then self:RecordDebugSurface(native, "area",
                nativeName, "mapLocationLabel", { name = nativeName, description = description }, { name = name }) end

            if enabled and name and native:IsVisible() then
                local anchor = description and description ~= "" and native.Description or native.Name
                frame:SetScale(native:GetEffectiveScale() / WorldMapFrame:GetEffectiveScale())
                frame:SetFrameStrata(native:GetFrameStrata())
                frame:SetFrameLevel(native:GetFrameLevel() + 1)
                frame:SetAlpha(native:GetAlpha())
                frame:ClearAllPoints()
                frame:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
                self:CopyQuestTextStyle(frame.Text, native.Description, self:GetTargetLocale())
                frame.Text:SetTextColor(native.Name:GetTextColor())
                frame.Text:SetText(name)
                frame:Show()
                return
            end
        end
    end

    frame:Hide()
end

function Addon:ShowLocationTooltip()
    local tip = self.locationTooltip
    local questList = QuestMapFrame.QuestsFrame.ScrollFrame

    local enabled = self:IsFeatureEnabled("locationTooltip")
    if self:IsTooltipHoldHidden() or (not enabled and not self:IsDebugPicking()) or not questList:IsVisible()
        or (GameMenuFrame and GameMenuFrame:IsShown())
        or (self.errorDialog and self.errorDialog.frame:IsShown() and not self:IsDebugPicking()) then
        tip:Hide()
        return false
    end

    local header, name = self:GetTooltipFocus(function(owner)
        return ResolveLocationHeader(owner, questList)
    end, questList)

    local areaInfo = self:IsDebugPicking() and header and C_QuestLog.GetInfo(header.questLogIndex)
    if areaInfo then
        local areaID = self:GetQuestHeaderAreaID(areaInfo)
        self:RecordDebugSurface(header, "area", areaInfo.title, "locationTooltip", {
            title = areaInfo.title,
            questLogIndex = header.questLogIndex,
            questLogInfo = areaInfo,
            areaID = areaID,
            sortKeyAreaName = areaID and C_Map.GetAreaInfo(areaID) or nil,
        }, name)
    end
    if not enabled or not name then
        tip:Hide()
        return false
    end

    tip:SetScale(header:GetEffectiveScale() / UIParent:GetEffectiveScale())
    tip:SetOwner(header, "ANCHOR_NONE")
    tip:ClearAllPoints()
    self:AnchorCompanionTooltip(tip, header)
    tip:ClearLines()
    self:SetStandaloneTooltipTitle(tip, name, 1, 0.82, 0)
    self:ApplyTooltipTranslationFont(tip, self:GetTargetLocale())
    tip:Show()
    self:PlaceCompanionTooltip(tip, header)
    if areaInfo then
        self:RecordDebugRenderedTooltip({ kind = "area", id = areaInfo.title, name = name,
            tip = tip, context = "locationTooltip" })
    end
    return true
end

local function PlaceHeaderWithQuestTooltip(self)
    local header = self.locationTooltip
    if not header:IsShown() then return end
    local occupied = {self:GetTooltipRect(GameTooltip)}
    if self.tooltip:IsShown() then occupied[#occupied + 1] = self:GetTooltipRect(self.tooltip) end
    -- Keep the independently selected header clear of the hovered quest's tooltips.
    for _, side in ipairs({"top", "bottom", "left", "right"}) do
        self:PlaceCompanionTooltip(header, GameTooltip, occupied, false, nil, {
            GetSide = function() return side end,
        })
        if header:IsShown() then return end
    end
end

function Addon:GetQuestListTooltipQuestID(owner)
    if not WorldMapFrame:IsShown() then return end
    local questList = QuestMapFrame.QuestsFrame.ScrollFrame
    if not questList:IsVisible() then return end
    local questID
    while owner and owner ~= questList do
        if owner:IsForbidden() then return end
        questID = questID or owner.questID or (owner.info and owner.info.questID)
        owner = owner:GetParent()
    end
    if owner == questList then return questID end
end

function Addon:ShowTranslationTooltip()
    local tip = self.tooltip

    if self:IsTooltipHoldHidden() then
        if not GameTooltip:IsForbidden() then self:ClearStackedTooltip(GameTooltip, false, tip) end
        tip:Hide()
        self.locationTooltip:Hide()
        return
    end

    if GameTooltip:IsForbidden() then
        tip:Hide()
        self.locationTooltip:Hide()
        return
    end

    local owner = GameTooltip:GetOwner()
    if owner and owner:IsForbidden() then
        tip:Hide()
        self.locationTooltip:Hide()
        return
    end
    local mapPin = GameTooltip:IsShown() and owner and owner.pinTemplate == "QuestPinTemplate" and owner

    if mapPin then
        self.locationTooltip:Hide()
        if not self:IsFeatureEnabled("mapQuestTooltip") then
            self:ClearStackedTooltip(GameTooltip)
            tip:Hide()
            return
        end
    else
        self:ShowLocationTooltip()
    end

    if not GameTooltip:IsShown() or not WorldMapFrame:IsShown() then
        tip:Hide()
        return
    end

    local questID

    if mapPin then
        if not mapPin:IsVisible() or mapPin:GetMap() ~= WorldMapFrame then
            tip:Hide()
            return
        end

        questID = mapPin:GetQuestID()
    else
        questID = self:GetQuestListTooltipQuestID(owner)
        if not questID then
            tip:Hide()
            return
        end

        if not self:IsFeatureEnabled("questTooltip") then
            self:ClearStackedTooltip(GameTooltip)
            tip:Hide()
            return
        end
    end

    local quest = questID and self:GetQuest(questID)
    if questID then self:RecordDebugSurface(GameTooltip, "quest", questID,
        mapPin and "mapQuestTooltip" or "questTooltip", nil, quest) end

    if not quest then
        self:ClearStackedTooltip(GameTooltip)
        tip:Hide()
        return
    end

    local title = self:FormatQuestText(quest.title, questID)
    if not title then
        self:ClearStackedTooltip(GameTooltip)
        tip:Hide()
        return
    end

    local completed = C_QuestLog.IsComplete(questID)
    local readyForTurnIn = not mapPin and completed
    local progress = completed and "" or self:GetProgressText(questID)
    local red, green, blue = 1, 0.82, 0

    if mapPin then
        red, green, blue = 1, 1, 1
        local difficulty = QuestUtilsOverrides.GetQuestTitleDifficultyColor(questID)

        if difficulty then red, green, blue = difficulty:GetRGB() end
    end

    local coverage = self:GetTooltipCoverage(mapPin and "mapQuest" or "quest")
    local key = table.concat({mapPin and "map" or "list", questID, self:GetTargetLocale(), coverage,
        tostring(readyForTurnIn), progress, red, green, blue}, ":")

    if self.tooltipKey ~= key or not tip:IsShown() then
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:ClearLines()
        self:CopyCompanionTooltipStyle(tip, GameTooltip)
        self:SetCompanionTooltipTitle(tip, title, red, green, blue)

        if coverage == "full" then
            local details = readyForTurnIn and self:GetQuestTurnInText(questID)
            if not readyForTurnIn and not mapPin and quest.summary then
                details = self:FormatQuestText(quest.summary, questID)
            end
            if details then
                tip:AddLine(" ")
                tip:AddLine(details, 1, 1, 1, true)
                if not readyForTurnIn then tip:AddLine(" ") end
            end
            for line in progress:gmatch("[^\n]+") do
                tip:AddLine("- " .. line, 1, 1, 1, true)
            end
        end

        self:ApplyTooltipTranslationFont(tip, self:GetTargetLocale())
        self.tooltipKey = key
    end

    if self:GetTooltipPresentation(GameTooltip) ~= "separate" then
        self:FillStackedTooltip(GameTooltip, tip, "quest:" .. key)
        PlaceHeaderWithQuestTooltip(self)
        return
    end

    tip:SetScale(GameTooltip:GetEffectiveScale() / UIParent:GetEffectiveScale())
    tip:ClearAllPoints()
    self:AnchorCompanionTooltip(tip, GameTooltip)
    tip:SetClampedToScreen(true)
    tip:Show()
    self:PlaceCompanionTooltip(tip, GameTooltip)
    PlaceHeaderWithQuestTooltip(self)
end
