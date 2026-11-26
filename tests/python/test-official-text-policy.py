"""Official wording is authoritative even when it happens to be English."""

import json
import copy
import runpy
import sqlite3
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.official_text import OFFICIAL_LOCALES, ADDITIONAL_LOCALES

fill = runpy.run_path(str(ROOT / 'tools/catalogs/fill-official-text.py'))
work = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))
batch = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-batch.py'))


class OfficialTextPolicyTests(unittest.TestCase):
    def entity(self):
        return {'locales': {locale: {'name': 'Official Name', 'translationMetadata': {
            'fields': {'name': {'origin': 'original', 'source': 'wago', 'sourceLocale': locale}}}}
            for locale in OFFICIAL_LOCALES}}

    def test_official_english_consensus_does_not_replace_other_languages(self):
        for origin in ('community', 'original', 'ai'):
            entity = self.entity()
            native = {'name': 'Původní název', 'translationMetadata': {'fields': {'name': {
                'origin': origin, 'source': 'fixture', 'sourceLocale': 'enUS' if origin == 'ai' else 'csCZ'}}}}
            entity['locales']['csCZ'] = copy.deepcopy(native)
            after, _ = fill['update_entity'](entity, [])
            self.assertEqual(after, entity)
            batch['validate_record']('factions', '1', entity, after, [*OFFICIAL_LOCALES, 'csCZ'])

    def test_official_english_is_not_discarded_as_a_missing_translation(self):
        db = sqlite3.connect(':memory:')
        db.row_factory = sqlite3.Row
        db.execute('CREATE TABLE records(kind,entity_id,locale,field,text,english,origin,evidence,provenance,flags,id)')
        db.execute('INSERT INTO records VALUES(?,?,?,?,?,?,?,?,?,?,?)',
                   ('factions', '72', 'frFR', 'name', 'Stormwind', 'Stormwind', 'original', 'sourceSnapshot',
                    json.dumps({'source': 'wago', 'sourceLocale': 'frFR', 'sourceBuild': '1.60.1.70938'}),
                    json.dumps(['equalsEnglish:inspectBeforeReuse']), 1))
        rows = list(fill['source_rows'](db))
        self.assertEqual(len(rows), 1)
        before = {'locales': {'enUS': {'name': 'Stormwind'}, 'frFR': {'name': 'Hurlevent'}}}
        after, _ = fill['update_entity'](before, rows)
        self.assertEqual(after['locales']['frFR']['name'], 'Stormwind')
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['name']['origin'], 'original')
        db.close()

    def test_missing_additional_language_waits_for_verified_game_evidence(self):
        entity = self.entity()
        documents = {'quests': {'locales': [*OFFICIAL_LOCALES, 'svSE'], 'catalogs': {'quests': {}}},
                     'factions': {'catalogs': {'factions': {'1': entity}}}}
        queue = work['create_queue'](documents)
        self.assertEqual(queue['jobs'], [])
        self.assertEqual(len(queue['blocked']), 1)
        self.assertEqual(queue['blocked'][0]['reasons'], ['noVerifiedOfficialSource'])

    def test_batches_cannot_overtranslate_existing_official_text(self):
        before = self.entity()
        after = copy.deepcopy(before)
        after['locales']['frFR']['name'] = 'Nom inventé'
        after['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'ai'
        with self.assertRaisesRegex(ValueError, 'Official wording must not be replaced'):
            batch['validate_record']('factions', '1', before, after, list(OFFICIAL_LOCALES))

    def test_batches_cannot_rewrite_existing_community_source_as_ai(self):
        before = self.entity()
        before['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'community'
        after = copy.deepcopy(before)
        after['locales']['frFR']['name'] = 'Rewritten name'
        after['locales']['frFR']['translationMetadata']['fields']['name']['origin'] = 'ai'
        with self.assertRaisesRegex(ValueError, 'Community source wording'):
            batch['validate_record']('factions', '1', before, after, list(OFFICIAL_LOCALES))

    def test_batches_accept_english_based_translation_for_missing_languages(self):
        before = self.entity()
        after = copy.deepcopy(before)
        after['locales']['svSE'] = {'name': 'Översatt namn', 'translationMetadata': {
            'fields': {'name': {'origin': 'ai', 'source': 'fixture', 'sourceLocale': 'enUS'}}}}
        batch['validate_record']('factions', '1', before, after, [*OFFICIAL_LOCALES, 'svSE'])

    def test_new_official_description_replaces_temporary_ai(self):
        before={'locales':{'enUS':{'description':'English source.'},'frFR':{
            'description':'Traduction temporaire.',
            'translationMetadata':{'fields':{'description':{'origin':'ai','source':'ForeverRosettaStoneAI','sourceLocale':'enUS'}}}}}}
        row={'locale':'frFR','field':'description','text':'Texte officiel.','english':'English source.',
             'origin':'original','provenance':json.dumps({'source':'wago','sourceLocale':'frFR','sourceBuild':'1.60.1.70938'})}
        self.assertEqual(fill['update_entity'](before,[])[0],before)
        after,_=fill['update_entity'](before,[row])
        self.assertEqual(after['locales']['frFR']['description'],'Texte officiel.')
        self.assertEqual(after['locales']['frFR']['translationMetadata']['fields']['description']['origin'],'original')

    def test_explicit_source_update_cannot_demote_official_to_community(self):
        before=self.entity()
        before['locales']['frFR']['name']='Nom officiel'
        row={'locale':'frFR','field':'name','text':'Community','english':'Official Name',
             'origin':'community','provenance':json.dumps({'source':'questie','sourceLocale':'frFR'})}
        after,_=fill['update_entity'](before,[row],update_english=True)
        self.assertEqual(after,before)

    def test_batches_cannot_demote_official_provenance_without_changing_text(self):
        before=self.entity();after=copy.deepcopy(before)
        after['locales']['frFR']['translationMetadata']['fields']['name']['origin']='ai'
        with self.assertRaisesRegex(ValueError,'Official wording must not be replaced'):
            batch['validate_record']('factions','1',before,after,list(OFFICIAL_LOCALES))


if __name__ == '__main__':
    unittest.main()
