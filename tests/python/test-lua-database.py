"""Check metadata generation, lazy decoding, independent locales, and the shipped API contract."""

import base64
import copy
import hashlib
import json
import runpy
import sys
import tempfile
import unittest
import zlib
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata


sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build import runtime_catalog
from tools.build import database_storage

build = runpy.run_path(str(ROOT / 'tools/build/build-lua-database.py'))


def create_documents(quests, names):
    documents = {
        'quests': quests,
        **{kind: {'schemaVersion': 1, 'catalogs': {kind: entities}}
           for kind, entities in names['catalogs'].items() if kind != 'maps'},
    }
    documents['areas']['catalogs']['maps'] = names['catalogs']['maps']

    for document in documents.values():
        for entities in document['catalogs'].values():
            for entity in entities.values():
                for localized in entity['locales'].values():
                    fields = [key for key in ('name', 'nameFemale', 'title', 'summary', 'description', 'auraDescription',
                                              'rank', 'nameDescription', 'eventObjectiveLabel', 'setName')
                              if key in localized]
                    metadata = localized.setdefault('translationMetadata', {}).setdefault('fields', {})

                    for field in fields:
                        metadata.setdefault(field, {'origin': 'original', 'source': 'testFixture'})

    return documents


def decode_page(lua, metadata, key):
    value = metadata[key]

    if value.startswith(b'~'):
        value = b''.join(metadata[key + b'-' + str(index).encode()]
                         for index in range(1, int(value[1:-1]) + 1))

    raw = zlib.decompress(base64.b64decode(value))

    return lua.globals().C_EncodingUtil.DeserializeCBOR(raw), len(raw)


def iter_data_pages(metadata):
    for key in metadata:
        parts = key.decode().split('-')

        if len(parts) == 5 and parts[3] in build['KINDS'] and parts[4].isdigit():
            yield key, parts[3], parts[2]


class DatabaseTests(unittest.TestCase):
    def test_equipment_requirement_labels_share_only_identical_specs_and_unambiguous_locales(self):
        from tools.build.runtime_catalog import equipment_requirement_sources
        records = {str(id): json.loads((ROOT / f'catalogs/spells/{id}.json').read_text())
                   for id in (3674, 14284, 1310687)}
        sources = equipment_requirement_sources(records)
        owner = sources[1310687][9]['frFR']
        self.assertEqual(records[str(owner)]['locales']['frFR']['equipmentRequirement'],
                         'Requiert Arme à distance')
        changed = json.loads(json.dumps(records))
        changed['1310687']['tooltipData']['requiredEquipment']['inventoryTypeMask'] ^= 1
        self.assertNotIn(1310687, equipment_requirement_sources(changed))
        changed = json.loads(json.dumps(records))
        changed['14284']['locales']['frFR']['equipmentRequirement'] += '?'
        self.assertNotIn('frFR', equipment_requirement_sources(changed)[1310687][9])

    def test_globalstring_scope_and_legitimate_empty_separator_are_preserved(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['globalstrings'] = {
            '1': {'key': 'LARGE_NUMBER_SEPERATOR', 'locales': {'enUS': {'name': ','}, 'frFR': {'name': ''}}},
            '2': {'key': 'PLACEHOLDER_SCENE', 'locales': {'enUS': {'name': 'Unrelated UI'}}},
        }
        documents = create_documents(quests, names)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](documents, output, globalstring_keys={'LARGE_NUMBER_SEPERATOR'})
            lua = LuaRuntime(encoding=None)
            install_metadata(lua, read_metadata(output))
            api = load_database(lua)
            self.assertEqual(api.GetGlobalStringByKey(api, b'LARGE_NUMBER_SEPERATOR', b'frFR')[0], b'')
            self.assertEqual(api.GetGlobalStrings(api, b'frFR')[b'LARGE_NUMBER_SEPERATOR'], b'')
            self.assertIsNone(api.GetGlobalStringByKey(api, b'PLACEHOLDER_SCENE', b'enUS'))

    def test_globalstrings_ship_the_text_the_client_shows(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['globalstrings'] = {
            '1': {'key': 'SPELL_TOTEMS', 'locales': {'enUS': {'name': 'Tools: '}, 'frFR': {'name': 'Outils\u00a0:\\32'}}},
            '2': {'key': 'ABANDON_QUEST_CONFIRM', 'locales': {'enUS': {'name': 'Abandon \\"%s\\"?'}}},
            '3': {'key': 'ICON_LABEL', 'locales': {'enUS': {'name': '|TInterface\\\\Icons\\\\Note:0|t Note'}}},
            '4': {'key': 'BELL', 'locales': {'enUS': {'name': '\\21'}}},
            '5': {'key': 'LIST', 'locales': {'enUS': {'name': 'One\nTwo'}}},
            '6': {'key': 'QUOTED_LABEL', 'locales': {'enUS': {'name': 'Say \\"Hello\\"'}}},
        }
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            lua = LuaRuntime(encoding=None)
            install_metadata(lua, read_metadata(output))
            api = load_database(lua)
            get = lambda key, locale: api.GetGlobalStringByKey(api, key.encode(), locale.encode())[0].decode('utf-8')
            self.assertEqual(get('SPELL_TOTEMS', 'frFR'), 'Outils\u00a0: ', 'The export\'s \\32 is the client\'s space')
            self.assertEqual(get('ABANDON_QUEST_CONFIRM', 'enUS'), 'Abandon "%s"?')
            self.assertEqual(get('ICON_LABEL', 'enUS'), '|TInterface\\Icons\\Note:0|t Note')
            self.assertEqual(get('BELL', 'enUS'), '\x15')
            self.assertEqual(get('LIST', 'enUS'), 'One\nTwo', 'Already decoded newlines are unchanged')
            found = api.GetGlobalStringKeysByText(api, b'Say "Hello"', b'enUS')
            self.assertEqual(list(found.values()), [b'QUOTED_LABEL'],
                             'Native text lookup matches the decoded client literal')

    def test_single_english_storage_rejects_removed_english_locale(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS'], 'catalogs': {'quests': {
            '1': {'locales': {'enUS': {'title': 'English'}}},
        }}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            lua = LuaRuntime(encoding=None)
            install_metadata(lua, read_metadata(output))
            api = load_database(lua)
            self.assertNotIn(b'enGB', api.GetLocales(api))
            self.assertIsNone(api.GetQuest(api, 1, b'enGB'))
            with self.assertRaisesRegex(Exception, 'Unknown Forever Rosetta Stone language'):
                api.LoadLocale(api, b'enGB')

    def test_manifest_only_preserves_database_without_reading_catalogs(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon.toc'
            metadata = b'# Generated database\n## X-Rosetta-test: unchanged\n\n'
            output.write_bytes(metadata + b'## Interface: 16001\nold-component.lua\n')
            with patch('sys.argv', ['build-lua-database.py', '--root', str(Path(directory) / 'missing'),
                                    '--output', str(output), '--manifest-only']):
                build['main']()

            template = (ROOT / 'tools/build/addon-manifest.toc').read_bytes()
            self.assertEqual(output.read_bytes(), metadata + template)

    def test_debug_manifest_preserves_runtime_order_and_loads_trace_before_safety(self):
        def entries(manifest):
            return [line for line in manifest.decode().splitlines() if line and not line.startswith('#')]

        production = entries(build['get_manifest']())
        debug = entries(build['get_manifest'](dev_debug=True))
        trace = 'diagnostics/dev-debug.lua'
        self.assertNotIn(trace, production)
        self.assertEqual(debug.count(trace), 1)
        local_tools = {trace, 'diagnostics/dev-benchmark.lua', 'diagnostics/dev-api-probe.lua'}
        for entry in local_tools:
            self.assertNotIn(entry, production)
            self.assertEqual(debug.count(entry), 1)
        self.assertEqual([entry for entry in debug if entry not in local_tools], production)
        self.assertGreater(debug.index('diagnostics/dev-benchmark.lua'), debug.index('diagnostics/benchmark.lua'))
        self.assertGreater(debug.index('diagnostics/dev-api-probe.lua'), debug.index('diagnostics/diagnostics.lua'))
        self.assertEqual(debug[debug.index(trace) + 1], 'core/safety.lua')
        for entry in debug:
            self.assertTrue((ROOT / 'ForeverRosettaStone' / entry).is_file(), entry)

    def test_manifest_refresh_refuses_unknown_files_without_changing_them(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'unknown.toc'
            original = b'Unrecognized manifest\n'
            output.write_bytes(original)

            with self.assertRaisesRegex(ValueError, 'missing ## Interface header'):
                build['refresh_manifest'](output)

            self.assertEqual(output.read_bytes(), original)

    def test_english_details_keep_templates_and_item_effect_links(self):
        _, api, _ = self.create_runtime()
        spell = api.GetSpellDetails(api, 10, b'enUS')
        self.assertIn(b'${$1279976m1*$d*$<frostdamage>}', spell[b'description'])
        self.assertEqual(spell[b'durationMs'], 8000)
        self.assertIsNone(spell[b'sourceDescriptions'])
        self.assertIsNone(api.GetSpellDetails(api, 10, b'enGB'))
        item = api.GetItemDetails(api, 2102, b'enUS')
        self.assertEqual(item[b'containerSlots'], 6)
        self.assertTrue(any(effect[b'spellID'] == 14824 for effect in item[b'effects'].values()))
        stoneform = api.GetSpellDetails(api, 20594, b'enUS')
        self.assertEqual(stoneform[b'rank'], b'Racial')
        self.assertIsNone(stoneform[b'sourceRanks'])
        self.assertEqual(api.GetSpellDetails(api, 20594, b'frFR')[b'rank'], b'Raciale')
        self.assertEqual(api.GetItemName(api, 967, b'enUS'), b'Tome of Frost Ward')
        flavor = api.GetItemDetails(api, 11511, b'enUS')
        self.assertIsNone(flavor[b'sourceDescriptions'])

    def test_only_canonical_english_is_exposed(self):
        self.assertFalse(any(key.startswith(b'x-rosetta-engb-') for key in self.metadata))
        lua, api, counts = self.create_runtime()
        english = api.GetQuest(api, 943, b'enUS')
        before = counts['cbor']
        british = api.GetQuest(api, 943, b'enGB')
        self.assertIsNone(british)
        self.assertEqual(counts['cbor'], before)
        title = api.GetQuest(api, 399, b'enUS')[b'title']
        self.assertIsNone(api.GetSpellName(api, 133, b'enGB'))
        self.assertNotIn(b'enGB', api.GetLocales(api))

    def test_languages_load_only_on_request_and_switch_without_reloading(self):
        _, api, counts = self.create_runtime()
        self.assertEqual(counts['packs'], [])
        self.assertLess((ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc').stat().st_size, 16 * 1024)
        api.LoadLocale(api, b'enUS')
        self.assertEqual(counts['packs'], [b'ForeverRosettaStone_Data_enUS'])
        english = api.GetQuest(api, 943, b'enUS')
        api.LoadLocale(api, b'deDE')
        self.assertIsNotNone(api.GetQuest(api, 943, b'deDE'))
        self.assertEqual(api.GetQuest(api, 943, b'enUS')[b'title'], english[b'title'])
        self.assertEqual(counts['packs'], [b'ForeverRosettaStone_Data_enUS', b'ForeverRosettaStone_Data_deDE'])

    def test_runtime_replays_load_real_packs_without_a_preparsed_page_inventory(self):
        metadata = read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc', include_pages=False)
        _, expected, _ = self.create_runtime()
        _, actual, counts = self.create_runtime(metadata)
        self.assertEqual(counts['packs'], [])
        for locale in (b'enUS', b'frFR'):
            self.assertEqual(actual.GetQuest(actual, 943, locale)[b'title'],
                             expected.GetQuest(expected, 943, locale)[b'title'])
            self.assertEqual(actual.GetSpellDetails(actual, 133, locale)[b'description'],
                             expected.GetSpellDetails(expected, 133, locale)[b'description'])
        self.assertEqual(set(counts['packs']), {b'ForeverRosettaStone_Data_enUS',
                                              b'ForeverRosettaStone_Data_frFR', b'ForeverRosettaStone_Rules'})

    def test_source_packs_and_legacy_source_apis_are_absent(self):
        _, api, _ = self.create_runtime()
        self.assertFalse(list(ROOT.glob('ForeverRosettaStone_Source_*')))
        self.assertFalse(any(b'-source-' in key for key in self.metadata))
        for method in ('GetQuestSource', 'GetSourceSpellName', 'GetSpellSourceDetails',
                       'GetItemSourceDetails', 'GetFactionSourceName', 'TranslateAreaName',
                       'TranslateItemName', 'ResolveQuestID'):
            self.assertIsNone(api[method.encode()])

    def test_non_english_target_uses_rules_without_loading_english_translations(self):
        _, api, counts = self.create_runtime()
        api.LoadLocale(api, b'deDE')
        self.assertIsNotNone(api.GetSpellRules(api, 133)[b'effects'])
        self.assertIsNotNone(api.GetSpellDetails(api, 133, b'deDE')[b'description'])
        self.assertEqual(set(counts['packs']), {b'ForeverRosettaStone_Data_deDE',
                                              b'ForeverRosettaStone_Rules'})

    def test_rule_lookups_load_no_translation_packs(self):
        _, api, counts = self.create_runtime()
        self.assertIsNotNone(api.GetSpellRules(api, 133)[b'effects'])
        self.assertIsNotNone(api.GetItemRules(api, 2102))
        self.assertIsNone(api.GetSpellRules(api, 0))
        self.assertEqual(counts['packs'], [b'ForeverRosettaStone_Rules'])

    def test_live_capture_loads_only_target_and_original_source_packs(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR', 'deDE'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['spells']['1'] = {'locales': {
            'enUS': {'name': 'Fire', 'description': 'Deals $s1 damage.'},
            'frFR': {'description': 'Inflige $s1 dégâts.'},
            'deDE': {'name': 'Feuer', 'description': 'Verursacht $s1 Schaden.'},
        }, 'tooltipData': {'effects': [{'index': 0, 'basePoints': 5}]}}

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            lua, api, counts = self.create_runtime(read_metadata(output))
            api.LoadLocale(api, b'deDE')
            translated = lua.execute('''
                GetLocale = function() return "frFR" end
                canaccessallvalues = function() return true end
                Enum = { TooltipDataLineType = { SpellDescription = 34 } }
                C_Spell = { GetSpellDescription = function() error("native description used") end }
                GetSpellDescription = C_Spell.GetSpellDescription
                ForeverRosettaStoneDB.GetSpellSourceDetails = function() error("native source used") end
                local Addon = {}
                assert(loadfile("ForeverRosettaStone/tooltips/spell-live-values.lua"))("ForeverRosettaStone", Addon)
                assert(loadfile("ForeverRosettaStone/tooltips/tooltip-descriptions.lua"))("ForeverRosettaStone", Addon)
                local text = Addon:GetLocalizedTooltipLine({ type = 34, leftText = "Inflige 42 dégâts." },
                    "spell", 1, "deDE")
                return text
            '''.encode())
            self.assertEqual(translated, b'Verursacht 42 Schaden.')
            self.assertEqual(set(counts['packs']), {b'ForeverRosettaStone_Data_deDE', b'ForeverRosettaStone_Data_frFR'})

    def test_pack_load_failure_and_catalog_mismatch_are_explicit(self):
        lua, api, counts = self.create_runtime()
        lua.execute(b'C_AddOns.LoadAddOn = function() return false, "DISABLED" end')

        with self.assertRaisesRegex(Exception, 'Cannot load Forever Rosetta Stone data addon.*DISABLED'):
            api.LoadLocale(api, b'enUS')

        with self.assertRaisesRegex(Exception, 'different catalog version'):
            api.RegisterStorage(api, b'ForeverRosettaStone_Data_enUS', b'wrong-version', lua.table())

        self.assertEqual(counts['packs'], [])

    def test_aura_only_locale_and_cast_description_stay_separate(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR', 'deDE'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['spells']['1'] = {'locales': {
            'enUS': {'name': 'Spell', 'description': 'Cast $s1 for $d.', 'auraDescription': 'Aura $s1.',
                     'translationMetadata': {'fields': {'name': {'origin': 'original'},
                         'description': {'origin': 'original'}, 'auraDescription': {'origin': 'original'}}}},
            'deDE': {'name': 'Zauber', 'auraDescription': 'Aura $s1 Schaden.',
                     'translationMetadata': {'fields': {'name': {'origin': 'original'},
                         'auraDescription': {'origin': 'ai'}}}},
            'frFR': {'auraDescription': 'Aura $s1 dégâts.'},
        }}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            _, api, _ = self.create_runtime(read_metadata(output))
            source = api.GetSpellDetails(api, 1, b'frFR')
            self.assertEqual(source[b'auraDescription'], 'Aura $s1 dégâts.'.encode())
            self.assertIsNone(source[b'description'])
            target = api.GetSpellDetails(api, 1, b'deDE')
            self.assertEqual(target[b'auraDescription'], b'Aura $s1 Schaden.')
            self.assertIsNone(target[b'description'])
            self.assertTrue(api.IsAITranslated(api, b'spells', 1, b'deDE'))
            english = api.GetSpellDetails(api, 1, b'enUS')
            self.assertEqual(english[b'auraDescription'], b'Aura $s1.')
            self.assertEqual(english[b'description'], b'Cast $s1 for $d.')
            self.assertIsNone(english[b'sourceAuraDescriptionMetadata'])

    def test_generated_packs_keep_payloads_out_of_toc_metadata(self):
        manifests = sorted((ROOT / 'ForeverRosettaStone_Data').glob('*/*.toc'))
        _, api, _ = self.create_runtime()
        self.assertEqual(len(manifests), len(list(api.GetLocales(api).keys())) + 1)

        for manifest in manifests:
            metadata = read_metadata(manifest)
            self.assertLess(manifest.stat().st_size, 512)
            self.assertEqual(metadata[b'loadondemand'], b'1')
            self.assertEqual(metadata[b'dependencies'], b'ForeverRosettaStone')
            self.assertEqual(metadata[b'interface'], self.metadata[b'interface'])
            self.assertEqual(metadata[b'x-rosetta-catalog'], self.metadata[b'x-rosetta-catalog'])
            entries = [line for line in manifest.read_text().splitlines() if line and not line.startswith('#')]
            self.assertEqual(entries, ['data.lua'])
            self.assertTrue((manifest.parent / 'data.lua').is_file())

        self.assertFalse(any(b'-source-' + kind + b'-' in key for key in self.metadata
                             for kind in (b'npcs', b'talents', b'maps')))

    def test_english_tooltip_rules_are_not_duplicated_in_translation_pages(self):
        lua, api, _ = self.create_runtime()
        directory, _ = decode_page(lua, self.metadata, b'x-rosetta-enus-spells-index')
        index = max(position for position, first_id in directory.items() if first_id <= 133)
        page, _ = decode_page(lua, self.metadata, f'x-rosetta-enus-spells-{index}'.encode())
        position = next(position for position, spell_id in page[1].items() if spell_id == 133)
        self.assertIsNone(page[3][position][b'effects'])
        self.assertIsNotNone(api.GetSpellDetails(api, 133, b'enUS')[b'effects'])

    def test_build_rejects_removed_english_locale(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'enGB'], 'catalogs': {'quests': {
            '1': {'locales': {'enUS': {'title': 'US text'}, 'enGB': {'title': 'UK text'}}},
        }}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}

        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, 'enGB is not supported'):
                build['export_database'](create_documents(quests, names), Path(directory) / 'addon/runtime.toc')

    def test_detail_only_translations_validate_the_fields_actually_present(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'hrHR'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['spells']['1'] = {'locales': {'enUS': {'name': 'Spell', 'rank': 'Rank 4'}, 'hrHR': {
            'rank': 'Rang 4', 'translationMetadata': {'fields': {'rank': {'origin': 'ai', 'source': 'testFixture'}}},
        }}}

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            _, api, _ = self.create_runtime(read_metadata(output))
            self.assertEqual(api.GetSpellDetails(api, 1, b'hrHR')[b'rank'], b'Rang 4')
            self.assertIsNone(api.GetSpellName(api, 1, b'hrHR'))
            self.assertTrue(api.IsAITranslated(api, b'spells', 1, b'hrHR'))

    def test_multilingual_details_export_target_text_without_english_fallback(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR', 'itIT', 'plPL'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        localized = {locale: {'name': locale} for locale in quests['locales']}
        names['catalogs']['spells']['1'] = {'locales': copy.deepcopy(localized), 'tooltipData': {
            'effects': [{'index': 1}],
        }}
        names['catalogs']['items']['2'] = {'locales': copy.deepcopy(localized), 'tooltipData': {
            'set': {'name': 'Set', 'items': [2]},
        }}
        names['catalogs']['spells']['1']['locales']['enUS'].update(description='Damage $s1', rank='Rank 2')
        names['catalogs']['spells']['1']['locales']['frFR'].update(description='Dégâts $s1', rank='Rang 2')
        names['catalogs']['items']['2']['locales']['enUS'].update(description='A description', nameDescription='Unique')
        names['catalogs']['items']['2']['locales']['frFR'].update(description='Une description', nameDescription='Unique FR')
        names['catalogs']['items']['2']['locales']['itIT'].update(description='Una descrizione', nameDescription='Unico')
        names['catalogs']['items']['2']['locales']['frFR']['setName'] = 'Ensemble'
        names['catalogs']['items']['2']['locales']['itIT']['setName'] = 'Completo'
        documents = create_documents(quests, names)
        if documents.get('globalstrings', {}).get('catalogs', {}).get('globalstrings', {}).get('10'):
            documents['globalstrings']['catalogs']['globalstrings']['10']['key'] = 'FIXTURE_LABEL'
        before = copy.deepcopy(documents)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](documents, output)
            _, api, _ = self.create_runtime(read_metadata(output))
            spell = api.GetSpellDetails(api, 1, b'frFR')
            self.assertEqual(spell[b'description'], 'Dégâts $s1'.encode())
            self.assertEqual(spell[b'rank'], b'Rang 2')
            self.assertIsNone(spell[b'effects'])
            self.assertIsNone(spell[b'sourceDescriptions'])
            english = api.GetSpellDetails(api, 1, b'enUS')
            self.assertEqual(english[b'effects'][1][b'index'], 1)
            self.assertIsNone(english[b'sourceDescriptions'])
            item = api.GetItemDetails(api, 2, b'frFR')
            self.assertEqual(item[b'nameDescription'], b'Unique FR')
            self.assertEqual(item[b'set'][b'name'], b'Ensemble')
            self.assertEqual(item[b'description'], b'Une description')
            italian = api.GetItemDetails(api, 2, b'itIT')
            self.assertEqual(italian[b'description'], b'Una descrizione')
            self.assertEqual(italian[b'nameDescription'], b'Unico')
            self.assertEqual(italian[b'set'][b'name'], b'Completo')
            english_item = api.GetItemDetails(api, 2, b'enUS')
            self.assertIsNone(english_item[b'sourceDescriptions'])
            self.assertIsNone(english_item[b'sourceNameDescriptions'])
            self.assertEqual(english_item[b'set'][b'name'], b'Set')
            self.assertIsNone(english_item[b'set'][b'sourceNames'])
            self.assertIsNone(api.GetItemDetails(api, 2, b'plPL'))
            self.assertIsNone(api.GetSpellDetails(api, 1, b'plPL'))
            self.assertIsNone(api.GetSpellDetails(api, 1, b'itIT'))

        self.assertEqual(documents, before)

        report = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-coverage.py'))
        italian_spell = copy.deepcopy(documents['spells']['catalogs']['spells']['1'])
        self.assertIsNone(report['get_text'](italian_spell, 'itIT', 'description'))
        self.assertIsNone(report['get_text'](italian_spell, 'itIT', 'rank'))
        italian_spell['locales']['itIT']['description'] = 'Danni $s1'
        italian_spell['locales']['itIT']['rank'] = 'Grado 2'
        projected = runtime_catalog.project_tooltip_details(italian_spell, italian_spell['locales']['itIT'], 'itIT')
        self.assertEqual(projected['description'], 'Danni $s1')
        self.assertEqual(projected['rank'], 'Grado 2')
        self.assertEqual(report['get_text'](italian_spell, 'itIT', 'description'), 'Danni $s1')
        self.assertEqual(report['get_text'](italian_spell, 'itIT', 'rank'), 'Grado 2')

    def test_owned_target_details_override_matching_sources_and_mark_ai(self):
        original = {
            'name': 'Objet', 'description': 'Une description', 'rank': 'Rang traduit',
            'nameDescription': 'Sous-titre traduit', 'setName': 'Ensemble traduit',
        }
        original['translationMetadata'] = {'fields': {
            field: {'origin': 'ai' if field != 'name' else 'original', 'source': 'fixture'}
            for field in original
        }}
        entity = {'locales': {'enUS': {'name': 'Item', 'description': 'Description', 'rank': 'Rank',
            'nameDescription': 'Subtitle', 'setName': 'Set'}, 'frFR': original}, 'tooltipData': {
            'sourceRanks': {'frFR': 'Rang source'}, 'sourceNameDescriptions': {'frFR': 'Sous-titre source'},
            'set': {'name': 'English set', 'sourceNames': {'frFR': 'Ensemble source'}},
        }}
        before = copy.deepcopy(entity)
        projected = runtime_catalog.project_localized_record('items', '1', entity, 'frFR', {})
        self.assertTrue(projected['hasAITranslation'])
        self.assertEqual(projected['details'], {
            'description': 'Une description', 'rank': 'Rang traduit',
            'nameDescription': 'Sous-titre traduit', 'set': {'name': 'Ensemble traduit'},
        })
        self.assertEqual(entity, before)

    def test_foreign_source_english_translation_is_target_text_only(self):
        metadata = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'zhTW'}
        original = {'name': 'Ingredient', 'description': 'Ingredient for poisons.', 'rank': 'Rank 1',
                    'translationMetadata': {'fields': {'name': {'origin': 'original', 'source': 'fixture'},
                                                     'description': metadata, 'rank': metadata}}}
        entity = {'locales': {'enUS': original, 'zhTW': {
            'description': '製毒的材料。', 'rank': '等級 1',
            'translationMetadata': {'fields': {
                field: {'origin': 'original', 'source': 'fixture', 'sourceLocale': 'zhTW'}
                for field in ('description', 'rank')
            }},
        }}}
        projected = runtime_catalog.project_localized_record('spells', '1', entity, 'enUS', {})
        self.assertTrue(projected['hasAITranslation'])
        self.assertEqual(projected['details']['description'], original['description'])
        self.assertEqual(projected['details']['rank'], 'Rank 1')
        report = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-coverage.py'))
        self.assertEqual(report['get_text'](entity, 'enUS', 'description'), original['description'])
        self.assertEqual(report['get_text'](entity, 'enUS', 'rank'), 'Rank 1')
        self.assertIsNone(report['get_text'](entity, 'enGB', 'description'))
        self.assertIsNone(report['get_text'](entity, 'enGB', 'rank'))

    def test_quest_titles_export_as_normal_localized_records(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {
            '1': {'locales': {'enUS': {'title': 'Quest'}, 'frFR': {'title': 'Titre source'}}},
        }}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['spells']['2'] = {
            'locales': {'enUS': {'name': 'Spell'}}, 'sourceNames': {'frFR': 'Sort source'},
        }

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            _, api, _ = self.create_runtime(read_metadata(output))
            self.assertIsNone(api.GetSpellName(api, 2, b'frFR'))
            self.assertEqual(api.GetQuest(api, 1, b'frFR')[b'title'], b'Titre source')

    def test_canonical_offer_replaces_only_english_description_fallback(self):
        english = 'Bring the letter.'
        offer = 'Apportez la lettre.'
        record = {
            'dialogueContexts': {'description': {
                'stage': 'accept', 'sourceField': 'description',
                'sourceDescriptionSha256': hashlib.sha256(english.encode()).hexdigest(),
            }},
            'locales': {
                'enUS': {'title': 'Quest', 'description': english},
                'frFR': {'title': 'Quête', 'description': english, 'dialogue': {'description': offer},
                         'translationMetadata': {'fields': {'dialogue.description': {'origin': 'ai'}}}},
            },
        }
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {'1': record}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](create_documents(quests, names), output)
            _, api, _ = self.create_runtime(read_metadata(output))
            self.assertEqual(api.GetQuest(api, 1, b'enUS')[b'description'].decode(), english)
            self.assertEqual(api.GetQuest(api, 1, b'frFR')[b'description'].decode(), offer)
            self.assertTrue(api.GetQuest(api, 1, b'frFR')[b'hasAITranslation'])
            self.assertIsNone(api.GetQuestDialogue(api, 1, None, b'frFR'))

        localized = record['locales']['frFR']
        localized['description'] = 'Remettez la lettre.'
        projected = runtime_catalog.project_localized_record('quests', 1, record, 'frFR', {})
        self.assertEqual(projected['description'], localized['description'])
        self.assertFalse(projected['hasAITranslation'])

        record['locales']['enUS']['description'] = 'Bring both letters.'
        localized['description'] = record['locales']['enUS']['description']
        projected = runtime_catalog.project_localized_record('quests', 1, record, 'frFR', {})
        self.assertEqual(projected['description'], localized['description'])
        self.assertFalse(projected['hasAITranslation'])

    @classmethod
    def setUpClass(cls):
        cls.metadata = read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc', include_pages=True)

    def create_runtime(self, metadata=None):
        lua = LuaRuntime(encoding=None)
        counts = install_metadata(lua, self.metadata if metadata is None else metadata)
        api = load_database(lua)

        return lua, api, counts

    def test_captured_objectives_remain_available_as_localized_templates(self):
        fixture = json.loads((ROOT / 'tests/fixtures/quest-objective-sources-70888.json').read_text())
        _, api, _ = self.create_runtime()

        for locale in (fixture['locale'], 'enUS'):
            for observed in fixture['objectives']:
                with self.subTest(quest=observed['questId'], index=observed['index'], locale=locale):
                    source = api.GetQuest(api, observed['questId'], locale.encode())
                    lines = source[b'objectiveLines'] if source else None
                    line = next((line for line in (lines.values() if lines else [])
                                 if line[b'index'] == observed['index']), None)
                    self.assertIsNotNone(line, 'Captured objective must remain available for native matching')
                    self.assertEqual(line[b'type'].decode(), observed['type'])
                    rendered = line[b'text'].decode().replace('{current}', str(observed['numFulfilled']))
                    rendered = rendered.replace('{required}', str(observed['numRequired']))
                    self.assertEqual(rendered, observed['text'])

    def test_quest_170_objectives_cover_every_target_language(self):
        _, api, _ = self.create_runtime()
        locales = load_catalog(ROOT, 'quests', ids={})['locales']

        for locale in locales:
            with self.subTest(locale=locale):
                quest = api.GetQuest(api, 170, locale.encode())
                lines = quest[b'objectiveLines'] if quest else None
                self.assertIsNotNone(lines)
                self.assertEqual({line[b'index'] for line in lines.values()}, {1, 2})

                for line in lines.values():
                    self.assertEqual(line[b'type'], b'monster')
                    self.assertIn(b'{current}', line[b'text'])
                    self.assertIn(b'{required}', line[b'text'])

    def test_scanned_quest_exports_preserve_each_maintained_language_template(self):
        fixture = json.loads((ROOT / 'tests/fixtures/quest-objective-sources-70888.json').read_text())
        get_tokens = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))['get_tokens']
        _, api, _ = self.create_runtime()
        locales = load_catalog(ROOT, 'quests', ids={})['locales']

        for observed in fixture['questText']:
            quest_id, field = observed['questId'], observed['field'].encode()
            entity = json.loads((ROOT / 'catalogs/quests' / f'{quest_id}.json').read_bytes())

            for locale in locales:
                with self.subTest(quest=quest_id, field=observed['field'], target=locale):
                    target = api.GetQuest(api, quest_id, locale.encode())
                    maintained = entity['locales'][locale][observed['field']]
                    self.assertEqual(target[field].decode(), maintained)
                    self.assertEqual(get_tokens(target[field].decode()), get_tokens(maintained))

    def test_export_keeps_runtime_fields_and_filters_development_quests(self):
        objective = {'index': 1, 'type': 'item', 'objectiveType': 1, 'numRequired': 5,
                     'text': '{current}/{required} Pelts'}
        localized = {
            'title': 'Playable quest', 'summary': 'Collect pelts', 'description': 'Quest narrative',
            'eventObjectiveLabel': 'Place the trap', 'objectiveLines': [objective],
            'hasAITranslation': False, 'catalogOnly': 'must not ship',
            'translationMetadata': {'fields': {
                field: {'origin': 'ai' if field == 'objectiveLines.1' else 'community', 'source': 'testFixture'}
                for field in ('title', 'summary', 'description', 'eventObjectiveLabel', 'objectiveLines.1')
            }},
        }
        records = {'1': {'areaId': 15, 'objectiveTargets': {'item': [{'id': 1}]},
                         'locales': {'enUS': localized, 'frFR': copy.deepcopy(localized)}}}

        for quest_id, status in enumerate(('test', 'notImplemented', 'placeholder', 'unused',
                                            'temporarilyDisabled'), start=2):
            records[str(quest_id)] = {'usageStatus': status, 'locales': copy.deepcopy(records['1']['locales'])}

        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': records}}
        names = {'catalogs': {kind: {'10': {'locales': {
            'enUS': {'name': kind, 'catalogOnly': 'must not ship', 'translationMetadata': {'fields': {
                'name': {'origin': 'community', 'source': 'testFixture', 'sourceWasAITranslated': True},
            }}},
            'frFR': {'name': kind + ' FR', 'translationMetadata': {'fields': {
                'name': {'origin': 'ai', 'source': 'testFixture'},
            }}},
        }}} for kind in build['KINDS'] if kind != 'quests'}}
        if 'bookpages' in names['catalogs']:
            for record in names['catalogs']['bookpages']['10']['locales'].values():
                record['description'] = record.pop('name')
                fields = record['translationMetadata']['fields']
                fields['description'] = fields.pop('name')
        documents = create_documents(quests, names)
        if documents.get('globalstrings', {}).get('catalogs', {}).get('globalstrings', {}).get('10'):
            documents['globalstrings']['catalogs']['globalstrings']['10']['key'] = 'FIXTURE_LABEL'
        before = copy.deepcopy(documents)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](documents, output)
            metadata = read_metadata(output, include_pages=True)
            lua, api, _ = self.create_runtime(metadata)
            expected = {field.encode() for field in runtime_catalog.QUEST_FIELDS} | {b'hasAITranslation'}

            for locale in (b'enUS', b'frFR'):
                quest = api.GetQuest(api, 1, locale)
                self.assertEqual(set(quest.keys()), expected)
                self.assertTrue(quest[b'hasAITranslation'])
                self.assertEqual(set(quest[b'objectiveLines'][1].keys()), {b'index', b'type', b'text'})

                for quest_id in range(2, 6):
                    self.assertIsNone(api.GetQuest(api, quest_id, locale))

                self.assertIsNotNone(api.GetQuest(api, 6, locale))

            page, _ = decode_page(lua, metadata, b'x-rosetta-enus-quests-1')
            self.assertEqual(list(page[1].values()), [1, 6])
            self.assertFalse(any(key.endswith(b'-r') for key in metadata))

            for kind in build['KINDS']:
                if kind == 'quests':
                    continue

                english, _ = decode_page(lua, metadata, f'x-rosetta-enus-{kind}-1'.encode())
                self.assertEqual(len(english), 4 if kind in ('items', 'spells', 'npcs', 'books', 'races') else 3)
                self.assertEqual(english[2][1].decode(), kind)
                self.assertEqual(english[len(english)], b'')
                self.assertFalse(api.IsAITranslated(api, kind.encode(), 10, b'enUS'))
                if kind != 'globalstrings':
                    self.assertTrue(api.IsAITranslated(api, kind.encode(), 10, b'frFR'))

        self.assertEqual(documents, before, 'Export must not mutate the full catalogs')

    def test_verified_item_objectives_compile_without_catalog_changes(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {'1': {
            'clientObjectiveTargets': [{'id': 10, 'kind': 'item'}, {'id': 11, 'kind': 'item'},
                                       {'id': 20, 'kind': 'npc', 'type': 'monster'}],
            'objectiveTargets': {'item': [{'id': 10, 'sourceIndex': 3}]},
            'locales': {
                'enUS': {'title': 'Quest'},
                'frFR': {'title': 'Quête', 'objectiveLines': [
                    {'index': 1, 'type': 'item', 'text': 'Texte conservé {current}/{required}'},
                ], 'translationMetadata': {'fields': {
                    'title': {'origin': 'original', 'source': 'testFixture'},
                    'objectiveLines.1': {'origin': 'original', 'source': 'testFixture'},
                }}},
            },
        }}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['items']['10'] = {'locales': {
            'enUS': {'name': 'Pelt', 'translationMetadata': {'fields': {
                'name': {'origin': 'ai', 'source': 'testFixture'},
            }}},
        }}
        names['catalogs']['npcs']['20'] = {'locales': {
            locale: {'name': name, 'translationMetadata': {'fields': {
                'name': {'origin': 'original', 'source': 'testFixture'},
            }}} for locale, name in (('enUS', 'Wolf'), ('frFR', 'Loup'))
        }}
        documents = create_documents(quests, names)
        if documents.get('globalstrings', {}).get('catalogs', {}).get('globalstrings', {}).get('10'):
            documents['globalstrings']['catalogs']['globalstrings']['10']['key'] = 'FIXTURE_LABEL'
        before = copy.deepcopy(documents)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](documents, output)
            _, api, _ = self.create_runtime(read_metadata(output))
            english = api.GetQuest(api, 1, b'enUS')
            lines = english[b'objectiveLines']
            self.assertEqual(len(lines), 2)
            self.assertEqual(lines[1][b'index'], 1)
            self.assertEqual(lines[1][b'type'], b'item')
            self.assertEqual(lines[1][b'text'], b'Pelt: {current}/{required}')
            self.assertEqual(lines[2][b'index'], 3)
            self.assertEqual(lines[2][b'type'], b'monster')
            self.assertEqual(lines[2][b'text'], b'Wolf: {current}/{required}')
            self.assertTrue(english[b'hasAITranslation'])
            french = api.GetQuest(api, 1, b'frFR')
            self.assertEqual(french[b'objectiveLines'][1][b'text'], b'Texte conserv\xc3\xa9 {current}/{required}')
            self.assertEqual(french[b'objectiveLines'][2][b'text'], b'Loup: {current}/{required}')
            self.assertFalse(french[b'hasAITranslation'])

        self.assertEqual(documents, before)

    def test_only_small_locale_manifest_decodes_at_load(self):
        lua, api, counts = self.create_runtime()
        self.assertEqual({key: counts[key] for key in ('base64', 'inflate', 'cbor')},
                         {'base64': 1, 'inflate': 1, 'cbor': 1})
        english = api.GetQuest(api, 943, b'enUS')
        self.assertEqual(english[b'title'], b'The Absent Minded Prospector')
        self.assertEqual(counts['inflate'], 3, 'English lookups decode only a directory and one page')
        self.assertEqual(counts['cbor'], 3)
        self.assertTrue(lua.eval(b'function(a,b) return a == b end')(english, api.GetQuest(api, 943, b'enUS')))
        self.assertEqual(counts['cbor'], 3, 'Repeated reads reuse the held quest record')

    def test_first_lookups_decode_small_pages(self):
        for kind in ('quest', 'spell'):
            with self.subTest(kind=kind):
                lua, api, counts = self.create_runtime()
                before = counts['decoded_bytes']

                if kind == 'quest':
                    self.assertIsNotNone(api.GetQuest(api, 943, b'frFR'))
                elif kind == 'spell':
                    self.assertIsNotNone(api.GetSpellName(api, 133, b'frFR'))

                self.assertLess(counts['decoded_bytes'] - before, 80 * 1024,
                                'A single lookup must not decode the complete locale dataset')

    def test_name_page_cache_has_bounded_retained_memory(self):
        lua, api, _ = self.create_runtime()
        api.LoadLocale(api, b'frFR')
        lua.gccollect()
        before = lua.eval(b'collectgarbage("count")')
        spells = load_catalog(ROOT, 'spells')['catalogs']['spells']

        for spell_id in sorted(map(int, spells))[::128]:
            api.GetSpellName(api, spell_id, b'frFR')

        lua.gccollect()
        self.assertLess(lua.eval(b'collectgarbage("count")') - before, 512,
                        'Browsing spells must not retain every decoded locale record')

    def test_sparse_columns_ai_bits_and_held_records_survive_page_eviction(self):
        records = {}
        ai_ids = {1, 8, 9, 128, 129, 256, 260}

        for quest_id in range(1, 401):
            english = {
                'title': 'Duplicate' if quest_id in (1, 260) else 'Quest ' + str(quest_id),
                'translationMetadata': {'fields': {
                    'title': {'origin': 'ai' if quest_id in ai_ids else 'original', 'source': 'testFixture'},
                }},
            }

            if quest_id % 3 == 0:
                english['description'] = 'Narrative ' * 20
                english['translationMetadata']['fields']['description'] = {
                    'origin': 'original', 'source': 'testFixture',
                }

            localized = {'enUS': english}

            if quest_id % 2 == 0:
                localized['frFR'] = {'title': 'Quête ' + str(quest_id)}

            records[str(quest_id)] = {'locales': localized}

        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': records}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'

            with patch.object(database_storage, 'PAGE_BYTE_LIMIT', 1024):
                build['export_database'](create_documents(quests, names), output)

            lua, api, counts = self.create_runtime(read_metadata(output))
            held = api.GetQuest(api, 1, b'enUS')

            for quest_id in range(1, 401):
                english = api.GetQuest(api, quest_id, b'enUS')
                self.assertEqual(english[b'hasAITranslation'], quest_id in ai_ids)
                self.assertEqual(english[b'description'] is not None, quest_id % 3 == 0)
                french = api.GetQuest(api, quest_id, b'frFR')
                self.assertEqual(french is not None, quest_id % 2 == 0)

                if french is not None:
                    self.assertIsNone(french[b'description'])
                    self.assertFalse(french[b'hasAITranslation'])

            self.assertGreater(counts['cbor'], 8)
            lua.gccollect()
            self.assertTrue(lua.eval(b'function(a,b) return a == b end')(held, api.GetQuest(api, 1, b'enUS')))

    def test_previous_storage_format_is_rejected(self):
        metadata = {**self.metadata, b'x-rosetta-format': b'3'}

        with self.assertRaisesRegex(Exception, 'Unsupported Forever Rosetta Stone database format'):
            self.create_runtime(metadata)

    def test_locales_are_independent_and_missing_values_do_not_fallback(self):
        _, api, counts = self.create_runtime()
        french = api.GetQuest(api, 943, b'frFR')
        french_title = french[b'title']
        self.assertEqual(counts['inflate'], 3)
        self.assertEqual(api.GetQuest(api, 943, b'enUS')[b'title'], b'The Absent Minded Prospector')
        self.assertEqual(french[b'title'], french_title)
        self.assertIsNone(api.GetQuest(api, 943, b'xxXX'))
        self.assertIsNone(api.GetQuest(api, 999999999, b'enUS'))
        self.assertIsNone(api.GetQuest(api, None, b'enUS'))
        self.assertIsNone(api.GetQuest(api, b'943', b'enUS'))
        self.assertIsNone(api.GetQuest(api, -1, b'enUS'))
        self.assertEqual(api[b'apiVersion'], 3)
        self.assertEqual(len(api[b'catalogVersion']), 64)

    def test_all_entity_kinds_and_ai_flags(self):
        _, api, _ = self.create_runtime()
        self.assertEqual(api.GetItemName(api, 5626, b'enUS'), b'Skullchipper')
        self.assertIsNotNone(api.GetNpcName(api, 266484, b'frFR'))
        self.assertIsNotNone(api.GetAreaName(api, 2104, b'enUS'))
        self.assertEqual(api.GetSpellName(api, 133, b'enUS'), b'Fireball')
        self.assertIsNotNone(api.GetTalentName(api, 23, b'enUS'))
        self.assertIsNone(api.GetTalentName(api, 134370, b'enUS'), 'Live talent IDs are not DB2 IDs')
        quest = api.GetQuest(api, 943, b'itIT')
        self.assertTrue(quest[b'hasAITranslation'])
        self.assertIsNone(quest[b'translationMetadata'])
        self.assertTrue(api.IsQuestAITranslated(api, 943, b'itIT'))
        self.assertFalse(api.IsQuestAITranslated(api, 943, b'enUS'))
        self.assertIsNone(api.IsQuestAITranslated(api, 999999999, b'itIT'))
        self.assertIsNone(api.IsQuestAITranslated(api, 943, b'xxXX'))

        for kind, entity_id in ((b'items', 5626), (b'npcs', 2911), (b'areas', 11),
                                (b'spells', 133), (b'talents', 23), (b'maps', 1415)):
            self.assertFalse(api.IsAITranslated(api, kind, entity_id, b'enUS'))

        self.assertIsNone(api.IsAITranslated(api, b'items', 5626, b'xxXX'))
        self.assertIsNone(api.IsAITranslated(api, b'unknown', 1, b'enUS'))
        self.assertIsNone(api.GetTranslationMetadata)
        self.assertIsNone(api.IsFieldAITranslated)
        self.assertIsNone(api.GetQuestRelations)

    def test_shipped_tooltip_details_exclude_maintenance_metadata(self):
        _, api, _ = self.create_runtime()
        item = api.GetItemDetails(api, 100, b'enUS')
        spell = api.GetSpellDetails(api, 1283034, b'enUS')
        self.assertEqual(item[b'classID'], 4)
        self.assertIsNotNone(spell[b'effects'])

        for details in (item, spell):
            for field in ('translationMetadata', 'sourceBuild', 'sourceLocale', 'effectSourceMetadata',
                          'sourceAuraDescriptionMetadata'):
                with self.subTest(field=field):
                    self.assertIsNone(details[field.encode()])

    def test_shipped_inventory_excludes_only_classified_development_quests(self):
        quests = load_catalog(ROOT, 'quests')['catalogs']['quests']
        kept = {int(quest_id) for quest_id, quest in quests.items()
                if quest.get('usageStatus') not in {'test', 'notImplemented', 'placeholder', 'unused'}}
        lua, api, _ = self.create_runtime()
        exported = set()

        for key, kind, locale in iter_data_pages(self.metadata):
            if kind == 'quests' and locale == 'enus':
                page, _ = decode_page(lua, self.metadata, key)
                exported.update(page[1].values())

        self.assertEqual(exported, kept)
        self.assertLess(len(kept), len(quests))

        for quest_id, quest in quests.items():
            if int(quest_id) not in kept:
                self.assertIsNone(api.GetQuest(api, int(quest_id), b'enUS'))
                self.assertIsNone(api.GetQuest(api, int(quest_id), b'frFR'))

    def test_tool_category_names_and_spell_rules_are_available_without_item_names(self):
        _, api, _ = self.create_runtime()
        self.assertEqual(list(api.GetSpellRules(api, 7418)[b'requiredToolCategories'].values()), [373])
        self.assertEqual(api.GetTotemCategoryName(api, 373, b'enUS').decode(), 'Runed Copper Rod')
        self.assertEqual(api.GetTotemCategoryName(api, 373, b'frFR').decode(), 'Bâtonnet runique en cuivre')
        self.assertEqual(api.GetTotemCategoryName(api, 373, b'plPL').decode(), 'Runiczna miedziana różdżka')
        self.assertIsNone(api.GetTotemCategoryName(api, 6218, b'enUS'))
        self.assertEqual(list(api.GetSpellRules(api, 3955)[b'requiredToolCategories'].values()), [162, 14])
        self.assertEqual(api.GetTotemCategoryName(api, 162, b'deDE').decode(), 'Schmiedehammer')
        item_tool = api.GetSpellRules(api, 818)
        self.assertEqual(list(item_tool[b'requiredToolItems'].values()), [4471])
        self.assertIsNone(item_tool[b'requiredToolCategories'])
        self.assertEqual(api.GetItemName(api, 4471, b'frFR').decode(), 'Silex et amadou')

    def test_captured_gossip_options_ship_all_locales_and_honest_ai_flags(self):
        _, api, _ = self.create_runtime()
        targets = load_catalog(ROOT, 'quests', ids={})['locales']
        options = load_catalog(ROOT, 'gossipoptions')['catalogs']['gossipoptions']
        captured_ids = {96904, 96905, 96906, 96907, 96908, 96909, 96910, 96911,
                        96912, 96913, 96914, 96915, 96916, 140186, 141988, 141989}
        captured_ids.update(range(95408, 95420))
        captured_ids.update((97329, 143270))
        self.assertTrue(captured_ids.issubset({int(key) for key in options}))
        for option_id in captured_ids:
            entity = options[str(option_id)]
            self.assertTrue(set(targets).issubset(entity['locales']))
            for locale in targets:
                with self.subTest(option=option_id, locale=locale):
                    localized = entity['locales'][locale]
                    self.assertTrue(localized['name'])
                    self.assertEqual(api.GetGossipOptionName(api, option_id, locale.encode()).decode(), localized['name'])
                    origin = localized['translationMetadata']['fields']['name']['origin']
                    self.assertEqual(api.IsAITranslated(api, b'gossipoptions', option_id, locale.encode()), origin == 'ai')
        self.assertEqual(api.GetGossipOptionName(api, 96916, b'frFR').decode(), 'Hôtel des ventes')
        self.assertEqual(api.GetGossipOptionName(api, 95418, b'enUS').decode(), 'Bank of Ironforge')
        self.assertEqual(api.GetGossipOptionName(api, 97329, b'enUS').decode(), 'I need a ride.')
        self.assertEqual(api.GetGossipOptionNameByIcon(api, 132057, b'enUS').decode(), 'I need a ride.')
        self.assertIsNone(api.GetGossipOptionNameByIcon(api, 132053, b'enUS'))
        self.assertEqual(api.GetGossipOptionName(api, 95418, b'frFR').decode(), 'Banque de Forgefer')
        self.assertFalse(api.IsAITranslated(api, b'gossipoptions', 96916, b'frFR'))
        self.assertFalse(api.IsAITranslated(api, b'gossipoptions', 96916, b'enUS'))
        self.assertTrue(api.IsAITranslated(api, b'gossipoptions', 96904, b'enUS'))
        self.assertIsNone(api.GetGossipOptionName(api, 0, b'enUS'), 'orderIndex is not the catalog identity')
        self.assertIsNone(api.GetGossipOptionName(api, 999999999, b'enUS'))
        self.assertIsNone(api.GetGossipOptionName(api, 96916, b'xxXX'))

    def test_book_catalog_bodies_rules_and_ai_flags_are_available_by_id(self):
        _, api, _ = self.create_runtime()
        entity = json.loads((ROOT / 'catalogs/bookpages/2097.json').read_text())
        for locale in load_catalog(ROOT, 'quests', ids={})['locales']:
            self.assertEqual(api.GetBookPage(api, 2097, locale.encode()).decode(),
                             entity['locales'][locale]['description'])
            origin = entity['locales'][locale]['translationMetadata']['fields']['description']['origin']
            self.assertEqual(api.IsAITranslated(api, b'bookpages', 2097, locale.encode()), origin == 'ai')
        rules = api.GetBookRules(api, 2097)
        self.assertEqual(list(rules[b'pages'].values()), [2097, 2098, 2099, 2100])
        self.assertEqual(api.GetBookName(api, 2097, b'frFR').decode(), 'Guerre civile dans les Maleterres')
        self.assertIsNone(api.GetBookPage(api, 2097, b'xxXX'))

    def test_every_shipped_page_has_compact_columns_and_bounded_size(self):
        lua, _, _ = self.create_runtime()
        validate = lua.eval(b"""function(page, kind)
            assert(#page == (kind == "quests" and 7 or (kind == "items" or kind == "spells" or kind == "npcs" or kind == "books" or kind == "races") and 4 or 3))
            assert(#page[1] <= 128)
            assert(type(page[#page]) == "string")
            assert(#page[#page] <= math.ceil(#page[1] / 8))
            local previous = 0
            for _, id in ipairs(page[1]) do
                assert(type(id) == "number" and id > previous)
                previous = id
            end
            for column = 2, #page - 1 do
                for position, value in pairs(page[column]) do
                    assert(page[1][position] ~= nil)
                    local isDetails = (kind == "items" or kind == "spells" or kind == "npcs" or kind == "books" or kind == "races") and column == 3
                    assert(type(value) == ((column == 6 or isDetails) and "table" or "string"))
                end
            end
        end""")
        checked_kinds = set()

        for key, kind, _ in iter_data_pages(self.metadata):
            page, raw_size = decode_page(lua, self.metadata, key)
            validate(page, kind.encode())
            self.assertTrue(raw_size <= database_storage.PAGE_BYTE_LIMIT or len(page[1]) == 1)
            checked_kinds.add(kind)

        self.assertEqual(checked_kinds, set(build['KINDS']))
        self.assertFalse(any(key.endswith(b'-ids') for key in self.metadata))

    def test_portuguese_keeps_brazilian_locale_only(self):
        _, api, _ = self.create_runtime()
        self.assertIsNone(api.GetLocales(api)[b'ptPT'])
        self.assertIsNone(api.GetQuest(api, 943, b'ptPT'))
        self.assertIsNone(api.IsQuestAITranslated(api, 943, b'ptPT'))
        self.assertIsNotNone(api.GetQuest(api, 943, b'ptBR'))
        self.assertIsNotNone(api.GetItemName(api, 5626, b'ptBR'))

    def test_completed_czech_description_is_available_with_ai_flag(self):
        _, api, _ = self.create_runtime()
        quest = api.GetQuest(api, 96045, b'csCZ')
        self.assertIsNotNone(quest[b'description'])
        self.assertTrue(quest[b'hasAITranslation'])

    def test_completed_turkish_fields_and_objectives_are_available(self):
        _, api, _ = self.create_runtime()
        quest = api.GetQuest(api, 10, b'trTR')
        self.assertIsNotNone(quest)
        self.assertIsNotNone(quest[b'title'])
        self.assertIsNotNone(quest[b'summary'])
        self.assertIsNotNone(quest[b'description'])
        self.assertTrue(quest[b'hasAITranslation'])
        objective = api.GetQuest(api, 7900, b'trTR')[b'objectiveLines'][1]
        self.assertIn(b'{current}/{required}', objective[b'text'])

    def test_completed_polish_fields_and_objectives_are_available(self):
        _, api, _ = self.create_runtime()
        quest = api.GetQuest(api, 824, b'plPL')
        self.assertIsNotNone(quest)
        for field in (b'title', b'summary', b'description'):
            self.assertIsNotNone(quest[field])
        self.assertTrue(quest[b'hasAITranslation'])
        objective = api.GetQuest(api, 7900, b'plPL')[b'objectiveLines'][1]
        self.assertIn(b'{current}/{required}', objective[b'text'])

    def test_completed_swedish_danish_and_croatian_quest_fields_are_available(self):
        _, api, _ = self.create_runtime()

        for locale in (b'svSE', b'daDK', b'hrHR'):
            quest = api.GetQuest(api, 10, locale)
            self.assertIsNotNone(quest)

            for field in (b'title', b'summary', b'description'):
                self.assertIsNotNone(quest[field])

            objective = api.GetQuest(api, 7900, locale)[b'objectiveLines'][1]
            self.assertIn(b'{current}/{required}', objective[b'text'])

    def test_missing_pages_fail_instead_of_returning_partial_text(self):
        lua, api, _ = self.create_runtime()
        directory, _ = decode_page(lua, self.metadata, b'x-rosetta-frfr-quests-index')
        index = max(position for position, first_id in directory.items() if first_id <= 943)
        key = f'x-rosetta-frfr-quests-{index}'.encode()
        lua.globals().missingPage = key.replace(b'x-rosetta', b'X-Rosetta').replace(b'frfr', b'frFR')
        lua.execute(b'''
            local register = ForeverRosettaStoneDB.RegisterStorage
            function ForeverRosettaStoneDB:RegisterStorage(name, version, pages)
                pages[missingPage] = nil
                register(self, name, version, pages)
            end
        ''')

        with self.assertRaisesRegex(Exception, 'missing page'):
            api.GetQuest(api, 943, b'frFR')

    def test_generated_fixture_is_deterministic_and_unicode_roundtrips(self):
        text = '  Éléonore\n한국어 \\"quoted\\"\x00\x01123\t'
        quests = {
            'schemaVersion': 1, 'locales': ['enUS', 'frFR'],
            'catalogs': {'quests': {'1': {'locales': {'enUS': {'title': text}, 'frFR': {'title': 'Français'}}}}},
        }
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['items']['1'] = {'locales': {'enUS': {'name': 'Sword'}, 'frFR': {
            'name': 'Épée', 'translationMetadata': {'fields': {'name': {'origin': 'ai', 'source': 'testFixture'}}},
        }}}

        with tempfile.TemporaryDirectory() as directory:
            first, second = Path(directory) / 'addon/first.toc', Path(directory) / 'addon/second.toc'
            build['export_database'](create_documents(quests, names), first)
            packs_before = {path.relative_to(directory): path.read_bytes()
                            for path in Path(directory).glob('ForeverRosettaStone_Data/*/*')}
            build['export_database'](create_documents(quests, names), second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(packs_before, {path.relative_to(directory): path.read_bytes()
                                           for path in Path(directory).glob('ForeverRosettaStone_Data/*/*')})
            _, api, _ = self.create_runtime(read_metadata(first))
            self.assertEqual(api.GetQuest(api, 1, b'enUS')[b'title'].decode(), text)
            self.assertIsNone(api.GetQuest(api, 1, b'frFR')[b'description'])
            self.assertTrue(api.IsAITranslated(api, b'items', 1, b'frFR'))

    def test_catalog_version_matches_the_exact_normalized_inputs(self):
        digest = hashlib.sha256(b'format8')

        for name in build['CATALOG_FILES']:
            value = load_catalog(ROOT, name)
            digest.update(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())

        _, api, _ = self.create_runtime()
        self.assertEqual(api[b'catalogVersion'].decode(), digest.hexdigest())

    def test_optional_profiling_tracks_native_stages_and_cache_without_idle_clocks(self):
        lua, api, counts = self.create_runtime()
        lua.execute(b'local clock = 0; function debugprofilestop() clock = clock + 0.01; return clock end')
        api.StartProfiling(api)
        api.GetSpellName(api, 133, b'enUS')
        api.GetSpellName(api, 133, b'enUS')
        profile = api.StopProfiling(api)
        self.assertEqual(profile[b'pageMisses'], 1)
        self.assertEqual(profile[b'pageHits'], 1)
        self.assertEqual(profile[b'decodes'], 2)  # directory and data page
        self.assertGreater(profile[b'decodedBytes'], 0)

        for field in (b'base64Ms', b'inflateMs', b'cborMs'):
            self.assertGreater(profile[field], 0)

        self.assertEqual(counts['cbor'], profile[b'decodes'] + 1)  # initial locale directory
        lua.execute(b'function debugprofilestop() error("idle clock must not run") end')
        self.assertEqual(api.GetSpellName(api, 116, b'frFR'), b'Eclair de givre')
        self.assertIsNone(api.StopProfiling(api))

    def test_rebuild_preserves_manually_patched_json_without_original_sources(self):
        quests = {
            'schemaVersion': 1, 'locales': ['enUS'],
            'catalogs': {'quests': {'123': {'locales': {'enUS': {'title': 'Manually corrected quest'}}}}},
        }
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['items']['456'] = {'locales': {'enUS': {'name': 'Manually added item'}}}

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            catalogs = root / 'catalogs'
            catalogs.mkdir()

            for name, value in create_documents(quests, names).items():
                directory = catalogs / name
                directory.mkdir(exist_ok=True)
                config = {key: content for key, content in value.items() if key != 'catalogs'}
                (directory / 'metadata.json').write_text(json.dumps({
                    'storageVersion': 2, 'kinds': sorted(value['catalogs']), 'document': config,
                }), encoding='utf-8')

                for kind, records in value['catalogs'].items():
                    (catalogs / kind).mkdir(exist_ok=True)

                    for entity_id, entity in records.items():
                        (catalogs / kind / (entity_id + '.json')).write_text(json.dumps(entity), encoding='utf-8')

            before = {path.relative_to(catalogs): path.read_bytes() for path in catalogs.rglob('*.json')}
            output = root / 'addon/runtime.toc'

            with patch('sys.argv', ['build-lua-database.py', '--root', str(root), '--output', str(output)]):
                build['main']()

            self.assertEqual({path.relative_to(catalogs): path.read_bytes() for path in catalogs.rglob('*.json')}, before)
            _, api, _ = self.create_runtime(read_metadata(output))
            self.assertEqual(api.GetQuest(api, 123, b'enUS')[b'title'], b'Manually corrected quest')
            self.assertEqual(api.GetItemName(api, 456, b'enUS'), b'Manually added item')


    def test_npc_faction_relationships_are_shared_and_reject_dangling_ids(self):
        quests = {'schemaVersion': 1, 'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}}
        names = {'catalogs': {kind: {} for kind in build['KINDS'] if kind != 'quests'}}
        names['catalogs']['npcs']['101'] = {'factionId': 201, 'locales': {
            'enUS': {'name': 'Unit'}, 'frFR': {'name': 'Unité'},
        }}
        names['catalogs']['factions']['201'] = {'locales': {
            'enUS': {'name': 'Faction'}, 'frFR': {'name': 'Faction FR'},
        }}
        documents = create_documents(quests, names)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'addon/runtime.toc'
            build['export_database'](documents, output)
            _, api, _ = self.create_runtime(read_metadata(output))
            self.assertEqual(api.GetNpcFactionID(api, 101), 201)
            self.assertEqual(api.GetFactionName(api, 201, b'frFR'), b'Faction FR')
            self.assertIsNone(api.GetNpcFactionID(api, 999))
            for invalid in (0, -1, True, '201', 999):
                documents['npcs']['catalogs']['npcs']['101']['factionId'] = invalid
                with self.subTest(invalid=invalid), self.assertRaisesRegex(ValueError, 'invalid or missing faction'):
                    build['export_database'](documents, output)


if __name__ == '__main__':
    unittest.main()
