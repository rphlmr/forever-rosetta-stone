"""Exercise native log-objective fallback across source and target locales."""

import re
import json
import sys
from collections import Counter

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES


LABELS = {
    'enUS': ('Warrior', 'Human', 'Complete'),
    'deDE': ('Krieger', 'Mensch', 'Abgeschlossen'), 'esES': ('Guerrero', 'Humano', 'Completada'),
    'esMX': ('Guerrero', 'Humano', 'Completada'), 'frFR': ('Guerrier', 'Humain', 'Terminé'),
    'itIT': ('Guerriero', 'Umano', 'Completata'), 'ptBR': ('Guerreiro', 'Humano', 'Concluída'),
    'ruRU': ('Воин', 'Человек', 'Выполнено'), 'koKR': ('전사', '인간', '완료'),
    'zhCN': ('战士', '人类', '完成'), 'zhTW': ('戰士', '人類', '完成'),
    'csCZ': ('Válečník', 'Člověk', 'Dokončeno'), 'daDK': ('Kriger', 'Menneske', 'Fuldført'),
    'hrHR': ('Ratnik', 'Čovjek', 'Dovršeno'), 'plPL': ('Wojownik', 'Człowiek', 'Ukończono'),
    'svSE': ('Krigare', 'Människa', 'Slutfört'), 'trTR': ('Savaşçı', 'İnsan', 'Tamamlandı'),
    'ukUA': ('Воїн', 'Людина', 'Виконано'),
}


def format_text(text, locale, source_locale):
    player_class, race, _ = LABELS[locale]
    if locale == source_locale:
        player_class, race = 'NativeClass', 'NativeRace'
    replacements = {'name': 'TestName', 'class': player_class, 'race': race}
    text = re.sub(r'\$[Nn](?![A-Za-z])', lambda _: replacements['name'], text)
    text = re.sub(r'\$[Rr](?![A-Za-z])', lambda _: replacements['race'], text)
    text = re.sub(r'\$[Cc](?![A-Za-z])', lambda _: replacements['class'], text)
    text = re.sub(r'\$[Gg]([^:;$\n.!?]+):([^:;$\n.!?]+);', lambda m: m[1], text)
    text = text.replace('$B', '\n')
    text = re.sub(r'\$b(?![A-Za-z])', '\n', text)
    aliases = {
        'name': 'name', 'nom': 'name', 'nombre': 'name', 'имя': 'name',
        'class': 'class', 'klasse': 'class', 'classe': 'class', 'clase': 'class',
        'race': 'race', 'raza': 'race', 'volk': 'race',
    }
    text = re.sub(r'<([^<>\n]+)>|\{([^{}\n]+)\}',
                  lambda m: replacements.get(aliases.get((m[1] or m[2]).lower()), m[0]), text)
    return re.sub(r'\$(\d+)oa', lambda match: str(6 + int(match[1])), text)


def main():
    catalog = load_catalog(ROOT, 'quests')
    locales = catalog['locales']
    client_locales = [locale for locale in locales if locale not in catalog['rosettaLocales']]
    quests = catalog['catalogs']['quests']
    lua = LuaRuntime(encoding=None)
    install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
    codec = lua.globals().C_EncodingUtil
    def memoize_read_only_decode(decode):
        decoded = {}

        def cached(*arguments):
            if arguments not in decoded:
                decoded[arguments] = decode(*arguments)

            return decoded[arguments]

        return cached

    # This matrix checks matching; repeated immutable page decoding is covered by database tests.
    for key in (b'DecodeBase64', b'DecompressString', b'DeserializeCBOR'):
        codec[key] = memoize_read_only_decode(codec[key])
    db = load_database(lua)
    addon = lua.table()
    lua.globals().testAddon = addon
    amount_indices = [int(index) for quest in quests.values() for localized in quest['locales'].values()
                      for index in re.findall(r'\$(\d+)oa', localized.get('summary', ''))]
    lua.globals().maxObjectiveIndex = max(amount_indices, default=1)
    lua.execute(b'''
        nativeLocale, targetLocale, currentID, objective = "enUS", "enUS", 0, {}
        function GetLocale() return nativeLocale end
        function UnitName() return "TestName" end
        function UnitClass() return "NativeClass", "WARRIOR" end
        function UnitRace() return "NativeRace", "Human" end
        function UnitSex() return 2 end
        liveObjectives = {}
        for index = 1, maxObjectiveIndex do liveObjectives[index] = { numRequired = 6 + index } end
        C_QuestLog = { GetQuestObjectives = function(id) return liveObjectives end }
        function testAddon:GetTargetLocale() return targetLocale end
        function testAddon:BeginBenchmarkSample() end
        function testAddon:EndBenchmarkSample() end
    ''')
    lua.eval(b'function(source, addon) assert(loadstring(source))("ForeverRosettaStone", addon) end')(
        (ROOT / 'ForeverRosettaStone/quests/quest-data.lua').read_bytes(), addon)
    state = lua.globals()
    counts = Counter()
    report = {'missingNativeSource': [], 'missingTargetSummary': [], 'fallback': [], 'failures': []}

    for quest_id, entity in quests.items():
        if entity.get('usageStatus') in EXCLUDED_QUEST_STATUSES:
            continue
        if not any(localized.get('summary') for localized in entity['locales'].values()):
            continue
        counts['quests'] += 1
        for source_locale in client_locales:
            state.nativeLocale = source_locale.encode()
            native_record = entity['locales'].get(source_locale, {})
            native_origin = native_record.get('translationMetadata', {}).get('fields', {}).get('summary', {}).get('origin')
            expected_source = native_record.get('summary') if native_origin != 'ai' else None

            source_summary = expected_source.encode() if expected_source else None

            if not source_summary:
                counts['missing native source pairs'] += 1
                report['missingNativeSource'].append({'questID': quest_id, 'sourceLocale': source_locale})
            for target_locale in locales:
                state.targetLocale = target_locale.encode()
                target = db.GetQuest(db, int(quest_id), target_locale.encode())
                target_record = entity['locales'].get(target_locale, {})
                target_template = target_record.get('summary')
                if target_record.get('title') and target_template and (
                    not target or target[b'title'] != target_record['title'].encode()
                    or target[b'summary'] != target_template.encode()
                ):
                    counts['failures'] += 1
                    report['failures'].append({
                        'questID': quest_id, 'sourceLocale': source_locale, 'targetLocale': target_locale,
                        'kind': 'targetExport', 'expected': target_template,
                        'actual': target[b'summary'].decode() if target and target[b'summary'] else None,
                    })

                if not target or not target[b'title'] or not target[b'summary']:
                    counts['missing target summary cases'] += 1
                    report['missingTargetSummary'].append({
                        'questID': quest_id, 'sourceLocale': source_locale, 'targetLocale': target_locale,
                    })
                    continue
                templates = target[b'objectiveLines']
                if templates and any(line[b'index'] == 1 and line[b'type'] == b'log'
                                     for _, line in templates.items()):
                    counts['indexed log interception cases'] += 1
                    continue
                native = (format_text(source_summary.decode(), source_locale, source_locale)
                          if source_summary else 'Unmatched native objective sentinel')
                for finished in (False, True):
                    state.objective = lua.table_from({
                        b'type': b'log', b'text': native.encode(), b'numFulfilled': 2,
                        b'numRequired': 7, b'finished': finished,
                    })
                    state.liveObjectives[1] = state.objective
                    result = addon.GetProgressLines(addon, int(quest_id))
                    line = result[1]
                    # A log objective without an indexed template has no structured
                    # association with the summary, so it retains the live text.
                    expected = native
                    if not line or line[b'native'] != native.encode() or line[b'translated'] != expected.encode():
                        counts['failures'] += 1
                        report['failures'].append({
                            'questID': quest_id, 'sourceLocale': source_locale, 'targetLocale': target_locale,
                            'finished': finished, 'expected': expected,
                            'actual': line[b'translated'].decode() if line and line[b'translated'] else None,
                            'nativePreserved': bool(line and line[b'native'] == native.encode()),
                        })
                    counts['native fallback cases'] += 1
                    if target[b'summary'] != target_template.encode() or state.objective[b'text'] != native.encode():
                        counts['failures'] += 1
                        report['failures'].append({
                            'questID': quest_id, 'sourceLocale': source_locale, 'targetLocale': target_locale,
                            'kind': 'mutation', 'finished': finished,
                        })
                if not source_summary:
                    report['fallback'].append({
                        'questID': quest_id, 'sourceLocale': source_locale, 'targetLocale': target_locale,
                    })

    report['counts'] = dict(counts)
    output = ROOT / 'datasources/imports/quest-matrix/summaries.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Quest summary matrix:', dict(counts))
    if report['failures']:
        raise AssertionError(f'{counts["failures"]} failures; first 20:\n'
                             + '\n'.join(str(failure) for failure in report['failures'][:20]))


if __name__ == '__main__':
    main()
