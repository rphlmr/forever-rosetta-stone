-- Native Forever quest components and QUEST_TEMPLATE_MAP_DETAILS layout.
-- Reward mirroring adapted from Spoken 3.8.3.
-- Copyright (c) 2026 Rusty Key (MIT). See THIRD-PARTY.md.
local _, Addon = ...

local function GetRewardName(source)
    if source.objectType ~= "item" then return source.Name:GetText() end

    local query = source.type == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
    local itemID = select(6, query(source:GetID()))

    local translated = ForeverRosettaStoneDB:GetItemName(itemID, Addon:GetTargetLocale())
    return translated or source.Name:GetText(), translated ~= nil
end

function Addon:CopyQuestTextStyle(target, source, locale, ...)
    if not target or not source then return end
    local font, size, flags = source:GetFont(...)
    if font and size and not Addon:TryLocalizedFont(target, locale, size, flags) then
        target:SetFont(font, size, flags)
    end
    target:SetTextColor(source:GetTextColor(...))
    target:SetShadowColor(source:GetShadowColor(...))
    target:SetShadowOffset(source:GetShadowOffset(...))
    target:SetSpacing(source:GetSpacing(...))
end

-- The target's parent mirrors the native details frame. Bottom anchoring preserves rewards height.
function Addon:CopyQuestFrameLayout(target, source, anchor, bottomLimit)
    if not target or not source or not QuestMapFrame or not QuestMapFrame.DetailsFrame then return end
    local details = QuestMapFrame.DetailsFrame
    local point = anchor or "TOPLEFT"
    local left = source:GetLeft()
    local edge = source:GetTop()

    if point == "BOTTOMLEFT" then edge = source:GetBottom() end

    local detailsLeft, detailsTop = details:GetLeft(), details:GetTop()

    if not (left and edge and detailsLeft and detailsTop) then return end

    local sourceScale, targetScale = source:GetEffectiveScale(), target:GetEffectiveScale()
    local detailsScale = details:GetEffectiveScale()
    local y = (edge * sourceScale - detailsTop * detailsScale) / targetScale
    local height = source:GetHeight() * sourceScale / targetScale
    if bottomLimit and point == "BOTTOMLEFT" then y = math.max(y, bottomLimit) end
    if bottomLimit and point == "TOPLEFT" then height = math.max(1, math.min(height, y - bottomLimit)) end
    target:ClearAllPoints()
    target:SetPoint(point, target:GetParent(), "TOPLEFT",
        (left * sourceScale - detailsLeft * detailsScale) / targetScale,
        y)
    target:SetWidth(source:GetWidth() * sourceScale / targetScale)

    if point == "TOPLEFT" then target:SetHeight(height) end
    return true
end

function Addon:AlignQuestScrollBar(target, native, panel, source, bottomLimit)
    local left, top = native and native:GetLeft(), native and native:GetTop()
    local bottom = native and native:GetBottom()
    local sourceLeft, sourceTop = source:GetLeft(), source:GetTop()
    if not (target and left and top and bottom and sourceLeft and sourceTop) then return false end
    local scale = native:GetEffectiveScale() / source:GetEffectiveScale()
    local x = (left - sourceLeft) * scale
    target:ClearAllPoints()
    target:SetWidth(native:GetWidth() * scale)
    local topOffset = (top - sourceTop) * scale
    local bottomOffset = (bottom - sourceTop) * scale
    if bottomLimit then bottomOffset = math.min(topOffset - 1, math.max(bottomOffset, bottomLimit)) end
    target:SetPoint("TOPLEFT", panel, "TOPLEFT", x, topOffset)
    target:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", x, bottomOffset)
    return true
end

function Addon:AlignQuestViewport(target, native, panel, source, leftInset)
    local left, top = native and native:GetLeft(), native and native:GetTop()
    local sourceLeft, sourceTop = source:GetLeft(), source:GetTop()
    if not (left and top and sourceLeft and sourceTop) then return end
    local scale = native:GetEffectiveScale() / source:GetEffectiveScale()
    local x = leftInset or 0
    target:ClearAllPoints()
    target:SetPoint("TOPLEFT", panel, "TOPLEFT", (left - sourceLeft) * scale + x, (top - sourceTop) * scale)
    target:SetSize(math.max(1, native:GetWidth() * scale - x), native:GetHeight() * scale)
    return scale
end

function Addon:SyncQuestInset(panel, source)
    local native = source.Inset
    local inset = panel.questInset
    local left, top = native and native:GetLeft(), native and native:GetTop()
    local sourceLeft, sourceTop = source:GetLeft(), source:GetTop()
    if not (left and top and sourceLeft and sourceTop and native:IsVisible()) then
        if inset then inset:Hide() end
        return
    end
    if not inset then
        inset = self:NewFrame("Frame", nil, panel, "InsetFrameTemplate")
        panel.questInset = inset
    end
    local scale = native:GetEffectiveScale() / source:GetEffectiveScale()
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", panel, "TOPLEFT", (left - sourceLeft) * scale, (top - sourceTop) * scale)
    inset:SetSize(native:GetWidth() * scale, native:GetHeight() * scale)
    inset:Show()
end

function Addon:CreateNativeQuestBody(parent, contentWidth)
    local scroll = self:NewFrame("EventScrollFrame", nil, parent, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -43)
    scroll.ScrollBar:ClearAllPoints()
    scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 13, 17)
    scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 13, -27)

    for _, event in ipairs({ "OnMouseWheel", "OnVerticalScroll", "OnScrollRangeChanged" }) do
        self:SetScript(scroll, event, scroll:GetScript(event))
    end

    local contents = self:NewFrame("Frame", nil, scroll)
    contents:SetSize(298, 1)
    scroll:SetScrollChild(contents)
    local body = { frame = scroll, child = contents, sections = {}, rowIcons = {}, textHeight = 1, spacerHeight = 0 }

    function body:ScrollTo(offset)
        scroll:SetVerticalScroll(math.max(0, math.min(offset, scroll:GetVerticalScrollRange())))
    end

    function body:UpdateScrollRange()
        contents:SetHeight(self.textHeight + self.spacerHeight)
        scroll:UpdateScrollChildRect()

        if scroll:GetVerticalScroll() > scroll:GetVerticalScrollRange() then
            self:ScrollTo(scroll:GetVerticalScrollRange())
        end
    end

    function body:SetSections(sections, locale)
        self.lastSections = sections
        self.locale = locale
        local wrapWithoutSpaces = Addon:UsesNonSpaceWrap(locale)
        local width = self.contentWidth or contentWidth or QUEST_TEMPLATE_MAP_DETAILS.contentWidth
        local leftInset = self.textInsetX or 5
        contents:SetWidth(width + leftInset)
        local offset = self.textInsetY or 10
        for _, icon in pairs(self.rowIcons) do icon:Hide() end

        for index, section in ipairs(sections) do
            local text = self.sections[index]

            if not text then
                text = contents:CreateFontString(nil, "ARTWORK")
                text:SetJustifyH("LEFT")
                text:SetJustifyV("TOP")
                text:SetWordWrap(true)
                self.sections[index] = text
            end

            offset = offset + section.gap
            if section.textType then
                Addon:CopyQuestTextStyle(text, section.source, locale, section.textType)
            else
                Addon:CopyQuestTextStyle(text, section.source, locale)
            end
            text:SetNonSpaceWrap(wrapWithoutSpaces)
            text:ClearAllPoints()
            local indent = section.indent or 0
            text:SetWidth(math.max(1, width - indent))
            text:SetText(section.text)
            text:Show()
            local height = text:GetStringHeight()
            if section.rowHeight then
                height = math.max(height, section.rowHeight)
                local center = -(offset + height / 2)
                text:SetPoint("LEFT", contents, "TOPLEFT", leftInset + indent, center)
                local art = section.icon
                if art then
                    local icon = self.rowIcons[index]
                    if not icon then
                        icon = contents:CreateTexture(nil, "ARTWORK")
                        self.rowIcons[index] = icon
                    end
                    if art.atlas then icon:SetAtlas(art.atlas) else icon:SetTexture(art.texture) end
                    icon:SetSize(art.width, art.height)
                    icon:ClearAllPoints()
                    icon:SetPoint("LEFT", contents, "TOPLEFT", leftInset + (art.x or 0), center)
                    icon:Show()
                end
            else
                text:SetPoint("TOPLEFT", contents, "TOPLEFT", leftInset, -offset)
            end
            offset = offset + height
        end

        for index = #sections + 1, #self.sections do self.sections[index]:Hide() end

        self.textHeight = offset + 10
        self:UpdateScrollRange()
    end

    self:SetScript(scroll, "OnSizeChanged", function()
        if body.lastSections then body:SetSections(body.lastSections, body.locale) end
    end)

    return body
end

function Addon:GetQuestPageSections(entry)
    local decorated = entry.missing and entry.title or QuestUtils_DecorateQuestText(entry.questID, entry.title, true)
    local progress = not entry.missing and entry.progress == entry.objectives and "" or entry.progress

    return {
        { source = QuestInfoTitleHeader, text = decorated, gap = 0 },
        { source = QuestInfoObjectivesText, text = entry.objectives, gap = 5 },
        { source = QuestInfoObjective1, text = progress, gap = 10 },
        { source = QuestInfoDescriptionHeader,
            text = entry.missing and QuestInfoDescriptionHeader:GetText() or self:GetQuestLabel("description"), gap = 20 },
        { source = QuestInfoDescriptionText, text = entry.description, gap = 5 },
    }
end

function Addon:CreateQuestPage(parent)
    local frame = self:NewFrame("Frame", nil, parent)
    frame:SetAllPoints()
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("QuestDetailsBackgrounds", true)
    background:SetPoint("TOPLEFT")
    background:SetPoint("TOPRIGHT")
    local body = self:CreateNativeQuestBody(frame)

    local rewards = Addon:NewFrame("Frame", nil, frame)
    rewards:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 23)
    rewards:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 23)
    rewards:SetFrameLevel(frame:GetFrameLevel() + 50)
    rewards:SetClipsChildren(true)
    local rewardContents = Addon:NewFrame("Frame", nil, rewards)
    rewards.RewardsFrame = rewardContents
    frame.RewardsFrameContainer, frame.ScrollFrame = rewards, body.frame
    rewardContents:SetPoint("TOPLEFT")
    rewardContents:SetPoint("TOPRIGHT")
    local top = rewardContents:CreateTexture(nil, "BORDER", nil, 1)
    top:SetAtlas("questlog-reward-header-top", true)
    top:SetPoint("TOPLEFT")
    local bottom = rewardContents:CreateTexture(nil, "BORDER", nil, 1)
    bottom:SetAtlas("questlog-reward-bottom", true)
    bottom:SetPoint("BOTTOMLEFT")
    local fill = rewardContents:CreateTexture(nil, "BACKGROUND")
    fill:SetAtlas("questlog-reward-tile-vertical")
    fill:SetPoint("TOPLEFT", top, "BOTTOMLEFT")
    fill:SetPoint("RIGHT", bottom, "RIGHT")
    fill:SetPoint("BOTTOM")
    local label = rewardContents:CreateFontString(nil, "ARTWORK", "QuestFont_Huge")
    label:SetPoint("TOP", rewardContents, "TOP", 0, -22)
    label:SetText("Rewards")
    local receive = rewardContents:CreateFontString(nil, "ARTWORK", "QuestMapRewardsFont")
    receive:SetPoint("TOPLEFT", rewardContents, "TOPLEFT", 12, -52)
    receive:SetText("You will receive:")
    local choose = rewardContents:CreateFontString(nil, "ARTWORK", "QuestMapRewardsFont")
    choose:SetText("Choose one of these rewards:")

    local page = { body = body, background = background, rewards = rewards,
        rewardButtons = {}, receiveText = receive, rewardLabel = label }
    local beer = Addon:NewFrame("Button", nil, rewardContents, "SmallItemButtonTemplate")
    beer:SetSize(134, 30)
    beer:SetPoint("TOPLEFT", receive, "BOTTOMLEFT", 0, -5)
    beer:EnableMouse(false)
    SmartNavigation_MarkFrameIgnored(beer)
    beer:Hide()
    page.beerReward = beer

    local function AdjustRewards()
        if not rewards:IsShown() then return end

        if page.missingQuest then
            rewards.isFixedHeight = true
            rewards:SetHeight(rewardContents:GetHeight())
        else
            rewards.isFixedHeight = nil
            QuestLogQuestDetailsMixin.AdjustRewardsFrameContainer(frame)
        end
    end

    for _, event in ipairs({ "OnVerticalScroll", "OnScrollRangeChanged" }) do
        body.frame:RegisterCallback(event, Addon:Wrap("adjust English rewards", AdjustRewards), page)
    end

    function page:RefreshNativeLayout()
        local details = QuestMapFrame.DetailsFrame
        local native = details.RewardsFrameContainer
        local shown = self.missingQuest or (native:IsShown() and MapQuestInfoRewardsFrame:IsShown())
        local limit = self.bottomLimit
        local nativeBottom, detailsTop = native:GetBottom(), details:GetTop()
        local nativeScale = native:GetEffectiveScale()
        local frameScale = frame:GetEffectiveScale()
        local rewardsOverflow = shown and limit and nativeBottom and detailsTop
            and (nativeBottom * nativeScale - detailsTop * details:GetEffectiveScale()) / frameScale < limit
        local viewportLimit
        local scroll = details.ScrollFrame
        local scrollBottom = scroll:GetBottom()
        if rewardsOverflow and scrollBottom then
            local gap = (scrollBottom * scroll:GetEffectiveScale() - nativeBottom * nativeScale) / frameScale
            viewportLimit = limit + math.max(0, gap)
        end
        background:SetAtlas(QuestTextContrast.GetDefaultDetailsBackgroundAtlas())

        QuestLogQuestDetailsMixin.AdjustBackgroundTexture(details, background)
        if details.Bg and details.Bg:GetLeft() and details.Bg:GetTop() then
            local atlas = details.Bg:GetAtlas()
            if atlas then background:SetAtlas(atlas) else background:SetTexture(details.Bg:GetTexture()) end
            background:SetTexCoord(details.Bg:GetTexCoord())
            background:SetSize(details.Bg:GetSize())
            Addon:CopyQuestFrameLayout(background, details.Bg, nil, rewardsOverflow and limit or nil)
        end

        rewards:SetShown(shown)
        local rewardHeight = self.missingQuest and 124 or native.RewardsFrame:GetHeight()
        local height = shown and rewardHeight or 0
        rewardContents:SetHeight(rewardHeight)
        if not Addon:CopyQuestFrameLayout(body.frame, scroll, nil, viewportLimit) then
            body.frame:SetSize(scroll:GetSize())
        end
        Addon:AlignQuestScrollBar(body.frame.ScrollBar, scroll.ScrollBar, frame, details, viewportLimit)
        Addon:CopyQuestFrameLayout(rewards, native, "BOTTOMLEFT", limit)
        body.spacerHeight = height
        body:UpdateScrollRange()
        AdjustRewards()
        local locale = not self.missingQuest and Addon:GetTargetLocale() or nil
        Addon:CopyQuestTextStyle(label, native.RewardsFrame.Label, locale)
        label:SetText(self.missingQuest and native.RewardsFrame.Label:GetText() or Addon:GetQuestLabel("rewards"))
        label:SetShown(self.missingQuest or native.RewardsFrame.Label:IsShown())
        Addon:CopyQuestTextStyle(receive, MapQuestInfoRewardsFrame.ItemReceiveText, locale)
        receive:SetText(self.missingQuest and REWARD_ITEMS_ONLY or Addon:GetQuestLabel("receive"))
        receive:SetShown(self.missingQuest or MapQuestInfoRewardsFrame.ItemReceiveText:IsShown())
        Addon:CopyQuestTextStyle(choose, MapQuestInfoRewardsFrame.ItemChooseText)
        choose:SetShown(not self.missingQuest and MapQuestInfoRewardsFrame.ItemChooseText:IsShown())

        local sourceFrame = MapQuestInfoRewardsFrame
        local baseLeft, baseTop = sourceFrame:GetLeft(), sourceFrame:GetTop()

        if self.missingQuest or not shown or not (baseLeft and baseTop) then
            if self.missingQuest then
                receive:ClearAllPoints()
                receive:SetPoint("TOPLEFT", rewardContents, "TOPLEFT", 12,
                    -52 - sourceFrame.Header:GetHeight() - 5)
            end

            for _, button in ipairs(self.rewardButtons) do button.rewardSource = nil; button:Hide() end
            return
        end

        for _, pair in ipairs({{receive, sourceFrame.ItemReceiveText}, {choose, sourceFrame.ItemChooseText}}) do
            local target, source = pair[1], pair[2]
            local left, topEdge = source:GetLeft(), source:GetTop()

            if source:IsShown() and left and topEdge then
                target:ClearAllPoints()
                target:SetPoint("TOPLEFT", rewardContents, "TOPLEFT", left - baseLeft + 12, topEdge - baseTop - 52)
            end
        end

        local buttonIndex = 0

        for _, source in ipairs(sourceFrame.activeRewardElements) do
            local left, topEdge = source:GetLeft(), source:GetTop()

            if source.smallItemButton and source:IsShown() and left and topEdge then
                buttonIndex = buttonIndex + 1
                local button = self.rewardButtons[buttonIndex]

                if not button then
                    button = Addon:NewFrame("Button", nil, rewardContents, "SmallItemButtonTemplate")
                    Addon:SetScript(button, "OnEnter", function(owner) Addon:UpdateRewardTooltips(owner) end)
                    local function HideTooltips(owner) Addon:HideRewardTooltips(owner) end
                    Addon:SetScript(button, "OnLeave", HideTooltips)
                    Addon:HookScript(button, "OnHide", HideTooltips)
                    button.IconBorder = button:CreateTexture(nil, "OVERLAY", nil, 1)
                    button.IconBorder:SetAllPoints(button.Icon)
                    self.rewardButtons[buttonIndex] = button
                end
                button.rewardSource = source
                button:EnableMouse(source.objectType == "item" and Addon:IsFeatureEnabled("rewardComparison"))
                if source.objectType ~= "item" then Addon:HideRewardTooltips(button) end
                button:SetSize(source:GetSize())
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", rewardContents, "TOPLEFT", left - baseLeft + 12, topEdge - baseTop - 52)
                button.Icon:SetTexture(source.Icon:GetTexture())
                button.Icon:SetTexCoord(source.Icon:GetTexCoord())
                button.Icon:SetVertexColor(source.Icon:GetVertexColor())
                local border = source.IconBorder
                button.IconBorder:SetShown(border ~= nil and border:IsShown())

                if border then
                    button.IconBorder:SetTexture(border:GetTexture())
                    button.IconBorder:SetTexCoord(border:GetTexCoord())
                    button.IconBorder:SetVertexColor(border:GetVertexColor())
                    button.IconBorder:SetAlpha(border:GetAlpha())
                end

                button.NameFrame:SetVertexColor(source.NameFrame:GetVertexColor())
                local name, translated = GetRewardName(source)
                Addon:CopyQuestTextStyle(button.Name, source.Name, translated and locale or nil)
                button.Name:SetText(name)
                if button.Count and source.Count then button.Count:SetText(source.Count:GetText()) end
                button:Show()
            end
        end

        for index = buttonIndex + 1, #self.rewardButtons do
            self.rewardButtons[index].rewardSource = nil
            self.rewardButtons[index]:Hide()
        end
    end

    function page:Show(entry)
        self.missingQuest = entry.missing
        beer:SetShown(entry.missing == true)
        if entry.missing then
            beer.Icon:SetTexture([[Interface\Icons\INV_Drink_03]])
            beer.Name:SetText(entry.reward)
            beer.Count:SetText("100")
        end
        body:SetSections(Addon:GetQuestPageSections(entry), entry.missing and GetLocale() or Addon:GetTargetLocale())
        self:RefreshNativeLayout()
    end

    return page
end
