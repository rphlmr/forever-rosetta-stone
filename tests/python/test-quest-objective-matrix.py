"""Exercise every maintained indexed objective across client and target locales."""

import json
import sys

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import indexed_client_targets


EXCLUDED = {'test', 'notImplemented', 'placeholder', 'unused'}
def lua_value(lua, value):
    if isinstance(value, dict):
        return lua.table_from({key.encode() if isinstance(key, str) else key: lua_value(lua, item)
                               for key, item in value.items()})
    if isinstance(value, list) or isinstance(value, tuple):
        return lua.table_from([lua_value(lua, item) for item in value])
    if isinstance(value, str):
        return value.encode()
    return value


def catalog_cases():
    document = load_catalog(ROOT, 'quests')
    locales = document['locales']
    clients = [locale for locale in locales if locale not in document['rosettaLocales']]
    quests = {key: quest for key, quest in document['catalogs']['quests'].items()
              if quest.get('usageStatus') not in EXCLUDED
              and (quest.get('clientObjectiveTargets')
                   or any(value.get('objectiveLines') for value in quest['locales'].values()))}
    item_ids = {str(target['id']) for quest in quests.values()
                for target in quest.get('clientObjectiveTargets', []) if target['kind'] == 'item'}
    items = load_catalog(ROOT, 'items', ids={'items': item_ids})['catalogs']['items']
    npc_ids = {str(target['id']) for quest in quests.values()
               for target in quest.get('clientObjectiveTargets', []) if target['kind'] == 'npc'}
    npcs = load_catalog(ROOT, 'npcs', ids={'npcs': npc_ids})['catalogs']['npcs']
    cases = []
    objective_count = 0

    for quest_id, quest in quests.items():
        targets = {}
        sources = {}
        kinds = {}

        for locale in locales:
            original = quest['locales'].get(locale, {})
            lines = {line['index']: {'type': line['type'], 'text': line['text']}
                     for line in original.get('objectiveLines', [])}
            for index, target in indexed_client_targets(quest):
                if index in lines:
                    continue
                if target['kind'] == 'item':
                    entities, kind = items, 'item'
                elif target['kind'] == 'npc' and target.get('type') == 'monster':
                    entities, kind = npcs, 'monster'
                else:
                    continue
                name = entities.get(str(target['id']), {}).get('locales', {}).get(locale, {}).get('name')
                if name:
                    lines[index] = {'type': kind, 'text': name + ': {current}/{required}'}
            targets[locale] = {'lines': lines, 'hasTitle': bool(original.get('title'))}
            fields = original.get('translationMetadata', {}).get('fields', {})
            sources[locale] = {'objectiveLines': [line for line in original.get('objectiveLines', [])
                if fields.get('objectiveLines.' + str(line['index']), {}).get('origin') == 'original']}
            for index, line in lines.items():
                kinds.setdefault(index, set()).add(line['type'])

        for index, types in kinds.items():
            for kind in types:
                objective_count += 1
                cases.append({'id': int(quest_id), 'index': index, 'type': kind, 'targets': targets, 'sources': sources})

    return locales, clients, cases, len(quests), objective_count


def run_matrix():
    locales, clients, cases, quest_count, objective_count = catalog_cases()
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
    load_database(lua)
    lua.execute(b'''
        addon = {}
        function addon:GetTargetLocale() return targetLocale end
        function addon:BeginBenchmarkSample() end
        function addon:EndBenchmarkSample() end
        function GetLocale() return sourceLocale end
        function UnitName() return "Rosetta" end
        function UnitClass() return "Mage", "MAGE" end
        function UnitRace() return "Human", "Human" end
        function UnitSex() return 2 end
        FACTION_STANDING_LABEL1 = "MatrixRankOne"
        FACTION_STANDING_LABEL2 = "MatrixRankTwo"
        C_QuestLog = { GetQuestObjectives = function() return live end }
    ''')
    lua.execute(b'assert(loadstring(...))("ForeverRosettaStone", addon)',
                (ROOT / 'ForeverRosettaStone/quests/quest-data.lua').read_bytes())
    run = lua.eval(b'''function(cases, clients, locales)
        local totals = { native = 0, synthetic = 0, reputationFallback = 0, translated = 0, mismatch = 0 }
        local missingNative, missingTarget, reputationFallback = {}, {}, {}
        local ranks = { "MatrixRankOne", "MatrixRankTwo" }
        local function fill(text, current, required, standing)
            return (text:gsub("{current}", tostring(current)):gsub("{required}", tostring(required))
                :gsub("{standing}", function() return standing end))
        end
        local function fail(case, source, target, detail)
            error(("quest=%d index=%d type=%s source=%s target=%s: %s")
                :format(case.id, case.index, case.type, source, target, detail))
        end
        for _, case in ipairs(cases) do
            for _, source in ipairs(clients) do
                sourceLocale = source
                local sourceQuest = case.sources[source]
                local nativeTemplate, nativeLine
                for _, line in ipairs(sourceQuest and sourceQuest.objectiveLines or {}) do
                    if line.index == case.index and line.type == case.type then
                        nativeTemplate, nativeLine = line.text, line
                        break
                    end
                end
                if not nativeTemplate then
                    missingNative[#missingNative + 1] = {
                        questId = case.id, index = case.index, type = case.type, source = source
                    }
                end
                for _, target in ipairs(locales) do
                    targetLocale = target
                    local targetCase = case.targets[target]
                    local targetLine = targetCase.lines[case.index]
                    if source == clients[1] then
                        if not targetCase.hasTitle then
                            missingTarget[#missingTarget + 1] = {
                                questId = case.id, index = case.index, type = case.type,
                                target = target, missing = "title"
                            }
                        end
                        if not targetLine or targetLine.type ~= case.type then
                            missingTarget[#missingTarget + 1] = {
                                questId = case.id, index = case.index, type = case.type,
                                target = target, missing = "objective"
                            }
                        end
                    end
                    local targetQuest = ForeverRosettaStoneDB:GetQuest(case.id, target)
                    local storedLine
                    for _, line in ipairs(targetQuest and targetQuest.objectiveLines or {}) do
                        if line.index == case.index then storedLine = line break end
                    end
                    if targetLine and (not storedLine or storedLine.type ~= targetLine.type
                        or storedLine.text ~= targetLine.text) then
                        fail(case, source, target, "database objective does not match maintained catalog")
                    elseif not targetLine and storedLine then
                        fail(case, source, target, "unexpected database objective")
                    end
                    for pass = 1, 2 do
                        local current, required = pass - 1, 7 + pass
                        local native = nativeTemplate and fill(nativeTemplate, current, required, ranks[pass])
                            or ("Synthetic objective " .. case.id .. ":" .. case.index)
                        live = {}
                        for index = 1, case.index do
                            live[index] = { type = "matrix-placeholder", text = "Synthetic filler " .. index }
                        end
                        live[case.index] = { type = case.type, text = native,
                            numFulfilled = current, numRequired = required }
                        local before = live[case.index]
                        local rendered = addon:GetProgressLines(case.id)
                        local expected
                        if targetCase.hasTitle then
                            expected = native
                            if targetLine and targetLine.type == case.type then
                                if targetLine.text:find("{standing}", 1, true) then
                                    totals.reputationFallback = totals.reputationFallback + 1
                                    if pass == 1 then
                                        reputationFallback[#reputationFallback + 1] = {
                                            questId = case.id, index = case.index, type = case.type,
                                            source = source, target = target
                                        }
                                    end
                                else
                                    expected = fill(targetLine.text, current, required, "")
                                    totals.translated = totals.translated + 1
                                end
                            end
                            if not rendered[case.index] or rendered[case.index].translated ~= expected then
                                fail(case, source, target, "expected " .. expected .. " got "
                                    .. tostring(rendered[case.index] and rendered[case.index].translated))
                            end
                            if rendered[case.index].native ~= native then fail(case, source, target, "native text changed") end
                        elseif #rendered ~= 0 then
                            fail(case, source, target, "quest without target title produced progress")
                        end
                        if live[case.index] ~= before or before.text ~= native
                            or before.type ~= case.type or before.numFulfilled ~= current or before.numRequired ~= required then
                            fail(case, source, target, "live objective mutated")
                        end
                        if nativeLine and (nativeLine.text ~= nativeTemplate or nativeLine.type ~= case.type
                            or nativeLine.index ~= case.index) then
                            fail(case, source, target, "source template mutated")
                        end
                        if storedLine and (storedLine.text ~= targetLine.text or storedLine.type ~= targetLine.type
                            or storedLine.index ~= case.index) then
                            fail(case, source, target, "target template mutated")
                        end
                        if nativeTemplate then totals.native = totals.native + 1 else totals.synthetic = totals.synthetic + 1 end
                    end
                    if targetCase.hasTitle then
                        local native = "Synthetic mismatch " .. case.id .. ":" .. case.index
                        live = {}
                        for index = 1, case.index do
                            live[index] = { type = "matrix-placeholder", text = "Synthetic filler " .. index }
                        end
                        live[case.index] = { type = "matrix-mismatch", text = native, numFulfilled = 1, numRequired = 8 }
                        local rendered = addon:GetProgressLines(case.id)
                        if not rendered[case.index] or rendered[case.index].translated ~= native then
                            fail(case, source, target, "mismatched type did not retain native text")
                        end
                        totals.mismatch = totals.mismatch + 1
                    end
                end
            end
        end
        return totals, missingNative, reputationFallback, missingTarget
    end''')
    totals, missing_native, reputation_fallback, missing_target = run(
        lua_value(lua, cases), lua_value(lua, clients), lua_value(lua, locales))
    def records(table):
        return [{key.decode(): value.decode() if isinstance(value, bytes) else value
                 for key, value in row.items()} for row in table.values()]

    report = {
        'counts': {
            'quests': quest_count, 'objectiveIndexTypePairs': objective_count,
            'clientLocales': len(clients), 'targetLocales': len(locales), 'liveValues': 2,
            'nativeTemplateBackedSyntheticValues': totals[b'native'],
            'syntheticWithoutNativeTemplate': totals[b'synthetic'],
            'reputationNativeFallbackValues': totals[b'reputationFallback'],
            'translatedValues': totals[b'translated'], 'mismatchedTypeCases': totals[b'mismatch'],
            'missingNativeEvidenceEntries': len(missing_native),
            'reputationFallbackPairs': len(reputation_fallback),
            'missingTargetEntries': len(missing_target),
        },
        'missingNativeEvidence': records(missing_native),
        'reputationFallback': records(reputation_fallback),
        'missingTarget': records(missing_target),
    }
    report_path = ROOT / 'datasources/imports/quest-matrix/objectives.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Quest objective matrix: {quest_count} quests, {objective_count} indexed objective/type pairs; '
          f'{len(clients)} client locales × {len(locales)} target locales × 2 live values')
    print(f'Native-template-backed synthetic values: {totals[b"native"]}; '
          f'values without native templates: {totals[b"synthetic"]}; '
          f'reputation native-fallback cases: {totals[b"reputationFallback"]}; '
          f'translated cases: {totals[b"translated"]}; mismatched-type cases: {totals[b"mismatch"]}')
    print(f'Diagnostic report: {report_path} '
          f'({len(missing_native)} missing native evidence entries, '
          f'{len(reputation_fallback)} reputation fallback pairs, {len(missing_target)} missing target entries)')


if __name__ == '__main__':
    run_matrix()
