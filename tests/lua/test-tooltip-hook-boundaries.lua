-- Load fresh modules for each saved preference left by the gamepad investigation.
-- The fixture checks integration boundaries; WoW's taint engine is validated in game.
for _, mode in ipairs({ "baseline", "separate", "no-stats", "no-method-hooks", "no-tooltip-data",
    "no-auxiliary-hooks", "no-script-hooks", "no-comparison-hooks", "no-tooltip-hooks", "no-comparison-event" }) do
    local hooks, messages, scripts = {}, {}, {}
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.print = function(message) messages[#messages + 1] = message end
    env.GetLocale = function() return "frFR" end
    env.date = function() return "2026-11-15 14:00:00" end
    env.GameTooltip = {
        IsForbidden = function() return false end,
        ClearLines = function() end,
        HookScript = function(_, event) scripts[event] = true end,
    }
    env.BattlePetTooltip = {
        IsForbidden = function() return false end,
        HookScript = function(_, event) scripts[event] = true end,
    }
    env.BattlePetToolTip_Show = function() end
    env.CreateFrame = function()
        return { SetScript = function() end, RegisterEvent = function() end }
    end
    env.hooksecurefunc = function(target, method)
        hooks[#hooks + 1] = { target = target, method = method }
    end
    local dataCallback
    env.TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) dataCallback = callback end }
    env.PaperDollFrame_SetLabelAndText = function() end
    env.CharacterStatFrameScrollBoxBaseElementMixin = { Init = function() end }
    env.CollectionWardrobeUtil = { SetAppearanceTooltip = function() end }
    env.TooltipComparisonManager = { AnchorShoppingTooltips = function() end, SetItemTooltip = function() end }
    env.GameTooltip_ShowCompareItem = function() end
    local events = 0
    env.RegisterEventCallback = function() events = events + 1 end
    local talentEvents = 0
    env.EventRegistry = { RegisterCallback = function(_, event)
        assert(event == "TalentDisplay.TooltipHook")
        talentEvents = talentEvents + 1
    end }
    local addon = {
        preferences = { gamepadTaintExperiment = mode, tooltipMode = "stacked" },
        TooltipSideRules = {},
        CreateTooltipPlacementProfiles = function(_, value) return value end,
        CreateTooltipComponent = function(_, value) return value end,
    }
    local function Load(path)
        setfenv(assert(loadfile("ForeverRosettaStone/" .. path .. ".lua")), env)("ForeverRosettaStone", addon)
    end
    Load("core/safety")
    Load("tooltips/tooltip-layout")
    Load("tooltips/tooltip-companions")
    Load("tooltips/components/character-stat-tooltip")
    Load("tooltips/components/appearance-tooltip")
    Load("tooltips/components/minimap-location-tooltip")
    Load("tooltips/components/pet-tooltip")
    Load("tooltips/components/talent-tooltip")
    addon:CreateNameTooltips()
    assert(events == 0, "FRS must not register a direct TOOLTIP_SHOW_ITEM_COMPARISON callback")
    assert(addon:GetTooltipDisplayMode(env.GameTooltip) == "stacked",
        "retired experiment preferences must not override the user's display mode")
    local methods, rows, managerHooks, completionHooks = 0, 0, 0, 0
    for _, hook in ipairs(hooks) do
        if hook.target == env.GameTooltip then methods = methods + 1 end
        if hook.target == "PaperDollFrame_SetLabelAndText"
            or hook.target == env.CharacterStatFrameScrollBoxBaseElementMixin then rows = rows + 1 end
        if hook.target == env.TooltipComparisonManager then managerHooks = managerHooks + 1 end
        if hook.target == env and hook.method == "GameTooltip_ShowCompareItem" then completionHooks = completionHooks + 1 end
    end
    assert(methods == 7 and rows == 2, "all native tooltip and character-stat hooks must remain enabled")
    assert(managerHooks == 2, "secure comparison completion hooks must remain enabled")
    assert(completionHooks == 1, "native comparison completion must use one secure post-hook")
    assert(scripts.OnHide and scripts.OnTooltipCleared and scripts.OnSizeChanged,
        "native tooltip lifecycle hooks must remain enabled")
    assert(talentEvents == 1 and type(dataCallback) == "function",
        "component and tooltip data callbacks must remain enabled")
    local callbacks = 0
    addon.RecordDebugTooltip = function() callbacks = callbacks + 1 end
    addon.TraceTooltip = function() callbacks = callbacks + 1 end
    addon.Run = function() callbacks = callbacks + 1 end
    addon.lifecycle = "ready"
    dataCallback(env.GameTooltip, { id = 1 })
    assert(callbacks == 3, "tooltip data must still reach diagnostics and translation dispatch")
end
print("PASS: tooltip hook boundaries and retired experiment preferences")
