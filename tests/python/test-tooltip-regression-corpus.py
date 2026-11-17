"""Frozen expectations stay independent, complete and reviewable after catalog updates."""
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import tooltip_regression_corpus as corpus


class TooltipRegressionCorpusTests(unittest.TestCase):
    def temporary_corpus(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        documents = corpus.validate()
        sources = {path for document in documents.values() for path in document['sourceInputs']}
        for relative in sources:
            target = root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        for name, document in documents.items():
            (root / corpus.CORPUS / name).write_text(corpus.encode(document))
        return root

    def test_frozen_cases_replay_without_generating_their_expectations(self):
        import live_spell_fixture
        with patch.object(corpus, 'generate', side_effect=AssertionError('Regenerated during replay')), \
                patch.object(live_spell_fixture, 'make_fixture', side_effect=AssertionError('Regenerated expected text')):
            result = corpus.replay()
        self.assertEqual(result, {'fixtures': 10, 'cases': 1800, 'failures': []})
        documents = corpus.validate()
        for rank, amount in ((1, '23'), (2, '47'), (3, '70')):
            for document in documents.values():
                if document['scenario'].get('rank') == rank:
                    self.assertTrue(all(amount in text for text in document['expected'].values()))

    def test_corrupted_production_output_cannot_redefine_the_baseline(self):
        import template_pilot_spells
        original = template_pilot_spells._renderer

        def corrupt(harness):
            renderer = original(harness)

            def render(*args):
                actual, incomplete = renderer(*args)
                return actual + b' corrupted' if actual else actual, incomplete
            return render

        with patch.object(template_pilot_spells, '_renderer', side_effect=corrupt):
            result = corpus.replay()
        self.assertEqual(len(result['failures']), 1800)

    def test_missing_locale_rank_and_dependency_pin_are_rejected(self):
        for mutation in ('locale', 'rank', 'pin'):
            root = self.temporary_corpus()
            path = root / corpus.CORPUS / 'talents-1001-rank-2-baseline.json'
            document = corpus.read(path)
            if mutation == 'rank':
                path.unlink()
            else:
                if mutation == 'locale':
                    document['expected'].pop('itIT')
                else:
                    document['sourceInputs'].pop('catalogs/spells/17783.json')
                path.write_text(corpus.encode(document))
            with self.subTest(mutation=mutation), self.assertRaisesRegex(ValueError, 'mismatch|Stale'):
                corpus.validate(root)

    def test_unchanged_preparation_is_deterministic(self):
        root = self.temporary_corpus()
        before = corpus.inventory(root)
        for number in (1, 2):
            directory = root / f'datasources/imports/proposal-{number}'
            result = corpus.prepare(root, directory)
            self.assertEqual(result['changedFixtures'], 0)
            self.assertEqual((directory / 'diff.patch').read_text(), '')
            corpus.apply(root, directory)
            self.assertEqual(corpus.inventory(root), before)

    def test_source_update_changes_only_owned_cases_and_requires_explicit_apply(self):
        root = self.temporary_corpus()
        before = corpus.inventory(root)
        path = root / 'catalogs/spells/16757.json'
        spell = corpus.read(path)
        spell['locales']['enUS']['description'] += ' Updated source wording.'
        path.write_text(corpus.encode(spell))
        with self.assertRaisesRegex(ValueError, 'Stale.*catalogs/spells/16757.json'):
            corpus.validate(root)
        directory = root / 'datasources/imports/source-update'
        result = corpus.prepare(root, directory)
        self.assertEqual(result['changedFixtures'], 2)
        self.assertEqual(corpus.inventory(root), before)
        self.assertIn('Updated source wording.', (directory / 'diff.patch').read_text())
        corpus.apply(root, directory)
        self.assertEqual(len(corpus.validate(root)), 10)
        self.assertEqual({name for name, checksum in before.items() if corpus.inventory(root)[name] != checksum},
                         {'spells-16757-baseline.json', 'spells-16757-modified.json'})

    def test_tampered_proposals_and_concurrent_edits_fail_before_writes(self):
        for mutation in ('proposal', 'fixture', 'source'):
            root = self.temporary_corpus()
            directory = root / 'datasources/imports/proposal'
            corpus.prepare(root, directory)
            name = 'spells-16757-modified.json'
            path = directory / 'cases' / name if mutation == 'proposal' else root / corpus.CORPUS / name
            if mutation == 'source':
                path = root / 'catalogs/spells/433.json'
                path.write_text(path.read_text() + '\n')
            else:
                document = corpus.read(path)
                document['expected']['enUS'] += ' Changed after preparation.'
                path.write_text(corpus.encode(document))
            before = corpus.inventory(root)
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                corpus.apply(root, directory)
            self.assertEqual(corpus.inventory(root), before)

    def test_unavailable_source_cannot_drop_previously_accepted_cases(self):
        root = self.temporary_corpus()
        path = root / 'catalogs/spells/433.json'
        spell = corpus.read(path)
        spell['locales']['frFR'].pop('auraDescription')
        path.write_text(corpus.encode(spell))
        before = corpus.inventory(root)
        from live_spell_fixture import FixtureUnavailable
        directory = root / 'datasources/imports/invalid-source'
        with self.assertRaises(FixtureUnavailable):
            corpus.prepare(root, directory)
        self.assertEqual(corpus.inventory(root), before)
        self.assertFalse(directory.exists())


if __name__ == '__main__':
    unittest.main()
