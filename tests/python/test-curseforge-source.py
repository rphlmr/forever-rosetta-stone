"""Public CurseForge discovery, replay integrity and typed source normalization."""
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from datasources import curseforge, github_community
from datasources.corpus.translation_corpus import CorpusBuilder, SCHEMA
from datasources.forever_translated_polish import loader as pl
from datasources.varlden_av_krigskraft import loader as sv
from datasources.forever_tr import loader as tr


class CurseForgeSourceTests(unittest.TestCase):
    def setUp(self):
        self.spec = {'projectID': 123, 'archivePattern': r'Example-(\d+\.\d+\.\d+)\.zip'}
        self.pin = {'projectID': 123, 'fileID': 1234567, 'fileName': 'Example-1.2.3.zip'}
        self.url = 'https://edge.forgecdn.net/files/1234/567/Example-1.2.3.zip'
        self.file = {'projectId': 123, 'id': 1234567, 'fileName': 'Example-1.2.3.zip',
                     'status': 4, 'releaseType': 1, 'gameVersionTypeIds': [88568],
                     'dateCreated': '2026-11-14T00:00:00Z', 'fileLength': 7}

    def response(self, rows, page=0, total=None):
        return json.dumps({'data': rows, 'pagination': {'index': page, 'pageSize': 50,
                           'totalCount': len(rows) if total is None else total}}).encode()

    def test_explicit_pin_needs_only_public_cdn_and_checks_hash(self):
        with patch.object(curseforge, 'read_url', return_value=b'archive') as read:
            identity, url, raw = curseforge.download(self.spec, self.pin)
        read.assert_called_once_with(self.url)
        self.assertEqual((identity['fileID'], identity['tag'], url, raw), (1234567, '1.2.3', self.url, b'archive'))
        with self.assertRaisesRegex(ValueError, 'project mismatch'):
            curseforge.download(self.spec, {**self.pin, 'projectID': 456})
        with patch.object(curseforge, 'read_url', return_value=b'changed'):
            with self.assertRaisesRegex(ValueError, 'hash changed'):
                curseforge.download(self.spec, {**self.pin, 'sha256': hashlib.sha256(b'original').hexdigest()})

    def test_discovery_selects_latest_date_and_excludes_unapproved_voice_beta_and_other_flavors(self):
        base = self.file
        rows = [base, {**base, 'id': 1234560, 'dateCreated': '2026-11-15T00:00:00Z'},
                {**base, 'id': 9, 'fileName': 'VoicePack.zip'},
                {**base, 'id': 10, 'releaseType': 2}, {**base, 'id': 11, 'projectId': 456},
                {**base, 'id': 12, 'status': 2}, {**base, 'id': 13, 'gameVersionTypeIds': [1]},
                {**base, 'id': 14, 'isEarlyAccessContent': True}]
        with patch.object(curseforge, 'read_url', side_effect=[self.response(rows), b'archive']) as read:
            identity, url, _ = curseforge.download(self.spec)
        self.assertEqual(identity['fileID'], 1234560)
        self.assertIn('www.curseforge.com/api/v1/mods/123/files', read.call_args_list[0].args[0])
        self.assertNotIn('x-api-key', read.call_args_list[0].kwargs['headers'])
        self.assertTrue(url.endswith('/1234/560/Example-1.2.3.zip'))

    def test_discovery_paginates_and_never_reuses_an_old_latest(self):
        page = [{**self.file, 'id': index+1, 'fileName': 'Voice.zip'} for index in range(50)]
        with patch.object(curseforge, 'read_url', side_effect=[self.response(page, total=51),
                self.response([self.file], page=1, total=51)]) as read:
            self.assertEqual(curseforge.latest(self.spec)['fileID'], 1234567)
        self.assertIn('pageIndex=1', read.call_args_list[1].args[0])
        with patch.object(curseforge, 'read_url', side_effect=OSError('unavailable')):
            with self.assertRaises(OSError):
                curseforge.download(self.spec)
        with patch.object(curseforge, 'read_url', return_value=self.response([])):
            with self.assertRaisesRegex(ValueError, 'No approved'):
                curseforge.download(self.spec)

    def test_invalid_filename_and_download_size_fail(self):
        with self.assertRaises(ValueError):
            curseforge.download(self.spec, {**self.pin, 'fileName': '../Example-1.2.3.zip'})
        with patch.object(curseforge, 'read_url', side_effect=[self.response([self.file]), b'bad']):
            with self.assertRaisesRegex(ValueError, 'length mismatch'):
                curseforge.download(self.spec)

    def test_typed_tables_preserve_fields_context_and_exclude_hash_ids(self):
        rows, _ = sv.normalize('Data/Spell.lua',
            'VAK.L.spell={[7]={n="Namn",d="Text",a="Aura",e="English",ea="English aura"}}')
        self.assertEqual({r['field'] for r in rows}, {'name', 'description', 'auraDescription'})
        self.assertEqual(next(r['english'] for r in rows if r['field']=='auraDescription'), 'English aura')
        rows, _ = tr.normalize('Data/Spells.lua', 'D.SD[123456789]="Hash text"; D.Q[7]={t="Başlık",o="Özet"}')
        self.assertEqual({r['id'] for r in rows}, {'7'})
        self.assertEqual({r['field'] for r in rows}, {'title', 'summary'})
        rows, _ = pl.normalize('ForeverTranslations_plPL/Data00.lua',
            'P.translations[7]={title="Tytuł",objectives="Cel"}; '
            'P.pins.quests[7]={title={{"f1:abc",prov="reviewed"}}}')
        self.assertEqual({r['field'] for r in rows}, {'title','summary'})
        self.assertIn('englishFingerprints', rows[0]['context'])
        self.assertIn('upstreamFingerprint:reviewBeforeReuse', rows[0]['flags'])

    def test_multifolder_archive_normalizes_only_language_data_into_verified_sqlite(self):
        buffer = io.BytesIO()
        with ZipFile(buffer, 'w') as archive:
            archive.writestr('ForeverTranslations_plPL/Data00.lua', 'P.translations[7]={title="Tytuł"}')
            archive.writestr('ForeverTranslations_plPL/LICENSE.txt', 'Translation terms')
            archive.writestr('ForeverTranslations_plPL_Voice/Voice.lua', 'error("must not execute")')
            archive.writestr('ForeverTranslations/Core.lua', 'error("must not execute")')
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            pin = {'projectID': pl.SPEC['projectID'], 'fileID': 1234567,
                   'fileName': 'ForeverTranslations-plPL-1.2.0.zip'}
            with patch.object(github_community, 'ROOT', root), \
                    patch.object(curseforge, 'read_url', return_value=buffer.getvalue()):
                entry = pl.fetch(root/'datasources/imports/pl', pin)
            db=sqlite3.connect(':memory:'); db.row_factory=sqlite3.Row; db.executescript(SCHEMA)
            builder=CorpusBuilder(root, db); builder.community(entry)
            self.assertEqual(tuple(db.execute('SELECT entity_id,locale,text FROM records').fetchone()),
                             ('7','plPL','Tytuł'))
            raw=root/entry['path']/'raw'
            self.assertTrue((raw/'ForeverTranslations_plPL/LICENSE.txt').is_file())
            self.assertFalse((raw/'ForeverTranslations/Core.lua').exists())
            (raw/'ForeverTranslations_plPL/Data00.lua').write_text('changed')
            with self.assertRaisesRegex(ValueError,'hash mismatch'):
                builder.community(entry)
            db.close()


if __name__ == '__main__':
    unittest.main()
