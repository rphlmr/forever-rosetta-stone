local _, Addon = ...

local rules = Addon.TooltipSideRules
Addon.talentTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "talent",
    contexts = { talentTree = {} },
    mouse = { allowSideFallback = true, sideRules = { rules.fixed, rules.owner, rules.anchor, rules.screen } },
    gamepad = { allowSideFallback = true, sideRules = { rules.fixed, rules.owner, rules.anchor, rules.screen } },
})
