local _, Addon = ...

function Addon:CreateQuestInteractionReader()
    local frame = self:NewFrame("Frame", "ForeverRosettaStoneQuestInteraction", UIParent,
        "ForeverRosettaStoneQuestPanelTemplate")
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
    local parchment = content:CreateTexture(nil, "BACKGROUND", nil, 1)
    parchment:Hide()
    local body = self:CreateNativeQuestBody(content, 278)
    body.frame:ClearAllPoints()
    body.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -8)
    body.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -5, 10)
    local close = self:NewFrame("Button", nil, frame, "UIPanelCloseButtonDefaultAnchors")
    frame.CloseButton = close
    self:SetScript(close, "OnClick", function() self:SendQuestInteraction({ type = "dismiss" }) end)

    -- Same Options menu as the journal panel, for the quest the NPC screen is showing.
    local options = self:NewFrame("Button", nil, frame, "UIPanelButtonTemplate")
    options:SetSize(110, 22)
    options:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -32)
    options:SetText("Options")
    options:Hide()

    local reader = { frame = frame, body = body, parchment = parchment, options = options }
    self:SetScript(options, "OnClick", function(owner)
        reader.reportOwner = true
        self:ShowQuestOptions(owner, reader.questID)
    end)

    -- Keep actions reachable without preselecting Options; the X gives way to Back.
    function reader:SyncTarget()
        local gamepad = InputUtil.IsGamepadUIEnabled()
        close:SetShown(not (gamepad and options:IsShown()))
        if not self.registered or InCombatLockdown() or SmartNavigation:GetActiveFrame() ~= frame then return end
        local selected = SmartNavigation:GetCurrentButton()
        if selected and not selected:IsVisible() then
            Addon:ClearGamepadTarget(frame)
        end
    end
    local footer = Addon:CreateGamepadLegend(frame, "ForeverRosettaStoneInteractionFooter")
    footer:AddStandardSelectPrompt()
    footer:AddStandardBackPrompt(FRAME_ACTION_CLOSE)
    footer:Finalize()
    footer:HidePrompts()

    function reader:ReleaseController()
        footer:HidePrompts()

        if not self.registered or InCombatLockdown() then return end

        self.registered = nil
        GamepadMode.FrameControlsManager:FrameHidden(frame)
        SmartNavigation:RemovePanelInfo(frame)
    end

    -- Like the journal, step aside while the report modal owns focus, and take focus back
    -- when the report this reader opened closes.
    function reader:SyncController(focus)
        if not InputUtil.IsGamepadUIEnabled() or not frame:IsShown()
            or (Addon.questReport and Addon.questReport.frame:IsShown()) then
            self:ReleaseController()
            return
        end

        if not self.registered and not InCombatLockdown() then
            self.registered = true
            GamepadMode.FrameControlsManager:FrameShown(frame, false, focus == true)
        end
    end

    frame.FocusGamepad = self:Wrap("focus NPC translation", function()
        if not reader.registered or InCombatLockdown() then return end

        SmartNavigation:SetScrollFrameForFrame(frame, body.frame)
        SmartNavigation_MarkScrollFrameMaintainPreviousButtonOnScroll(body.frame)
        Addon:ClearGamepadTarget(frame)
        footer:ShowPrompts()
    end)
    frame.UnfocusGamepad = self:Wrap("leave NPC translation", function()
        footer:HidePrompts()

        if not InCombatLockdown() then SmartNavigation:SetScrollFrameForFrame(frame, nil) end
    end)
    frame.SmartNavigationCloseHandler = self:Wrap("close NPC translation", function()
        self:SendQuestInteraction({ type = "dismiss" })
        return true
    end, true)
    self:HookScript(frame, "OnHide", function()
        reader:ReleaseController()
        Addon:HideRewardTooltips()
    end)

    function reader:ShowQuest(questID, quest, context)
        local sections = Addon:GetQuestInteractionSections(questID, quest)
        local keys = { tostring(questID), Addon:GetTargetLocale(), context }
        for _, section in ipairs(sections) do keys[#keys + 1] = section.text end
        local key = table.concat(keys, "\031")
        frame:SetTitle(Addon:GetTranslationLanguageLabel())
        Addon:FitQuestPanelTitle(frame)

        if self.contentKey ~= key then
            body:SetSections(sections)
            body:ScrollTo(0)
            self.contentKey = key
        end
        self:AlignWithNative(context)
        self:SyncRewards(context)
        self.questID = Addon:IsReadableEntityID(questID) and questID or nil
        options:SetShown(self.questID ~= nil)
        frame:Show()
        self:SyncController()
        self:SyncTarget()
    end

    -- Mirror visible native regions (text, icons, art) onto a target without reparenting or
    -- activating them. Position, font, color and icons stay the client's; only text that has an
    -- owned translation is replaced by the translate callback.
    local function Mirror(owner, cache, target, origin, translate)
        if not owner:IsVisible() or owner:IsForbidden() then return end
        local highlight = owner.GetHighlightTexture and owner:GetHighlightTexture()
        for _, native in ipairs({ owner:GetRegions() }) do
            local kind = native:GetObjectType()
            local x, y = native:GetLeft(), native:GetTop()
            if native ~= highlight and native:IsShown() and x and y and (kind == "FontString" or kind == "Texture") then
                local region = cache[native]
                if not region then
                    if kind == "FontString" then region = target:CreateFontString(nil, "ARTWORK")
                    else
                        local layer, sublevel = native:GetDrawLayer()
                        region = target:CreateTexture(nil, layer, nil, sublevel)
                    end
                    cache[native] = region
                end
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", target, "TOPLEFT", (x - origin.left) * origin.scale + origin.x,
                    (y - origin.top) * origin.scale + origin.y)
                region:SetAlpha(native:GetAlpha())
                if kind == "FontString" then
                    Addon:CopyQuestTextStyle(region, native)
                    region:SetJustifyH(native:GetJustifyH())
                    region:SetJustifyV(native:GetJustifyV())
                    local text = native:GetText()
                    local translated = translate(native, owner, text)
                    region:SetText(translated)
                    -- Translated text keeps the native width but may need more room: a single-line
                    -- label widens to fit, wrapped text grows downward, nothing is truncated.
                    local width = native:GetWidth() * origin.scale
                    if translated ~= text and (not native.GetNumLines or native:GetNumLines() <= 1)
                        and region.GetUnboundedStringWidth then
                        width = math.max(width, region:GetUnboundedStringWidth())
                    end
                    -- Keep the native box so its vertical justification still centers the text;
                    -- only translated text taller than that box grows downward.
                    local height = native:GetHeight() * origin.scale
                    region:SetSize(width, height)
                    if translated ~= text and region:GetStringHeight() > height then region:SetHeight(0) end
                else
                    region:SetSize(native:GetWidth() * origin.scale, native:GetHeight() * origin.scale)
                    local atlas = native:GetAtlas()
                    if atlas then region:SetAtlas(atlas) else region:SetTexture(native:GetTexture()) end
                    region:SetTexCoord(native:GetTexCoord())
                    region:SetVertexColor(native:GetVertexColor())
                end
                region:Show()
            end
        end
        for _, child in ipairs({ owner:GetChildren() }) do Mirror(child, cache, target, origin, translate) end
    end

    -- Counts, money, XP and reward choices continue to belong to the client.
    local rewardRegions = {}
    -- Every client GlobalString QuestInfo can print in its rewards frame (QuestInfo.xml labels,
    -- QuestInfo_ShowRewards and QUEST_INFO_SPELL_REWARD_TO_HEADER). The native text is matched
    -- by value and translated by the same key.
    local rewardLabelKeys = { "REWARD_CHOICES", "REWARD_CHOOSE", "REWARD_ITEMS", "REWARD_ITEMS_ONLY",
        "REWARD_TITLE", "EXPERIENCE_COLON", "HONOR", "REWARD_SPELL", "REWARD_ABILITY", "REWARD_AURA",
        "REWARD_TRADESKILL_SPELL", "REWARD_FOLLOWER", "REWARD_UNLOCK", "REWARD_COMPANION" }
    local function TranslateReward(source, native, owner, text)
        if native == source.Header then return Addon:GetQuestLabel("rewards") end
        local locale = Addon:GetTargetLocale()
        if native == owner.Name and owner.objectType == "item" and GetQuestItemInfo then
            local itemID = select(6, GetQuestItemInfo(owner.type, owner:GetID()))
            return itemID and ForeverRosettaStoneDB:GetItemName(itemID, locale) or text
        end
        if native == owner.Name and owner.rewardSpellID then
            return ForeverRosettaStoneDB:GetSpellName(owner.rewardSpellID, locale) or text
        end
        for _, key in ipairs(rewardLabelKeys) do
            if text and text == _G[key] then return Addon:GetClientLabel(key, locale) or text end
        end
        return text
    end

    -- Native reward buttons stay where they are; transparent buttons over their mirrored copy
    -- carry the hover and gamepad target.
    local rewardButtons = {}
    frame.hasRewardTooltips = true
    local function HideRewardTooltip(button)
        Addon:HideRewardTooltips(button)
        if Addon:GetWidgetTooltip():IsOwned(button) then Addon:GetWidgetTooltip():Hide() end
    end
    -- Items and spells use the journal's translated reward tooltip (mouse and gamepad alike);
    -- currencies have no owned translation and keep the native tooltip.
    local function ShowRewardTooltip(button)
        local source = button.rewardSource
        if source.objectType ~= "currency" then Addon:UpdateRewardTooltips(button); return end
        Addon:GetWidgetTooltip():SetOwner(button, "ANCHOR_RIGHT")
        Addon:GetWidgetTooltip():SetQuestCurrency(source.type, source:GetID())
    end
    local function SyncRewardButtons(source, origin)
        local index = 0
        for _, native in ipairs({ source:GetChildren() }) do
            local left, top = native:GetLeft(), native:GetTop()
            if native:IsVisible() and not native:IsForbidden() and left and top
                and (native.objectType == "item" or native.objectType == "currency" or native.rewardSpellID) then
                index = index + 1
                local button = rewardButtons[index]
                if not button then
                    button = Addon:NewFrame("Button", nil, body.child)
                    button.rewardQuestLog = false
                    button.rewardPanel = frame
                    Addon:SetScript(button, "OnEnter", ShowRewardTooltip)
                    Addon:SetScript(button, "OnLeave", HideRewardTooltip)
                    Addon:HookScript(button, "OnHide", HideRewardTooltip)
                    rewardButtons[index] = button
                end
                button.rewardSource = native
                button:ClearAllPoints()
                button:SetPoint("TOPLEFT", body.child, "TOPLEFT", (left - origin.left) * origin.scale + origin.x,
                    (top - origin.top) * origin.scale + origin.y)
                button:SetSize(native:GetWidth() * origin.scale, native:GetHeight() * origin.scale)
                button:Show()
            end
        end
        for position = index + 1, #rewardButtons do
            rewardButtons[position].rewardSource = nil
            rewardButtons[position]:Hide()
        end
    end

    function reader:SyncRewards(context)
        for _, region in pairs(rewardRegions) do region:Hide() end
        body.spacerHeight = 0
        local source = context == "detail" and QuestInfoRewardsFrame
        local left, top = source and source:IsVisible() and source:GetLeft(), source and source:GetTop()
        if not left or not top then
            -- Hover targets are only hidden when their reward goes away, never on each refresh,
            -- so a hovered or controller-selected reward keeps its tooltip.
            for _, button in ipairs(rewardButtons) do button.rewardSource = nil; button:Hide() end
            body:UpdateScrollRange()
            return
        end
        local scale = source:GetEffectiveScale() / body.child:GetEffectiveScale()
        local origin = { left = left, top = top, scale = scale, x = 5, y = -body.textHeight }
        Mirror(source, rewardRegions, body.child, origin, function(native, owner, text)
            return TranslateReward(source, native, owner, text)
        end)
        SyncRewardButtons(source, origin)
        body.spacerHeight = source:GetHeight() * scale + 10
        body:UpdateScrollRange()
    end

    -- Copy the parchment the visible native panel draws (its atlas, size and offset), so the
    -- companion keeps the same torn edges, contrast mode and quest theme as the original.
    function reader:SyncBackground(source, native)
        local left, top = native and native:GetLeft(), native and native:GetTop()
        local sourceLeft, sourceTop = source:GetLeft(), source:GetTop()
        if not (native and native:IsVisible() and left and top and sourceLeft and sourceTop) then
            parchment:Hide()
            background:Show()
            return
        end
        local atlas = native:GetAtlas()
        if atlas then parchment:SetAtlas(atlas) else
            parchment:SetTexture(native:GetTexture())
            parchment:SetTexCoord(native:GetTexCoord())
        end
        local scale = native:GetEffectiveScale() / source:GetEffectiveScale()
        parchment:ClearAllPoints()
        parchment:SetPoint("TOPLEFT", frame, "TOPLEFT", (left - sourceLeft) * scale, (top - sourceTop) * scale)
        parchment:SetSize(native:GetWidth() * scale, native:GetHeight() * scale)
        parchment:Show()
        background:Hide()
    end

    -- Start our text where the native screen starts its title, using unscrolled offsets so that
    -- scrolling either window never moves the other.
    local nativeScrollFrames = { detail = "QuestDetailScrollFrame" }
    local nativeTitles = { detail = "QuestInfoTitleHeader" }
    function reader:AlignWithNative(context)
        local source = self.source
        local scroll = nativeScrollFrames[context] and _G[nativeScrollFrames[context]]
        local title = nativeTitles[context] and _G[nativeTitles[context]]
        local child = scroll and scroll.GetScrollChild and scroll:GetScrollChild()
        local values = source and child and title and title:IsVisible() and {
            source:GetLeft(), source:GetTop(), scroll:GetTop(), child:GetTop(), title:GetLeft(), title:GetTop() }
        if not (values and #values == 6) then return end
        local scale = title:GetEffectiveScale() / source:GetEffectiveScale()
        local x = (values[5] - values[1]) * scale - 5
        local y = (values[3] - values[2] + values[6] - values[4]) * scale + 10
        body.frame:ClearAllPoints()
        body.frame:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
        body.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -5, 10)
        -- The scroll bar follows the native one, not the text, so it never rises into the header.
        local bar, nativeBar = body.frame.ScrollBar, scroll.ScrollBar
        local barLeft, barTop = nativeBar and nativeBar:GetLeft(), nativeBar and nativeBar:GetTop()
        local barBottom = nativeBar and nativeBar:GetBottom()
        bar:ClearAllPoints()
        if barLeft and barTop and barBottom and nativeBar:IsVisible() then
            local barScale = nativeBar:GetEffectiveScale() / source:GetEffectiveScale()
            bar:SetPoint("TOPLEFT", frame, "TOPLEFT", (barLeft - values[1]) * barScale, (barTop - values[2]) * barScale)
            bar:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", (barLeft - values[1]) * barScale, (barBottom - values[2]) * barScale)
        else
            bar:SetPoint("TOPLEFT", content, "TOPRIGHT", 8, 9)
            bar:SetPoint("BOTTOMLEFT", content, "BOTTOMRIGHT", 8, -17)
        end
    end

    function reader:Layout(source, policy, native)
        self.source = source
        self:SyncBackground(source, native)
        local scale = source:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local side = policy.GetSide(source)
        local key = table.concat({ tostring(source), policy.context, policy.inputMode, scale, source:GetWidth(), source:GetHeight(),
            source:GetLeft() or 0, source:GetTop() or 0, side, source:GetFrameStrata(), source:GetFrameLevel() }, ":")

        if self.layoutKey == key then return end

        frame:SetScale(scale)
        frame:SetSize(source:GetWidth(), source:GetHeight())
        frame:SetFrameStrata(source:GetFrameStrata())
        frame:SetFrameLevel(source:GetFrameLevel() + 20)
        frame:SetFrameLevelsFromBaseLevel(frame:GetFrameLevel())
        frame:ClearAllPoints()
        frame:SetPoint(side == "left" and "TOPRIGHT" or "TOPLEFT", source,
            side == "left" and "TOPLEFT" or "TOPRIGHT", 0, 0)
        self.layoutKey = key
    end

    return reader
end
