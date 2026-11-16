local _, Addon = ...

local function NoResult() end
local function FillTitle(tip, _, name, red, green, blue)
    Addon:SetCompanionTooltipTitle(tip, name, red, green, blue)
end

-- Every registered tooltip component exposes these methods, including components driven by focus polling.
Addon.tooltipComponentMethods = {
    "GetName", "ResolveData", "ResolveOwner", "GetPlacementContext", "SelectPlacementPolicy", "FillTooltip",
    "AfterFill", "Install", "Update", "Hide",
}

function Addon:CreateTooltipComponent(definition)
    assert(type(definition.kind) == "string" and definition.kind ~= "", "Tooltip component requires a kind")
    assert(type(definition.GetName) == "function", definition.kind .. ".GetName must be a function")
    local component = {}
    for key, value in pairs(definition) do component[key] = value end
    for _, capability in ipairs({ "supportsFullText", "alwaysFull", "supportsEmbedded" }) do
        assert(definition[capability] == nil or type(definition[capability]) == "boolean",
            component.kind .. "." .. capability .. " must be a boolean")
    end
    component.defaultContext = definition.defaultContext or "default"
    component.placementProfiles = definition.placementProfiles or self:CreateTooltipPlacementProfiles({
        name = component.kind, contexts = { [component.defaultContext] = {} },
        mouse = { sideRules = { self.TooltipSideRules.right } },
        gamepad = { sideRules = { self.TooltipSideRules.right } },
    })
    assert(component.placementProfiles[component.defaultContext], component.kind .. " requires its default placement context")
    for context, profiles in pairs(component.placementProfiles) do
        assert(profiles.mouse ~= profiles.gamepad, component.kind .. "." .. context .. " must isolate input modes")
        for _, mode in ipairs({ "mouse", "gamepad" }) do
            assert(type(profiles[mode]) == "table" and type(profiles[mode].GetSide) == "function",
                component.kind .. "." .. context .. "." .. mode .. " must implement GetSide")
        end
    end
    component.supportsFullText = definition.supportsFullText == true
    component.alwaysFull = definition.alwaysFull == true
    component.supportsEmbedded = definition.supportsEmbedded ~= false
    local defaults = {
        ResolveData = NoResult, ResolveOwner = NoResult, FillTooltip = FillTitle,
        AfterFill = NoResult, Install = NoResult, Update = NoResult, Hide = NoResult,
        GetPlacementContext = function() return component.defaultContext end,
        SelectPlacementPolicy = function(source)
            return component.placementProfiles[component.GetPlacementContext(source)][self:GetTooltipInputMode()]
        end,
    }
    for method, default in pairs(defaults) do
        if component[method] == nil then component[method] = default end
    end
    for _, method in ipairs(self.tooltipComponentMethods) do
        assert(type(component[method]) == "function", component.kind .. "." .. method .. " must be a function")
    end
    return component
end
