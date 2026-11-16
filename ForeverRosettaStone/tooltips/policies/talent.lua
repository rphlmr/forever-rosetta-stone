local _, Addon = ...

local rules = Addon.TooltipSideRules
Addon.talentTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "talent",
    contexts = { talentTree = {} },
    mouse = { allowNativeShift = true, sideRules = { rules.fixed, rules.owner, rules.anchor, rules.screen } },
    gamepad = { allowNativeShift = true, sideRules = { rules.fixed, rules.owner, rules.anchor, rules.screen } },
})
