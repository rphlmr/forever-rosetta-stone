local Addon = { itemTooltipLabels = {} }
function Addon:RecordAuraResolution(reason) self.lastAuraReason = reason end
function Addon:RegisterNameTooltipComponent(component) self.spellComponent = component end
function Addon:IsReadableEntityID(value) return canaccessallvalues(value) and type(value) == "number" and value > 0 end
function Addon:GetTargetLocale() return "enUS" end
GetLocale = function() return "frFR" end
canaccessallvalues = function(...)
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if type(value) == "table" and value.secret then return false end
    end
    return true
end
Enum = { TooltipDataType = { Spell = 1, UnitAura = 7 }, TooltipDataLineType = { SpellName = 13 } }
local native = { originalFields = { description = true, auraDescription = true }, description = "Inflige $s1 dégâts pendant $d.", auraDescription = "Subit $s1 dégâts.",
    sourceDescriptions = { frFR = "Inflige $s1 dégâts pendant $d." } }
local target = { description = "Deals $s1 damage for $d.", auraDescription = "Takes $w1 damage." }
local rules = {}
ForeverRosettaStoneDB = {
    GetSpellName = function() return "Aura name" end,
    GetSourceSpellName = function() return "Nom natif" end,
    GetSpellDetails = function(_, _, locale) return locale == "frFR" and native or target end,
    GetSpellRules = function() return rules end,
    GetSpellSourceDetails = function() return native end,
}
assert(loadfile("ForeverRosettaStone/tooltips/english-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/localized-tooltip-formats.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
assert(loadfile("ForeverRosettaStone/tooltips/components/spell-tooltip.lua"))("ForeverRosettaStone", Addon)

local calls, result = {}, { spellId = 370337 }
C_UnitAuras = {
    GetAuraDataByIndex = function(unit, index, filter)
        calls[#calls + 1] = { "index", unit, index, filter }
        return result
    end,
    GetAuraDataByAuraInstanceID = function(unit, instance)
        calls[#calls + 1] = { "instance", unit, instance }
        return result
    end,
}
local info = { getterName = "GetUnitBuff", getterArgs = { "player", 2 } }
local source = { GetProcessingTooltipInfo = function() return info end }
local auraData = { type = Enum.TooltipDataType.UnitAura }
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337)
assert(calls[1][1] == "index" and calls[1][2] == "player" and calls[1][3] == 2 and calls[1][4] == "HELPFUL")
info.getterName = "GetUnitDebuff"
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337 and calls[2][4] == "HARMFUL")
info = { getterName = "GetUnitAura", getterArgs = { "player", 3, "HELPFUL|PLAYER" } }
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337 and calls[3][4] == "HELPFUL|PLAYER")
info = { getterName = "GetUnitAuraByAuraInstanceID", getterArgs = { "target", 41 } }
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337 and calls[4][1] == "instance")
info.getterName = "GetUnitBuffByAuraInstanceID"
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337 and calls[5][1] == "instance")
info.getterName = "GetUnitDebuffByAuraInstanceID"
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337 and calls[6][1] == "instance")
local processing = source.GetProcessingTooltipInfo
source.GetProcessingTooltipInfo = function() return nil end
source.GetPrimaryTooltipInfo = function() return info end
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337,
    "Persistent primary tooltip info resolves auras outside the native processing callback")
source.GetProcessingTooltipInfo = processing
result = { spellId = { secret = true } }
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "Secret spell IDs must not be used")
result = { secret = true }
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "Secret aura data must not be inspected")
assert(Addon.lastAuraReason == "aura-data-restricted", "Diagnostics distinguish restricted aura payloads")
info = { getterName = "GetUnitAura", getterArgs = { "player", { secret = true } } }
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "Secret getter arguments must not be used")
assert(Addon.lastAuraReason == "getter-arguments-restricted", "Diagnostics identify the common argument gate")
info = { getterName = "GetUnitAura", getterArgs = { "player", 2 } }
C_UnitAuras.GetAuraDataByIndex = function() error("restricted") end
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "Restricted aura lookup must fail closed")
local secretTooltip = setmetatable({ secret = true }, { __index = function() error("restricted tooltip data") end })
assert(Addon.spellComponent.ResolveData(source, secretTooltip) == nil, "Secret tooltip data must not be inspected")
assert(Addon.lastAuraReason == "tooltip-data-restricted", "Diagnostics record restrictions before aura lookup")
assert(Addon.spellComponent.ResolveData(source, { type = Enum.TooltipDataType.Spell, id = 7 }) == 7)

-- Combat can hide a spell ID while leaving the same aura instance publicly identifiable.
local unitGUID = "Player-42-ABCDEF"
UnitGUID = function() return unitGUID end
local inCombat = false
InCombatLockdown = function() return inCombat end
C_UnitAuras.GetUnitAuras = function(_, filter)
    return filter == "HELPFUL" and { { auraInstanceID = 77, spellId = 370337 } } or {}
end
Addon:RefreshPlayerAuraIdentities()
info = { getterName = "GetUnitAuraByAuraInstanceID", getterArgs = { "player", 77 } }
C_UnitAuras.GetAuraDataByAuraInstanceID = function() return result end
inCombat = true
result = { auraInstanceID = 77, spellId = { secret = true } }
C_UnitAuras.GetAuraDataByAuraInstanceID = function() error("combat aura API is inaccessible") end
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337,
    "A current public instance request can use its known identity before the restricted API lookup")
info.getterArgs[3] = { secret = true }
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337,
    "Instance-ID getters never inspect an unused filter argument")
info.getterArgs[2] = 78
assert(Addon.spellComponent.ResolveData(source, auraData) == nil,
    "A failed lookup for an unknown instance never borrows cached text")
info.getterArgs[2], info.getterArgs[3] = 77, nil
C_UnitAuras.GetAuraDataByAuraInstanceID = function() return result end
assert(Addon.spellComponent.ResolveData(source, auraData) == 370337,
    "The same public aura instance keeps its previously known translation during combat")
info.getterArgs[2] = 78
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "New restricted auras never borrow cached identities")
info.getterArgs[2], unitGUID = 77, "Player-42-OTHER"
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "A different unit cannot reuse the player's aura cache")
unitGUID = "Player-42-ABCDEF"
info.getterArgs[2] = { secret = true }
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "An inaccessible instance ID cannot select cached text")
info.getterArgs[2] = 77
result = nil
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "An expired aura cannot reuse cached text")
inCombat = false
C_UnitAuras.GetUnitAuras = function() return {} end
Addon:RefreshPlayerAuraIdentities()
result = { auraInstanceID = 77, spellId = { secret = true } }
assert(Addon.spellComponent.ResolveData(source, auraData) == nil, "Refreshing the live aura list prunes expired identities")
UnitGUID, InCombatLockdown = nil, nil
info = { getterName = "GetUnitAura", getterArgs = { "player", 2 } }

local original = {
    GetTextColor = function() return 1, 1, 1 end,
    GetFont = function() return "font", 12, "" end,
    GetTextScale = function() return 1 end,
}
source.GetLeftLine = function() return original end
local rendered = {}
local tip = {
    AddLine = function(_, text) rendered[#rendered + 1] = { text = text, SetFont = function() end,
        SetTextScale = function() end } end,
    NumLines = function() return #rendered end,
    GetLeftLine = function(_, index) return rendered[index] end,
}
C_Spell = { GetSpellDescription = function() error("Aura rendering must not query cast descriptions") end }
result = { spellId = 370337, points = { 42 }, expirationTime = 0 }
C_UnitAuras.GetAuraDataByIndex = function() return result end
local function render(text)
    rendered = {}
    Addon:FillEnglishTooltip({ source = source, tip = tip, kind = "spell", id = 370337, name = "Aura name",
        data = { type = Enum.TooltipDataType.UnitAura, lines = {
            { lineIndex = 1, type = Enum.TooltipDataLineType.SpellName, leftText = "Nom natif" },
            { lineIndex = 2, leftText = text },
        } } })
    return rendered
end
local lines = render("Subit 42 dégâts.")
assert(#lines == 2 and lines[2].text == "Takes 42 damage.", "Translate the aura template with live values")
rendered = {}
Addon:FillEnglishTooltip({ source = source, tip = tip, kind = "spell", id = 370337, name = "Aura name",
    data = { type = Enum.TooltipDataType.UnitAura, lines = { { lineIndex = 1, leftText = "Subit 42 dégâts." } } } })
assert(#rendered == 2 and rendered[2].text == "Takes 42 damage.",
    "An aura description in the first row must not be mistaken for its title")
lines = render("Unrelated client wording.")
assert(#lines == 3 and lines[2].text == "Unrelated client wording.", "A template mismatch stays native")
result.points = { secret = true }
lines = render("Subit 73 dégâts.")
assert(#lines == 2 and lines[2].text == "Takes 73 damage.", "Aura text supplies amounts without reading points")
GetSpellBonusDamage = function() error("No damage power recalculation") end
GetSpellBonusHealing = function() error("No healing power recalculation") end
result.points = nil
lines = render("Subit 19 dégâts.")
assert(#lines == 2 and lines[2].text == "Takes 19 damage.", "Refresh values from the displayed text")
UnitGUID = function() return "Player-42-ABCDEF" end
InCombatLockdown = function() return false end
C_UnitAuras.GetUnitAuras = function(_, filter)
    return filter == "HELPFUL" and { { auraInstanceID = 77, spellId = 370337 } } or {}
end
Addon:RefreshPlayerAuraIdentities()
InCombatLockdown = function() return true end
result = { auraInstanceID = 77, spellId = { secret = true }, points = { secret = true } }
lines = render("Subit 73 dégâts.")
assert(#lines == 2 and lines[2].text == "Takes 73 damage.",
    "A known aura keeps its translated description with current readable amounts during combat")
result.auraInstanceID = { secret = true }
assert(Addon.spellComponent.ResolveData(source, auraData) == nil,
    "A restricted aura slot cannot select a cached instance through secret data")
UnitGUID, InCombatLockdown = nil, nil
target.auraDescription = nil
lines = render("Subit 42 dégâts.")
assert(#lines == 3 and lines[2].text == "Subit 42 dégâts.", "Missing translations retain native text")
result = { spellId = 370337, name = "Nourriture" }
rendered = {}
Addon:FillEnglishTooltip({ source = source, tip = tip, kind = "spell", id = 370337, name = "Food",
    data = { type = Enum.TooltipDataType.UnitAura, lines = {
        { lineIndex = 1, type = 0, leftText = "Nourriture" },
        { lineIndex = 2, type = 0, leftText = "Rend 2 points de vie par seconde." },
    } } })
assert(#rendered == 3 and rendered[1].text == "Food"
    and rendered[2].text == "Rend 2 points de vie par seconde.", "No duplicate untyped aura title")
print("PASS: ID-based aura identity, native numeric capture and safe fallbacks")
