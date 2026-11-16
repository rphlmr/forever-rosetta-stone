"""Unverified item-trigger surfaces remain failures without fabricated client rows."""

import unittest
from unittest.mock import patch

import id_only_item_matrix as matrix


class Harness:
    def __init__(self, root=None):
        self.db = self
        self.profile = {'level': 1, 'spirit': 20, 'spellPower': 0}

    def set_context(self, *args, **kwargs):
        pass

    def GetItemName(self, *args):
        return 'Item'

    def attempt(self, call):
        return call(), None, []


class ItemTriggerCoverageTests(unittest.TestCase):
    def test_unverified_trigger_is_counted_without_fabricating_a_row(self):
        triggers = (5, 6, 7, 9, 10)
        item = {'locales': {'enUS': {'name': 'Item'}}, 'tooltipData': {
            'effects': [{'spellID': 7, 'triggerType': trigger} for trigger in triggers],
        }}
        spell = {'locales': {'enUS': {'description': 'A description'}}, 'tooltipData': {}}

        def load(root, kind, ids=None):
            return {'catalogs': {kind: {'1': item} if kind == 'items' else {'7': spell}}}

        with patch.object(matrix, 'load_catalog', side_effect=load), \
                patch.object(matrix, 'IdOnlyHarness', Harness), \
                patch.object(matrix, 'render_line') as render:
            report = matrix.run_matrix(locales=['enUS'], ids=[1], profiles=['baseline'])

        render.assert_not_called()
        failures = [row for row in report['failures'] if row['field'] == 'effect']
        self.assertEqual([row['triggerType'] for row in failures], list(triggers))
        self.assertTrue(all(row['reason'] == 'unsupported item trigger type' for row in failures))


if __name__ == '__main__':
    unittest.main()
