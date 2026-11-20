local checks = 0
date = function() return "2026-11-11 12:00:00" end
GetBuildInfo = function() return "1.15.8", "test-build" end
local function equal(actual, expected, label)
    assert(actual == expected, (label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local function near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.000001,
        label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    checks = checks + 1
end

local Frame = {}
Frame.__index = Frame

function Frame:SetScript(name, handler) self.scripts[name] = handler end
function Frame:GetScript(name) return self.scripts[name] end
function Frame:HookScript(name, handler)
    local previous = self.scripts[name]
    self.scripts[name] = function(...)
        if previous then previous(...) end
        return handler(...)
    end
end
function Frame:Fire(name, ...)
    local result

    if self.scripts[name] then result = self.scripts[name](self, ...) end

    for _, callback in ipairs(self.callbacks[name] or {}) do
        callback.handler(callback.owner, ...)
    end

    return result
end
function Frame:RegisterCallback(name, handler, owner)
    self.callbacks[name] = self.callbacks[name] or {}
    table.insert(self.callbacks[name], { handler = handler, owner = owner })
end
function Frame:Show()
    if self.nativeTooltipLifetime and (not self.owner or not self.text) then
        self:Hide()
        return
    end
    local changed = not self.shown
    self.shown = true
    if changed then self:Fire("OnShow") end
end
function Frame:Hide()
    if self.nativeTooltipLifetime then
        self.text, self.owner = nil, nil
        self.lines = {}
    end
    local changed = self.shown
    self.shown = false
    if changed then self:Fire("OnHide") end
end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:GetParent() return self.parent end
function Frame:GetName() return self.name end
function Frame:SetID(value) self.id = value end
function Frame:GetID() return self.id or 0 end
function Frame:RegisterForClicks() end
function Frame:RegisterForDrag(...) self.dragButtons = {...} end
function Frame:SetMovable(value) self.movable = value end
function Frame:StartMoving() assert(self.movable, "frame must be movable"); self.moving = true end
function Frame:StopMovingOrSizing() self.moving = false end
function Frame:SetHitRectInsets(...) self.hitRectInsets = {...} end
function Frame:IsMouseOver() return self.mouseOver == true end
function Frame:SetBackdropColor(...) self.backdropColor = {...} end
function Frame:SetBackdropBorderColor(...) self.backdropBorderColor = {...} end
function Frame:SetAttribute(key, value) self.attributes[key] = value end
function Frame:ClearBindings() ClearOverrideBindings(self) end
function Frame:SetWidth(width) self.width = width end
function Frame:SetMinimumWidth(width) self.minimumWidth = width end
function Frame:SetHeight(height) self.height = height end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetPadding(right, bottom, left, top) self.padding = { right, bottom, left or 0, top or 0 } end
function Frame:ClearPadding() self.padding = nil end
function Frame:GetPadding() return unpack(self.padding or { 0, 0, 0, 0 }) end
function Frame:GetHeight() return self.height + (self.padding and self.padding[2] + self.padding[4] or 0) end
function Frame:GetWidth() return self.width + (self.padding and self.padding[1] + self.padding[3] or 0) end
function Frame:GetSize() return self.width, self.height end
function Frame:GetTop()
    if self.clamped and self.top then
        local _, _, top, bottom = self:GetClampRectInsets()
        local scale = self:GetEffectiveScale()
        return math.max(self.height - bottom, math.min(self.top, UIParent:GetHeight() * UIParent:GetEffectiveScale() / scale - top))
    end
    return self.top
end
function Frame:GetLeft()
    if self.clamped and self.left then
        local left, right = self:GetClampRectInsets()
        return math.max(-left, math.min(self.left,
            UIParent:GetWidth() * UIParent:GetEffectiveScale() / self:GetEffectiveScale() - self.width - right))
    end
    return self.left
end
function Frame:GetRight() return self.right or (self:GetLeft() and self:GetLeft() + self.width) end
function Frame:GetBottom() return self.bottom or (self:GetTop() and self:GetTop() - self.height) end
function Frame:SetScale(scale) self.scale = scale end
function Frame:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function Frame:GetScale() return self.scale end
function Frame:SetFrameStrata(strata) self.strata = strata end
function Frame:GetFrameStrata() return self.strata end
function Frame:SetFrameLevel(level) self.level = math.min(10000, level) end
function Frame:GetFrameLevel() return self.level end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:GetAlpha() return self.alpha end
function Frame:FadeOut() self:SetAlpha(1) end
function Frame:SetTitle(title)
    self.title = title
    self.TitleContainer.TitleText:SetText(title)
end
function Frame:GetStringWidth() return #(self:GetText() or "") * 6 end
function Frame:GetFontString()
    if not self.fontString then self.fontString = self:CreateFontString(nil, "OVERLAY") end
    return self.fontString
end
function Frame:GetUnboundedStringWidth() return self:GetStringWidth() end
function Frame:SetTitleOffsets(left, right)
    self.TitleContainer:ClearAllPoints()
    self.TitleContainer:SetPoint("TOPLEFT", self, "TOPLEFT", left, -1)
    self.TitleContainer:SetPoint("TOPRIGHT", self, "TOPRIGHT", right, -1)
end
function Frame:GetPortrait() return self.PortraitContainer.portrait end
function Frame:SetPortraitToAsset(texture) self:GetPortrait():SetTexture(texture) end
function Frame:SetPortraitTextureSizeAndOffset(size, x, y)
    self:GetPortrait():SetSize(size, size)
    self:GetPortrait():SetPoint("TOPLEFT", self, "TOPLEFT", x, y)
end
function Frame:SetBorder(layout) self.NineSlice.appliedLayout = layout end
function Frame:SetFrameLevelsFromBaseLevel(level)
    self.NineSlice:SetFrameLevel(level + 500)
    self.PortraitContainer:SetFrameLevel(level + 400)
    self.TitleContainer:SetFrameLevel(level + 510)
    self.CloseButton:SetFrameLevel(level + 510)
end
function Frame:SetText(text, ...)
    self.text = text
    self.titleColor = {...}
    if self.kind == "GameTooltip" and self.TextLeft1 then self.TextLeft1:SetText(text) end
    if self.accurateLines then self.lines = { text } end
    if self.kind == "EditBox" then self:Fire("OnTextChanged", false) end
end
function Frame:GetText() return self.text end
function Frame:SetChecked(value) self.checked = value end
function Frame:GenerateMenu()
    local root = { entries = {} }
    function root:CreateRadio(label, isSelected, onClick)
        self.entries[#self.entries + 1] = { label = label, isSelected = isSelected, onClick = onClick }
    end
    self.menuGenerator(self, root)
    self.menuDescription = root
end
function Frame:SetupMenu(generator) self.menuGenerator = generator; self:GenerateMenu() end
function Frame:GetChecked() return self.checked end
function Frame:SetPoint(...) self.points[#self.points + 1] = {...} end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetOwner(owner, anchor) self.owner, self.anchor = owner, anchor end
function Frame:SetInputKey(key) self.inputKey = key end
function Frame:GetAnchorType() return self.anchor end
function Frame:GetOwner() return self.owner end
function Frame:GetProcessingTooltipInfo() return self.processingInfo end
function Frame:SetWindow(window) self.window = window end
function Frame:GetWindow() return self.window end
function Frame:IsOwned(owner) return self.owner == owner end
function Frame:IsForbidden() return false end
function Frame:GetPoint(index) return unpack(self.points[index] or {}) end
function Frame:GetNumPoints() return #self.points end
function Frame:ClearLines() self.lines, self.lineColors = {}, {} end
function Frame:AddLine(text, ...)
    self.lines[#self.lines + 1] = text
    self.lineColors = self.lineColors or {}
    self.lineColors[#self.lines] = {...}
    local line = self:GetLeftLine(#self.lines)
    line:SetText(text)
    if select("#", ...) >= 3 then line:SetTextColor(...) end
    self:GetRightLine(#self.lines):SetText("")
end
function Frame:AddDoubleLine(left, right, ...)
    self.lines[#self.lines + 1] = { left = left, right = right, colors = {...} }
    self:GetLeftLine(#self.lines):SetText(left)
    self:GetRightLine(#self.lines):SetText(right)
end
function Frame:SetParent(parent) self.parent = parent end
function Frame:SetVerticalScroll(value)
    self.scroll = value
    self:Fire("OnVerticalScroll", value)
end
function Frame:GetVerticalScroll() return self.scroll or 0 end
function Frame:GetVerticalScrollRange()
    return math.max(0, (self.scrollChild and self.scrollChild:GetHeight() or 0) - self:GetHeight())
end
function Frame:UpdateScrollChildRect() self:Fire("OnScrollRangeChanged", 0, self:GetVerticalScrollRange()) end
function Frame:SetClipsChildren(value) self.clipsChildren = value end
function Frame:IsMaximized() return self.maximized end
function Frame:EnableGamePadButton(enabled) self.gamepadEnabled = enabled end
function Frame:IsGamePadButtonEnabled() return self.gamepadEnabled == true end
function Frame:SetNormalTexture(texture) self.normal = self:CreateTexture(); self.normal:SetTexture(texture) end
function Frame:GetNormalTexture() return self.normal end
function Frame:SetTexture(texture) self.texture = texture end
function Frame:GetTexture() return self.texture end
function Frame:SetVertexColor(...) self.vertexColor = {...} end
function Frame:GetVertexColor() return unpack(self.vertexColor or {1, 1, 1, 1}) end
function Frame:SetCenterColor(...) self.centerColor = {...} end
function Frame:GetCenterColor() return unpack(self.centerColor or {0.1, 0.1, 0.1, 1}) end
function Frame:SetBorderColor(...) self.borderColor = {...} end
function Frame:GetBorderColor() return unpack(self.borderColor or {1, 1, 1, 1}) end
function Frame:SetAtlas(atlas) self.atlas = atlas end
function Frame:GetAtlas() return self.atlas end
function Frame:SetTextureSliceMargins(...) self.sliceMargins = {...} end
function Frame:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function Frame:SetValue(value) self.value = value end
function Frame:SetStatusBarTexture(texture) self.statusBarTexture = texture end
function Frame:SetStatusBarColor(...) self.statusBarColor = {...} end
function Frame:GetTexCoord() return unpack(self.coords or {0, 1, 0, 1}) end
function Frame:SetTexCoord(...) self.coords = {...} end
function Frame:SetAllPoints(target) self.allPointsTarget = target end
function Frame:SetBackdrop(backdrop) self.backdrop = backdrop end
function Frame:SetMultiLine(value) self.multiLine = value end
function Frame:SetAutoFocus(value) self.autoFocus = value end
function Frame:SetMaxLetters(value) self.maxLetters = value end
function Frame:SetTextInsets() end
function Frame:SetClipsChildren(value) self.clipsChildren = value end
function Frame:SetDesaturated(value) self.desaturated = value end
function Frame:GetPrimaryTooltipData() return self.processingInfo and self.processingInfo.tooltipData end
function Frame:SetItemByID(id)
    self:ClearLines()
    self:AddLine("Viande séchée coriace", 1, 1, 1)
    self:AddLine(SPELL_PASSIVE, 0, 1, 0)
    self.processingInfo = { tooltipData = { id = id, type = Enum.TooltipDataType.Item, lines = {
        { type = Enum.TooltipDataLineType.ItemName, leftText = "Viande séchée coriace", lineIndex = 1 },
        { type = 0, leftText = SPELL_PASSIVE, lineIndex = 2 },
    } } }
    self:Show()
end
function Frame:HighlightText(start, finish) self.highlighted = not (start == 0 and finish == 0) end
function Frame:SetFocus() self.focused = true end
function Frame:ClearFocus() self.focused = false end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetEnabled(enabled) self.enabled = enabled and true or false end
function Frame:LockHighlight() self.highlightLocked = true end
function Frame:UnlockHighlight() self.highlightLocked = false end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:NumLines() return #self.lines end
-- Stacked translations are blanked in place, so rendered rows end at the last non-empty line.
function RenderedTooltipRows(tip)
    local rows = {}
    for index = 1, tip:NumLines() do
        local left, right = tip:GetLeftLine(index):GetText() or "", tip:GetRightLine(index):GetText() or ""
        if left ~= "" or right ~= "" then rows[#rows + 1] = left end
    end
    return rows
end
function VisibleTooltipLines(tip)
    local count = tip:NumLines()
    while count > 0 and (tip:GetLeftLine(count):GetText() or "") == "" and (tip:GetRightLine(count):GetText() or "") == "" do
        count = count - 1
    end
    return count
end
function Frame:GetLeftLine(index)
    local key = "TextLeft" .. index
    if not self[key] then self[key] = self:CreateFontString(nil, "ARTWORK") end
    return self[key]
end
function Frame:GetRightLine(index)
    local key = "TextRight" .. index
    if not self[key] then self[key] = self:CreateFontString(nil, "ARTWORK") end
    return self[key]
end
function Frame:SetFont(path, size, flags) self.font = {path, size, flags} end
function Frame:SetFontObject(font) self.fontObject, self.font = font, nil end
function Frame:GetFont()
    if self.font then return unpack(self.font) end
    local fontObject = type(self.fontObject) == "string" and _G[self.fontObject] or self.fontObject
    if type(fontObject) == "table" then return fontObject:GetFont() end
    if self.template and _G[self.template] then return _G[self.template]:GetFont() end
    return "Fonts/FRIZQT__.TTF", 14, ""
end
function Frame:GetTextScale() return self.textScale or 1 end
function Frame:SetTextScale(scale) self.textScale = scale end
function Frame:SetJustifyH(value) self.justifyH = value end
function Frame:GetJustifyH() return self.justifyH or "LEFT" end
function Frame:CanWordWrap() return self.wordWrap == true end
function Frame:SetJustifyV(value) self.justifyV = value end
function Frame:SetWordWrap(value) self.wordWrap = value end
function Frame:SetTextColor(...) self.textColor = {...} end
function Frame:GetTextColor() return unpack(self.textColor or {0, 0, 0, 1}) end
function Frame:SetShadowColor(...) self.shadowColor = {...} end
function Frame:GetShadowColor() return unpack(self.shadowColor or {0.49, 0.35, 0.05, 1}) end
function Frame:SetShadowOffset(...) self.shadowOffset = {...} end
function Frame:GetShadowOffset() return unpack(self.shadowOffset or {1, -1}) end
function Frame:SetSpacing(value) self.spacing = value end
function Frame:GetSpacing() return self.spacing or 0 end
function Frame:SetColorTexture(...) self.colorTexture = {...} end
function Frame:EnableMouseWheel(enabled) self.mouseWheelEnabled = enabled end
function Frame:SetScrollChild(child) self.scrollChild = child end
function Frame:UnregisterAllEvents() self.events = {} end
function Frame:GetStringHeight()
    if self.wordWrap == false then return select(2, self:GetFont()) end
    return math.ceil(#(self.text or "") / 35) * 17
end
function Frame:SetPushedTexture(texture)
    self.pushed = self:CreateTexture()
    self.pushed:SetTexture(texture)
end
function Frame:GetPushedTexture() return self.pushed end
function Frame:SetHighlightTexture() end
function Frame:SetClampedToScreen(value) self.clamped = value end
function Frame:IsClampedToScreen() return self.clamped == true end
function Frame:GetClampRectInsets() return unpack(self.clampInsets or { 0, 0, 25, 0 }) end
function Frame:SetClampRectInsets(...) self.clampInsets = { ... } end
function Frame:IsProtected() return self.protected == true end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:CreateTexture(name) return CreateFrame("Texture", name, self) end
function Frame:CreateFontString(name, _, template) return CreateFrame("FontString", name, self, template) end
function Frame:CreateMaskTexture() return CreateFrame("MaskTexture", nil, self) end
function Frame:AddMaskTexture(mask) self.mask = mask end

local frames = {}
function Frame:GetChildren()
    local children = {}
    for _, frame in ipairs(frames) do
        if frame.parent == self then children[#children + 1] = frame end
    end
    return unpack(children)
end
function Frame:GetRegions()
    local regions = {}
    for _, frame in ipairs(frames) do
        if frame.parent == self and (frame.kind == "Texture" or frame.kind == "FontString") then regions[#regions + 1] = frame end
    end
    return unpack(regions)
end
function Frame:GetObjectType() return self.kind end
function Frame:IsMouseEnabled() return self.mouseEnabled == true end
function Frame:IsMouseWheelEnabled() return self.mouseWheelEnabled == true end
function CreateFrame(kind, name, parent, template)
    local frame = setmetatable({
        kind = kind, name = name, parent = parent, template = template,
        shown = true, width = 300, height = (kind == "ScrollFrame" or kind == "EventScrollFrame") and 180 or 500, scale = 1,
        strata = "MEDIUM", level = math.min(10000, parent and (rawget(parent, "level") or 0) + 1 or 1), alpha = 1,
        scripts = {}, callbacks = {}, events = {}, points = {}, lines = {}, attributes = {},
    }, Frame)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    if template == "NewFeatureLabelTemplate" then
        frame.Label = frame:CreateFontString(nil, "OVERLAY")
        frame.Label:SetText("NEW")
    end
    if template == "GameTooltipTemplate" or template == "ShoppingTooltipTemplate"
        or template == "TooltipBackdropTemplate" then
        frame.TextLeft1 = frame:CreateFontString(nil, "ARTWORK")
        frame.TextLeft2 = frame:CreateFontString(nil, "ARTWORK")
        frame.NineSlice = CreateFrame("Frame", nil, frame)
        for _, piece in ipairs({"TopEdge", "BottomEdge", "TopLeftCorner", "TopRightCorner",
            "BottomLeftCorner", "BottomRightCorner", "LeftEdge", "RightEdge", "Center"}) do
            frame.NineSlice[piece] = frame.NineSlice:CreateTexture(nil, "BORDER")
        end
    end
    if template == "LargeSideTabButtonTemplate" then
        frame:SetSize(64, 53)
        frame.Icon = frame:CreateTexture(nil, "ARTWORK")
        function frame:SetFillToInterior(fill, extent)
            self.fillToInterior = fill
            self.interiorExtent = extent
            if fill then self.Icon:SetSize(extent or 50, extent or 50) end
        end
        frame.Background = frame:CreateTexture(nil, "BACKGROUND")
        frame.Background:SetAtlas("common-sidetab")
        frame.HighlightTexture = frame:CreateTexture(nil, "HIGHLIGHT")
        frame.HighlightTexture:SetAtlas("common-sidetab-hover")
        function frame:InitializeIconAnchoring()
            self.Icon:ClearAllPoints()
            self.Icon:SetPoint("CENTER", -3, 0)
        end
        frame:InitializeIconAnchoring()
        frame:SetScript("OnMouseDown", function(owner, button)
            if button == "LeftButton" then
                owner.Icon:ClearAllPoints()
                owner.Icon:SetPoint("CENTER", -2, -1)
            end
        end)
        frame:SetScript("OnMouseUp", function(owner, button)
            if button == "LeftButton" then owner:InitializeIconAnchoring() end
        end)
    end
    if template == "UICheckButtonTemplate" then frame.Text = frame:CreateFontString(nil, "ARTWORK") end
    if template == "ShoppingTooltipTemplate" then
        frame.CompareHeader = CreateFrame("Frame", nil, frame)
        frame.CompareHeader.Label = frame.CompareHeader:CreateFontString(nil, "OVERLAY")
    end
    if template == "SmallItemButtonTemplate" then
        frame.smallItemButton = true
        frame.Icon = CreateFrame("Texture", nil, frame)
        frame.Name = CreateFrame("FontString", nil, frame)
        frame.NameFrame = CreateFrame("Texture", nil, frame)
        frame.Count = CreateFrame("FontString", nil, frame)
    end
    if template == "ScrollFrameTemplate" then
        local bar = CreateFrame("Frame", nil, frame)
        frame.ScrollBar = bar
        bar.Track = CreateFrame("Frame", nil, bar)
        bar.Track.Thumb = CreateFrame("Button", nil, bar.Track)
        function bar:ScrollStepInDirection(direction)
            frame:SetVerticalScroll(math.max(0, math.min(frame:GetVerticalScrollRange(),
                frame:GetVerticalScroll() + direction * 30)))
        end
        frame:SetScript("OnMouseWheel", function(_, direction) bar:ScrollStepInDirection(-direction) end)
        frame:SetScript("OnVerticalScroll", function(_, offset)
            local range = frame:GetVerticalScrollRange()
            bar.scrollPercentage = range > 0 and offset / range or 0
        end)
        frame:SetScript("OnScrollRangeChanged", function() end)
    end
    if template == "FocusFramesInterfaceTemplate" or template == "DefaultPanelTemplate"
        or template == "ForeverRosettaStoneQuestPanelTemplate"
        or template == "DefaultPanelFlatTemplate" then
        frame.FrameGlow = CreateFrame("Frame", nil, frame)
        frame.FrameGlow.GlowTexture = CreateFrame("Texture", nil, frame.FrameGlow)
        if template == "ForeverRosettaStoneQuestPanelTemplate" then
            frame.FrameGlow.GlowTexture:SetAtlas("gamepad-uiframemetal-focus")
        end
        frame.FrameGlow:Hide()

        for _, key in ipairs({"LeftJumpHint", "RightJumpHint", "FocusJumpHint"}) do
            frame[key] = CreateFrame("Frame", nil, frame)
            frame[key]:Hide()
            frame["Show" .. key] = function(self) self[key]:Show() end
            frame["Hide" .. key] = function(self) self[key]:Hide() end
        end

        function frame:StartFocus() self.FrameGlow:Show() end
        function frame:EndFocus() self.FrameGlow:Hide() end
    end
    if template == "DefaultPanelTemplate" or template == "DefaultPanelFlatTemplate"
        or template == "ForeverRosettaStoneQuestPanelTemplate" or template == "PortraitFrameTemplateNoCloseButton" then
        frame.layoutType = "ButtonFrameTemplateNoPortrait"
        frame.NineSlice = CreateFrame("Frame", nil, frame)
        frame.NineSlice:SetFrameLevel(500)
        frame.TitleContainer = CreateFrame("Frame", nil, frame)
        frame.TitleContainer:SetFrameLevel(510)
        frame.TitleContainer.TitleText = CreateFrame("FontString", nil, frame.TitleContainer)
        if template == "ForeverRosettaStoneQuestPanelTemplate" or template == "PortraitFrameTemplateNoCloseButton" then
            frame.layoutType = "ButtonFrameTemplateNoPortrait"
            frame.NineSlice.appliedLayout = "ButtonFrameTemplateNoPortrait"
            frame.PortraitContainer = CreateFrame("Frame", nil, frame)
            frame.PortraitContainer:SetFrameLevel(400)
            frame.PortraitContainer.portrait = CreateFrame("Texture", nil, frame.PortraitContainer)
            frame.PortraitContainer.CircleMask = CreateFrame("MaskTexture", nil, frame.PortraitContainer)
        end
    end
    return frame
end

local panelLayout = { BottomRightCorner = { y = -3 } }
NineSliceUtil = {
    GetLayout = function(layoutType)
        assert(layoutType == "ButtonFrameTemplateNoPortrait", "expected the native border without a corner portrait")
        return panelLayout
    end,
}

local combat, style, selected = false, "1", 399
local playedSounds = {}
SOUNDKIT = { IG_QUEST_LOG_OPEN = 1, IG_QUEST_LOG_CLOSE = 2 }
function PlaySound(sound) playedSounds[#playedSounds + 1] = sound end
function ClearOverrideBindings() error("addon must not change controller overrides") end
function SetOverrideBindingClick() error("addon must not create controller overrides") end
local fulfilled, escortFinished = 0, false
local stoneFulfilled, fossilFulfilled = 0, 0
local questLogEntries = {}
local mouseFoci = {}
local mapDifficultyColor, showDifficultyColor = {1, 0.1, 0.1}, true
QuestUtilsOverrides = {
    GetQuestTitleDifficultyColor = function()
        if not showDifficultyColor then return nil end

        return { GetRGB = function() return unpack(mapDifficultyColor) end }
    end,
}
function GetMouseFoci() return mouseFoci end
function GetCursorPosition() return 0, 0 end
function InCombatLockdown() return combat end
function debugstack() return "stack line 1\nstack line 2" end
function DisplayInterfaceActionBlockedMessage() end
function GetCVar() return style end
local completedQuests = {}
C_QuestLog = {
    IsComplete = function(id) return completedQuests[id] == true end,
    GetInfo = function(index) return questLogEntries[index] end,
    GetSelectedQuest = function() return selected end,
    GetQuestObjectives = function(questID)
        if questID == 731 then return {{type = "event", finished = escortFinished}} end
        if questID == 943 then
            return {
                {type = "item", numFulfilled = stoneFulfilled, numRequired = 1},
                {type = "item", numFulfilled = fossilFulfilled, numRequired = 1},
            }
        end
        return {{type = "item", numFulfilled = fulfilled, numRequired = 1}}
    end,
}
SlashCmdList = {}
local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function flushTimers()
    local pending = timers
    timers = {}
    for _, callback in ipairs(pending) do callback() end
end
UIParent = CreateFrame("Frame", "UIParent")
Minimap = CreateFrame("Frame", "Minimap", UIParent)
UIParent:SetSize(1920, 1080)
WorldMapFrame = CreateFrame("Frame", "WorldMapFrame", UIParent)
WorldMapFrame:SetScale(0.8)
local viewedMapID, playerMapID = 1424, 1437
local mapInfo = {
    [947] = { name = "Azeroth", mapID = 947, parentMapID = 0, mapType = 0 },
    [1415] = { name = "Royaumes de l'est", mapID = 1415, parentMapID = 947, mapType = 2 },
    [1424] = { name = "Contreforts de Hautebrande", mapID = 1424, parentMapID = 1415, mapType = 3 },
    [1437] = { name = "Les Paluns", mapID = 1437, parentMapID = 1415, mapType = 3 },
    [9998] = { name = "Unknown place", mapID = 9998, parentMapID = 1415, mapType = 3 },
}
Enum = { UIMapType = { Continent = 2 } }
Enum.TooltipDataType = { Item = 0, Spell = 1, Quest = 23 }
Enum.TooltipDataType.Unit, Enum.TooltipDataType.MinimapMouseover = 2, 21
Enum.TooltipDataType.Mount, Enum.TooltipDataType.Toy = 10, 19
Enum.TooltipDataType.Object = 4
Enum.TooltipDataLineType = { ItemName = 22, SpellName = 13, UnitName = 2 }
local tooltipCallbacks = {}
local tooltipLineCallbacks = {}
TooltipDataProcessor = {
    AllTypes = "ALL",
    AddLinePostCall = function(kind, callback)
        tooltipLineCallbacks[kind] = tooltipLineCallbacks[kind] or {}
        table.insert(tooltipLineCallbacks[kind], callback)
    end,
    AddTooltipPostCall = function(kind, callback)
        assert(kind == "ALL")
        tooltipCallbacks[#tooltipCallbacks + 1] = callback
    end,
}
function canaccessallvalues(value) return type(value) ~= "table" or not value.secret end
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, callback, owner)
    self.callbacks[event] = self.callbacks[event] or {}
    table.insert(self.callbacks[event], { callback = callback, owner = owner })
end
function EventRegistry:TriggerEvent(event, ...)
    for _, entry in ipairs(self.callbacks[event] or {}) do entry.callback(entry.owner, ...) end
end
C_Map = {
    GetMapInfo = function(mapID) return mapInfo[mapID] end,
    GetBestMapForUnit = function(unit) assert(unit == "player"); return playerMapID end,
}
function WorldMapFrame:GetMapID() return viewedMapID end
local mapCanvas = CreateFrame("Frame", nil, WorldMapFrame)
mapCanvas.bottom = 0
function WorldMapFrame:GetCanvasContainer() return mapCanvas end
local coordsPanel = CreateFrame("Frame", nil, WorldMapFrame)
coordsPanel.PlayerCoords = CreateFrame("Frame", nil, coordsPanel)
local playerCoordsText = coordsPanel.PlayerCoords:CreateFontString(nil, "ARTWORK")
playerCoordsText:SetFont("Fonts/MapCoords.ttf", 10, "OUTLINE")
playerCoordsText:SetTextColor(1, 1, 1, 1)
playerCoordsText:SetText("Personnage : 10.7, 61.6 (Les Paluns)")
coordsPanel.PlayerCoords.Label = playerCoordsText
WorldMapFrame.overlayFrames = {coordsPanel}
WorldMapFrame.NavBar = CreateFrame("Frame", nil, WorldMapFrame)
local mapMenuArrow = CreateFrame("Button", nil, WorldMapFrame.NavBar)
local menuModifiers = {}
Menu = {
    ModifyMenu = function(tag, callback)
        menuModifiers[tag] = menuModifiers[tag] or {}
        table.insert(menuModifiers[tag], callback)
    end,
}
MenuUtil = {
    CreateContextMenu = function(owner, generator)
        local root = { entries = {} }
        function root:CreateTitle(label) self.entries[#self.entries + 1] = { kind = "title", label = label } end
        function root:CreateDivider() self.entries[#self.entries + 1] = { kind = "divider" } end
        function root:CreateButton(label, click)
            self.entries[#self.entries + 1] = { kind = "button", label = label, onClick = click }
        end
        function root:CreateRadio(label, selected, click)
            self.entries[#self.entries + 1] = { kind = "radio", label = label, isSelected = selected, onClick = click }
        end
        generator(owner, root)
        owner.contextMenu = root
    end,
    GetElementText = function(description) return description.text end,
    ShowTooltipEx = function(owner, tooltip, initializer, ...)
        tooltip:SetOwner(owner, "ANCHOR_RIGHT")
        tooltip:SetWindow(owner:GetWindow())
        initializer(tooltip, ...)
        tooltip:Show()
    end,
}
MenuResponse = { Refresh = 1 }
local function createMapMenu(owner, names, tag, data)
    local root = { elements = {}, released = {} }
    function root:EnumerateElementDescriptions() return ipairs(self.elements) end
    function root:SetTooltipFrame(tooltip) self.tooltip = tooltip end
    function root:AddMenuReleasedCallback(callback) table.insert(self.released, callback) end
    function root:Release()
        for _, callback in ipairs(self.released) do callback() end
    end

    for index, name in ipairs(names) do
        local element = { text = name, responder = function() return name end, nativeEnters = 0 }
        function element:GetData() return data and data[index] end
        function element:EnumerateElementDescriptions() return ipairs({}) end
        function element:HookOnEnter(callback)
            self.onEnter = function(row)
                self.nativeEnters = self.nativeEnters + 1
                callback(row)
            end
        end
        function element:Enter(row) if self.onEnter then self.onEnter(row) end end
        function element:Leave(row)
            if root.tooltip and root.tooltip:GetOwner() == row then
                root.tooltip:Hide()
                root.tooltip:SetWindow(nil)
            end
        end
        table.insert(root.elements, element)
    end

    for _, callback in ipairs(menuModifiers[tag or "MENU_MINIMAP_BATTLEFIELD"] or {}) do callback(owner, root) end

    return root
end
local nativeAreaLabel = CreateFrame("Frame", nil, WorldMapFrame)
nativeAreaLabel:SetScale(0.695)
nativeAreaLabel.Name = nativeAreaLabel:CreateFontString(nil, "OVERLAY")
nativeAreaLabel.Name:SetFont("Fonts/MapName.ttf", 22, "OUTLINE")
nativeAreaLabel.Name:SetText("")
nativeAreaLabel.Description = nativeAreaLabel:CreateFontString(nil, "OVERLAY")
nativeAreaLabel.Description:SetFont("Fonts/MapSubtitle.ttf", 16, "OUTLINE")
nativeAreaLabel.Description:SetText("")
local areaLabelProvider = { Label = nativeAreaLabel }
WorldMapFrame.dataProviders = { [areaLabelProvider] = true }
WorldMapFrame.MiniBorderFrame = CreateFrame("Frame", nil, WorldMapFrame)
QuestMapFrame = CreateFrame("Frame", "QuestMapFrame", WorldMapFrame)
QuestMapFrame.QuestsFrame = CreateFrame("Frame", nil, QuestMapFrame)
QuestMapFrame.QuestsFrame.ScrollFrame = CreateFrame("ScrollFrame", "QuestScrollFrame", QuestMapFrame.QuestsFrame)
QuestMapFrame.DetailsFrame = CreateFrame("Frame", nil, QuestMapFrame)
QuestMapFrame.DetailsFrame.questID = 399
QuestMapFrame.DetailsFrame.top = 760
QuestMapFrame.DetailsFrame.left = 700
QuestMapFrame.DetailsFrame.BorderFrame = CreateFrame("Frame", nil, QuestMapFrame.DetailsFrame)
QuestMapFrame.DetailsFrame.BorderFrame.left, QuestMapFrame.DetailsFrame.BorderFrame.top = 697, 764
QuestMapFrame.DetailsFrame.BorderFrame:SetSize(306, 487)
QuestMapFrame.DetailsFrame.BackFrame = CreateFrame("Frame", nil, QuestMapFrame.DetailsFrame)
WorldMapFrame.MiniBorderFrame.top = 800
WorldMapFrame.MiniBorderFrame.left, WorldMapFrame.MiniBorderFrame.right = 0, 1000
WorldMapFrame.MiniBorderFrame.bottom = 200
local mapBorder = WorldMapFrame.MiniBorderFrame
mapBorder.NineSlice = CreateFrame("Frame", nil, mapBorder)
mapBorder.NineSlice.TopLeftCorner = CreateFrame("Texture", nil, mapBorder.NineSlice)
mapBorder.NineSlice.TopLeftCorner.left, mapBorder.NineSlice.TopLeftCorner.top = -8, 816
mapBorder.NineSlice.BottomRightCorner = CreateFrame("Texture", nil, mapBorder.NineSlice)
mapBorder.NineSlice.BottomRightCorner.right, mapBorder.NineSlice.BottomRightCorner.bottom = 992, 197
QuestMapFrame.DetailsFrame.ScrollFrame = CreateFrame("EventScrollFrame", nil,
    QuestMapFrame.DetailsFrame, "ScrollFrameTemplate")
QuestMapFrame.DetailsFrame.ScrollFrame:SetSize(298, 180)
QuestMapFrame.DetailsFrame.ScrollFrame.left, QuestMapFrame.DetailsFrame.ScrollFrame.top = 705, 717
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent, "GameTooltipTemplate")
GameTooltip.left, GameTooltip.top = 700, 800
GameTooltipTextLeft1 = CreateFrame("FontString", "GameTooltipTextLeft1", GameTooltip)
GameTooltip.TextLeft1 = GameTooltipTextLeft1
BattlePetTooltip = CreateFrame("Frame", "BattlePetTooltip", UIParent)
BattlePetTooltip:Hide()
function BattlePetToolTip_Show() BattlePetTooltip:Show() end
for _, name in ipairs({ "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefTooltip",
    "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2", "BuffFrameTooltip" }) do
    local template = name:find("Shopping") and "ShoppingTooltipTemplate" or "GameTooltipTemplate"
    CreateFrame("GameTooltip", name, UIParent, template):Hide()
end
GameMenuFrame = CreateFrame("Frame", "GameMenuFrame", UIParent)
GameMenuFrame:Hide()
SettingsPanel = CreateFrame("Frame", "SettingsPanel", UIParent)
SettingsPanel:Hide()
SettingsPanel:SetScript("OnShow", function() SmartNavigation.panels[SettingsPanel] = true end)
function SettingsPanel:FocusContainer(button)
    if not self.containerFocused then
        self.containerFocused = true
        if button or self.nativeDefaultButton then SmartNavigation:SelectButton(button or self.nativeDefaultButton) end
    end
end
function SettingsPanel:UnfocusContainer()
    if self.containerFocused then
        self.containerFocused = false
        SmartNavigation:SelectButton(self.categoryButton)
        return true
    end
end
function SettingsPanel:SmartNavigationCloseHandler() return self:UnfocusContainer() end
Settings = { categories = {}, allCategories = {}, VarType = { Boolean = "boolean", String = "string", Number = "number" } }
SettingsPanel.settingsList = { Header = { DefaultsButton = CreateFrame("Button", nil, SettingsPanel) } }
SettingsPanel.settingsList.ScrollBox = CreateFrame("Frame", nil, SettingsPanel)
function SettingsPanel:GetSettingsList() return self.settingsList end
function SettingsPanel:GetCurrentCategory() return self.currentCategory end
function SettingsPanel:DisplayCategory(category) self.currentCategory = category end
SettingsPanel.settingsList.Header.DefaultsButton:SetScript("OnClick", function()
    StaticPopup_Show("GAME_SETTINGS_APPLY_DEFAULTS")
end)
StaticPopupDialogs = {}
function StaticPopup_Show(name, _, _, data)
    StaticPopupDialogs.shown, StaticPopupDialogs.data = name, data
end
local function CreateSettingsCategory(name, parent)
    local category = { name = name, parent = parent, initializers = {}, settings = {} }
    function category:GetID() return (self.parent and self.parent:GetID() .. "/" or "") .. self.name end
    function category:SetExpanded(expanded) self.expanded = expanded end
    function category:IsExpanded() return self.expanded end
    function category:AddInitializer(initializer) table.insert(self.initializers, initializer) end
    table.insert(Settings.allCategories, category)
    return category, category
end
function Settings.RegisterVerticalLayoutCategory(name) return CreateSettingsCategory(name) end
function Settings.RegisterVerticalLayoutSubcategory(parent, name) return CreateSettingsCategory(name, parent) end
function Settings.RegisterInitializer(category, initializer) category:AddInitializer(initializer) end
function Settings.RegisterCanvasLayoutSubcategory(parent, panel, name)
    local category = CreateSettingsCategory(name, parent)
    panel.parent, category.panel = SettingsPanel, panel
    return category
end
function Settings.RegisterProxySetting(category, variable, valueType, name, default, getter, setter)
    local setting = { variable = variable, name = name, default = default, category = category }
    function setting:GetVariable() return self.variable end
    function setting:GetValue() return getter() end
    function setting:IsLocked() return self.locked end
    function setting:SetValue(value)
        assert(type(value) == valueType, "native settings enforce their value type")
        self.locked = true
        setter(value)
        self.locked = false
        self:NotifyUpdate()
    end
    function setting:SetValueToDefault() self:SetValue(default) end
    function setting:NotifyUpdate()
        for _, category in ipairs(Settings.allCategories) do
            for _, other in ipairs(category.settings) do
                assert(not other:IsLocked(), "native controls must not rebuild inside a proxy setter")
            end
        end
        self.displayedValue = getter()
        for _, initializer in ipairs(category.initializers) do
            local parent = initializer.parentInitializer
            if initializer.modifyPredicate and ((parent and parent.setting == self)
                or (initializer.watchedVariables and initializer.watchedVariables[self.variable])) then
                initializer.displayedEnabled = initializer.modifyPredicate()
            end
        end
    end
    table.insert(category.settings, setting)
    return setting
end
function Settings.CreateControlTextContainer()
    local container = { data = {} }
    function container:Add(value, label) table.insert(self.data, { value = value, label = label }) end
    function container:GetData() return self.data end
    return container
end
function Settings.CreateCheckbox(category, setting, tooltip)
    local initializer = { kind = "checkbox", setting = setting, tooltip = tooltip }
    function initializer:SetParentInitializer(parent, predicate)
        self.parentInitializer, self.modifyPredicate = parent, predicate
        self.displayedEnabled = predicate()
    end
    function initializer:AddModifyPredicate(predicate)
        self.modifyPredicate = predicate
        self.displayedEnabled = predicate()
    end
    function initializer:AddEvaluateStateCVar(variable)
        self.watchedVariables = self.watchedVariables or {}
        self.watchedVariables[variable] = true
    end
    category:AddInitializer(initializer)
    return initializer
end
function Settings.CreateDropdown(category, setting, options, tooltip)
    local initializer = { kind = "dropdown", setting = setting, options = options, tooltip = tooltip }
    category:AddInitializer(initializer)
    return initializer
end
MinimalSliderWithSteppersMixin = { Label = { Right = "Right" } }
function Settings.CreateSliderOptions(minimum, maximum, step)
    local options = { minimum = minimum, maximum = maximum, step = step }
    function options:SetLabelFormatter(_, formatter) self.formatter = formatter end
    return options
end
function Settings.CreateSlider(category, setting, options, tooltip)
    local initializer = { kind = "slider", setting = setting, options = options, tooltip = tooltip }
    function initializer:SetParentInitializer(parent, predicate)
        self.parentInitializer, self.modifyPredicate = parent, predicate
    end
    category:AddInitializer(initializer)
    return initializer
end
function CreateSettingsListSectionHeaderInitializer(name) return { kind = "header", name = name } end
function Settings.CreatePanelInitializer(template, data)
    return { kind = "panel", template = template, data = data }
end
function CreateSettingsButtonInitializer(name, text, callback, tooltip, search)
    local initializer = { kind = "button", name = name, text = text, callback = callback, tooltip = tooltip, search = search }
    function initializer:AddSearchTags(...) self.searchTags = { ... } end
    return initializer
end
function Settings.FindButton(category, name)
    for _, initializer in ipairs(category.initializers) do
        if initializer.kind == "button" and initializer.name == name then return initializer end
    end
    error("Missing native settings button: " .. name)
end
function Settings.RegisterCanvasLayoutCategory(panel, name)
    panel.parent = SettingsPanel
    local category = { panel = panel, name = name }
    function category:GetID() return self.name end
    return category
end
function Settings.RegisterAddOnCategory(category) table.insert(Settings.categories, category) end
-- Native panel occupancy survives Frame:Hide(); HideUIPanel clears it.
local managedCenterPanel
function ShowUIPanel(frame)
    managedCenterPanel = frame
    frame:Show()
end
function HideUIPanel(frame)
    if not frame or not frame:IsShown() then return end
    if managedCenterPanel == frame then managedCenterPanel = nil end
    frame:Hide()
end
function CanOpenPanels() return managedCenterPanel == nil end
function GetUIPanel(area) return area == "center" and managedCenterPanel or nil end
function Settings.OpenToCategory(id)
    Settings.openedCategory = id
    ShowUIPanel(SettingsPanel)
    for _, category in ipairs(Settings.allCategories) do
        if category:GetID() == id then SettingsPanel:DisplayCategory(category) end
        if category.panel then category.panel:SetShown(category:GetID() == id) end
        for _, initializer in ipairs(category.initializers) do
            if initializer.kind == "panel" then
                if not initializer.host then
                    initializer.host = CreateFrame("Frame", nil, SettingsPanel)
                    initializer.host:SetSize(740, initializer.data.list and 142 or 260)
                    initializer.host:Hide()
                    initializer.host:SetScript("OnShow", function(host)
                        if initializer.data.list then
                            _G.ForeverRosettaStone:AttachRadioList(host, initializer.data.list)
                        else
                            _G.ForeverRosettaStone:AttachSettingsPreview(host)
                        end
                    end)
                end
                initializer.host:SetShown(category:GetID() == id)
            end
        end
    end
end
ENABLE, DEFAULTS, CANCEL = "Enabled", "Defaults", "Cancel"
GameTooltip:Hide()
GREEN_FONT_COLOR = {}
GAMEPAD_FACE_LEFT, GAMEPAD_FACE_BOTTOM, GAMEPAD_FACE_TOP = "PAD3", "PAD1", "PAD4"
function GameTooltip_AddLineWithInputIcon(tip, text, _, key) tip:AddLine(key .. " " .. text) end

local hooks = {}
function hooksecurefunc(target, name, callback)
    if type(target) == "table" then
        local original = target[name]
        target[name] = function(...)
            local result = original(...)
            callback(...)
            return result
        end
    else
        hooks[target] = name
    end
end
TooltipComparisonManager = {
    SetItemTooltip = function(self, isPrimaryTooltip)
        if self.buildItemTooltip then return self.buildItemTooltip(isPrimaryTooltip) end
    end,
    AnchorShoppingTooltips = function() end,
}
local eventCallbacks = {}
function RegisterEventCallback(event, callback)
    eventCallbacks[event] = eventCallbacks[event] or {}
    table.insert(eventCallbacks[event], callback)
end
local nativeSetItemTooltip = TooltipComparisonManager.SetItemTooltip
RegisterEventCallback("TOOLTIP_SHOW_ITEM_COMPARISON", function(_, _, tooltip)
    TooltipComparisonManager.tooltip = tooltip
    nativeSetItemTooltip(TooltipComparisonManager, true)
end)
function GameTooltip_ShowCompareItem(tooltip)
    for _, callback in ipairs(eventCallbacks.TOOLTIP_SHOW_ITEM_COMPARISON) do
        callback(nil, {}, tooltip or GameTooltip)
    end
end
QuestFont, QuestTitleFont = CreateFrame("Font"), CreateFrame("Font")
QuestFontNormalSmall = CreateFrame("Font")
QuestFont:SetFont("Fonts/Quest.ttf", 12, "")
QuestTitleFont:SetFont("Fonts/QuestTitle.ttf", 18, "")
QuestFontNormalSmall:SetFont("Fonts/Quest.ttf", 11, "")
QuestInfoTitleHeader = CreateFrame("FontString", nil, nil, "QuestTitleFont")
QuestInfoObjectivesHeader = CreateFrame("FontString", nil, nil, "QuestTitleFont")
QuestInfoDescriptionHeader = CreateFrame("FontString", nil, nil, "QuestTitleFont")
QuestInfoObjectivesText = CreateFrame("FontString", nil, nil, "QuestFont")
QuestInfoDescriptionText = CreateFrame("FontString", nil, nil, "QuestFont")
QuestInfoObjective1 = CreateFrame("FontString", nil, nil, "QuestFontNormalSmall")
QuestInfoTitleHeader:SetText("Titre français")
QuestInfoDescriptionText:SetText("Description française")
function QuestInfo_Display() error("the shared native quest renderer must not be called") end
QuestTextContrast = { GetDefaultDetailsBackgroundAtlas = function() return "QuestDetailsBackgrounds" end }
REWARD_ITEMS_ONLY = "You will receive:"
QuestLogQuestDetailsMixin = {
    AdjustBackgroundTexture = function(_, texture)
        texture:SetWidth(QuestMapFrame.DetailsFrame:GetWidth())
        texture:SetHeight(440)
    end,
    AdjustRewardsFrameContainer = function(frame)
        local container = frame.RewardsFrameContainer
        local range = frame.ScrollFrame:GetVerticalScrollRange()
        local height = container.RewardsFrame:GetHeight()

        if range == 0 or QuestInfo_GetNumRewardRows() <= 1 then
            container:SetHeight(height)
        else
            container:SetHeight(math.max(124, height - (range - frame.ScrollFrame:GetVerticalScroll())))
        end
    end,
}
local rewardRows = 2
function QuestInfo_GetNumRewardRows() return rewardRows end
QUEST_TEMPLATE_MAP_DETAILS = { contentWidth = 289 }
function QuestUtils_DecorateQuestText(questID, title)
    return "[" .. (questID == 399 and "15" or "20") .. "] " .. title
end
local nativeRewards = CreateFrame("Frame", nil, QuestMapFrame.DetailsFrame)
QuestMapFrame.DetailsFrame.RewardsFrameContainer = nativeRewards
nativeRewards:SetHeight(100)
nativeRewards.left, nativeRewards.bottom = 700, 283
nativeRewards.RewardsFrame = CreateFrame("Frame", nil, nativeRewards)
nativeRewards.RewardsFrame:SetHeight(200)
nativeRewards.RewardsFrame.Label = CreateFrame("FontString", nil, nativeRewards.RewardsFrame)
MapQuestInfoRewardsFrame = CreateFrame("Frame", nil, nativeRewards)
MapQuestInfoRewardsFrame.left, MapQuestInfoRewardsFrame.top = 0, 0
MapQuestInfoRewardsFrame.Header = CreateFrame("Frame", nil, MapQuestInfoRewardsFrame)
MapQuestInfoRewardsFrame.Header:SetHeight(1)
MapQuestInfoRewardsFrame.ItemReceiveText = CreateFrame("FontString", nil, MapQuestInfoRewardsFrame)
MapQuestInfoRewardsFrame.ItemReceiveText.left, MapQuestInfoRewardsFrame.ItemReceiveText.top = 0, 10
MapQuestInfoRewardsFrame.ItemChooseText = CreateFrame("FontString", nil, MapQuestInfoRewardsFrame)
MapQuestInfoRewardsFrame.ItemChooseText:Hide()
local nativeXP = CreateFrame("Button", nil, MapQuestInfoRewardsFrame, "SmallItemButtonTemplate")
nativeXP.left, nativeXP.top = 0, 0
nativeXP.Icon:SetTexture("XP_Icon")
nativeXP.Name:SetText("1050")
local nativeMoney = CreateFrame("Button", nil, MapQuestInfoRewardsFrame, "SmallItemButtonTemplate")
nativeMoney.left, nativeMoney.top = 140, 0
nativeMoney.Icon:SetTexture("Coin_Icon")
nativeMoney.Name:SetText("7 silver")
local choiceItems = {5627, 5626, 270022}
function GetQuestLogChoiceInfo(index) return nil, nil, 1, 2, true, choiceItems[index] end
function GetQuestLogRewardInfo() return nil, nil, 1, 2, true, 5627 end
MapQuestInfoRewardsFrame.activeRewardElements = {
    MapQuestInfoRewardsFrame.ItemReceiveText, nativeXP, nativeMoney,
}

local inputTransitions = {}
InputUtil = {
    IsGamepadUIEnabled = function() return style == "1" end,
    RegisterForInterfaceTransitions = function(owner, callback) inputTransitions[owner] = callback end,
}
UISpecialFrames = {}
function CloseSpecialWindows()
    local closed = false

    for _, name in pairs(UISpecialFrames) do
        local frame = _G[name]

        if frame and frame:IsShown() then frame:Hide(); closed = true end
    end

    return closed
end
SmartNavigation = { scrollFrames = {}, panels = {}, targetButtons = {}, lastButtons = {} }
FRAME_ACTION_CLOSE = "Close"
GAMEPAD_FACE_RIGHT = "PAD2"
IsKeyDown = function() return false end
GamepadSharedUtility = {}
function GamepadSharedUtility.CreateMoreActionsPromptedBinding(key)
    local binding = { key = key, conditions = {}, entries = {} }
    function binding:SetLabelFunction(callback) self.label = callback end
    function binding:SetMoreActionsMenuOwnerRegion(owner) self.owner = owner end
    function binding:AddCondition(callback) table.insert(self.conditions, callback) end
    function binding:SetMenuOpeningCallback(callback) self.onOpening = callback end
    function binding:AddMoreActionsEntry(label, callback)
        table.insert(self.entries, { label = label, callback = callback })
    end
    function binding:Trigger()
        for _, condition in ipairs(self.conditions) do if not condition() then return false end end
        self:onOpening()
        MenuUtil.CreateContextMenu(self.owner, function(_, root)
            for _, entry in ipairs(self.entries) do root:CreateButton(entry.label, entry.callback) end
        end)
        return true
    end
    return binding
end
-- A native prompt footer pushes an addon-owned binding group on the shared gamepad stack.
function GamepadSharedUtility.CreatePromptedBindingFooter()
    error("addon code must not create native binding footers")
end
SMART_NAV_INPUT_DIRECTION = {
    UP = {dirKey = "up"}, DOWN = {dirKey = "down"}, LEFT = {dirKey = "left"}, RIGHT = {dirKey = "right"},
}
function SmartNavigation_MarkFrameIgnored(frame) frame.smartNavigationIgnored = true end
function SmartNavigation_ClearIgnoreStatus(frame) frame.smartNavigationIgnored = nil end
function SmartNavigation_MarkFrameFocusable(frame) frame.smartNavigationCanFocus = true end
function securecallfunction(callback, ...) return callback(...) end
function CreateAnchor(point, relativeTo, relativePoint, x, y)
    return { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end
function SmartNavigation_SetCustomCursorAnchorPointForFrame(frame, anchor) frame.cursorAnchor = anchor end
function SmartNavigation_AddJumpNavigationOverride(frame, direction, target)
    frame.navigationOverrides = frame.navigationOverrides or {}
    frame.navigationOverrides[direction.dirKey] = target
end
function SmartNavigation_AddBidirectionalJumpNavigationOverride(first, direction, second)
    local opposite = {up = "DOWN", down = "UP", left = "RIGHT", right = "LEFT"}
    SmartNavigation_AddJumpNavigationOverride(first, direction, second)
    SmartNavigation_AddJumpNavigationOverride(second, SMART_NAV_INPUT_DIRECTION[opposite[direction.dirKey]], first)
end
function SmartNavigation:SetTargetButtonForFrame(panel, button)
    assert(not combat, "no addon navigation changes in combat")
    assert(self.panels[panel], "native manager must activate reopen action before targeting it")
    self.targetButtons[panel] = button

    if self.activeFrame == panel and button then self:SelectButton(button) end
end
function SmartNavigation_MarkScrollFrameMaintainPreviousButtonOnScroll(scroll)
    assert(not combat, "no addon navigation changes in combat")
    scroll.maintainPreviousButtonOnScroll = true
end
function SmartNavigation:GetCurrentButton() return self.currentButton end
function SmartNavigation:GetActiveFrame() return self.activeFrame end
function SmartNavigation:IsInFocusGroup()
    return self.activeFrame == SettingsPanel and SettingsPanel.containerFocused == true
end
function SmartNavigation:IsCursorHidden() return self.currentButton == nil end
function SmartNavigation:HideCursor()
    assert(not combat, "no addon navigation changes in combat")
    local previous = self.currentButton

    if previous and previous.OnSmartNavDeselect then previous:OnSmartNavDeselect() end

    self.currentButton = nil
end
function SmartNavigation:SelectButton(button)
    assert(button:IsVisible(), "native navigation cannot select a hidden button")
    local parent = button:GetParent()

    while parent and not self.panels[parent] do parent = parent:GetParent() end

    assert(parent == self.activeFrame, "button must belong to the active window's navigation tree")
    local previous = self.currentButton

    if previous and previous ~= button and previous.OnSmartNavDeselect then previous:OnSmartNavDeselect() end

    self.currentButton = button

    if button.OnSmartNavSelect then button:OnSmartNavSelect() end
end
function SmartNavigation:SetScrollFrameForFrame(panel, scroll)
    assert(not combat, "no addon focus changes in combat")
    assert(self.panels[panel], "native manager must activate the panel before scroll registration")
    self.scrollFrames[panel] = scroll
end
function SmartNavigation:RemovePanelInfo(panel)
    assert(not combat, "no addon focus removal in combat")
    self.panels[panel], self.scrollFrames[panel], self.targetButtons[panel] = nil, nil, nil
    if self.activeFrame == panel then self.activeFrame, self.currentButton = nil, nil end
end
local manager = { shownFrames = {WorldMapFrame}, focusedFrame = WorldMapFrame, registrations = 0 }
GamepadMode = { FrameControlsManager = manager }
function GamepadMode.AddGamepadIconToButton(button, key)
    local icon = CreateFrame("Frame", nil, button)
    icon.inputKey = key
    return icon
end
function GamepadMode.SetGamepadIconShown(icon, shown) icon:SetShown(shown) end
function manager:GetActiveFrame() return self.focusedFrame end
local function focusNativeFrame(self, panel)
    local previous = self.focusedFrame

    if previous == panel then return end

    if previous then SmartNavigation.lastButtons[previous] = SmartNavigation.currentButton end

    if previous and previous.UnfocusGamepad then previous:UnfocusGamepad() end
    if previous and previous.EndFocus then previous:EndFocus() end

    self.focusedFrame = panel
    self.isUIFocused = true
    SmartNavigation.panels[panel] = true
    SmartNavigation.activeFrame = panel
    SmartNavigation.currentButton = SmartNavigation.lastButtons[panel] or SmartNavigation.targetButtons[panel]

    if panel.FocusGamepad then panel:FocusGamepad() end
    if panel.StartFocus then panel:StartFocus() end
end
function manager:FocusFrame()
    error("addon must not call unwrapped FocusFrame; use secure FrameShown instead")
end
function manager:FrameShown(panel, isPopup, shouldFocus)
    assert(not combat, "no addon registration in combat")
    assert(panel.skipGamepadAutoFocus == nil, "addon autofocus flags taint native focus handling")

    for _, shown in ipairs(self.shownFrames) do
        if shown == panel then return false end
    end

    self.registrations = self.registrations + 1
    self.lastPopup = isPopup and panel or nil
    self.shownFrames[#self.shownFrames + 1] = panel

    if shouldFocus ~= false then
        focusNativeFrame(self, panel)
    elseif isPopup and not self.isUIFocused then
        self.focusedFrame = panel
        if panel.ShowFocusJumpHint then panel:ShowFocusJumpHint() end
    end

    local trackedFocus = false

    for _, shown in ipairs(self.shownFrames) do
        if shown == self.focusedFrame then trackedFocus = true end
    end

    assert(trackedFocus, "Frame is not tracked by FrameControlsManager")

    return true
end
function manager:FrameHidden(panel)
    assert(not combat, "no addon deregistration in combat")
    assert(panel.returnToPlayerControl == nil, "addon return flags taint native focus handling")
    local returnFrame = self.popupReturnFrames and self.popupReturnFrames[panel]
    if self.popupReturnFrames then self.popupReturnFrames[panel] = nil end

    for index, shown in ipairs(self.shownFrames) do
        if shown == panel then table.remove(self.shownFrames, index); break end
    end

    if self.focusedFrame == panel then
        if panel.returnToPlayerControl then
            if panel.UnfocusGamepad then panel:UnfocusGamepad() end
            self.isUIFocused = false
            self.focusedFrame = WorldMapFrame
            SmartNavigation.activeFrame, SmartNavigation.currentButton = nil, nil
        elseif self.isUIFocused and returnFrame then
            focusNativeFrame(self, returnFrame)
        else
            focusNativeFrame(self, WorldMapFrame)
        end
    end
end
function manager:HandlePopupShown(panel)
    local returnFrame = self.isUIFocused and self.focusedFrame or nil
    if self:FrameShown(panel, true) then
        self.popupReturnFrames = self.popupReturnFrames or {}
        self.popupReturnFrames[panel] = returnFrame
    end
end
function manager:HandlePopupHide(panel)
    self:FrameHidden(panel)
end
function WorldMapFrame:FocusGamepad()
    self:FocusDetails()
end
function WorldMapFrame:FocusDetails()
    SmartNavigation:SetScrollFrameForFrame(self, QuestMapFrame.DetailsFrame.ScrollFrame)
    QuestMapFrame.DetailsFrame.ScrollFrame:SetVerticalScroll(0)
end
SmartNavigation.panels[WorldMapFrame] = true
SmartNavigation.activeFrame = WorldMapFrame
WorldMapFrame:FocusGamepad()

GetLocale = function() return "frFR" end
UnitName = function() return "Rosetta" end
UnitRace = function() return "Human", "Human" end
UnitClass = function() return "Mage", "MAGE" end
PaperDollFrame_SetLabelAndText = function(frame, label, text)
    frame.Label:SetText(label)
    frame.Value:SetText(text)
end
PaperDollFrame_SetResistanceTooltips = function() end
CharacterStatFrameScrollBoxBaseElementMixin = { Init = function() end }
local Addon = {}
PanelTemplates_TabResize = function(tab) tab:SetWidth(tab:GetText():len() * 7 + 40) end
PanelTemplates_SelectTab = function(tab) tab.selected = true end
PanelTemplates_DeselectTab = function(tab) tab.selected = false end
for _, file in ipairs({
    "database/database-api", "core/safety", "locales/settings-locales", "settings/settings", "settings/minimap-button", "locales/debug-locales", "diagnostics/error-dialog", "diagnostics/diagnostics", "diagnostics/debug-display", "diagnostics/benchmark", "tooltips/tooltip-layout", "quests/quest-report", "quests/missing-quest",
    "quests/quest-data", "quests/quest-dialogue", "database/item-data", "database/npc-tooltip-data", "tooltips/english-tooltip-formats", "quests/quest-state", "quests/quest-page", "quests/quest-interaction-reader", "quests/reward-tooltips", "tooltips/tooltip-state", "tooltips/tooltip-comparisons", "tooltips/tooltip-component", "tooltips/tooltip-companions", "tooltips/spell-live-values", "tooltips/tooltip-descriptions",
    "tooltips/policies/toolkit", "tooltips/policies/item-comparison", "tooltips/policies/item", "tooltips/policies/spell", "tooltips/policies/talent", "tooltips/policies/npc",
    "tooltips/policies/quest-tracker",
    "tooltips/components/talent-tooltip", "tooltips/components/mount-tooltip", "tooltips/components/pet-tooltip", "tooltips/components/appearance-tooltip", "tooltips/components/activity-tooltip", "tooltips/components/taxi-node-tooltip", "tooltips/components/item-tooltip", "tooltips/components/spell-tooltip",
    "tooltips/character-stat-formats", "tooltips/components/character-stat-tooltip",
    "tooltips/components/npc-tooltip", "tooltips/components/player-tooltip", "tooltips/components/minimap-quest-tooltip",
    "tooltips/components/minimap-location-tooltip", "tooltips/components/quest-tracker-tooltip", "tooltips/components/profession-tooltips", "tooltips/components/quest-offer-tooltip",
    "tooltips/components/quest-link-tooltip", "tooltips/components/gossip-option-tooltip",
    "quests/components/quest-interaction-panel", "books/book-reader",
    "quests/quest-ui", "core/controller", "core",
}) do
    assert(loadfile("ForeverRosettaStone/" .. file .. ".lua"))("ForeverRosettaStone", Addon)
end

local baselineTitle
Addon:SetCompanionTooltipTitle({
    TextLeft1 = { GetFont = function() return "Fonts/Test.ttf", 14 end },
    SetText = function(_, text) baselineTitle = text end,
}, "Logo test")
equal(baselineTitle, "Logo test", "tooltip titles contain no addon icon")
Addon:SetCompanionTooltipTitle({ SetText = function(_, text) baselineTitle = text end }, "Baseline")
equal(baselineTitle, "Baseline", "baseline title requires no font access or texture markup")
Addon:LoadPreferences()
equal(Addon.preferences.tooltipMode, "stacked", "fresh preferences default to Stacked")
Addon.preferences.tooltipMode = "separate"

-- Exercise every declared transition and refusal before wiring the UI.
equal(Addon:MoveLifecycle("initialize.ready"), false, "cannot become ready before initialization")
equal(Addon.lifecycle, "waiting")
local state = Addon:CreateQuestState()
equal(state.mode, "unavailable")
for _, event in ipairs({
    "focus.enter", "focus.leave", "panel.open", "panel.close", "bookmark.focus", "bookmark.blur", "unknown",
}) do
    equal(Addon:Transition(state, event), state, "unavailable refuses " .. event)
end
state = Addon:Transition(state, "quest.select", 399)
equal(state.mode, "open")
equal(Addon:Transition(state, "quest.select", 399), state, "same selection preserves mode")
equal(Addon:Transition(state, "quest.select", 400).mode, "open", "missing quest opens a report page")
local bookmarkState = Addon:Transition({mode = "collapsed", questID = 399}, "bookmark.focus")
equal(bookmarkState.mode, "bookmarkFocused", "manual bookmark selection has its own state")
local openingState, openingEffect = Addon:Transition(bookmarkState, "panel.open")
equal(openingState.mode, "open", "bookmark activation opens before native focus is confirmed")
equal(openingEffect, "panel.focus", "the machine requests focus only for an activated bookmark")
local _, mouseOpenEffect = Addon:Transition({mode = "collapsed", questID = 399}, "panel.open")
equal(mouseOpenEffect, nil, "opening without bookmark selection does not request controller focus")
equal(Addon:Transition(bookmarkState, "bookmark.blur").mode, "collapsed", "deselection leaves the bookmark visible")
local refreshedState, refreshEffect = Addon:Transition(bookmarkState, "quest.select", 399)
equal(refreshedState, bookmarkState, "refresh preserves manual bookmark selection")
equal(refreshEffect, "quest.refresh", "unchanged quests refresh layout without a focus request")
local returnedState = Addon:Transition(bookmarkState, "map.close")
equal(returnedState.mode, "unavailable", "leaving details invalidates bookmark focus")
local ignoredState, ignoredEffect = Addon:Transition(returnedState, "panel.open")
equal(ignoredState, returnedState, "stale activation after leaving details is refused")
equal(ignoredEffect, nil, "stale activation produces no focus effect")
for mode, expected in pairs({
    unavailable = "unavailable", open = "open", reading = "open", collapsed = "collapsed",
    bookmarkFocused = "collapsed",
}) do
    local resetState, resetEffect = Addon:Transition({mode = mode, questID = 399}, "input.reset")
    equal(resetState.mode, expected, "input teardown resets native focus from " .. mode)
    equal(resetEffect, "controller.reset", "input teardown explicitly requests registration invalidation")
end
for mode, events in pairs({
    open = { ["panel.close"] = "collapsed", ["focus.enter"] = "reading" },
    collapsed = { ["panel.open"] = "open", ["bookmark.focus"] = "bookmarkFocused" },
    bookmarkFocused = { ["panel.open"] = "open", ["bookmark.blur"] = "collapsed" },
    reading = { ["panel.close"] = "collapsed", ["focus.leave"] = "open" },
}) do
    for event, expected in pairs(events) do
        local nextState = Addon:Transition({mode = mode, questID = 399}, event)
        equal(nextState.mode, expected, mode .. " " .. event)
        equal(nextState.questID, 399)
    end
    equal(Addon:Transition({mode = mode, questID = 399}, "map.close").mode, "unavailable")
    local current = {mode = mode, questID = 399}
    local ignored, effect = Addon:Transition(current, "unknown")
    equal(ignored, current, "unknown events preserve " .. mode)
    equal(effect, nil, "unknown events produce no effects in " .. mode)
end
equal(Addon:Transition({mode = "collapsed", questID = 399}, "focus.enter").mode, "collapsed",
    "native focus cannot reopen collapsed panel")
equal(Addon:Transition({mode = "reading", questID = 399}, "quest.select", 943).mode, "reading",
    "changing supported quest preserves native focus")

local events
for _, frame in ipairs(frames) do
    if frame.events.PLAYER_LOGIN then events = frame end
end
events:Fire("OnEvent", "PLAYER_LOGIN")
equal(Addon.lifecycle, "ready", "login initializes without Spoken installed")
equal(Addon.protectedActionEvents, nil, "normal startup does not arm diagnostic monitoring")
for _, frame in ipairs(Addon.frames) do
    equal(frame.gamepadEnabled == true, false, "no raw controller capture")
    equal(frame.scripts.OnGamePadButtonDown, nil, "no native button handler")
end
for _, frame in ipairs(frames) do
    if frame.events.QUEST_LOG_UPDATE then events = frame end
end
local body, page = Addon.page.body, Addon.page
local nativeTitle = body.sections[1]
equal(select(2, nativeTitle:GetFont()), select(2, QuestTitleFont:GetFont()), "native quest title size")
local entry
local shows = 0
local showPage = page.Show
function page:Show(value)
    entry = value
    shows = shows + 1
    return showPage(self, value)
end
Addon.contentKey = nil
Addon:RefreshSelection()
equal(Addon.current.mode, "open", "selected DB quest opens automatically")
equal(Addon.panel:IsShown(), true)
equal(Addon.panel:GetParent(), UIParent, "panel stays outside native map navigation")
equal(Addon.toggle:GetParent(), QuestMapFrame.DetailsFrame, "bookmark belongs only to quest-details navigation")
equal(Addon.headerToggle, nil, "collapsed control does not create a separate focus window")
equal(Addon.input:GetParent(), UIParent, "input stays outside native map navigation")
equal(Addon.panel.template, "ForeverRosettaStoneQuestPanelTemplate", "native portrait shell keeps an opaque background")
equal(Addon.panel.title, Addon:GetTranslationLanguageLabel(), "panel title uses the localized translation label and language name")
Addon.toggle:Fire("OnEnter")
equal(Addon:GetWidgetTooltip():GetText(), "Ouvrir Forever Rosetta Stone : anglais",
    "bookmark tooltip follows the French client rather than the English translation target")
local clientLocale = GetLocale
GetLocale = function() return "enUS" end
Addon.toggle:Fire("OnEnter")
equal(Addon:GetWidgetTooltip():GetText(), "Open Forever Rosetta Stone: English", "bookmark tooltip follows the English client")
GetLocale = clientLocale
Addon.toggle:Fire("OnLeave")
equal(select(2, Addon.panel.TitleContainer.TitleText:GetTextColor()), 0.82, "quest window translation header stays yellow")
equal(Addon.panel.TitleIcon:GetTexture(), [[Interface\AddOns\ForeverRosettaStone\media\icon]],
    "title portrait displays the Rosetta icon")
equal(Addon.panel.TitleIcon:GetWidth(), 16, "title icon stays small")
equal(Addon.panel.TitleIcon.points[1][2], Addon.panel.TitleContainer.TitleText, "icon sits next to the title")
equal(Addon.panel.TitleIcon.points[1][4], -3, "icon has roughly one character space before the title")
equal(Addon.panel.TitleIcon:GetParent(), Addon.panel.TitleContainer, "icon shares the title's frame level")
equal(Addon.panel.TitleRing, nil, "title has no ring border")
equal(Addon.panel.PortraitContainer:IsShown(), false, "unused corner portrait stays hidden")
local titleWidth = Addon.panel.TitleContainer.TitleText:GetWidth()
local titleCenter = Addon.panel.TitleContainer.TitleText.points[1][4]
local titleLeft = titleCenter - titleWidth / 2
local iconLeft = titleLeft + Addon.panel.TitleIcon.points[1][4] - Addon.panel.TitleIcon:GetWidth()
near((iconLeft + titleCenter + titleWidth / 2) / 2, 0, "title and icon form one centered group")
equal(Addon.panel.NineSlice.appliedLayout, "ButtonFrameTemplateNoPortrait", "border has no corner portrait")
equal(Addon.panel.layoutType, "ButtonFrameTemplateNoPortrait", "focus glow has no corner portrait")
equal(Addon.panel.FrameGlow.GlowTexture.atlas, "gamepad-uiframemetal-focus",
    "focus glow initializes without a corner portrait")
equal(Addon.panel.PortraitContainer:GetFrameLevel() > mapBorder.NineSlice:GetFrameLevel(), true,
    "native portrait draws above the left pane's border")
mapBorder:SetFrameStrata("HIGH")
Addon:Layout()
equal(Addon.panel:GetFrameStrata(), "HIGH", "panel matches native border strata even when map strata is lower")
mapBorder:SetFrameStrata("MEDIUM")
Addon:Layout()
equal(Addon.panel:GetFrameStrata(), "MEDIUM", "panel follows native strata back down")
equal(Addon.panel.CloseButton.template, "UIPanelCloseButtonDefaultAnchors", "native X button in title bar")
equal(Addon.panel.CloseButton:GetParent(), Addon.panel, "close button stays outside quest content")
equal(Addon.panel.Content.points[1][4], 8, "quest content inset from outer border")
near(Addon.panel.Content.points[1][5], -40, "content follows the native quest top inside aligned shell")
equal(Addon.panel:GetWidth() - Addon.panel.Content:GetWidth(), 36, "shell reserves room for scrollbar and border")
equal(Addon.panel.Content:GetWidth(), QuestMapFrame.DetailsFrame:GetWidth(), "quest wrapping width preserved")
equal(Addon.panel.BorderFrame.template, "QuestLogBorderFrameTemplate", "native quest border")
equal(page.background.atlas, "QuestDetailsBackgrounds", "native quest parchment atlas")
equal(page.background:GetHeight(), 440, "native helper sizes parchment")
near(page.background:GetWidth() * Addon.panel.Content:GetEffectiveScale(),
    QuestMapFrame.DetailsFrame:GetWidth() * QuestMapFrame.DetailsFrame:GetEffectiveScale(),
    "parchment matches the native quest page's physical width")
equal(body.frame.template, "ScrollFrameTemplate", "native quest scrolling template")
equal(body.frame.kind, "EventScrollFrame", "same scrolling intrinsic as quest details")
equal(body.frame.ScrollBar:GetParent(), body.frame, "native scrollbar belongs to English page")
local details = QuestMapFrame.DetailsFrame
local sourceBar = details.ScrollFrame.ScrollBar
sourceBar.left, sourceBar.top = 1000, 730
sourceBar:SetSize(11, 160)
page:RefreshNativeLayout()
local _, translatedBarAnchor, _, translatedBarX, translatedBarY = body.frame.ScrollBar:GetPoint(1)
equal(translatedBarAnchor, body.frame:GetParent(), "map scrollbar anchors to the translated content")
equal(translatedBarX, 300, "map scrollbar copies the native horizontal inset")
equal(translatedBarY, -30, "map scrollbar copies the native top inset")
equal(body.frame.ScrollBar:GetWidth(), 11, "map scrollbar copies the native width")
equal(body.frame.clipsChildren == true, false, "viewport must not clip its native scrollbar")
equal(page.rewards.clipsChildren, true, "native rewards clipping")
equal(QuestInfoTitleHeader:GetText(), "Titre français", "French title stays unchanged")
equal(QuestInfoDescriptionText:GetText(), "Description française", "French description stays unchanged")
equal(QuestInfoTitleHeader:GetParent(), nil, "native title is never reparented")
equal(C_QuestLog.GetSelectedQuest(), 399, "rendering does not change selected quest")
equal(Addon.panel:GetEffectiveScale(), WorldMapFrame:GetEffectiveScale(), "gamepad map scale")
near(Addon.panel.points[1][5] + Addon.panel.Content.points[1][5], -40,
    "inner quest panel stays aligned with French details")
near(Addon.panel:GetHeight(), 600, "outer shell accounts for the native bag bottom corner offset")
near(mapBorder:GetTop() + Addon.panel.points[1][5] - Addon.panel:GetHeight()
    + panelLayout.BottomRightCorner.y, mapBorder.NineSlice.BottomRightCorner:GetBottom(),
    "visible shell bottom aligns with the native map border")
near(Addon.panel.points[1][4], -14, "native border sits against the quest panel")
local mapNineSlice = mapBorder.NineSlice
mapBorder.NineSlice = nil
Addon:Layout()
near(Addon.panel.points[1][4], -18, "native map padding does not widen the visible panel gap")
near(Addon.panel.points[1][5], -16, "spacing adjustment preserves vertical positioning")
near(Addon.panel:GetHeight(), 581, "shell height accounts for the native bag bottom corner without a map NineSlice")
near(mapBorder:GetTop() + Addon.panel.points[1][5] - Addon.panel:GetHeight()
    + panelLayout.BottomRightCorner.y, mapBorder:GetBottom(),
    "visible shell bottom aligns when the map has no NineSlice")
mapBorder.NineSlice = mapNineSlice
Addon:Layout()
near(Addon.panel.BorderFrame.points[1][4], -3, "inner rim copies native horizontal position")
near(Addon.panel.BorderFrame.points[1][5], 4, "inner rim copies native vertical position")
near(Addon.panel.BorderFrame:GetHeight(), 487, "inner rim copies actual native crop height")
near(body.frame.points[1][5], -43, "text viewport copies native top")
near(page.rewards.points[1][5], -477, "rewards clip bottom matches native quest bottom")
QuestMapFrame.DetailsFrame.BorderFrame:SetHeight(480)
QuestMapFrame.DetailsFrame.ScrollFrame.top = 716
nativeRewards.bottom = 285
Addon:Layout()
near(Addon.panel.BorderFrame:GetHeight(), 480, "rim follows native layout changes")
near(body.frame.points[1][5], -44, "text viewport follows native layout changes")
near(page.rewards.points[1][5], -475, "reward clipping follows native layout changes")
QuestMapFrame.DetailsFrame.BorderFrame:SetHeight(487)
QuestMapFrame.DetailsFrame.ScrollFrame.top = 717
nativeRewards.bottom = 283
Addon:Layout()
equal(Addon.toggle:GetFrameLevel(), QuestMapFrame.DetailsFrame:GetFrameLevel() + 1,
    "bookmark draws above its native parent")
equal(Addon.toggle:GetEffectiveScale(), QuestMapFrame.DetailsFrame:GetEffectiveScale(),
    "bookmark inherits map scaling without applying it twice")
equal(Addon.hint, nil, "quest header has no written controller instructions")
equal(entry.title, "Humble Beginnings")
equal(entry.progress, "A Simple Compass: 0/1")
equal(select(1, body.sections[1]:GetFont()), select(1, QuestTitleFont:GetFont()), "native heading face")
equal(select(2, body.sections[1]:GetFont()), select(2, QuestTitleFont:GetFont()), "native heading size")
equal(select(1, body.sections[2]:GetFont()), select(1, QuestFont:GetFont()), "native objective face")
equal(select(2, body.sections[2]:GetFont()), select(2, QuestFont:GetFont()), "native objective size")
equal(select(2, body.sections[3]:GetFont()), select(2, QuestFontNormalSmall:GetFont()), "native progress size")
equal(select(1, body.sections[5]:GetFont()), select(1, QuestFont:GetFont()), "native description face")
equal(select(2, body.sections[5]:GetFont()), select(2, QuestFont:GetFont()), "native description size")
equal(select(1, body.sections[4]:GetTextColor()), select(1, QuestInfoDescriptionHeader:GetTextColor()),
    "native heading ink")
equal(select(4, body.sections[4]:GetShadowColor()), select(4, QuestInfoDescriptionHeader:GetShadowColor()),
    "native heading shadow opacity")
equal(body.sections[1]:GetText(), "[15] Humble Beginnings", "native title decoration")
equal(body.sections[2]:GetText(), entry.objectives, "objective text follows title without extra heading")
equal(body.sections[4]:GetText(), "Description")
equal(body.lastSections[1].gap, 0)
equal(body.lastSections[2].gap, 5, "native objective gap")
equal(body.lastSections[3].gap, 10, "native progress gap")
equal(body.lastSections[4].gap, 20, "native description heading gap")
equal(body.lastSections[5].gap, 5, "native description text gap")
equal(body.sections[5]:GetWidth(), QUEST_TEMPLATE_MAP_DETAILS.contentWidth, "native wrapping width")
equal(page.rewards:GetHeight(), 124, "long quest starts with native clipped rewards preview")
local viewportHeight = body.frame:GetHeight()
nativeRewards:SetHeight(180)
page:RefreshNativeLayout()
equal(body.frame:GetHeight(), viewportHeight, "revealing rewards does not resize the English viewport")
equal(page.rewards:GetHeight(), 124, "French reward reveal cannot resize English rewards")
equal(body.frame:GetHeight(), QuestMapFrame.DetailsFrame.ScrollFrame:GetHeight(),
    "English scroll viewport follows native full height")
equal(body.child:GetHeight(), body.textHeight + 200, "native rewards spacer participates in scrolling")
equal(page.rewards:GetParent() == body.child, false, "rewards stay outside scrolling text")
rewardRows = 1
page:RefreshNativeLayout()
equal(page.rewards:GetHeight(), 200, "single-row rewards stay fully visible like native rewards")
rewardRows = 2
local textHeight = body.textHeight
body.textHeight = 1
body.frame:SetHeight(300)
body:UpdateScrollRange()
equal(page.rewards:GetHeight(), 200, "short quest reveals all rewards without scrolling")
body.textHeight = textHeight
body.frame:SetHeight(180)
body:UpdateScrollRange()
equal(page.rewards:GetHeight(), 124, "restoring long quest restores rewards preview")
MapQuestInfoRewardsFrame:Hide()
page:RefreshNativeLayout()
equal(page.rewards:IsShown(), false, "no rewards hides reward area")
equal(body.child:GetHeight(), body.textHeight, "no rewards leaves no invisible scroll spacer")
MapQuestInfoRewardsFrame:Show()
nativeRewards:SetHeight(100)
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "1050", "live native XP reward")
equal(page.rewardButtons[1].Icon:GetTexture(), "XP_Icon")
equal(#page.rewardButtons, 2, "native text header does not become a reward card")
equal(page.rewardButtons[2].Name:GetText(), "7 silver", "money after native text header")
MapQuestInfoRewardsFrame.activeRewardElements = {MapQuestInfoRewardsFrame.ItemReceiveText, nativeMoney}
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "7 silver", "card reused after removing XP")
equal(page.rewardButtons[2]:IsShown(), false, "unused reward card is hidden")
MapQuestInfoRewardsFrame.ItemChooseText.left, MapQuestInfoRewardsFrame.ItemChooseText.top = 0, 20
MapQuestInfoRewardsFrame.ItemChooseText:Show()
MapQuestInfoRewardsFrame.activeRewardElements = {
    MapQuestInfoRewardsFrame.ItemChooseText, nativeXP, MapQuestInfoRewardsFrame.ItemReceiveText, nativeMoney,
}
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "1050", "choice and receive headers are both excluded")
equal(page.rewardButtons[2].Name:GetText(), "7 silver")
equal(Addon.lifecycle, "ready", "mixed native rewards do not suspend addon")
MapQuestInfoRewardsFrame.ItemChooseText:Hide()
equal(#body.lastSections, 5, "native quest content only")
QuestInfoDescriptionText:SetFont("Fonts/CustomQuest.ttf", 13, "OUTLINE")
QuestInfoDescriptionText:SetTextColor(0.04, 0.03, 0.02, 1)
QuestInfoDescriptionText:SetShadowColor(0.1, 0.2, 0.3, 0.6)
QuestInfoDescriptionText:SetShadowOffset(2, -2)
QuestInfoDescriptionText:SetSpacing(1)
page:Show(entry)
equal(select(1, body.sections[5]:GetFont()), "Fonts/CustomQuest.ttf", "effective native font override")
equal(select(2, body.sections[5]:GetFont()), 13)
equal(select(3, body.sections[5]:GetFont()), "OUTLINE")
equal(select(1, body.sections[5]:GetTextColor()), 0.04)
equal(select(4, body.sections[5]:GetShadowColor()), 0.6)
equal(select(1, body.sections[5]:GetShadowOffset()), 2)
equal(body.sections[5]:GetSpacing(), 1)
local previousShows = shows
Addon:RefreshSelection()
equal(shows, previousShows, "refresh does not reset reading position")

local function press(button)
    local direction = ({PADDUP = "up", PADDDOWN = "down", PADDLEFT = "left", PADDRIGHT = "right"})[button]

    if direction then
        local current = SmartNavigation:GetCurrentButton()
        local target = current and current.navigationOverrides and current.navigationOverrides[direction]

        if type(target) == "function" then target = target() end
        if target then SmartNavigation:SelectButton(target); return false end
        return true
    end

    if button == "PADLTRIGGER" or button == "PADRTRIGGER" then
        local step = button == "PADLTRIGGER" and -1 or 1

        for index, panel in ipairs(manager.shownFrames) do
            if panel == manager.focusedFrame and manager.shownFrames[index + step] then
                focusNativeFrame(manager, manager.shownFrames[index + step])
                return false
            end
        end
    elseif button == "PAD2" and manager.focusedFrame.SmartNavigationCloseHandler then
        local frame = manager.focusedFrame

        if not frame:SmartNavigationCloseHandler() and frame.CloseButton then frame.CloseButton:Fire("OnClick") end
        return false
    elseif button == "PAD1" and SmartNavigation:GetCurrentButton() then
        local current = SmartNavigation:GetCurrentButton()

        if current.OnSmartNavClick then
            current:OnSmartNavClick()
        else
            if current.kind == "CheckButton" then current:SetChecked(not current:GetChecked()) end
            current:Fire("OnClick")
        end
        return false
    end

    return true
end
local function nativeScroll(offset)
    local scroll = SmartNavigation.scrollFrames[manager.focusedFrame]
    assert(scroll, "native focused window has a scroll target")
    scroll:SetVerticalScroll(math.max(0, math.min(scroll:GetVerticalScrollRange(),
        scroll:GetVerticalScroll() + offset)))

    if not scroll.maintainPreviousButtonOnScroll then
        SmartNavigation.currentButton = nil
    end
end
equal(press("PAD1"), true, "map actions pass through")
equal(press("PADDUP"), true, "addon does not capture D-pad")
equal(press("PADRSTICK"), true, "right-stick click is not captured")
equal(manager:GetActiveFrame(), WorldMapFrame, "opening English does not steal map focus")
equal(Addon.registeredPanel, Addon.panel, "English joins native window paging")
local registrations = manager.registrations
Addon:RefreshSelection()
equal(manager.registrations, registrations, "refresh does not register duplicate windows")
local frenchScroll = QuestMapFrame.DetailsFrame.ScrollFrame
local frenchContents = CreateFrame("Frame", nil, frenchScroll)
frenchContents:SetHeight(1000)
frenchScroll:SetScrollChild(frenchContents)
frenchScroll:SetVerticalScroll(90)
equal(press("PADRTRIGGER"), false, "native RT switches to English")
equal(Addon.current.mode, "reading")
equal(SmartNavigation.scrollFrames[Addon.panel], body.frame, "native right stick targets English")
equal(Addon.scrollHint.owner, body.frame.ScrollBar.Track.Thumb, "native R prompt sits on English thumb")
equal(Addon.panel.gamepadFooter.frame:IsShown(), true, "footer appears when the panel gains native focus")
nativeScroll(84)
equal(body.frame:GetVerticalScroll(), 84, "native right stick scrolls English")
equal(frenchScroll:GetVerticalScroll(), 90, "English scrolling leaves French unchanged")
equal(body.frame.ScrollBar.scrollPercentage, 84 / body.frame:GetVerticalScrollRange(),
    "controller scroll synchronizes native thumb")
nativeScroll(-84)
equal(body.frame:GetVerticalScroll(), 0)
equal(press("PADLTRIGGER"), false, "native LT returns to French")
equal(frenchScroll:GetVerticalScroll(), 90, "native return to French preserves its reading position")
frenchScroll:SetVerticalScroll(0)
equal(Addon.current.mode, "open", "native unfocus releases English reading")
equal(SmartNavigation.scrollFrames[Addon.panel], nil, "unfocus clears English scroll target")
equal(Addon.scrollHint:IsShown(), false, "unfocus hides English R prompt")
equal(Addon.panel.gamepadFooter.frame:IsShown(), false, "unfocus hides the legend")
frenchScroll:SetVerticalScroll(70)
equal(press("PADRTRIGGER"), false)
QuestMapFrame.DetailsFrame.questID = 943
Addon:RefreshSelection()
equal(press("PADLTRIGGER"), false)
equal(frenchScroll:GetVerticalScroll(), 0, "a different quest does not receive the old French reading position")
QuestMapFrame.DetailsFrame.questID = 399
Addon:RefreshSelection()
local inventory = CreateFrame("Frame", nil, UIParent)
manager:FrameShown(inventory, false, false)
equal(press("PADRTRIGGER"), false)
equal(manager:GetActiveFrame(), Addon.panel)
equal(press("PADRTRIGGER"), false, "RT can continue from English to another native window")
equal(manager:GetActiveFrame(), inventory)
equal(Addon.current.mode, "open", "another window releases English focus")
equal(press("PADLTRIGGER"), false)
equal(Addon.current.mode, "reading", "LT can return from another native window")
equal(press("PADLTRIGGER"), false)
manager:FrameHidden(inventory)
local frenchChild = CreateFrame("Frame", nil, QuestMapFrame.DetailsFrame.ScrollFrame)
frenchChild:SetHeight(1000)
QuestMapFrame.DetailsFrame.ScrollFrame:SetScrollChild(frenchChild)
nativeScroll(60)
equal(body.frame:GetVerticalScroll(), 0, "French scrolling leaves English unchanged")
equal(page.rewards:GetHeight(), 124, "French scrolling leaves English rewards unchanged")
equal(press("PADRTRIGGER"), false)
body:ScrollTo(math.huge)
equal(body.frame:GetVerticalScroll(), body.frame:GetVerticalScrollRange(), "last paragraph is reachable")
equal(body.frame.ScrollBar.scrollPercentage, 1, "native thumb reaches bottom")
equal(page.rewards:GetHeight(), 200, "English scrolling reveals all rewards at the bottom")
body.frame:Fire("OnMouseWheel", 1)
equal(body.frame:GetVerticalScroll(), body.frame:GetVerticalScrollRange() - 30, "native wheel scrolls once")
equal(page.rewards:GetHeight(), 170, "native wheel scrolling also retracts rewards")
body.frame:SetHeight(body.child:GetHeight() + 100)
body.frame:Fire("OnSizeChanged")
equal(body.frame:GetVerticalScroll(), 0, "larger viewport clamps scroll when all text fits")
body.frame:SetHeight(180)
body.frame:Fire("OnSizeChanged")
body:ScrollTo(-100)
equal(body.frame:GetVerticalScroll(), 0, "scroll clamps at top")
local soundsBeforeClose = #playedSounds
equal(press("PAD2"), false, "B closes translation only")
equal(playedSounds[#playedSounds], SOUNDKIT.IG_QUEST_LOG_CLOSE, "closing plays the native quest-log sound")
equal(#playedSounds, soundsBeforeClose + 1, "closing plays one sound")
Addon:RefreshSelection()
equal(#playedSounds, soundsBeforeClose + 1, "refreshing a collapsed panel does not repeat its sound")
equal(Addon.current.mode, "collapsed")
equal(Addon.panel:IsShown(), false)
equal(Addon.toggle:IsShown(), true)
equal(Addon.registeredPanel, nil, "collapsed Rosetta does not register a focus window")
equal(#manager.shownFrames, 1, "collapsed Rosetta leaves only the native map in window paging")
equal(press("PADLTRIGGER"), true, "collapsed Rosetta adds no LT focus target")
equal(press("PADRTRIGGER"), true, "collapsed Rosetta adds no RT focus target")
equal(Addon.toggle:IsVisible(), true, "collapsed panel keeps its bookmark visible")
equal(Addon.toggle.Icon:GetTexture(), [[Interface\AddOns\ForeverRosettaStone\media\icon]],
    "bookmark displays the Rosetta book icon")
equal(Addon.toggle.template, "LargeSideTabButtonTemplate", "reopen uses the native Profession side tab")
equal(Addon.toggle.Background.atlas, "common-sidetab", "tab retains native solid backing")
equal(Addon.toggle.HighlightTexture.atlas, "common-sidetab-hover", "tab retains native hover highlight")
near(Addon.toggle.points[1][4], -10, "tab overlaps the visible map border by two UI units")
Addon.toggle:Fire("OnMouseDown", "LeftButton")
equal(Addon.toggle.Icon.points[1][2], -2, "held click uses native pressed icon offset")
equal(Addon.toggle.Icon:IsShown(), true, "pressed tab retains the icon")
Addon.toggle:Fire("OnMouseUp", "LeftButton")
equal(Addon.toggle.Icon.points[1][2], -3, "release restores native icon offset")
Addon.toggle:Fire("OnMouseDown", "LeftButton")
Addon.toggle:Hide()
equal(Addon.toggle.Icon.points[1][2], -3, "hiding a pressed tab resets icon position")
Addon.toggle:Show()
Addon.toggle:Fire("OnClick")
equal(playedSounds[#playedSounds], SOUNDKIT.IG_QUEST_LOG_OPEN, "reopening plays the native quest-log sound")
equal(#playedSounds, soundsBeforeClose + 2, "reopening plays one sound")
Addon:RefreshSelection()
equal(#playedSounds, soundsBeforeClose + 2, "refreshing an open panel does not repeat its sound")
equal(Addon.current.mode, "open", "clicking the book reopens the translation")
equal(Addon.toggle:IsShown(), false, "mouse reopening hides the bookmark")
Addon.panel.CloseButton:Fire("OnClick")
SmartNavigation:SelectButton(Addon.toggle)
equal(Addon.current.mode, "bookmarkFocused", "native D-pad selection enters the bookmark state")
equal(manager:GetActiveFrame(), WorldMapFrame, "bookmark selection keeps the map as the focused window")
equal(SmartNavigation:GetCurrentButton(), Addon.toggle, "native map navigation selects the bookmark")
equal(press("PAD1"), false, "A activates the selected bookmark")
equal(Addon.current.mode, "reading", "gamepad reopen returns focus to translation")
equal(Addon.toggle:IsShown(), false, "bookmark withdraws when panel is open")
equal(Addon.lifecycle, "ready", "bookmark reopening does not call unwrapped focus APIs")
equal(SmartNavigation.lastButtons[WorldMapFrame] == Addon.toggle, false,
    "opening English does not cache the hidden bookmark as the map's return target")
equal(manager:GetActiveFrame(), Addon.panel, "reopening hands native window focus to English")
equal(SmartNavigation:GetCurrentButton(), nil, "English opens without selecting an action")
equal(Addon.panel.CloseButton:IsShown(), false, "gamepad mode hides the X")
equal(Addon.panel.gamepadFooter.frame:IsShown(), true, "focused gamepad panel shows the addon legend")
equal(Addon.panel.gamepadFooter.prompts[1].icon.inputKey, GAMEPAD_FACE_BOTTOM, "legend draws the Select input icon")
equal(Addon.panel.gamepadFooter.prompts[2].text:GetText(), FRAME_ACTION_CLOSE, "legend draws the localized Close label")
nativeScroll(30)
equal(body.frame:GetVerticalScroll(), 30, "right stick scrolls after bookmark reopening")
equal(SmartNavigation:GetCurrentButton(), nil, "scrolling does not select an action")
SmartNavigation:SelectButton(Addon.panel.ReportButton)
Addon:SyncControllerFocus()
equal(SmartNavigation:GetCurrentButton(), Addon.panel.ReportButton, "refresh preserves an explicitly selected action")
equal(press("PAD2"), false, "B closes the focused translation")
equal(Addon.current.mode, "collapsed", "native Back handler collapses translation")
equal(Addon.panel.gamepadFooter.frame:IsShown(), false, "closing the panel hides the footer")
equal(Addon.registeredPanel, nil, "closing English removes its window registration")
equal(press("PAD2"), true, "collapsed Rosetta leaves Back to the native map")
equal(Addon.current.mode, "collapsed", "Back keeps translation collapsed")
equal(SmartNavigation:GetCurrentButton() == Addon.toggle, false,
    "returning from English does not select the bookmark automatically")
local nativeQuestRow = CreateFrame("Button", nil, QuestScrollFrame)
SmartNavigation:SelectButton(nativeQuestRow)
Addon:RefreshSelection()
equal(SmartNavigation:GetCurrentButton(), nativeQuestRow, "refresh preserves native quest focus")
equal(Addon.current.mode, "collapsed", "native quest focus does not select the bookmark state")
SmartNavigation:SelectButton(Addon.toggle)
equal(Addon.current.mode, "bookmarkFocused", "manual selection enters bookmark focus before Back")
equal(Addon:GetWidgetTooltip():IsShown(), true, "manual bookmark selection shows its tooltip")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "bookmark focus cannot inherit a quest tooltip from its details parent")
equal(Addon:GetWidgetTooltip():GetOwner(), Addon.toggle, "bookmark keeps its own reopen tooltip")
SmartNavigation:SelectButton(nativeQuestRow)
equal(Addon:GetWidgetTooltip():IsShown(), false, "leaving bookmark focus hides its reopen tooltip")
SmartNavigation:SelectButton(Addon.toggle)
QuestMapFrame.DetailsFrame:Hide()
equal(Addon.current.mode, "unavailable", "returning to the quest list withdraws Rosetta")
equal(Addon.toggle:IsVisible(), false, "bookmark is absent from the quest list")
equal(SmartNavigation:GetCurrentButton() == Addon.toggle, false,
    "leaving details clears selection of the hidden bookmark")
equal(Addon:GetWidgetTooltip():IsShown(), false, "leaving details clears the bookmark tooltip")
SmartNavigation:SelectButton(nativeQuestRow)
Addon:RefreshSelection()
equal(SmartNavigation:GetCurrentButton(), nativeQuestRow, "quest-list refresh does not steal native focus")
QuestMapFrame.DetailsFrame:Show()
Addon:RefreshSelection()
Addon:Send("panel.close")
equal(SmartNavigation:GetCurrentButton(), nativeQuestRow,
    "showing the bookmark waits for manual D-pad selection")
GameMenuFrame:Show()
equal(Addon.registeredPanel, nil, "menu does not register a collapsed Rosetta window")
GameMenuFrame:Hide()
equal(Addon.registeredPanel, nil, "closing menu leaves collapsed Rosetta outside window paging")
SmartNavigation:SelectButton(Addon.toggle)
combat = true
equal(press("PAD1"), false, "native activation reaches the bookmark in combat")
equal(Addon.current.mode, "bookmarkFocused", "combat refuses opening and preserves bookmark selection")
combat = false
SmartNavigation:HideCursor()
equal(SLASH_FOREVERROSETTASTONE1, "/frs", "FRS slash command is registered")
SlashCmdList.FOREVERROSETTASTONE("quest")
equal(Addon.current.mode, "open", "slash command reopens collapsed panel")
equal(press("PADRTRIGGER"), false)
equal(Addon.current.mode, "reading", "native focus enters reopened panel")
equal(press("PADLTRIGGER"), false)

-- These real DB quests share a title but represent different quest stages.
QuestMapFrame.DetailsFrame.questID = 731
nativeXP.Name:SetText("500")
hooks.QuestMapFrame_ShowQuestDetails()
equal(Addon.current.questID, 731)
equal(entry.title, "The Absent Minded Prospector")
equal(entry.progress, "Escort Prospector Remtravel")
equal(body.sections[1]:GetText(), "[20] The Absent Minded Prospector")
equal(page.rewardButtons[1].Name:GetText(), "500", "second quest reads its current rewards")
escortFinished = true
events:Fire("OnEvent", "QUEST_LOG_UPDATE")
equal(entry.progress, "Escort Prospector Remtravel (Complete)")
local escortRow = CreateFrame("Button", nil, QuestScrollFrame)
escortRow.info = {questID = 731}
GameTooltip:SetOwner(escortRow, "ANCHOR_RIGHT")
GameTooltipTextLeft1:SetText("Les absences du Prospecteur")
GameTooltip:Show()
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:GetText(), "The Absent Minded Prospector", "second quest tooltip")
escortRow.info.questID = 943
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "stone-and-fossil stage has a hover translation")
equal(Addon.tooltip.lines[2], Addon:GetQuest(943).summary, "hover uses collection summary, not escort")
equal(Addon.tooltip.lines[4], "- Stone of Relu: 0/1")
equal(Addon.tooltip.lines[5], "- Flagongut's Fossil: 0/1")
QuestMapFrame.DetailsFrame.questID = 943
hooks.QuestMapFrame_ShowQuestDetails()
equal(Addon.current.questID, 943, "collection stage opens its own translation")
equal(Addon.panel:IsShown(), true)
equal(entry.objectives, Addon:GetQuest(943).summary)
equal(body.sections[5]:GetText(), Addon:GetQuest(943).description, "collection description replaces escort")
equal(entry.progress, "Stone of Relu: 0/1\nFlagongut's Fossil: 0/1")
local nativeChoices = {}

for index, name in ipairs({"Lame de relique", "Broie-crâne", "Robe d'archéologue"}) do
    local item = CreateFrame("Button", nil, MapQuestInfoRewardsFrame, "SmallItemButtonTemplate")
    item:SetID(index)
    item.type, item.objectType = "choice", "item"
    item.left, item.top = (index % 2 == 0 and 140 or 0), -math.floor((index - 1) / 2) * 32
    item.Name:SetText(name)
    item.IconBorder = item:CreateTexture(nil, "OVERLAY", nil, 1)
    item.IconBorder:SetTexture([[Interface\Common\WhiteIconFrame]])
    item.IconBorder:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    item.IconBorder:SetVertexColor(0.12, 1, 0)
    item.IconBorder:SetAlpha(0.8)
    nativeChoices[index] = item
end

nativeChoices[2].IconBorder:SetVertexColor(0, 0.44, 0.87)
nativeChoices[3].IconBorder:Hide()
nativeChoices[1].Icon:SetVertexColor(0.9, 0, 0)
nativeChoices[1].NameFrame:SetVertexColor(0.9, 0, 0)
MapQuestInfoRewardsFrame.activeRewardElements = nativeChoices
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "Relic Blade", "choice item name translated by item ID")
equal(page.rewardButtons[2].Name:GetText(), "Skullchipper")
equal(page.rewardButtons[3].Name:GetText(), "Archaeologist's Gown")
equal(nativeChoices[1].Name:GetText(), "Lame de relique", "French item label stays intact")
equal(select(2, page.rewardButtons[1].Icon:GetVertexColor()), 0, "native unusable-item tint copied")
equal(select(2, page.rewardButtons[1].NameFrame:GetVertexColor()), 0, "native reward card tint copied")
equal(page.rewardButtons[1].IconBorder ~= nil, true, "reward card has a native quality border")
equal(page.rewardButtons[1].IconBorder:IsShown(), true, "uncommon reward border is visible")
equal(page.rewardButtons[1].IconBorder:GetTexture(), [[Interface\Common\WhiteIconFrame]],
    "quality border uses native artwork")
equal(select(1, page.rewardButtons[1].IconBorder:GetVertexColor()), 0.12, "uncommon border red matches native")
equal(select(2, page.rewardButtons[1].IconBorder:GetVertexColor()), 1, "unusable item retains its green quality border")
equal(page.rewardButtons[1].IconBorder:GetAlpha(), 0.8, "quality border opacity follows native")
equal(select(1, page.rewardButtons[1].IconBorder:GetTexCoord()), 0.1, "quality border crop follows native")
equal(select(3, page.rewardButtons[2].IconBorder:GetVertexColor()), 0.87, "rare reward has its native blue border")
equal(page.rewardButtons[3].IconBorder:IsShown(), false, "hidden native border stays hidden")
checks = checks + assert(loadfile("tests/lua/test-reward-tooltips.lua"))(
    Addon, page, nativeChoices,
    function(value) mouseFoci = value end,
    function(value) style = value end,
    press
)
nativeChoices[1].IconBorder:SetVertexColor(0.64, 0.21, 0.93)
page:RefreshNativeLayout()
equal(select(1, page.rewardButtons[1].IconBorder:GetVertexColor()), 0.64, "quality changes refresh on reused cards")
choiceItems[1] = 999999
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "Lame de relique", "unknown item preserves native label")
nativeChoices[1].type = "reward"
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "Relic Blade", "fixed reward names use reward query")
MapQuestInfoRewardsFrame.activeRewardElements = {nativeXP, nativeMoney}
page:RefreshNativeLayout()
equal(page.rewardButtons[1].Name:GetText(), "500", "recycled item card returns to numeric XP")
equal(select(2, page.rewardButtons[1].Icon:GetVertexColor()), 1, "recycled item tint resets")
equal(page.rewardButtons[1].IconBorder:IsShown(), false, "XP clears a reused item's quality border")
equal(page.rewardButtons[2].IconBorder:IsShown(), false, "money clears a reused item's quality border")
fossilFulfilled = 1
events:Fire("OnEvent", "QUEST_LOG_UPDATE")
Addon:ShowTranslationTooltip()
equal(entry.progress, "Stone of Relu: 0/1\nFlagongut's Fossil: 1/1", "second objective updates independently")
equal(body.sections[3]:GetText(), entry.progress, "both objectives appear in quest details")
equal(Addon.tooltip.lines[4], "- Stone of Relu: 0/1")
equal(Addon.tooltip.lines[5], "- Flagongut's Fossil: 1/1", "second objective updates hover")
stoneFulfilled = 1
events:Fire("OnEvent", "QUEST_LOG_UPDATE")
equal(entry.progress, "Stone of Relu: 1/1\nFlagongut's Fossil: 1/1", "both objectives complete")
Addon:Send("panel.close")
Addon.toggle:Fire("OnClick")
equal(press("PADRTRIGGER"), false)
equal(Addon.current.mode, "reading", "native focus reads collection translation")
equal(Addon.current.questID, 943)
escortRow.info.questID = 942
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:GetText(), Addon:GetQuest(942).title, "same-title quest 942 resolves by its own ID")
equal(Addon.tooltip.lines[2], Addon:GetQuest(942).summary, "same-title quest 942 retains its own summary")
escortRow.info.questID = 999999999
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "an unknown ID cannot substitute a same-title quest")
QuestMapFrame.DetailsFrame.questID = 399
hooks.QuestMapFrame_ShowQuestDetails()
equal(Addon.current.questID, 399)
equal(entry.progress, "A Simple Compass: 0/1", "switching back restores compass progress")
GameTooltip:Hide()

fulfilled = 1
events:Fire("OnEvent", "QUEST_LOG_UPDATE")
equal(entry.progress, "A Simple Compass: 1/1", "live objective counts")
combat = true
Addon:RefreshSelection()
equal(Addon.registeredPanel, Addon.panel, "native registration is not mutated during combat")
equal(press("PADRSTICK"), true, "combat input passes through")
combat = false
events:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
style = "0"
Addon:RefreshSelection()
equal(Addon.registeredPanel, nil, "mouse mode releases native registration")
equal(Addon.panel.CloseButton:IsShown(), true, "mouse mode restores the X")
equal(Addon.panel.gamepadFooter.frame:IsShown(), false, "mouse mode hides the gamepad footer")
equal(Addon.panel.TitleContainer.points[2][4], -35, "mouse title stays centered")
equal(press("PADRSTICK"), true, "mouse interface input passes through")
style = "1"
Addon:RefreshSelection()
equal(press("PADRTRIGGER"), false)
equal(Addon.current.mode, "reading", "input-mode teardown begins with active English focus")
equal(Addon.panel.CloseButton:IsShown(), false, "switching back to gamepad hides the X")
equal(Addon.panel.TitleContainer.points[2][4], -35, "gamepad title keeps the same center")
combat = true
style = "0"
manager.shownFrames, manager.focusedFrame = {}, nil
SmartNavigation.panels, SmartNavigation.scrollFrames = {}, {}
SmartNavigation.targetButtons, SmartNavigation.lastButtons = {}, {}
SmartNavigation.currentButton, SmartNavigation.activeFrame = nil, nil
for _, callback in pairs(inputTransitions) do callback() end
equal(Addon.current.mode, "open", "input-mode teardown clears the reading state even in combat")
equal(Addon.panel.CloseButton:IsShown(), true, "input transition immediately restores the mouse X in combat")
equal(Addon.panel.gamepadFooter.frame:IsShown(), false, "input transition immediately hides the footer in combat")
equal(Addon.registeredPanel, nil, "input-mode teardown invalidates stale native registration in combat")
Addon:RefreshSelection()
style = "1"
manager.shownFrames, manager.focusedFrame = {WorldMapFrame}, WorldMapFrame
SmartNavigation.panels[WorldMapFrame] = true
SmartNavigation.activeFrame = WorldMapFrame
for _, callback in pairs(inputTransitions) do callback() end
combat = false
events:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
equal(#manager.shownFrames, 2, "combat input-mode round-trip restores native English registration")
equal(press("PADRTRIGGER"), false, "English remains reachable after native input-mode teardown")
equal(Addon.current.mode, "reading", "input-mode recovery restores functional English focus")
equal(press("PADLTRIGGER"), false)
GameMenuFrame:Show()
equal(Addon.registeredPanel, nil, "menu releases native registration")
equal(press("PADRSTICK"), true, "menu input passes through")
GameMenuFrame:Hide()

-- A pooled quest row's ID must be read again, rather than cached by its frame.
local row = CreateFrame("Button", nil, QuestScrollFrame)
row.info = {questID = 399}
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
GameTooltipTextLeft1:SetText("Débuts modestes")
GameTooltip:Show()
GameTooltip:ClearLines()
GameTooltip:AddLine("Native controller command")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "hover companion")
equal(Addon.tooltip.text, "Humble Beginnings")
equal(GameTooltip:GetOwner(), row, "original tooltip owner preserved")
equal(Addon.tooltip.points[1][2], GameTooltip, "quest-list companion sits beside the original")
equal(Addon.tooltip.points[1][3], "TOPRIGHT")
equal(#Addon.tooltip.lines, 4, "translated tooltip contains only quest content")
equal(GameTooltip.lines[1], "Native controller command", "original tooltip commands stay intact")
equal(#GameTooltip.lines, 1, "translated tooltip does not change native tooltip lines")
style = "0"
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 4, "mouse tooltip also omits the green command footer")
near(Addon.tooltip.points[1][4], Addon:GetTooltipGap(Addon.tooltip), "quest companion uses the shared horizontal gap")
local previousTurnInLabel = Addon.GetClientLabel
Addon.GetClientLabel = function(_, key, locale) return ForeverRosettaStoneDB:GetGlobalStringByKey(key, locale) end
completedQuests[399] = true
Addon:ShowTranslationTooltip()
equal(Addon.tooltip.lines[2], "Ready for turn-in", "completed quest replaces its summary with the native turn-in GlobalString")
equal(#Addon.tooltip.lines, 2, "completed quest does not repeat finished objectives")
local previousCompletion, previousLogIndex = GetQuestLogCompletionText, C_QuestLog.GetLogIndexForQuestID
C_QuestLog.GetLogIndexForQuestID = function(id) return id == 399 and 4 or previousLogIndex(id) end
local nativeSummary = Addon:FormatQuestText(ForeverRosettaStoneDB:GetQuest(399, GetLocale()).summary, 399, GetLocale())
GetQuestLogCompletionText = function(index) return index == 4 and nativeSummary or nil end
Addon.tooltipKey = nil
Addon:ShowTranslationTooltip()
equal(Addon.tooltip.lines[2], Addon:FormatQuestText(Addon:GetQuest(399).summary, 399),
    "completion text that is the quest summary translates through the owned summary")
GetQuestLogCompletionText = function() return "Unowned native completion text" end
Addon.tooltipKey = nil
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 0, "completion text without owned data adds no guessed line or spacer")
GetQuestLogCompletionText, C_QuestLog.GetLogIndexForQuestID = previousCompletion, previousLogIndex
Addon.tooltipKey = nil
Addon.GetClientLabel = previousTurnInLabel
completedQuests[399] = false
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 4, "quest becoming incomplete restores summary and progress")
style = "1"
row.info.questID = 999999999
GameTooltipTextLeft1:SetText("Other quest")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "recycled row clears old translation")
GameTooltip:SetOwner(UIParent, "ANCHOR_RIGHT")
GameTooltipTextLeft1:SetText("Débuts modestes")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "a known title outside the quest list does not create a translation")
row.info = nil
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "a title without a quest ID does not create a translation")
QuestScrollFrame:Hide()
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "hidden quest-list rows cannot leave a stale companion")
QuestScrollFrame:Show()
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "returning to the list does not resolve an unidentifiable quest")
GameTooltip:Hide()
equal(Addon.tooltip:IsShown(), false, "source tooltip hides companion")

local locationHeader = CreateFrame("Button", nil, QuestScrollFrame)
locationHeader.left, locationHeader.top = 700, 800
locationHeader.questLogIndex = 77
questLogEntries[77] = { isHeader = true, title = "Hurlevent" }
SmartNavigation:SelectButton(locationHeader)
Addon:ShowTranslationTooltip()
equal(Addon.locationTooltip == nil or not Addon.locationTooltip:IsShown(), true,
    "A location header without an area ID stays native")
mouseFoci = {locationHeader}
Addon:ShowTranslationTooltip()
equal(Addon.locationTooltip == nil or not Addon.locationTooltip:IsShown(), true,
    "Hovering a title-only location header stays native")
local mapChildren = { mapInfo[1424], mapInfo[1437] }
C_Map.GetMapChildrenInfo = function(rootID, mapType, descendants)
    equal(rootID, 947, "header lookup uses the live map root")
    equal(descendants, true, "header lookup includes other continents")
    return mapChildren
end
questLogEntries[77].title = "Les Paluns"
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), true, "live map IDs restore quest header translations")
equal(Addon.locationTooltip.lines[2], "Wetlands", "header uses the target map name")
mouseFoci = {}
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), true, "gamepad selection resolves the same live header ID")
do
    local questRow = CreateFrame("Button", nil, QuestScrollFrame)
    local accurateLines = Addon.tooltip.accurateLines
    Addon.tooltip.accurateLines = true
    Addon.tooltipKey = nil
    questRow.info = {questID = 399}
    mouseFoci = {questRow}
    GameTooltip:SetOwner(questRow, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Débuts modestes")
    GameTooltip:Show()
    Addon:ShowTranslationTooltip()
    equal(Addon.tooltip:IsShown(), true, "mouse quest translation coexists with a gamepad header selection")
    equal(Addon.tooltip:GetText(), "Humble Beginnings", "mixed input keeps the hovered quest translation")
    equal(Addon.locationTooltip:IsShown(), true, "mixed input retains the gamepad header translation")
    equal(Addon.locationTooltip.lines[2], "Wetlands", "mixed input keeps the selected header name")
    equal(Addon.locationTooltip.points[1][2], GameTooltip, "mixed input places the header around the quest tooltip")
    Addon.preferences.tooltipMode = "stacked"
    Addon:ShowTranslationTooltip()
    local hasQuestTranslation = false
    for index = 1, GameTooltip:NumLines() do
        if GameTooltip:GetLeftLine(index):GetText() == "Humble Beginnings" then hasQuestTranslation = true end
    end
    equal(hasQuestTranslation, true, "stacked mode retains the hovered quest translation alongside the header")
    equal(Addon.locationTooltip:IsShown(), true, "stacked mode retains the independent header translation")
    Addon:ClearStackedTooltip(GameTooltip)
    Addon.preferences.tooltipMode = "separate"
    GameTooltip:Hide()
    mouseFoci = {}
    Addon:ShowTranslationTooltip()
    equal(Addon.tooltip:IsShown(), false, "leaving the quest hides only its translation")
    equal(Addon.locationTooltip:IsShown(), true, "leaving the quest retains the selected header translation")
    Addon.tooltip.accurateLines = accurateLines
end
Addon:SetFeatureEnabled("locationTooltip", false)
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "header opt-out hides resolved translations")
Addon:SetFeatureEnabled("locationTooltip", true)
mouseFoci = {locationHeader}
questLogEntries[77].title = "Les Paluns (Wetlands)"
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), true, "verified English suffix is accepted on native headers")
questLogEntries[77].title = "Les Paluns (Unrelated)"
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "unverified header suffix stays native")
mapChildren = { mapInfo[9998] }
questLogEntries[77].title = "Unknown place"
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "an identified header without a translation stays native")
mapChildren = { mapInfo[1437], { mapID = 9998, name = "Les Paluns" } }
questLogEntries[77].title = "Les Paluns"
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "ambiguous live header names stay native")
C_Map.GetMapChildrenInfo = nil
local oldHeaderAreaInfo = C_Map.GetAreaInfo
local headerAreas = { [719] = "Profondeurs de Brassenoire", [1581] = "Les Mortemines", [3277] = "Goulet des Chanteguerres",
    [999999] = "Unknown instance" }
C_Map.GetAreaInfo = function(id) return headerAreas[id] end
questLogEntries[77].title, questLogEntries[77].headerSortKey = "Les Mortemines", 1581
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip.lines[2], "The Deadmines", "verified area sort keys resolve dungeon headers without a UI map")
equal(Addon.locationTooltip:IsShown(), true, "dungeon header translation is visible")
do
    local previousStyle, previousActive = style, SmartNavigation.activeFrame
    -- Captured from the Forever quest log: the area sort key carries bit 30.
    questLogEntries[77].title = "Profondeurs de Brassenoire"
    questLogEntries[77].headerSortKey = 1073742543
    for _, gamepad in ipairs({false, true}) do
        style = gamepad and "1" or "0"
        mouseFoci = gamepad and {} or {locationHeader}
        SmartNavigation.activeFrame = QuestMapFrame
        Addon:ShowLocationTooltip()
        equal(Addon.locationTooltip:IsShown(), true, "captured tagged dungeon header renders in both input modes")
        equal(Addon.locationTooltip.lines[2], "Blackfathom Deeps", "tagged sort key resolves the owned area translation")
    end
    style, SmartNavigation.activeFrame = previousStyle, previousActive
    mouseFoci = {locationHeader}
    questLogEntries[77].title, questLogEntries[77].headerSortKey = "Les Mortemines", 1073743405
    Addon:ShowLocationTooltip()
    equal(Addon.locationTooltip.lines[2], "The Deadmines", "tagged area decoding works for other dungeons")
    questLogEntries[77].title = "Unrelated category"
    Addon:ShowLocationTooltip()
    equal(Addon.locationTooltip:IsShown(), false, "decoded IDs still require the client's matching area name")
    questLogEntries[77].title, questLogEntries[77].headerSortKey = "Les Mortemines", 2147485229
    Addon:ShowLocationTooltip()
    equal(Addon.locationTooltip:IsShown(), false, "unknown sort-key tags are not stripped")
    questLogEntries[77].headerSortKey = 1581
end
do
    local previousActive = SmartNavigation.activeFrame
    local otherHeader = CreateFrame("Button", nil, QuestScrollFrame)
    otherHeader.questLogIndex = 78
    questLogEntries[78] = {isHeader = true, title = "Goulet des Chanteguerres", headerSortKey = 3277}
    mouseFoci = {otherHeader}
    SmartNavigation.activeFrame = QuestMapFrame
    Addon:ShowLocationTooltip()
    equal(Addon.locationTooltip.lines[2], "The Deadmines", "nested quest-panel gamepad focus wins over a parked mouse")
    mouseFoci = {}
    SmartNavigation.activeFrame = QuestScrollFrame
    Addon:ShowLocationTooltip()
    equal(Addon.locationTooltip:IsShown(), true, "quest-list navigation resolves dungeon headers without mouse hover")
    equal(Addon.locationTooltip.lines[2], "The Deadmines", "mouse and gamepad resolve the same dungeon name")
    SmartNavigation.activeFrame = previousActive
    mouseFoci = {locationHeader}
    questLogEntries[78] = nil
end
questLogEntries[77].title, questLogEntries[77].headerSortKey = "Goulet des Chanteguerres", 3277
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip.lines[2], "Warsong Gulch", "verified area sort keys resolve battleground headers")
questLogEntries[77].title = "Unrelated category"
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "a sort key is not an area identity unless its native name agrees")
questLogEntries[77].title, questLogEntries[77].headerSortKey = "Les Mortemines", -1581
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "negative quest categories are not treated as area IDs")
questLogEntries[77].title, questLogEntries[77].headerSortKey = "Unknown instance", 999999
Addon:ShowLocationTooltip()
equal(Addon.locationTooltip:IsShown(), false, "untranslated dungeon headers stay native")
questLogEntries[77].headerSortKey = nil
C_Map.GetAreaInfo = oldHeaderAreaInfo
questLogEntries[77].title = "Hurlevent"
mouseFoci = {}
SmartNavigation.currentButton = nil
local questPin = CreateFrame("Button", nil, WorldMapFrame)
stoneFulfilled, fossilFulfilled = 0, 0
questPin.pinTemplate = "QuestPinTemplate"
questPin.questID = 943
function questPin:GetQuestID() return self.questID end
function questPin:GetMap() return WorldMapFrame end
local selectedBeforePin = SmartNavigation:GetCurrentButton()
QuestMapFrame.DetailsFrame:Hide()
QuestScrollFrame:Hide()
GameTooltip:SetOwner(questPin, "ANCHOR_RIGHT")
GameTooltipTextLeft1:SetText("[24] Les absences du Prospecteur")
GameTooltip:ClearLines()
GameTooltip:AddLine("Native map controller commands")
GameTooltip:Show()
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.current.mode, "unavailable", "map quest translation does not require quest details")
equal(Addon.tooltip:IsShown(), true, "controller map quest marker shows its English companion")
equal(Addon.tooltip:GetText(), "The Absent Minded Prospector", "map marker resolves its quest ID")
equal(Addon.tooltip.points[1][2], GameTooltip, "map companion follows the native quest tooltip")
equal(Addon.tooltip.points[1][3], "TOPRIGHT", "map companion sits right of the native tooltip")
equal(#Addon.tooltip.lines, 2, "map companion contains only both live objectives below its title")
equal(Addon.tooltip.lines[1], "- Stone of Relu: 0/1", "map objectives start immediately below the title")
equal(Addon.tooltip.lines[2], "- Flagongut's Fossil: 0/1", "map companion omits the summary paragraph")
completedQuests[943] = true
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 0, "completed map pins show no objectives or invented turn-in status")
equal(Addon.tooltip:GetText(), "The Absent Minded Prospector", "completed map pins retain the translated title without a level")
completedQuests[943] = false
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 2, "incomplete map pins restore their live objectives")
equal(Addon.tooltip.titleColor[1], 1, "map quest title follows native difficulty red")
equal(Addon.tooltip.titleColor[2], 0.1, "map quest title does not use generic gold")
equal(Addon.tooltip.titleColor[3], 0.1, "map quest title uses all native difficulty channels")
equal(GameTooltip.lines[1], "Native map controller commands", "native map commands remain untouched")
equal(GameTooltip:GetOwner(), questPin, "map translation keeps the native pin tooltip owner")
equal(SmartNavigation:GetCurrentButton(), selectedBeforePin, "map companion does not change native selection")
mapDifficultyColor = {0.1, 1, 0.1}
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.tooltip.titleColor[1], 0.1, "difficulty updates without an objective or quest change")
equal(Addon.tooltip.titleColor[2], 1, "updated difficulty color is reflected in the open tooltip")
showDifficultyColor = false
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.tooltip.titleColor[1], 1, "disabling native difficulty color restores white")
equal(Addon.tooltip.titleColor[2], 1, "native difficulty preference is respected")
equal(Addon.tooltip.titleColor[3], 1, "disabled difficulty color is neutral instead of gold")
showDifficultyColor = true
QuestScrollFrame:Show()
SmartNavigation:HideCursor()
row.info = { questID = 943 }
GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 5, "returning to the same quest in the list restores its summary")
equal(Addon.tooltip.titleColor[2], 0.82, "quest-list title retains its existing gold color")
GameTooltip:SetOwner(questPin, "ANCHOR_RIGHT")
Addon:ShowTranslationTooltip()
equal(#Addon.tooltip.lines, 2, "returning to the same map quest removes the list summary again")
equal(Addon.tooltip.titleColor[2], 1, "returning to the map restores difficulty color")
QuestScrollFrame:Hide()
row.info = nil
stoneFulfilled = 1
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.tooltip.lines[1], "- Stone of Relu: 1/1", "map companion updates objective progress")
stoneFulfilled = 0
style = "0"
GameTooltip:SetOwner(questPin, "ANCHOR_CURSOR_RIGHT")
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "mouse map quest hover also shows its translation")
style = "1"
QuestScrollFrame:Show()
SmartNavigation:SelectButton(locationHeader)
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), true, "hovered map pin takes priority over an old controller header selection")
equal(Addon.locationTooltip:IsShown(), false, "map tooltip cannot compete with a stale location companion")
SmartNavigation:HideCursor()
questPin.questID = 999999999
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "recycled unsupported map quest cannot inherit another stage's text")
questPin.questID = 943
questPin:Hide()
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "hidden map quest marker cannot retain its translation")
questPin:Show()
questPin.pinTemplate = nil
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "released map pin loses tooltip eligibility")
questPin.pinTemplate = "AreaPOIPinTemplate"
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "unrelated map markers cannot show a quest companion")
questPin.pinTemplate = "QuestPinTemplate"
function questPin:GetMap() return UIParent end
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "quest pins on other map surfaces remain excluded")
function questPin:GetMap() return WorldMapFrame end
Addon:ShowTranslationTooltip()
GameTooltip:Hide()
equal(Addon.tooltip:IsShown(), false, "leaving map marker clears its companion immediately")
GameTooltip:Show()
WorldMapFrame:Hide()
Addon:ShowTranslationTooltip()
equal(Addon.tooltip:IsShown(), false, "closing map clears its quest marker companion")
GameTooltip:Hide()
WorldMapFrame:Show()
QuestMapFrame.DetailsFrame:Show()
Addon:RefreshSelection()

nativeAreaLabel.Name:SetText("Comté-de-l'Or")
nativeAreaLabel.Name:SetTextColor(1, 0.82, 0, 0.9)
nativeAreaLabel.Description:SetTextColor(1, 1, 1, 1)
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapLocationLabel:IsShown(), false, "A map label without an area ID stays native")
equal(nativeAreaLabel.Name:GetText(), "Comté-de-l'Or", "Native map name stays unchanged")
local canvasFocused, hoveredMapID = true, 1437
function WorldMapFrame:IsCanvasMouseFocus() return canvasFocused end
function WorldMapFrame:GetNormalizedCursorPosition() return 0.4, 0.6 end
C_Map.GetMapInfoAtPosition = function(mapID, x, y)
    equal(mapID, viewedMapID, "hover lookup uses the viewed map")
    equal(x, 0.4, "hover lookup uses the cursor x")
    equal(y, 0.6, "hover lookup uses the cursor y")
    return mapInfo[hoveredMapID]
end
viewedMapID = 1415
nativeAreaLabel.Name:SetText("Les Paluns")
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), true, "continent hover translates the child map ID")
equal(Addon.mapLocationLabel.Text:GetText(), "Wetlands", "continent hover uses the owned map translation")
equal(nativeAreaLabel.Name:GetText(), "Les Paluns", "continent hover preserves the native label")
Addon:SetFeatureEnabled("mapLocationLabel", false)
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), false, "map hover opt-out hides identified translations")
Addon:SetFeatureEnabled("mapLocationLabel", true)
viewedMapID, hoveredMapID = 947, 1415
nativeAreaLabel.Name:SetText("Royaumes de l'est")
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel.Text:GetText(), "Eastern Kingdoms", "world hover translates a continent ID")
viewedMapID, hoveredMapID = 1415, 1437
nativeAreaLabel.Name:SetText("Les Paluns|cffff0000 (20-30)|r")
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), true, "native map level decoration keeps the translation")
nativeAreaLabel.Name:SetText("Unrelated point of interest")
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), false, "a higher-priority native label does not inherit the hovered map")
nativeAreaLabel.Name:SetText("Les Paluns")
canvasFocused = false
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), false, "leaving the map clears the hover translation")
canvasFocused, hoveredMapID = true, 9998
nativeAreaLabel.Name:SetText("Unknown place")
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), false, "missing map translation leaves the native name")
hoveredMapID = nil
Addon:ShowMapLocationLabel()
equal(Addon.mapLocationLabel:IsShown(), false, "missing hover identity clears the translation")
C_Map.GetMapInfoAtPosition = nil
WorldMapFrame.IsCanvasMouseFocus, WorldMapFrame.GetNormalizedCursorPosition = nil, nil
viewedMapID = 1424
nativeAreaLabel.Name:SetTextColor(0.2, 0.7, 0.3, 1)
nativeAreaLabel.Name:SetText("")
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextTooltip, nil, "bottom-right map tooltip has been removed")
equal(Addon.mapContextLabel:IsVisible(), true, "map context is visible without hover or controller selection")
equal(Addon.mapContextLabel.Text:GetText(), "Eastern Kingdoms - Hillsbrad Foothills",
    "plain label displays the hyphen-separated path without a logo")
equal(Addon.mapContextLabel.points[1][1], "BOTTOM", "map context is centered above the place name")
equal(Addon.mapContextLabel.points[1][2], nativeAreaLabel.Name, "context follows the native map place name")
equal(Addon.mapContextLabel.points[1][3], "TOP", "map context joins the top of the native place name")
equal(Addon.mapContextLabel.points[1][4], 0, "map context has no horizontal offset")
equal(Addon.mapContextLabel.points[1][5], 8, "map context leaves space above the native name")
near(Addon.mapContextLabel:GetEffectiveScale(), nativeAreaLabel:GetEffectiveScale(),
    "context follows the native map-label scale")
equal(select(2, Addon.mapContextLabel.Text:GetFont()), 16, "map context uses the smaller native subtitle font")
equal(select(1, Addon.mapContextLabel.Text:GetTextColor()), 0.2, "map context matches native place-name red")
equal(select(2, Addon.mapContextLabel.Text:GetTextColor()), 0.7, "map context matches native place-name green")
equal(select(3, Addon.mapContextLabel.Text:GetTextColor()), 0.3, "map context matches native place-name blue")
equal(Addon.mapContextLabel.template, nil, "map context has no tooltip template or border")
style = "0"
WorldMapFrame.SidePanelToggle = CreateFrame("Button", nil, mapCanvas)
WorldMapFrame.SidePanelToggle:SetSize(32, 32)
WorldMapFrame.SidePanelToggle.bottom = 1
Addon:ShowMapContext()
equal(Addon.mapContextLabel.points[1][2], nativeAreaLabel.Name, "mouse mode uses the same top label")
WorldMapFrame.SidePanelToggle:Hide()
style = "1"
Addon:ShowMapContext()
equal(Addon.mapContextLabel.points[1][2], nativeAreaLabel.Name, "gamepad mode keeps the same top label")
equal(Addon.mapContextLabel.points[1][5], 8, "hiding the native toggle leaves the label in place")
equal(Addon.playerLocationLabel:IsVisible(), true, "native character location has its English suffix")
equal(Addon.playerLocationLabel.Text:GetText(), " - Wetlands", "character suffix uses player location rather than viewed map")
equal(Addon.playerLocationLabel.points[1][2], playerCoordsText, "suffix stays attached to native character text")
equal(Addon.playerLocationLabel.points[1][3], "RIGHT", "suffix follows the end of the native character line")
equal(playerCoordsText:GetText(), "Personnage : 10.7, 61.6 (Les Paluns)", "native coordinate text remains intact")
equal(select(1, Addon.playerLocationLabel.Text:GetTextColor()), 1, "character suffix is white")
equal(select(2, Addon.playerLocationLabel.Text:GetTextColor()), 1, "character suffix is white in every channel")
equal(select(3, Addon.playerLocationLabel.Text:GetTextColor()), 1, "character suffix has no yellow tint")
equal(select(2, Addon.playerLocationLabel.Text:GetFont()), 10, "character suffix follows native coordinate typography")
viewedMapID = 1437
playerCoordsText:SetText("Personnage : 10.7, 61.6")
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextLabel.Text:GetText(), "Eastern Kingdoms - Wetlands",
    "changing viewed map refreshes context")
equal(Addon.playerLocationLabel:IsShown(), false, "no suffix is invented when native coordinates omit the place")
playerMapID = 1424
playerCoordsText:SetText("Personnage : 50.1, 32.4 (Contreforts de Hautebrande)")
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.playerLocationLabel.Text:GetText(), " - Hillsbrad Foothills", "player travel refreshes character translation")
coordsPanel.PlayerCoords:Hide()
equal(Addon.playerLocationLabel:IsVisible(), false, "hiding native player coordinates immediately hides suffix")
coordsPanel.PlayerCoords:Show()
playerMapID = 9998
playerCoordsText:SetText("Personnage : 50.1, 32.4 (Unknown place)")
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.playerLocationLabel:IsShown(), false, "unknown player location clears old translation")
viewedMapID = 9998
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextLabel.Text:GetText(), "Eastern Kingdoms - Unknown place",
    "untranslated map names remain identifiable")
viewedMapID = 1415
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextLabel.Text:GetText(), "Eastern Kingdoms", "continent context omits unused ancestors")
viewedMapID = 947
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextLabel.Text:GetText(), "Azeroth", "world context identifies the world itself")
viewedMapID = nil
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextLabel:IsShown(), false, "missing map information clears previous map context")
viewedMapID, playerMapID = 1424, 1437
playerCoordsText:SetText("Personnage : 10.7, 61.6 (Les Paluns)")
Addon.input:Fire("OnUpdate", 0.2)
WorldMapFrame:Hide()
equal(Addon.mapContextLabel:IsShown(), false, "closing map clears persistent context")
equal(Addon.playerLocationLabel:IsVisible(), false, "closing map hides character translation")
WorldMapFrame:Show()
Addon.input:Fire("OnUpdate", 0.2)
equal(Addon.mapContextLabel:IsVisible(), true, "reopening map restores current map context")
equal(Addon.playerLocationLabel:IsVisible(), true, "reopening map restores character translation")

do
    local originalChildren = C_Map.GetMapChildrenInfo
    local children = { mapInfo[1424], mapInfo[1437] }
    C_Map.GetMapChildrenInfo = function(rootID, _, descendants)
        equal(rootID, 947, "menu resolves locations from the live world map root")
        equal(descendants, true, "menu resolves descendant map IDs")
        return children
    end
    equal(Addon:GetClientMapLocationName("Contreforts de Hautebrande"), "Hillsbrad Foothills", "live map resolver returns catalog name")
    local menu = createMapMenu(mapMenuArrow, { "Contreforts de Hautebrande", "Les Paluns", "Unknown place" })
    local row = CreateFrame("Button", nil, UIParent)
    row.left, row.top = 400, 900
    row:SetSize(200, 32)
    row:SetWindow(UIParent)
    local focus = SmartNavigation:GetCurrentButton()
    menu.elements[1]:Enter(row)
    equal(Addon.mapMenuTooltip:IsShown(), true, "live client map identity restores menu translation")
    equal(Addon.mapMenuTooltip:GetLeftLine(2):GetText(), "Hillsbrad Foothills", "menu translates the resolved map ID")
    menu.elements[2]:Enter(row)
    equal(Addon.mapMenuTooltip:GetLeftLine(2):GetText(), "Wetlands", "selection updates the translated location")
    equal(SmartNavigation:GetCurrentButton(), focus, "map translation preserves controller focus")
    Addon:SetFeatureEnabled("mapDropdown", false)
    menu.elements[1]:Enter(row)
    equal(Addon.mapMenuTooltip:IsShown(), false, "map menu honors feature opt-out with resolvable maps")
    Addon:SetFeatureEnabled("mapDropdown", true)
    menu.elements[3]:Enter(row)
    equal(Addon.mapMenuTooltip:IsShown(), false, "unknown map names preserve native text")
    children[3] = { mapID = 9998, name = mapInfo[1424].name }
    menu.elements[1]:Enter(row)
    equal(Addon.mapMenuTooltip:IsShown(), false, "ambiguous live map names preserve native text")
    children[3] = nil
    menu.elements[1]:Enter(row)
    menu:Release()
    equal(Addon.mapMenuTooltip:IsShown(), false, "closing a translated map menu clears its tooltip")
    C_Map.GetMapChildrenInfo = originalChildren
end

local mapMenu = createMapMenu(mapMenuArrow, {"Bois de la Pénombre", "Hurlevent", "Unknown place", "Rives Claires"})
equal(Addon.mapMenuTooltip ~= nil, true, "map navigation has a separate translation tooltip")
equal(mapMenu.tooltip, Addon.mapMenuTooltip, "native menu owns translation tooltip cleanup")
local menuWindow = CreateFrame("Frame", nil, UIParent)
local menuRow = CreateFrame("Button", nil, menuWindow)
menuRow.left, menuRow.top = 400, 900
menuRow:SetSize(200, 32)
menuRow:SetScale(0.7)
menuRow:SetWindow(menuWindow)
local focusedBeforeMenu = SmartNavigation:GetCurrentButton()
mapMenu.elements[1]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "A title-only menu row stays native")
equal(mapMenu.elements[1].nativeEnters, 1, "Native menu highlight handler is preserved")
mapMenu.elements[1]:Leave(menuRow)
mapMenu.elements[2]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "Another title-only menu row stays native")
mapMenu:Release()
equal(Addon.mapMenuTooltip:IsShown(), false, "Closing the dropdown clears its tooltip")
equal(SmartNavigation:GetCurrentButton(), focusedBeforeMenu, "Translation callbacks never move controller focus")
equal(mapMenu.elements[1].responder(), "Bois de la Pénombre", "Map selection responder is unchanged")
local unrelatedMenu = createMapMenu(UIParent, {"Hurlevent"})
equal(unrelatedMenu.elements[1].onEnter, nil, "shared menu tag cannot affect unrelated dropdowns")
local forbiddenMenuOwner = setmetatable({ IsForbidden = function() return true end }, {
    __index = function(_, key) error("forbidden menu field accessed: " .. key) end,
})
local forbiddenMenuChild = CreateFrame("Button", nil, forbiddenMenuOwner)
local forbiddenMenu = createMapMenu(forbiddenMenuChild, {"Hurlevent"})
equal(forbiddenMenu.elements[1].onEnter, nil, "map menus ignore forbidden owner ancestors")
mapMenu.elements[1]:Enter(forbiddenMenuOwner)
equal(Addon.mapMenuTooltip:IsShown(), false, "forbidden menu rows never reveal a companion")
equal(Addon.lifecycle, "ready", "forbidden menus cannot suspend the addon")
local trackingNames = { "Tout décocher", "Commissaire-priseur", "Banquier", "Maître de guerre",
    "Aubergiste", "Boîte aux lettres", "Maître de classe", "Maîtres de métier", "Réparations",
    "Maître des écuries", "Maître de vol", "Quêtes de bas niveau", "Découverte de trésors" }
local trackingKeys = { "Auctioneer", "Banker", "Battlemaster", "Innkeeper", "Mailbox",
    "TrainerClass", "TrainerProfession", "Repair", "Stablemaster", "TaxiNode", "TrivialQuests" }
local trackingExpected = { "Auctioneer", "Banker", "Battlemaster", "Innkeeper", "Mailbox",
    "Class Trainer", "Profession Trainers", "Repair", "Stable Master", "Flight Master", "Low Level Quests" }
local trackingData = {}
Enum.MinimapTrackingFilter = {}
for index, key in ipairs(trackingKeys) do
    Enum.MinimapTrackingFilter[key] = index
    trackingData[index + 1] = { index = index }
end
C_Minimap = { GetTrackingFilter = function(index) return { filterID = index } end }
trackingData[13] = { index = 12, spellID = 2481 }
local trackingMenu = createMapMenu(UIParent, trackingNames, "MENU_MINIMAP_TRACKING", trackingData)
for index, expected in ipairs(trackingExpected) do
    trackingMenu.elements[index + 1]:Enter(menuRow)
    equal(Addon.mapMenuTooltip:GetLeftLine(2):GetText(), expected, "tracking option translates " .. expected)
    equal(trackingMenu.elements[index + 1].responder(), trackingNames[index + 1], "tracking action is preserved")
end
trackingMenu.elements[13]:Enter(menuRow)
equal(Addon.mapMenuTooltip:GetLeftLine(2):GetText(), "Find Treasure", "tracking spell uses catalog translation")
trackingMenu.elements[1]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "uncheck all clears the preceding translation without translating")
Addon.preferences.features.trackingMenu = false
trackingMenu.elements[2]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "tracking translations can be disabled independently")
Addon.preferences.features.trackingMenu = true
local trackingLocale = Addon.preferences.locale
Addon.preferences.locale = "frFR"
trackingMenu.elements[2]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "English service labels do not leak into another target language")
Addon.preferences.locale = trackingLocale
trackingMenu.elements[2]:Enter(menuRow)
trackingMenu:Release()
equal(Addon.mapMenuTooltip:IsShown(), false, "closing tracking menu clears translation")
equal(Addon.mapMenuTooltip:GetWindow(), nil, "tracking menu releases native window")
equal(SmartNavigation:GetCurrentButton(), focusedBeforeMenu, "tracking translations preserve controller focus")

local savedGeneration = Addon.generation
Addon.generation = savedGeneration + 1
mapMenu.elements[1]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "callbacks from a previous addon generation cannot reveal old tooltips")
Addon.generation = savedGeneration
local savedLifecycle = Addon.lifecycle
Addon.lifecycle = "suspended"
mapMenu.elements[1]:Enter(menuRow)
equal(Addon.mapMenuTooltip:IsShown(), false, "a paused addon cannot reveal menu tooltips")
Addon.lifecycle = savedLifecycle
mapMenu.elements[1]:Enter(menuRow)
WorldMapFrame:Hide()
equal(Addon.mapMenuTooltip:IsShown(), false, "closing map also clears an open dropdown translation")
WorldMapFrame:Show()

SpokenPlacesPanel = CreateFrame("Frame", "SpokenPlacesPanel", UIParent)
SpokenPlacesPanel.top = 850
SpokenPlacesPanel.left, SpokenPlacesPanel.right = 820, 1120
SpokenPlacesPanel.NineSlice = CreateFrame("Frame", nil, SpokenPlacesPanel)
SpokenPlacesPanel.NineSlice.TopLeftCorner = CreateFrame("Texture", nil, SpokenPlacesPanel.NineSlice)
SpokenPlacesPanel.NineSlice.TopLeftCorner.left = 812
SpokenPlacesPanel.NineSlice.TopLeftCorner.top = 866
SpokenPlacesPanel.NineSlice.BottomRightCorner = CreateFrame("Texture", nil, SpokenPlacesPanel.NineSlice)
SpokenPlacesPanel.NineSlice.BottomRightCorner.right = 1124
SpokenPlacesPanel.NineSlice.BottomRightCorner.bottom = 347
SpokenPlacesPanel:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 10)
Addon:Layout()
equal(Addon.panel.points[1][2], SpokenPlacesPanel, "coexists with lore panel")
SpokenPlacesPanel.NineSlice:SetFrameLevel(4000)
Addon:Layout()
equal(Addon.panel.PortraitContainer:GetFrameLevel() > SpokenPlacesPanel.NineSlice:GetFrameLevel(), true,
    "native portrait stays above a raised left pane")
equal(Addon.panel.NineSlice:GetFrameLevel() > SpokenPlacesPanel.NineSlice:GetFrameLevel(), true,
    "native border stays above a raised left pane")
SpokenPlacesPanel.NineSlice:SetFrameStrata("DIALOG")
Addon:Layout()
equal(Addon.panel:GetFrameStrata(), "DIALOG", "panel clears a neighbor border with its own higher strata")
SpokenPlacesPanel.NineSlice:SetFrameStrata("MEDIUM")
SpokenPlacesPanel.NineSlice:SetFrameLevel(1)
Addon:Layout()
equal(Addon.panel:GetFrameStrata(), "MEDIUM", "panel lowers after the neighbor border returns to normal")
near(Addon.panel.points[1][4], 36, "translation repeats visible quest-to-Spoken gap across different scales")
SpokenPlacesPanel.NineSlice.TopLeftCorner.left = 795.2
Addon:Layout()
near(Addon.panel.points[1][4], 15, "small reference gap is preserved without forcing a larger minimum")
SpokenPlacesPanel.NineSlice.TopLeftCorner.left = 812
Addon:Layout()
equal(Addon.toggle:GetFrameLevel() < SpokenPlacesPanel:GetFrameLevel(), true,
    "collapsed bookmark cannot cover Spoken panel")
near(Addon.panel.points[1][5] + Addon.panel.Content.points[1][5], -302.5,
    "vertical alignment accounts for different lore scale")
SpokenPlacesPanel:Hide()
Addon:Layout()
equal(Addon.panel.points[1][2], WorldMapFrame.MiniBorderFrame, "uses map edge without lore")

QuestMapFrame.DetailsFrame.questID = 999999999
hooks.QuestMapFrame_ShowQuestDetails()
equal(Addon.current.mode, "open", "missing quest opens the report page")
equal(press("PADRSTICK"), true)
QuestMapFrame.DetailsFrame.questID = 399
hooks.QuestMapFrame_ShowQuestDetails()
WorldMapFrame.maximized = true
Addon:RefreshSelection()
equal(Addon.panel:IsShown(), false, "full screen map hides side panel")
WorldMapFrame.maximized = false
Addon:RefreshSelection()
equal(press("PADRTRIGGER"), false)
WorldMapFrame:Hide()
equal(Addon.current.mode, "unavailable", "map close releases controller")
equal(Addon.registeredPanel, nil, "map close removes native English registration")
equal(#manager.shownFrames, 1, "map close leaves other registered windows intact")
equal(Addon.toggle:IsShown(), false)
equal(Addon.tooltip:IsShown(), false)
equal(press("PADRSTICK"), true, "hidden map input passes through")
WorldMapFrame:Show()
equal(Addon.current.mode, "open", "map reopen shows selected quest")
QuestMapFrame.DetailsFrame:Hide()
equal(Addon.current.mode, "unavailable", "quest list clears panel")

-- Faults are contained at native callback boundaries and stop repeated work.
QuestMapFrame.DetailsFrame:Show()
SlashCmdList.FOREVERROSETTASTONE("error")
equal(Addon.errorDialog, nil, "dialog waits for native chat handler to finish")
flushTimers()
local dialog = Addon.errorDialog
equal(dialog.frame:IsShown(), true, "copy dialog opens with no errors")
equal(dialog.frame:GetParent(), UIParent, "diagnostics outside native quest navigation")
equal(dialog.editBox:GetText():find("Error log", 1, true) ~= nil, true, "error dialog shows the error log")
equal(dialog.editBox.autoFocus, false, "no forced focus")
equal(dialog.editBox.focused, false, "error dialog does not request keyboard focus")
equal(dialog.editBox.highlighted, false, "report opens readable without a selection overlay")
equal(CloseSpecialWindows(), true, "native Escape dismisses diagnostics without edit-box focus")
equal(dialog.frame:IsShown(), false, "Escape closes the unfocused diagnostic overlay")
Addon:ShowErrorDialog()
Addon:RefreshSelection()
equal(Addon.registeredPanel, nil, "copy dialog releases English focus registration")
dialog.close:Fire("OnClick")
equal(dialog.frame:IsShown(), false, "copy dialog closes")
Addon:RefreshSelection()
local refreshSelection = Addon.RefreshSelection
local attempts = 0
Addon.RefreshSelection = function()
    attempts = attempts + 1
    error("injected quest API failure")
end
local ok = pcall(Addon.input:GetScript("OnUpdate"), Addon.input, 0.2)
equal(ok, true, "update callback does not throw")
equal(Addon.lifecycle, "suspended", "failure suspends addon")
equal(select(2, Addon.minimapButton.icon:GetVertexColor()), 0.2, "paused minimap icon stays red")
local widgetAccurateLines = Addon:GetWidgetTooltip().accurateLines
Addon:GetWidgetTooltip().accurateLines = true
Addon.minimapButton:Fire("OnEnter")
equal(Addon:GetWidgetTooltip().lines[2], Addon:GetPauseMessage(), "minimap hover explains the paused state")
Addon.minimapButton:Fire("OnLeave")
Addon:GetWidgetTooltip().accurateLines = widgetAccurateLines
equal(Addon.registeredPanel, nil, "failure releases English focus registration")
equal(Addon:MoveLifecycle("initialize.ready"), false, "late initialization cannot revive suspended addon")
equal(Addon.panel:IsShown(), false, "failure hides panel")
equal(Addon.toggle:IsShown(), false)
equal(Addon.tooltip:IsShown(), false)
local failures = #Addon.errors
Addon.input:Fire("OnUpdate", 0.2)
equal(attempts, 1, "suspended callback does not retry")
equal(#Addon.errors, failures, "no error flood")
equal(press("PADRSTICK"), true, "failed controller callback releases input")
SlashCmdList.FOREVERROSETTASTONE("status")
Addon.minimapButton:Fire("OnClick", "LeftButton")
equal(dialog.frame:IsShown(), true, "paused minimap launcher opens the failure report")
dialog.close:Fire("OnClick")
equal(pcall(SlashCmdList.FOREVERROSETTASTONE, "error"), true, "diagnostics open while suspended")
flushTimers()
equal(dialog.frame:IsShown(), true)
equal(dialog.editBox:GetText():find(Addon.errors[#Addon.errors], 1, true) ~= nil, true,
    "full original error included")
equal(dialog.editBox:GetText():find("stack line 1\nstack line 2", 1, true) ~= nil, true,
    "multiline stack trace included")
dialog.editBox:SetText("accidental edit")
equal(dialog.editBox:GetText(), dialog.report, "editing cannot corrupt the captured report")
equal(Addon.lifecycle, "suspended", "copying does not restart failed addon")
equal(#Addon.errors, failures, "copying preserves error history")
equal(CloseSpecialWindows(), true, "Escape still dismisses diagnostics while the addon is paused")
equal(dialog.frame:IsShown(), false, "paused diagnostic overlay closes without text focus")
Addon:ShowErrorDialog()
dialog.editBox:Fire("OnEscapePressed")
equal(dialog.frame:IsShown(), false, "Escape closes copy dialog")
SlashCmdList.FOREVERROSETTASTONE("error")
flushTimers()
equal(dialog.frame:IsShown(), true, "copy dialog reopens without rebuilding")
local getHeight = dialog.measure.GetStringHeight
dialog.measure.GetStringHeight = function() error("injected diagnostic display failure") end
equal(pcall(Addon.ShowErrorDialog, Addon), true, "diagnostic failure does not throw")
equal(Addon.errors[#Addon.errors]:find("injected quest API failure", 1, true) ~= nil, true,
    "diagnostic failure does not replace original error")
equal(#Addon.errors, failures)
dialog.measure.GetStringHeight = getHeight
SlashCmdList.FOREVERROSETTASTONE("error")
flushTimers()
combat = true
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "suspended", "reset refused during combat")
combat = false
Addon.RefreshSelection = refreshSelection
local oldInput = Addon.input
local oldHook = hooks.QuestMapFrame_ShowQuestDetails
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready", "reset recovers without reloading")
equal(select(2, Addon.minimapButton.icon:GetVertexColor()), 1, "successful reset restores the minimap icon")
equal(dialog.frame:IsShown(), false, "reset dismisses old error report")
equal(Addon.panel:IsShown(), true)
equal(oldInput:IsShown(), false, "old frames remain inactive")
equal(oldInput.scripts.OnGamePadButtonDown, nil, "old update frame has no controller handler")
oldHook()
equal(Addon.current.mode, "open", "old hook does not change new state")

local createQuestPage = Addon.CreateQuestPage
Addon.CreateQuestPage = function() error("injected construction failure") end
equal(pcall(SlashCmdList.FOREVERROSETTASTONE, "reset"), true, "partial initialization contained")
equal(Addon.lifecycle, "suspended")
for _, frame in ipairs(Addon.frames) do equal(frame:IsShown(), false, "partial UI hidden") end
Addon.CreateQuestPage = createQuestPage
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready", "partial initialization can be retried")
equal(Addon.panel:IsShown(), true)

Addon.page.body.frame.ScrollBar.ScrollStepInDirection = function() error("injected scroll failure") end
equal(pcall(Addon.page.body.frame.Fire, Addon.page.body.frame, "OnMouseWheel", -1), true,
    "native scrollbar callback contained")
equal(Addon.lifecycle, "suspended")
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready")
local setScrollFrame = SmartNavigation.SetScrollFrameForFrame
SmartNavigation.SetScrollFrameForFrame = function(self, panel, scroll)
    if panel == Addon.panel then error("injected controller failure") end

    return setScrollFrame(self, panel, scroll)
end
equal(pcall(press, "PADRTRIGGER"), true, "failing native focus callback does not throw")
equal(Addon.lifecycle, "suspended")
equal(Addon.registeredPanel, nil, "failed focus callback releases native registration")
equal(SmartNavigation.panels[Addon.panel], nil, "failed native focus removes stale scroll routing")
SmartNavigation.SetScrollFrameForFrame = setScrollFrame
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready")

-- Native registration cleanup must outlive a failure during combat.
combat = true
Addon:Run("combat failure", function() error("injected combat failure") end)
equal(Addon.lifecycle, "suspended")
equal(Addon.registeredPanel, Addon.panel, "focus removal waits for the native combat restriction")
combat = false

for _, frame in ipairs(frames) do
    if frame.events.PLAYER_REGEN_ENABLED then frame:Fire("OnEvent", "PLAYER_REGEN_ENABLED") end
end

equal(Addon.registeredPanel, nil, "combat end releases focus even while suspended")
equal(SmartNavigation.panels[Addon.panel], nil, "combat cleanup removes stale scroll routing")
equal(Addon.lifecycle, "suspended", "cleanup does not restart paused addon")
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready")

Addon:Run("outer", function()
    Addon:Run("inner", function() error("nested UI failure") end)
    Addon.panel:Show()
end)
equal(Addon.lifecycle, "suspended", "nested failure stays suspended")
equal(Addon.panel:IsShown(), false, "outer callback cannot reveal failed UI")
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready")
equal(#Addon.errors <= 5, true, "bounded error history")
equal(SpokenPlaces, nil, "no Spoken dependency")
equal(SpokenTextView, nil, "renderer does not create Spoken globals")
equal(Addon.TextView, nil, "vendored text renderer is not loaded")
equal(Addon.Art, nil, "vendored texture helpers are not loaded")
equal(ForeverRosettaStone, Addon, "public binding namespace")

-- The first caught fault emits one notice even if more frames arrive.
local notices = 0
local originalPrint = print
print = function() notices = notices + 1 end
Addon.page.body.frame.ScrollBar.ScrollStepInDirection = function() error("injected repeated fault") end
Addon.page.body.frame:Fire("OnMouseWheel", -1)
Addon.page.body.frame:Fire("OnMouseWheel", -1)
Addon.input:Fire("OnUpdate", 0.2)
print = originalPrint
equal(notices, 1, "one chat notice per failure")
SlashCmdList.FOREVERROSETTASTONE("reset")
equal(Addon.lifecycle, "ready")

checks = checks + assert(loadfile("tests/lua/test-database-integration.lua"))(Addon)
checks = checks + assert(loadfile("tests/lua/test-protected-actions.lua"))(Addon)
checks = checks + assert(loadfile("tests/lua/test-settings.lua"))(Addon, {
    press = press,
    flushTimers = flushTimers,
    setCombat = function(value) combat = value end,
    setMouseFoci = function(value) mouseFoci = value end,
    locationHeader = locationHeader,
    questPin = questPin,
    nativeAreaLabel = nativeAreaLabel,
    nativeChoices = nativeChoices,
    createMapMenu = createMapMenu,
    mapMenuArrow = mapMenuArrow,
    menuRow = menuRow,
})

checks = checks + assert(loadfile("tests/lua/test-settings-controller.lua"))(Addon, press, flushTimers)

checks = checks + assert(loadfile("tests/lua/test-quest-report.lua"))(Addon, {
    press = press,
    setCombat = function(value) combat = value end,
    setGamepad = function(value) style = value and "1" or "0" end,
    manager = manager,
})

local function tooltipData(source, kind, id, color, body)
    source:ClearLines()
    source.lastTooltipRequest = { kind, id, color, body }
    local line = { type = kind == Enum.TooltipDataType.Item and Enum.TooltipDataLineType.ItemName
        or Enum.TooltipDataLineType.SpellName, leftColor = color, leftText = "Native title", lineIndex = 1 }
    local data = { type = kind, id = id, lines = { line } }
    for _, row in ipairs(body or { { type = 0, leftText = "Native details" } }) do
        data.lines[#data.lines + 1] = row
    end
    source.processingInfo = { tooltipData = data,
        append = source == ShoppingTooltip1 or source == ShoppingTooltip2
            or source == ItemRefShoppingTooltip1 or source == ItemRefShoppingTooltip2 }
    for _, row in ipairs(data.lines) do
        if row.rightText then source:AddDoubleLine(row.leftText, row.rightText)
        else source:AddLine(row.leftText or "") end
        row.lineIndex = source:NumLines()
        for _, callback in ipairs(tooltipLineCallbacks[TooltipDataProcessor.AllTypes] or {}) do callback(source, row) end
        for _, callback in ipairs(tooltipLineCallbacks[row.type] or {}) do callback(source, row) end
    end
    for _, callback in ipairs(tooltipCallbacks) do
        callback(source, data)
    end
end

function Frame:RebuildFromTooltipInfo()
    if self.lastTooltipRequest then tooltipData(self, unpack(self.lastTooltipRequest)) end
end

do
    local previousLocale, previousLabels = GetLocale, Addon.GetClientLabel
    GetLocale = function() return "frFR" end
    Addon.GetClientLabel = function(_, key, locale)
        return ForeverRosettaStoneDB:GetGlobalStringByKey(key, locale)
    end
    local previousNone = Enum.TooltipDataLineType.None
    Enum.TooltipDataLineType.None = 0
    local function itemRow(text, lineType, enchantID)
        return { type = lineType, leftText = text, enchantID = enchantID }
    end
    local function english(line)
        return Addon:GetEnglishTooltipLine({}, line, "item", 5315)
    end
    local spirit = itemRow("Enchanté : Esprit +3", 15, 243)
    local oil = itemRow("Huile de sorcier mineure (30 min)", 0)
    equal(english(spirit), "Enchanted: Spirit +3", "captured permanent enchantment")
    equal(english(oil), "Minor Wizard Oil (30 min)", "captured untyped temporary enchantment")
    equal(english(itemRow("Huile de sorcier mineure (29 min)", 0)),
        "Minor Wizard Oil (29 min)", "keep the remaining duration instead of the catalog duration")
    equal(english(itemRow("Huile de sorcier mineure (1 heure)", 0)),
        "Minor Wizard Oil (1 hour)", "localize the time unit and its plural")
    equal(english(itemRow("Enchanté : Endurance +1 et armure +8", 15, 15)),
        "Enchanted: Stamina +1 and Armor +8", "keep both rendered modifier amounts")
    equal(english(itemRow("Enchanté : Esprit +4", 15, 243)), nil,
        "preserve a permanent effect whose source wording does not match the ID")
    equal(english(itemRow("Huile de sorcier mineure", 0)), nil, "require the native duration on untyped rows")
    equal(english(itemRow("Huile inconnue (30 min)", 0)), nil, "preserve unknown temporary effects")
    local previousSpellTranslation = Addon.TranslateLiveSpellDescription
    Addon.TranslateLiveSpellDescription = function(_, spellID, locale, body)
        if spellID == 1225951 and locale == "enUS" and body == "Effet du sort" then return "Spell effect" end
    end
    equal(english(itemRow("Enchanté : Effet du sort", 15, 7919)), "Enchanted: Spell effect",
        "resolve the owned spell reference through the existing tooltip translator")
    Addon.TranslateLiveSpellDescription = previousSpellTranslation
    local german = Addon:GetLocalizedTooltipLine(spirit, "item", 5315, "deDE", {})
    local germanFormat = ForeverRosettaStoneDB:GetGlobalStringByKey("ENCHANTED_TOOLTIP_LINE", "deDE")
    equal(german, germanFormat:gsub("%%s", "Willenskraft +3"), "render a non-English target")
    equal(english(itemRow("Enchanté : +24 Armure", 15, 122)), "Enchanted: +24 Armor",
        "resolve the armor kit through the permanent enchantment table")
    equal(Addon:GetLocalizedTooltipLine(spirit, "item", 5315, "itIT", {}), "Incantato: Spirito +3",
        "load the localized prefix and value from the additional locale pack")
    Enum.TooltipDataLineType.None = previousNone
    GetLocale, Addon.GetClientLabel = previousLocale, previousLabels
end

do
    local previousInspect, previousUnitIsUnit = InspectFrame, UnitIsUnit
    local previousInventoryID, previousCollection = GetInventoryItemID, C_TransmogCollection
    local previousLocale, previousTarget, previousLabels = GetLocale, Addon.GetTargetLocale, Addon.GetClientLabel
    local previousNone = Enum.TooltipDataLineType.None
    Enum.TooltipDataLineType.None = 0
    InspectFrame = { unit = "target", IsShown = function() return true end }
    UnitIsUnit = function(left, right) return left == right end
    GetLocale = function() return "frFR" end
    Addon.GetTargetLocale = function() return "enUS" end
    Addon.GetClientLabel = function(_, key, locale) return ForeverRosettaStoneDB:GetGlobalStringByKey(key, locale) end
    C_TransmogCollection = {
        GetInspectItemTransmogInfoList = function()
            return { [1] = { appearanceID = 77344 }, [16] = { appearanceID = 309588 } }
        end,
        GetSourceItemID = function(id) return ({ [77344] = 134110, [309588] = 276102 })[id] end,
    }
    local function render(id, slot, unit, text, liveID)
        GetInventoryItemID = function() return liveID or id end
        local source, tip = CreateFrame("GameTooltip", nil, UIParent), CreateFrame("GameTooltip", nil, UIParent)
        local lines = {
            { type = Enum.TooltipDataLineType.ItemName, leftText = "Native title", lineIndex = 1 },
            { type = 0, leftText = "Transmogrifié en :", lineIndex = 2 },
            { type = 0, leftText = text, lineIndex = 3 },
        }
        for _, line in ipairs(lines) do source:AddLine(line.leftText) end
        source.processingInfo = { getterName = "GetInventoryItem", getterArgs = { unit, slot } }
        Addon:FillEnglishTooltip({ kind = "item", id = id, name = ForeverRosettaStoneDB:GetItemName(id, "enUS"),
            source = source, tip = tip, data = { lines = lines } })
        return tip:GetLeftLine(3):GetText()
    end
    equal(render(276102, 16, "target", "Lame-vent"), "Bladewind", "inspected weapon appearance translates by source ID")
    equal(render(9969, 1, "target", "Heaume caché"), "Hidden Helm", "hidden helm uses its own source ID")
    equal(render(9969, 1, "player", "Heaume caché"), "Heaume caché", "another unit cannot use the inspect cache")
    local priorLocation, priorApplied = ItemLocation, C_Item.GetAppliedItemTransmogInfo
    local priorSourceLookup = C_TransmogCollection.GetSourceItemID
    ItemLocation = { CreateFromEquipmentSlot = function(_, slot) return { slot = slot } end }
    C_Item.GetAppliedItemTransmogInfo = function(location)
        equal(location.slot, 16, "own transmog uses the equipped item location")
        return { appearanceID = 156293, secondaryAppearanceID = 0 }
    end
    C_TransmogCollection.GetSourceItemID = function(sourceID)
        if sourceID == 156293 then return 1411 end
        return priorSourceLookup(sourceID)
    end
    equal(render(15397, 16, "player", "Vieux bâton usé"), "Withered Staff", "use the equipped item's applied appearance")
    equal(render(15397, 16, "player", "Lame-vent"), "Lame-vent", "reject a name that differs from the applied appearance")
    local priorModel = CharacterModelScene
    local modelVisible, modelReads = true, 0
    CharacterModelScene = {
        IsVisible = function() return modelVisible end,
        GetPlayerActor = function()
            return { GetItemTransmogInfo = function(_, slot)
                equal(slot, 16, "read the rendered appearance of the hovered slot")
                modelReads = modelReads + 1
                return { appearanceID = 156293, secondaryAppearanceID = 0 }
            end }
        end,
    }
    equal(render(15397, 16, "player", "Vieux bâton usé"), "Withered Staff", "prefer an applied item appearance")
    equal(modelReads, 0, "no model lookup when the item reports an applied appearance")
    C_Item.GetAppliedItemTransmogInfo = function() return { appearanceID = 0, secondaryAppearanceID = 0 } end
    equal(render(15397, 16, "player", "Vieux bâton usé"), "Withered Staff",
        "use the character sheet when the captured equipped item returns zero appearances")
    equal(render(15397, 16, "player", "Autre apparence"), "Autre apparence", "verify the name from the scene")
    modelVisible = false
    equal(render(15397, 16, "player", "Vieux bâton usé"), "Vieux bâton usé", "ignore hidden character scenes")
    equal(modelReads, 2, "the hidden scene is never read")
    local priorCurrent = C_Item.GetCurrentItemTransmogInfo
    C_Item.GetCurrentItemTransmogInfo = function(location)
        equal(location.slot, 18, "read the current appearance of the ranged weapon slot")
        return { appearanceID = 158636, secondaryAppearanceID = 0 }
    end
    C_TransmogCollection.GetSourceItemID = function(sourceID)
        if sourceID == 158636 then return 6677 end
        return priorSourceLookup(sourceID)
    end
    equal(render(6677, 18, "player", "Baguette de sortilèges"), "Spellcrafter Wand",
        "resolve the wand with zero applied appearances and no readable character model")
    equal(render(6677, 18, "player", "Autre apparence"), "Autre apparence",
        "the current appearance must match the row")
    C_Item.GetCurrentItemTransmogInfo = priorCurrent
    CharacterModelScene = priorModel
    ItemLocation, C_Item.GetAppliedItemTransmogInfo = priorLocation, priorApplied
    C_TransmogCollection.GetSourceItemID = priorSourceLookup
    equal(render(9969, 1, "target", "Ancienne apparence"), "Ancienne apparence", "reject stale appearance wording")
    equal(render(9969, 1, "target", "Heaume caché", 25), "Heaume caché", "reject stale equipment data")
    InspectFrame, UnitIsUnit = previousInspect, previousUnitIsUnit
    GetInventoryItemID, C_TransmogCollection = previousInventoryID, previousCollection
    GetLocale, Addon.GetTargetLocale, Addon.GetClientLabel = previousLocale, previousTarget, previousLabels
    Enum.TooltipDataLineType.None = previousNone
end

checks = checks + assert(loadfile("tests/lua/test-tooltip-component-contract.lua"))(Addon)
checks = checks + assert(loadfile("tests/lua/test-name-tooltips.lua"))(Addon, tooltipData, tooltipCallbacks, flushTimers)
checks = checks + assert(loadfile("tests/lua/test-tooltip-header.lua"))(Addon)
checks = checks + assert(loadfile("tests/lua/test-player-tooltips.lua"))(Addon, tooltipCallbacks, flushTimers)
checks = checks + assert(loadfile("tests/lua/test-aura-recovery.lua"))(Addon, tooltipCallbacks, flushTimers)
checks = checks + assert(loadfile("tests/lua/test-tooltip-components.lua"))(Addon, {
    callbacks = tooltipCallbacks,
    lineCallbacks = tooltipLineCallbacks,
    hooks = hooks,
    eventCallbacks = eventCallbacks,
    flushTimers = flushTimers,
    setMouseFoci = function(value) mouseFoci = value end,
})
checks = checks + assert(loadfile("tests/lua/test-taxi-tooltips.lua"))(Addon, flushTimers)
checks = checks + assert(loadfile("tests/lua/test-profession-tooltips.lua"))(Addon, function(value) mouseFoci = value end)
checks = checks + assert(loadfile("tests/lua/test-collection-tooltips.lua"))(Addon, {
    callbacks = tooltipCallbacks,
    flushTimers = flushTimers,
    setMouseFoci = function(value) mouseFoci = value end,
})
checks = checks + assert(loadfile("tests/lua/test-character-stat-tooltip.lua"))(Addon, flushTimers, hooks)
checks = checks + assert(loadfile("tests/lua/test-tooltip-missing-lines.lua"))(Addon)
checks = checks + assert(loadfile("tests/lua/test-benchmark.lua"))(Addon, {
    tooltipData = tooltipData,
    flushTimers = flushTimers,
    frames = frames,
    setSelected = function(id) selected = id; QuestMapFrame.DetailsFrame.questID = id end,
})
checks = checks + assert(loadfile("tests/lua/test-diagnostics.lua"))(Addon, tooltipData, flushTimers)
checks = checks + assert(loadfile("tests/lua/test-debug-display.lua"))(Addon)
checks = checks + assert(loadfile("tests/lua/test-quest-interaction.lua"))(Addon, {
    setMouseFoci = function(value) mouseFoci = value end,
    setGamepad = function(value) style = value and "1" or "0" end,
})
checks = checks + assert(loadfile("tests/lua/test-book-reader.lua"))(Addon, {
    setMouseFoci = function(value) mouseFoci = value end,
    setGamepad = function(value) style = value and "1" or "0" end,
})
checks = checks + assert(loadfile("tests/lua/test-debug-surfaces.lua"))(Addon, {
    hooks = hooks, flushTimers = flushTimers, nativeAreaLabel = nativeAreaLabel,
    createMapMenu = createMapMenu, mapMenuArrow = mapMenuArrow, menuRow = menuRow, locationHeader = locationHeader,
})

do
    local onUpdate = Addon.input:GetScript("OnUpdate")
    local run, calls = Addon.Run, 0
    Addon.Run = function() calls = calls + 1; return true end
    onUpdate(Addon.input, 0.2)
    calls = 0

    collectgarbage("collect")
    collectgarbage("stop")
    local beforeKiB = collectgarbage("count")
    for _ = 1, 10000 do onUpdate(Addon.input, 0) end
    local allocatedKiB = collectgarbage("count") - beforeKiB
    collectgarbage("restart")
    equal(calls, 0, "throttled frames do not enter the allocating safety wrapper")
    equal(allocatedKiB < 1, true, "throttled frames allocate less than 1 KiB over 10000 calls")

    onUpdate(Addon.input, 0.04)
    onUpdate(Addon.input, 0.04)
    equal(calls, 0, "updates wait for the full interval")
    onUpdate(Addon.input, 0.03)
    equal(calls, 1, "elapsed frames trigger one protected update")
    onUpdate(Addon.input, 1)
    equal(calls, 2, "slow frames trigger one update without catch-up work")

    local lifecycle = Addon.lifecycle
    Addon.lifecycle = "suspended"
    onUpdate(Addon.input, 0.2)
    equal(calls, 2, "suspended updates skip the safety wrapper")
    Addon.lifecycle = lifecycle
    Addon.generation = Addon.generation + 1
    onUpdate(Addon.input, 0.2)
    equal(calls, 2, "stale update handlers skip the safety wrapper")
    Addon.generation = Addon.generation - 1
    Addon.Run = run
end

do
    local oldBook = Addon:GetBookBookmark()
    local oldDialogue = Addon:GetQuestInteractionBookmark()
    Addon:Restart()
    equal(Addon.lifecycle, "ready", "reset recreates the reading UI")
    equal(Addon.bookReader, nil, "book reader is recreated on demand after reset")
    equal(Addon:GetBookBookmark() ~= oldBook, true, "book bookmark belongs to the current generation")
    equal(Addon:GetQuestInteractionBookmark() ~= oldDialogue, true, "dialogue bookmark belongs to the current generation")
    local calls = 0
    local update = Addon.UpdateBookReader
    Addon.UpdateBookReader = function() calls = calls + 1 end
    Addon.bookBookmark:Fire("OnClick")
    equal(calls, 1, "clicking the new book bookmark opens the reader after reset")
    Addon.UpdateBookReader = update
end

print("PASS: " .. checks .. " assertions (Lua 5.1; real addon renderer, mocked WoW APIs and templates)")
