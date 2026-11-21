local _, Addon = ...

local kinds = { "item", "spell", "quest", "recipe", "comparison" }
local examples = { item = 117, spell = 133, quest = 783, recipe = 7418, comparison = 19019 }
local linkTypes = { item = "item", spell = "spell", quest = "quest", recipe = "enchant", comparison = "item" }
local previewState = "idle"
local previewTransitions = {
    idle = { start = "preview" },
    preview = { ["return"] = "idle", dismiss = "idle" },
}

function Addon:MoveDebugPreview(event)
    local nextState = previewTransitions[previewState][event]
    if not nextState then return false end
    previewState = nextState
    local dialog = self.errorDialog
    if event == "start" then
        dialog.frame:Hide()
        dialog.previewReturnPanel:Show()
    else
        dialog.previewReturnPanel:Hide()
        GameTooltip_HideShoppingTooltips(GameTooltip)
        GameTooltip_HideShoppingTooltips(ItemRefTooltip)
        GameTooltip:Hide()
        ItemRefTooltip:Hide()
        self:HideNameTooltips()
        self.debugPreviewSource, self.debugPreviewMode = nil, nil
        self.debugPreviewLink, self.debugPreviewKind = nil, nil
        if event == "return" then self:ShowDebugDisplay() end
    end
    self:SyncDebugController()
    return true
end

function Addon:RefreshDebugPreview()
    local source,link=self.debugPreviewSource,self.debugPreviewLink
    if previewState~="preview" or not source or not link or InCombatLockdown()
        or self.lifecycle~="ready" or not source:IsShown() or source:GetOwner()~=UIParent then return end
    source:SetHyperlink(link)
    source:Show()
    if self.debugPreviewKind=="comparison" then GameTooltip_ShowCompareItem(source) end
end

local function GetLink(kind, input)
    local linkType = linkTypes[kind]
    if not linkType then return end
    input = (input or ""):match("^%s*(.-)%s*$")
    if input == "" then input = tostring(examples[kind]) end
    local id = tonumber(input:match("^(%d+)$"))
    if id and id > 0 then
        return linkType .. ":" .. id .. (kind == "quest" and ":" .. UnitLevel("player") or "")
    end
    local link = input:match("|H([^|]+)|h") or input
    local actualType, linkID = link:match("^(%a+):(%d+)")
    if actualType == linkType and tonumber(linkID) > 0 and not link:find("[|%s]") then return link end
end

function Addon:DisplayDebugTooltip(kind, input, pinned)
    local dialog = self.errorDialog
    local function Refuse(key)
        if dialog then dialog.displayStatus:SetText(self:DebugText(key)) end
        return false
    end
    if InCombatLockdown() then return Refuse("displayCombat") end
    if self.lifecycle ~= "ready" then return Refuse("displayPaused") end
    local link
    if kind == "target" then
        if pinned then return Refuse("displayInvalid") end
        if not UnitExists("target") then return Refuse("displayNoTarget") end
    else
        link = GetLink(kind, input)
        if not link then return Refuse("displayInvalid") end
    end

    -- Native tooltips and their translation hooks must run outside the console overlay.
    if not self:MoveDebugPreview("start") then return false end
    local source = pinned and ItemRefTooltip or GameTooltip
    self.debugPreviewSource, self.debugPreviewMode = source, dialog.displayMode
    self.debugPreviewLink, self.debugPreviewKind = link, kind
    GameTooltip:Hide()
    if pinned then
        ItemRefTooltip:Hide()
        ItemRefTooltip:SetOwner(UIParent, "ANCHOR_NONE")
        ItemRefTooltip:ClearAllPoints()
        ItemRefTooltip:SetPoint("CENTER", UIParent, "CENTER")
        ItemRefTooltip:SetHyperlink(link)
        ItemRefTooltip:Show()
    else
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        if kind == "target" then GameTooltip:SetUnit("target")
        else GameTooltip:SetHyperlink(link) end
        GameTooltip:Show()
    end
    if kind == "comparison" then GameTooltip_ShowCompareItem(source) end
    return true
end

function Addon:CreateDebugDisplay(dialog, protect)
    local panel = CreateFrame("Frame", nil, dialog.window)
    panel:SetPoint("TOPLEFT", dialog.window, "TOPLEFT", 24, -78)
    panel:SetPoint("BOTTOMRIGHT", dialog.window, "BOTTOMRIGHT", -40, 60)
    panel:Hide()
    dialog.display, dialog.displayKind, dialog.displayKinds = panel, "item", {}
    dialog.displayMode = self.preferences.tooltipMode
    local function Button(parent, text, x, y, width, callback, height)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        button:SetSize(width, height or 28)
        button:SetText(text)
        button:SetScript("OnClick", protect(callback))
        button.OnSmartNavClick = button:GetScript("OnClick")
        return button
    end
    local function SideTab(key, icon, index)
        local tab = CreateFrame("CheckButton", nil, dialog.window, "LargeSideTabButtonTemplate")
        tab:SetPoint("TOPLEFT", dialog.window, "TOPRIGHT", -2, -70 - (index - 1) * 56)
        tab.Icon:SetTexture(icon)
        tab:SetFillToInterior(true, 50)
        tab:SetChecked(false)
        tab:SetScript("OnEnter", protect(function()
            local tip = self:GetWidgetTooltip()
            tip:SetOwner(tab, "ANCHOR_RIGHT")
            tip:SetText(self:DebugText(key))
            tip:Show()
        end))
        tab:SetScript("OnLeave", protect(function()
            local tip = self:GetWidgetTooltip()
            if tip:IsOwned(tab) then tip:Hide() end
        end))
        return tab
    end
    -- Tabs follow the player's goal: report a problem, test a tooltip, then advanced commands.
    local capturesTab = SideTab("captures", [[Interface\Icons\INV_Misc_Note_01]], 1)
    capturesTab:SetScript("OnClick", protect(function() self:ShowDebugView("report") end))
    capturesTab.OnSmartNavClick = capturesTab:GetScript("OnClick")
    local toggle = SideTab("display", [[Interface\Icons\INV_Misc_Spyglass_03]], 2)
    toggle:SetScript("OnClick", protect(function() self:ShowDebugDisplay() end))
    toggle.OnSmartNavClick = toggle:GetScript("OnClick")
    local consoleTab = SideTab("consoleTab", [[Interface\Icons\INV_Misc_Book_09]], 3)
    consoleTab:SetScript("OnClick", protect(function() self:ShowDebugView("console") end))
    consoleTab.OnSmartNavClick = consoleTab:GetScript("OnClick")
    dialog.capturesTab, dialog.displayToggle, dialog.consoleTab = capturesTab, toggle, consoleTab

    local function Highlight(buttons, selected)
        for key, button in pairs(buttons) do
            if key == selected then button:LockHighlight() else button:UnlockHighlight() end
        end
    end
    local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", panel, "TOPLEFT", 242, 0)
    dialog.displayLabel = label
    local input = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", panel, "TOPLEFT", 248, -26)
    input:SetSize(330, 28)
    input:SetAutoFocus(false)
    input:SetTextColor(1, 1, 1, 1)
    dialog.displayInput = input
    dialog.SelectDisplayKind = function(kind, keepInput)
        dialog.displayKind = kind
        label:SetText(self:DebugText(kind) .. " · " .. self:DebugText("displayInput"))
        if not keepInput then input:SetText(tostring(examples[kind])) end
        Highlight(dialog.displayKinds, kind)
    end
    for index, kind in ipairs(kinds) do
        dialog.displayKinds[kind] = Button(panel, self:DebugText(kind), 0, -(index - 1) * 36, 210, function()
            dialog.SelectDisplayKind(kind)
            dialog.displayStatus:SetText(self:DebugText("displayHint"))
            self:RefreshDebugPickedList()
        end)
    end
    local function Display(pinned)
        input:ClearFocus()
        self:DisplayDebugTooltip(dialog.displayKind, input:GetText(), pinned)
    end
    input:SetScript("OnEnterPressed", protect(function() Display(false) end))
    input:SetScript("OnEscapePressed", protect(function() input:ClearFocus() end))
    SmartNavigation_MarkFrameIgnored(input)
    -- One primary action; the others are secondary and grouped on one row.
    dialog.displayShow = Button(panel, self:DebugText("displayShow"), 242, -66, 520,
        function() Display(false) end, 34)
    dialog.displayPin = Button(panel, self:DebugText("displayPin"), 242, -110, 166, function() Display(true) end)
    dialog.displayTarget = Button(panel, self:DebugText("displayTarget"), 419, -110, 166,
        function() self:DisplayDebugTooltip("target") end)
    dialog.displayHide = Button(panel, self:DebugText("displayHide"), 596, -110, 166,
        function() GameTooltip:Hide(); ItemRefTooltip:Hide(); self:HideNameTooltips() end)
    local modeLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 242, -158)
    modeLabel:SetText(self:DebugText("previewLayout"))
    local modes = {}
    local function SelectMode(mode)
        dialog.displayMode = mode
        Highlight(modes, mode)
    end
    dialog.displaySeparate = Button(panel, self:DebugText("previewSeparate"), 242, -180, 255,
        function() SelectMode("separate") end)
    dialog.displayStacked = Button(panel, self:DebugText("previewStacked"), 507, -180, 255,
        function() SelectMode("stacked") end)
    modes.separate, modes.stacked = dialog.displaySeparate, dialog.displayStacked
    dialog.SelectDisplayMode = SelectMode
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 242, -230)
    status:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    status:SetJustifyH("LEFT")
    dialog.displayStatus = status
    dialog.SelectDisplayKind("item")
    SelectMode(dialog.displayMode)

    local returnPanel = CreateFrame("Frame", "ForeverRosettaStonePreviewReturn", UIParent)
    returnPanel:SetSize(280, 32)
    returnPanel:SetPoint("TOP", UIParent, "TOP", 0, -35)
    returnPanel:SetFrameStrata("TOOLTIP")
    returnPanel:SetFrameLevel(9100)
    returnPanel:Hide()
    table.insert(UISpecialFrames, returnPanel:GetName())
    local returnButton = Button(returnPanel, self:DebugText("previewReturn"), 0, 0, 280,
        function() self:MoveDebugPreview("return") end)
    returnButton:SetAllPoints(returnPanel)
    returnPanel:SetScript("OnHide", protect(function() self:MoveDebugPreview("return") end))
    returnPanel.FocusGamepad = protect(function() self:ClearGamepadTarget(returnPanel) end)
    returnPanel.SmartNavigationCloseHandler = protect(function() return self:MoveDebugPreview("return") end)
    local footer = Addon:CreateGamepadLegend(returnPanel, "ForeverRosettaStonePreviewFooter")
    footer:AddStandardSelectPrompt()
    footer:AddStandardBackPrompt(FRAME_ACTION_CLOSE)
    footer:Finalize()
    dialog.previewReturnPanel, dialog.previewReturn, dialog.previewFooter = returnPanel, returnButton, footer
    InputUtil.RegisterForInterfaceTransitions(returnPanel, protect(function() self:SyncDebugController() end))
    returnPanel:RegisterEvent("PLAYER_REGEN_ENABLED")
    returnPanel:RegisterEvent("MODIFIER_STATE_CHANGED")
    returnPanel:SetScript("OnEvent", protect(function(_,event)
        if event=="MODIFIER_STATE_CHANGED" then self:RefreshDebugPreview()
        else self:SyncDebugController() end
    end))
end

function Addon:ShowDebugDisplay()
    if self.InitializeSafetyMonitoring then self:InitializeSafetyMonitoring() end
    self:ShowDebugConsole(self:GetDebugWelcome(), nil, "display")
    local dialog = self.errorDialog
    dialog.SelectDisplayKind(dialog.displayKind, true)
    dialog.SelectDisplayMode(dialog.displayMode)
    dialog.displayStatus:SetText(self:DebugText("displayHint"))
    self:RefreshDebugPickedList()
    if dialog.controllerRegistered == dialog.window then
        self:ClearGamepadTarget(dialog.window)
    end
end
