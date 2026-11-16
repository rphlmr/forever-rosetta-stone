local _, Addon = ...

local owners = setmetatable({}, { __mode = "k" })
local records = setmetatable({}, { __mode = "v" })
local nextID = 0

local function TrackRow(frame, label)
    if not frame or frame:IsForbidden() then return end
    local record = owners[frame]
    if not record then
        nextID = nextID + 1
        record = { id = "stat:" .. nextID }
        owners[frame], records[record.id] = record, record
    end
    record.labelKey = nil
    if label then
        for key in pairs(Addon.characterStatFormats.enUS) do
            if _G[key] == label then record.labelKey = key; break end
        end
    end
end

local function CaptureTooltip(source)
    if Addon.lifecycle ~= "ready" or Addon.tooltipRendering or source:IsForbidden() or not source:IsShown() then return end
    local owner = source:GetOwner()
    if not owner or owner:IsForbidden() then return end
    local record = owners[owner]
    if not record then return end
    Addon:ClearStackedTooltip(source)
    local lines = {}
    for index = 1, source:NumLines() do
        local left, right = source:GetLeftLine(index), source:GetRightLine(index)
        local leftText, rightText = left and left:GetText(), right and right:GetText()
        if not canaccessallvalues(leftText, rightText) then return end
        lines[index] = {
            left = leftText, right = rightText,
            leftColor = left and { left:GetTextColor() } or { 1, 1, 1 },
            rightColor = right and { right:GetTextColor() } or { 1, 1, 1 },
        }
    end
    if #lines == 0 then return end
    record.lines = lines
    Addon:UpdateNameTooltip(source, "characterStat", record.id)
end

Addon:RegisterNameTooltipComponent({
    kind = "characterStat",
    alwaysFull = true,
    placementProfiles = Addon:CreateTooltipPlacementProfiles({
        name = "characterStat", contexts = { default = {} },
        mouse = { allowSideFallback = true, sideRules = { Addon.TooltipSideRules.right, Addon.TooltipSideRules.screen } },
        gamepad = { allowSideFallback = true, sideRules = { Addon.TooltipSideRules.right, Addon.TooltipSideRules.screen } },
    }),
    GetName = function(id, locale)
        local record = records[id]
        if not record or not record.lines or not record.lines[1] then return end
        return Addon:TranslateCharacterStatText(record.lines[1].left, locale, record.labelKey) or record.lines[1].left
    end,
    FillTooltip = function(tip, source, _, _, _, _, spec)
        local record = records[spec.id]
        if not record or not record.lines then return end
        local locale = Addon:GetTargetLocale()
        local incomplete = false
        for index, row in ipairs(record.lines) do
            local left = Addon:TranslateCharacterStatText(row.left, locale, record.labelKey)
            local right = Addon:TranslateCharacterStatText(row.right, locale, record.labelKey)
            if (row.left and not left) or (row.right and row.right ~= "" and not right) then incomplete = true end
            left, right = left or row.left or "", right or row.right
            if right and right ~= "" then
                tip:AddDoubleLine(left, right, row.leftColor[1], row.leftColor[2], row.leftColor[3],
                    row.rightColor[1], row.rightColor[2], row.rightColor[3])
            else
                tip:AddLine(left, row.leftColor[1], row.leftColor[2], row.leftColor[3], true)
            end
            for _, side in ipairs({ "Left", "Right" }) do
                local target = tip["Get" .. side .. "Line"](tip, index)
                local original = source["Get" .. side .. "Line"](source, index)
                if target and original then
                    Addon:CopyQuestTextStyle(target, original)
                    target:SetTextScale(original:GetTextScale())
                end
            end
        end
        if incomplete then tip:AddLine(Addon:GetIncompleteTranslationNotice(), 0.65, 0.65, 0.65, true) end
    end,
    Install = function()
        hooksecurefunc(GameTooltip, "Show", function(source)
            Addon:Run("translate character stat tooltip", CaptureTooltip, source)
        end)
        local function InstallRowHooks()
            if type(PaperDollFrame_SetLabelAndText) ~= "function"
                or not CharacterStatFrameScrollBoxBaseElementMixin
                or type(CharacterStatFrameScrollBoxBaseElementMixin.Init) ~= "function" then return false end
            hooksecurefunc("PaperDollFrame_SetLabelAndText", function(frame, label) TrackRow(frame, label) end)
            hooksecurefunc(CharacterStatFrameScrollBoxBaseElementMixin, "Init", function(frame, elementData)
                local label = canaccessallvalues(elementData) and type(elementData) == "table" and elementData.labelText
                TrackRow(frame, label)
            end)
            return true
        end
        if InstallRowHooks() then return end
        local loader = CreateFrame("Frame")
        loader:RegisterEvent("ADDON_LOADED")
        loader:SetScript("OnEvent", function(frame)
            if InstallRowHooks() then frame:UnregisterAllEvents() end
        end)
    end,
})
