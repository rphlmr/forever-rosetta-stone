"""Exercise deterministic source priority, AI eligibility and incremental resync."""

import copy
import hashlib
import json
import runpy
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from datasources.corpus.translation_corpus import SCHEMA
from tools.catalogs.import_policy import (OfficialEvidence, ai_block_reason, filter_queue,
                                         english_source, validate_batch_policy, validate_queue_policy)

RESYNC = runpy.run_path(str(ROOT / 'tools/catalogs/resync.py'))
FILL = RESYNC['FILL']


def record(text, origin='original', locale='enUS'):
    return {'description': text, 'translationMetadata': {'fields': {'description': {
        'origin': origin, 'source': 'fixture', 'sourceLocale': locale}}}}


class ImportPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.raw = self.root / 'snapshot.txt'
        self.raw.write_text('Pinned game snapshot')
        self.database = self.root / 'corpus.sqlite'
        self.db = sqlite3.connect(self.database)
        self.db.executescript(SCHEMA)
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('schemaVersion', '1'))
        self.db.execute('INSERT INTO inputs VALUES(?,?)', ('snapshot.txt', hashlib.sha256(self.raw.read_bytes()).hexdigest()))
        self.db.commit()
        self.addCleanup(self.db.close)

    def add(self, text='Inflige $s1 dégâts.', english='Deals $s1 damage.', locale='frFR',
            kind='spells', entity_id='1', field='description', origin='original',
            source='wago', evidence='sourceSnapshot', flags=(), provenance=None):
        provenance = {'source': source, 'sourceLocale': locale, 'sourceBuild': '1.60.1.70938',
                      **(provenance or {})}
        self.db.execute('INSERT INTO records VALUES(NULL,?,?,?,?,?,?,?,?,?,?,?)',
                        (kind, entity_id, locale, field, text, english, origin, evidence,
                         json.dumps(provenance), 'snapshot.txt', json.dumps(list(flags))))
        self.db.commit()

    def evidence(self):
        return OfficialEvidence(self.database, self.root)

    def queue(self, locale='itIT', entity_id='1', field='description'):
        return {'jobs': [{'jobId': 'job', 'locale': locale, 'context': 'spells.' + field,
            'source': 'Deals $s1 damage.', 'sourceHash': 'hash', 'pointers': [
                {'kind': 'spells', 'id': entity_id, 'field': field}]}]}

    def test_one_verified_official_translation_allows_additional_language(self):
        self.add()
        evidence = self.evidence()
        self.assertIsNone(ai_block_reason('itIT', 'spells', '1', 'description', 'Deals $s1 damage.', evidence))
        self.assertEqual(len(filter_queue(self.queue(), evidence)['jobs']), 1)

    def test_public_queue_api_uses_policy_and_keeps_blocked_gaps_visible(self):
        self.add()
        documents = {'quests': {'locales': ['enUS', 'frFR', 'itIT'], 'catalogs': {'quests': {}}},
                     'spells': {'catalogs': {'spells': {'1': {'locales': {
                         'enUS': record('Deals $s1 damage.')}}}}}}
        self.assertEqual(RESYNC['WORK']['create_queue'](documents)['jobs'], [])
        queue = RESYNC['WORK']['create_queue'](documents, evidence=self.evidence())
        self.assertNotIn('policyVersion', queue)
        self.assertEqual({job['locale'] for job in queue['jobs']}, {'itIT'})
        self.assertEqual({row['locale'] for row in queue['blocked']}, {'frFR'})

    def test_official_languages_never_receive_ai_jobs(self):
        self.add()
        for locale in ('enUS', 'frFR', 'deDE'):
            queue = filter_queue(self.queue(locale), self.evidence())
            self.assertEqual(queue['jobs'], [])
            self.assertEqual(queue['blocked'][0]['reasons'], ['officialLocaleNeverAuthored'])

    def test_no_evidence_blocks_additional_language(self):
        queue = filter_queue(self.queue(), None)
        self.assertEqual(queue['jobs'], [])
        self.assertEqual(queue['blocked'][0]['reasons'], ['noVerifiedOfficialTranslation'])

    def test_catalog_quest_queue_requires_verified_source_and_objective_binding(self):
        summary = 'Scout the ridge.'
        capture = {'origin': 'original', 'source': 'wowClient', 'sourceLocale': 'enUS',
                   'sourceBuild': '70938'}
        english = {
            'summary': summary, 'eventObjectiveLabel': summary,
            'objectiveLines': [{'index': 2, 'type': 'event', 'text': summary}],
            'translationMetadata': {'fields': {
                'summary': {'origin': 'community', 'source': 'questie', 'sourceLocale': 'enUS'},
                'eventObjectiveLabel': {'origin': 'community', 'source': 'questie', 'sourceLocale': 'enUS'},
                'objectiveLines.2': capture,
            }},
        }
        verified = {'locales': {'enUS': english}}
        unverified = copy.deepcopy(verified)
        unverified_fields = unverified['locales']['enUS']['translationMetadata']['fields']
        for field in ('summary', 'objectiveLines.2'):
            unverified_fields[field]['origin'] = 'ai'
        doc = {'quests': {'locales': ['enUS', 'frFR', 'ltLT'],
                          'catalogs': {'quests': {'1': verified, '2': unverified}}}}
        queue = RESYNC['WORK']['create_queue'](doc)
        self.assertEqual({job['context'] for job in queue['jobs']},
                         {'quests.summary', 'quests.objectiveLines', 'quests.eventObjectiveLabel'})
        for job in queue['jobs']:
            self.assertEqual(job['locale'], 'ltLT')
            self.assertEqual([pointer['id'] for pointer in job['pointers']], ['1'])
        self.assertTrue(any(row['locale'] == 'frFR' and row['reasons'] == ['officialLocaleNeverAuthored']
                            for row in queue['blocked']))
        self.assertTrue(any(row['locale'] == 'ltLT' and row['reasons'] == ['noVerifiedClientObjectiveBinding']
                            and [pointer['id'] for pointer in row['pointers']] == ['2']
                            for row in queue['blocked']))

        binding = {'index': 2, 'type': 'event', 'source': 'wowClient', 'sourceLocale': 'frFR',
                   'sourceBuild': '71037', 'englishSha256': hashlib.sha256(summary.encode()).hexdigest()}
        unverified['clientObjectiveBindings'] = {'objectiveLines.2': binding,
                                                 'eventObjectiveLabel': {**binding, 'index': 1}}
        captured = RESYNC['WORK']['create_queue'](doc)
        pointers = {job['context']: {pointer['id'] for pointer in job['pointers']} for job in captured['jobs']}
        self.assertEqual(pointers, {'quests.summary': {'1'}, 'quests.objectiveLines': {'1', '2'},
                                   'quests.eventObjectiveLabel': {'1', '2'}})
        binding['englishSha256'] = hashlib.sha256(b'Stale wording').hexdigest()
        stale = RESYNC['WORK']['create_queue'](doc)
        objectives = next(job for job in stale['jobs'] if job['context'] == 'quests.objectiveLines')
        self.assertEqual([pointer['id'] for pointer in objectives['pointers']], ['1'])

    def test_quest_summary_exception_requires_both_pinned_sources_for_the_same_quest(self):
        summary = 'Return to Deliana.'
        questie = {'kind': 'quests', 'entity_id': '1', 'field': 'summary', 'locale': 'enUS',
                   'text': summary, 'english': summary, 'origin': 'community', 'source': 'questie',
                   'provenance': {'sourceRevision': 'a' * 40, 'layer': 'composedStaticWithAuthoredCorrections'}}
        blizzard = {'kind': 'quests', 'entity_id': '1', 'field': 'title', 'locale': 'enUS',
                    'text': 'Just Compensation', 'english': 'Just Compensation', 'source': 'blizzard',
                    'provenance': {'sourceNamespace': 'static-1.60.1_70399-forever-eu'}}
        for invalid in ({'evidence': 'catalogClaim'}, {'entity_id': '2'},
                        {'provenance': {'sourceNamespace': 'static-eu'}}):
            with self.subTest(invalid=invalid):
                self.db.execute('DELETE FROM records')
                self.add(**questie)
                self.add(**(blizzard | invalid))
                self.assertFalse(self.evidence().allows('quests', '1', 'summary', summary))

        self.db.execute('DELETE FROM records')
        self.add(**blizzard)
        self.add(**(questie | {'flags': ['headingOnlySummary']}))
        self.assertFalse(self.evidence().allows('quests', '1', 'summary', summary))
        self.add(**questie)
        evidence = self.evidence()
        self.assertIsNone(ai_block_reason('itIT', 'quests', '1', 'summary', summary, evidence))
        self.assertEqual(ai_block_reason('frFR', 'quests', '1', 'summary', summary, evidence),
                         'officialLocaleNeverAuthored')
        self.assertFalse(evidence.allows('quests', '1', 'description', summary))
        self.assertFalse(evidence.allows('quests', '1', 'summary', 'Return to Mokvar.'))

        self.add(**(questie | {'text': 'Return to Mokvar.', 'english': 'Return to Mokvar.'}))
        self.assertFalse(self.evidence().allows('quests', '1', 'summary', summary))

    def test_incremental_resync_replaces_ai_summary_with_matching_localized_source(self):
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        previous = self.root / 'previous.sqlite'
        old = sqlite3.connect(previous)
        self.db.backup(old)
        old.close()

        summary = 'Return to {name}.'
        source = {'kind': 'quests', 'field': 'summary', 'source': 'questie', 'origin': 'community',
                  'english': summary, 'provenance': {'sourceRevision': 'b' * 40}}
        self.add(**source, locale='itIT', text='Torna da {name}.')
        self.add(**source, locale='plPL', text='Wróć do miasta.')
        path = self.root / 'catalogs/quests/1.json'
        path.parent.mkdir(parents=True)
        (path.parent / 'metadata.json').write_text(json.dumps({'document': {
            'locales': ['enUS', 'frFR', 'itIT', 'plPL']}}))

        def summary_record(text, origin, provider):
            return {'summary': text, 'translationMetadata': {'fields': {'summary': {
                'origin': origin, 'source': provider, 'sourceLocale': 'enUS'}}}}

        polish = summary_record('Wróć do {name}.', 'ai', 'ForeverRosettaStoneAI')
        path.write_text(json.dumps({'locales': {
            'enUS': summary_record(summary, 'community', 'questie'),
            'itIT': summary_record('Ritorna da {name}.', 'ai', 'ForeverRosettaStoneAI'),
            'plPL': polish}}))
        output = self.root / 'datasources/imports/replace-ai-summary'
        RESYNC['prepare'](self.root, self.database, previous, output)
        RESYNC['apply'](self.root, output)
        RESYNC['verify'](self.root, output)
        after = json.loads(path.read_text())['locales']
        self.assertEqual(after['itIT']['summary'], 'Torna da {name}.')
        self.assertEqual(after['itIT']['translationMetadata']['fields']['summary']['origin'], 'community')
        self.assertEqual(after['plPL'], polish)

    def test_empty_sourced_globalstring_is_not_a_missing_translation(self):
        documents = {'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {'quests': {}}},
                     'globalstrings': {'catalogs': {'globalstrings': {'1': {'key': 'LARGE_NUMBER_SEPERATOR',
                        'locales': {'enUS': {'name': ','}, 'frFR': {'name': '', 'translationMetadata': {
                            'fields': {'name': {'origin': 'original', 'sourceLocale': 'frFR'}}}}}}}}}}
        candidates = RESYNC['WORK']['collect_translation_candidates'](documents)
        self.assertEqual(candidates['jobs'], [])

    def test_catalog_claims_ai_and_untrusted_providers_are_not_translation_proof(self):
        for options in ({'evidence': 'catalogClaim'},
                        {'origin': 'ai'}, {'source': 'unknown'},
                        {'locale': 'itIT'}, {'flags': ['unsupportedQuestMarkup']}):
            with self.subTest(options=options):
                self.db.execute('DELETE FROM records')
                self.add(**options)
                self.assertFalse(self.evidence().allows('spells', '1', 'description', 'Deals $s1 damage.'))

    def test_all_four_verified_core_sources_authorize_additional_translations(self):
        for provider, origin in [('wago', 'original'), ('blizzard', 'original'),
                                 ('questie', 'community'), ('egLink', 'original')]:
            with self.subTest(provider=provider):
                self.db.execute('DELETE FROM records')
                self.add(source=provider, origin=origin)
                self.assertTrue(self.evidence().allows('spells', '1', 'description', 'Deals $s1 damage.'))
                self.assertEqual(len(filter_queue(self.queue(), self.evidence())['jobs']), 1)

    def test_questie_revision_is_a_pin_not_a_game_build(self):
        self.add(source='questie', origin='community')
        self.db.execute("UPDATE records SET provenance=?", (json.dumps({
            'source': 'questie', 'sourceLocale': 'frFR', 'sourceRevision': 'pinned-commit'}),))
        self.db.commit()
        self.assertTrue(self.evidence().allows('spells', '1', 'description', 'Deals $s1 damage.'))
        self.db.execute("UPDATE records SET provenance=?", (json.dumps({
            'source': 'questie', 'sourceLocale': 'frFR'}),))
        self.db.commit()
        self.assertFalse(self.evidence().allows('spells', '1', 'description', 'Deals $s1 damage.'))

    def test_questie_fallback_or_flagged_rows_are_not_translation_proof(self):
        for options in ({'text': 'Deals $s1 damage.'}, {'flags': ['unverifiedNameVariant']},
                        {'origin': 'ai'}, {'evidence': 'catalogClaim'}):
            with self.subTest(options=options):
                self.db.execute('DELETE FROM records')
                self.add(source='questie', **options)
                self.assertFalse(self.evidence().allows('spells', '1', 'description', 'Deals $s1 damage.'))

    def test_english_copies_and_whitespace_differences_are_not_translation_proof(self):
        self.add(text='  Deals $s1\n damage.  ')
        self.assertEqual(filter_queue(self.queue(), self.evidence())['jobs'], [])

    def test_proof_must_match_entity_field_kind_and_english_context(self):
        self.add()
        evidence = self.evidence()
        for args in [('spells', '2', 'description', 'Deals $s1 damage.'),
                     ('spells', '1', 'auraDescription', 'Deals $s1 damage.'),
                     ('items', '1', 'description', 'Deals $s1 damage.'),
                     ('spells', '1', 'description', 'Deals $s2 damage.')]:
            self.assertFalse(evidence.allows(*args))
        self.assertTrue(evidence.allows('spells', '1', 'tooltip.description', 'Deals $s1 damage.'))

    def test_missing_or_changed_external_source_blocks_evidence(self):
        self.add()
        self.raw.write_text('Changed')
        with self.assertRaisesRegex(ValueError, 'Source changed'):
            self.evidence()

    def test_native_reuse_is_allowed_even_when_ai_is_blocked(self):
        queue = self.queue('frFR')
        queue['jobs'][0]['reuse'] = {'text': 'Inflige $s1 dégâts.', 'metadata': {'origin': 'community'}}
        filtered = filter_queue(queue, None)
        self.assertEqual(len(filtered['jobs']), 1)
        validate_queue_policy(filtered, [{'jobId': 'job', 'translation': 'Inflige $s1 dégâts.'}], self.root)
        with self.assertRaisesRegex(ValueError, 'officialLocaleNeverAuthored'):
            validate_queue_policy(filtered, [{'jobId': 'job', 'translation': 'Rewritten $s1'}], self.root)

    def test_saved_queue_revalidates_proof_instead_of_trusting_a_boolean(self):
        self.add()
        queue = filter_queue(self.queue(), self.evidence())
        validate_queue_policy(queue, [{'jobId': 'job', 'translation': 'Infligge $s1 danni.'}], self.root)
        self.db.execute('DELETE FROM records')
        self.db.commit()
        with self.assertRaisesRegex(ValueError, 'noVerifiedOfficialTranslation'):
            validate_queue_policy(queue, [{'jobId': 'job', 'translation': 'Infligge $s1 danni.'}], self.root)

    def test_batch_cannot_bypass_policy_but_preserves_unchanged_authored_fields(self):
        before = {'locales': {'enUS': record('Deals $s1 damage.'), 'frFR': record('Ancien $s1', 'ai')}}
        batch = {'records': {'spells': {'1': before}}}
        validate_batch_policy(batch, {'spells': {'1': before}}, None)
        after = copy.deepcopy(before)
        after['locales']['frFR']['description'] = 'Nouveau $s1'
        with self.assertRaisesRegex(ValueError, 'officialLocaleNeverAuthored'):
            validate_batch_policy(batch, {'spells': {'1': after}}, None)
        after = copy.deepcopy(before)
        after['locales']['itIT'] = record('Infligge $s1 danni.', 'ai')
        with self.assertRaisesRegex(ValueError, 'noVerifiedOfficialTranslation'):
            validate_batch_policy(batch, {'spells': {'1': after}}, None)
        self.add()
        validate_batch_policy(batch, {'spells': {'1': after}}, self.evidence())

    def test_community_localization_wins_over_official_english_fallback(self):
        before = {'locales': {'enUS': record('Deals $s1 damage.'), 'frFR': record('Deals $s1 damage.')}}
        rows = [{'locale': 'frFR', 'field': 'description', 'text': text, 'english': 'Deals $s1 damage.',
                 'origin': origin, 'provenance': json.dumps({'source': source, 'sourceLocale': 'frFR'})}
                for text, origin, source in [('Deals $s1 damage.', 'original', 'wago'),
                                             ('Inflige $s1 dégâts.', 'community', 'questie')]]
        after, _ = FILL['update_entity'](before, rows)
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige $s1 dégâts.')
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['description']['origin'], 'community')
        after, _ = FILL['update_entity'](after, rows[:1])
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige $s1 dégâts.')

    def test_ai_official_target_uses_english_but_extra_language_is_preserved(self):
        before = {'locales': {'enUS': record('Deals $s1 damage.'),
                             'frFR': record('Traduction $s1', 'ai'), 'itIT': record('Traduzione $s1', 'ai')}}
        after, counts, unresolved = RESYNC['reconcile_official_targets'](before, {'description'}, ['enUS', 'frFR', 'itIT'])
        self.assertEqual(after['locales']['frFR'], before['locales']['enUS'])
        self.assertEqual(after['locales']['itIT'], before['locales']['itIT'])
        self.assertEqual(counts['officialEnglishFallback'], 1)
        self.assertFalse(unresolved)
        self.assertEqual(RESYNC['reconcile_official_targets'](after, set(), ['enUS', 'frFR'])[0], after)

    def test_english_authorship_provenance_is_not_falsely_promoted(self):
        before = {'locales': {'enUS': record('Owned English source.', 'ai'),
                             'frFR': record('Traduction IA.', 'ai')}}
        after, counts, _ = RESYNC['reconcile_official_targets'](before, {'description'}, ['enUS', 'frFR'])
        self.assertEqual(after['locales']['frFR'], before['locales']['enUS'])
        self.assertEqual(counts['fallbackRetainsEnglishSourceAIProvenance'], 1)

    def test_item_set_eligibility_uses_owned_binding_and_verified_game_exports(self):
        self.add()
        results = []
        for locale, text in [('enUS', 'Stormcloth Regalia'), ('frFR', 'Tenue en étoffe-tempête')]:
            path = self.root / ('ItemSet.1.60.1.70938.' + locale + '.csv')
            path.write_text('ID,Name_lang\n42,' + text + '\n')
            results.append({'table': 'ItemSet', 'locale': locale, 'file': path.name,
                            'status': 'downloaded', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps({'build': '1.60.1.70938', 'complete': True, 'results': results}))
        self.db.execute('INSERT INTO inputs VALUES(?,?)',
                        ('manifest.json', hashlib.sha256(manifest.read_bytes()).hexdigest()))
        self.db.commit()
        entity = {'tooltipData': {'itemSet': 42, 'set': {'name': 'Stormcloth Regalia'}},
                  'locales': {'enUS': {'name': 'Pants'}, 'itIT': {'setName': 'Completo della tempesta',
                    'translationMetadata': {'fields': {'setName': {'origin': 'ai', 'sourceLocale': 'enUS'}}}}}}
        evidence = self.evidence()
        self.assertTrue(evidence.allows('items', '1', 'setName', None, entity=entity))
        self.assertEqual(english_source(entity, 'setName', evidence)[0], 'Stormcloth Regalia')
        self.assertEqual(english_source(entity, 'setName', evidence)[1]['source'], 'wago')
        self.assertFalse(evidence.allows('items', '1', 'setName', 'A different set', entity=entity))
        entity['tooltipData']['itemSet'] = 43
        self.assertFalse(evidence.allows('items', '1', 'setName', None, entity=entity))
        path.write_text('ID,Name_lang\n42,Modified\n')
        with self.assertRaisesRegex(ValueError, 'ItemSet source changed'):
            self.evidence()

    def test_empty_english_source_is_copied_with_its_provenance(self):
        entity = {'locales': {'enUS': {'name': '', 'translationMetadata': {'fields': {'name': {
            'origin': 'original', 'sourceLocale': 'enUS', 'source': 'wago'}}}},
            'itIT': {'name': '', 'translationMetadata': {'fields': {'name': {'origin': 'ai'}}}}}}
        entity['locales']['frFR'] = entity['locales'].pop('itIT')
        after, counts, issues = RESYNC['reconcile_official_targets'](entity, {'name'}, ['frFR'])
        self.assertFalse(issues)
        self.assertEqual(after['locales']['frFR'], entity['locales']['enUS'])
        self.assertEqual(counts['officialEnglishFallback'], 1)

    def test_missing_english_stays_explicit_and_objective_bindings_are_not_invented(self):
        before = {'locales': {'enUS': record('English.'), 'frFR': {'name': 'Nom IA',
            'translationMetadata': {'fields': {'name': {'origin': 'ai'}}}}}}
        after, _, unresolved = RESYNC['reconcile_official_targets'](before, {'name', 'objectiveLines.1'}, ['frFR'])
        self.assertEqual(after['locales']['frFR']['name'], 'Nom IA')
        self.assertEqual(unresolved[0]['reason'], 'missingOwnedEnglishSource')
        self.assertNotIn('objectiveLines', after['locales']['frFR'])

    def test_upstream_only_fields_do_not_require_fallbacks_or_create_locale_slots(self):
        before = {'locales': {'enUS': record('English.')}}
        after, counts, unresolved = RESYNC['reconcile_official_targets'](
            before, {'summary', 'auraDescription'}, ['frFR', 'deDE'])
        self.assertEqual(after, before)
        self.assertFalse(counts)
        self.assertEqual(unresolved, [])

    def test_existing_english_without_provenance_remains_a_real_source_issue(self):
        before = {'locales': {'enUS': {'description': 'English.'}}}
        after, counts, unresolved = RESYNC['reconcile_official_targets'](
            before, {'description'}, ['frFR'])
        self.assertEqual(after, before)
        self.assertFalse(counts)
        self.assertEqual(unresolved, [{'locale': 'frFR', 'field': 'description',
                                      'reason': 'missingOwnedEnglishSource'}])

    def test_first_import_applies_supported_fields_despite_upstream_only_text(self):
        self.add()
        self.add(text='Upstream aura', english=None, locale='csCZ', field='auraDescription',
                 source='czechForever', origin='community')
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'csCZ']}}))
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        accepted = record('Accepted Czech $s1', 'ai')
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'frFR': record('Old $s1', 'ai'), 'csCZ': accepted}}))
        output = self.root / 'datasources/imports/upstream-only'
        summary = RESYNC['prepare'](self.root, self.database, None, output)
        self.assertEqual(summary['unresolvedFields'], 0)
        RESYNC['apply'](self.root, output)
        RESYNC['verify'](self.root, output)
        after = json.loads(path.read_text())
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige $s1 dégâts.')
        self.assertEqual(after['locales']['csCZ'], accepted)
        self.assertTrue(all('auraDescription' not in record for record in after['locales'].values()))

    def test_pipeline_prepares_applies_verifies_and_is_idempotent(self):
        self.add()
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'frFR': record('Mauvais $s1', 'ai'),
                                               'itIT': record('Italiano $s1', 'ai')}}))
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'itIT']}}))
        before = path.read_bytes()
        output = self.root / 'datasources/imports/first'
        previous = self.root / 'previous.sqlite'
        old = sqlite3.connect(previous)
        self.db.backup(old)
        old.execute('DELETE FROM records')
        old.commit()
        old.close()
        summary = RESYNC['prepare'](self.root, self.database, previous, output)
        self.assertEqual(summary['changedFiles'], 1)
        self.assertNotIn('policyVersion', json.loads((output / 'manifest.json').read_text()))
        self.assertEqual(path.read_bytes(), before)
        self.assertEqual(RESYNC['apply'](self.root, output)['writtenFiles'], 1)
        self.assertEqual(RESYNC['verify'](self.root, output)['verifiedFiles'], 1)
        after = json.loads(path.read_text())
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige $s1 dégâts.')
        self.assertEqual(after['locales']['itIT']['description'], 'Italiano $s1')
        second = RESYNC['prepare'](self.root, self.database, self.database,
                                   self.root / 'datasources/imports/second')
        self.assertEqual(second['changedFiles'], 0)

    def test_unchanged_sources_do_not_repeat_historical_reset(self):
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'itIT']}}))
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'itIT': record('Historic authored text', 'ai')}}))
        before = path.read_bytes()
        summary = RESYNC['prepare'](self.root, self.database, self.database,
                                   self.root / 'datasources/imports/unchanged')
        self.assertEqual(summary['changedFiles'], 0)
        self.assertEqual(path.read_bytes(), before)

    def test_source_update_keeps_existing_extra_languages_without_new_job_evidence(self):
        self.add(text='Deals $s1 damage.', locale='enUS', kind='quests')
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        previous = self.root / 'previous.sqlite'
        old = sqlite3.connect(previous)
        self.db.backup(old)
        old.execute('DELETE FROM records')
        old.commit()
        old.close()
        path = self.root / 'catalogs/quests/1.json'
        path.parent.mkdir(parents=True)
        config = path.parent / 'metadata.json'
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'itIT']}}))
        authored = record('Italiano $s1', 'ai')
        authored['objectiveLines'] = [{'index': 1, 'type': 'event', 'text': 'Obiettivo tradotto'}]
        authored['translationMetadata']['fields']['objectiveLines.1'] = {
            'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS'}
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'frFR': record('Ancien $s1', 'ai'), 'itIT': authored}}))
        output = self.root / 'datasources/imports/preserve-existing'
        RESYNC['prepare'](self.root, self.database, previous, output)
        RESYNC['apply'](self.root, output)
        after = json.loads(path.read_text())
        self.assertEqual(after['locales']['itIT'], authored)
        self.assertEqual(after['locales']['frFR']['description'], 'Deals $s1 damage.')
        self.assertFalse(self.evidence().allows('quests', '1', 'description', 'Deals $s1 damage.'))

    def test_repaired_english_context_replaces_explicit_official_language_fallback(self):
        self.add(source='questie', origin='community')
        self.db.execute('UPDATE records SET english=NULL')
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        previous = self.root / 'previous.sqlite'
        old = sqlite3.connect(previous)
        self.db.backup(old)
        old.close()
        self.db.execute('UPDATE records SET english=?', ('Deals $s1 damage.',))
        self.db.commit()
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'itIT']}}))
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'frFR': record('Deals $s1 damage.'),
                                               'itIT': record('Italiano $s1', 'ai')}}))
        output = self.root / 'datasources/imports/repaired-context'
        RESYNC['prepare'](self.root, self.database, previous, output)
        RESYNC['apply'](self.root, output)
        after = json.loads(path.read_text())
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige $s1 dégâts.')
        self.assertEqual(after['locales']['itIT']['description'], 'Italiano $s1')

    def test_pipeline_compares_unchanged_newer_provider_for_an_affected_field(self):
        self.add(text='Ancien Wago $s1')
        self.add(text='Blizzard actuel $s1', source='blizzard')
        self.db.execute("UPDATE records SET provenance=? WHERE json_extract(provenance,'$.source')='blizzard'",
                        (json.dumps({'source': 'blizzard', 'sourceLocale': 'frFR',
                                     'sourceNamespace': 'static-1.60.1_71000-forever-eu'}),))
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        previous = self.root / 'previous.sqlite'
        old = sqlite3.connect(previous)
        self.db.backup(old)
        old.close()
        self.db.execute("UPDATE records SET text='Nouveau Wago $s1' WHERE json_extract(provenance,'$.source')='wago'")
        self.db.commit()
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR']}}))
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'frFR': record('Ancien Wago $s1')}}))
        output = self.root / 'datasources/imports/priority'
        RESYNC['prepare'](self.root, self.database, previous, output)
        RESYNC['apply'](self.root, output)
        self.assertEqual(json.loads(path.read_text())['locales']['frFR']['description'], 'Blizzard actuel $s1')

    def test_pipeline_preflights_all_conflicts_before_writing(self):
        output = self.root / 'datasources/imports/prepared'
        output.mkdir(parents=True)
        files = []
        for entity_id in ('1', '2'):
            path = self.root / ('catalogs/spells/' + entity_id + '.json')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'original')
            result = entity_id + '.json'
            (output / result).write_bytes(b'expected')
            files.append({'path': str(path.relative_to(self.root)), 'result': result,
                          'beforeSha256': hashlib.sha256(b'original').hexdigest(),
                          'afterSha256': hashlib.sha256(b'expected').hexdigest()})
        manifest = {'database': str(self.database), 'databaseSha256': RESYNC['PLAN']['file_sha'](self.database),
                    'files': files}
        (output / 'manifest.json').write_text(json.dumps(manifest))
        (self.root / files[1]['path']).write_bytes(b'concurrent')
        with self.assertRaisesRegex(ValueError, 'Concurrent catalog edit'):
            RESYNC['apply'](self.root, output)
        self.assertEqual((self.root / files[0]['path']).read_bytes(), b'original')

    def test_newer_provider_replaces_owned_core_source_but_not_manual_override(self):
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        previous = self.root / 'previous.sqlite'
        old = sqlite3.connect(previous)
        self.db.backup(old)
        old.close()
        self.add(source='blizzard')
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR']}}))
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        for provider, expected in [('wago', 'Inflige $s1 dégâts.'), ('manual', 'Correction $s1')]:
            before = {'locales': {'enUS': record('Deals $s1 damage.'),
                                  'frFR': record('Correction $s1', locale='frFR')}}
            before['locales']['frFR']['translationMetadata']['fields']['description'].update(
                {'source': provider, 'sourceBuild': '1.60.1.70888'})
            path.write_text(json.dumps(before))
            output = self.root / ('datasources/imports/provider-' + provider)
            RESYNC['prepare'](self.root, self.database, previous, output)
            RESYNC['apply'](self.root, output)
            self.assertEqual(json.loads(path.read_text())['locales']['frFR']['description'], expected)

    def test_first_import_needs_no_previous_download_or_prepared_policy(self):
        self.add()
        self.db.execute('INSERT INTO settings VALUES(?,?)', ('fingerprint', json.dumps('pinned-fixture')))
        self.db.commit()
        config = self.root / 'catalogs/quests/metadata.json'
        config.parent.mkdir(parents=True)
        config.write_text(json.dumps({'document': {'locales': ['enUS', 'frFR', 'itIT']}}))
        path = self.root / 'catalogs/spells/1.json'
        path.parent.mkdir(parents=True)
        accepted = record('Italiano $s1', 'ai')
        path.write_text(json.dumps({'locales': {'enUS': record('Deals $s1 damage.'),
                                               'frFR': record('Ancien $s1', 'ai'), 'itIT': accepted}}))
        output = self.root / 'datasources/imports/first-import'
        RESYNC['prepare'](self.root, self.database, None, output)
        RESYNC['apply'](self.root, output)
        RESYNC['verify'](self.root, output)
        after = json.loads(path.read_text())
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige $s1 dégâts.')
        self.assertEqual(after['locales']['itIT'], accepted)
        second = RESYNC['prepare'](self.root, self.database, None,
                                   self.root / 'datasources/imports/first-import-repeated')
        self.assertEqual(second['changedFiles'], 0)


if __name__ == '__main__':
    unittest.main()
