"""Guard source-confirmed bindings, dependency kinds and all-language effect coverage."""

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_links import entity_links, spell_references
from catalog_placeholder_matrix import audit_documents


class CatalogLinkTests(unittest.TestCase):
    def fixture(self):
        return json.loads((ROOT / 'tests/fixtures/catalog-effect-bindings-70938.json').read_text())

    def test_owned_bindings_match_the_verified_client_slots_and_triggers(self):
        for binding in self.fixture()['bindings']:
            with self.subTest(item=binding['item'], spell=binding['spell']):
                item = json.loads((ROOT / f"catalogs/items/{binding['item']}.json").read_text())
                effects = item.get('tooltipData', {}).get('effects', [])
                actual = [effect for effect in effects if effect['slot'] == binding['slot']]
                self.assertEqual(actual, [{'slot': binding['slot'], 'spellID': binding['spell'],
                                           'triggerType': binding['trigger']}])

    def test_every_linked_effect_has_owned_text_and_provenance_in_all_languages(self):
        fixture = self.fixture()
        for spell_id in sorted({binding['spell'] for binding in fixture['bindings']}):
            path = ROOT / f'catalogs/spells/{spell_id}.json'
            with self.subTest(spell=spell_id):
                self.assertTrue(path.exists(), f'Missing owned spell: {spell_id}')
                if not path.exists(): continue
                entity = json.loads(path.read_text())
                english = entity['locales']['enUS']
                self.assertTrue(english.get('description'))
                for locale in fixture['locales']:
                    text = entity['locales'].get(locale, {})
                    for field in ('name', 'description', 'auraDescription'):
                        if not english.get(field): continue
                        self.assertTrue(text.get(field), (spell_id, locale, field))
                        origin = text.get('translationMetadata', {}).get('fields', {}).get(field, {}).get('origin')
                        self.assertIn(origin, ('original', 'community', 'ai'))

    def test_link_inventory_keeps_id_namespaces_and_template_fields(self):
        refs = spell_references('$@spelldesc<101> $@spellaura102 $@spellname103 $104s2 $105w1 $@spelltooltip<106>')
        self.assertEqual(refs, {(101, 'description'), (102, 'auraDescription'),
                                (103, 'name'), (104, None), (105, None), (106, 'description')})
        self.assertEqual(spell_references('$?s42[known][] $?pc43[active][] $s1'), set())
        npc = list(entity_links('npcs', {'factionTemplateId': 12, 'factionId': 72}))
        self.assertEqual(npc, [('factionId', 'factions', 72, 'name', None)])
        item = {'tooltipData': {'set': {'items': [7], 'bonuses': [{'spellID': 8, 'threshold': 2}]}}}
        self.assertEqual({(kind, id) for _, kind, id, _, _ in entity_links('items', item)},
                         {('items', 7), ('spells', 8)})
        quest = {'areaId': 9, 'objectiveTargets': {'item': [{'id': 10}]},
                 'clientObjectiveTargets': [{'kind': 'npc', 'id': 11}, {'kind': 'faction', 'id': 12}]}
        self.assertEqual({(kind, id) for _, kind, id, _, _ in entity_links('quests', quest)},
                         {('areas', 9), ('items', 10), ('npcs', 11), ('factions', 12)})
        tool_spell = {'tooltipData': {'requiredToolCategories': [373]}}
        self.assertEqual(list(entity_links('spells', tool_spell)),
                         [('tooltipData.requiredToolCategories.0', 'totemcategories', 373, 'name', None)])
        item_tool_spell = {'tooltipData': {'requiredToolCategories': [373], 'requiredToolItems': [6218]}}
        self.assertEqual(list(entity_links('spells', item_tool_spell)),
                         [('tooltipData.requiredToolCategories.0', 'totemcategories', 373, 'name', None),
                          ('tooltipData.requiredToolItems.0', 'items', 6218, 'name', None)])
        spell = {'tooltipData': {'variables': ['$value=$106s1'],
                                'durationModifiers': [{'spellID': 107}]}}
        self.assertEqual({id for _, _, id, _, _ in entity_links('spells', spell)}, {106, 107})

    def test_effect_placeholders_preserve_their_official_value_inputs(self):
        fixture = self.fixture()
        entities = {str(id): json.loads((ROOT / f'catalogs/spells/{id}.json').read_text())
                    for id in {binding['spell'] for binding in fixture['bindings']}}
        documents = {'quests': {'locales': fixture['locales'], 'catalogs': {}},
                     'spells': {'catalogs': {'spells': entities}}}
        report = audit_documents(documents)
        self.assertEqual(report['counts']['failed'], 0, report['failures'][:5])


if __name__ == '__main__':
    unittest.main()
