"""Quest formatting uses indexed client data without matching native text."""

import unittest

from id_only_matrix_harness import IdOnlyHarness


class QuestSourcesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.harness = IdOnlyHarness()

    def setUp(self):
        self.harness.set_context('frFR', 987654, 'baseline')
        self.harness.set_offer(True)
        self.harness.lua.globals().fixtureQuest = self.harness.to_lua({
            'title': 'Titre',
            'objectiveLines': [{'index': 1, 'type': 'item', 'text': 'Objets: {current}/{required}'}],
        })
        self.harness.lua.execute(b'ForeverRosettaStoneDB.GetQuest = function() return fixtureQuest end')

    def test_amounts_require_indexed_client_values(self):
        self.harness.set_objectives(None)
        actual, error, forbidden = self.harness.attempt(
            lambda: self.harness.addon.FormatQuestText(self.harness.addon, b'Collect $1oa', 987654))
        self.assertIsNone(actual)
        self.assertIsNone(error)
        self.assertFalse(forbidden)

        self.harness.set_objectives([{'numRequired': 8}, {'numRequired': 0}])
        actual, error, forbidden = self.harness.attempt(
            lambda: self.harness.addon.FormatQuestText(self.harness.addon, b'$2oa / $1oa', 987654))
        self.assertEqual(actual, b'0 / 8')
        self.assertIsNone(error)
        self.assertFalse(forbidden)

    def test_indexed_objective_uses_structured_counts(self):
        self.harness.set_objectives([{'type': 'item', 'text': 'Native', 'numFulfilled': 2, 'numRequired': 8}])
        actual, error, forbidden = self.harness.attempt(
            lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[1][b'translated'])
        self.assertEqual(actual, b'Objets: 2/8')
        self.assertIsNone(error)
        self.assertFalse(forbidden)

    def test_missing_player_label_signals_incomplete(self):
        self.harness.lua.execute(b"UnitClass = function() return nil, 'UNKNOWN' end")
        try:
            actual, error, forbidden = self.harness.attempt(
                lambda: self.harness.addon.FormatQuestText(self.harness.addon, b'Hello $C', 987654))
            self.assertIsNone(actual)
            self.assertIsNone(error)
            self.assertFalse(forbidden)
        finally:
            self.harness.lua.execute(b"UnitClass = function() return 'Warrior', 'WARRIOR' end")

    def test_unavailable_data_preserves_native_without_formatting(self):
        for template, objective in [
            ('Faction: {standing}', {'type': 'item', 'numFulfilled': 2, 'numRequired': 8}),
            ('Objets: {current}/{required}', {'type': 'item', 'numRequired': 8}),
            ('Objets: $2oa', {'type': 'item', 'numRequired': 8}),
            ('Objets: {current}/{required}', {'type': 'log'}),
        ]:
            with self.subTest(template=template, objective=objective):
                self.harness.lua.globals().fixtureQuest[b'objectiveLines'][1][b'text'] = template.encode()
                objective['text'] = 'Native $B text'
                self.harness.set_objectives([objective])
                actual, error, forbidden = self.harness.attempt(
                    lambda: self.harness.addon.GetProgressLines(self.harness.addon, 987654)[1][b'translated'])
                self.assertEqual(actual, b'Native $B text')
                self.assertIsNone(error)
                self.assertFalse(forbidden)


if __name__ == '__main__':
    unittest.main()
