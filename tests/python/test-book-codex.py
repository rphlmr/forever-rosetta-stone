"""Book source projection and reconciliation use typed IDs and keep unresolved evidence."""
import hashlib
import io
import json
import sqlite3
import runpy
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from datasources.books.codex import reconcile, store, export
from datasources.vmangos import loader
from datasources.eg_link import loader as eg_loader
from datasources.corpus.translation_corpus import CorpusBuilder, build, open_corpus, verify


class BookCodexTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.imports = self.root / 'datasources/imports'
        self.imports.mkdir(parents=True)
        self.db = self.imports / 'fixture.sqlite'
        db = sqlite3.connect(self.db)
        db.executescript('''
            CREATE TABLE item_template(entry INTEGER,patch INTEGER,name TEXT,page_text INTEGER);
            INSERT INTO item_template VALUES(11,0,'Old item',101),(11,10,'Vanilla item',101),
                (12,0,'Removed before patch 10',101),(12,5,'No longer readable',0),
                (13,0,'Future version',101),(13,11,'Not yet applicable',105);
            CREATE TABLE gameobject_template(entry INTEGER,patch INTEGER,name TEXT,type INTEGER,data0 INTEGER,data7 INTEGER);
            INSERT INTO gameobject_template VALUES(11,0,'Different namespace',9,103,0),
                (14,0,'Tablet',10,0,105),(15,0,'Missing',9,999,0),
                (16,0,'Former book',9,101,0),(16,8,'Chest',3,101,0);
            CREATE TABLE page_text(entry INTEGER,text TEXT,next_page INTEGER);
            INSERT INTO page_text VALUES(101,'DO NOT IMPORT THIS BODY',102),(102,'PRIVATE BODY',0),
                (103,'Loop',104),(104,'Loop',103),(105,'Shared',102);
        ''')
        db.close()
        archive = io.BytesIO()
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('sqlite-dump/mangos.sqlite', self.db.read_bytes())
        self.raw = archive.getvalue()
        self.asset = {'id': 123, 'name': 'db-sqlite-abcdef0.zip',
                      'browser_download_url': 'https://github.com/vmangos/core/releases/download/db_latest/db-sqlite-abcdef0.zip',
                      'digest': 'sha256:' + hashlib.sha256(self.raw).hexdigest()}
        self.release = {'assets': [self.asset]}
        with patch.object(loader, 'ROOT', self.root), patch.object(loader, 'read_url',
                side_effect=[json.dumps(self.release).encode(), self.raw]):
            self.vm = loader.fetch(self.imports / 'vmangos')
        self.config = {'vmangos': [self.vm]}

    def reconcile(self):
        builder = CorpusBuilder(self.root, sqlite3.connect(':memory:'))
        try:
            return reconcile(self.root, self.config, builder.read), builder.input_hashes
        finally:
            builder.db.close()

    def wago(self, rows):
        directory = self.imports / 'wago'; directory.mkdir()
        raw = ('ID,Display_lang,Description_lang,PageID\n' + '\n'.join(rows) + '\n').encode()
        (directory / 'items.csv').write_bytes(raw)
        (directory / 'manifest.json').write_text(json.dumps({'build': '1.60.1.70938', 'results': [
            {'table': 'ItemSparse', 'locale': 'enUS', 'file': 'items.csv', 'status': 'downloaded',
             'url': 'https://wago.tools/example', 'sha256': hashlib.sha256(raw).hexdigest()}]}))
        self.config['wago'] = [str(directory.relative_to(self.root))]

    def eg(self, build, records):
        path = self.imports / ('objects-' + build + '.json')
        path.write_text(json.dumps({'meta': {'schemaVersion': 1, 'product': 'wowf', 'dataset': 'object_details',
            'locale': 'enUS', 'clientBuild': build, 'license': 'CC BY 4.0', 'attribution': 'Efficient Games'},
            'objects': records}))
        self.config.setdefault('egBooks', []).append({'path': str(path.relative_to(self.root)), 'revision': 'a' * 40})

    def test_projection_selects_patch_before_filtering_and_never_projects_bodies(self):
        projection = json.loads((self.imports / 'vmangos/identities.json').read_text())
        owners = {(r['kind'], r['id']): r for r in projection['owners']}
        self.assertEqual(owners['item', 11]['title'], 'Vanilla item')
        self.assertEqual(owners['item', 13]['firstPageId'], 101)
        self.assertNotIn(('item', 12), owners)
        self.assertNotIn(('object', 16), owners)
        self.assertEqual(owners['object', 14]['firstPageId'], 105)
        self.assertNotIn('DO NOT IMPORT', json.dumps(projection))

    def test_reconciliation_keeps_namespaces_conflicts_cycles_missing_and_shared_pages(self):
        self.wago(['11,Forever item,,105', '13,Removed,,0', '18,New book,,800'])
        self.eg('1.60.1.70888', {'11': {'name': 'Old object', 'type': 9, 'data': [101]}})
        self.eg('1.60.1.70938', {'11': {'name': 'Observed object', 'type': 9, 'data': [103]}})
        document, inputs = self.reconcile()
        books = {b['firstPageId']: b for b in document['books']}
        item = next(o for o in books[105]['owners'] if o['kind'] == 'item')
        self.assertEqual(item['title'], 'Forever item')
        self.assertEqual(set(item['flags']), {'titleConflict', 'firstPageConflict'})
        self.assertEqual(books[103]['owners'][0]['status'], 'foreverObserved')
        self.assertEqual(books[103]['issues'][0]['type'], 'cycle')
        self.assertEqual(books[999]['issues'][0], {'type': 'missingPage', 'pageId': 999})
        self.assertEqual(document['excludedOwners'][0]['id'], 13)
        self.assertFalse(books[105]['foreverPageSequenceVerified'])
        self.assertIn('datasources/imports/vmangos/mangos.sqlite', inputs)
        self.assertNotIn('DO NOT IMPORT', json.dumps(document))

    def test_latest_nonreadable_observation_does_not_resurrect_vanilla_owner(self):
        self.eg('1.60.1.70938', {'11': {'name': 'Now a chest', 'type': 3, 'data': [103]}})
        document, _ = self.reconcile()
        self.assertEqual(document['excludedOwners'][0]['kind'], 'object')
        self.assertEqual(document['excludedOwners'][0]['id'], 11)

    def test_tampered_snapshot_fails(self):
        (self.imports / 'vmangos/identities.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            self.reconcile()

    def test_wago_path_escape_and_same_build_conflicts_fail(self):
        self.wago(['11,Book,,101'])
        manifest = self.imports / 'wago/manifest.json'
        data = json.loads(manifest.read_text()); data['results'][0]['file'] = '../fixture.sqlite'
        manifest.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'input path'):
            self.reconcile()
        del self.config['wago']
        self.eg('1.60.1.70938', {'11': {'name': 'Book', 'type': 9, 'data': [101]}})
        entry = self.config['egBooks'][0]
        other = self.imports / 'contradiction.json'
        data = json.loads((self.root / entry['path']).read_text()); data['objects']['11']['name'] = 'Conflict'
        other.write_text(json.dumps(data))
        self.config['egBooks'].append({**entry, 'path': str(other.relative_to(self.root))})
        with self.assertRaisesRegex(ValueError, 'same build'):
            self.reconcile()

    def test_offline_corpus_roundtrip_verifies_codex_inputs(self):
        config = self.imports / 'sources.json'; config.write_text(json.dumps(self.config))
        output = self.imports / 'corpus.sqlite'
        metadata = self.root / 'catalogs/quests/metadata.json'
        metadata.parent.mkdir(parents=True)
        metadata.write_text(json.dumps({'document': {'locales': ['enUS']}}))
        with patch.object(CorpusBuilder, 'catalogs', lambda builder: builder.read(metadata)):
            build(self.root, config, output)
        connection = open_corpus(output)
        try:
            document = export(connection)
            self.assertEqual(document['scope'], 'identity-only')
            self.assertEqual(document['summary']['owners'], 5)
            self.assertTrue(verify(connection, self.root)['valid'])
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM records").fetchone()[0], 0)
            (self.imports / 'vmangos/mangos.sqlite').write_bytes(b'changed')
            self.assertFalse(verify(connection, self.root)['valid'])
        finally:
            connection.close()

    def test_identity_only_build_never_reads_catalogs_or_translation_records(self):
        self.config['scope'] = 'book-identities'
        config = self.imports / 'sources.json'; config.write_text(json.dumps(self.config))
        unrelated = self.root / 'catalogs/items/unrelated.json'
        unrelated.parent.mkdir(parents=True); unrelated.write_text('not a catalog to parse')
        output = self.imports / 'identity.sqlite'
        with patch.object(CorpusBuilder, 'catalogs', side_effect=AssertionError('catalog scan')), \
                patch.object(CorpusBuilder, 'wago', side_effect=AssertionError('text import')):
            build(self.root, config, output)
        connection = open_corpus(output)
        try:
            self.assertTrue(verify(connection, self.root)['valid'])
            self.assertEqual(connection.execute('SELECT COUNT(*) FROM records').fetchone()[0], 0)
            self.assertFalse(any(row[0].startswith('catalogs/') for row in connection.execute('SELECT path FROM inputs')))
            first = export(connection)
        finally:
            connection.close()
        build(self.root, config, self.imports / 'rebuilt.sqlite')
        connection = open_corpus(self.imports / 'rebuilt.sqlite')
        try:
            self.assertEqual(export(connection), first)
        finally:
            connection.close()

    def test_refresh_registers_vmangos_and_publishes_verified_codex(self):
        refresh = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'datasources/refresh.py'))
        template = self.root / 'datasources/corpus/sources.json'
        template.parent.mkdir(); template.write_text('{}')
        output = self.imports / 'run'
        with patch.dict(refresh['refresh'].__globals__, {'ROOT': self.root}), \
                patch.object(loader, 'fetch', return_value=self.vm), \
                patch.object(CorpusBuilder, 'catalogs', side_effect=AssertionError('catalog scan')):
            refresh['refresh'](output, self.root / '.env', sources=['vmangos'], book_codex_only=True)
        complete = json.loads((output / 'complete.json').read_text())
        self.assertTrue(complete['verified'])
        self.assertEqual(json.loads((output / 'pins.json').read_text())['vmangos'], self.vm['pin'])
        self.assertEqual(json.loads((output / 'book-codex.json').read_text())['scope'], 'identity-only')

    def test_default_identity_refresh_fetches_only_relevant_sources(self):
        refresh = runpy.run_path(str(Path(__file__).resolve().parents[2] / 'datasources/refresh.py'))
        template = self.root / 'datasources/corpus/sources.json'
        template.parent.mkdir(); template.write_text('{}')
        def wago_fetch(output, pin, tables, locales):
            self.assertEqual((tables, locales), (['ItemSparse'], ['enUS']))
            output.mkdir()
            raw = b'ID,Display_lang,PageID\n11,Forever item,101\n'
            (output / 'items.csv').write_bytes(raw)
            (output / 'manifest.json').write_text(json.dumps({'build': '1.60.1.70938', 'results': [
                {'table': 'ItemSparse', 'locale': 'enUS', 'file': 'items.csv', 'status': 'downloaded',
                 'sha256': hashlib.sha256(raw).hexdigest()}]}))
            return '1.60.1.70938'
        self.eg('1.60.1.70938', {'11': {'name': 'Object', 'type': 9, 'data': [103]}})
        with patch.dict(refresh['refresh'].__globals__, {'ROOT': self.root}), \
                patch.object(loader, 'fetch', return_value=self.vm), \
                patch.object(refresh['wago'], 'fetch', side_effect=wago_fetch), \
                patch.object(refresh['eg_link'], 'latest_revision', return_value='a' * 40), \
                patch.object(refresh['eg_link'], 'fetch_book_objects', return_value=self.config['egBooks']) as books, \
                patch.object(refresh['eg_link'], 'fetch', side_effect=AssertionError('NPC/item fetch')), \
                patch.object(CorpusBuilder, 'catalogs', side_effect=AssertionError('catalog scan')):
            refresh['refresh'](self.imports / 'run', self.root / '.env', book_codex_only=True)
        self.assertEqual(books.call_args.args[1], 'a' * 40)
        config = json.loads((self.imports / 'run/sources.json').read_text())
        self.assertEqual(config['egLink'], [])
        self.assertEqual(config['scope'], 'book-identities')

    def test_eg_collector_pins_all_sparse_object_snapshots_and_rejects_other_datasets(self):
        builds = ['1.60.1.70888', '1.60.1.70938']
        index = {'products': {'wowf': {build: {'object_details.enUS': {}} for build in builds}}}
        payloads = [{'meta': {'clientBuild': build, 'locale': 'enUS', 'product': 'wowf',
            'dataset': 'object_details', 'schemaVersion': 1}, 'objects': {}} for build in builds]
        with patch.object(eg_loader, 'ROOT', self.root), patch.object(eg_loader, 'read_url',
                side_effect=[json.dumps(x).encode() for x in [index, *payloads]]):
            entries = eg_loader.fetch_book_objects(self.imports / 'eg', 'a' * 40)
        self.assertEqual(len(entries), 2)
        self.assertTrue(all(e['indexPath'].endswith('/index.json') for e in entries))
        with self.assertRaisesRegex(ValueError, 'pinned EG'):
            eg_loader.fetch_book_objects(self.imports / 'unpinned', 'main')
        payloads[0]['meta']['dataset'] = 'quests'
        with patch.object(eg_loader, 'read_url', side_effect=[json.dumps(x).encode() for x in [index, payloads[0]]]):
            with self.assertRaisesRegex(ValueError, 'snapshot identity'):
                eg_loader.fetch_book_objects(self.imports / 'wrong-dataset', 'a' * 40)

    def test_asset_hash_mismatch_and_pinned_asset_replay(self):
        with patch.object(loader, 'ROOT', self.root), patch.object(loader, 'read_url', side_effect=[
                json.dumps(self.release).encode(), b'corrupt']):
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                loader.fetch(self.imports / 'bad')
        with patch.object(loader, 'ROOT', self.root), patch.object(loader, 'read_url', side_effect=[
                json.dumps(self.release).encode(), json.dumps(self.asset).encode(), self.raw]) as network:
            result = loader.fetch(self.imports / 'replay', self.vm['pin'])
            self.assertEqual(result['pin'], self.vm['pin'])
            self.assertIn('/releases/assets/123', network.call_args_list[1].args[0])


if __name__ == '__main__':
    unittest.main()
