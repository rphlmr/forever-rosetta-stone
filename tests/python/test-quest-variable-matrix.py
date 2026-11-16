"""Exercise maintained quest variables through the Lua formatter across locales."""

import json
import re
import sys
import unittest
from collections import Counter

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES


LABELS = {
    'enUS': (('Mage', 'Human'), ('Mage', 'Human')),
    'deDE': (('Magier', 'Mensch'), ('Magierin', 'Mensch')),
    'esES': (('Mago', 'Humano'), ('Maga', 'Humana')),
    'esMX': (('Mago', 'Humano'), ('Maga', 'Humana')),
    'frFR': (('Mage', 'Humain'), ('Mage', 'Humaine')),
    'itIT': (('Mago', 'Umano'), ('Maga', 'Umana')),
    'ptBR': (('Mago', 'Humano'), ('Maga', 'Humana')),
    'ruRU': (('Маг', 'Человек'), ('Маг', 'Человек')),
    'koKR': (('마법사', '인간'), ('마법사', '인간')),
    'zhCN': (('法师', '人类'), ('法师', '人类')),
    'zhTW': (('法師', '人類'), ('法師', '人類')),
    'csCZ': (('Mág', 'Člověk'), ('Mágyně', 'Člověk')),
    'daDK': (('Magiker', 'Menneske'), ('Magiker', 'Menneske')),
    'hrHR': (('Mag', 'Čovjek'), ('Maga', 'Čovjek')),
    'plPL': (('Mag', 'Człowiek'), ('Magini', 'Człowiek')),
    'svSE': (('Magiker', 'Människa'), ('Magiker', 'Människa')),
    'trTR': (('Büyücü', 'İnsan'), ('Büyücü', 'İnsan')),
    'ukUA': (('Маг', 'Людина'), ('Магиня', 'Людина')),
}
TOKEN = re.compile(
    r'\$[NnRrCc](?![A-Za-z])|\$B|\$b(?![A-Za-z])|'
    r'\$[Gg]([^:;$\n.!?]+):([^:;$\n.!?]+);|'
    r'<((?i:name|race|class|nom|nombre|klasse|classe|clase|raza|volk|имя))>|'
    r'{((?i:name|race|class|nom|nombre|klasse|classe|clase|raza|volk|имя))}|\$(\d+)oa',
)
AMOUNT = re.compile(r'\$(\d+)oa')


def render_expected(text, locale, source, sex, amount_base=100):
    class_name, race_name = LABELS[locale][sex - 2]
    if locale == source:
        class_name, race_name = 'NativeClass', 'NativeRace'
    values = {'name': 'Rosetta', 'class': class_name, 'race': race_name}

    def replace(match):
        token = match.group()
        if token.lower() in ('$n', '$r', '$c'):
            return values[{'n': 'name', 'r': 'race', 'c': 'class'}[token[1].lower()]]
        if token in ('$B', '$b'):
            return '\n'
        if match.group(1) is not None:
            return TOKEN.sub(replace, match.group(1 if sex == 2 else 2))
        if match.group(3) or match.group(4):
            token_name = (match.group(3) or match.group(4)).lower()
            aliases = {'nom': 'name', 'nombre': 'name', 'имя': 'name',
                       'klasse': 'class', 'classe': 'class', 'clase': 'class',
                       'raza': 'race', 'volk': 'race'}
            return values[aliases.get(token_name, token_name)]
        return str(amount_base + int(match.group(5)))

    return TOKEN.sub(replace, text)


def fields(record):
    for key in ('title', 'summary', 'description', 'eventObjectiveLabel'):
        if isinstance(record.get(key), str):
            yield key, record[key]
    for line in record.get('objectiveLines', []):
        if isinstance(line.get('text'), str):
            yield 'objectiveLines.' + str(line['index']), line['text']


def database_field(record, field):
    if not record:
        return None
    if not field.startswith('objectiveLines.'):
        return record[field.encode()]
    index = int(field.split('.')[1])
    for line in (record[b'objectiveLines'] or {}).values():
        if line[b'index'] == index:
            return line[b'text']
    return None


class QuestVariableMatrix(unittest.TestCase):
    def test_catalog_variables(self):
        document = load_catalog(ROOT, 'quests')
        locales = document['locales']
        sources = [locale for locale in locales if locale not in document['rosettaLocales']]
        self.assertEqual(set(locales), set(LABELS))
        lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        metadata = read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc')
        install_metadata(lua, metadata)
        database = load_database(lua)
        lua.execute(b"""
            addon = {}
            function addon:GetTargetLocale() return target end
            function GetLocale() return source end
            function UnitName() return 'Rosetta' end
            function UnitClass() return 'NativeClass', 'MAGE' end
            function UnitRace() return 'NativeRace', 'Human' end
            function UnitSex() return sex end
            objectives = {}
            changedObjectives = {}
            for i = 1, 1000 do
                objectives[i] = { numRequired = 100 + i }
                changedObjectives[i] = { numRequired = 200 + i }
            end
            live = true
            changed = false
            C_QuestLog = { GetQuestObjectives = function()
                if live then return changed and changedObjectives or objectives end
            end }
        """)
        lua.execute(b"assert(loadstring(...))('addon', addon)",
                    (ROOT / 'ForeverRosettaStone/quests/quest-data.lua').read_bytes())
        globals_ = lua.globals()
        addon = globals_[b'addon']
        formatter = addon[b'FormatQuestText']
        counts = Counter()
        failures = []
        missing_targets = []
        missing_sources = []
        quests = document['catalogs']['quests']

        for quest_id, quest in quests.items():
            if quest.get('usageStatus') in EXCLUDED_QUEST_STATUSES:
                counts['excluded'] += 1
                continue
            counts['eligible'] += 1
            records = quest.get('locales', {})
            variable_fields = {}
            for locale, record in records.items():
                for field, text in fields(record):
                    if TOKEN.search(text):
                        variable_fields.setdefault(field, {})[locale] = text
            if not variable_fields:
                continue
            counts['variable_quests'] += 1
            for field, translations in variable_fields.items():
                for target, text in translations.items():
                    record = database[b'GetQuest'](database, int(quest_id), target.encode())
                    actual = database_field(record, field)
                    actual = actual.decode() if actual is not None else None
                    counts['database_fields'] += 1
                    if actual != text:
                        failures.append({'kind': 'database', 'questId': quest_id, 'field': field,
                                         'target': target, 'expected': text, 'actual': actual})
                for source in sources:
                    source_record = database[b'GetQuest'](database, int(quest_id), source.encode())
                    native = database_field(source_record, field)
                    if native is None:
                        missing_sources.append({'questId': quest_id, 'field': field, 'source': source})
                        counts['native_source_field_missing'] += 1
                    elif TOKEN.search(native.decode()):
                        native_text = native.decode()
                        globals_[b'source'] = source.encode()
                        globals_[b'target'] = source.encode()
                        globals_[b'live'] = True
                        globals_[b'changed'] = False
                        for sex in (2, 3):
                            globals_[b'sex'] = sex
                            native_expected = render_expected(native_text, source, source, sex)
                            native_actual = formatter(addon, native, int(quest_id)).decode()
                            counts['native_format_cases'] += 1
                            if native_actual != native_expected:
                                failures.append({'kind': 'native_format', 'questId': quest_id, 'field': field,
                                                 'source': source, 'target': source, 'sex': sex,
                                                 'expected': native_expected, 'actual': native_actual})
                    if source not in translations:
                        available = dict(fields(records.get(source, {})))
                        reason = 'source_field_without_variables' if field in available else 'source_field_missing'
                        counts[reason] += 1
                    globals_[b'source'] = source.encode()
                    for target in locales:
                        text = translations.get(target)
                        if text is None:
                            available = dict(fields(records.get(target, {})))
                            reason = 'target_field_without_variables' if field in available else 'target_field_missing'
                            counts[reason] += 1
                            if field not in available:
                                missing_targets.append({'questId': quest_id, 'field': field,
                                                        'source': source, 'target': target})
                            continue
                        globals_[b'target'] = target.encode()
                        for sex in (2, 3):
                            globals_[b'sex'] = sex
                            globals_[b'live'] = True
                            globals_[b'changed'] = False
                            expected = render_expected(text, target, source, sex)
                            actual = formatter(addon, text.encode(), int(quest_id)).decode()
                            counts['cases'] += 1
                            if actual != expected:
                                counts['mismatches'] += 1
                                failures.append({'kind': 'format', 'questId': quest_id, 'field': field,
                                                 'source': source, 'target': target, 'sex': sex,
                                                 'expected': expected, 'actual': actual})
                            wanted = set(AMOUNT.findall(text))
                            if wanted:
                                globals_[b'changed'] = True
                                changed_expected = render_expected(text, target, source, sex, 200)
                                changed_actual = formatter(addon, text.encode(), int(quest_id)).decode()
                                counts['changed_live_cases'] += 1
                                if changed_actual != changed_expected:
                                    failures.append({'kind': 'changed_live', 'questId': quest_id, 'field': field,
                                                     'source': source, 'target': target, 'sex': sex,
                                                     'expected': changed_expected, 'actual': changed_actual})
                    after_source_record = database[b'GetQuest'](database, int(quest_id), source.encode())
                    after_native = database_field(after_source_record, field)
                    if native != after_native:
                        failures.append({'kind': 'source_mutation', 'questId': quest_id, 'field': field,
                                         'source': source, 'expected': native.decode() if native else None,
                                         'actual': after_native.decode() if after_native else None})
                for target, text in translations.items():
                    record = database[b'GetQuest'](database, int(quest_id), target.encode())
                    after = database_field(record, field)
                    if after != text.encode():
                        failures.append({'kind': 'target_mutation', 'questId': quest_id, 'field': field,
                                         'target': target, 'expected': text,
                                         'actual': after.decode() if after else None})

        report = {'sourceLocales': sources, 'targetLocales': locales, 'counts': dict(counts),
                  'failures': failures, 'missingTargets': missing_targets,
                  'missingNativeSources': missing_sources}
        report_path = ROOT / 'datasources/imports/quest-matrix/variables.json'
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        print(f'Quest variable matrix: {len(sources)} sources x {len(locales)} targets; {dict(counts)}')
        self.assertFalse(failures, f'Mismatches (first 30): {failures[:30]!r}; full report: {report_path}')

    def test_live_amounts_do_not_mutate_catalog_templates(self):
        lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        database = load_database(lua)
        lua.execute(b"""
            addon = {}
            function addon:GetTargetLocale() return 'enUS' end
            function GetLocale() return 'enUS' end
            function UnitName() return playerName end
            function UnitClass() return 'Mage', 'MAGE' end
            function UnitRace() return 'Human', 'Human' end
            function UnitSex() return 2 end
            C_QuestLog = { GetQuestObjectives = function() return liveObjectives end }
            playerName = 'Rosetta'
            liveObjectives = { { numRequired = 9 } }
        """)
        lua.execute(b"assert(loadstring(...))('addon', addon)",
                    (ROOT / 'ForeverRosettaStone/quests/quest-data.lua').read_bytes())
        globals_ = lua.globals()
        addon = globals_[b'addon']
        formatter = addon[b'FormatQuestText']
        before = database[b'GetQuest'](database, 94902, b'enUS')[b'summary']
        self.assertEqual(before, b'Collect $1oa grapes.')
        self.assertEqual(formatter(addon, b'$N needs $1oa', 94902), b'Rosetta needs 9')
        lua.execute(b"playerName = 'Mira'; liveObjectives = { { numRequired = 4 } }")
        self.assertEqual(formatter(addon, b'$N needs $1oa', 94902), b'Mira needs 4')
        self.assertEqual(database[b'GetQuest'](database, 94902, b'enUS')[b'summary'], before)


if __name__ == '__main__':
    unittest.main()
