local _, Addon = ...

local rules = Addon.TooltipSideRules
local function LeftSide() return "left" end
Addon.questTrackerTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "questTracker",
    contexts = {
        tracker = {},
        standalone = {
            mouse = { sideRules = { LeftSide } },
            gamepad = { sideRules = { LeftSide } },
        },
    },
    mouse = { sideRules = { rules.owner, rules.screen } },
    gamepad = { sideRules = { rules.owner, rules.screen } },
})
