"""Check reference isolation, source integrity, fallback flags and bounded retrieval."""

import csv
import hashlib
import importlib.util
import json
import runpy
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import dump_json
from datasources.corpus.translation_corpus import CorpusBuilder, SCHEMA, build, open_corpus, packet, search, verify


class TranslationCorpusTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        directory = self.root / 'catalogs/quests'
        directory.mkdir(parents=True)
        (directory / 'metadata.json').write_text(dump_json({'document': {'locales': ['enUS', 'frFR', 'svSE']}}))
        self.entity = directory / '1.json'
        self.entity.write_text(dump_json({'locales': {
            'enUS': self.localized('A sword', 'original', 'blizzard', 'enUS'),
            'frFR': self.localized('Une épée', 'original', 'blizzard', 'frFR'),
            'svSE': self.localized('Ett svärd', 'ai', 'varldenAvKrigskraft', 'enUS'),
        }}))
        self.config = self.root / 'sources.json'
        self.config.write_text('{}')
        self.output = self.root / 'datasources/imports/corpus.sqlite'

    def localized(self, text, origin, source, locale):
        return {'title': text, 'translationMetadata': {'fields': {'title': {
            'origin': origin, 'source': source, 'sourceLocale': locale,
        }}}}

    def database(self):
        build(self.root, self.config, self.output)
        connection = open_corpus(self.output)
        self.addCleanup(connection.close)

        return connection

    def test_build_preserves_catalogs_and_never_promotes_claims(self):
        before = self.entity.read_bytes()
        db = self.database()
        self.assertEqual(self.entity.read_bytes(), before)
        rows = db.execute('SELECT evidence,origin FROM records').fetchall()
        self.assertEqual({row[0] for row in rows}, {'catalogClaim'})
        self.assertIn('ai', {row[1] for row in rows})
        self.assertTrue(verify(db, self.root)['valid'])
        with self.assertRaises(sqlite3.OperationalError):
            db.execute('DELETE FROM records')

    def test_corpus_stores_and_exposes_only_one_english(self):
        document = json.loads(self.entity.read_text())
        document['locales']['enGB'] = document['locales']['enUS']
        self.entity.write_text(dump_json(document))
        metadata = self.root / 'catalogs/quests/metadata.json'
        metadata.write_text(dump_json({'document': {'locales': ['enUS', 'enGB', 'frFR', 'svSE']}}))
        db = self.database()
        self.assertEqual(db.execute("SELECT COUNT(*) FROM records WHERE locale='enGB'").fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT COUNT(*) FROM records WHERE locale='enUS'").fetchone()[0], 1)
        with self.assertRaisesRegex(ValueError, 'not supported'):
            search(db, 'enGB', 'sword')
        with self.assertRaisesRegex(ValueError, 'not supported'):
            packet(db, self.root, 'quests', '1', ['enGB', 'enUS'])

    def test_excludes_locally_authored_ai_from_reference_evidence(self):
        document = json.loads(self.entity.read_text())
        document['locales']['frFR'] = self.localized('Une épée', 'ai', 'ForeverRosettaStoneAI', 'enUS')
        self.entity.write_text(dump_json(document))
        db = self.database()
        self.assertEqual(db.execute("SELECT count(*) FROM records WHERE locale='frFR'").fetchone()[0], 0)
        self.assertEqual(packet(db, self.root, 'quests', '1', ['frFR'])['entity'], document)

    def test_locally_authored_english_never_becomes_reference_pair(self):
        document = json.loads(self.entity.read_text())
        document['locales']['enUS'] = self.localized('A generated sword', 'ai', 'ForeverRosettaStoneAI', 'frFR')
        self.entity.write_text(dump_json(document))
        db = self.database()
        self.assertEqual(db.execute("SELECT count(*) FROM records WHERE text=? OR english=?",
                                    ('A generated sword', 'A generated sword')).fetchone()[0], 0)
        row = db.execute("SELECT text,english,origin,provenance FROM records WHERE locale='frFR'").fetchone()
        self.assertEqual(tuple(row[:3]), ('Une épée', None, 'original'))
        self.assertEqual(json.loads(row['provenance'])['source'], 'blizzard')
        self.assertEqual(packet(db, self.root, 'quests', '1', ['frFR'])['entity'], document)

    def test_independent_original_english_still_pairs_after_ai_english_excluded(self):
        document = json.loads(self.entity.read_text())
        document['locales']['enUS'] = self.localized('A generated sword', 'ai', 'ForeverRosettaStoneAI', 'frFR')
        self.entity.write_text(dump_json(document))
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        builder.catalogs(kinds=['quests'])
        builder.add('quests', '1', 'enUS', 'title', 'Verified sword', None, 'original', 'sourceSnapshot', {}, self.entity)
        builder.finish()
        self.assertEqual(db.execute("SELECT english FROM records WHERE locale='frFR'").fetchone()[0], 'Verified sword')

    def test_community_ai_english_retains_existing_reference_policy(self):
        document = json.loads(self.entity.read_text())
        document['locales']['enUS'] = self.localized('Community sword', 'ai', 'polishForever', 'plPL')
        self.entity.write_text(dump_json(document))
        db = self.database()
        row = db.execute("SELECT text,origin,provenance FROM records WHERE locale='enUS'").fetchone()
        self.assertEqual((row['text'], row['origin'], json.loads(row['provenance'])['source']),
                         ('Community sword', 'ai', 'polishForever'))
        self.assertEqual(db.execute("SELECT english FROM records WHERE locale='frFR'").fetchone()[0], 'Community sword')

    def test_search_accepts_literal_punctuation_and_limits_results(self):
        db = self.database()
        rows = search(db, 'frFR', 'épée " OR * :', limit=1)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['text'], 'Une épée')
        self.assertEqual(search(db, 'frFR', '"*:'), [])

    def test_changed_entity_is_rejected_and_verify_reports_drift(self):
        db = self.database()
        self.entity.write_text(self.entity.read_text() + '\n')
        self.assertFalse(verify(db, self.root)['valid'])
        with self.assertRaisesRegex(ValueError, 'changed since corpus build'):
            packet(db, self.root, 'quests', '1', ['frFR'])

    def test_wrong_language_and_fallback_candidates_are_visible_but_not_examples(self):
        document = json.loads(self.entity.read_text())
        prose = 'Une longue description française qui contient plus de huit mots pour vérifier les langues.'
        document['locales']['frFR']['description'] = prose
        document['locales']['svSE']['description'] = prose
        for locale in ('frFR', 'svSE'):
            document['locales'][locale]['translationMetadata']['fields']['description'] = {
                'origin': 'original', 'source': 'blizzard', 'sourceLocale': locale,
            }
        document['locales']['frFR']['title'] = 'A sword'
        self.entity.write_text(dump_json(document))
        db = self.database()
        self.assertEqual(search(db, 'svSE', prose), [])
        result = packet(db, self.root, 'quests', '1', ['frFR'])
        candidates = result['languages']['frFR']['exactCandidates']
        self.assertTrue(all(row['flags'] for row in candidates))

    def test_cached_wago_checksums_and_multiline_templates(self):
        directory = self.root / 'wago'
        directory.mkdir()
        path = directory / 'Spell.csv'
        with path.open('w', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['ID', 'Description_lang', 'AuraDescription_lang', 'NameSubtext_lang'])
            writer.writerow(['7', 'First line\nSecond $s1 line', '', ''])
        manifest = {'build': '1.60.1.70888', 'results': [{
            'table': 'Spell', 'locale': 'enUS', 'status': 'existing', 'file': 'Spell.csv',
            'url': 'https://example.test', 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        }]}
        (directory / 'manifest.json').write_text(dump_json(manifest))
        self.config.write_text(dump_json({'wago': ['wago']}))
        db = self.database()
        self.assertEqual(db.execute("SELECT text FROM records WHERE kind='spells'").fetchone()[0],
                         'First line\nSecond $s1 line')

    def test_bad_source_checksum_does_not_leave_a_usable_corpus(self):
        directory = self.root / 'wago'
        directory.mkdir()
        (directory / 'Spell.csv').write_text('broken')
        (directory / 'manifest.json').write_text(dump_json({'build': '1.60.1.70888', 'results': [{
            'table': 'Spell', 'locale': 'enUS', 'status': 'downloaded', 'file': 'Spell.csv',
            'url': 'https://example.test', 'sha256': 'wrong',
        }]}))
        self.config.write_text(dump_json({'wago': ['wago']}))
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            build(self.root, self.config, self.output)
        self.assertFalse(self.output.exists())

    def test_item_subtitles_join_by_reference_and_fill_localized_fields(self):
        directory = self.root / 'wago'
        directory.mkdir()
        exports = []

        for locale, name, subtitle in (('enUS', 'Sword', 'Season of Discovery'),
                                       ('frFR', 'Épée', 'Saison de la découverte')):
            for table, content in (
                ('ItemSparse', 'ID,Display_lang,Description_lang,ItemNameDescriptionID\n'
                 f'7,{name},,42\n8,Other,,999\n'),
                ('ItemNameDescription', f'ID,Description_lang\n42,{subtitle}\n'),
            ):
                path = directory / f'{table}.{locale}.csv'
                path.write_text(content)
                exports.append({'table': table, 'locale': locale, 'status': 'downloaded', 'file': path.name,
                                'url': 'https://example.test/' + table,
                                'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})

        (directory / 'manifest.json').write_text(dump_json({'build': '1.60.1.70888', 'results': exports}))
        self.config.write_text(dump_json({'wago': ['wago']}))
        db = self.database()
        rows = db.execute("SELECT * FROM records WHERE field='nameDescription' ORDER BY locale").fetchall()
        self.assertEqual([(row['entity_id'], row['locale'], row['text']) for row in rows], [
            ('7', 'enUS', 'Season of Discovery'), ('7', 'frFR', 'Saison de la découverte'),
        ])
        self.assertEqual(rows[1]['english'], 'Season of Discovery')
        self.assertIn('ItemNameDescription.frFR.csv', rows[1]['source_path'])
        self.assertEqual(json.loads(rows[1]['provenance'])['itemNameDescriptionId'], '42')
        fill = runpy.run_path(str(ROOT / 'tools/catalogs/fill-official-text.py'))
        entity = {'locales': {'enUS': {'nameDescription': 'Season of Discovery'}}}
        after, counts = fill['update_entity'](entity, [dict(rows[1])])
        self.assertEqual(after['locales']['frFR']['nameDescription'], 'Saison de la découverte')
        self.assertEqual(counts['filled'], 1)

    def test_existing_corpus_and_nonreference_output_are_rejected(self):
        self.database()
        with self.assertRaisesRegex(ValueError, 'already exists'):
            build(self.root, self.config, self.output)
        with self.assertRaisesRegex(ValueError, 'under ignored datasources/imports'):
            build(self.root, self.config, self.entity)

    def test_verify_detects_added_catalog_entries(self):
        db = self.database()
        added = self.entity.with_name('2.json')
        added.write_bytes(self.entity.read_bytes())
        self.assertEqual(verify(db, self.root)['changedInputs'], ['catalogs/quests/2.json'])

    def test_eg_link_quest_inputs_are_rejected(self):
        path = self.root / 'quests.json'
        path.write_text(dump_json({'meta': {
            'product': 'wowf', 'dataset': 'quests', 'schemaVersion': 1, 'locale': 'enUS',
            'clientBuild': '1.60.1.70888', 'license': 'CC BY 4.0', 'attribution': 'Efficient Games',
        }, 'quests': {'1': {'title': 'Quest', 'objectivesText': 'Find the sword'}}}))
        self.config.write_text(dump_json({'egLink': [{'path': 'quests.json', 'revision': 'a' * 40}]}))
        with self.assertRaisesRegex(ValueError, 'supported Forever cache'):
            self.database()

    def blizzard_fixture(self):
        directory = self.root / 'datasources/imports/blizzard'
        path = directory / 'quest/1.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(dump_json({'id': 1, 'title': {'en_US': 'Quest', 'fr_FR': 'Quête'},
                                   'description': {'en_US': 'English prose', 'fr_FR': 'English prose',
                                                   'it_IT': 'Wrong Italian slot'}}))
        manifest = {'state': 'complete', 'resolved_namespace': 'static-1.60.1_70399-forever-eu',
                    'resources': {'/data/wow/quest/1': {'path': 'quest/1.json',
                        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'url': 'https://eu.api.blizzard.com/data/wow/quest/1'}}}
        (directory / 'manifest.json').write_text(dump_json(manifest))
        self.config.write_text(dump_json({'blizzard': [{'path': 'datasources/imports/blizzard'}]}))

        return directory

    def test_blizzard_imports_only_titles_and_descriptions_and_flags_fallback(self):
        self.blizzard_fixture()
        db = self.database()
        rows = db.execute("SELECT locale,field,flags,provenance FROM records WHERE evidence='sourceSnapshot'").fetchall()
        self.assertEqual({row['field'] for row in rows}, {'title', 'description'})
        self.assertEqual({row['locale'] for row in rows}, {'enUS', 'frFR'})
        fallback = next(row for row in rows if row['locale'] == 'frFR' and row['field'] == 'description')
        self.assertIn('equalsEnglish:inspectBeforeReuse', json.loads(fallback['flags']))
        self.assertEqual(json.loads(fallback['provenance'])['source'], 'blizzard')
        self.assertTrue(verify(db, self.root)['valid'])

    def test_blizzard_checksum_and_partial_collections_are_rejected(self):
        directory = self.blizzard_fixture()
        (directory / 'quest/1.json').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.database()
        self.assertFalse(self.output.exists())
        directory = self.blizzard_fixture()
        manifest_path = directory / 'manifest.json'
        manifest = json.loads(manifest_path.read_text())
        manifest['state'] = 'fetching'
        manifest_path.write_text(dump_json(manifest))
        with self.assertRaisesRegex(ValueError, 'complete Forever'):
            self.database()

    @unittest.skipUnless(importlib.util.find_spec('lupa'), 'Run with pinned Lupa for Questie adapter checks')
    def test_questie_reads_data_without_executing_loader_and_preserves_ambiguous_summary(self):
        directory = self.root / 'questie/l10n/Forever/lookupQuests'
        directory.mkdir(parents=True)
        path = directory / 'frFR.lua'
        path.write_text('error("Loader must never run")\n'
                        'local rows = loadstring([[return {[1]={"Titre", {"Un", "Deux"}},'
                        '[2]={"Autre", {"Résumé"}}}]])\n')
        self.config.write_text(dump_json({'questie': [{'path': 'questie', 'revision': 'b' * 40}]}))
        db = self.database()
        rows = db.execute("SELECT entity_id,field FROM records WHERE evidence='sourceSnapshot'").fetchall()
        self.assertEqual({tuple(row) for row in rows}, {('1', 'title'), ('2', 'title'), ('2', 'summary')})

    def test_conflicting_english_sources_do_not_produce_a_false_pair(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        for locale, text in (('enUS', 'One'), ('enUS', 'Two'), ('frFR', 'Un')):
            builder.add('quests', '1', locale, 'title', text, None, 'original', 'sourceSnapshot', {}, self.entity)
        builder.finish()
        self.assertIsNone(db.execute("SELECT english FROM records WHERE locale='frFR'").fetchone()[0])

    def test_quest_variables_normalize_without_touching_formulas_or_other_kinds(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        raw = '$N $n $C $c $R $r $B$bParagraph $1oa $s1 $123 $ghe:she; $Ghis:her; $name $class $race'
        expected = '{name} {name} {class} {class} {race} {race} \n\nParagraph $1oa $s1 $123 $ghe:she; $Ghis:her; $name $class $race'
        for kind in ('quests', 'items', 'spells'):
            builder.add(kind, '1', 'frFR', 'description', raw, raw, 'original', 'sourceSnapshot', {}, self.entity)
        rows = dict((kind, (text, english)) for kind, text, english in db.execute('SELECT kind,text,english FROM records'))
        self.assertEqual(rows['quests'], (expected, expected))
        self.assertEqual(rows['items'], (raw, raw))
        self.assertEqual(rows['spells'], (raw, raw))

    def test_quest_pipe_linebreak_preserves_markup_and_source_metadata(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        raw = '|cffff0000Red|r|n|Hitem:1|h[Item]|h |Ticon:12|t ||n'
        expected = '|cffff0000Red|r\n|Hitem:1|h[Item]|h |Ticon:12|t ||n'
        provenance = {'source': 'questie', 'sourceLocale': 'esES', 'sourceRevision': 'revision'}
        for kind in ('quests', 'items', 'spells'):
            builder.add(kind, '1', 'esES', 'summary', raw, raw, 'community', 'sourceSnapshot',
                        provenance, self.entity)
        rows = {kind: (text, english, json.loads(metadata)) for kind, text, english, metadata
                in db.execute('SELECT kind,text,english,provenance FROM records')}
        self.assertEqual(rows['quests'], (expected, expected, provenance))
        for kind in ('items', 'spells'):
            self.assertEqual(rows[kind], (raw, raw, provenance))
        comparable = runpy.run_path(str(ROOT / 'tools/catalogs/plan-update.py'))['comparable']
        self.assertEqual(comparable('quests', 'First|nSecond'), comparable('quests', 'First\nSecond'))
        self.assertEqual(comparable('spells', 'First|nSecond'), 'First|nSecond')

    def test_quest_fallback_and_collisions_use_normalized_text(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        english = 'Welcome $n to this long story with many words for you.'
        normalized = 'Welcome {name} to this long story with many words for you.'
        for locale, text, context, flags in (
            ('enUS', english, None, ()),
            ('frFR', normalized, english, ('sourceLocaleDiffers:inspectBeforeReuse',)),
            ('svSE', english, None, ()),
        ):
            builder.add('quests', '1', locale, 'description', text, context, 'original', 'sourceSnapshot', {}, self.entity, flags)
        builder.finish()
        for locale, text, paired, raw_flags in db.execute("SELECT locale,text,english,flags FROM records WHERE locale!='enUS'"):
            self.assertEqual((text, paired), (normalized, normalized))
            flags = json.loads(raw_flags)
            self.assertIn('equalsEnglish:inspectBeforeReuse', flags)
            self.assertTrue(any(flag.startswith('sharedProseAcrossLanguages:') for flag in flags))
            if locale == 'frFR':
                self.assertIn('sourceLocaleDiffers:inspectBeforeReuse', flags)

    def test_packet_matches_normalized_quest_source(self):
        document = json.loads(self.entity.read_text())
        document['locales']['enUS']['title'] = 'Welcome $n'
        self.entity.write_text(dump_json(document))
        other = {'locales': {
            'enUS': self.localized('Welcome {name}', 'original', 'blizzard', 'enUS'),
            'frFR': self.localized('Bienvenue {name}', 'original', 'blizzard', 'frFR'),
        }}
        (self.entity.parent / '2.json').write_text(dump_json(other))
        db = self.database()
        field = packet(db, self.root, 'quests', '1', ['frFR'])['languages']['frFR']['fields']['title']
        self.assertEqual(field['source'], 'Welcome {name}')
        self.assertEqual([row['text'] for row in field['sameTextCandidates']], ['Bienvenue {name}'])

    def test_packet_requested_fields_filter_only_references(self):
        document = json.loads(self.entity.read_text())
        for locale, value in (('enUS', 'A sword for battle'), ('frFR', 'Une épée pour le combat')):
            document['locales'][locale]['description'] = value
            document['locales'][locale]['translationMetadata']['fields']['description'] = {
                'origin': 'original', 'source': 'blizzard', 'sourceLocale': locale,
            }
        document['areaId'] = 77
        self.entity.write_text(dump_json(document))
        other = {'locales': {
            'enUS': self.localized('Another sword', 'original', 'blizzard', 'enUS'),
            'frFR': self.localized('Une autre épée', 'original', 'blizzard', 'frFR'),
        }}
        for locale, value in (('enUS', 'A sword for battle'), ('frFR', 'Une épée de bataille')):
            other['locales'][locale]['description'] = value
            other['locales'][locale]['translationMetadata']['fields']['description'] = {
                'origin': 'original', 'source': 'blizzard', 'sourceLocale': locale,
            }
        (self.entity.parent / '2.json').write_text(dump_json(other))
        db = self.database()
        default = packet(db, self.root, 'quests', '1', ['frFR'])
        self.assertEqual(default, packet(db, self.root, 'quests', '1', ['frFR'], fields=None))
        self.assertEqual(set(default['languages']['frFR']['fields']), {'title', 'description'})
        with patch('datasources.corpus.translation_corpus.search', wraps=search) as searched:
            scoped = packet(db, self.root, 'quests', '1', ['frFR'], fields=['description'])
        self.assertEqual(scoped['entity'], document)
        self.assertEqual(scoped['entitySha256'], default['entitySha256'])
        self.assertEqual(scoped['corpusFingerprint'], default['corpusFingerprint'])
        self.assertEqual(scoped['relatedNames'], default['relatedNames'])
        self.assertEqual(set(scoped['languages']['frFR']['fields']), {'description'})
        self.assertEqual({row['field'] for row in scoped['languages']['frFR']['exactCandidates']}, {'description'})
        self.assertEqual(scoped['languages']['frFR']['fields']['description'], default['languages']['frFR']['fields']['description'])
        self.assertEqual([row['text'] for row in scoped['languages']['frFR']['fields']['description']['sameTextCandidates']],
                         ['Une épée de bataille'])
        self.assertEqual([call.args[-1] for call in searched.call_args_list], ['description'])
        for invalid in (['tooltip.description'], ['objectiveLines.0'], ['description; DROP TABLE records'], []):
            with self.assertRaises(ValueError):
                packet(db, self.root, 'quests', '1', ['frFR'], fields=invalid)

    def test_packet_cli_accepts_field_scope_and_rejects_unknown_field(self):
        self.database()
        command = [sys.executable, str(ROOT / 'datasources/corpus/translation_corpus.py'),
                   '--root', str(self.root), 'packet', '--database', str(self.output),
                   '--kind', 'quests', '--id', '1', '--locale', 'frFR', '--field']
        valid = subprocess.run([*command, 'title'], capture_output=True, text=True, check=True)
        self.assertEqual(set(json.loads(valid.stdout)['languages']['frFR']['fields']), {'title'})
        invalid = subprocess.run([*command, 'tooltip.description'], capture_output=True, text=True)
        self.assertNotEqual(invalid.returncode, 0)
        self.assertIn('Invalid packet field scope', invalid.stderr)

    def test_community_quest_markup_and_unsafe_constructs(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        cases = [
            ('wowitaQuests', '<nome> <Class> <race> {nombre} <smiles>', '{name} {class} {race} {name} <smiles>', None),
            ('wowLang', 'YOUR_NAME NEW_LINENEW_LINEYOUR_CLASS $g$N:amica; $Bparola $b$bprose', '{name} \n\n{class} $g{name}:amica; \nparola \n\nprose', None),
            ('questTranslatorTR', 'YOUR_CLASSnin', '{class}nin', 'unsupportedQuestMarkup:turkishInflection'),
            ('foreverTR', "@<Crab Cake> {Orc|'u|a}", "@<Crab Cake> {Orc|'u|a}", 'unsupportedQuestMarkup:turkishEntity'),
            ('varldenAvKrigskraft', 'Samla #/#', 'Samla #/#', 'unsupportedQuestMarkup:objectiveProgress'),
            ('wowitaQuests', '<gender:uno|una>', '<gender:uno|una>', 'unsupportedQuestMarkup:italianGender'),
            ('wowForeverIT', '$Psicuro:sicura;', '$Psicuro:sicura;', 'unsupportedQuestMarkup:italianGender'),
            ('foreverTranslatedPolish', '[[Sword|Miecz]]', '[[Sword|Miecz]]', 'unsupportedQuestMarkup:polishLink'),
            ('classicUA', "{ім'я} {клас:к}", '{name} {клас:к}', 'unsupportedQuestMarkup:ukrainianGrammar'),
            ('wowLang', 'YOUR_GENDER(on;ona) $O(place;miejsce)', 'YOUR_GENDER(on;ona) $O(place;miejsce)', 'unsupportedQuestMarkup:communitySelector'),
        ]
        for i, (source, raw, expected, flag) in enumerate(cases):
            builder.add('quests', str(i + 1), 'frFR', 'description', raw, None, 'community', 'sourceSnapshot', {'source': source}, self.entity)
            text, raw_flags = db.execute('SELECT text,flags FROM records WHERE entity_id=?', (str(i + 1),)).fetchone()
            self.assertEqual(text, expected, source)
            if flag:
                self.assertIn(flag, json.loads(raw_flags), source)
            else:
                self.assertEqual(json.loads(raw_flags), [], source)

    def test_community_indexes_use_raw_english_lookup_keys(self):
        from datasources.github_community import polish_hash
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.row_factory = sqlite3.Row
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        raw = 'Hello $N'
        builder.add('quests', '1', 'enUS', 'description', raw, None, 'original', 'sourceSnapshot', {}, self.entity)
        self.assertEqual(db.execute('SELECT text FROM records').fetchone()[0], 'Hello {name}')
        for algorithm, key in (('exact', raw), ('polish-hash', polish_hash(raw))):
            index = builder.community_lookup_index(('quests',), ('description',), algorithm)
            self.assertEqual(index[key][0]['text'], raw)

    def test_unhandled_quest_dollar_markers_are_flagged_after_normalization(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        for i, raw in enumerate(('$name', '$bprose', 'G$meu:minha;', '$fourrures', '$Uo', '$Forastero:Forastero;', '$gmalformed;')):
            builder.add('quests', str(i + 1), 'frFR', 'description', raw, None, 'original', 'sourceSnapshot', {}, self.entity)
            flags = json.loads(db.execute('SELECT flags FROM records WHERE entity_id=?', (str(i + 1),)).fetchone()[0])
            self.assertIn('unsupportedQuestMarkup:dollarToken', flags)
        builder.add('quests', '8', 'frFR', 'description', '$1oa개 $g$N:amie; $Bprose', None, 'original', 'sourceSnapshot', {}, self.entity)
        self.assertEqual(json.loads(db.execute("SELECT flags FROM records WHERE entity_id='8'").fetchone()[0]), [])
        builder.add('spells', '9', 'frFR', 'description', '$s1 $Uo', None, 'original', 'sourceSnapshot', {}, self.entity)
        self.assertEqual(db.execute("SELECT text,flags FROM records WHERE entity_id='9'").fetchone(), ('$s1 $Uo', '[]'))

    def test_heading_only_quest_summary_is_retained_but_excluded_from_fill(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.row_factory = sqlite3.Row
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        cases = [
            ('quests', '1', 'summary', 'Requisitos:  ', True),
            ('quests', '6', 'summary', 'Requirements:', True),
            ('quests', '7', 'summary', 'Conditions:', True),
            ('quests', '2', 'summary', 'Requisitos:\nTrae el objeto.', False),
            ('quests', '8', 'summary', 'Requirements:\r\nBring the item.', False),
            ('quests', '3', 'summary', 'Requisitos: trae el objeto.', False),
            ('quests', '4', 'title', 'Requisitos:', False),
            ('items', '5', 'name', 'Requisitos:', False),
        ]
        for kind, entity_id, field, text, flagged in cases:
            builder.add(kind, entity_id, 'esMX', field, text, None, 'community', 'sourceSnapshot',
                        {'source': 'questie'}, self.entity)
            row = db.execute('SELECT text,flags FROM records WHERE kind=? AND entity_id=?',
                             (kind, entity_id)).fetchone()
            self.assertEqual(row['text'], text)
            self.assertEqual('headingOnlySummary' in json.loads(row['flags']), flagged)
        source_rows = runpy.run_path(str(ROOT / 'tools/catalogs/fill-official-text.py'))['source_rows']
        allowed = list(source_rows(db))
        self.assertNotIn(('quests', '1'), [(row['kind'], row['entity_id']) for row in allowed])
        self.assertEqual(len(allowed), 5)

    def test_fresh_english_snapshot_pairs_before_stale_catalog_claim(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        for locale, text, evidence in (('enUS', 'Old', 'catalogClaim'),
                                       ('enUS', 'Current', 'sourceSnapshot'), ('frFR', 'Actuel', 'sourceSnapshot')):
            builder.add('quests', '1', locale, 'title', text, None, 'original', evidence, {}, self.entity)

        builder.finish()
        self.assertEqual(db.execute("SELECT english FROM records WHERE locale='frFR'").fetchone()[0], 'Current')

    def test_verified_community_english_pairs_before_catalog_claims_but_not_native_snapshots(self):
        for native in (None, 'Native English'):
            db = sqlite3.connect(':memory:')
            self.addCleanup(db.close)
            db.executescript(SCHEMA)
            builder = CorpusBuilder(self.root, db)
            for locale, text, origin, evidence in (
                    ('enUS', 'Stale catalog', 'original', 'catalogClaim'),
                    ('enUS', 'Questie English', 'community', 'sourceSnapshot'),
                    ('frFR', 'Résumé français', 'community', 'sourceSnapshot')):
                builder.add('quests', '1', locale, 'summary', text, None, origin, evidence, {}, self.entity)
            if native:
                builder.add('quests', '1', 'enUS', 'summary', native, None, 'original', 'sourceSnapshot', {}, self.entity)
            builder.finish()
            self.assertEqual(db.execute("SELECT english FROM records WHERE locale='frFR'").fetchone()[0], native or 'Questie English')

    def test_conflicting_community_english_and_ai_do_not_create_a_pair(self):
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        for locale, text, origin in (('enUS', 'One', 'community'), ('enUS', 'Two', 'community'),
                                     ('enUS', 'Authored', 'ai'), ('frFR', 'Un', 'community')):
            builder.add('quests', '1', locale, 'summary', text, None, origin, 'sourceSnapshot', {}, self.entity)
        builder.finish()
        self.assertIsNone(db.execute("SELECT english FROM records WHERE locale='frFR'").fetchone()[0])

    @unittest.skipUnless(importlib.util.find_spec('lupa'), 'Run with pinned Lupa for composed source checks')
    def test_questie_paragraph_summaries_keep_exact_english_context(self):
        directory = self.root / 'questie/src/corrections/Forever/combined'
        directory.mkdir(parents=True)
        (directory / 'foreverQuestDB.lua').write_text('local q={};q[7]={"Quest",nil,nil,nil,nil,nil,nil,{"First paragraph.","","Second paragraph."}};return q')
        lookup = self.root / 'questie/l10n/Forever/lookupQuests'
        lookup.mkdir(parents=True)
        (lookup / 'frFR.lua').write_text('local t=loadstring([[return {[7]={"Quête",{"Premier paragraphe.","","Deuxième paragraphe."}}}]])')
        self.config.write_text(dump_json({'questie': [{'path': 'questie', 'revision': 'pinned'}]}))
        db = self.database()
        row = db.execute("SELECT text,english FROM records WHERE locale='frFR' AND field='summary'").fetchone()
        self.assertEqual(tuple(row), ('Premier paragraphe.\n\nDeuxième paragraphe.', 'First paragraph.\n\nSecond paragraph.'))

    def test_eg_link_imports_npc_names_and_only_valid_item_text(self):
        entries = []
        for dataset, key, rows in (
            ('creature_details', 'creatures', {'7': {'name': 'Wolf'}}),
            ('item_hotfixes', 'items', {'8': {'status': 'valid', 'name': 'Sword', 'description': 'Sharp'},
                                      '9': {'status': 'removed', 'name': 'Removed'}}),
        ):
            path = self.root / (dataset + '.json')
            path.write_text(dump_json({'meta': {
                'product': 'wowf', 'dataset': dataset, 'schemaVersion': 1, 'locale': 'enUS',
                'clientBuild': '1.60.1.70888', 'license': 'CC BY 4.0', 'attribution': 'Efficient Games',
            }, key: rows}))
            entries.append({'path': path.name, 'revision': 'pinned'})

        self.config.write_text(dump_json({'egLink': entries}))
        db = self.database()
        rows = db.execute("SELECT kind,entity_id,field,text FROM records WHERE evidence='sourceSnapshot'").fetchall()
        self.assertEqual({tuple(row) for row in rows}, {
            ('npcs', '7', 'name', 'Wolf'), ('items', '8', 'name', 'Sword'),
            ('items', '8', 'description', 'Sharp'),
        })

    @unittest.skipUnless(importlib.util.find_spec('lupa'), 'Run with pinned Lupa for trace adapter checks')
    def test_quest_traces_override_but_item_variants_remain_unverified(self):
        for lookup, base, trace in (
            ('lookupQuests', '{[1]={"Base", {"Résumé"}},[2]={"Deux", {"Résumé"}}}',
             '{[1]={"Titre", nil},[2]={nil,{"Un","Deux"}}}'),
            ('lookupItems', '{[7]="Ancien",[9]="Identique"}', '{[7]="Nouveau",[8]="Ajout",[9]="Identique"}'),
        ):
            for layer, literal in (('', base), ('traces/', trace)):
                path = self.root / ('questie/l10n/Forever/' + layer + lookup + '/frFR.lua')
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('error("Loader must not run")\nlocal rows=loadstring([[return ' + literal + ']])')

        self.config.write_text(dump_json({'questie': [{'path': 'questie', 'revision': 'pinned'}]}))
        db = self.database()
        rows = db.execute("SELECT kind,entity_id,field,text FROM records WHERE evidence='sourceSnapshot'").fetchall()
        self.assertEqual({tuple(row) for row in rows}, {
            ('quests', '1', 'title', 'Titre'), ('quests', '1', 'summary', 'Résumé'),
            ('quests', '2', 'title', 'Deux'), ('items', '7', 'name', 'Ancien'), ('items', '7', 'name', 'Nouveau'),
            ('items', '8', 'name', 'Ajout'), ('items', '9', 'name', 'Identique'),
        })
        observed = db.execute("SELECT text,flags FROM records WHERE kind='items' AND text IN ('Nouveau','Ajout')").fetchall()
        self.assertTrue(all('unverifiedItemNameTrace' in json.loads(row['flags']) for row in observed))
        self.assertEqual(search(db, 'frFR', 'Nouveau'), [])
        self.assertEqual(db.execute("SELECT COUNT(*) FROM records WHERE kind='items' AND entity_id='9'").fetchone()[0], 1)

    @unittest.skipUnless(importlib.util.find_spec('lupa'), 'Run with pinned Lupa for NPC adapter checks')
    def test_npc_names_use_first_slot_and_trace_name_override(self):
        directory = self.root / 'questie'
        lookup = directory / 'l10n/Forever/lookupNpcs'
        trace = directory / 'l10n/Forever/traces/lookupNpcs'
        combined = directory / 'src/corrections/Forever/combined'
        for path in (lookup, trace, combined):
            path.mkdir(parents=True)
        (combined / 'foreverNpcDB.lua').write_text('return {[7]={"Wolf"},[8]={"Owl"}}')
        (lookup / 'frFR.lua').write_text('local t=loadstring([[return {[7]={"Base",nil},[8]={nil,"Title"}}]])')
        (trace / 'frFR.lua').write_text('local t=loadstring([[return {[7]={"Loup",nil}}]])')
        self.config.write_text(dump_json({'questie': [{'path': 'questie', 'revision': 'pinned'}]}))
        db = self.database()
        rows = db.execute("SELECT * FROM records WHERE kind='npcs' AND locale='frFR'").fetchall()
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0]['entity_id'], rows[0]['text'], rows[0]['english']), ('7', 'Loup', 'Wolf'))
        self.assertEqual(rows[0]['origin'], 'community')
        self.assertIn('/traces/', rows[0]['source_path'])

    @unittest.skipUnless(importlib.util.find_spec('lupa'), 'Run with pinned Lupa for NPC adapter checks')
    def test_npc_subnames_pair_with_english_subname_and_merge_traces_per_field(self):
        directory = self.root / 'questie'
        lookup = directory / 'l10n/Forever/lookupNpcs'
        trace = directory / 'l10n/Forever/traces/lookupNpcs'
        combined = directory / 'src/corrections/Forever/combined'
        for path in (lookup, trace, combined):
            path.mkdir(parents=True)
        padding = ',nil' * 12
        (combined / 'foreverNpcDB.lua').write_text(
            'return {[7]={"Wolf"' + padding + ',"Trainer"},[8]={"Owl"},[9]={"Cat"' + padding + ',"Vendor"}}')
        (lookup / 'frFR.lua').write_text(
            'local t=loadstring([[return {[7]={"Loup","Base"},[8]={"Hibou","Orphan"},[9]={"Chat","Marchand"}}]])')
        (trace / 'frFR.lua').write_text('local t=loadstring([[return {[7]={"Loup","Maître"},[9]={"Chat",nil}}]])')
        self.config.write_text(dump_json({'questie': [{'path': 'questie', 'revision': 'pinned'}]}))
        db = self.database()
        rows = {(row['entity_id'], row['locale'], row['text'], row['english']) for row in db.execute(
            "SELECT * FROM records WHERE kind='npcs' AND field='subName'")}
        self.assertEqual(rows, {('7', 'enUS', 'Trainer', 'Trainer'), ('9', 'enUS', 'Vendor', 'Vendor'),
                                ('7', 'frFR', 'Maître', 'Trainer'), ('9', 'frFR', 'Marchand', 'Vendor')})

    @unittest.skipUnless(importlib.util.find_spec('lupa'), 'Run with pinned Lupa for composed source checks')
    def test_composed_english_quest_and_item_text_supplies_real_source_context(self):
        directory = self.root / 'questie/src/corrections/Forever/combined'
        directory.mkdir(parents=True)
        (directory / 'foreverQuestDB.lua').write_text('local q={};q[7]={"Quest",nil,nil,nil,nil,nil,nil,{"Goal"}};return q')
        (directory / 'foreverItemDB.lua').write_text('local i={};i[8]={"Item"};return i')
        lookup = self.root / 'questie/l10n/Forever/lookupQuests'
        lookup.mkdir(parents=True)
        (lookup / 'frFR.lua').write_text('local t=loadstring([[return {[7]={"Quête",{"Objectif"}}}]])')
        self.config.write_text(dump_json({'questie': [{'path': 'questie', 'revision': 'pinned'}]}))
        db = self.database()
        rows = db.execute("SELECT kind,entity_id,locale,field,text,english FROM records WHERE evidence='sourceSnapshot'").fetchall()
        self.assertIn(('quests', '7', 'enUS', 'summary', 'Goal', 'Goal'), {tuple(row) for row in rows})
        self.assertIn(('items', '8', 'enUS', 'name', 'Item', 'Item'), {tuple(row) for row in rows})
        self.assertIn(('quests', '7', 'frFR', 'summary', 'Objectif', 'Goal'), {tuple(row) for row in rows})

    def test_talent_names_join_verified_rank_spell_in_separate_id_namespace(self):
        directory = self.root / 'wago'
        directory.mkdir()
        talent_file = directory / 'Talent.csv'
        talent_file.write_text('ID,SpellRank_0,SpellID\n9,700,0\n10,701,0\n11,0,702\n')
        name_file = directory / 'SpellName.csv'
        name_file.write_text('ID,Name_lang\n700,Nom natif\n702,Nom direct\n')
        manifest = {'build': '1.60.1.70888', 'results': [{
            'table': 'Talent', 'locale': 'enUS', 'status': 'existing', 'file': 'Talent.csv',
            'sha256': hashlib.sha256(talent_file.read_bytes()).hexdigest(),
        }, {
            'table': 'SpellName', 'locale': 'frFR', 'status': 'existing', 'file': 'SpellName.csv',
            'sha256': hashlib.sha256(name_file.read_bytes()).hexdigest(),
        }]}
        (directory / 'manifest.json').write_text(dump_json(manifest))
        talents = self.root / 'catalogs/talents'
        talents.mkdir()
        (talents / '9.json').write_text(dump_json({'spellId': 700, 'locales': {}}))
        (talents / '10.json').write_text(dump_json({'spellId': 999, 'locales': {}}))
        (talents / '11.json').write_text(dump_json({'spellId': 702, 'locales': {}}))
        db = sqlite3.connect(':memory:')
        self.addCleanup(db.close)
        db.row_factory = sqlite3.Row
        db.executescript(SCHEMA)
        builder = CorpusBuilder(self.root, db)
        builder.add('spells', '700', 'frFR', 'name', 'Nom natif', 'Native name', 'original',
                    'sourceSnapshot', {'source': 'wago', 'sourceLocale': 'frFR', 'sourceBuild': manifest['build']},
                    name_file)
        builder.talents('wago')
        rows = db.execute("SELECT entity_id,text FROM records WHERE kind='talents'").fetchall()
        self.assertEqual(set(tuple(row) for row in rows), {('9', 'Nom natif'), ('11', 'Nom direct')})

    def test_packet_retrieves_only_explicitly_typed_related_names(self):
        document = json.loads(self.entity.read_text())
        document.update({'areaId': 19, 'objectiveTargets': {'npc': [{'id': 7, 'sourceIndex': 1}]},
                         'startedBy': {'1': {'1': 999}}})
        self.entity.write_text(dump_json(document))
        db = self.database()
        result = packet(db, self.root, 'quests', '1', ['frFR'])
        self.assertEqual({(row['kind'], row['id']) for row in result['relatedNames']},
                         {('areas', '19'), ('npcs', '7')})


if __name__ == '__main__':
    unittest.main()
