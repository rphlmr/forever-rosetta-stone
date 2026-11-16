"""Focused checks for reference exports; no network or maintained catalog writes."""

import importlib.util
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.error import HTTPError, URLError
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'wago_download', Path(__file__).resolve().parents[2] / 'datasources/wago/loader.py'
)
downloader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(downloader)


class DownloadTests(unittest.TestCase):
    def test_default_download_discovers_latest_build_and_uses_its_directory(self):
        with patch('sys.argv', ['wago.py', 'download', '--tables', 'SpellName']), \
                patch.object(downloader, 'get_published_builds', create=True,
                             return_value=['1.60.1.70888', '1.60.1.70900']) as discover, \
                patch.object(downloader, 'download_tables', return_value=0) as download:
            self.assertEqual(downloader.main(), 0)

        discover.assert_called_once_with()
        self.assertEqual(download.call_args.args[0], '1.60.1.70900')
        self.assertEqual(download.call_args.args[1].name, '1.60.1.70900')
        self.assertEqual(download.call_args.args[2], ('SpellName',))

    def test_explicit_build_skips_discovery_for_reproducible_comparisons(self):
        with patch('sys.argv', ['wago.py', 'download', '--build', '1.60.1.70862']), \
                patch.object(downloader, 'get_published_builds', create=True) as discover, \
                patch.object(downloader, 'download_tables', return_value=0) as download:
            self.assertEqual(downloader.main(), 0)

        discover.assert_not_called()
        self.assertEqual(download.call_args.args[0], '1.60.1.70862')

    def test_failed_discovery_does_not_download_the_old_baseline(self):
        with patch('sys.argv', ['wago.py', 'download']), \
                patch.object(downloader, 'get_published_builds', create=True,
                             side_effect=URLError('offline')), \
                patch.object(downloader, 'download_tables') as download, \
                contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as raised:
            downloader.main()

        self.assertEqual(raised.exception.code, 1)
        download.assert_not_called()

    def test_default_profile_excludes_visuals_and_keeps_effect_dependencies(self):
        self.assertEqual(len(downloader.DEFAULT_TABLES), len(set(downloader.DEFAULT_TABLES)))
        self.assertFalse(any('Visual' in name or 'Clutter' in name for name in downloader.DEFAULT_TABLES))
        for table in ('SpellEffect', 'SpellMisc', 'SpellXDescriptionVariables', 'ItemEffect', 'ItemXItemEffect',
                      'TraitDefinition', 'TraitDefinitionEffectPoints', 'CurvePoint',
                      'TraitNodeEntry', 'TraitNodeXTraitNodeEntry', 'TraitNode'):
            self.assertIn(table, downloader.DEFAULT_TABLES)

    def test_locales_follow_actual_columns_and_existing_files_resume(self):
        calls = []

        def fetch(request, timeout):
            calls.append(request.full_url)
            content = b'ID,Description_lang\n1,"Damage $s1, over $d"\n'

            if '/SpellEffect/' in request.full_url:
                content = b'ID,SpellID,EffectBasePointsF\n10,1,5\n'

            return io.BytesIO(content)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            args = ('1.60.1.70862', output, ('Spell', 'SpellEffect'), ('frFR',), fetch)
            self.assertEqual(downloader.download_tables(*args), 0)
            self.assertEqual(len(calls), 3)
            self.assertEqual(len(list(output.glob('*.csv'))), 3)
            self.assertEqual(downloader.download_tables(*args), 0)
            self.assertEqual(len(calls), 3)

    def test_geographic_tables_are_opt_in_and_download_localized_names(self):
        calls = []

        def fetch(request, timeout):
            calls.append(request.full_url)
            name_column = b'Name_lang' if '/UiMap/' in request.full_url else b'AreaName_lang'

            return io.BytesIO(b'ID,' + name_column + b'\n1,Example\n')

        for table in ('AreaTable', 'UiMap'):
            self.assertIn(table, downloader.SUPPORTED_TABLES)
            self.assertNotIn(table, downloader.DEFAULT_TABLES)

        with tempfile.TemporaryDirectory() as directory:
            result = downloader.download_tables('1.60.1.70888', Path(directory),
                                                ('AreaTable', 'UiMap'), ('frFR',), fetch)
            self.assertEqual(result, 0)
            self.assertEqual(len(calls), 4)
            self.assertTrue(any('/UiMap/' in url and 'locale=frFR' in url for url in calls))

    def test_access_denial_stops_without_publishing_csv(self):
        calls = []

        def fetch(request, timeout):
            calls.append(request.full_url)
            raise HTTPError(request.full_url, 403, 'Forbidden', {}, None)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = downloader.download_tables('1.60.1.70862', output, ('Spell', 'Item'), ('frFR',), fetch)
            manifest = json.loads((output / 'manifest.json').read_text())
            self.assertEqual(result, 1)
            self.assertEqual(len(calls), 1)
            self.assertTrue(manifest['stoppedEarly'])
            self.assertFalse(manifest['complete'])
            self.assertEqual(list(output.glob('*.csv')), [])

    def test_talent_stays_english_and_globalstrings_are_localized(self):
        calls = []

        def fetch(request, timeout):
            calls.append(request.full_url)
            return io.BytesIO(b'ID,BaseTag,TagText_lang,Flags\n1,SPELL_PASSIVE,Passive,1\n')

        for table, locales in (('Talent', ['enUS']), ('GlobalStrings', ['enUS', 'frFR'])):
            with self.subTest(table=table), tempfile.TemporaryDirectory() as directory:
                calls.clear()
                result = downloader.download_tables('1.60.1.70862', Path(directory), (table,), ('frFR',), fetch)
                self.assertEqual(result, 0)
                self.assertEqual([call.split('locale=')[1] for call in calls], locales)

    def test_error_pages_and_malformed_records_are_rejected(self):
        for content in (
            b'<html>Denied</html>',
            b'ID,Description_lang\n1,a\n1,b\n',
            b'ID,Description_lang\n1,a,extra\n',
            b'ID,Description_lang\n1\n',
        ):
            with self.subTest(content=content), self.assertRaises(ValueError):
                downloader.validate_csv(content, 'Spell')

    def test_empty_structural_table_is_valid(self):
        self.assertEqual(downloader.validate_csv(b'ID,SpellID\n', 'SpellScript'), 0)

    def test_invalid_existing_file_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            destination = output / 'Spell.1.60.1.70862.enUS.csv'
            destination.write_bytes(b'<html>Denied</html>')

            def fetch(request, timeout):
                self.fail('Existing files must not be overwritten')

            result = downloader.download_tables('1.60.1.70862', output, ('Spell',), ('enUS',), fetch)
            self.assertEqual(result, 1)
            self.assertEqual(destination.read_bytes(), b'<html>Denied</html>')


if __name__ == '__main__':
    unittest.main()
