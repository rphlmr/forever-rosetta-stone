local Addon = {}
GetLocale = function() return "enUS" end
canaccessallvalues = function() return true end
Enum = { TooltipDataLineType = {} }
ForeverRosettaStoneDB = {
    GetItemDetails = function() return nil end,
    GetSpellDetails = function() return nil end,
    GetItemRules = function() return nil end,
}
assert(loadfile("tests/fixtures/tooltip-source-api.lua"))()(ForeverRosettaStoneDB)
assert(loadfile("ForeverRosettaStone/database/item-data.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/localized-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)

for key, value in pairs(Addon.tooltipFormatsByLocale.enUS) do _G[key] = value end

for _, key in ipairs({ "ITEM_MOD_FIRE_DAMAGE_DONE_SHORT", "ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT",
    "ITEM_MOD_PHYSICAL_DAMAGE_DONE_SHORT" }) do
    local translated = Addon:GetLocalizedTooltipLine({ leftText = _G[key] }, "item", 0, "frFR")
    assert(translated == Addon.tooltipFormatsByLocale.frFR[key], key .. " shared label must translate")
end

local translated = Addon:GetLocalizedTooltipLine({ leftText = "Requires 1 - 2" }, "item", 0, "frFR")
assert(translated == "Requiert 1 - 2", "Known requirement formats preserve displayed values")
print("PASS: shared labels and numeric formats translate through the whole-tooltip path")
