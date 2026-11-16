local Addon = ...
local checks = 0
local function check(condition, label)
    assert(condition, label)
    checks = checks + 1
end
local expected = { characterStat = true, item = true, spell = true, talent = true, npc = true, player = true, mount = true, pet = true,
    recipeTracker = true, recipeList = true, quest = true, questTracker = true, questOffer = true, questInteraction = true,
    minimapQuest = true, minimapLocation = true, appearance = true, appearanceSlot = true, activity = true,
    bookReader = true, book = true, gossipOption = true, taxiNode = true }
local methods = { "GetName", "ResolveData", "ResolveOwner", "GetPlacementContext", "SelectPlacementPolicy", "FillTooltip",
    "AfterFill", "Install", "Update", "Hide" }
local components = Addon:GetTooltipComponents()
local seenPolicies = {}
local featureIDs = {}
for _, feature in ipairs(Addon.features) do featureIDs[feature.id] = true end
local panelFeatures = { questInteraction = "questPanel", bookReader = "bookPanel" }
check(#components == 23, "all twenty-three translation components must register")
for _, component in ipairs(components) do
    local feature = panelFeatures[component.kind] or component.kind .. "Tooltip"
    check(featureIDs[feature] and Addon.settings[feature] ~= nil,
        component.kind .. " must have a native Settings checkbox for disabling its translation")
    check(expected[component.kind], "component IDs are unique and match the component inventory")
    expected[component.kind] = nil
    check(Addon:GetTooltipComponent(component.kind) == component, "component registry returns the registered implementation")
    for _, method in ipairs(methods) do
        check(type(component[method]) == "function", component.kind .. " must implement " .. method)
    end
    for context, profiles in pairs(component.placementProfiles) do
        for _, mode in ipairs({ "mouse", "gamepad" }) do
            local policy = profiles[mode]
            check(type(policy.GetSide) == "function", component.kind .. " must have a placement strategy")
            check(policy.context == context and policy.inputMode == mode, "placement configuration identifies its context and input mode")
            check(not seenPolicies[policy], "components, screen contexts, and input modes must not share mutable policy instances")
            seenPolicies[policy] = true
        end
    end
end
check(next(expected) == nil, "every inventoried component implements the common contract")
local validName = function() return "Test" end
check(not pcall(Addon.CreateTooltipComponent, Addon, { kind = "invalid" }), "missing lookups are rejected during registration")
check(not pcall(Addon.CreateTooltipComponent, Addon, { kind = "invalid", GetName = validName, ResolveData = true }),
    "invalid method implementations are rejected rather than ignored")
check(not pcall(Addon.CreateTooltipComponent, Addon, { kind = "invalid", GetName = validName, supportsFullText = "yes" }),
    "invalid capability types are rejected rather than silently changing behavior")
check(not pcall(Addon.CreateTooltipComponent, Addon, { kind = "invalid", GetName = validName, placementProfiles = { default = { mouse = {}, gamepad = {} } } }),
    "placement strategies must implement their interface")
local originalItem = Addon:GetTooltipComponent("item")
check(not pcall(Addon.RegisterNameTooltipComponent, Addon, { kind = "item", GetName = validName }),
    "duplicate component IDs are refused")
check(Addon:GetTooltipComponent("item") == originalItem, "rejected registration cannot replace an existing component")
local getGamepadMode = InputUtil.IsGamepadUIEnabled
for _, mode in ipairs({ "mouse", "gamepad" }) do
    InputUtil.IsGamepadUIEnabled = function() return mode == "gamepad" end
    for _, component in ipairs(components) do
        check(component.SelectPlacementPolicy(GameTooltip).inputMode == mode, "registry selects the active input-mode policy")
    end
end
InputUtil.IsGamepadUIEnabled = getGamepadMode
local updateTracker, updateOffer = Addon.UpdateQuestTrackerTooltip, Addon.UpdateQuestOfferTooltip
local trackerUpdates, offerUpdates = 0, 0
Addon.UpdateQuestTrackerTooltip = function() trackerUpdates = trackerUpdates + 1 end
Addon.UpdateQuestOfferTooltip = function() offerUpdates = offerUpdates + 1 end
Addon:UpdateTooltipComponents()
Addon.UpdateQuestTrackerTooltip, Addon.UpdateQuestOfferTooltip = updateTracker, updateOffer
check(trackerUpdates == 1 and offerUpdates == 1, "focus-driven components update through the same interface")
return checks
