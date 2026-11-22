local _, Addon = ...

local hooked = {}
local registered = false
local components, componentByKind = {}, {}

function Addon:RegisterNameTooltipComponent(definition)
    local component = self:CreateTooltipComponent(definition)
    assert(not componentByKind[component.kind], "Duplicate tooltip component: " .. component.kind)
    components[#components + 1] = component
    componentByKind[component.kind] = component
end

function Addon:GetTooltipComponent(kind)
    return componentByKind[kind]
end

function Addon:GetTooltipComponents()
    local result = {}
    for index, component in ipairs(components) do result[index] = component end
    return result
end

function Addon:UpdateTooltipComponents()
    -- Resolve the NPC reader first so its row tooltips never show on the opening frame.
    local interaction = componentByKind.questInteraction
    if interaction then interaction.Update() end
    for _, component in ipairs(components) do
        if component ~= interaction then component.Update() end
    end
end

function Addon:GetTooltipPlacementPolicy(source)
    local spec = self.nameTooltips and self.nameTooltips[source]
    local component = spec and componentByKind[spec.kind]
    return component and component.SelectPlacementPolicy(source)
end

function Addon:HideNameTooltips()
    if not self.nameTooltips then return end
    for _, component in ipairs(components) do component.Hide() end

    local groups = {}
    for _, spec in pairs(self.nameTooltips) do
        if not groups[spec.group] then
            groups[spec.group] = true
            self:SendTooltipEvent(spec.group, { type = "reset" })
        end
    end
end

function Addon:FillNameTooltip(spec, presentation)
    if not spec then return end
    local source = spec.source
    local component = componentByKind[spec.kind]
    if not source or not component or not spec.name then
        if spec.tip then spec.tip:Hide() end
        return
    end
    if not spec.tip then
        local sourceName = source:GetName()
        spec.tip = Addon:CreateCompanionTooltip(sourceName and "ForeverRosettaStoneName" .. sourceName or nil, nil,
            source.CompareHeader and "ShoppingTooltipTemplate" or "GameTooltipTemplate")
        spec.tip:SetClampedToScreen(true)
    end
    local tip = spec.tip
    tip:SetMinimumWidth(0)
    if not tip:IsOwned(source) then tip:SetOwner(source, "ANCHOR_NONE") end
    tip:SetScale(source:GetEffectiveScale() / UIParent:GetEffectiveScale())
    Addon:AnchorCompanionTooltip(tip, source)
    tip:ClearLines()
    Addon:CopyCompanionTooltipStyle(tip, source)
    local red, green, blue = 1, 1, 1
    local title = source.TextLeft1 or source.Name
    if title then red, green, blue = title:GetTextColor() end
    if spec.color then red, green, blue = spec.color:GetRGB() end
    if self:GetTooltipCoverage(spec.kind, spec.data) == "name" then
        Addon:SetCompanionTooltipTitle(tip, spec.name, red, green, blue)
    elseif spec.data and component.supportsFullText then
        Addon:FillEnglishTooltip(spec)
    else
        component.FillTooltip(tip, source, spec.name, red, green, blue, spec)
    end
    component.AfterFill(spec, presentation or "separate")
    if presentation == "replacement" then
        Addon:AppendTooltipExtraRows(spec)
    end
    tip:Show()
    Addon:RecordDebugRenderedTooltip(spec)
end

local PREVIEW_ITEM_ID = 117

function Addon:RenderTooltipPreview(data)
    local preview = self.settingsPanel and self.settingsPanel.TooltipPreview
    if not preview or not preview:IsVisible() or preview:GetWidth() <= 24 then return end
    local source, tip = preview.native, preview.translated
    local name = ForeverRosettaStoneDB:GetItemName(PREVIEW_ITEM_ID, self:GetTargetLocale())
    tip:Hide()
    if not name then return end
    local spec = { source = source, tip = tip, kind = "item", id = PREVIEW_ITEM_ID, name = name, data = data }
    local requested = self:GetTooltipPresentation(source)
    local separate = requested == "separate"
    local presentation = separate and requested or self:ResolveStackedPresentation(source, tip, requested)
    self:FillNameTooltip(spec, presentation)
    if not separate then
        self:FillStackedTooltip(source, tip, "preview:" .. self:GetTargetLocale()
            .. ":" .. self:GetTooltipCoverage(spec.kind, spec.data), presentation)
    end
    local side = self.preferences.npcTooltipPosition
    local horizontal = side == "left" or side == "right"
    local totalWidth = source:GetWidth()
    local totalHeight = source:GetHeight()
    if presentation == "replacement" and tip:IsShown() then
        totalWidth, totalHeight = tip:GetSize()
    end
    local sourceX, sourceY = 0, 0
    if separate then
        if horizontal then
            totalWidth = totalWidth + tip:GetWidth() + 8
            totalHeight = math.max(totalHeight, tip:GetHeight())
            if side == "left" then sourceX = tip:GetWidth() + 8 end
        else
            totalWidth = math.max(totalWidth, tip:GetWidth())
            totalHeight = totalHeight + tip:GetHeight() + 8
            if side == "top" then sourceY = tip:GetHeight() + 8 end
        end
    end
    local scale = math.min(1, (preview:GetWidth() - 24) / totalWidth,
        (preview:GetHeight() - 24) / totalHeight)
    if scale <= 0 then return end
    source:SetScale(scale)
    tip:SetScale(scale)
    source:ClearAllPoints()
    source:SetPoint("TOPLEFT", preview, "TOPLEFT", 12 / scale + sourceX, -12 / scale - sourceY)
    if separate then
        tip:ClearAllPoints()
        if side == "left" then
            tip:SetPoint("TOPRIGHT", source, "TOPLEFT", -8, 0)
        elseif side == "top" then
            tip:SetPoint("BOTTOMLEFT", source, "TOPLEFT", 0, 8)
        elseif side == "bottom" then
            tip:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -8)
        else
            tip:SetPoint("TOPLEFT", source, "TOPRIGHT", 8, 0)
        end
        tip:Show()
    end
end

-- The preview tooltip does not refresh itself when item data arrives, so wait for the item first.
local function WaitForPreviewItem(self, preview)
    if not (C_Item and C_Item.IsItemDataCachedByID) or C_Item.IsItemDataCachedByID(PREVIEW_ITEM_ID) then
        return false
    end
    preview.native:Hide()
    preview.translated:Hide()
    if not preview.waitingForItem and Item and Item.CreateFromItemID then
        preview.waitingForItem = true
        Item:CreateFromItemID(PREVIEW_ITEM_ID):ContinueOnItemLoad(function()
            preview.waitingForItem = nil
            self:Run("refresh tooltip preview", function() self:RefreshTooltipPreview() end)
        end)
    end
    return true
end

-- Settings rows are shown before the list finishes its layout; refresh again once it settles.
function Addon:QueueTooltipPreviewRefresh()
    local preview = self.settingsPanel and self.settingsPanel.TooltipPreview
    if not preview or preview.refreshQueued then return end
    preview.refreshQueued = true
    C_Timer.After(0, function()
        preview.refreshQueued = nil
        self:Run("refresh tooltip preview", function() self:RefreshTooltipPreview() end)
    end)
end

function Addon:RefreshTooltipPreview()
    local preview = self.settingsPanel and self.settingsPanel.TooltipPreview
    if not preview then return end
    if not preview:IsVisible() or preview:GetWidth() <= 24 then
        preview.native:Hide()
        preview.translated:Hide()
        return
    end
    if WaitForPreviewItem(self, preview) then return end
    self:ClearStackedTooltip(preview.native)
    preview.native:SetScale(1)
    preview.native:SetOwner(preview, "ANCHOR_NONE")
    preview.native:SetItemByID(PREVIEW_ITEM_ID)
    self:RenderTooltipPreview(preview.native:GetPrimaryTooltipData())
end


local function LayoutReplacementComparisons(self, group)
    local primary = group[1]
    local primarySlot = self:GetTooltipRect(primary)
    local primaryState = self.stackedTooltips[primary]
    local anchor = primaryState and primaryState.replacement and primaryState.owner or primary
    local bounds = self:GetTooltipRect(anchor)
    if not primarySlot or not bounds then return end
    local occupied, replacements = { bounds }, {}
    for index = 2, #group do
        local source = group[index]
        if not source:IsForbidden() and source:IsVisible() then
            local rect = self:GetTooltipRect(source)
            local saved = self.stackedTooltips[source]
            if rect and saved and saved.replacement then
                replacements[#replacements + 1] = { source = source, saved = saved, left = rect.left }
            elseif rect then
                occupied[#occupied + 1] = rect
            end
        end
    end
    for _, entry in ipairs(replacements) do
        local side = entry.left < primarySlot.left and "left" or "right"
        local rect = self:PlaceCompanionTooltip(entry.saved.owner, anchor, occupied, false, nil,
            { GetSide = function() return side end, allowSideFallback = true, allowVerticalFallback = true })
        if rect then occupied[#occupied + 1] = rect
        else self:ClearStackedTooltip(entry.source) end
    end
end

local function StackedKey(self, spec, coverage)
    return table.concat({ spec.kind, spec.id, self:GetTargetLocale(), coverage }, ":")
end

local function LayoutNameTooltipGroup(self, group)
    local restoreBlocked = false
    local requested = self:GetTooltipPresentation(group[1])
    local nativeSlot = requested ~= "separate"
    if nativeSlot then
        self:TransitionTooltipSources(group, "sources.restore")
        restoreBlocked = group.sourcePlacements ~= nil
        for _, source in ipairs(group) do
            local spec = self.nameTooltips[source]
            if spec.tip then
                self:TransitionTooltipSources(spec.tip, "sources.restore")
                restoreBlocked = restoreBlocked or spec.tip.sourcePlacements ~= nil
            end
        end
    end
    local primary = self.nameTooltips[group[1]]
    local component = componentByKind[primary.kind]

    if nativeSlot and component and component.supportsEmbedded and group[1].ClearLines then
        for _, source in ipairs(group) do
            local spec = self.nameTooltips[source]
            if not self:IsTooltipBlocked() and not source:IsForbidden() and source:IsVisible()
                and spec.name and self:IsFeatureEnabled(self:GetTooltipCategory(spec.kind, spec.data) .. "Tooltip") then
                local stacked = self.stackedTooltips and self.stackedTooltips[source]
                local coverage = self:GetTooltipCoverage(spec.kind, spec.data)
                local key = StackedKey(self, spec, coverage)
                local presentation = self:ResolveStackedPresentation(source, spec.tip, requested)
                local numLines = source:NumLines()
                if stacked and stacked.owner == spec.tip and stacked.key == key
                    and stacked.presentation == "below" and presentation == "below"
                    and spec.kind == "item" and numLines > stacked.numLines
                    and (coverage == "name" or not self:HasNewTooltipComparisonRows(source, stacked.numLines + 1)) then
                    -- Item details come from native data. Only a live comparison can
                    -- add translatable rows after this block has already been built.
                    stacked.numLines = numLines
                end
                if not stacked or stacked.owner ~= spec.tip or stacked.key ~= key
                    or numLines ~= stacked.numLines or stacked.presentation ~= presentation
                    or (stacked.contentDirty and not (spec.tip.hiddenOriginal and spec.tip.hiddenOriginal.fading)) then
                    if stacked then self:ClearStackedTooltip(source) end
                    self:FillNameTooltip(spec, presentation)
                    self:FillStackedTooltip(source, spec.tip, key, presentation)
                else
                    self:RefreshStackedTooltip(source, stacked)
                end
            else
                self:ClearStackedTooltip(source)
                if spec.tip then spec.tip:Hide() end
            end
        end
        if requested == "replacement" and primary.kind == "item" and #group > 1 and self.stackedTooltips then
            LayoutReplacementComparisons(self, group)
        end
        return
    end

    if (restoreBlocked and not InCombatLockdown())
        or self:IsTooltipBlocked() or group[1]:IsForbidden() or not group[1]:IsVisible() or not primary.kind
        or not self:IsFeatureEnabled(self:GetTooltipCategory(primary.kind, primary.data) .. "Tooltip") then
        self:TransitionTooltipSources(group, "sources.restore")
        for _, source in ipairs(group) do
            local spec = self.nameTooltips[source]
            if spec.tip then
                self:TransitionTooltipSources(spec.tip, "sources.restore")
                spec.tip:Hide()
            end
        end
        return
    end

    local started = self:BeginBenchmarkSample()
    local occupied, originals = {}, {}

    for _, source in ipairs(group) do
        local spec = self.nameTooltips[source]

        local rect = not source:IsForbidden() and source:IsVisible() and self:GetTooltipRect(source)
        if rect then
            originals[#originals + 1] = { spec = spec, rect = rect }
            occupied[#occupied + 1] = rect
        elseif spec.tip then
            self:TransitionTooltipSources(spec.tip, "sources.restore")
            spec.tip:Hide()
        end
    end

    if #originals == 0 then
        self:TransitionTooltipSources(group, "sources.restore")
        self:EndBenchmarkSample(primary.kind .. ".layout", primary.id, started, false, primary.source)
        return
    end

    local policy = self:GetTooltipPlacementPolicy(primary.source)
    local shown = policy and policy.LayoutGroup and policy.LayoutGroup(group, originals, restoreBlocked)
    if shown ~= nil then
        self:EndBenchmarkSample(primary.kind .. ".layout", primary.id, started, shown, primary.source)
        return
    end

    if restoreBlocked then
        for _, original in ipairs(originals) do
            if original.spec.tip then original.spec.tip:Hide() end
        end
        return
    end

    if group.sourcePlacements then
        self:TransitionTooltipSources(group, "sources.restore")
        for _, original in ipairs(originals) do original.rect = self:GetTooltipRect(original.spec.source) end
    end

    local count = 0

    for _, original in ipairs(originals) do
        local spec, shown = original.spec, false

        if spec.name and spec.kind == primary.kind then
            self:FillNameTooltip(spec)

            local rect = self:PlaceCompanionTooltip(spec.tip, spec.source, occupied)
            if rect then
                shown = true
                occupied[#occupied + 1] = rect
                count = count + 1
            end
        end

        if not shown and spec.tip then
            self:TransitionTooltipSources(spec.tip, "sources.restore")
            spec.tip:Hide()
        end
    end

    self:EndBenchmarkSample(primary.kind .. ".layout", primary.id, started, count > 0, primary.source)
end

local function GetGroupVisibility(group)
    local visible = {}
    for _, source in ipairs(group) do visible[source] = not source:IsForbidden() and source:IsVisible() end
    return visible
end

local function ClearSource(self, source)
    local spec = self.nameTooltips[source]
    self:ClearStackedTooltip(source, true)
    spec.kind, spec.id, spec.name, spec.data = nil, nil, nil, nil
end

local function ResolveData(self, source, data, nativeShowPending)
    if not canaccessallvalues(data) or type(data) ~= "table" then
        if self.RecordAuraResolution then self:RecordAuraResolution("tooltip-payload-unavailable") end
        ClearSource(self, source)
        local spec = self.nameTooltips[source]
        if spec.tip then spec.tip:Hide() end
        return
    end
    local info = source.GetProcessingTooltipInfo and source:GetProcessingTooltipInfo()
    self.nameTooltips[source].getterName = canaccessallvalues(info) and type(info) == "table" and info.getterName or nil
    for _, component in ipairs(components) do
        local id, color
        id, color = component.ResolveData(source, data)
        if id then
            self.nameTooltips[source].data = data
            if not color then
                for _, line in ipairs(data.lines or {}) do
                    if line.type == Enum.TooltipDataLineType.ItemName
                        or line.type == Enum.TooltipDataLineType.SpellName then color = line.leftColor; break end
                end
            end
            self:UpdateNameTooltip(source, component.kind, id, color, true)
            local spec = self.nameTooltips[source]
            if not spec.name and spec.tip then spec.tip:Hide() end
            -- Finish the primary item translation before Blizzard and later post-calls show it.
            -- Comparison tooltips still render after the client appends their stat summary.
            if nativeShowPending and spec.name and spec.kind == "item" and source == spec.group[1]
                and canaccessallvalues(info) and type(info) == "table"
                and canaccessallvalues(info.tooltipData, info.append) and info.tooltipData == data and not info.append
                and self:GetTooltipPresentation(source) == "below" then
                self:FillNameTooltip(spec, "below")
                local coverage = self:GetTooltipCoverage(spec.kind, data)
                self:FillStackedTooltip(source, spec.tip, StackedKey(self, spec, coverage), "below", true)
            end
            return
        end
    end
    ClearSource(self, source)
    local spec = self.nameTooltips[source]
    if spec.tip then spec.tip:Hide() end
end

function Addon:SendTooltipEvent(group, event)
    if not group or not group[1] then return end
    if self.tooltipRendering and event.type ~= "reset" then return end
    local visible = GetGroupVisibility(group)
    group.lifecycle = group.lifecycle or self:CreateTooltipLifecycle(group[1], visible)
    event.visible = visible
    local previous = group.lifecycle.value
    local nextState, effects = self:TransitionTooltipLifecycle(group.lifecycle, event)
    group.lifecycle = nextState
    if self.TraceTooltip then
        self:TraceTooltip(event.type, event.source or group[1], event.data, previous .. " -> " .. nextState.value)
    end
    for _, effect in ipairs(effects) do
        if effect.type == "clear.source" then
            ClearSource(self, effect.source)
            if event.type == "native.hidden" then self.nameTooltips[effect.source].sharedTextCache = nil end
        elseif effect.type == "resolve.data" then
            ResolveData(self, effect.source, effect.data, event.nativeShowPending)
        elseif effect.type == "resolve.owner" then
            for _, component in ipairs(components) do
                local id = component.ResolveOwner(effect.source)
                if id then
                    self.nameTooltips[effect.source].data = effect.source:GetPrimaryTooltipData()
                    self:UpdateNameTooltip(effect.source, component.kind, id, nil, true)
                    break
                end
            end
        elseif effect.type == "schedule" then
            local generation = self.generation
            C_Timer.After(0, function()
                if generation ~= self.generation or self.lifecycle ~= "ready" then return end
                self:Run("tooltip layout tick", self.SendTooltipEvent, self, group,
                    { type = "layout.tick", ticket = effect.ticket })
            end)
        elseif effect.type == "render" then
            self:Run("layout tooltip group", LayoutNameTooltipGroup, self, group)
            self:SendTooltipEvent(group, { type = "layout.complete" })
            if self.TraceTooltip then self:TraceTooltip("layout", group[1]) end
        elseif effect.type == "cleanup" then
            self:TransitionTooltipSources(group, "sources.restore")
            for _, source in ipairs(group) do
                local spec = self.nameTooltips[source]
                self:ClearStackedTooltip(source, effect.nativeCleared)
                if spec.tip then
                    self:TransitionTooltipSources(spec.tip, "sources.restore")
                    spec.tip:Hide()
                end
                if effect.clearIdentity then
                    spec.kind, spec.id, spec.name, spec.data, spec.sharedTextCache = nil, nil, nil, nil, nil
                end
            end
            self:SendTooltipEvent(group, { type = "cleanup.complete" })
        end
    end
end

function Addon:LayoutNameTooltipGroup(group)
    self:SendTooltipEvent(group, { type = "layout.now" })
end

function Addon:UpdateNameTooltip(source, kind, id, color, deferLayout)
    if source:IsForbidden() then return end
    local spec = self.nameTooltips[source]
    if spec.kind ~= kind or spec.id ~= id or self:GetTooltipPresentation(source) == "separate" then
        self:ClearStackedTooltip(source)
    end
    spec.kind, spec.id, spec.color = kind, id, color
    local featureID = self:GetTooltipCategory(kind, spec.data) .. "Tooltip"
    if self:IsDebugPicking() then
        local nativeData = spec.data
        if kind == "characterStat" or kind == "pet" or kind == "minimapLocation" then nativeData = nil end
        self:RecordDebugSurface(source, kind, id, componentByKind[kind].GetPlacementContext(source), nativeData,
            { name = componentByKind[kind].GetName(id, self:GetTargetLocale(), source, spec.data),
                enabled = self:IsFeatureEnabled(featureID) })
    end

    if self:IsTooltipBlocked() or not self:IsFeatureEnabled(featureID) then
        spec.name = nil
        if spec.tip then spec.tip:Hide() end
        self:LayoutNameTooltipGroup(spec.group)
        return
    end

    local started = self:BeginBenchmarkSample()
    local lookupStarted = self:BeginBenchmarkSample()
    local name = componentByKind[kind].GetName(id, self:GetTargetLocale(), source, spec.data)
    self:EndBenchmarkSample(kind .. ".lookup", id, lookupStarted, name ~= nil, source)
    spec.name = name
    if self.TraceTooltip then self:TraceTooltip("lookup", source, spec.data) end

    if not deferLayout then self:LayoutNameTooltipGroup(spec.group) end
    self:EndBenchmarkSample(kind .. ".tooltip", id, started, name ~= nil, source)
end

function Addon:RefreshNameTooltips()
    if not self.nameTooltips then return end

    for source, spec in pairs(self.nameTooltips) do
        if not source:IsForbidden() then
            -- An aura first shown with restricted identity has no cached kind/ID to refresh.
            -- Resolve current native data again when it becomes readable after combat.
            local data = source:IsVisible() and source.GetPrimaryTooltipData and source:GetPrimaryTooltipData()
            local readable = canaccessallvalues(data) and type(data) == "table"
            local aura = readable and canaccessallvalues(data.type) and Enum.TooltipDataType.UnitAura
                and data.type == Enum.TooltipDataType.UnitAura
            if readable and (not spec.kind or not spec.id or aura) then
                self:SendTooltipEvent(spec.group, { type = "native.data", source = source, data = data })
                -- The source is already visible, so no native Show will finish this refresh.
                self:SendTooltipEvent(spec.group, { type = "native.shown", source = source })
            elseif spec.kind and spec.id then
                self:ClearStackedTooltip(source)
                self:UpdateNameTooltip(source, spec.kind, spec.id, spec.color)
            end
        end
    end
end

function Addon:CreateNameTooltips()
    self:HideNameTooltips()
    self.nameTooltips = {}

    for _, names in ipairs({
        { "GameTooltip", "ShoppingTooltip1", "ShoppingTooltip2" },
        { "ItemRefTooltip", "ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2" },
        { "BattlePetTooltip" },
        -- Aura tooltips the client shows on its own when the player gains a buff or debuff.
        { "BuffFrameTooltip" },
    }) do
        local group = {}

        for _, name in ipairs(names) do
            local source = _G[name]

            if source and not source:IsForbidden() then
                group[#group + 1] = source
                self.nameTooltips[source] = { source = source, group = group }

                if not hooked[source] then
                    hooked[source] = true
                    local function Send(event)
                        if Addon.lifecycle ~= "ready" or source:IsForbidden() then return end
                        local spec = Addon.nameTooltips and Addon.nameTooltips[source]
                        if not spec then return end
                        -- Comparison Show runs before the client appends the stat summary.
                        local immediate = Addon:GetTooltipPresentation(source) ~= "separate" and source == spec.group[1]
                        Addon:Run("tooltip lifecycle", Addon.SendTooltipEvent, Addon, spec.group,
                            { type = event, source = source, immediate = immediate })
                    end
                    source:HookScript("OnHide", function()
                        Addon:UpdateReplacementFade(source, "hide")
                        Send("native.hidden")
                    end)
                    if source.FadeOut then
                        hooksecurefunc(source, "FadeOut", function()
                            if not source:IsForbidden() then Addon:UpdateReplacementFade(source, "start") end
                        end)
                        source:HookScript("OnUpdate", function()
                            if Addon.preferences.translationOnly and not source:IsForbidden() then
                                Addon:UpdateReplacementFade(source)
                            end
                        end)
                    end
                    if source.ClearLines then
                        source:HookScript("OnTooltipCleared", function() Send("native.clear") end)
                        hooksecurefunc(source, "ClearLines", function() Send("native.clear") end)
                        hooksecurefunc(source, "SetText", function()
                            Send("native.clear")
                            if source:IsVisible() then Send("native.shown") end
                        end)
                    end
                    hooksecurefunc(source, "Show", function()
                        if Addon.TraceTooltip then Addon:TraceTooltip("show", source) end
                        if not source:IsForbidden() and source:IsVisible() then
                            if not Addon.tooltipRendering then Addon:UpdateReplacementFade(source, "show") end
                            Send("native.shown")
                            if Addon.preferences.translationOnly and not Addon.tooltipRendering then
                                -- Later post-hooks can change existing row text or attach live widgets.
                                local saved = Addon.stackedTooltips and Addon.stackedTooltips[source]
                                if saved and saved.replacement then saved.contentDirty = true end
                                Send("layout.request")
                            end
                            -- Quest tooltips are complete at Show, including the native controller hints.
                            local owner = source == GameTooltip and source:GetOwner()
                            if Addon.lifecycle == "ready" and not Addon.tooltipRendering
                                and owner and not owner:IsForbidden()
                                and (owner.pinTemplate == "QuestPinTemplate" or Addon:GetQuestListTooltipQuestID(owner)) then
                                Addon:Run("translate quest tooltip", Addon.ShowTranslationTooltip, Addon)
                            end
                            Addon:RecordDebugTooltipText(source)
                        end
                    end)
                    hooksecurefunc(source, "SetPoint", function() Send("layout.request") end)
                    source:HookScript("OnSizeChanged", function() Send("layout.request") end)
                end
            end
        end
    end

    if registered then return end

    registered = true
    if TooltipComparisonManager then
        local function LayoutComparisonSource(source)
            if Addon.lifecycle ~= "ready" or not source or source:IsForbidden() then return end
            local spec = Addon.nameTooltips[source]
            if spec then Addon:LayoutNameTooltipGroup(spec.group) end
        end
        local function LayoutComparison(manager)
            LayoutComparisonSource(manager.tooltip)
        end
        -- Observe completion through secure post-hooks. The direct TOOLTIP_SHOW_ITEM_COMPARISON
        -- callback caused native merchant gamepad taint in client testing.
        hooksecurefunc(TooltipComparisonManager, "AnchorShoppingTooltips", LayoutComparison)
        hooksecurefunc(TooltipComparisonManager, "SetItemTooltip", function(manager)
            if Addon:GetTooltipPresentation(manager.tooltip) ~= "separate" then LayoutComparison(manager) end
        end)
        if GameTooltip_ShowCompareItem then
            -- The native C comparison path can bypass the manager's method hooks. Finish stacked
            -- layout after that entire call, so periodic pinned-tooltip refreshes never paint short.
            hooksecurefunc(_G, "GameTooltip_ShowCompareItem", function(source)
                source = source or GameTooltip
                if Addon:GetTooltipPresentation(source) ~= "separate" then
                    Addon:Run("layout completed item comparison", LayoutComparisonSource, source)
                end
            end)
        end
    end
    for _, component in ipairs(components) do
        component.Install()
    end
    TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(source, data)
        if Addon.nameTooltips and Addon.nameTooltips[source] and Addon.RecordAuraResolution then
            Addon:RecordAuraResolution(source:IsForbidden() and "tooltip-source-forbidden" or "tooltip-postcall-received")
        end
        if Addon.RecordDebugTooltip then Addon:RecordDebugTooltip(source, data) end
        if Addon.TraceTooltip then Addon:TraceTooltip("data", source, data) end
        local preview = Addon.settingsPanel and Addon.settingsPanel.TooltipPreview
        if preview and source == preview.native and not Addon.tooltipRendering then
            Addon:Run("update tooltip preview", Addon.RenderTooltipPreview, Addon, data)
            return
        end
        if Addon.lifecycle ~= "ready" or not Addon.nameTooltips[source] or source:IsForbidden() then return end
        Addon:Run("translate tooltip data", Addon.SendTooltipEvent, Addon, Addon.nameTooltips[source].group,
            { type = "native.data", source = source, data = data, nativeShowPending = true })
    end)
end
