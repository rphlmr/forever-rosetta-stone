local _, Addon = ...

local function GetColor(color)
    if color then return color:GetRGB() end

    return 1, 1, 1
end

local function TranslateBinding(text)
    if Addon:GetTargetLocale() ~= "enUS" then return text end

    for key, translated in pairs(Addon.itemTooltipLabels) do
        if key:sub(1, 5) == "ITEM_" and _G[key] == text then return translated end
    end

    return text
end

local function GetComparisonItem(data)
    if data.guid then return { guid = data.guid, overrideItemLevel = data.overrideItemLevel } end
    if data.hyperlink and data.hyperlink ~= "" then
        return { hyperlink = data.hyperlink, overrideItemLevel = data.overrideItemLevel }
    end
end

local function GetComparisonData(item)
    if not item then return end
    if item.guid then return C_TooltipInfo.GetItemByGUID(item.guid) end
    if item.hyperlink then return C_TooltipInfo.GetHyperlink(item.hyperlink) end
end

local function FindRewardButton(owner)
    while owner and owner ~= Addon.panel do
        if owner:IsForbidden() then return end
        if owner.rewardSource then return owner end

        owner = owner:GetParent()
    end
end

local function FillTooltip(tip, button, data, header)
    if not data then return false end

    local nameLine

    for _, line in ipairs(data.lines) do
        if line.type == Enum.TooltipDataLineType.ItemName then nameLine = line; break end
    end

    if not nameLine then return false end

    local _, _, _, equipLoc, _, classID, subclassID = C_Item.GetItemInfoInstant(data.id)
    local englishLabels = Addon:GetTargetLocale() == "enUS"
    local subclasses = englishLabels and Addon.itemSubclasses[classID]
    tip:SetOwner(button, "ANCHOR_NONE")
    tip:SetScale(button:GetEffectiveScale() / UIParent:GetEffectiveScale())
    tip:ClearLines()
    Addon:SetStandaloneTooltipTitle(tip,
        ForeverRosettaStoneDB:GetItemName(data.id, Addon:GetTargetLocale()) or nameLine.leftText,
        GetColor(nameLine.leftColor))

    for _, line in ipairs(data.lines) do
        if Addon.preferences.tooltipCoverage ~= "name" and line.type == Enum.TooltipDataLineType.ItemBinding then
            tip:AddLine(TranslateBinding(line.leftText), GetColor(line.leftColor))
        elseif Addon.preferences.tooltipCoverage ~= "name" and line.type == Enum.TooltipDataLineType.EquipSlot then
            local left = line.leftText

            if englishLabels and equipLoc and _G[equipLoc] == left then
                left = Addon.itemTooltipLabels[equipLoc] or left
            end

            if line.rightText and line.rightText ~= "" then
                local right = subclasses and subclasses[subclassID] or line.rightText
                local red, green, blue = GetColor(line.leftColor)
                tip:AddDoubleLine(left, right, red, green, blue, GetColor(line.rightColor))
            else
                tip:AddLine(left, GetColor(line.leftColor))
            end
        end
    end

    if tip.CompareHeader then
        tip.CompareHeader:SetShown(header ~= nil)

        if header then
            tip.CompareHeader.Label:SetText(header)
            tip.CompareHeader:SetWidth(tip.CompareHeader.Label:GetWidth() + 30)
        end
    end

    tip:Show()
    return true
end

function Addon:CreateRewardTooltips()
    self.rewardTooltips = {}

    for index = 1, 3 do
        local template = index == 1 and "GameTooltipTemplate" or "ShoppingTooltipTemplate"
        local tip = self:NewFrame("GameTooltip", "ForeverRosettaStoneRewardTooltip" .. index, UIParent, template)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(false)
        tip:EnableMouse(false)
        tip:Hide()
        self.rewardTooltips[index] = tip
    end

    self.rewardSpellSource = self:CreateCompanionTooltip("ForeverRosettaStoneRewardSpellSource")
    self.rewardSpellSource:SetAlpha(0)
    self.rewardSpellSource:SetClampedToScreen(false)
    if self.rewardSpellSource.EnableMouseMotion then self.rewardSpellSource:EnableMouseMotion(false) end
    self:HookScript(self.panel, "OnHide", function() self:HideRewardTooltips() end)
end

function Addon:HideRewardTooltips(button)
    if button and self.rewardTooltipOwner ~= button then return end

    self.rewardTooltipOwner, self.rewardTooltipSpell = nil, nil
    for _, tip in ipairs(self.rewardTooltips) do tip:Hide() end
    self.rewardSpellSource:Hide()
end

-- Spell rewards render through the same translated spell tooltip as the rest of the addon,
-- measured on a transparent native tooltip like the settings preview.
local function FillSpellTooltip(self, tip, button, spellID)
    local name = self:IsReadableEntityID(spellID) and ForeverRosettaStoneDB:GetSpellName(spellID, self:GetTargetLocale())
    if not name then return false end
    local native = self.rewardSpellSource
    if self.rewardTooltipOwner == button and self.rewardTooltipSpell == spellID and tip:IsShown() then return true end
    native:SetOwner(button, "ANCHOR_NONE")
    native:SetSpellByID(spellID)
    -- Showing a tooltip restores its alpha; keep the source invisible and off-screen so it never
    -- appears beside the translation or takes the mouse from the reward button.
    native:SetAlpha(0)
    native:ClearAllPoints()
    native:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -100, -100)
    local data = native:GetPrimaryTooltipData()
    if not data then native:Hide(); return false end
    -- The transparent source stays shown: the translated tooltip it owns hides with it.
    self:FillNameTooltip({ source = native, tip = tip, kind = "spell", id = spellID, name = name, data = data })
    tip:SetAlpha(1)
    self.rewardTooltipSpell = spellID
    tip:SetScale(button:GetEffectiveScale() / UIParent:GetEffectiveScale())
    if tip.CompareHeader then tip.CompareHeader:Hide() end
    return true
end

local function IsRewardPanel(self, frame)
    return frame and (frame == self.panel or frame.hasRewardTooltips == true) or false
end

function Addon:UpdateRewardTooltips(button)
    if not self:IsFeatureEnabled("rewardComparison")
        or (GameMenuFrame and GameMenuFrame:IsShown())
        or (self.errorDialog and self.errorDialog.frame:IsShown() and not self:IsDebugPicking()) then
        self:HideRewardTooltips()
        return
    end

    if not button then
        for _, owner in ipairs(GetMouseFoci()) do
            button = FindRewardButton(owner)

            if button then break end
        end

        -- The controller's selected reward counts as hovered in any panel that owns reward tooltips.
        local current = not button and InputUtil.IsGamepadUIEnabled() and not SmartNavigation:IsCursorHidden()
            and SmartNavigation:GetCurrentButton()
        local candidate = current and FindRewardButton(current)
        if candidate and IsRewardPanel(self, candidate.rewardPanel or self.panel) then button = candidate end
    end

    if button and button:IsForbidden() then self:HideRewardTooltips(); return end
    local source = button and button.rewardSource
    local panel = button and (button.rewardPanel or self.panel)
    local left, top = button and button:GetLeft(), button and button:GetTop()
    local spellID = source and source.rewardSpellID

    if not source or (source.objectType ~= "item" and not spellID) or not panel:IsVisible()
        or not button:IsVisible() or not left or not top then
        self:HideRewardTooltips()
        return
    end

    local data
    if spellID then
        if not FillSpellTooltip(self, self.rewardTooltips[1], button, spellID) then
            self:HideRewardTooltips()
            return
        end
    else
        -- NPC quest windows show quest-giver rewards; the journal shows quest log rewards.
        if button.rewardQuestLog == false then data = C_TooltipInfo.GetQuestItem(source.type, source:GetID())
        else data = C_TooltipInfo.GetQuestLogItem(source.type, source:GetID(), self.current.questID, false) end
        if self:IsDebugPicking() and data and self:IsReadableEntityID(data.id) then
            self:RecordDebugSurface(button, "item", data.id, "rewardComparison", data,
                ForeverRosettaStoneDB:GetItemDetails(data.id, self:GetTargetLocale()))
        end

        if not FillTooltip(self.rewardTooltips[1], button, data) then
            self:HideRewardTooltips()
            return
        end
        self.rewardTooltipSpell = nil
        self.rewardSpellSource:Hide()
    end
    self.rewardTooltipOwner = button

    local item = data and GetComparisonItem(data)
    local comparison = item and C_TooltipComparison.GetItemComparisonInfo(item)
    local paired = comparison and (comparison.method == Enum.TooltipComparisonMethod.WithBagMainHandItem
        or comparison.method == Enum.TooltipComparisonMethod.WithBagOffHandItem)
    local count = 1

    for index = 1, 2 do
        local equipped = comparison and (index == 1 and comparison.item or comparison.additionalItems[1])
        local header = index == 2 and paired and IF_EQUIPPED_TOGETHER or EQUIPPED

        if equipped and FillTooltip(self.rewardTooltips[count + 1], button, GetComparisonData(equipped), header) then
            count = count + 1
        end
    end

    for index = count + 1, #self.rewardTooltips do self.rewardTooltips[index]:Hide() end

    local scale = button:GetEffectiveScale()
    local width, height = 0, 0

    for index = 1, count do
        local tip = self.rewardTooltips[index]
        width = width + tip:GetWidth() * scale
            + (index > 1 and self.TOOLTIP_GAP * UIParent:GetEffectiveScale() or 0)
        height = math.max(height, (tip:GetHeight() + 22) * scale)
        tip:ClearAllPoints()

        if index > 1 then
            tip:SetPoint("TOPLEFT", self.rewardTooltips[index - 1], "TOPRIGHT",
                self:GetTooltipGap(tip), 0)
        end
    end

    local screenScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
    -- Same anchor as the native reward buttons (ANCHOR_RIGHT): the tooltip's bottom-left sits on
    -- the button's top-right corner, kept on screen with comparisons beside it.
    local x = math.max(12, math.min((left + button:GetWidth()) * scale, screenWidth - width - 12))
    local y = math.max(12, math.min(top * scale, screenHeight - height - 12))
    self.rewardTooltips[1]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / screenScale, y / screenScale)
end
