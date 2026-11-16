"""Guard disjoint label assignments and prevent stale or malformed translations."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tools.catalogs import client_label_batches as labels


class ClientLabelBatchTests(unittest.TestCase):
    def test_disjoint_jobs_preserve_sources_placeholders_and_other_translations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'catalogs/globalstrings'
            path.mkdir(parents=True)
            (path / 'metadata.json').write_text(json.dumps({
                'storageVersion': 2, 'kinds': ['globalstrings'], 'document': {'schemaVersion': 1}}))
            for id, key, source, target in ((1, 'A', 'Requires %s (%d)', None),
                                             (2, 'B', 'Tools', None), (3, 'C', 'Known', 'Connu')):
                entity = {'key': key, 'locales': {'enUS': {'name': source}, 'frFR': {}}}
                if target: entity['locales']['frFR']['name'] = target
                (path / f'{id}.json').write_text(json.dumps(entity))
            jobs = root / 'jobs'
            manifest = labels.prepare(root, 'frFR', jobs, 1)
            self.assertEqual(len(manifest), 2)
            batch = json.loads((jobs / manifest[0]['batch']).read_text())
            self.assertEqual(set(batch['records']), {'A'})
            results = {'A': '%s (%d) requis'}
            self.assertEqual(labels.validate(root, batch, results), 'frFR')
            patch = labels.patch(root, batch, results)
            self.assertIn('ForeverRosettaStoneAI', patch)
            with self.assertRaisesRegex(ValueError, 'placeholders'):
                labels.validate(root, batch, {'A': '%s requis'})
            with self.assertRaisesRegex(ValueError, 'exactly'):
                labels.validate(root, batch, {'A': 'Texte', 'C': 'Changed'})
            entity = json.loads((path / '1.json').read_text())
            entity['locales']['deDE'] = {'name': 'Unrelated accepted translation'}
            (path / '1.json').write_text(json.dumps(entity))
            self.assertEqual(labels.validate(root, batch, results), 'frFR')
            entity['locales']['enUS']['name'] = 'Requires %s'
            (path / '1.json').write_text(json.dumps(entity))
            with self.assertRaisesRegex(ValueError, 'Stale'):
                labels.validate(root, batch, results)


if __name__ == '__main__':
    unittest.main()
