local _, Addon = ...

local rules = Addon.TooltipSideRules
Addon.spellTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "spell",
    contexts = { default = {}, actionBar = {}, spellbook = {} },
    mouse = { allowSideFallback = true, sideRules = { rules.fixed, rules.anchor, rules.owner, rules.cursor, rules.screen } },
    gamepad = { allowSideFallback = true, sideRules = { rules.fixed, rules.anchor, rules.owner, rules.cursor, rules.screen } },
})
