local _, Addon = ...

local function Readable(value, kind)
    return canaccessallvalues(value) and type(value) == kind
end

local function MatchesUnit(source, guid)
    if not source or not source.GetUnit or not UnitGUID then return false end
    local ok, _, unit = pcall(source.GetUnit, source)
    if not ok or not Readable(unit, "string") then return false end
    local guidOK, liveGUID = pcall(UnitGUID, unit)
    return guidOK and Readable(liveGUID, "string") and liveGUID == guid
end

local function Prepare(tip, source)
    local width = source:GetWidth() * source:GetEffectiveScale() / tip:GetEffectiveScale()
    tip:SetMinimumWidth(width)
    tip:SetWidth(width)
end

Addon:RegisterNameTooltipComponent({
    kind = "player",
    supportsFullText = true,
    defaultContext = "unit",
    placementProfiles = Addon:CreateTooltipPlacementProfiles({
        name = "player",
        contexts = { unit = {} },
        mouse = { Prepare = Prepare, sideRules = { function() return Addon.preferences.npcTooltipPosition end } },
        gamepad = { Prepare = Prepare, sideRules = { function() return Addon.preferences.npcTooltipPosition end } },
    }),
    GetName = function(guid, _, source, data)
        -- Names are personal text, not catalog translations. There is no name-only player translation.
        if Addon.preferences.tooltipCoverage == "name" or not Readable(guid, "string")
            or not data or not Readable(data.guid, "string") or data.guid ~= guid
            or not MatchesUnit(source, guid) then return end
        local title = source:GetLeftLine(1)
        local name = title and title:GetText()
        if Readable(name, "string") and name ~= "" then return name end
    end,
    ResolveData = function(source, data)
        if data.type ~= Enum.TooltipDataType.Unit or not Readable(data.guid, "string") then return end
        if data.guid:match("^Player%-%d+%-%x+$") and MatchesUnit(source, data.guid) then return data.guid end
    end,
})
