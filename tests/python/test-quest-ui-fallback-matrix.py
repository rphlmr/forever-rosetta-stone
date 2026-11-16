"""Exercise real quest UI paths with missing and available localized fields."""

import json
from pathlib import Path

from lupa.lua51 import LuaRuntime

from matrix_classification import classify_failure, summarize_report


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'datasources/imports/translation-matrix/quest-ui-fallbacks.json'


def make_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        addon = { current = { mode = 'open', questID = 42 }, panel = {}, toggle = {}, page = { body = {} } }
        function addon:GetTranslationLanguageLabel() return 'French' end
        function addon:GetTargetLocale() return 'frFR' end
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
        function GetLocale() return 'enUS' end
        function UnitRace() return 'Human', 'Human' end
        function UnitClass() return 'Warrior', 'WARRIOR' end
        function UnitName() return 'Tester' end
        function UnitSex() return 2 end
        C_QuestLog = {
            GetQuestObjectives = function() return nil end,
            GetLogIndexForQuestID = function() return 3 end,
            GetQuestIDForLogIndex = function() return logQuestID end,
        }
        function GetQuestLogQuestText() nativeCalls = nativeCalls + 1; return 'Native description', 'Native objectives' end
    """)
    def load(path):
        lua.execute("assert(loadstring(...))('addon', addon)", (ROOT / path).read_text())

    load('ForeverRosettaStone/quests/quest-data.lua')
    load('ForeverRosettaStone/quests/quest-ui.lua')
    lua.execute("""
        function addon:Layout() end
        function addon:GetQuest() return quest end
        function addon:GetClientLabel() return nil end
        function addon:CreateTooltipPlacementProfiles(spec) return spec end
        function addon:RegisterNameTooltipComponent() end
        addon.TooltipSideRules = { screen = function() end }
        QuestInfoTitleHeader, QuestInfoDescriptionText = {}, {}
        QuestInfoObjectivesHeader, QuestInfoObjectivesText = {}, {}
        QUEST_OBJECTIVES = 'Objectives'
        function GetQuestID() return activeQuestID end
        function GetObjectiveText() nativeCalls = nativeCalls + 1; return 'Native objectives' end
        function GetQuestText() nativeCalls = nativeCalls + 1; return 'Native description' end
    """)
    load('ForeverRosettaStone/quests/components/quest-interaction-panel.lua')
    return lua


def run_matrix():
    lua = make_runtime()
    failures = []
    passed = 0
    scenarios = [
        ('missing_summary', None, 'Texte traduit', 42, 'Native objectives', 'Texte traduit'),
        ('missing_description', 'Objectifs traduits', None, 42, 'Objectifs traduits', 'Native description'),
        ('empty_summary', '', 'Texte traduit', 42, 'Native objectives', 'Texte traduit'),
        ('empty_description', 'Objectifs traduits', '', 42, 'Objectifs traduits', 'Native description'),
        ('blank_summary', ' \t\n', 'Texte traduit', 42, 'Native objectives', 'Texte traduit'),
        ('translated', 'Objectifs traduits', 'Texte traduit', 42, 'Objectifs traduits', 'Texte traduit'),
    ]
    for surface in ('panel', 'interaction_sections'):
        for name, summary, description, active_id, expected_summary, expected_description in scenarios:
            lua.globals().quest = lua.table_from({'title': 'Titre', 'summary': summary, 'description': description})
            lua.globals().logQuestID = active_id
            lua.globals().activeQuestID = active_id
            lua.execute('addon.contentKey = nil; nativeCalls = 0')
            if surface == 'panel':
                lua.execute('addon:Render()')
            else:
                lua.execute("""
                    captured = { objectives = '', description = '' }
                    for _, section in ipairs(addon:GetQuestInteractionSections(42, quest)) do
                        if section.source == QuestInfoObjectivesText then captured.objectives = section.text end
                        if section.source == QuestInfoDescriptionText then captured.description = section.text end
                    end
                """)
            entry = lua.globals().captured
            for field, actual, expected in (('summary', entry.objectives, expected_summary),
                                            ('description', entry.description, expected_description)):
                if actual == expected:
                    passed += 1
                else:
                    row = {'id': 42, 'field': field, 'locale': 'frFR', 'surface': surface,
                           'scenario': name, 'reason': 'mismatch', 'expectedPreview': expected,
                           'actualPreview': actual}
                    diagnostic = classify_failure('quest_ui', row)
                    row.update(category=diagnostic['category'], diagnosticCode=diagnostic['code'])
                    failures.append(row)
            if name == 'translated':
                calls = lua.globals().nativeCalls
                if calls == 0:
                    passed += 1
                else:
                    row = {'id': 42, 'field': 'native_lookup_guard', 'locale': 'frFR', 'surface': surface,
                           'scenario': name, 'reason': 'mismatch', 'expectedPreview': '0',
                           'actualPreview': str(calls)}
                    diagnostic = classify_failure('quest_ui', row)
                    row.update(category=diagnostic['category'], diagnosticCode=diagnostic['code'])
                    failures.append(row)
    report = {'kind': 'quest_ui', 'counts': {'cases': passed + len(failures), 'passed': passed,
                                              'failed': len(failures)}, 'failures': failures}
    report['diagnostics'] = summarize_report(report)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(f"Quest UI fallback matrix: {passed}/{report['counts']['cases']} passed; {len(failures)} failed ({OUTPUT})")
    return report


if __name__ == '__main__':
    raise SystemExit(1 if run_matrix()['failures'] else 0)
