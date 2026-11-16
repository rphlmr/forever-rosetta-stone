local _, Addon = ...

Addon.TOOLTIP_GAP = 2

local ICON = [[Interface\AddOns\ForeverRosettaStone\media\icon]]

local translationLabels = {
    enUS = "Translated into",
    frFR = "Traduit en", deDE = "Übersetzt in",
    esES = "Traducido al", esMX = "Traducido al",
    itIT = "Tradotto in", ptBR = "Traduzido para",
    ruRU = "Перевод на", koKR = "번역 언어:",
    zhCN = "译文语言：", zhTW = "譯文語言：",
    csCZ = "Jazyk překladu:", daDK = "Oversat til",
    hrHR = "Jezik prijevoda:", plPL = "Język tłumaczenia:",
    svSE = "Översatt till", trTR = "Çeviri dili:",
    ukUA = "Мова перекладу:",
}

-- Names follow the client language; the selected FRS locale only chooses the target.
local languageOrder = { "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR",
    "zhCN", "zhTW", "csCZ", "daDK", "hrHR", "plPL", "svSE", "trTR", "ukUA" }
local localizedLanguageNames = {
    enUS = { "English", "French", "German", "Spanish", "Spanish (Mexico)", "Italian", "Portuguese", "Russian",
        "Korean", "Chinese (Simplified)", "Chinese (Traditional)", "Czech", "Danish", "Croatian", "Polish", "Swedish", "Turkish", "Ukrainian" },
    frFR = { "anglais", "français", "allemand", "espagnol", "espagnol (Mexique)", "italien", "portugais", "russe",
        "coréen", "chinois simplifié", "chinois traditionnel", "tchèque", "danois", "croate", "polonais", "suédois", "turc", "ukrainien" },
    deDE = { "Englisch", "Französisch", "Deutsch", "Spanisch", "Spanisch (Mexiko)", "Italienisch", "Portugiesisch", "Russisch",
        "Koreanisch", "Chinesisch (vereinfacht)", "Chinesisch (traditionell)", "Tschechisch", "Dänisch", "Kroatisch", "Polnisch", "Schwedisch", "Türkisch", "Ukrainisch" },
    esES = { "inglés", "francés", "alemán", "español", "español (México)", "italiano", "portugués", "ruso",
        "coreano", "chino simplificado", "chino tradicional", "checo", "danés", "croata", "polaco", "sueco", "turco", "ucraniano" },
    itIT = { "inglese", "francese", "tedesco", "spagnolo", "spagnolo (Messico)", "italiano", "portoghese", "russo",
        "coreano", "cinese semplificato", "cinese tradizionale", "ceco", "danese", "croato", "polacco", "svedese", "turco", "ucraino" },
    ptBR = { "inglês", "francês", "alemão", "espanhol", "espanhol (México)", "italiano", "português", "russo",
        "coreano", "chinês simplificado", "chinês tradicional", "tcheco", "dinamarquês", "croata", "polonês", "sueco", "turco", "ucraniano" },
    ruRU = { "английский", "французский", "немецкий", "испанский", "испанский (Мексика)", "итальянский", "португальский", "русский",
        "корейский", "китайский (упрощённый)", "китайский (традиционный)", "чешский", "датский", "хорватский", "польский", "шведский", "турецкий", "украинский" },
    koKR = { "영어", "프랑스어", "독일어", "스페인어", "스페인어 (멕시코)", "이탈리아어", "포르투갈어", "러시아어",
        "한국어", "중국어 간체", "중국어 번체", "체코어", "덴마크어", "크로아티아어", "폴란드어", "스웨덴어", "튀르키예어", "우크라이나어" },
    zhCN = { "英语", "法语", "德语", "西班牙语", "西班牙语（墨西哥）", "意大利语", "葡萄牙语", "俄语",
        "韩语", "简体中文", "繁体中文", "捷克语", "丹麦语", "克罗地亚语", "波兰语", "瑞典语", "土耳其语", "乌克兰语" },
    zhTW = { "英語", "法語", "德語", "西班牙語", "西班牙語（墨西哥）", "義大利語", "葡萄牙語", "俄語",
        "韓語", "簡體中文", "繁體中文", "捷克語", "丹麥語", "克羅埃西亞語", "波蘭語", "瑞典語", "土耳其語", "烏克蘭語" },
}
localizedLanguageNames.esMX = localizedLanguageNames.esES
localizedLanguageNames.enGB = localizedLanguageNames.enUS

function Addon:GetLocalizedLanguageName()
    local locale = GetLocale()
    local names = localizedLanguageNames[locale] or localizedLanguageNames.enUS
    local target = self:GetTargetLocale()
    for index, language in ipairs(languageOrder) do
        if language == target then
            return names[index]
        end
    end
    return self:GetLanguageName()
end

function Addon:GetTranslationLanguageLabel()
    return (translationLabels[GetLocale()] or translationLabels.enUS) .. " " .. self:GetLocalizedLanguageName()
end

local openPanelLabels = {
    enUS = "Open Forever Rosetta Stone: %s",
    frFR = "Ouvrir Forever Rosetta Stone : %s",
    deDE = "Forever Rosetta Stone öffnen: %s",
    esES = "Abrir Forever Rosetta Stone: %s",
    esMX = "Abrir Forever Rosetta Stone: %s",
    itIT = "Apri Forever Rosetta Stone: %s",
    ptBR = "Abrir Forever Rosetta Stone: %s",
    ruRU = "Открыть Forever Rosetta Stone: %s",
    koKR = "Forever Rosetta Stone 열기: %s",
    zhCN = "打开 Forever Rosetta Stone：%s",
    zhTW = "開啟 Forever Rosetta Stone：%s",
}

function Addon:GetOpenPanelLabel()
    return string.format(openPanelLabels[GetLocale()] or openPanelLabels.enUS, self:GetLocalizedLanguageName())
end

function Addon:GetTooltipTranslationLabel()
    return "|T" .. ICON .. ":14:14:0:1|t " .. self:GetTranslationLanguageLabel()
end

function Addon:ShouldShowTranslationHeader()
    return not self.preferences or self.preferences.translationHeader ~= false
end

local function StyleTranslationLabel(label, title)
    if not label or not title then return end
    local font, size, flags = title:GetFont()
    if not font or not size then return end
    label:SetFont(font, size * 0.8, flags)
    label:SetTextScale(title:GetTextScale())
    label:SetTextColor(0.65, 0.65, 0.65)
    label:SetJustifyH("LEFT")
end

function Addon:SetStandaloneTooltipTitle(tip, text, ...)
    local showHeader = self:ShouldShowTranslationHeader()
    if showHeader then tip:AddLine(self:GetTooltipTranslationLabel(), 0.65, 0.65, 0.65) end
    tip:AddLine(text, ...)
    local title = tip:GetLeftLine(showHeader and 2 or 1)
    if title then
        title:SetFontObject("GameTooltipHeaderText")
        title:SetTextScale(1)
    end
    if showHeader then StyleTranslationLabel(tip:GetLeftLine(1), title) end
end

local function RefreshTooltipLayout(source)
    local previousRendering = Addon.tooltipRendering
    Addon.tooltipRendering = source
    source:Show()
    Addon.tooltipRendering = previousRendering
end

local function SnapshotLine(line)
    if not line then return end
    return { text = line:GetText(), color = { line:GetTextColor() }, font = { line:GetFont() },
        scale = line:GetTextScale(), justify = line:GetJustifyH(), wrap = line:CanWordWrap(),
        shadowColor = { line:GetShadowColor() }, shadowOffset = { line:GetShadowOffset() }, spacing = line:GetSpacing() }
end

local function RestoreLine(line, saved)
    if not line or not saved then return end
    if saved.font[1] and saved.font[2] then line:SetFont(unpack(saved.font)) end
    line:SetTextScale(saved.scale)
    line:SetTextColor(unpack(saved.color))
    line:SetJustifyH(saved.justify)
    line:SetWordWrap(saved.wrap)
    line:SetShadowColor(unpack(saved.shadowColor))
    line:SetShadowOffset(unpack(saved.shadowOffset))
    line:SetSpacing(saved.spacing)
end

-- Stacked translations are edited in place. ClearLines on a native tooltip would run Blizzard's
-- OnTooltipCleared handler from addon code and leave its shared fields insecure, so the appended
-- lines are blanked and reused instead of rebuilding the native tooltip.
local function IsBlank(line)
    if not line then return true end
    local text = line:GetText()
    return canaccessallvalues(text) and (text == nil or text == "")
end

-- When supplied, owner limits cleanup to the companion that created the snapshot.
function Addon:ClearStackedTooltip(source, nativeCleared, owner)
    if not source then return end
    if nativeCleared and self.blankTooltipLines then self.blankTooltipLines[source] = nil end
    local saved = self.stackedTooltips and self.stackedTooltips[source]
    if not saved or (owner and saved.owner ~= owner) then return end
    self.stackedTooltips[source] = nil
    if source:IsForbidden() then return end
    for line, style in pairs(saved.styles) do RestoreLine(line, style) end
    if nativeCleared then return end
    local last = math.min(saved.last, source:NumLines())
    for index = saved.first, last do
        local left, right = source:GetLeftLine(index), source:GetRightLine(index)
        if left then left:SetText("") end
        if right then right:SetText("") end
    end
    self.blankTooltipLines = self.blankTooltipLines or setmetatable({}, { __mode = "k" })
    self.blankTooltipLines[source] = { first = saved.first, last = last }
    if source:IsShown() then RefreshTooltipLayout(source) end
end

function Addon:FillStackedTooltip(source, tip, key)
    if not source or not tip then return end
    local showHeader = self:ShouldShowTranslationHeader()
    self.stackedTooltips = self.stackedTooltips or {}
    local previous = self.stackedTooltips[source]
    if previous and previous.owner == tip and previous.key == key and previous.showHeader == showHeader
        and previous.numLines == source:NumLines() then
        tip:Hide()
        return
    end
    self:ClearStackedTooltip(source)
    local saved = { key = key, owner = tip, styles = {}, showHeader = showHeader }
    -- Blank lines left by an earlier translation are reused while they still end the tooltip.
    local blank = self.blankTooltipLines and self.blankTooltipLines[source]
    local cursor
    if blank and blank.last == source:NumLines() then
        cursor = blank.first
        for index = blank.first, blank.last do
            if not IsBlank(source:GetLeftLine(index)) or not IsBlank(source:GetRightLine(index)) then cursor = nil; break end
        end
    end
    if self.blankTooltipLines then self.blankTooltipLines[source] = nil end
    saved.first = cursor or source:NumLines() + 1
    -- Native rows are never modified or restored here. Keep their count without reading
    -- potentially restricted text; only appended FRS rows need style snapshots.
    saved.rows = {}
    for index = 1, saved.first - 1 do saved.rows[index] = {} end
    self.stackedTooltips[source] = saved
    self.tooltipRendering = source
    local function Append(left, right, originalLeft, originalRight)
        local hasRight = right and right ~= ""
        local index = source:NumLines() + 1
        if cursor and cursor <= blank.last and not hasRight then
            index, cursor = cursor, cursor + 1
        else
            cursor = nil
        end
        local targetLeft, targetRight = source:GetLeftLine(index), source:GetRightLine(index)
        local leftStyle, rightStyle = SnapshotLine(targetLeft), SnapshotLine(targetRight)
        if index <= source:NumLines() and targetLeft then
            targetLeft:SetText(left or "")
            targetLeft:SetTextColor(1, 1, 1)
            targetLeft:SetWordWrap(true)
        elseif hasRight then
            source:AddDoubleLine(left or "", right)
        else
            source:AddLine(left or "", 1, 1, 1, true)
        end
        -- Native tooltips allocate FontStrings when a row is added, not on lookup.
        targetLeft, targetRight = source:GetLeftLine(index), source:GetRightLine(index)
        if targetLeft then saved.styles[targetLeft] = leftStyle or SnapshotLine(targetLeft) end
        if targetRight then saved.styles[targetRight] = rightStyle or SnapshotLine(targetRight) end
        if targetLeft and originalLeft then
            self:CopyQuestTextStyle(targetLeft, originalLeft)
            targetLeft:SetTextScale(originalLeft:GetTextScale())
        end
        if targetRight and originalRight then
            self:CopyQuestTextStyle(targetRight, originalRight)
            targetRight:SetTextScale(originalRight:GetTextScale())
        end
        return targetLeft
    end
    Append(" ")
    if showHeader then
        local header = Append(self:GetTooltipTranslationLabel())
        StyleTranslationLabel(header, source:GetLeftLine(1))
    end
    for index = 1, tip:NumLines() do
        local left, right = tip:GetLeftLine(index), tip:GetRightLine(index)
        Append(left and left:GetText(), right and right:GetText(), left, right)
    end
    saved.last, saved.numLines = source:NumLines(), source:NumLines()
    self.tooltipRendering = nil
    tip:Hide()
    if source:IsShown() then RefreshTooltipLayout(source) end
end

function Addon:SetCompanionTooltipTitle(tip, text, ...)
    tip:SetText(text, ...)
end

function Addon:CopyCompanionTooltipStyle(tip, source)
    if not tip or not source then return end
    local title = source.TextLeft1 or source.Name

    if title then self:CopyQuestTextStyle(tip.TextLeft1, title) end

    if source.NineSlice and tip.NineSlice then
        tip.NineSlice:SetCenterColor(source.NineSlice:GetCenterColor())
        tip.NineSlice:SetBorderColor(source.NineSlice:GetBorderColor())
    end

    tip:SetAlpha(source:GetAlpha())
end

function Addon:GetTooltipGap(frame)
    return self.TOOLTIP_GAP * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
end

function Addon:IsTooltipBlocked()
    return self.lifecycle ~= "ready"
        or (GameMenuFrame and GameMenuFrame:IsShown())
        or (self.errorDialog and self.errorDialog.frame:IsShown() and not self:IsDebugPicking())
end

function Addon:CreateCompanionTooltip(name, parent, template)
    local tip = self:NewFrame("GameTooltip", name, parent or UIParent, template or "GameTooltipTemplate")
    tip:SetFrameStrata("TOOLTIP")
    tip:EnableMouse(false)
    tip:HookScript("OnHide", function()
        local owner = tip:GetOwner()
        local spec = self.nameTooltips and self.nameTooltips[owner]
        if spec and spec.tip == tip then return end
        self:TransitionTooltipSources(tip, "sources.restore")
    end)
    tip:Hide()
    return tip
end

-- Addon widgets describe themselves in an addon tooltip: hiding or re-owning GameTooltip from
-- addon code would run its native handlers insecurely.
function Addon:GetWidgetTooltip()
    if not self.widgetTooltip or self.widgetTooltipGeneration ~= self.generation then
        self.widgetTooltip = self:CreateCompanionTooltip("ForeverRosettaStoneWidgetTooltip")
        self.widgetTooltipGeneration = self.generation
    end
    return self.widgetTooltip
end

-- Original -> placed captures native settings once; placed updates retain them until cleanup.
function Addon:TransitionTooltipSources(owner, event, positions)
    if not owner then return false end
    if event == "sources.restore" then
        local originals = owner.sourcePlacements
        if not originals then return false end
        if InCombatLockdown() then
            for _, original in ipairs(originals) do
                if not original.source:IsForbidden() and original.source:IsProtected() then return false end
            end
        end
        owner.sourcePlacements = nil
        for _, original in ipairs(originals) do
            if not original.source:IsForbidden() then
                original.source:SetClampRectInsets(unpack(original.insets))
                original.source:SetClampedToScreen(original.clamped)
                if original.source:IsShown() then RefreshTooltipLayout(original.source) end
            end
        end
        return true
    end
    if event ~= "sources.place" or type(positions) ~= "table" then return false end
    for _, position in ipairs(positions) do
        if not position.source or type(position.left) ~= "number" or type(position.top) ~= "number"
            or position.source:IsForbidden() or (InCombatLockdown() and position.source:IsProtected()) then return false end
    end
    local originals = owner.sourcePlacements or {}
    for _, position in ipairs(positions) do
        local source = position.source
        local captured = false
        for _, original in ipairs(originals) do
            if original.source == source then captured = true; break end
        end
        if not captured then
            originals[#originals + 1] = {
                source = source, insets = { source:GetClampRectInsets() }, clamped = source:IsClampedToScreen(),
                rect = self:GetTooltipRect(source), owner = source:GetOwner(),
            }
        end
    end
    owner.sourcePlacements = originals
    local screenScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
    for _, position in ipairs(positions) do
        local source, scale = position.source, position.source:GetEffectiveScale()
        local insets = { -position.left / scale,
            (screenWidth - position.left) / scale - source:GetWidth(),
            (screenHeight - position.top) / scale, source:GetHeight() - position.top / scale }
        local current = { source:GetClampRectInsets() }
        local changed = not source:IsClampedToScreen()
        for index = 1, 4 do changed = changed or math.abs(insets[index] - current[index]) > 0.01 end
        if changed then
            source:SetClampRectInsets(unpack(insets))
            source:SetClampedToScreen(true)
            if source:IsShown() then RefreshTooltipLayout(source) end
        end
    end
    return true
end

function Addon:RestoreTooltipSources()
    for _, frame in ipairs(self.frames) do self:TransitionTooltipSources(frame, "sources.restore") end
    for _, spec in pairs(self.nameTooltips or {}) do
        self:TransitionTooltipSources(spec.group, "sources.restore")
    end
end

function Addon:GetTooltipAnchorContext(source)
    if not source then return { screenSide = "right" } end
    local spec = self.nameTooltips and self.nameTooltips[source]
    local original = self:GetTooltipRect(source)
    local owner = source.GetOwner and source:GetOwner()
    local placements = spec and (spec.group and spec.group.sourcePlacements or spec.tip and spec.tip.sourcePlacements)
    for _, placement in ipairs(placements or {}) do
        if placement.source == source and placement.owner == owner then original = placement.rect; break end
    end
    local fixedSide
    local anchor = source.GetAnchorType and source:GetAnchorType()
    if source.default or (anchor == "ANCHOR_NONE" and (not owner or owner == UIParent)) then
        for index = 1, source:GetNumPoints() do
            local point, relative = source:GetPoint(index)
            if relative == UIParent and point then
                if point:find("RIGHT", 1, true) then fixedSide = "left"
                elseif point:find("LEFT", 1, true) then fixedSide = "right" end
            end
        end
    end
    return { native = original, owner = owner and owner ~= UIParent and self:GetTooltipRect(owner),
        anchor = anchor, fixedSide = fixedSide,
        screenSide = original and original.left + original.right > UIParent:GetWidth() * UIParent:GetEffectiveScale()
            and "left" or "right" }
end

function Addon:GetCompanionTooltipSide(source)
    local policy = self:GetTooltipPlacementPolicy(source)
    return policy and policy.GetSide(source) or "right"
end

function Addon:AnchorCompanionTooltip(tip, source, side)
    if not tip or not source then return end
    tip:SetScale(source:GetEffectiveScale() / UIParent:GetEffectiveScale())
    tip:ClearAllPoints()
    if (side or self:GetCompanionTooltipSide(source)) == "left" then
        tip:SetPoint("TOPRIGHT", source, "TOPLEFT", -self:GetTooltipGap(tip), 0)
    else
        tip:SetPoint("TOPLEFT", source, "TOPRIGHT", self:GetTooltipGap(tip), 0)
    end
end

function Addon:GetTooltipRect(frame)
    if not frame or frame:IsForbidden() then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local scale = frame:GetEffectiveScale()
    return { frame = frame, left = left * scale, right = (left + frame:GetWidth()) * scale,
        top = top * scale, bottom = (top - frame:GetHeight()) * scale }
end

-- At an edge, the translation takes the native position while retaining the chosen pair order.
function Addon:PlaceCompanionTooltip(tip, source, occupied, centerVertically, alignmentFrame, placementPolicy)
    if not tip then return end
    local original = self:GetTooltipRect(source)
    if not original then tip:Hide(); return end
    local screenScale, scale = UIParent:GetEffectiveScale(), tip:GetEffectiveScale()
    local policy = placementPolicy or self:GetTooltipPlacementPolicy(source)
    if policy and policy.Prepare then policy.Prepare(tip, source) end
    local gap = self.TOOLTIP_GAP * screenScale
    local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
    local width, height = tip:GetWidth() * scale, tip:GetHeight() * scale
    if width > screenWidth - 2 * gap or height > screenHeight - 2 * gap then
        self:TransitionTooltipSources(tip, "sources.restore")
        tip:Hide()
        return
    end
    local alignment = alignmentFrame and self:GetTooltipRect(alignmentFrame) or original
    local titleTop = alignmentFrame and tip.TextLeft1:GetTop()
    local titleInset = titleTop and tip:GetTop() and (tip:GetTop() - titleTop) * scale or 0
    local desiredTop = centerVertically and (alignment.top + alignment.bottom + height) / 2
        or alignment.top + titleInset
    local alignedTop = math.max(height + gap, math.min(desiredTop, screenHeight - gap))
    local side = policy and policy.GetSide(source) or "right"
    local vertical = side == "top" or side == "bottom"
    local left = side == "left" and original.left - gap - width or original.right + gap
    if vertical then left = math.max(gap, math.min(original.left, screenWidth - width - gap)) end
    local top = side == "top" and original.top + gap + height
        or side == "bottom" and original.bottom - gap or alignedTop
    if policy and policy.allowNativeShift and (left < gap or left + width > screenWidth - gap) then
        local nativeWidth = original.right - original.left
        local translatedLeft = side == "left" and math.max(gap, original.left)
            or math.min(original.left, screenWidth - width - gap)
        local nativeLeft = side == "left" and translatedLeft + width + gap or translatedLeft - gap - nativeWidth
        if nativeLeft >= gap and nativeLeft + nativeWidth <= screenWidth - gap
            and self:TransitionTooltipSources(tip, "sources.place", {
            { source = source, left = nativeLeft, top = original.top },
        }) then
            original = self:GetTooltipRect(source)
            left = side == "left" and original.left - gap - width or original.right + gap
        end
    end
    local bounds = { left = left, right = left + width, top = top, bottom = top - height }
    -- Scaled anchors can differ by floating-point roundoff at an exact gap or screen edge.
    local epsilon = 0.01
    local fits = bounds.left >= gap - epsilon and bounds.right <= screenWidth - gap + epsilon
        and bounds.bottom >= gap - epsilon and bounds.top <= screenHeight - gap + epsilon
    if fits then
        for _, other in ipairs(occupied or { original }) do
            local current = other.frame and self:GetTooltipRect(other.frame) or other
            if bounds.left < current.right + gap - epsilon and bounds.right + gap > current.left + epsilon
                and bounds.bottom < current.top + gap - epsilon and bounds.top + gap > current.bottom + epsilon then
                fits = false
                break
            end
        end
    end
    if fits then
        tip:ClearAllPoints()
        if side == "top" then
            tip:SetPoint("BOTTOMLEFT", source, "TOPLEFT", (left - original.left) / scale, gap / scale)
        elseif side == "bottom" then
            tip:SetPoint("TOPLEFT", source, "BOTTOMLEFT", (left - original.left) / scale, -gap / scale)
        elseif side == "left" then
            tip:SetPoint("TOPRIGHT", source, "TOPLEFT", -gap / scale, (top - original.top) / scale)
        else
            tip:SetPoint("TOPLEFT", source, "TOPRIGHT", gap / scale, (top - original.top) / scale)
        end
        tip:Show()
        if tip:IsShown() then return bounds end
    end

    self:TransitionTooltipSources(tip, "sources.restore")
    tip:Hide()
end

function Addon:IsReadableEntityID(id)
    return canaccessallvalues(id) and type(id) == "number" and id > 0 and id % 1 == 0
end

function Addon:GetTooltipFocus(find, activeFrame)
    if activeFrame and InputUtil.IsGamepadUIEnabled() and not SmartNavigation:IsCursorHidden() then
        local selected = SmartNavigation:GetCurrentButton()
        local panel = SmartNavigation:GetActiveFrame()
        local frame = selected
        -- Navigation can belong to a parent panel or a nested subpanel. The
        -- component's resolver still owns the boundary and entity validation.
        while frame and panel do
            if frame:IsForbidden() then break end
            if frame == panel then
                local source, id, context = find(selected)
                if source then return source, id, context end
                break
            end
            frame = frame:GetParent()
        end
    end

    for _, frame in ipairs(GetMouseFoci() or {}) do
        local source, id, context = find(frame)
        if source then return source, id, context end
    end
end
