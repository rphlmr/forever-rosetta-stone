"""Regression checks for missing, duplicated and rebound catalog placeholders."""

import unittest

from catalog_placeholder_matrix import audit_documents, signature


class CatalogPlaceholderTests(unittest.TestCase):
    def audit(self, source, target, other=None, origin='original', kind='spells'):
        records = {'enUS': {'description': source, 'translationMetadata': {
            'fields': {'description': {'origin': origin}}}}, 'frFR': {'description': target}}
        if other is not None:
            records['deDE'] = {'description': other, 'translationMetadata': {
                'fields': {'description': {'origin': 'original'}}}}
        docs = {'quests': {'locales': ['enUS', 'frFR', 'deDE'], 'catalogs': {}},
                kind: {'catalogs': {kind: {'1': {'locales': records}}}}}
        if kind == 'quests':
            docs['quests']['locales'] = ['enUS', 'frFR', 'deDE']
        return audit_documents(docs)

    def test_preserves_index_reference_formula_and_occurrence_counts(self):
        for target in ('Dégâts $s2', 'Dégâts', 'Dégâts $s1 $s1'):
            with self.subTest(target=target):
                self.assertEqual(self.audit('Damage $s1', target)['counts']['failed'], 1)
        self.assertEqual(self.audit('$@spelldesc42', '$@spelldesc43')['counts']['failed'], 1)
        self.assertEqual(self.audit('${$s1*2}', '${$s1*3}')['counts']['failed'], 1)

    def test_checks_extra_placeholders_when_source_has_none(self):
        self.assertEqual(self.audit('Literal', 'Texte $s1')['counts']['failed'], 1)

    def test_printf_reordering_keeps_types_and_positions(self):
        self.assertEqual(signature('%s: %d', 'items'), signature('%2$d : %1$s', 'items'))
        self.assertNotEqual(signature('%s: %d', 'items'), signature('%1$d : %2$s', 'items'))

    def test_ai_text_never_becomes_official_evidence(self):
        report = self.audit('$s1', '$s1', origin='ai')
        self.assertEqual(report['counts']['failed'], 2)
        self.assertTrue(all('no original' in row['reason'] for row in report['failures']))

    def test_official_variation_is_informational_and_target_uses_its_source(self):
        report = self.audit('$s1', '$s1', other='$s2')
        self.assertEqual(report['counts']['failed'], 0)
        self.assertEqual(len(report['officialVariations']), 1)
        self.assertEqual(report['officialVariations'][0]['officialTokens'], ['$s2'])

    def test_original_without_english_placeholder_is_not_blocked(self):
        docs = {'quests': {'locales': ['enUS', 'esES'], 'catalogs': {'quests': {'1': {'locales': {
            'enUS': {'description': 'Listen, {class}.', 'translationMetadata': {
                'fields': {'description': {'origin': 'original', 'sourceLocale': 'enUS'}}}},
            'esES': {'description': 'Escúchame bien.', 'translationMetadata': {
                'fields': {'description': {'origin': 'original', 'sourceLocale': 'esES'}}}},
        }}}}}}
        report = audit_documents(docs)
        self.assertEqual(report['counts']['failed'], 0)
        self.assertEqual(report['counts']['passed'], 2)
        self.assertEqual(report['officialVariations'][0]['officialTokens'], [])

    def test_quest_gender_wording_can_vary_without_losing_player_tokens(self):
        self.assertEqual(self.audit('$N, friend', '$N, $Gami:amie;', kind='quests')['counts']['failed'], 0)
        self.assertEqual(self.audit('$N, friend', '$Gami:amie;', kind='quests')['counts']['failed'], 1)

    def test_missing_text_is_left_to_completeness_gate(self):
        self.assertEqual(self.audit('$s1', '')['counts']['cases'], 1)

    def test_spell_grammatical_inflection_does_not_change_numeric_inputs(self):
        self.assertEqual(self.audit('Deals $s1 damage.', 'Inflige $s1 $lpoint:points;.')['counts']['failed'], 0)
        self.assertEqual(self.audit('Transformed $s1', '$gTransformado:Transformada; $s1')['counts']['failed'], 0)
        self.assertEqual(self.audit('Deals $s1', '$s2 $lpoint:points;')['counts']['failed'], 1)

    def test_all_catalog_kinds_and_sparse_objective_fields_are_enumerated(self):
        docs = {'quests': {'locales': ['enUS', 'frFR'], 'catalogs': {}}}
        for kind in ('quests', 'items', 'spells', 'npcs', 'areas', 'maps', 'talents',
                     'factions', 'creaturetypes', 'classes'):
            field = 'objectiveLines.3' if kind == 'quests' else 'name'
            def record(text, original=False):
                value = {'objectiveLines': [{'index': 3, 'text': text}]} if kind == 'quests' else {'name': text}
                value['translationMetadata'] = {'fields': {field: {'origin': 'original' if original else 'ai'}}}
                return value
            docs.setdefault(kind, {}).setdefault('catalogs', {})[kind] = {
                '1': {'locales': {'enUS': record('$N', True), 'frFR': record('Missing')}}}
        report = audit_documents(docs)
        self.assertEqual(report['counts']['entities'], 10)
        self.assertEqual(report['counts']['failed'], 10)


if __name__ == '__main__':
    unittest.main()
