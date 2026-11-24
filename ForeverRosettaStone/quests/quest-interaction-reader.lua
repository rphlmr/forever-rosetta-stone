local _, Addon = ...

function Addon:CreateQuestInteractionReader()
    local function Dismiss()
        self:SendQuestInteraction({ type = "dismiss" })
        self:UpdateQuestInteraction()
    end
    local reader = self:CreateSideReader("ForeverRosettaStoneQuestInteraction", Dismiss)
    local frame, body, content, background = reader.frame, reader.body, reader.content, reader.background
    local parchment = content:CreateTexture(nil, "BACKGROUND", nil, 1)
    parchment:Hide()
    reader.parchment = parchment

    -- Same Options menu as the journal panel, for the quest the NPC screen is showing.
    local options = self:NewFrame("Button", nil, frame, "UIPanelButtonTemplate")
    options:SetSize(110, 22)
    options:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -32)
    options:SetText("Options")
    options:Hide()

    reader.options = options
    self:SetScript(options, "OnClick", function(owner)
        reader.reportOwner = true
        local context = reader.context
        if context == "gossip" or context == "greeting" then
            self:ShowTranslationOptions(owner, self:SettingsText("reportTranslation"), function()
                self:ShowNPCDialogueReport(context)
            end)
        elseif reader.questID then
            self:ShowQuestOptions(owner, reader.questID, reader.context)
        end
    end)

    self:SetupSideReaderController(reader, "ForeverRosettaStoneInteractionFooter", Dismiss)
    self:HookScript(frame, "OnHide", function() Addon:HideRewardTooltips() end)

    function reader:ShowSections(questID, context, sections, dialogueKey, missing)
        local greeting = context == "gossip" or context == "greeting"
        body.contentWidth = greeting and math.max(1, frame:GetWidth() - 68) or nil
        local keys = { tostring(questID), Addon:GetTargetLocale(), context, dialogueKey or "", tostring(body.contentWidth) }
        for _, section in ipairs(sections) do
            keys[#keys + 1] = section.text
            keys[#keys + 1] = tostring(section.source)
            keys[#keys + 1] = tostring(section.gap)
            keys[#keys + 1] = tostring(section.indent)
            keys[#keys + 1] = tostring(section.rowHeight)
            local art = section.icon
            if art then
                keys[#keys + 1] = table.concat({ art.atlas or art.texture, art.width, art.height, art.x or 0 }, ":")
            end
        end
        local key = table.concat(keys, "\031")
        frame:SetTitle(missing and "Forever Rosetta Stone" or Addon:GetTranslationLanguageLabel())
        Addon:FitQuestPanelTitle(frame)

        if self.contentKey ~= key then
            body:SetSections(sections, not missing and Addon:GetTargetLocale() or nil)
            body:ScrollTo(0)
            self.contentKey = key
        end
        local nativeTitleLeft = self:AlignWithNative(context)
        self:SyncRewards(context, nativeTitleLeft)
        self.questID = Addon:IsReadableEntityID(questID) and questID or nil
        self.context = context
        options:SetShown(self.questID ~= nil or greeting)
        frame:Show()
        self:SyncController()
        self:SyncTarget()
    end

    -- Mirror visible native regions (text, icons, art) onto a target without reparenting or
    -- activating them. Translate owned text and use a compatible font when needed.
    local function Mirror(owner, cache, target, origin, translate)
        if not owner:IsVisible() or owner:IsForbidden() then return end
        local highlight = owner.GetHighlightTexture and owner:GetHighlightTexture()
        for _, native in ipairs({ owner:GetRegions() }) do
            local kind = native:GetObjectType()
            local x, y = native:GetLeft(), native:GetTop()
            if native ~= highlight and not (origin.required and (native == QuestProgressTitleText or native == QuestProgressText))
                and native:IsShown() and x and y and (kind == "FontString" or kind == "Texture") then
                local region = cache[native]
                if not region then
                    if kind == "FontString" then region = target:CreateFontString(nil, "ARTWORK")
                    else
                        local layer, sublevel = native:GetDrawLayer()
                        region = target:CreateTexture(nil, layer, nil, sublevel)
                    end
                    cache[native] = region
                end
                region:SetAlpha(native:GetAlpha())
                if kind == "FontString" then
                    region:SetJustifyH(native:GetJustifyH())
                    region:SetJustifyV(native:GetJustifyV())
                    local text = native:GetText()
                    local translated, rewardName = translate(native, owner, text)
                    Addon:CopyQuestTextStyle(region, native, translated ~= text and Addon:GetTargetLocale() or nil)
                    region:SetText(translated)
                    local width = native:GetWidth() * origin.scale
                    local height = native:GetHeight() * origin.scale
                    if translated ~= text and rewardName and owner:GetRight() then
                        -- Fit the name between the icon and the edge of its native reward card.
                        local card = owner.NameFrame
                        if not card or not card:GetRight() or not card:GetTop() then card = owner end
                        local inset = 3
                        width = math.max(1, (card:GetRight() - x - inset) * origin.scale)
                        height = math.max(1, (card:GetHeight() - 2 * inset) * origin.scale)
                        y = card:GetTop() - inset
                        region:SetWordWrap(true)
                        region:SetJustifyV("MIDDLE")
                        region:SetSize(width, height)
                    else
                        if translated ~= text and (not native.GetNumLines or native:GetNumLines() <= 1)
                            and region.GetUnboundedStringWidth then
                            width = math.max(width, region:GetUnboundedStringWidth())
                        end
                        region:SetSize(width, height)
                        if translated ~= text and region:GetStringHeight() > height then region:SetHeight(0) end
                    end
                else
                    region:SetSize(native:GetWidth() * origin.scale, native:GetHeight() * origin.scale)
                    local atlas = native:GetAtlas()
                    if atlas then region:SetAtlas(atlas) else region:SetTexture(native:GetTexture()) end
                    region:SetTexCoord(native:GetTexCoord())
                    region:SetVertexColor(native:GetVertexColor())
                end
                region:ClearAllPoints()
                region:SetPoint("TOPLEFT", target, "TOPLEFT", (x - origin.left) * origin.scale + origin.x,
                    (y - origin.top) * origin.scale + origin.y)
                origin.height = math.max(origin.height or 0, (origin.top - y) * origin.scale + region:GetHeight())
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
        "REWARD_TRADESKILL_SPELL", "REWARD_FOLLOWER", "REWARD_UNLOCK", "REWARD_COMPANION",
        "TURN_IN_ITEMS", "REQUIRED_MONEY" }
    local function TranslateReward(source, native, owner, text)
        if native == source.Header then return Addon:GetQuestLabel("rewards") end
        local locale = Addon:GetTargetLocale()
        local name = owner.Name or (owner:GetName() and _G[owner:GetName() .. "Name"])
        if native == name and owner.objectType == "item" and GetQuestItemInfo then
            local itemID = select(6, GetQuestItemInfo(owner.type, owner:GetID()))
            if not Addon:IsReadableEntityID(itemID) and GetQuestItemLink then
                local link = GetQuestItemLink(owner.type, owner:GetID())
                if canaccessallvalues(link) and type(link) == "string" then itemID = tonumber(link:match("item:(%d+)")) end
            end
            if not Addon:IsReadableEntityID(itemID) and owner.type == "required"
                and C_TooltipInfo and C_TooltipInfo.GetQuestItem then
                local item = C_TooltipInfo.GetQuestItem(owner.type, owner:GetID())
                if canaccessallvalues(item) and type(item) == "table" then itemID = item.id end
            end
            return Addon:IsReadableEntityID(itemID) and ForeverRosettaStoneDB:GetItemName(itemID, locale) or text, true
        end
        if native == name and owner.rewardSpellID then
            return ForeverRosettaStoneDB:GetSpellName(owner.rewardSpellID, locale) or text, true
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

    function reader:SyncRewards(context, nativeTitleLeft)
        for _, region in pairs(rewardRegions) do region:Hide() end
        body.spacerHeight = 0
        local required = context == "progress"
        local source = required and QuestProgressScrollChildFrame
            or (context == "detail" or context == "reward") and QuestInfoRewardsFrame
        local anchor = source
        if required then
            anchor = QuestProgressRequiredItemsText and QuestProgressRequiredItemsText:IsVisible() and QuestProgressRequiredItemsText
                or QuestProgressRequiredMoneyText and QuestProgressRequiredMoneyText:IsVisible() and QuestProgressRequiredMoneyText
        end
        local left = source and source:IsVisible() and source:GetLeft()
        local top = anchor and anchor:GetTop()
        if not left or not top then
            -- Hover targets are only hidden when their reward goes away, never on each refresh,
            -- so a hovered or controller-selected reward keeps its tooltip.
            for _, button in ipairs(rewardButtons) do button.rewardSource = nil; button:Hide() end
            body:UpdateScrollRange()
            return
        end
        local scale = source:GetEffectiveScale() / body.child:GetEffectiveScale()
        -- The progress reader already aligns its text to the native title. Mirror the
        -- requirements relative to that title so the scroll child's inset is applied once.
        local originLeft = required and nativeTitleLeft or left
        local origin = { left = originLeft, top = top, scale = scale, x = 5, y = -body.textHeight, required = required }
        Mirror(source, rewardRegions, body.child, origin, function(native, owner, text)
            return TranslateReward(source, native, owner, text)
        end)
        SyncRewardButtons(source, origin)
        body.spacerHeight = (required and (origin.height or 0) or source:GetHeight() * scale) + 10
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
        if atlas then parchment:SetAtlas(atlas) else parchment:SetTexture(native:GetTexture()) end
        parchment:SetTexCoord(native:GetTexCoord())
        local scale = native:GetEffectiveScale() / source:GetEffectiveScale()
        parchment:ClearAllPoints()
        parchment:SetPoint("TOPLEFT", frame, "TOPLEFT", (left - sourceLeft) * scale, (top - sourceTop) * scale)
        parchment:SetSize(native:GetWidth() * scale, native:GetHeight() * scale)
        parchment:Show()
        background:Hide()
    end

    -- Start our text where the native screen starts its title, using unscrolled offsets so that
    -- scrolling either window never moves the other.
    local nativeScrollFrames = { detail = "QuestDetailScrollFrame", reward = "QuestRewardScrollFrame",
        progress = "QuestProgressScrollFrame" }
    function reader:AlignWithNative(context)
        local source = self.source
        if self.alignedContext ~= context then
            self.alignedContext = context
            body.frame:ClearAllPoints()
            body.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -8)
            body.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -5, 10)
        end
        if source and (context == "gossip" or context == "greeting") then
            local greeting = context == "gossip" and source.GreetingPanel
            local viewport = greeting and greeting.ScrollBox or QuestGreetingScrollFrame
            local bar = greeting and greeting.ScrollBar or viewport and viewport.ScrollBar
            Addon:AlignQuestViewport(body.frame, viewport, frame, source, 5)
            Addon:AlignQuestScrollBar(body.frame.ScrollBar, bar, frame, source)
            return
        end
        local scroll = nativeScrollFrames[context] and _G[nativeScrollFrames[context]]
        local title = scroll and (context == "progress" and QuestProgressTitleText or QuestInfoTitleHeader)
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
        local bar = body.frame.ScrollBar
        if not Addon:AlignQuestScrollBar(bar, scroll.ScrollBar, frame, source) then
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", content, "TOPRIGHT", 8, 9)
            bar:SetPoint("BOTTOMLEFT", content, "BOTTOMRIGHT", 8, -17)
        end
        return values[5]
    end

    function reader:Layout(source, policy, native)
        self.source = source
        Addon:SyncQuestInset(frame, source)
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
