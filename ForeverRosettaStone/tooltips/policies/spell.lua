local _, Addon = ...

local rules = Addon.TooltipSideRules
Addon.spellTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "spell",
    contexts = { default = {}, actionBar = {}, spellbook = {} },
    mouse = { allowNativeShift = true, sideRules = { rules.fixed, rules.anchor, rules.owner, rules.cursor, rules.screen } },
    gamepad = { allowNativeShift = true, sideRules = { rules.fixed, rules.anchor, rules.owner, rules.cursor, rules.screen } },
})
