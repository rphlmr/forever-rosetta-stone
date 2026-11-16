local _, Addon = ...

local function LayoutCombatComparisonTranslations(originals, kind)
    local screenScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
    local gap = Addon.TOOLTIP_GAP * screenScale
    local width, height, topMargin, nativeTop, nativeBottom = 0, 0, 0, 0, screenHeight
    local translated = {}
    for _, original in ipairs(originals) do
        local spec, rect = original.spec, original.rect
        nativeTop, nativeBottom = math.max(nativeTop, rect.top), math.min(nativeBottom, rect.bottom)
        if spec.name and spec.kind == kind then
            Addon:FillNameTooltip(spec)
            local scale = spec.tip:GetEffectiveScale()
            if #translated > 0 then width = width + gap end
            translated[#translated + 1] = { spec = spec, rect = rect, offset = width, scale = scale }
            width = width + spec.tip:GetWidth() * scale
            height = math.max(height, spec.tip:GetHeight() * scale)
            topMargin = math.max(topMargin, select(3, spec.tip:GetClampRectInsets()) * scale)
        end
    end
    if #translated == 0 or width > screenWidth - 2 * gap then return false end
    local top = nativeTop + gap + height
    if top > screenHeight - math.max(gap, topMargin) then top = nativeBottom - gap end
    if top - height < gap then return false end
    local left = math.max(gap, math.min(originals[1].rect.left, screenWidth - width - gap))
    for _, entry in ipairs(translated) do
        local tip, rect, scale = entry.spec.tip, entry.rect, entry.scale
        tip:ClearAllPoints()
        tip:SetPoint("TOPLEFT", entry.spec.source, "TOPLEFT",
            (left + entry.offset - rect.left) / scale, (top - rect.top) / scale)
        tip:Show()
    end
    return true
end

local function LayoutComparisonTooltipRow(group, originals, kind)
    local self = Addon
    local screenScale = UIParent:GetEffectiveScale()
    local screenWidth, screenHeight = UIParent:GetWidth() * screenScale, UIParent:GetHeight() * screenScale
    local gap, height, topMargin, count = self.TOOLTIP_GAP * screenScale, 0, 0, 0
    table.sort(originals, function(a, b) return a.rect.left < b.rect.left end)
    local nativeLeft = originals[1].rect.left
    local leftWidth, rightWidth, nativeWidth = 0, 0, 0
    for index, original in ipairs(originals) do
        local spec, rect = original.spec, original.rect
        if index > 1 then nativeWidth = nativeWidth + math.max(0, rect.left - originals[index - 1].rect.right) end
        original.offset = nativeWidth
        nativeWidth = nativeWidth + rect.right - rect.left
        height = math.max(height, rect.top - rect.bottom)
        original.side = index <= math.floor(#originals / 2) and "left" or "right"
        original.translated = spec.name and spec.kind == kind
        if original.translated then
            Addon:FillNameTooltip(spec)
            local scale = spec.tip:GetEffectiveScale()
            local width = gap + spec.tip:GetWidth() * scale
            if original.side == "left" then leftWidth = leftWidth + width
            else rightWidth = rightWidth + width end
            height = math.max(height, spec.tip:GetHeight() * scale)
            topMargin = math.max(topMargin, select(3, spec.tip:GetClampRectInsets()) * scale)
            count = count + 1
        end
    end
    local width = leftWidth + nativeWidth + rightWidth
    if count == 0 or width > screenWidth - 2 * gap or height > screenHeight - topMargin - gap then return false end
    local component = Addon:GetTooltipComponent("item")
    local context = component.GetPlacementContext(group[1])
    local side = Addon.itemComparisonPlacements[context][Addon:GetTooltipInputMode()].GetSide(group[1])
    -- The complete row inherits the native outer edge, so it grows away from the hovered item.
    local desiredLeft = side == "left" and nativeLeft + nativeWidth - width or nativeLeft
    local left = math.max(gap, math.min(desiredLeft, screenWidth - width - gap))
    local top = math.max(height + gap, math.min(originals[1].rect.top, screenHeight - math.max(gap, topMargin)))
    if InCombatLockdown() then
        for _, original in ipairs(originals) do
            if original.spec.source:IsProtected() then
                left = original.liveRect.left - leftWidth - original.offset
                top = original.liveRect.top
                break
            end
        end
    end
    if left < gap or left + width > screenWidth - gap or top < height + gap
        or top > screenHeight - math.max(gap, topMargin) then return false end
    local positions = {}
    for _, original in ipairs(originals) do
        local source, rect = original.spec.source, original.liveRect
        local targetLeft = left + leftWidth + original.offset
        if math.abs(rect.left - targetLeft) > 0.01 or math.abs(rect.top - top) > 0.01 then
            if InCombatLockdown() and source:IsProtected() then return false end
            positions[#positions + 1] = { source = source, left = targetLeft, top = top }
        end
    end
    if #positions > 0 and not self:TransitionTooltipSources(group, "sources.place", positions) then return false end
    local leftTip, rightTip = originals[1].spec.source, originals[#originals].spec.source
    for index = #originals, 1, -1 do
        local original = originals[index]
        local spec = original.spec
        if original.translated and original.side == "left" then
            self:AnchorCompanionTooltip(spec.tip, leftTip, "left")
            spec.tip:Show()
            leftTip = spec.tip
        end
    end
    for _, original in ipairs(originals) do
        local spec = original.spec
        if original.translated and original.side == "right" then
            self:AnchorCompanionTooltip(spec.tip, rightTip, "right")
            spec.tip:Show()
            rightTip = spec.tip
        elseif not original.translated and spec.tip then spec.tip:Hide() end
    end
    return true
end

local rules = Addon.TooltipSideRules
Addon.itemComparisonPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "itemComparison",
    contexts = { default = {}, bag = {}, equipment = {}, actionBar = {}, chatLink = {} },
    mouse = { sideRules = { rules.fixed, rules.owner, rules.anchor, rules.cursor, rules.screen } },
    gamepad = { sideRules = { rules.fixed, rules.owner, rules.anchor, rules.cursor, rules.screen } },
})

local function LayoutGroup(group, originals, restoreBlocked)
        for _, original in ipairs(originals) do
            if original.spec.tip then Addon:TransitionTooltipSources(original.spec.tip, "sources.restore") end
            local source = original.spec.source
            original.liveRect = Addon:GetTooltipRect(source)
            local anchor = Addon:GetTooltipAnchorContext(source).native
            local width = original.liveRect.right - original.liveRect.left
            local height = original.liveRect.top - original.liveRect.bottom
            original.rect = { left = anchor.left, right = anchor.left + width, top = anchor.top, bottom = anchor.top - height }
        end
        local shown = not (restoreBlocked and not group.sourcePlacements)
            and LayoutComparisonTooltipRow(group, originals, "item")
        if not shown and InCombatLockdown() then
            for _, original in ipairs(originals) do original.rect = original.liveRect end
            shown = LayoutCombatComparisonTranslations(originals, "item")
        end
        if not shown then
            Addon:TransitionTooltipSources(group, "sources.restore")
            for _, original in ipairs(originals) do
                if original.spec.tip then original.spec.tip:Hide() end
            end
        end
        return shown
end
for _, profiles in pairs(Addon.itemComparisonPlacements) do
    profiles.mouse.LayoutGroup, profiles.gamepad.LayoutGroup = LayoutGroup, LayoutGroup
end

