local _, Addon = ...

Addon.TooltipSideRules = {
    right = function() return "right" end,
    fixed = function(context) return context.fixedSide end,
    owner = function(context)
        if context.native and context.owner then
            return context.native.left + context.native.right < context.owner.left + context.owner.right and "left" or "right"
        end
    end,
    anchor = function(context)
        local anchor = context.anchor or ""
        if anchor:find("LEFT", 1, true) then return "left" end
        if anchor:find("RIGHT", 1, true) then return "right" end
    end,
    cursor = function(context)
        if context.native and (context.anchor or ""):find("CURSOR", 1, true) then
            local cursorX = GetCursorPosition()
            return (context.native.left + context.native.right) / 2 < cursorX and "left" or "right"
        end
    end,
    screen = function(context) return context.screenSide end,
}

function Addon:CreateTooltipPlacementPolicy(options)
    local sideRules = {}
    for index, rule in ipairs(options.sideRules) do sideRules[index] = rule end
    return {
        name = options.name,
        context = options.context,
        inputMode = options.inputMode,
        allowNativeShift = options.allowNativeShift,
        Prepare = options.Prepare,
        LayoutGroup = options.LayoutGroup,
        GetSide = function(source)
            local context = self:GetTooltipAnchorContext(source)
            for _, rule in ipairs(sideRules) do
                local side = rule(context)
                if side then return side end
            end
        end,
    }
end

function Addon:GetTooltipInputMode()
    return InputUtil.IsGamepadUIEnabled() and "gamepad" or "mouse"
end

function Addon:CreateTooltipPlacementProfiles(options)
    local profiles = {}
    for context, overrides in pairs(options.contexts) do
        profiles[context] = {}
        for _, mode in ipairs({ "mouse", "gamepad" }) do
            local configuration = {}
            for key, value in pairs(options[mode]) do configuration[key] = value end
            for key, value in pairs(overrides[mode] or {}) do configuration[key] = value end
            configuration.name, configuration.context, configuration.inputMode = options.name, context, mode
            profiles[context][mode] = self:CreateTooltipPlacementPolicy(configuration)
        end
    end
    return profiles
end
