local _, Addon = ...

local function Prepare(tip, source)
    local width = source:GetWidth() * source:GetEffectiveScale() / tip:GetEffectiveScale()
    tip:SetMinimumWidth(width)
    tip:SetWidth(width)
end
local function PreferredSide() return Addon.preferences.npcTooltipPosition end
Addon.npcTooltipPlacements = Addon:CreateTooltipPlacementProfiles({
    name = "npc",
    contexts = { unit = {} },
    mouse = { Prepare = Prepare, sideRules = { PreferredSide } },
    gamepad = { Prepare = Prepare, sideRules = { PreferredSide } },
})
