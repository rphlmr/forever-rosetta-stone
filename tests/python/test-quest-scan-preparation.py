"""Check offline probe preparation without WoW or ignored reference artifacts."""

import runpy
import re
import tempfile
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


ROOT = Path(__file__).resolve().parents[2]
prepare = runpy.run_path(str(ROOT / 'tools/quest-scan/prepare.py'))['prepare_probe']


class QuestScanPreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.output = self.root / 'datasources/imports/quest-scan/run/rosetta-quest-probe'

    def test_fresh_checkout_prepares_explicit_ids_and_reproducible_fingerprints(self):
        first = prepare([170, 16], self.output, root=self.root)
        second = prepare([16, 170], self.output.parent / 'another-probe', root=self.root)
        self.assertEqual(first, second)
        self.assertEqual(first['ids'], [16, 170])
        self.assertEqual({path.name for path in self.output.iterdir()},
                         {'probe.lua', 'queue.lua', 'rosetta-quest-probe.toc'})
        self.assertIn('ids = {16, 170}', (self.output / 'queue.lua').read_text())
        self.assertEqual((self.output / 'probe.lua').read_bytes(),
                         (ROOT / 'tools/quest-scan/rosetta-quest-probe/probe.lua').read_bytes())

    def test_existing_run_is_never_overwritten(self):
        prepare([170], self.output, root=self.root)
        before = {path.name: path.read_bytes() for path in self.output.iterdir()}

        with self.assertRaises(FileExistsError):
            prepare([171], self.output, root=self.root)

        self.assertEqual({path.name: path.read_bytes() for path in self.output.iterdir()}, before)

    def test_candidate_dependencies_are_validated_sorted_and_fingerprinted(self):
        for dependencies in ({'171': [1]}, {'0170': [1]}, {'170': []}, {'170': [1, 1]},
                             {'170': [True]}, {'170': list(range(1, 102))}):
            with self.subTest(dependencies=dependencies), self.assertRaises(ValueError):
                prepare([170], self.output, root=self.root, item_dependencies=dependencies)
        queue = prepare([170], self.output, root=self.root, item_dependencies={'170': [8, 2]})
        self.assertEqual(queue['itemDependencies'], {'170': [2, 8]})
        self.assertIn('[170] = {2, 8}', (self.output / 'queue.lua').read_text())
        other = prepare([170], self.output.parent / 'other', root=self.root)
        self.assertNotEqual(queue['hash'], other['hash'])

    def test_named_session_isolates_saved_state_and_rejects_invalid_identifiers(self):
        for name in ('', 'invalid-name', 'x;error()', '9start', 'a' * 65):
            with self.subTest(name=name), self.assertRaises(ValueError):
                prepare([170], self.output, root=self.root, session_name=name)
        queue = prepare([170], self.output, root=self.root, session_name='Matrix20261113')
        self.assertEqual(queue['savedVariable'], 'RosettaQuestProbeData_Matrix20261113')
        for name in ('probe.lua', 'rosetta-quest-probe.toc'):
            text = (self.output / name).read_text()
            self.assertIn(queue['savedVariable'], text)
            self.assertIsNone(re.search(r'\bRosettaQuestProbeData\b', text))
        original = prepare([170], self.output.parent / 'original', root=self.root)
        self.assertNotEqual(queue['hash'], original['hash'])

    def test_preparation_cannot_write_into_shipping_folders(self):
        with self.assertRaisesRegex(ValueError, 'outside shipping addons'):
            prepare([170], self.root / 'ForeverRosettaStone/probe', root=self.root)

        self.assertFalse((self.root / 'ForeverRosettaStone').exists())

    def test_invalid_queues_are_rejected_before_creating_output(self):
        for ids in ([], [0], [-1], [True], ['170'], [170, 170]):
            with self.subTest(ids=ids), self.assertRaises(ValueError):
                prepare(ids, self.output, root=self.root)

        with self.assertRaisesRegex(ValueError, 'commit SHA'):
            prepare([170], self.output, 'main', root=self.root)

        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
