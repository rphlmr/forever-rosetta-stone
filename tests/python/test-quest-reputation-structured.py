"""Verified indexed faction bindings render live structured standing only."""

import unittest

from lupa.lua51 import LuaRuntime

from tools.build.runtime_catalog import project_objectives


class QuestReputationStructuredTests(unittest.TestCase):
    def test_projection_preserves_explicit_text_and_attaches_verified_faction(self):
        quest = {'clientObjectiveTargets': [{'index': 2, 'kind': 'faction', 'type': 'reputation', 'id': 42}]}
        original = {'objectiveLines': [{'index': 2, 'type': 'reputation', 'text': '{standing} / Friendly'}]}
        lines, _ = project_objectives(quest, original, 'frFR', {})
        self.assertEqual(lines, [{'index': 2, 'type': 'reputation', 'text': '{standing} / Friendly', 'factionID': 42}])
        for target in ({'kind': 'faction', 'type': 'reputation', 'id': 42},
                       {'index': 2, 'kind': 'faction', 'id': 42},
                       {'index': 2, 'kind': 'faction', 'type': 'reputation', 'id': 0}):
            self.assertNotIn('factionID', project_objectives({'clientObjectiveTargets': [target]}, original, 'frFR', {})[0][0])

    def test_reaction_changes_and_missing_or_restricted_values_fall_back(self):
        lua = LuaRuntime()
        lua.execute('''
            addon = {}
            function addon:GetTargetLocale() return 'frFR' end
            function addon:BeginBenchmarkSample() end
            function addon:EndBenchmarkSample() end
            function addon:GetFactionStandingLabel(rank, locale)
                if locale == 'frFR' then return ({[4] = 'Neutre', [5] = 'Amical'})[rank] end
            end
            function GetLocale() return 'enUS' end
            function UnitRace() return 'Human', 'Human' end
            function UnitClass() return 'Mage', 'MAGE' end
            function UnitName() return 'Test' end
            function UnitSex() return 2 end
            local quest = {title = 'Titre', objectiveLines = {
                {index = 1, type = 'reputation', text = '{standing} / Amical', factionID = 42}}}
            ForeverRosettaStoneDB = {GetQuest = function() return quest end}
            C_QuestLog = {GetQuestObjectives = function() return {
                {type = 'reputation', text = 'Native standing', numFulfilled = 0, numRequired = 1}} end}
            data = {factionID = 42, reaction = 4}
            C_Reputation = {GetFactionDataByID = function(id) assert(id == 42); return data end}
            assert(loadfile('ForeverRosettaStone/quests/quest-data.lua'))('test', addon)
            function result() return addon:GetProgressLines(1)[1].translated end
            assert(result() == 'Neutre / Amical')
            data.reaction = 5
            assert(result() == 'Amical / Amical')
            data.factionID = 43
            assert(result() == 'Native standing')
            data.factionID, data.reaction = 42, 9
            assert(result() == 'Native standing')
            data.reaction = nil
            assert(result() == 'Native standing')
            data.reaction = 3 -- no target-locale label
            assert(result() == 'Native standing')
            C_Reputation.GetFactionDataByID = function() error('restricted') end
            assert(result() == 'Native standing')
            C_Reputation.GetFactionDataByID = function() return data end
            data.reaction = 4
            issecretvalue = function(value) return value == 4 end
            assert(result() == 'Native standing')
            issecretvalue = function(value) return value == data end
            assert(result() == 'Native standing')
            issecretvalue = nil
            canaccessallvalues = function(value) return value ~= data end
            assert(result() == 'Native standing')
            canaccessallvalues = function() error('restricted') end
            assert(result() == 'Native standing')
            canaccessallvalues = nil
            addon.GetFactionStandingLabel = function() return '  ' end
            assert(result() == 'Native standing')
            quest.objectiveLines[1].factionID = math.huge
            local called = false
            C_Reputation.GetFactionDataByID = function() called = true; error('must not call API') end
            assert(result() == 'Native standing')
            assert(not called)
            quest.objectiveLines[1].factionID = nil
            assert(result() == 'Native standing')
        ''')


if __name__ == '__main__':
    unittest.main()
