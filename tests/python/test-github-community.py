"""Offline regression checks for active community sources and typed data boundaries."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import io
import json
import runpy
import sqlite3
import tempfile
import unittest
from unittest.mock import patch, Mock
from zipfile import ZipFile
from datasources import github_community as shared
from datasources import curseforge
from datasources.classic_ua import loader as ua
from datasources.czech_forever import loader as cz
from datasources.polish_forever import loader as pl
from datasources.corpus.translation_corpus import CorpusBuilder, SCHEMA
from datasources.lua_data import assignments

ROOT = Path(__file__).resolve().parents[2]
refresh = runpy.run_path(str(ROOT / 'datasources/refresh.py'))


def archive(files):
    result = io.BytesIO()
    with ZipFile(result, 'w') as zip:
        for path, text in files.items():
            zip.writestr(path, text)
    return result.getvalue()


class GithubCommunityTests(unittest.TestCase):
    def test_active_sources_include_public_curseforge_projects(self):
        self.assertTrue({'classic-ua', 'czech-forever', 'polish-forever', 'wowita-quests',
                         'wow-forever-it', 'wow-forver-italiano', 'wow-lang', 'questtranslator-tr',
                         'forever-translated-polish', 'varlden-av-krigskraft', 'forever-tr'}
                        == set(refresh['COMMUNITY_SOURCES']))
        self.assertEqual(set(refresh['DEFAULT_PROVIDERS']),
                         {'wago', 'questie', 'blizzard', 'eg-link'} | set(refresh['COMMUNITY_SOURCES']))
        self.assertEqual(set(refresh['PROVIDERS']) - set(refresh['DEFAULT_PROVIDERS']),
                         {'vmangos', 'book-archives'})
        self.assertTrue(all(module.SPEC.get('repository') or module.SPEC.get('projectID') for module in refresh['COMMUNITY_SOURCES'].values()))

    def test_italian_alias_tables_and_questit_fingerprints_are_retained(self):
        from datasources.wowita_quests import loader as wowita
        from datasources.wow_forever_it import loader as wfit
        from datasources.wow_forver_italiano import loader as wfi
        rows, _ = wowita.normalize('QuestData_it.lua',
            'QTR_QuestData={["7"]={Title="Titolo",Description="Testo YOUR_NAME"}}')
        self.assertEqual({row['field'] for row in rows}, {'title', 'description'})
        self.assertTrue(all('crossVersionContext:checkForeverMeaning' in row['flags'] for row in rows))
        rows, _ = wfit.normalize('WoWForeverIT/Locales/QuestIT094-Forever.lua',
            'local db=WoWForeverIT_QuestIT.DataIT; db[7]=db[7] or {}; '
            'db[7]["text#variant"]={it="Testo",enHash={"abcd"}}')
        self.assertEqual(rows[0]['field'], 'description')
        self.assertEqual(rows[0]['context']['englishFingerprints'], {1: 'abcd'})
        self.assertIn('upstreamFingerprint:reviewBeforeReuse', rows[0]['flags'])
        rows, _ = wfi.normalize('Addon/Data/CompleteSpellDescription001.lua',
            'ns.data.spellDescriptionOverrides=ns.data.spellDescriptionOverrides or {}; '
            'local records={[7]={en="English",description="Italiano"}}')
        self.assertEqual((rows[0]['kind'],rows[0]['field'],rows[0]['english']), ('spells','description','English'))

    def test_multilingual_source_keeps_locale_identity(self):
        from datasources.wow_lang import loader as wowlang
        for folder, locale in (('WoWPL','plPL'),('WoWTR','trTR'),('WoWUA','ukUA')):
            rows, _ = wowlang.normalize(folder+'/Translations/QuestData.lua',
                                       'QTR_QuestData={["7"]={Title="Translated"}}')
            self.assertEqual(rows[0]['locale'], locale)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            raw = archive({'WoWLang-commit/WoWPL/Translations/QuestData_PL.lua':
                           'QTR_QuestData={["7"]={Title="Nazwa"}}',
                           'WoWLang-commit/WoWTR/Translations/QuestData_TR.lua':
                           'QTR_QuestData={["7"]={Title="Başlık"}}'})
            with patch.object(shared,'ROOT',root), patch.object(shared,'github_json',return_value={'sha':'a'*40}), \
                    patch.object(shared,'read_url',return_value=raw):
                entry=wowlang.fetch(root/'datasources/imports/wow-lang')
            db=sqlite3.connect(':memory:');db.row_factory=sqlite3.Row;db.executescript(SCHEMA)
            builder=CorpusBuilder(root,db);builder.community(entry)
            self.assertEqual({row[0] for row in db.execute('SELECT locale FROM records')},{'plPL','trTR'})
            db.close()

    def test_literal_parsing_and_field_meanings(self):
        self.assertEqual(list(assignments('local d=CF.quests; d[7]={t=[=[Title]=],a="Body\\ntext"}', [('d',)])),
                         [(['d', 7], {'t': 'Title', 'a': 'Body\ntext'})])
        with self.assertRaises(ValueError):
            list(assignments('d[7]={t=execute()}', [('d',)]))
        rows, _ = ua.normalize('entries/forever/quest_both.lua', 'local quest_both={[7]={"Назва","Опис","Мета",ai=true,en="Title"}}')
        self.assertEqual({row['field'] for row in rows}, {'title', 'description', 'summary'})
        self.assertTrue(all(row['origin'] == 'ai' for row in rows))
        rows, _ = cz.normalize('Data/Quests01.lua', 'd[7]={t="Název",a={"male","female"}}')
        self.assertEqual(len(rows), 3)
        self.assertTrue(all('upstreamGenderVariants' in row['flags'] for row in rows if row['field'] == 'description'))
        self.assertEqual({row['text'] for row in rows if row['field'] == 'description'}, {'male', 'female'})
        rows, _ = cz.normalize('Data/Quests01.lua', 'd[7]={a={"same","same"}}')
        self.assertEqual(len(rows), 1)
        self.assertNotIn('upstreamGenderVariants', rows[0]['flags'])
        rows, lookups = pl.normalize('Data/Items.lua', 'PF.Text.Items={[123456]="Nazwa"}')
        self.assertEqual(rows, [])
        self.assertEqual(lookups[0]['algorithm'], 'polish-hash')

    def test_pinned_archive_flows_into_sqlite_without_network(self):
        raw = archive({'ClassicUA-commit/entries/classic/item.lua': 'local items={[7]={"Old",en="Item"}}',
                       'ClassicUA-commit/entries/forever/item.lua': 'local items={[7]={"Нове",en="Item",ai=true}}',
                       'ClassicUA-commit/COPYING': 'License'})
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            with patch.object(shared, 'ROOT', root), patch.object(shared, 'github_json', return_value={'sha': 'a' * 40}), \
                    patch.object(shared, 'read_url', return_value=raw) as read:
                entry = ua.fetch(root / 'datasources/imports/ua')
            self.assertIn('a' * 40, read.call_args.args[0])
            db = sqlite3.connect(':memory:')
            db.row_factory = sqlite3.Row
            db.executescript(SCHEMA)
            builder = CorpusBuilder(root, db)
            builder.community(entry)
            row = db.execute('SELECT entity_id,text,origin,evidence FROM records').fetchone()
            self.assertEqual(tuple(row), ('7', 'Нове', 'ai', 'sourceSnapshot'))
            self.assertTrue(any(path.endswith('COPYING') for path in builder.input_hashes))
            (root / entry['path'] / 'raw/entries/forever/item.lua').write_text('tampered')
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                builder.community(entry)
            db.close()

    def test_polish_hashes_resolve_owned_ids_not_hash_numbers(self):
        hashed = shared.polish_hash('English item')
        raw = archive({'PolishForever-commit/Data/Items.lua': 'PF.Text.Items={[' + str(hashed) + ']="Przedmiot"}'})
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            with patch.object(shared, 'ROOT', root), patch.object(shared, 'github_json', return_value={'sha': 'b' * 40}), \
                    patch.object(shared, 'read_url', return_value=raw):
                entry = pl.fetch(root / 'datasources/imports/pl')
            db = sqlite3.connect(':memory:')
            db.row_factory = sqlite3.Row
            db.executescript(SCHEMA)
            builder = CorpusBuilder(root, db)
            builder.add('items', '42', 'enUS', 'name', 'English item', 'English item', 'original', 'sourceSnapshot', {}, root / 'english')
            builder.community(entry)
            self.assertEqual(tuple(db.execute("SELECT entity_id,origin FROM records WHERE locale='plPL'").fetchone()), ('42', 'ai'))
            db.close()

    def test_czech_uses_pinned_main_curseforge_archive_without_inventing_text_authorship(self):
        pin = {'projectID': cz.SPEC['projectID'], 'fileID': 1234567, 'fileName': 'CzechForever-0.7.3.zip'}
        raw = archive({'CzechForever/Data/Quests01.lua': 'd[7]={t="Název"}'})
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(shared, 'ROOT', Path(tmp).resolve()), patch.object(curseforge, 'read_url', return_value=raw) as read:
                entry = cz.fetch(Path(tmp).resolve() / 'snapshot', pin)
            self.assertEqual(entry['pin']['fileID'], 1234567)
            self.assertTrue(read.call_args.args[0].endswith('CzechForever-0.7.3.zip'))
            manifest = json.loads((Path(tmp) / 'snapshot/manifest.json').read_text())
            self.assertEqual(manifest['origin'], 'community')

    def test_selective_refresh_registers_community_pins_and_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp).resolve()
            config = root / 'datasources/corpus/sources.json'
            config.parent.mkdir(parents=True)
            config.write_text('{}')
            output = root / 'datasources/imports/run'
            entry = {'path': 'datasources/imports/run/classic-ua', 'source': 'classicUA', 'pin': {'revision': 'a' * 40}}
            changes = {'ROOT': root, 'build': Mock(), 'open_corpus': Mock(return_value=Mock()),
                       'verify': Mock(return_value={'valid': True})}
            with patch.dict(refresh['refresh'].__globals__, changes), patch.object(ua, 'fetch', return_value=entry), \
                    patch.object(refresh['blizzard'], 'credentials') as credentials:
                refresh['refresh'](output, root / '.env', sources=['classic-ua'])
            credentials.assert_not_called()
            self.assertEqual(json.loads((output / 'sources.json').read_text())['classicUA'], [entry])
            self.assertEqual(json.loads((output / 'pins.json').read_text())['classicUA'], entry['pin'])


if __name__ == '__main__':
    unittest.main()
