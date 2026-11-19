"""Exercise translation queue grouping, provenance, and refusal of unsafe results."""

import copy
import json
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
work = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))
from tools.build.runtime_catalog import get_has_ai_translation, get_tooltip_source_text, project_tooltip_details, project_tooltip_rules


class TranslationWorkTests(unittest.TestCase):
    def test_dialogue_selectors_can_contain_complete_sentences(self):
        token = work['get_quest_tokens']
        source = '$gWelcome, sir. Need help?:Hello! Need help?; $N'
        translated = '$gBonjour, monsieur. Besoin d’aide ?:Bonjour ! Besoin d’aide ?; $N'
        self.assertEqual(token(source, allow_sentence_selectors=True),
                         token(translated, allow_sentence_selectors=True))
        with self.assertRaisesRegex(ValueError, 'Malformed quest gender selector'):
            token(source)

    def test_quest_gender_controls_do_not_hide_technical_tokens(self):
        token = work['get_quest_tokens']
        self.assertEqual(token('Hello {name}'), token('Bonjour $gami:amie; {name}'))
        self.assertEqual(token('$gReady:Ready; {name}'), token('Prêt {name}'))
        for invalid in ('Bonjour $gami:amie;', 'Bonjour $gami$s1:amie; {name}',
                        'Bonjour $gami:amie {name}', 'Bonjour $g:{name}; {name}'):
            with self.subTest(invalid=invalid):
                with self.assertRaises(ValueError):
                    if token(invalid) != token('Hello {name}'):
                        raise ValueError('mismatch')
        self.assertNotEqual(token('Value ${$s1+${$s2}}'), token('Value ${$s1+${$s3}}'))
        self.assertNotEqual(token('Value $s1'), token('Value $s2'))
        self.assertNotEqual(token('$g<foo>:<bar>;'), token('word'))
        self.assertEqual(token('$g{name}:{name};'), token('$g{name}:{name};'))
        self.assertNotEqual(token('$g{name}:{name};'), token('$g{name}:ami;'))

    def test_quest_queue_validates_literal_gender_without_weakening_item_tokens(self):
        docs = {'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {
            '2': {'locales': {'enUS': {'summary': 'Hello {name}'}}}}}}}
        queue = work['collect_translation_candidates'](docs)
        job = queue['jobs'][0]
        result = {'jobId': job['jobId'], 'sourceHash': job['sourceHash'], 'translation': 'Bonjour $gami:amie; {name}'}
        work['validate_results'](queue, [result], docs)
        result['translation'] = 'Bonjour $gami:amie;'
        with self.assertRaisesRegex(ValueError, 'Placeholder mismatch'):
            work['validate_results'](queue, [result], docs)
        self.assertNotEqual(work['get_tokens']('Hello {name}'), work['get_tokens']('Bonjour $gami:amie; {name}'))

    def test_tooltip_exports_include_rendering_data_without_maintenance_metadata(self):
        entity = {'locales': {'enUS': {'name': 'Spell', 'description': 'Deals $s1 damage.'},
                              'frFR': {'setName': 'Ensemble'}},
                  'tooltipData': {
                      'effects': [{'index': 0, 'basePoints': 7}], 'classID': 2,
                      'sourceDescriptions': {'frFR': 'Inflige $s1 dégâts.'},
                      'sourceBuild': '1.60.1.70888', 'sourceLocale': 'enUS',
                      'effectSourceMetadata': {'source': 'wowClient', 'sourceFileSha256': 'hash'},
                      'sourceAuraDescriptionMetadata': {'frFR': {'origin': 'original'}},
                      'futureMaintenanceField': {'attribution': 'Source author'},
                      'set': {'name': 'Set',
                              'bonuses': [{'spellID': 1, 'threshold': 2}], 'sourceBuild': 'old-build'},
                  }}
        original = copy.deepcopy(entity)
        details = project_tooltip_details(entity, entity['locales']['enUS'], 'enUS')
        rules = project_tooltip_rules(entity)
        self.assertEqual(set(rules), {'effects', 'classID', 'set'})
        self.assertEqual(set(details), {'effects', 'classID', 'description', 'set'})
        self.assertEqual(rules['set'], {'bonuses': [{'spellID': 1, 'threshold': 2}]})
        self.assertNotIn('sourceNames', details['set'])
        self.assertEqual(project_tooltip_details(entity, entity['locales']['frFR'], 'frFR')['set']['name'], 'Ensemble')
        self.assertNotIn('sourceBuild', details['set'])
        self.assertEqual(entity, original)

    def test_numeric_and_named_client_placeholders_are_protected_whole(self):
        self.assertEqual(work['get_tokens']('$1 $$444681s2 $10/;s1 $rad#'),
                         ['$$444681s2', '$1', '$10/;s1', '$rad#'])

    def setUp(self):
        metadata = {'fields': {'name': {'origin': 'community', 'source': 'fixture'}}}
        self.documents = {
            'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {
                '1': {'usageStatus': 'unused', 'locales': {'enUS': {'title': 'Excluded'}}},
            }}},
            'items': {'catalogs': {'items': {
                '1': {'locales': {'enUS': {'name': 'Sword $s1'}, 'frFR': {'name': 'Épée $s1',
                                                                           'translationMetadata': metadata}}},
                '2': {'locales': {'enUS': {'name': 'Sword $s1'}}},
                '3': {'locales': {'enUS': {'name': 'Sword $s1'}}},
                '4': {'locales': {'frFR': {'name': 'Sans source'}}},
            }}},
        }
        self.queue = work['collect_translation_candidates'](self.documents)
        self.job = self.queue['jobs'][0]
        self.results = [{'jobId': self.job['jobId'], 'sourceHash': self.job['sourceHash'],
                         'translation': 'Épée $s1'}]

    def test_deduplicates_and_retains_reuse_provenance(self):
        self.assertEqual(len(self.queue['jobs']), 1)
        self.assertEqual(len(self.job['pointers']), 2)
        self.assertEqual(self.job['reuse']['metadata']['origin'], 'community')
        self.assertEqual(self.queue['missingSource'][0]['id'], '4')
        work['validate_results'](self.queue, self.results, self.documents)

    def test_all_catalog_queue_includes_runtime_excluded_quest_files(self):
        original = copy.deepcopy(self.documents)
        default = work['collect_translation_candidates'](self.documents)
        complete = work['collect_translation_candidates'](self.documents, include_excluded_quests=True)
        self.assertFalse(any(job['context'].startswith('quests.') for job in default['jobs']))
        quest = next(job for job in complete['jobs'] if job['context'] == 'quests.title')
        self.assertEqual(quest['source'], 'Excluded')
        self.assertEqual(quest['pointers'], [{'catalog': 'quests', 'kind': 'quests',
                                            'id': '1', 'field': 'title'}])
        self.assertEqual(self.documents, original)

    def test_quest_technical_markers_do_not_exempt_surrounding_prose(self):
        for text in ('<UNUSED>', '<nyi>', '<NYI> <TXT>', 'x', 'zzOLD UNUSED', 'UNUSED', 'REUSE', 'reuse', 'DNT'):
            self.assertEqual(work['get_invariant_reason']({'context': 'quests.title', 'source': text}),
                             'structuralSentinel')

        for text in ('<NYI> <TXT> Report to the captain.', 'x marks the spot',
                     'zzOLD UNUSED Return to the tower', '<The captain nods.>'):
            self.assertIsNone(work['get_invariant_reason']({'context': 'quests.title', 'source': text}))

        self.assertIsNone(work['get_invariant_reason']({'context': 'items.name', 'source': '<UNUSED>'}))

    def test_shared_test_lexeme_does_not_exempt_test_instructions(self):
        for locale in ('csCZ', 'plPL', 'trTR'):
            self.assertEqual(work['get_invariant_reason']({'context': 'spells.tooltip.description',
                                                          'source': 'Test', 'locale': locale}),
                             'reviewedSharedLocaleWording')
            self.assertIsNone(work['get_invariant_reason']({'context': 'spells.tooltip.description',
                                                           'source': 'Test your strength.', 'locale': locale}))

        for locale in ('esES', 'esMX'):
            self.assertEqual(work['get_invariant_reason']({'context': 'quests.summary',
                                                          'source': 'Derrotado.', 'locale': locale}),
                             'reviewedSharedLocaleWording')
            self.assertIsNone(work['get_invariant_reason']({'context': 'quests.summary',
                                                           'source': 'Derrotado. Volte ao capitão.', 'locale': locale}))

    def test_all_catalog_foreign_queue_includes_excluded_quest_sources(self):
        documents = copy.deepcopy(self.documents)
        documents['quests']['catalogs']['quests']['1']['locales'] = {'frFR': {'title': 'Titre conservé'}}
        default = work['create_foreign_queue'](documents)
        complete = work['create_foreign_queue'](documents, include_excluded_quests=True)
        self.assertFalse(any(job['context'].startswith('quests.') for job in default['jobs']))
        self.assertEqual(complete['jobs'], [])
        self.assertTrue(any(pointer['kind'] == 'quests' and pointer['field'] == 'title'
                            for pointer in complete['excludedWithoutEnglish']))

    def test_race_inventory_includes_owned_female_names(self):
        entity = {'locales': {'enUS': {'name': 'Human', 'nameFemale': 'Human'}}}
        self.assertEqual(list(work['iter_fields']('races', entity)),
                         [('name', 'Human', None), ('nameFemale', 'Human', None)])

    def test_book_pages_inventory_the_body_without_requiring_an_invented_name(self):
        documents = {
            'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}},
            'bookpages': {'catalogs': {'bookpages': {
                '1': {'locales': {'enUS': {'description': 'A page body.'}, 'frFR': {}}},
            }}},
        }
        queue = work['collect_translation_candidates'](documents)
        self.assertEqual(queue['missingSource'], [])
        self.assertEqual([job['context'] for job in queue['jobs']], ['bookpages.description'])
        page = documents['bookpages']['catalogs']['bookpages']['1']
        page['locales'] = {'enUS': {}, 'frFR': {'description': 'Un texte de page.'}}
        queue = work['collect_translation_candidates'](documents)
        self.assertEqual([row['field'] for row in queue['missingSource']], ['description'])
        self.assertFalse(queue['jobs'])

    def test_aura_details_keep_native_target_and_provenance_separate(self):
        native_metadata = {'origin': 'original', 'source': 'wago', 'sourceLocale': 'frFR'}
        entity = {'locales': {
            'enUS': {'auraDescription': 'Deals $s1 damage.', 'translationMetadata': {'fields': {
                'auraDescription': {'origin': 'original'}}}},
            'frFR': {'auraDescription': 'Inflige $s1 dégâts.', 'translationMetadata': {'fields': {
                'auraDescription': {'origin': 'ai'}}}},
        }, 'tooltipData': {'sourceAuraDescriptions': {'frFR': 'Subit $s1 dégâts.'},
                           'sourceAuraDescriptionMetadata': {'frFR': native_metadata}}}
        self.assertEqual(project_tooltip_details(entity, entity['locales']['frFR'], 'frFR')['auraDescription'],
                         'Inflige $s1 dégâts.')
        self.assertIsNone(get_tooltip_source_text(entity, 'frFR', 'auraDescription'))
        self.assertTrue(get_has_ai_translation('spells', '1', 'frFR', entity['locales']['frFR']))
        self.assertNotIn('sourceAuraDescriptions', project_tooltip_rules(entity))
        self.assertNotIn('sourceAuraDescriptionMetadata', project_tooltip_rules(entity))
        self.assertEqual(work['get_metadata'](entity, 'frFR', 'tooltip.auraDescription', None)['origin'], 'ai')
        del entity['locales']['frFR']['auraDescription']
        entity['locales']['frFR']['auraDescription'] = 'Subit $s1 dégâts.'
        entity['locales']['frFR']['translationMetadata']['fields']['auraDescription'] = native_metadata
        self.assertEqual(work['get_metadata'](entity, 'frFR', 'tooltip.auraDescription', None), native_metadata)
        self.assertEqual(work['get_target'](entity, 'enUS', 'tooltip.auraDescription', None), 'Deals $s1 damage.')
        self.assertIsNone(work['get_target'](entity, 'enGB', 'tooltip.auraDescription', None))
        self.assertIn(('tooltip.auraDescription', 'Deals $s1 damage.', None), list(work['iter_fields']('spells', entity)))

    def test_tooltip_reuse_preserves_field_context_and_tokens(self):
        cast_metadata = {'origin': 'original', 'source': 'wowClient', 'sourceLocale': 'frFR'}
        aura_metadata = {'origin': 'community', 'source': 'fixture', 'sourceLocale': 'enUS'}
        documents = {'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}},
                     'spells': {'catalogs': {'spells': {
                         '1': {'locales': {
                             'enUS': {'description': 'Deals $s1 damage.'},
                             'frFR': {'description': 'Inflige $s1 dégâts.', 'translationMetadata': {'fields': {
                                 'description': cast_metadata}}},
                         }},
                         '2': {'locales': {'enUS': {'auraDescription': 'Deals $s1 damage.'}, 'frFR': {}}},
                         '3': {'locales': {'enUS': {'description': 'Deals $s1 damage.'}, 'frFR': {}}},
                     }}}}
        queue = work['collect_translation_candidates'](documents)
        aura = next(job for job in queue['jobs'] if job['context'] == 'spells.tooltip.auraDescription')
        cast = next(job for job in queue['jobs'] if job['context'] == 'spells.tooltip.description')
        self.assertEqual(cast['reuse'], {'text': 'Inflige $s1 dégâts.', 'metadata': cast_metadata})
        self.assertNotIn('reuse', aura)

        documents['spells']['catalogs']['spells']['4'] = {'locales': {
            'enUS': {'auraDescription': 'Deals $s1 damage.'},
            'frFR': {'auraDescription': 'Subit $s1 dégâts.', 'translationMetadata': {'fields': {
                'auraDescription': aura_metadata}}},
        }}
        aura = next(job for job in work['collect_translation_candidates'](documents)['jobs']
                    if job['context'] == 'spells.tooltip.auraDescription')
        self.assertEqual(aura['reuse'], {'text': 'Subit $s1 dégâts.', 'metadata': aura_metadata})
        documents['spells']['catalogs']['spells']['4']['locales']['frFR']['auraDescription'] = 'Subit $s2 dégâts.'
        aura = next(job for job in work['collect_translation_candidates'](documents)['jobs']
                    if job['context'] == 'spells.tooltip.auraDescription')
        self.assertNotIn('reuse', aura)

    def test_rejects_missing_extra_duplicate_and_corrupt_results(self):
        invalid = [[], self.results * 2, [{**self.results[0], 'jobId': 'extra'}],
                   [{**self.results[0], 'sourceHash': 'wrong'}],
                   [{**self.results[0], 'translation': 'Épée $s2'}]]

        for results in invalid:
            with self.subTest(results=results), self.assertRaises(ValueError):
                work['validate_results'](self.queue, results, self.documents)

    def test_rejects_changed_source_or_existing_target(self):
        for changed in ('source', 'target'):
            documents = copy.deepcopy(self.documents)
            localized = documents['items']['catalogs']['items']['2']['locales']

            if changed == 'source':
                localized['enUS']['name'] = 'Changed $s1'
            else:
                localized['frFR'] = {'name': 'Existant $s1'}

            with self.subTest(changed=changed), self.assertRaises(ValueError):
                work['validate_results'](self.queue, self.results, documents)

    def test_tooltip_source_rejects_italian_english_fallback_and_retains_corrected_text(self):
        entity = {'locales': {'enUS': {'name': 'Example', 'description': 'Damage $s1'},
                              'itIT': {'name': 'Esempio', 'description': 'Danni $s1'}},
                  'tooltipData': {'rank': 'Rank 2', 'sourceRanks': {'itIT': 'Rank 2'},
                                  'sourceDescriptions': {'itIT': 'Danni $s1'}}}
        self.assertEqual(work['get_target'](entity, 'itIT', 'tooltip.description', None), 'Danni $s1')
        self.assertIsNone(work['get_target'](entity, 'itIT', 'tooltip.rank', None))
        entity['locales']['itIT']['rank'] = 'Grado 2'
        self.assertEqual(work['get_target'](entity, 'itIT', 'tooltip.rank', None), 'Grado 2')

    def test_tokens_preserve_printf_game_and_named_placeholders(self):
        tokens = work['get_tokens']('Deal %1$d $s1 ${$s2*2} {current} |cffffffffdamage|r')
        self.assertEqual(tokens, sorted(['%1$d', '$s1', '${$s2*2}', '{current}', '|cffffffff', '|r']))
        self.assertEqual(work['get_tokens']('Collect $1oa grapes and $2oa leaves.'), ['$1oa', '$2oa'])

    def test_tokens_protect_reference_ids_and_nested_expression_precision(self):
        source = '$@spelldesc<123> ${$s1+${$s2*2}}.2 $@spellname456'
        self.assertEqual(work['get_tokens'](source),
                         sorted(['$@spelldesc<123>', '${$s1+${$s2*2}}.2', '$@spellname456']))
        for changed in (source.replace('<123>', '<124>'), source.replace('}.2', '}.3'),
                        source.replace('$s2*2', '$s3*2')):
            self.assertNotEqual(work['get_tokens'](source), work['get_tokens'](changed))

    def test_literal_percentages_are_not_printf_arguments(self):
        self.assertEqual(work['get_tokens']('+1% Critical and 100% increased'), ['%', '%'])
        self.assertEqual(work['get_tokens']('%1$d charges; %s sec; 100%%'), sorted(['%1$d', '%s', '%%']))

    def test_game_markup_protects_values_without_freezing_plural_words(self):
        source = '$/10;s2 $lpoint:points; |cnEPIC_PURPLE_COLOR:word|r |TInterface\\icon:16|t <name>'
        target = '$/10;s2 $lbod:bodů; |cnEPIC_PURPLE_COLOR:slovo|r |TInterface\\icon:16|t <name>'
        self.assertEqual(work['get_tokens'](source), work['get_tokens'](target))
        self.assertIn('$/10;s2', work['get_tokens'](source))
        self.assertIn('|cnEPIC_PURPLE_COLOR:', work['get_tokens'](source))
        self.assertNotEqual(work['get_tokens'](source), work['get_tokens'](target.replace('icon:16', 'icon:32')))

    def test_chained_else_if_conditions_are_structural_and_protected(self):
        source = '$?s11286[$@spelldesc11286]?s11285[$@spelldesc11285][$@spelldesc1776]'
        self.assertIn('?s11285', work['get_tokens'](source))
        for field in ('description', 'auraDescription'):
            context = 'spells.tooltip.' + field
            self.assertEqual(work['get_invariant_reason']({'context': context, 'source': source}), 'structuralTemplate')
            self.assertIsNone(work['get_invariant_reason']({'context': context, 'source': 'Active for $d.'}))
        self.assertNotEqual(work['get_tokens'](source), work['get_tokens'](source.replace('?s11285[', '?s999[')))

    def test_invariant_reuse_is_explicit_and_does_not_swallow_prose(self):
        self.assertEqual(work['get_invariant_reason']({'context': 'spells.name', 'source': 'MHTest01'}),
                         'technicalIdentifier')
        self.assertEqual(work['get_invariant_reason']({'context': 'spells.tooltip.description',
                                                      'source': '$@spelldesc123'}), 'structuralTemplate')
        self.assertIsNone(work['get_invariant_reason']({'context': 'spells.tooltip.description',
                                                       'source': 'Deals $s1 damage.'}))
        self.assertIsNone(work['get_invariant_reason']({'context': 'spells.name', 'source': 'Fireball'}))
        self.assertEqual(work['get_invariant_reason']({'context': 'items.tooltip.description', 'source': 'K.D.'}),
                         'characterInitials')
        self.assertEqual(work['get_invariant_reason']({'context': 'items.tooltip.description', 'source': '-Feralas',
                                                      'locale': 'daDK'}), 'maintainedPlaceNameMatchesSource')
        self.assertIsNone(work['get_invariant_reason']({'context': 'items.tooltip.description', 'source': '-Feralas',
                                                       'locale': 'frFR'}))

    def test_compact_results_expand_without_repeating_source_hashes(self):
        batch, results = work['expand_translations'](self.queue, [{'source': 'Sword $s1', 'frFR': 'Épée $s1'}],
                                                    'items.name')
        self.assertEqual(results, self.results)
        self.assertEqual(batch['jobs'], self.queue['jobs'])

        with self.assertRaises(ValueError):
            work['expand_translations'](self.queue, [{'source': 'Sword $s1', 'frFR': 'Épée $s2'}], 'items.name')

    def test_patch_preserves_unmodified_text_and_adds_provenance(self):
        raw = json.dumps(self.documents['items'], ensure_ascii=False, indent=2) + '\n'
        metadata = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        updates = {('items', '2', 'frFR'): [('name', None, 'Épée $s1', metadata)],
                   ('items', '3', 'frFR'): [('name', None, 'Épée $s1', metadata)]}
        edited = work['create_catalog_patch'](raw, self.documents['items'], updates)
        value = json.loads(edited)
        self.assertEqual(value['catalogs']['items']['2']['locales']['frFR']['name'], 'Épée $s1')
        self.assertEqual(value['catalogs']['items']['3']['locales']['frFR']['translationMetadata']['fields']['name'],
                         metadata)
        original = copy.deepcopy(self.documents['items'])

        for entity_id in ('2', '3'):
            del value['catalogs']['items'][entity_id]['locales']['frFR']

        self.assertEqual(value, original)

    def test_patch_touches_only_selected_entity_files(self):
        from tools.catalogs.catalog_storage import load_catalog

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            directory = root / 'catalogs/items'
            directory.mkdir(parents=True)
            document = self.documents['items']
            config = {key: value for key, value in document.items() if key != 'catalogs'}
            (directory / 'metadata.json').write_text(json.dumps({
                'storageVersion': 2, 'kinds': ['items'], 'document': config,
            }), encoding='utf-8')

            for entity_id, entity in document['catalogs']['items'].items():
                (directory / (entity_id + '.json')).write_text(json.dumps(entity), encoding='utf-8')
            manifest = (root / 'catalogs/items/metadata.json').read_bytes()
            documents = {'items': load_catalog(root, 'items', ids={'items': ['2', '3']})}
            patch = work['create_patch'](self.queue, self.results, documents, root)
            self.assertIn('*** Update File: ' + str(root / 'catalogs/items/2.json'), patch)
            self.assertIn('*** Update File: ' + str(root / 'catalogs/items/3.json'), patch)
            self.assertNotIn(str(root / 'catalogs/items/1.json'), patch)
            self.assertNotIn('metadata.json', patch)
            self.assertIn('Épée $s1', patch)
            self.assertEqual((root / 'catalogs/items/metadata.json').read_bytes(), manifest)
            self.assertEqual(load_catalog(root, 'items'), self.documents['items'])

            path = root / 'catalogs/items/2.json'
            changed = json.loads(path.read_bytes())
            changed['locales']['enUS']['name'] = 'Changed sword $s1'
            path.write_text(json.dumps(changed), encoding='utf-8')

            with self.assertRaisesRegex(ValueError, 'Catalog changed during patch generation'):
                work['create_patch'](self.queue, self.results, documents, root)

    def test_patch_adds_fields_to_existing_locale_and_objective_array(self):
        metadata = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        document = {'catalogs': {'quests': {'2': {'locales': {
            'enUS': {'title': 'Quest', 'objectiveLines': [{'index': 2, 'type': 'item', 'text': 'Pelts {current}'}]},
            'frFR': {'title': 'Quête', 'objectiveLines': [{'index': 1, 'type': 'item', 'text': 'Autre'}],
                     'translationMetadata': {'fields': {'title': {'origin': 'original'}}}},
        }}}}}
        raw = json.dumps(document, ensure_ascii=False, indent=2) + '\n'
        updates = {('quests', '2', 'frFR'): [('summary', None, 'Résumé', metadata),
                                             ('objectiveLines', 2, 'Peaux {current}', metadata)]}
        value = json.loads(work['create_catalog_patch'](raw, document, updates))
        localized = value['catalogs']['quests']['2']['locales']['frFR']
        self.assertEqual(localized['summary'], 'Résumé')
        self.assertEqual(localized['objectiveLines'][1]['text'], 'Peaux {current}')
        self.assertEqual(localized['translationMetadata']['fields']['objectiveLines.2'], metadata)
        self.assertEqual(localized['translationMetadata']['fields']['title']['origin'], 'original')

    def test_unsupported_english_locale_does_not_create_a_second_translation_job(self):
        documents = copy.deepcopy(self.documents)
        documents['quests']['locales'].append('enGB')
        entity = documents['items']['catalogs']['items']['2']
        entity['locales']['enUS']['translationMetadata'] = {'fields': {
            'name': {'origin': 'community', 'source': 'fixture'},
        }}
        queue = work['collect_translation_candidates'](documents)
        self.assertFalse(any(job['locale'] == 'enGB' for job in queue['jobs']))

    def test_patches_cannot_recreate_a_second_english_locale(self):
        updates = {('items', '2', 'enGB'): [('name', None, 'Text', {'origin': 'original'})]}
        for writer in ('create_catalog_patch', 'create_small_catalog_patch'):
            with self.assertRaisesRegex(ValueError, 'write English fields under enUS'):
                work[writer]('{}', {}, updates)

    def test_patch_refuses_existing_empty_field(self):
        document = copy.deepcopy(self.documents['items'])
        document['catalogs']['items']['2']['locales']['frFR'] = {'name': ''}
        raw = json.dumps(document)
        updates = {('items', '2', 'frFR'): [('name', None, 'Épée', {'origin': 'ai'})]}

        with self.assertRaisesRegex(ValueError, 'Existing localized field'):
            work['create_catalog_patch'](raw, document, updates)

    def test_owned_english_correction_is_guarded_without_creating_source_maps(self):
        old_metadata = {'origin': 'original', 'source': 'fixture', 'sourceLocale': 'frFR'}
        metadata = {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        documents = copy.deepcopy(self.documents)
        entity = {'locales': {'enUS': {'title': 'Welcome'}, 'frFR': {
            'title': 'Welcome', 'translationMetadata': {'fields': {'title': old_metadata}},
        }}}
        documents['quests']['catalogs']['quests'] = {'2': entity}
        source = 'Welcome'
        job = {'jobId': work['get_digest'](json.dumps(['frFR', 'quests.title', source], separators=(',', ':'))),
               'locale': 'frFR', 'context': 'quests.title', 'source': source,
               'sourceHash': work['get_digest'](source), 'tokens': [], 'pointers': [{
                   'catalog': 'quests', 'kind': 'quests', 'id': '2', 'field': 'title',
                   'ownedEnglishFallback': True, 'existingMetadata': old_metadata,
               }]}
        queue = {'jobs': [job]}
        results = [{'jobId': job['jobId'], 'sourceHash': job['sourceHash'], 'translation': 'Bienvenue'}]
        work['validate_results'](queue, results, documents)

        for changed in ('metadata', 'text', 'unchanged_output'):
            altered = copy.deepcopy(documents)
            invalid_results = copy.deepcopy(results)

            if changed == 'metadata':
                altered['quests']['catalogs']['quests']['2']['locales']['frFR']['translationMetadata']['fields']['title'] = metadata
            elif changed == 'text':
                altered['quests']['catalogs']['quests']['2']['locales']['frFR']['title'] = 'Manual correction'
            else:
                invalid_results[0]['translation'] = source

            with self.subTest(changed=changed), self.assertRaises(ValueError):
                work['validate_results'](queue, invalid_results, altered)

        for existing_sources in (False, True):
            document = copy.deepcopy(documents['quests'])

            if existing_sources:
                document['catalogs']['quests']['2']['tooltipData'] = {'sourceDescriptions': {'frFR': 'Texte natif'}}

            raw = json.dumps(document, ensure_ascii=False, indent=2) + '\n'
            updates = {('quests', '2', 'frFR'): [('title', None, 'Bienvenue', metadata, source)]}
            value = json.loads(work['create_catalog_patch'](raw, document, updates))['catalogs']['quests']['2']
            self.assertEqual(value['locales']['enUS']['title'], source)
            self.assertEqual(value['locales']['frFR']['title'], 'Bienvenue')
            self.assertEqual(value['locales']['frFR']['translationMetadata']['fields']['title'], metadata)
            self.assertNotIn('sourceTitles', value.get('tooltipData', {}))
            self.assertNotIn('sourceTitleMetadata', value.get('tooltipData', {}))

            if existing_sources:
                self.assertEqual(value['tooltipData']['sourceDescriptions']['frFR'], 'Texte natif')

    def test_value_frames_preserve_literal_meaning_and_repeated_bindings(self):
        first = work['get_value_frame']('Deals ${$s1*2} damage, then $s2; ${$s1*2} again.',
                                        'Puis $s2 ; inflige ${$s1*2} dégâts, encore ${$s1*2}.')
        second = work['get_value_frame']('Deals ${$s3*3} damage, then $s4; ${$s3*3} again.')
        self.assertEqual(first[0], second[0])
        self.assertNotEqual(first[0], work['get_value_frame'](
            'Deals ${$s3*3} damage, then $s4; ${$s5*3} again.')[0])
        self.assertNotEqual(work['get_value_frame']('Deals $s1 damage for 10 sec.')[0],
                            work['get_value_frame']('Deals $s2 damage for 20 sec.')[0])
        self.assertNotEqual(work['get_value_frame']('$@spellname123 deals $s1 damage.')[0],
                            work['get_value_frame']('$@spellname456 deals $s2 damage.')[0])
        self.assertNotEqual(work['get_value_frame']('$?s1[Deals $s1 damage.]')[0],
                            work['get_value_frame']('$?s2[Deals $s1 damage.]')[0])
        with self.assertRaises(ValueError):
            work['get_value_frame']('Deals $s1 damage.', 'Inflige $s2 dégâts.')

    def test_value_reuse_rejects_conflicts_and_maps_only_missing_numeric_tokens(self):
        documents = {'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}},
                     'spells': {'catalogs': {'spells': {
                         str(index): {'locales': {'enUS': {'description': f'Deals $s{index} damage.'}}}
                         for index in (1, 2, 3)
                     }}}}
        queue = work['collect_translation_candidates'](documents)
        by_source = {job['source']: job for job in queue['jobs']}
        first, second = by_source['Deals $s1 damage.'], by_source['Deals $s2 damage.']
        submitted = {first['jobId']: {'jobId': first['jobId'], 'sourceHash': first['sourceHash'],
                                      'translation': 'Inflige $s1 dégâts.'}}
        batch, results = work['create_value_reuse'](queue, submitted, documents)
        self.assertEqual(len(batch['jobs']), 2)
        self.assertEqual({result['translation'] for result in results},
                         {'Inflige $s2 dégâts.', 'Inflige $s3 dégâts.'})
        submitted[second['jobId']] = {'jobId': second['jobId'], 'sourceHash': second['sourceHash'],
                                      'translation': 'Inflige $s2 points de dégâts.'}
        batch, results = work['create_value_reuse'](queue, submitted, documents)
        self.assertEqual(batch['jobs'], [])
        self.assertEqual(results, [])

    def test_record_outputs_are_discovered_for_reuse_and_conflicts_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'spell-record-1234567-text.json'
            output.write_text(json.dumps(self.results), encoding='utf-8')
            numeric = Path(directory) / 'numeric-reuse-0003-results.json'
            numeric.write_text(json.dumps([{**self.results[0], 'translation': 'Autre $s1'}]), encoding='utf-8')
            submissions, inputs = work['read_submitted_results'](self.queue, Path(directory))
            self.assertEqual(submissions[self.job['jobId']]['translation'], 'Épée $s1')
            self.assertEqual(len(inputs), 2)
            duplicate = Path(directory) / 'spell-main-0001-text.json'
            duplicate.write_text(json.dumps([{**self.results[0], 'translation': 'Lame $s1'}]), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Conflicting submitted translations'):
                work['read_submitted_results'](self.queue, Path(directory))

    def test_reference_frames_preserve_words_numbers_markup_and_repeated_bindings(self):
        first = work['get_reference_frame']('Deals $s1 damage, then $s2 damage; $s1 again.',
                                            'Inflige $s2 dégâts, puis $s1 ; encore $s1.')
        second = work['get_reference_frame']('Deals $123s3 damage, then $s4 damage; $123s3 again.')
        self.assertEqual(first[0], second[0])
        self.assertEqual(first[1], ('$s1', '$s2'))
        self.assertNotEqual(first[0], work['get_reference_frame'](
            'Deals $s1 damage, then $s2 damage; $s2 again.')[0])
        self.assertNotEqual(work['get_reference_frame']('Deals $s1 damage for 10 sec.')[0],
                            work['get_reference_frame']('Deals $s2 damage for 20 sec.')[0])
        self.assertNotEqual(work['get_reference_frame']('$@spellname123 deals $s1 damage.')[0],
                            work['get_reference_frame']('$@spellname456 deals $s2 damage.')[0])
        self.assertIsNone(work['get_reference_frame']('Plain text $d'))

    def test_foreign_sources_do_not_create_english_or_target_translation_jobs(self):
        documents = copy.deepcopy(self.documents)
        documents['items']['catalogs']['items'] = {
            '1': {'locales': {'enUS': {'name': 'Sword'}, 'frFR': {'description': 'Inflige $s1 dégâts.'}}},
        }
        queue = work['create_foreign_queue'](documents)
        self.assertEqual(queue['jobs'], [])
        self.assertTrue(any(pointer['field'] == 'tooltip.description'
                            for pointer in queue['excludedWithoutEnglish']))

    def test_stale_source_maps_cannot_create_translation_jobs(self):
        documents = copy.deepcopy(self.documents)
        documents['npcs'] = {'catalogs': {'npcs': {}}}
        documents['areas'] = {'catalogs': {'areas': {}}}
        documents['spells'] = {'catalogs': {'spells': {}}}
        entity = {'locales': {'enUS': {'name': 'Test', 'description': 'Damage $s1'}, 'frFR': {'name': 'Test'}},
                  'tooltipData': {'sourceDescriptions': {'frFR': 'Damage $s1'}}}
        documents['items']['catalogs']['items'] = {'1': entity}
        queue = work['create_fallback_queue'](documents)
        self.assertEqual(queue['jobs'], [])
        missing = work['collect_translation_candidates'](documents)
        job = next(job for job in missing['jobs'] if job['context'] == 'items.tooltip.description')
        self.assertEqual(job['source'], 'Damage $s1')
        self.assertFalse(job['pointers'][0].get('nativeFallback'))
        self.assertIsNone(work['get_target'](entity, 'frFR', 'tooltip.description', None))

    def test_reference_reuse_requires_unanimous_same_locale_whole_sentence(self):
        documents = copy.deepcopy(self.documents)
        records = documents['items']['catalogs']['items']
        records.clear()

        for index, source in enumerate(('Deals $s1 damage.', 'Deals $s2 damage.', 'Deals $s3 damage.'), 1):
            records[str(index)] = {'locales': {'enUS': {'description': source}}}

        queue = work['collect_translation_candidates'](documents)
        jobs = {job['source']: job for job in queue['jobs']}
        first = jobs['Deals $s1 damage.']
        submissions = {first['jobId']: {'jobId': first['jobId'], 'sourceHash': first['sourceHash'],
                                        'translation': 'Inflige $s1 dégâts.'}}
        batch, results = work['create_reference_reuse'](queue, submissions, documents)
        self.assertEqual(len(batch['jobs']), 2)
        self.assertEqual({result['translation'] for result in results},
                         {'Inflige $s2 dégâts.', 'Inflige $s3 dégâts.'})
        second = jobs['Deals $s2 damage.']
        submissions[second['jobId']] = {'jobId': second['jobId'], 'sourceHash': second['sourceHash'],
                                        'translation': 'Cause $s2 dégâts.'}
        batch, results = work['create_reference_reuse'](queue, submissions, documents)
        self.assertEqual(results, [])


if __name__ == '__main__':
    unittest.main()
