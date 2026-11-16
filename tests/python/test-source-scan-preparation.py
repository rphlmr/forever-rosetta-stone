"""Verify offline source queue preparation using a fresh temporary checkout."""

import json
import hashlib
import runpy
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from unittest.mock import patch

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
module = runpy.run_path(str(ROOT / 'tools/source-scan/prepare.py'))
prepare = module['prepare_probe']
main = module['main']
load_full_inventory = module['load_full_inventory']


class SourceScanPreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / 'datasources/imports/source-scan/run/probe'
        for kind, entity_id in (('quests', 16), ('talents', 1001)):
            target = self.root / 'catalogs' / kind
            target.mkdir(parents=True)
            shutil.copy2(ROOT / 'catalogs' / kind / f'{entity_id}.json', target)
        shutil.copy2(ROOT / 'catalogs/quests/metadata.json', self.root / 'catalogs/quests/metadata.json')

    def test_prepares_fresh_checkout_and_talent_backing_spell_ids(self):
        queue = prepare(self.output, {'quests': [16], 'talents': [1001]}, root=self.root)
        self.assertEqual(set(queue['profiles']), {
            'deDE', 'enUS', 'esES', 'esMX', 'frFR',
            'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW',
        })
        jobs = queue['profiles']['enUS']['jobs']
        talent = json.loads((self.root / 'catalogs/talents/1001.json').read_text())
        self.assertEqual({job['id'] for job in jobs if job['kind'] == 'spells'}, set(talent['spellRankIds']))
        self.assertTrue(all(1001 in job['talentIds'] for job in jobs if job['kind'] == 'spells'))
        for rank, spell_id in enumerate(talent['spellRankIds'], start=1):
            job = next(job for job in jobs if job['kind'] == 'spells' and job['id'] == spell_id)
            self.assertIn({'talentId': 1001, 'rank': rank}, job['talentRanks'])
        lua = LuaRuntime()
        lua.execute((self.output / 'queue.lua').read_text())
        self.assertEqual(lua.globals().RosettaSourceProbeQueue.hash, queue['hash'])
        self.assertEqual(json.loads((self.output / 'queue.json').read_text()), queue)

    def test_rejects_overwrite_external_paths_and_invalid_ids(self):
        for selections in ({'quests': [0]}, {'quests': [-1]}, {'quests': [True]},
                           {'quests': ['16']}, {'unknown': [16]}, {'quests': [999999999]}):
            with self.subTest(selections=selections), self.assertRaises((ValueError, TypeError)):
                prepare(self.output, selections, root=self.root)
        self.assertFalse(self.output.exists())
        with self.assertRaises(ValueError):
            prepare(self.root / 'outside', {'quests': [16]}, root=self.root)
        prepare(self.output, {'quests': [16]}, root=self.root)
        before = (self.output / 'queue.lua').read_bytes()
        with self.assertRaises(FileExistsError):
            prepare(self.output, {'quests': [16]}, root=self.root)
        self.assertEqual((self.output / 'queue.lua').read_bytes(), before)

    def test_spell_context_is_opt_in_and_extracts_owned_conditions(self):
        target = self.root / 'catalogs/spells'
        target.mkdir(parents=True)
        (target / '10.json').write_text(json.dumps({'locales': {'enUS': {
            'description': '$?s11151[yes][no]'}}, 'tooltipData': {'variables': ['$x=$?s12952[1][0]']}}))
        queue = prepare(self.output, {'spells': [10]}, root=self.root, spell_context=True)
        job = queue['profiles']['enUS']['jobs'][0]
        self.assertEqual(job['knownSpellIds'], [11151, 12952])
        lua = LuaRuntime()
        lua.execute((self.output / 'queue.lua').read_text())
        self.assertEqual(lua.globals().RosettaSourceProbeQueue.profiles.enUS.jobs[1].captureContext, 1)
        with self.assertRaisesRegex(ValueError, 'explicit spells'):
            prepare(self.output.parent / 'invalid', {'spells': [10], 'quests': [16]}, root=self.root, spell_context=True)

    def test_spell_context_in_mixed_queue_is_limited_to_spells(self):
        for kind, entity_id in (('spells', 10), ('items', 1002)):
            target = self.root / 'catalogs' / kind
            target.mkdir(parents=True)
            shutil.copy2(ROOT / 'catalogs' / kind / f'{entity_id}.json', target)
        queue = prepare(self.output, {'spells': [10], 'items': [1002]}, root=self.root, spell_context=True)
        jobs = queue['profiles']['enUS']['jobs']
        spell = next(job for job in jobs if job['kind'] == 'spells')
        item = next(job for job in jobs if job['kind'] == 'items')
        self.assertEqual(spell['captureContext'], 1)
        self.assertNotIn('captureContext', item)
        self.assertNotIn('knownSpellIds', item)

    def test_explicit_factions_and_global_whitelist_are_hashed(self):
        target = self.root / 'catalogs/factions'
        target.mkdir(parents=True)
        shutil.copy2(ROOT / 'catalogs/factions/92.json', target)
        keys = ['FACTION_STANDING_LABEL1', 'FACTION_STANDING_LABEL8']
        queue = prepare(self.output, {'factions': [92]}, root=self.root, global_keys=keys)
        jobs = queue['profiles']['enUS']['jobs']
        self.assertEqual({job.get('key') for job in jobs if job['kind'] == 'globals'}, set(keys))
        self.assertEqual([job['id'] for job in jobs if job['kind'] == 'factions'], [92])
        lua = LuaRuntime(); lua.execute((self.output / 'queue.lua').read_text())
        self.assertEqual(lua.globals().RosettaSourceProbeQueue.hash, queue['hash'])
        other = prepare(self.output.parent / 'other', {'factions': [92]}, root=self.root, global_keys=keys[:1])
        self.assertNotEqual(queue['hash'], other['hash'])
        with self.assertRaisesRegex(ValueError, 'Unsupported explicit global'):
            prepare(self.output.parent / 'bad', {'factions': [92]}, root=self.root, global_keys=['ARBITRARY'])

    def test_explicit_unowned_spell_ids_are_bounded_and_hashed(self):
        first = prepare(self.output, {}, root=self.root, unowned_spells=[12165])
        job = first['profiles']['enUS']['jobs'][0]
        self.assertEqual((job['kind'], job['id']), ('spells', 12165))
        other = prepare(self.output.parent / 'other', {}, root=self.root, unowned_spells=[12166])
        self.assertNotEqual(first['hash'], other['hash'])
        with self.assertRaises(ValueError):
            prepare(self.output.parent / 'bad', {}, root=self.root, unowned_spells=[0])

    def test_large_queue_compiles_and_loads_in_lua_51(self):
        quests = self.root / 'catalogs/quests'
        fixture = (quests / '16.json').read_bytes()
        for entity_id in range(10000, 11501):
            (quests / f'{entity_id}.json').write_bytes(fixture)
        ids = [int(path.stem) for path in quests.glob('[0-9]*.json')]
        fixture_dir = self.root / 'tests/fixtures'
        fixture_dir.mkdir(parents=True)
        shutil.copy2(ROOT / 'tests/fixtures/tooltip-client-strings.json', fixture_dir)
        def prepare_from_checkout(output, selections, include_globals, **kwargs):
            return prepare(output, selections, include_globals, root=self.root, **kwargs)

        with patch.dict(main.__globals__, ROOT=self.root, prepare_probe=prepare_from_checkout,
                        load_full_inventory=lambda *_: ({}, {})), patch.object(
                sys, 'argv', ['prepare.py', '--all', '--client-snapshot', 'snapshot', '--quest-ids', 'ids.json',
                              '--output', str(self.output)]):
            main()
        queue = json.loads((self.output / 'queue.json').read_text())
        lua = LuaRuntime()
        lua.execute((self.output / 'queue.lua').read_text())
        jobs = queue['profiles']['enUS']['jobs']
        self.assertEqual(len([job for job in jobs if job['kind'] == 'quests']), len(ids))
        self.assertTrue(any(job['kind'] == 'globals' for job in jobs))
        self.assertEqual(len(lua.globals().RosettaSourceProbeQueue.profiles.enUS.jobs), len(jobs))
        self.assertEqual(lua.globals().RosettaSourceProbeQueue.hash, queue['hash'])

    def test_full_inventory_unions_sources_and_preserves_provenance(self):
        snapshot = self.root / 'snapshot'
        snapshot.mkdir()
        results = []
        for table, ids in (('Item', [201]), ('ItemSparse', [202]), ('Spell', [301]), ('SpellName', [302])):
            locales = {'enUS'} if table == 'Item' else module['CLIENT_LOCALES']
            extra = {'Spell': ',Description_lang', 'SpellName': ',Name_lang'}.get(table, '')
            for locale in sorted(locales):
                path = snapshot / f'{table}.1.60.1.70888.{locale}.csv'
                path.write_text('ID' + extra + '\n' + '\n'.join(f'{value}{",text" if extra else ""}'
                                                                for value in ids) + '\n', encoding='utf-8')
                results.append({'table': table, 'locale': locale, 'status': 'downloaded', 'file': path.name,
                                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'rows': len(ids)})
        (snapshot / 'manifest.json').write_text(json.dumps({
            'build': '1.60.1.70888', 'complete': True, 'stoppedEarly': False, 'results': results,
        }))
        quest_ids = self.root / 'quest-ids.json'
        quest_ids.write_text(json.dumps({'schemaVersion': 1, 'sources': {
            'questieForever': {'revision': 'questie-rev', 'ids': [401, 402]},
            'egQuests70862': {'revision': 'eg-rev', 'ids': [402, 403]},
            'egHistoricalQuestsAndObjectives': {'revision': 'history-rev', 'ids': [403, 404]},
        }}))
        inventory, sources = load_full_inventory(snapshot, quest_ids)
        queue = prepare(self.output, {'quests': [16], 'talents': [1001]}, root=self.root,
                        inventory=inventory, sources=sources)
        jobs = queue['profiles']['enUS']['jobs']
        self.assertEqual({job['id'] for job in jobs if job['kind'] == 'quests'}, {16, 401, 402, 403, 404})
        self.assertEqual({job['id'] for job in jobs if job['kind'] == 'items'}, {201, 202})
        spell_ids = {job['id'] for job in jobs if job['kind'] == 'spells'}
        self.assertTrue({301, 302}.issubset(spell_ids))
        self.assertEqual(queue['inventory']['sources']['questieForever']['revision'], 'questie-rev')
        self.assertEqual(queue['inventory']['sources']['questieForever']['idCount'], 2)
        self.assertEqual(queue['inventory']['sources']['Item']['files'][0]['sha256'], results[0]['sha256'])
        self.assertTrue(queue['inventory']['limitations'])
        (snapshot / results[0]['file']).write_text('ID\n999\n', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            load_full_inventory(snapshot, quest_ids)


if __name__ == '__main__':
    unittest.main()
