local Addon = ...
local checks = 0
local function Check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

-- Model native allocation: lookups never create rows, and AddLine has no right FontString.
local function SparseTooltip()
    local tip = CreateFrame("GameTooltip", nil, UIParent)
    local getLeft, getRight, addLine, addDouble = tip.GetLeftLine, tip.GetRightLine, tip.AddLine, tip.AddDoubleLine
    local writing = false
    tip.GetLeftLine = function(self, index)
        if writing or self.lines[index] ~= nil then return getLeft(self, index) end
    end
    tip.GetRightLine = function(self, index)
        if writing or type(self.lines[index]) == "table" then return getRight(self, index) end
    end
    tip.AddLine = function(self, ...)
        writing = true
        addLine(self, ...)
        writing = false
    end
    tip.AddDoubleLine = function(self, ...)
        writing = true
        addDouble(self, ...)
        writing = false
    end
    return tip
end

local source, translated = SparseTooltip(), SparseTooltip()
Check(Addon:GetTooltipRect(nil) == nil, "absent frames have no tooltip rectangle")
Check(not Addon:TransitionTooltipSources(nil, "sources.restore"), "absent placement owners require no cleanup")
Check(not Addon:TransitionTooltipSources({}, "sources.place", {{left = 0, top = 0}}), "incomplete placement data leaves native anchors alone")
Addon:FillEnglishTooltip(nil)
Addon:FillNpcTooltip(nil)
Addon:FillNameTooltip(nil)
Addon:FillNameTooltip({source = source, tip = translated, kind = "removed"})
Check(not translated:IsShown(), "expired tooltip identities hide their old companion")
source:AddLine("Native title")
translated:AddLine("Translated title")
translated:AddDoubleLine("Damage", "4 - 7")
Check(source:GetRightLine(1) == nil, "single-column native rows do not allocate right FontStrings")
Check(source:GetLeftLine(2) == nil, "future rows do not exist before AddLine")
Addon:CopyQuestTextStyle(nil, source:GetLeftLine(1))
Addon:CopyQuestTextStyle(translated:GetLeftLine(1), nil)
local nativeTitle = source:GetLeftLine(1)
local nativeFont = nativeTitle.GetFont
nativeTitle.GetFont = function() return nil end
local translatedFont = translated:GetLeftLine(1):GetFont()
Addon:CopyQuestTextStyle(translated:GetLeftLine(1), nativeTitle)
Check(translated:GetLeftLine(1):GetFont() == translatedFont, "missing source font retains the target font")
nativeTitle.GetFont = nativeFont
Addon:FillStackedTooltip(source, translated, "sparse")
Check(source:GetLeftLine(1):GetText() == "Native title", "stacking preserves native text")
Check(source:GetLeftLine(4):GetText() == "Translated title", "stacking allocates translated single-column rows")
Check(source:GetRightLine(5):GetText() == "4 - 7", "stacking allocates translated double-column rows")
Addon:ClearStackedTooltip(source)
Check(source:GetLeftLine(4):GetText() == "", "cleanup tolerates missing right FontStrings")
translated:ClearLines()
translated:AddLine("Translated title")
Addon:FillStackedTooltip(source, translated, "sparse-again")
Check(source:NumLines() == 5, "stacking reuses blank rows with missing right FontStrings")
Addon:ClearStackedTooltip(source)

local empty, tip = SparseTooltip(), SparseTooltip()
Addon:FillEnglishTooltip({source = empty, tip = tip, kind = "spell", id = 458,
    name = "Translated mount", data = {lines = {}}})
Check(tip:GetLeftLine(1):GetText() == "Translated mount", "missing native spell title retains the translated name")
tip:ClearLines()
Addon:FillNpcTooltip({source = empty, tip = tip, kind = "npc", id = 721,
    name = "Rabbit", data = {lines = {}}})
Check(tip:GetLeftLine(1):GetText() == "Rabbit", "missing native NPC title retains the translated name")

Addon:SetStandaloneTooltipTitle(tip, "Standalone title")
Check(tip:GetLeftLine(tip:NumLines()):GetText() == "Standalone title", "standalone titles tolerate sparse columns")

local nativeMap = WorldMapFrame
WorldMapFrame = {IsShown = function() return true end,
    dataProviders = {[{Label = {IsVisible = function() return true end}}] = true}}
Addon:ShowMapLocationLabel()
Check(not Addon.mapLocationLabel:IsShown(), "a pooled map label without text regions stays native")
WorldMapFrame = nativeMap

local spec = Addon.nameTooltips[GameTooltip]
Addon:SendTooltipEvent(spec.group, {type = "native.data", source = GameTooltip})
Check(spec.kind == nil and not spec.tip:IsShown(), "missing client tooltip data clears stale translations without suspending the addon")
return checks
