"""Exercise unavailable quest formatting at the UI entry points."""

import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]


class QuestFallbackTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            addon = { current = { mode = 'open', questID = 42 }, panel = {}, toggle = {}, page = { body = {} } }
            function addon:GetQuest() return { title = 'title', summary = 'summary', description = 'description' } end
            function addon:FormatQuestText(value) if value == 'title' then return 'Translated' end end
            function addon:GetTranslationLanguageLabel() return 'English' end
            function addon:GetTargetLocale() return 'enUS' end
            function addon:GetProgressText() return '' end
            function addon:IsPanelCollapsed() return false end
            function addon:BeginBenchmarkSample() end
            function addon:EndBenchmarkSample() end
            function addon:RecordDebugSurface() end
            function addon:Layout() end
            function addon.panel:SetTitle() end
            function addon.panel:SetShown() end
            addon.panel.ReportButton = { SetShown = function() end }
            function addon.toggle:SetShown() end
            function addon.page:Show(entry) captured = entry end
            function addon.page.body:ScrollTo() end
            C_QuestLog = {
                GetLogIndexForQuestID = function() return 3 end,
                GetQuestIDForLogIndex = function() return logQuestID end,
            }
            function GetQuestLogQuestText() return 'Native description', 'Native objectives' end
        """)
        source = (ROOT / 'ForeverRosettaStone/quests/quest-ui.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)
        self.lua.execute('function addon:Layout() end')

    def test_panel_uses_only_verified_native_quest_log_fields(self):
        self.lua.execute('logQuestID = 42; addon:Render()')
        entry = self.lua.globals().captured
        self.assertEqual(entry.title, 'Translated')
        self.assertEqual(entry.objectives, 'Native objectives')
        self.assertEqual(entry.description, 'Native description')
        self.lua.execute('logQuestID = 43; addon.contentKey = nil; addon:Render()')
        self.assertEqual(entry.title, 'Translated')
        entry = self.lua.globals().captured
        self.assertEqual(entry.objectives, '')
        self.assertEqual(entry.description, '')

    def test_offer_tooltip_hides_when_title_cannot_be_formatted(self):
        self.lua.execute("""
            hidden = false
            addon.questOfferTooltip = { Hide = function() hidden = true end }
            function addon:IsTooltipBlocked() return false end
            function addon:IsFeatureEnabled() return true end
            function addon:GetTooltipFocus() return { IsVisible = function() return true end }, 42 end
            function addon:RegisterNameTooltipComponent() end
            function addon:FormatQuestText() return nil end
        """)
        source = (ROOT / 'ForeverRosettaStone/tooltips/components/quest-offer-tooltip.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)
        self.lua.execute('addon:UpdateQuestOfferTooltip()')
        self.assertTrue(self.lua.globals().hidden)

    def test_interaction_sections_use_native_text_only_for_active_quest(self):
        self.lua.execute("""
            addon.TooltipSideRules = {}
            function addon:CreateTooltipPlacementProfiles() return {} end
            function addon:RegisterNameTooltipComponent() end
            function addon:GetClientLabel() return 'Objectives' end
            function addon:FormatQuestText(value) if value == 'title' then return 'Translated' end end
            function GetQuestID() return activeQuestID end
            function GetTitleText() return 'Native title' end
            function GetObjectiveText() return 'Native objectives' end
            function GetQuestText() return 'Native description' end
        """)
        source = (ROOT / 'ForeverRosettaStone/quests/components/quest-interaction-panel.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)

        def texts(quest_id, context):
            sections = self.lua.eval(
                f"addon:GetQuestInteractionSections({quest_id}, addon:GetQuest(), '{context}')"
            )
            return [sections[i].text for i in range(1, len(sections) + 1)]

        self.lua.execute('activeQuestID = 42')
        self.assertEqual(texts(42, 'detail'),
                         ['Translated', 'Native description', 'Objectives', 'Native objectives'])
        self.lua.execute('activeQuestID = 43')
        self.assertEqual(texts(42, 'detail'), ['Translated', 'Objectives'])


if __name__ == '__main__':
    unittest.main()
