"""Check that tracker cleanup only removes its own stacked tooltip."""

import unittest

from lupa.lua51 import LuaRuntime


class StackedTooltipOwnershipTests(unittest.TestCase):
    def test_tracker_cleanup_preserves_other_components(self):
        lua = LuaRuntime(encoding=None)
        lua.execute(b"""
            canaccessallvalues = function() return true end
            GetLocale = function() return "enUS" end
            local addon = {
                GetTargetLocale = function() return "enUS" end,
                GetLanguageName = function() return "English" end,
                IsTooltipBlocked = function() return false end,
                IsFeatureEnabled = function() return true end,
                GetTooltipFocus = function() return nil end,
                RegisterNameTooltipComponent = function() end,
            }
            assert(loadfile("ForeverRosettaStone/core/localized-fonts.lua"))("addon", addon)
            assert(loadfile("ForeverRosettaStone/tooltips/tooltip-layout.lua"))("addon", addon)
            assert(loadfile("ForeverRosettaStone/tooltips/components/quest-tracker-tooltip.lua"))("addon", addon)

            local function line()
                return {
                    GetText = function(self) return self.text end,
                    SetText = function(self, text) self.text = text end,
                    GetTextColor = function() return 1, 1, 1, 1 end,
                    GetFont = function() return "font", 12, "" end,
                    GetTextScale = function() return 1 end,
                    GetJustifyH = function() return "LEFT" end,
                    CanWordWrap = function() return false end,
                    CanNonSpaceWrap = function() return false end,
                    GetShadowColor = function() return 0, 0, 0, 1 end,
                    GetShadowOffset = function() return 0, 0 end,
                    GetSpacing = function() return 0 end,
                    SetFont = function() end, SetTextScale = function() end,
                    SetTextColor = function() end, SetJustifyH = function() end,
                    SetWordWrap = function() end, SetNonSpaceWrap = function() end, SetShadowColor = function() end,
                    SetShadowOffset = function() end, SetSpacing = function() end,
                }
            end
            local source = { left = {}, right = {}, count = 0 }
            function source:GetLeftLine(index)
                self.left[index] = self.left[index] or line()
                return self.left[index]
            end
            function source:GetRightLine(index)
                self.right[index] = self.right[index] or line()
                return self.right[index]
            end
            function source:NumLines() return self.count end
            function source:AddLine(text)
                self.count = self.count + 1
                self:GetLeftLine(self.count).text = text
            end
            function source:ClearLines() error("addon code must not clear a native tooltip") end
            function source:IsForbidden() return false end
            function source:IsShown() return false end
            GameTooltip = source
            local tracker = { Hide = function(self) self.hidden = true end,
                NumLines = function() return 0 end }
            local location = { Hide = function() end, NumLines = function() return 0 end }
            addon.questTrackerTooltip = tracker

            source:AddLine("Native zone")
            source:AddLine("Native subzone")
            source:AddLine("Map hint")
            addon:FillStackedTooltip(source, location, "location")
            assert(source:NumLines() == 5)
            addon:ClearStackedTooltip(source, true, tracker)
            assert(source:NumLines() == 5, "foreign native-clear removed rows")
            assert(addon.stackedTooltips[source].owner == location)
            addon:UpdateQuestTrackerTooltip()
            assert(source:NumLines() == 5, "tracker cleanup removed another component's rows")
            assert(addon.stackedTooltips[source].owner == location)
            addon.questTrackerTooltip = nil
            addon:UpdateQuestTrackerTooltip()
            assert(source:NumLines() == 5, "missing tracker companion removed another component's rows")
            addon.questTrackerTooltip = tracker

            addon:FillStackedTooltip(source, tracker, "location")
            assert(source:NumLines() == 5)
            assert(addon.stackedTooltips[source].owner == tracker, "same key retained the previous owner")
            addon:UpdateQuestTrackerTooltip()
            assert(source:NumLines() == 5, "stacked rows are blanked in place")
            assert(source:GetLeftLine(4):GetText() == "", "unavailable tracker left its stacked rows")
            assert(source:GetLeftLine(5):GetText() == "", "unavailable tracker left its stacked rows")
            assert(source:GetLeftLine(1):GetText() == "Native zone")
            assert(source:GetLeftLine(2):GetText() == "Native subzone")
            assert(source:GetLeftLine(3):GetText() == "Map hint")
            assert(addon.stackedTooltips[source] == nil)

            addon:FillStackedTooltip(source, location, "location")
            assert(source:NumLines() == 5, "blank rows are reused instead of growing the tooltip")
            assert(source:GetLeftLine(5):GetText() ~= "", "reused rows carry the new translation")
        """)


if __name__ == "__main__":
    unittest.main()
