local _, Addon = ...

local rules = Addon.TooltipSideRules
Addon.itemTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "item",
    contexts = { default = {}, bag = {}, equipment = {}, actionBar = {}, chatLink = {} },
    mouse = { allowNativeShift = true, sideRules = { rules.fixed, rules.owner, rules.anchor, rules.cursor, rules.screen } },
    gamepad = { allowNativeShift = true, sideRules = { rules.fixed, rules.owner, rules.anchor, rules.cursor, rules.screen } },
})
