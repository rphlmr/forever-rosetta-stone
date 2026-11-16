"""Check authenticated raw collection and the fetch-before-build boundary offline."""

import ast
import hashlib
import sqlite3
import ssl
import json
import os
import runpy
import sys
import tempfile
import threading
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from unittest.mock import Mock, patch
from urllib.error import HTTPError, URLError


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'datasources'))
from datasources.blizzard import loader as blizzard
from datasources.questie import loader as questie
from datasources.eg_link import loader as eg_link

refresh = runpy.run_path(str(ROOT / 'datasources/refresh.py'))


class DatasourceTests(unittest.TestCase):
    def test_unavailable_community_source_fails_before_expensive_core_collection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / 'datasources/corpus').mkdir(parents=True)
            (root / 'datasources/corpus/sources.json').write_text('{}')
            with patch.dict(refresh['refresh'].__globals__, {'ROOT': root}), \
                    patch.object(refresh['COMMUNITY_SOURCES']['czech-forever'], 'fetch',
                                 side_effect=HTTPError('url', 404, 'Missing release', {}, None)), \
                    patch.object(refresh['wago'], 'fetch') as core:
                with self.assertRaises(HTTPError):
                    refresh['refresh'](root / 'datasources/imports/run', root / '.env',
                                       sources=['wago', 'czech-forever'])
                core.assert_not_called()

    def test_blizzard_get_retries_transport_timeouts_with_shared_pacing(self):
        limiter = Mock()
        for failure in (TimeoutError(), URLError(OSError(65, 'No route to host'))):
            limiter.reset_mock()
            with patch.object(blizzard, 'read_url_response', side_effect=[failure, (b'{}', {})]), \
                    patch.object(blizzard.time, 'sleep') as sleep:
                self.assertEqual(blizzard.read_response('https://example.test', {}, limiter), (b'{}', {}))
            self.assertEqual(limiter.acquire.call_count, 2)
            sleep.assert_called_once_with(1)

    def test_blizzard_get_stops_after_bounded_retries_and_does_not_retry_http_errors(self):
        limiter = Mock()
        with patch.object(blizzard, 'read_url_response', side_effect=TimeoutError()), \
                patch.object(blizzard.time, 'sleep') as sleep:
            with self.assertRaises(TimeoutError):
                blizzard.read_response('https://example.test', {}, limiter)
        self.assertEqual(limiter.acquire.call_count, 3)
        self.assertEqual([call.args for call in sleep.call_args_list], [(1,), (2,)])
        limiter.reset_mock()
        with patch.object(blizzard, 'read_url_response', side_effect=HTTPError('url', 429, 'Limited', {}, None)) as read:
            with self.assertRaises(HTTPError):
                blizzard.read_response('https://example.test', {}, limiter)
        self.assertEqual(read.call_count, 1)
        self.assertEqual(limiter.acquire.call_count, 1)
        with patch.object(blizzard, 'read_url_response', side_effect=URLError(ssl.SSLCertVerificationError())) as read:
            with self.assertRaises(URLError):
                blizzard.read_response('https://example.test', {}, limiter)
        self.assertEqual(read.call_count, 1)

    def test_eg_fetch_records_both_datasets_relative_to_the_project(self):
        build='1.60.1.70938'
        index={'products':{'wowf':{build:['creature_details.enUS','item_hotfixes.enUS']}}}
        payload={'meta':{'clientBuild':build,'locale':'enUS'},'data':[]}
        with tempfile.TemporaryDirectory(dir=ROOT/'datasources/imports') as temporary:
            output=Path(temporary)/'eg-link'
            with patch.object(eg_link,'latest_revision',return_value='a'*40), \
                    patch.object(eg_link,'read_url',side_effect=[json.dumps(value).encode() for value in (index,payload,payload)]):
                entries=eg_link.fetch(output)
            self.assertEqual(len(entries),2)
            self.assertTrue(all((ROOT/entry['path']).is_file() for entry in entries))
            self.assertTrue((output/'source.json').is_file())

    def test_targeted_wago_refresh_does_not_require_unselected_talent_table(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / 'datasources/corpus').mkdir(parents=True)
            (root / 'datasources/corpus/sources.json').write_text('{}')
            connection = sqlite3.connect(':memory:')
            build = Mock()
            with patch.dict(refresh['refresh'].__globals__, {'ROOT': root, 'build': build,
                    'open_corpus': Mock(return_value=connection), 'verify': Mock(return_value={'valid': True})}), \
                    patch.object(refresh['wago'], 'fetch', return_value='1.60.1.70938') as fetch:
                output = root / 'datasources/imports/scoped'
                refresh['refresh'](output, root / '.env', sources=['wago'],
                                   wago_tables=['SpellClassOptions'], wago_locales=['enUS'])
            fetch.assert_called_once_with(output / 'wago', None, ['SpellClassOptions'], ['enUS'])
            config = json.loads((output / 'sources.json').read_text())
            self.assertEqual(config['talents'], [])
            self.assertEqual(config['wago'], ['datasources/imports/scoped/wago'])

    def test_dotenv_is_not_executed_and_environment_takes_precedence(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / '.env'
            path.write_text('BLIZZARD_CLIENT_ID="$(literal)"\nBLIZZARD_CLIENT_SECRET=file-secret\n')
            with patch.dict(os.environ, {'BLIZZARD_CLIENT_SECRET': 'env-secret'}, clear=True):
                self.assertEqual(blizzard.credentials(path), {
                    'BLIZZARD_CLIENT_ID': '$(literal)', 'BLIZZARD_CLIENT_SECRET': 'env-secret',
                })

    def test_missing_credentials_fail_before_creating_a_refresh(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            root = Path(temporary).resolve()
            with patch.dict(refresh['refresh'].__globals__, {'ROOT': root}):
                with self.assertRaisesRegex(ValueError, 'BLIZZARD_CLIENT_ID'):
                    refresh['refresh'](root / 'datasources/imports/run', root / '.env', sources=['wago', 'questie', 'blizzard', 'eg-link'])
            self.assertFalse((root / 'datasources/imports').exists())

    def test_blizzard_saves_unfiltered_multilingual_bytes_and_probes_extra_ids(self):
        namespace = 'static-1.60.1_70399-forever-eu'
        raw = ('{ "id": 1, "_links": {"self": {"href": '
               '"https://eu.api.blizzard.com/data/wow/quest/1?namespace=' + namespace + '"}}, '
               '"description": {"en_US": "English", "fr_FR": "Français"}, "extra": true }').encode()

        def read(url, headers=None, data=None):
            if url.endswith('/token'):
                return b'{"access_token":"private-token"}'
            if '/quest/index?' in url:
                return json.dumps({'_links': {'self': {'href': url.replace('static-forever-eu', namespace)}},
                                   'quests': [{'key': {'href': 'https://eu.api.blizzard.com/data/wow/quest/1'}}]}).encode()
            if '/quest/2?' in url:
                raise HTTPError(url, 404, 'Missing', {}, None)
            return raw

        with tempfile.TemporaryDirectory() as temporary, patch.object(blizzard, 'read_url', side_effect=read), \
                patch.object(blizzard, 'read_url_response', side_effect=lambda url, headers: (read(url, headers), {})), \
                patch.object(blizzard.time, 'sleep'):
            output = Path(temporary) / 'blizzard'
            self.assertEqual(blizzard.fetch(output, dict(zip(blizzard.KEYS, ('id', 'secret'))), {2}), namespace)
            self.assertEqual((output / 'quest/1.json').read_bytes(), raw)
            manifest = json.loads((output / 'manifest.json').read_text())
            self.assertEqual(manifest['state'], 'complete')
            self.assertIn('/data/wow/quest/2', manifest['unavailable'])
            self.assertNotIn('private-token', json.dumps(manifest))

    def test_blizzard_limiter_paces_requests_and_stops_at_hourly_budget(self):
        limiter = blizzard.RequestLimiter(requests_per_second=90, hourly_limit=2)
        with patch.object(blizzard.time, 'monotonic', return_value=100), \
                patch.object(blizzard.time, 'sleep') as sleep:
            limiter.acquire()
            limiter.acquire()
            self.assertAlmostEqual(sleep.call_args.args[0], 1 / 90)
            with self.assertRaisesRegex(RuntimeError, 'hourly request budget'):
                limiter.acquire()
        with patch.object(blizzard.time, 'monotonic', return_value=3701), \
                patch.object(blizzard.time, 'sleep'):
            limiter.acquire()
        self.assertEqual(len(limiter.starts), 1)

    def test_blizzard_revalidates_each_resource_and_checks_cached_bytes(self):
        namespace = 'static-1.60.1_70399-forever-eu'
        validator = {'Last-Modified': 'Fri, 13 Nov 2026 19:25:48 GMT'}

        def response(url, headers):
            if headers.get('If-Modified-Since') == validator['Last-Modified']:
                raise HTTPError(url, 304, 'Not modified', {}, None)
            document = {'_links': {'self': {'href': url.replace('static-forever-eu', namespace)}}}
            if '/quest/index?' in url:
                document['quests'] = [{'key': {'href': 'https://eu.api.blizzard.com/data/wow/quest/1'}}]
            else:
                document.update(id=1, description={'en_US': 'English', 'fr_FR': 'Français'})
            return json.dumps(document).encode(), validator

        with tempfile.TemporaryDirectory() as temporary, \
                patch.object(blizzard, 'read_url', return_value=b'{"access_token":"private"}'), \
                patch.object(blizzard, 'read_url_response', side_effect=response) as request, \
                patch.object(blizzard.time, 'sleep'):
            previous = Path(temporary) / 'previous'
            values = dict(zip(blizzard.KEYS, ('id', 'secret')))
            blizzard.fetch(previous, values)
            request.reset_mock()
            current = Path(temporary) / 'current'
            blizzard.fetch(current, values, previous=previous)
            self.assertEqual(request.call_count, 2)
            self.assertTrue(all(call.args[1].get('If-Modified-Since') for call in request.call_args_list))
            self.assertEqual((current / 'quest/1.json').read_bytes(), (previous / 'quest/1.json').read_bytes())
            manifest = json.loads((current / 'manifest.json').read_text())
            self.assertEqual(manifest['state'], 'complete')
            self.assertTrue(all(row['httpStatus'] == 304 for row in manifest['resources'].values()))
            (previous / 'quest/1.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'cache bytes changed'):
                blizzard.fetch(Path(temporary) / 'invalid', values, previous=previous)
            self.assertEqual(json.loads((Path(temporary) / 'invalid/manifest.json').read_text())['state'], 'fetching')

    def test_failed_fetch_never_builds_sqlite(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / 'datasources/corpus').mkdir(parents=True)
            (root / 'datasources/corpus/sources.json').write_text('{}')
            values = dict(zip(blizzard.KEYS, ('id', 'secret')))
            build = Mock()
            with patch.dict(refresh['refresh'].__globals__, {'ROOT': root, 'build': build}), \
                    patch.object(blizzard, 'credentials', return_value=values), \
                    patch.object(refresh['wago'], 'fetch', return_value='1.60.1.70888'), \
                    patch.object(refresh['eg_link'], 'fetch', return_value=[]), \
                    patch.object(questie, 'fetch', side_effect=RuntimeError('fetch failed')):
                with self.assertRaisesRegex(RuntimeError, 'fetch failed'):
                    refresh['refresh'](root / 'datasources/imports/run', root / '.env', sources=['wago', 'questie', 'blizzard', 'eg-link'])
            build.assert_not_called()
            self.assertFalse((root / 'datasources/imports/run/complete.json').exists())

    def test_wago_only_needs_no_blizzard_credentials_or_other_fetches(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / 'datasources/corpus').mkdir(parents=True)
            (root / 'datasources/corpus/sources.json').write_text('{}')
            connection = Mock()
            replacements = {'ROOT': root, 'build': Mock(), 'open_corpus': Mock(return_value=connection),
                            'verify': Mock(return_value={'valid': True})}
            with patch.dict(refresh['refresh'].__globals__, replacements), \
                    patch.object(blizzard, 'credentials', side_effect=AssertionError('credentials requested')), \
                    patch.object(blizzard, 'fetch') as blizzard_fetch, \
                    patch.object(questie, 'fetch') as questie_fetch, \
                    patch.object(refresh['eg_link'], 'fetch') as eg_fetch, \
                    patch.object(refresh['wago'], 'fetch', return_value='1.60.1.70900') as wago_fetch:
                output = root / 'datasources/imports/run'
                refresh['refresh'](output, root / '.env', sources=['wago'])
            wago_fetch.assert_called_once_with(output / 'wago', None)
            for fetcher in (blizzard_fetch, questie_fetch, eg_fetch):
                fetcher.assert_not_called()
            sources = json.loads((output / 'sources.json').read_text())
            self.assertEqual(sources['blizzard'], [])
            self.assertEqual(sources['questie'], [])
            self.assertEqual(sources['egLink'], [])
            self.assertEqual(sources['talents'], sources['wago'])
            self.assertEqual(json.loads((output / 'complete.json').read_text())['fetchedSources'], ['wago'])

    def test_partial_refresh_keeps_explicitly_reused_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / 'datasources/corpus').mkdir(parents=True)
            (root / 'datasources/corpus/sources.json').write_text('{}')
            retained = {'blizzard': [{'path': 'datasources/imports/previous/blizzard'}]}
            replacements = {'ROOT': root, 'build': Mock(), 'open_corpus': Mock(return_value=Mock()),
                            'verify': Mock(return_value={'valid': True}),
                            'reuse_sources': Mock(return_value=(retained, {'blizzardNamespace': 'old-namespace'}))}
            with patch.dict(refresh['refresh'].__globals__, replacements), \
                    patch.object(blizzard, 'credentials', side_effect=AssertionError('credentials requested')), \
                    patch.object(refresh['wago'], 'fetch', return_value='1.60.1.70900'):
                output = root / 'datasources/imports/run'
                refresh['refresh'](output, root / '.env', sources=['wago'], reuse=root / 'datasources/imports/previous')
            config = json.loads((output / 'sources.json').read_text())
            self.assertEqual(config['blizzard'], retained['blizzard'])
            self.assertEqual(json.loads((output / 'pins.json').read_text())['blizzardNamespace'], 'old-namespace')
            self.assertEqual(json.loads((output / 'complete.json').read_text())['reusedSources'], ['blizzard'])

    def test_reuse_checks_raw_hashes_without_requiring_unchanged_catalogs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            previous = root / 'datasources/imports/previous'
            raw = previous / 'blizzard/quest.json'
            raw.parent.mkdir(parents=True)
            raw.write_text('{"title": "Native"}')
            config = previous / 'sources.json'
            config.write_text(json.dumps({'blizzard': [{'path': 'datasources/imports/previous/blizzard'}]}))
            (previous / 'complete.json').write_text('{"verified": true}')
            (previous / 'pins.json').write_text('{"blizzardNamespace": "namespace"}')
            db = sqlite3.connect(previous / 'corpus.sqlite')
            db.execute('CREATE TABLE inputs (path TEXT, sha256 TEXT)')
            for path in (raw, config):
                db.execute('INSERT INTO inputs VALUES (?,?)',
                           (str(path.relative_to(root)), hashlib.sha256(path.read_bytes()).hexdigest()))
            db.execute('INSERT INTO inputs VALUES (?,?)', ('catalogs/changed.json', 'old-hash'))
            db.commit()
            db.close()
            with patch.dict(refresh['reuse_sources'].__globals__, {'ROOT': root, 'open_corpus': sqlite3.connect}):
                sources, pins = refresh['reuse_sources'](previous, {'wago'})
                self.assertEqual(pins['blizzardNamespace'], 'namespace')
                self.assertTrue(sources['blizzard'])
                sources, pins = refresh['reuse_sources'](previous, {'blizzard'})
                self.assertNotIn('blizzard', sources)
                self.assertNotIn('blizzardNamespace', pins)
                raw.write_text('changed')
                with self.assertRaisesRegex(ValueError, 'Reused source input changed'):
                    refresh['reuse_sources'](previous, {'wago'})
                with self.assertRaisesRegex(ValueError, 'Reused source input changed'):
                    refresh['reuse_sources'](previous, {'blizzard'})

    def test_unknown_source_fails_before_credentials_or_creating_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            with patch.dict(refresh['refresh'].__globals__, {'ROOT': root}), \
                    patch.object(blizzard, 'credentials') as credentials:
                with self.assertRaisesRegex(ValueError, 'known sources'):
                    refresh['refresh'](root / 'datasources/imports/run', root / '.env', sources=['unknown'])
                credentials.assert_not_called()
            self.assertFalse((root / 'datasources/imports/run').exists())

    def test_questie_export_command_is_valid_python_and_pinned(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'datasources/imports/questie'
            output.parent.mkdir(parents=True)
            revision = 'a' * 40
            with patch.object(questie, 'ROOT', root), patch.object(questie.subprocess, 'run') as run, \
                    patch.object(questie.subprocess, 'check_output', return_value=revision + '\n'):
                result = questie.fetch(output, revision)
            self.assertEqual(result['revision'], revision)
            commands = [call.args[0] for call in run.call_args_list]
            ast.parse(next(command[2] for command in commands if command[0] == sys.executable))
            self.assertIn(revision, commands[1])

    def test_all_fetches_finish_before_build_and_verification(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            (root / 'datasources/corpus').mkdir(parents=True)
            (root / 'datasources/corpus/sources.json').write_text('{}')
            events = []
            started = {'wago': threading.Event(), 'eg': threading.Event()}
            connection = Mock()

            def record(name, result):
                def call(*args, **kwargs):
                    if name in started:
                        started[name].set()

                    if name == 'blizzard':
                        self.assertTrue(started['wago'].wait(2), 'Wago must start before Blizzard finishes')
                        self.assertTrue(started['eg'].wait(2), 'EG must start before Blizzard finishes')

                    events.append(name)
                    return result
                return call

            replacements = {
                'ROOT': root, 'build': Mock(side_effect=record('build', None)),
                'open_corpus': Mock(return_value=connection),
                'verify': Mock(side_effect=record('verify', {'valid': True})),
            }
            with patch.dict(refresh['refresh'].__globals__, replacements), \
                    patch.object(blizzard, 'credentials', return_value={}), \
                    patch.object(questie, 'quest_ids', return_value={1}), \
                    patch.object(questie, 'fetch', side_effect=record('questie', {'path': 'datasources/imports/run/questie', 'revision': 'a' * 40})), \
                    patch.object(blizzard, 'fetch', side_effect=record('blizzard', 'static-1.60.1_70399-forever-eu')), \
                    patch.object(refresh['wago'], 'fetch', side_effect=record('wago', '1.60.1.70888')), \
                    patch.object(refresh['eg_link'], 'fetch', side_effect=record('eg', [{'path': 'datasources/imports/run/eg-link/creature_details.enUS.json', 'revision': 'b' * 40}])):
                refresh['refresh'](root / 'datasources/imports/run', root / '.env', sources=['wago', 'questie', 'blizzard', 'eg-link'])
            self.assertEqual(set(events[:4]), {'questie', 'blizzard', 'wago', 'eg'})
            self.assertLess(events.index('questie'), events.index('blizzard'))
            self.assertEqual(events[4:], ['build', 'verify'])
            self.assertTrue((root / 'datasources/imports/run/complete.json').exists())
            sources = json.loads((root / 'datasources/imports/run/sources.json').read_text())
            self.assertEqual(sources['blizzard'], [{'path': 'datasources/imports/run/blizzard'}])
            self.assertEqual(sources['questie'][0]['revision'], 'a' * 40)
            connection.close.assert_called_once()


if __name__ == '__main__':
    unittest.main()
