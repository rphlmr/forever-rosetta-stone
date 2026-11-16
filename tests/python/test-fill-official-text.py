"""Check deterministic official-source replacement without changing protected source wording."""

import json
import runpy
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
fill = runpy.run_path(str(ROOT / 'tools/catalogs/fill-official-text.py'))
from datasources.corpus.translation_corpus import SCHEMA


def candidate(locale, field, text, english='Fireball'):
    return {'locale': locale, 'field': field, 'text': text, 'english': english, 'origin': 'original',
            'provenance': json.dumps({'source': 'wago', 'sourceLocale': locale, 'sourceBuild': '1.60.1.70888'})}


class OfficialSourceFillTests(unittest.TestCase):
    def entity(self):
        return {'locales': {'enUS': {'name': 'Fireball'}, 'frFR': {
            'name': 'Mauvaise traduction', 'translationMetadata': {'fields': {'name': {
                'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': 'enUS',
            }}}}}, 'tooltipData': {'effects': [{'points': 10}]}}

    def test_replaces_ai_with_official_and_preserves_structure(self):
        before = self.entity()
        after, counts = fill['update_entity'](before, [candidate('frFR', 'name', 'Boule de feu')])
        self.assertEqual(after['locales']['frFR']['name'], 'Boule de feu')
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['name']['origin'], 'original')
        self.assertEqual(after['tooltipData'], before['tooltipData'])
        self.assertEqual(before['locales']['frFR']['name'], 'Mauvaise traduction')
        self.assertEqual(counts['replaced'], 1)

    def test_description_fill_updates_locales_without_refreshing_source_maps(self):
        before = self.entity()
        before['locales']['enUS']['description'] = 'Deals damage.'
        before['locales']['frFR']['description'] = 'Ancienne traduction.'
        before['tooltipData']['sourceDescriptions'] = {'frFR': 'Ancienne source.'}
        after, counts = fill['update_entity'](before, [
            candidate('frFR', 'description', 'Inflige des dégâts.', 'Deals damage.'),
        ])
        self.assertEqual(after['locales']['frFR']['description'], 'Inflige des dégâts.')
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['description'], {
            'origin': 'original', 'source': 'wago', 'sourceLocale': 'frFR', 'sourceBuild': '1.60.1.70888',
        })
        self.assertEqual(after['tooltipData'], before['tooltipData'])
        self.assertEqual(counts['replaced'], 1)

    def test_default_candidates_prefer_community_evidence_over_local_ai(self):
        import sqlite3
        db = sqlite3.connect(':memory:')
        db.row_factory = sqlite3.Row
        db.execute('CREATE TABLE records (kind,entity_id,locale,field,text,english,origin,evidence,provenance,flags,id)')
        for index, origin in enumerate(('community', 'ai'), 1):
            db.execute('INSERT INTO records VALUES (?,?,?,?,?,?,?,?,?,?,?)',
                       ('spells', '1', 'frFR', 'name', origin, 'English', origin,
                        'sourceSnapshot', '{}', '[]', index))
        rows = list(fill['source_rows'](db))
        self.assertEqual([row['origin'] for row in rows], ['community'])
        self.assertEqual(list(fill['source_rows'](db, include_community=False)), [])
        db.close()

    def test_community_source_stays_community_and_cannot_replace_official(self):
        row = candidate('frFR', 'name', 'Nom communautaire')
        row['origin'] = 'community'
        row['provenance'] = json.dumps({'source': 'questie', 'sourceLocale': 'frFR', 'sourceRevision': 'pinned'})
        before = self.entity()
        after, _ = fill['update_entity'](before, [row])
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['name']['origin'], 'community')
        before['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'original'
        after, counts = fill['update_entity'](before, [row])
        self.assertEqual(after, before)
        self.assertEqual(counts['preservedPreferredOfficial'], 1)

    def test_kind_scope_does_not_modify_other_catalogs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, database, _ = self.prepared_fixture(root)
            summary = fill['prepare'](database, root / 'datasources/imports/npcs-only', root=root,
                                      kinds=['npcs'], include_community=True)
            self.assertEqual(summary['chunks'], [])

    def test_community_prose_cannot_introduce_or_drop_source_placeholders(self):
        for english, target in [('Bring the staff.', '가져가야 합니{name}.'),
                                ('Bring it, {name}.', 'Apportez cet objet.'),
                                ('Bring 10 motes.', 'Принесите 10 |4частицу:частицы:частиц;.'),
                                ('Bring it.', '$gMalformed;')]:
            before = self.entity()
            before['locales']['enUS']['summary'] = english
            before['locales']['frFR']['summary'] = 'Existing maintained translation.'
            row = candidate('frFR', 'summary', target, english)
            row['origin'] = 'community'
            after, counts = fill['update_entity'](before, [row])
            self.assertEqual(after, before)
            self.assertEqual(counts['communityPlaceholderMismatch'], 1)

    def test_community_prose_with_matching_placeholders_can_replace_ai(self):
        before = self.entity()
        before['locales']['enUS']['summary'] = 'Bring it, {name}.'
        row = candidate('frFR', 'summary', 'Apportez cet objet, {name}.', 'Bring it, {name}.')
        row['origin'] = 'community'
        after, counts = fill['update_entity'](before, [row])
        self.assertEqual(after['locales']['frFR']['summary'], row['text'])
        self.assertEqual(counts['filled'], 1)

    def test_verified_names_can_update_previous_english_spelling(self):
        after, counts = fill['update_entity'](self.entity(), [candidate('enUS', 'name', 'Corrected source name')])
        self.assertEqual(after['locales']['enUS']['name'], 'Corrected source name')
        self.assertEqual(counts['replaced'], 1)

    def test_trusted_quest_title_updates_by_id_without_a_prose_context_pair(self):
        before = self.entity()
        before['locales']['enUS']['title'] = 'English title'
        before['locales']['frFR']['title'] = 'Titre IA'
        after, _ = fill['update_entity'](before, [candidate('frFR', 'title', 'Titre vérifié', None)])
        self.assertEqual(after['locales']['frFR']['title'], 'Titre vérifié')

    def test_same_build_server_hotfix_takes_precedence_over_client_text(self):
        client = candidate('enUS', 'name', 'Client name')
        server = candidate('enUS', 'name', 'Server name')
        server['provenance'] = json.dumps({'source': 'egLink', 'sourceLocale': 'enUS',
                                           'sourceBuild': '1.60.1.70888', 'sourceRevision': 'pinned'})
        after, _ = fill['update_entity'](self.entity(), [client, server])
        self.assertEqual(after['locales']['enUS']['name'], 'Server name')

    def test_latest_verified_client_build_wins_over_older_name_snapshot(self):
        old = candidate('frFR', 'name', 'Ancien nom')
        new = candidate('frFR', 'name', 'Nom actuel')
        old['provenance'] = json.dumps({'source': 'wago', 'sourceLocale': 'frFR', 'sourceBuild': '1.60.1.70862'})
        new['provenance'] = json.dumps({'source': 'wago', 'sourceLocale': 'frFR', 'sourceBuild': '1.60.1.70888'})
        after, _ = fill['update_entity'](self.entity(), [old, new])
        self.assertEqual(after['locales']['frFR']['name'], 'Nom actuel')

    def test_newer_blizzard_namespace_wins_over_other_core_source_builds(self):
        for provider in ('wago', 'egLink', 'questie'):
            with self.subTest(provider=provider):
                old = candidate('frFR', 'name', 'Ancien nom')
                old['provenance'] = json.dumps({'source': provider, 'sourceLocale': 'frFR',
                                                'sourceBuild': '1.60.1.70888'})
                if provider == 'questie':
                    old['origin'] = 'community'
                new = candidate('frFR', 'name', 'Nom Blizzard actuel')
                new['provenance'] = json.dumps({'source': 'blizzard', 'sourceLocale': 'frFR',
                                                'sourceNamespace': 'static-1.60.1_70938-forever-eu'})
                after, _ = fill['update_entity'](self.entity(), [old, new])
                self.assertEqual(after['locales']['frFR']['name'], 'Nom Blizzard actuel')
                self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['name']['source'], 'blizzard')

    def test_older_blizzard_namespace_does_not_override_newer_wago_or_eg(self):
        old = candidate('frFR', 'name', 'Ancien nom Blizzard')
        old['provenance'] = json.dumps({'source': 'blizzard', 'sourceLocale': 'frFR',
                                       'sourceNamespace': 'static-1.60.1_70399-forever-eu'})
        for provider in ('wago', 'egLink', 'questie'):
            new = candidate('frFR', 'name', 'Nom actuel')
            new['origin'] = 'community' if provider == 'questie' else 'original'
            new['provenance'] = json.dumps({'source': provider, 'sourceLocale': 'frFR',
                                           'sourceBuild': '1.60.1.70938'})
            after, _ = fill['update_entity'](self.entity(), [old, new])
            self.assertEqual(after['locales']['frFR']['name'], 'Nom actuel')

    def test_git_revisions_do_not_establish_source_build_priority(self):
        blizzard = {'source': 'blizzard', 'sourceNamespace': 'static-1.60.1_71000-forever-eu'}
        questie = {'source': 'questie', 'sourceRevision': '9999999999999999999999999999999999999999'}
        self.assertFalse(fill['newer_core_source'](blizzard, questie))
        self.assertFalse(fill['newer_core_source'](questie, blizzard))

    def test_single_stale_provider_update_cannot_replace_newer_owned_source(self):
        entity = self.entity()
        entity['locales']['frFR']['name'] = 'Nom actuel'
        entity['locales']['frFR']['translationMetadata']['fields']['name'] = {
            'origin': 'community', 'source': 'questie', 'sourceLocale': 'frFR',
            'sourceBuild': '1.60.1.70938'}
        row = candidate('frFR', 'name', 'Ancien nom Blizzard')
        row['provenance'] = json.dumps({'source': 'blizzard', 'sourceLocale': 'frFR',
                                       'sourceNamespace': 'static-1.60.1_70399-forever-eu'})
        after, counts = fill['update_entity'](entity, [row])
        self.assertEqual(after, entity)
        self.assertEqual(counts['preservedNewerSource'], 1)

    def test_newer_blizzard_keeps_exact_text_and_updates_its_provenance(self):
        entity = self.entity()
        entity['locales']['frFR']['name'] = 'Même nom'
        entity['locales']['frFR']['translationMetadata']['fields']['name'] = {
            'origin': 'original', 'source': 'wago', 'sourceLocale': 'frFR',
            'sourceBuild': '1.60.1.70888'}
        row = candidate('frFR', 'name', 'Même nom')
        row['provenance'] = json.dumps({'source': 'blizzard', 'sourceLocale': 'frFR',
                                       'sourceNamespace': 'static-1.60.1_70938-forever-eu'})
        after, _ = fill['update_entity'](entity, [row])
        self.assertEqual(after['locales']['frFR']['name'], 'Même nom')
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['name']['source'], 'blizzard')

    def test_preserves_matching_native_text_and_metadata(self):
        before = self.entity()
        before['locales']['frFR']['name'] = 'Boule de feu'
        before['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'original'
        after, counts = fill['update_entity'](before, [candidate('frFR', 'name', 'Boule de feu')])
        self.assertEqual(after, before)
        self.assertEqual(counts['alreadyOfficial'], 1)

    def test_english_fallback_preserves_existing_additional_text_of_every_origin(self):
        for field in ('name', 'summary'):
            for origin in ('original', 'community', 'ai'):
                before = self.entity()
                before['locales']['enUS'][field] = 'Fireball'
                before['locales']['itIT'] = {field: 'Nome già tradotto', 'translationMetadata': {
                    'fields': {field: {'origin': origin, 'source': 'egLink', 'sourceLocale': 'enUS'}}}}
                row = candidate('itIT', field, 'Fireball')
                after, _ = fill['update_entity'](before, [row])
                self.assertEqual(after['locales']['itIT'], before['locales']['itIT'])

    def test_fills_missing_and_replaces_incorrect_native(self):
        before = self.entity()
        before['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'original'
        rows = [candidate('deDE', 'name', 'Feuerball'), candidate('frFR', 'name', 'Boule de feu')]
        after, counts = fill['update_entity'](before, rows)
        self.assertEqual(after['locales']['deDE']['name'], 'Feuerball')
        self.assertEqual(after['locales']['frFR']['name'], 'Boule de feu')
        self.assertEqual((counts['filled'], counts['replaced']), (1, 1))

    def test_rejects_conflicting_sources(self):
        before = self.entity()
        rows = [candidate('frFR', 'name', 'A'), candidate('frFR', 'name', 'B')]
        after, counts = fill['update_entity'](before, rows)
        self.assertEqual(after, before)
        self.assertEqual(counts['conflictingSources'], 1)

    def test_rejects_changed_source_context_and_unresolved_templates(self):
        before = self.entity()
        before['locales']['enUS']['description'] = 'Canonical source'
        after, counts = fill['update_entity'](before, [candidate('frFR', 'description', 'Éclair', 'Different source')])
        self.assertEqual(after, before)
        self.assertEqual(counts['sourceContextMismatch'], 1)
        for text in ('$@null', '\r\n'):
            with self.subTest(text=text):
                after, counts = fill['update_entity'](before, [candidate('frFR', 'description', text)])
                self.assertEqual(after, before)
                self.assertEqual(counts['unresolvedSourceTemplate'], 1)

    def test_preserves_canonical_english_without_creating_duplicate_english(self):
        before = self.entity()
        before['locales']['enUS']['description'] = 'Canonical source'
        after, counts = fill['update_entity'](before, [candidate('enUS', 'description', 'Different')])
        self.assertEqual(after, before)
        self.assertEqual(counts['preservedCanonicalEnglish'], 1)
        after, counts = fill['update_entity'](before, [candidate('enUS', 'rank', 'Rank 1', 'Rank 1')])
        self.assertEqual(after['locales']['enUS']['rank'], 'Rank 1')
        self.assertNotIn('enGB', after['locales'])

    def test_reviewed_english_update_can_replace_old_prose(self):
        before = self.entity()
        before['locales']['enUS']['description'] = 'Old requirement'
        after, counts = fill['update_entity'](before, [candidate('enUS', 'description', 'New requirement')],
                                             update_english=True)
        self.assertEqual(after['locales']['enUS']['description'], 'New requirement')
        self.assertEqual(counts['replaced'], 1)

    def test_trusted_summary_can_replace_ai_objective_tokens_with_literal_amounts(self):
        before = self.entity()
        before['locales']['enUS']['summary'] = 'Bring $1oa crystals.'
        before['locales']['frFR']['summary'] = 'Rapportez $1oa cristaux.'
        row = candidate('frFR', 'summary', 'Rapportez 1 cristal.', 'Bring $1oa crystals.')
        after, counts = fill['update_entity'](before, [row], update_english=True)
        self.assertEqual(after['locales']['frFR']['summary'], 'Rapportez 1 cristal.')
        self.assertEqual(counts['replaced'], 1)

    def test_blizzard_title_wins_and_questie_fills_a_missing_title(self):
        before = self.entity()
        before['locales']['enUS']['title'] = 'English quest title'
        original = candidate('frFR', 'title', 'Titre Blizzard')
        original['provenance'] = json.dumps({'source': 'blizzard', 'sourceLocale': 'frFR'})
        fallback = candidate('frFR', 'title', 'Titre Questie')
        fallback['origin'] = 'community'
        fallback['provenance'] = json.dumps({'source': 'questie', 'sourceLocale': 'frFR'})
        after, _ = fill['update_entity'](before, [fallback, original])
        self.assertEqual(after['locales']['frFR']['title'], 'Titre Blizzard')
        after, _ = fill['update_entity'](before, [fallback])
        self.assertEqual(after['locales']['frFR']['title'], 'Titre Questie')

    def test_questie_summary_has_priority_over_core_providers_that_do_not_own_it(self):
        before = self.entity()
        before['locales']['enUS']['summary'] = 'Bring 6 crystals.'
        before['locales']['frFR']['summary'] = 'Ancien résumé.'
        row = candidate('frFR', 'summary', 'Rapportez 6 cristaux.', 'Bring 6 crystals.')
        row['origin'] = 'community'
        row['provenance'] = json.dumps({'source': 'questie', 'sourceLocale': 'frFR'})
        for provider in ('egLink', 'wago', 'blizzard'):
            before['locales']['frFR']['translationMetadata']['fields']['summary'] = {
                'origin': 'original', 'source': provider}
            after, _ = fill['update_entity'](before, [row])
            self.assertEqual(after['locales']['frFR']['summary'], 'Rapportez 6 cristaux.')

    def prepared_fixture(self, root):
        catalog = root / 'catalogs/spells/1.json'
        catalog.parent.mkdir(parents=True)
        catalog.write_text(json.dumps(self.entity()))
        native = root / 'native.txt'
        native.write_text('Pinned native fixture')
        database = root / 'corpus.sqlite'
        db = sqlite3.connect(database)
        db.executescript(SCHEMA)
        db.execute('INSERT INTO settings VALUES(?,?)', ('schemaVersion', '1'))
        db.execute('INSERT INTO inputs VALUES(?,?)', ('native.txt', fill['sha256'](native.read_bytes())))
        for evidence, text in (('sourceSnapshot', 'Boule de feu'), ('catalogClaim', 'Not official proof')):
            row = candidate('frFR', 'name', text)
            db.execute('INSERT INTO records VALUES(NULL,?,?,?,?,?,?,?,?,?,?,?)', (
                'spells', '1', 'frFR', 'name', text, 'Fireball', 'original', evidence,
                row['provenance'], 'native.txt', '[]'))
        db.commit()
        db.close()
        output = root / 'datasources/imports/fill'
        fill['prepare'](database, output, root=root)

        return catalog, database, output

    def test_authored_audit_uses_only_verified_snapshots_and_never_writes_catalogs(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            catalog,database,_=self.prepared_fixture(root)
            before=catalog.read_bytes()
            output=root/'audit.json'
            summary=fill['audit_authored'](database,output,root=root)
            self.assertEqual((summary['fields'],summary['entities']),(1,1))
            finding=json.loads(output.read_text())['findings'][0]
            self.assertEqual(finding['official'],'Boule de feu')
            self.assertEqual(catalog.read_bytes(),before)
            (root/'native.txt').write_text('Changed snapshot')
            with self.assertRaisesRegex(ValueError,'Source changed'):
                fill['audit_authored'](database,output,root=root)

    def test_generator_applies_only_official_snapshot_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, database, output = self.prepared_fixture(root)
            applied = fill['apply_prepared'](output, root=root)
            self.assertEqual(applied['generatedFilesWritten'], 1)
            self.assertEqual(json.loads(catalog.read_text())['locales']['frFR']['name'], 'Boule de feu')
            self.assertEqual(fill['verify'](output, root=root)['verifiedFiles'], 1)
            next_plan = fill['prepare'](database, root / 'datasources/imports/next', root=root)
            self.assertEqual(next_plan['chunks'], [])

    def test_authored_audit_excludes_retired_quests_like_the_generator(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, database, _ = self.prepared_fixture(root)
            quest = root / 'catalogs/quests/1.json'
            quest.parent.mkdir(parents=True)
            entity = json.loads(catalog.read_text())
            entity['usageStatus'] = 'unused'
            for entry in entity['locales'].values():
                entry['title'] = entry.pop('name')
                metadata = entry.get('translationMetadata', {}).get('fields', {})
                if 'name' in metadata:
                    metadata['title'] = metadata.pop('name')
            quest.write_text(json.dumps(entity))
            db = sqlite3.connect(database)
            db.execute("UPDATE records SET kind='quests',field='title'")
            db.commit()
            db.close()
            summary = fill['audit_authored'](database, root / 'audit.json', root=root)
            self.assertEqual(summary['fields'], 0)
            self.assertEqual(summary['counts']['excludedQuestEntities'], 1)

    def test_generator_rejects_concurrent_catalog_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, _, output = self.prepared_fixture(root)
            manual = self.entity()
            manual['locales']['frFR']['name'] = 'Concurrent manual edit'
            catalog.write_text(json.dumps(manual))
            with self.assertRaisesRegex(ValueError, 'changed since source matching'):
                fill['apply_prepared'](output, root=root)
            self.assertEqual(json.loads(catalog.read_text()), manual)

    def test_scoped_generator_preserves_unselected_fields_and_applies_selected_fields(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            catalog, database, _ = self.prepared_fixture(root)
            before = catalog.read_bytes()
            empty = fill['prepare'](database, root / 'datasources/imports/empty', root=root, scope=set())
            self.assertEqual(empty['chunks'], [])
            scoped = root / 'datasources/imports/scoped'
            fill['prepare'](database, scoped, root=root, scope={('spells', '1', 'frFR', 'name')})
            self.assertEqual(catalog.read_bytes(), before)
            fill['apply_prepared'](scoped, root=root)
            self.assertEqual(json.loads(catalog.read_text())['locales']['frFR']['name'], 'Boule de feu')

    def test_provider_scope_excludes_unchanged_competing_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            _, database, _ = self.prepared_fixture(root)
            db = sqlite3.connect(database)
            db.row_factory = sqlite3.Row
            self.addCleanup(db.close)
            rows = list(fill['source_rows'](db, scope={('spells', '1', 'frFR', 'name', 'questie')}))
            self.assertEqual(rows, [])
            rows = list(fill['source_rows'](db, scope={('spells', '1', 'frFR', 'name', 'wago')}))
            self.assertEqual([row['text'] for row in rows], ['Boule de feu'])


if __name__ == '__main__':
    unittest.main()
