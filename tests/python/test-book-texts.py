"""Book text ingestion and prepared writes preserve evidence, gaps and accepted wording."""
import hashlib
import io
import json
import runpy
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from datasources.vmangos import loader
from datasources.corpus.translation_corpus import build, open_corpus, verify
from datasources.books.catalogs import prepare, item_title_reuse
from datasources.books.texts import czech_key, turkish_key
from tools.build.runtime_catalog import project_localized_record
from tools.build.database_storage import pack_records
RESYNC = runpy.run_path(str(ROOT / 'tools/catalogs/resync.py'))


class BookTextTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve(); self.imports = self.root / 'datasources/imports'
        self.imports.mkdir(parents=True)
        db = self.imports / 'world.sqlite'; c = sqlite3.connect(db)
        columns = ','.join('Text_loc'+str(i)+' TEXT' for i in range(1, 9))
        names = ','.join('name_loc'+str(i)+' TEXT' for i in range(1, 9))
        c.executescript(f'''
            CREATE TABLE page_text(entry INTEGER,text TEXT,next_page INTEGER);
            CREATE TABLE locales_page_text(entry INTEGER,{columns});
            CREATE TABLE item_template(entry INTEGER,patch INTEGER,name TEXT,page_text INTEGER);
            INSERT INTO item_template VALUES(301,0,'A Book',101);
            CREATE TABLE gameobject_template(entry INTEGER,patch INTEGER,name TEXT,type INTEGER,data0 INTEGER,data7 INTEGER);
            INSERT INTO gameobject_template VALUES(201,0,'A Book',9,101,0);
            CREATE TABLE locales_item(entry INTEGER,{names});
            CREATE TABLE locales_gameobject(entry INTEGER,{names});
            INSERT INTO page_text VALUES(101,'Hello $N.\nKeep $C and $R.',102),(102,'Missing Text',103),(103,'<HTML><BODY></BODY></HTML>',0);
            INSERT INTO locales_page_text(entry,Text_loc2) VALUES(101,'Bonjour $N.\nGardez $C et $R.');
            INSERT INTO locales_gameobject(entry,name_loc2) VALUES(201,'Un livre');
        '''); c.close()
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as archive: archive.writestr('sqlite-dump/mangos.sqlite', db.read_bytes())
        raw = stream.getvalue()
        asset = {'id': 123, 'name': 'db-sqlite-abcdef0.zip',
                 'browser_download_url': 'https://github.com/vmangos/core/releases/download/db_latest/db-sqlite-abcdef0.zip',
                 'digest': 'sha256:' + hashlib.sha256(raw).hexdigest()}
        with patch.object(loader, 'ROOT', self.root), patch.object(loader, 'read_url',
                side_effect=[json.dumps({'assets': [asset]}).encode(), raw]):
            entry = loader.fetch(self.imports / 'vmangos')
        self.config = self.imports / 'sources.json'
        self.config.write_text(json.dumps({'scope': 'book-texts', 'vmangos': [entry]}))
        self.database = self.imports / 'corpus.sqlite'
        build(self.root, self.config, self.database)

    def test_source_bytes_placeholders_provenance_and_missing_pages(self):
        output = self.imports / 'prepared'; result = prepare(self.root, self.database, output)
        self.assertEqual(result['counts']['missingEnglishEntities'], 2)
        manifest = json.loads((output / 'manifest.json').read_text())
        row = next(f for f in manifest['files'] if f['path'] == 'catalogs/bookpages/101.json')
        page = json.loads((output / row['result']).read_text())
        self.assertEqual(page['locales']['frFR']['description'], 'Bonjour $N.\nGardez $C et $R.')
        meta = page['locales']['frFR']['translationMetadata']['fields']['description']
        self.assertEqual((meta['source'], meta['sourceLocale'], meta['origin']), ('vmangos', 'frFR', 'community'))
        self.assertEqual(meta['sourceTextSha256'], hashlib.sha256(page['locales']['frFR']['description'].encode()).hexdigest())
        self.assertNotIn('ptBR', page['locales'])
        self.assertFalse(any(f['path'].endswith('/102.json') for f in manifest['files']))
        self.assertEqual(RESYNC['apply'](self.root, output)['writtenFiles'], 4)
        self.assertEqual(RESYNC['verify'](self.root, output)['verifiedFiles'], 4)
        # Prepared application is idempotent and creates only the two new catalog kinds.
        self.assertEqual(RESYNC['apply'](self.root, output)['writtenFiles'], 0)

    def test_manual_translation_is_preserved_and_repeat_prepare_is_empty(self):
        first = self.imports / 'first'; prepare(self.root, self.database, first); RESYNC['apply'](self.root, first)
        path = self.root / 'catalogs/bookpages/101.json'; page = json.loads(path.read_text())
        page['locales']['frFR']['description'] = 'Manual correction'
        path.write_text(json.dumps(page))
        output = self.imports / 'next'; prepare(self.root, self.database, output)
        held = json.loads((output / 'held-source-conflicts.json').read_text())
        self.assertTrue(any(r['reason'] == 'preserveAcceptedTranslation' for r in held))
        RESYNC['apply'](self.root, output)
        self.assertEqual(json.loads(path.read_text())['locales']['frFR']['description'], 'Manual correction')

    def test_changed_prepared_result_and_concurrent_new_file_fail_before_writes(self):
        output = self.imports / 'prepared'; prepare(self.root, self.database, output)
        manifest = json.loads((output / 'manifest.json').read_text()); target = self.root / manifest['files'][-1]['path']
        target.parent.mkdir(parents=True); target.write_text('concurrent')
        with self.assertRaisesRegex(ValueError, 'Concurrent catalog edit'):
            RESYNC['apply'](self.root, output)
        self.assertFalse((self.root / manifest['files'][0]['path']).exists())

    def test_source_corruption_blocks_application(self):
        output = self.imports / 'prepared'; prepare(self.root, self.database, output)
        (self.imports / 'vmangos/mangos.sqlite').write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'Source changed'):
            RESYNC['apply'](self.root, output)

    def test_runtime_projection_has_body_ai_flag_and_no_invented_title(self):
        page = {'locales': {'enUS': {'description': 'English', 'translationMetadata': {'fields': {'description': {'origin': 'community'}}}},
                            'plPL': {'description': 'Polski', 'translationMetadata': {'fields': {'description': {'origin': 'ai'}}}}}}
        projected = project_localized_record('bookpages', 999, page, 'plPL', {})
        self.assertEqual(projected, {'description': 'Polski', 'hasAITranslation': True})
        packed = pack_records('bookpages', [(999, projected)])
        self.assertEqual(packed[1], {1: 'Polski'})
        self.assertEqual(len(packed), 3)

    def test_vmangos_ai_evidence_is_scoped_to_matching_book_page(self):
        from tools.catalogs.import_policy import OfficialEvidence, ai_block_reason
        evidence = OfficialEvidence(self.database, self.root)
        english = 'Hello $N.\nKeep $C and $R.'
        self.assertTrue(evidence.allows('bookpages', 101, 'description', english))
        self.assertFalse(evidence.allows('quests', 101, 'description', english))
        self.assertFalse(evidence.allows('items', 101, 'description', english))
        self.assertFalse(evidence.allows('bookpages', 102, 'description', english))
        self.assertFalse(evidence.allows('bookpages', 101, 'description', 'Changed meaning'))
        self.assertEqual(ai_block_reason('frFR', 'bookpages', 101, 'description', english, evidence), 'officialLocaleNeverAuthored')
        self.assertIsNone(ai_block_reason('daDK', 'bookpages', 101, 'description', english, evidence))

    def test_hash_ports_are_stable_and_preserve_source_token_case(self):
        self.assertEqual(czech_key('Hello $N!'), czech_key('hello'))
        self.assertEqual(turkish_key('A\r\n\r\nB'), turkish_key('a $B b'))
        self.assertNotEqual(turkish_key('Hello $C'), turkish_key('Hello $c'))

    def test_item_title_reuse_requires_exact_owner_context_and_keeps_origin(self):
        path = self.root / 'catalogs/items/301.json'
        path.parent.mkdir(parents=True)
        ai = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        community = {'origin': 'community', 'source': 'existingProvider', 'sourceLocale': 'ukUA'}
        path.write_text(json.dumps({'locales': {
            'enUS': {'name': 'A Book'},
            'daDK': {'name': 'En bog', 'translationMetadata': {'fields': {'name': ai}}},
            'ukUA': {'name': 'Книга', 'translationMetadata': {'fields': {'name': community}}},
            'frFR': {'name': 'AI official', 'translationMetadata': {'fields': {'name': ai}}},
            'itIT': {'name': 'No provenance'}}}))
        owner = {'ownerKind': 'item', 'ownerId': 301}
        source, reused = item_title_reuse(self.root, 'A Book', owner)
        self.assertEqual(source, ('catalogs/items/301.json', hashlib.sha256(path.read_bytes()).hexdigest()))
        self.assertEqual(reused, {'daDK': ('En bog', ai), 'ukUA': ('Книга', community)})
        self.assertEqual(item_title_reuse(self.root, 'Changed title', owner), (None, {}))
        self.assertEqual(item_title_reuse(self.root, 'A Book', {'ownerKind': 'gameobject', 'ownerId': 301}), (None, {}))

    def test_reused_title_input_change_blocks_application_before_writes(self):
        path = self.root / 'catalogs/items/301.json'
        path.parent.mkdir(parents=True)
        metadata = {'origin': 'community', 'source': 'existingProvider', 'sourceLocale': 'ukUA'}
        path.write_text(json.dumps({'locales': {'enUS': {'name': 'A Book'},
            'ukUA': {'name': 'Книга', 'translationMetadata': {'fields': {'name': metadata}}}}}))
        output = self.imports / 'reused'; prepare(self.root, self.database, output)
        manifest = json.loads((output / 'manifest.json').read_text())
        self.assertIn('catalogs/items/301.json', manifest['policyInputs'])
        book = next(f for f in manifest['files'] if f['path'] == 'catalogs/books/101.json')
        record = json.loads((output / book['result']).read_text())['locales']['ukUA']
        self.assertEqual(record, {'name': 'Книга', 'translationMetadata': {'fields': {'name': metadata}}})
        path.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'Policy source changed'):
            RESYNC['apply'](self.root, output)
        self.assertFalse((self.root / 'catalogs/books/101.json').exists())

    def test_book_newline_before_literal_hours_is_not_a_number_placeholder(self):
        batch = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-batch.py'))
        source = 'Day 1:$B4:00pm - upper camp$B$N'
        target = 'Dag 1:$B16:00 - øvre lejr$B$N'
        token = batch['GET_BOOK_TOKENS']
        self.assertEqual(token(source), token(target))
        self.assertEqual(token(source), token('Giorno 1:$Bdalle 16:00$B$N'))
        self.assertNotEqual(token(source), token(target.replace('$B16', '16')))
        self.assertNotEqual(token(source), token(target.replace('$N', '$R')))
        self.assertNotEqual(token(source + '${$B1}'), token(target + '${$B2}'))
        self.assertNotEqual(batch['GET_TOKENS']('$B4'), batch['GET_TOKENS']('$B16'))


if __name__ == '__main__': unittest.main()
