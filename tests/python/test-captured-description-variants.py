"""Native wording reuse and observed symbolic grammar preserve real captured values."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from live_value_harness import LiveValueHarness, ROOT
sys.path.insert(0, str(ROOT))
from tools.build.runtime_catalog import project_tooltip_details
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps


class CapturedDescriptionVariantTests(LiveValueHarness, unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((ROOT / 'tests/fixtures/source-backed-description-variants.json').read_text())
        cls.observations = list(matrix.observations(ROOT / 'tests/fixtures/tooltip-campaign'))
        keys = {matrix.fingerprint(o) for o in cls.observations if o['kind'] == 'spell' and o['id'] in (20694, 459611)}
        with tempfile.TemporaryDirectory(dir=ROOT / 'datasources/imports') as directory:
            with contextlib.redirect_stdout(io.StringIO()):
                cls.report = matrix.run(ROOT / 'tests/fixtures/tooltip-campaign', Path(directory) / 'report', case_keys=keys)

    def native(self, entity, locale):
        o = next(o for o in self.observations if o['kind'] == 'spell' and o['id'] == entity and o['locale'] == locale)
        return next(row['leftText'] for row in gaps.clean(o['data'])['lines'] if row.get('type') == 34)

    def test_native_holy_nova_variants_pass_all_official_directions(self):
        self.assertTrue(any(c['id'] == 20694 for c in self.report['cases']))
        self.assertFalse([failure for failure in self.report['failures'] if failure['id'] == 20694])

    def test_primary_native_wording_and_verified_donor_provenance_are_retained(self):
        owner = json.loads((ROOT / 'catalogs/spells/20694.json').read_text())
        for locale in ('zhCN', 'zhTW'):
            current = owner['locales'][locale]
            self.assertEqual(current['description'], self.evidence['native'][locale]['20694'])
            values = {self.evidence['native'][locale][str(i)] for i in self.evidence['donorIDs']}
            self.assertEqual(current['descriptionVariants'], list(values))
            proof = current['translationMetadata']['fields']['descriptionVariants.0']
            self.assertEqual(proof['sourceRecordIDs'], self.evidence['donorIDs'])
            self.assertEqual(proof['origin'], 'original')
            self.assertEqual(proof['canonicalEnglishSha256'], hashlib.sha256(self.evidence['canonicalEnglish'].encode()).hexdigest())
            for entity in self.evidence['donorIDs']:
                self.assertEqual(self.evidence['native']['enUS'][str(entity)], self.evidence['canonicalEnglish'])

    def test_stale_english_or_unverified_variant_cannot_ship(self):
        owner = json.loads((ROOT / 'catalogs/spells/20694.json').read_text())
        for mutation in ('english', 'provenance'):
            changed = copy.deepcopy(owner)
            if mutation == 'english':
                changed['locales']['enUS']['description'] += '!'
            else:
                changed['locales']['zhCN']['translationMetadata']['fields']['descriptionVariants.0']['origin'] = 'ai'
            with self.assertRaises(ValueError):
                project_tooltip_details(changed, changed['locales']['zhCN'], 'zhCN')

    def test_distinct_fallback_outputs_remain_ambiguous(self):
        # Fault-inject a second derivative of the real native variant, not a new
        # source claim. The engine must not select arbitrary alternate wording.
        self.lua.execute(b'''
            local original=ForeverRosettaStoneDB.GetSpellDetails
            ForeverRosettaStoneDB.GetSpellDetails=function(self,id,locale)
                local value=original(self,id,locale)
                if id~=20694 or locale~='zhCN' then return value end
                local changed={}
                for key,part in pairs(value) do changed[key]=part end
                changed.descriptionVariants={value.descriptionVariants[1],value.descriptionVariants[1]..'!'}
                return changed
            end
        ''')
        self.assertIsNone(self.capture(20694, self.native(20694, 'frFR'), 'frFR', 'zhCN'))

    def test_missing_approved_variant_cannot_invent_the_primary_radius(self):
        self.lua.execute(b'''
            local original=ForeverRosettaStoneDB.GetSpellDetails
            ForeverRosettaStoneDB.GetSpellDetails=function(self,id,locale)
                local value=original(self,id,locale)
                if id~=20694 or locale~='zhCN' then return value end
                local changed={}
                for key,part in pairs(value) do changed[key]=part end
                changed.descriptionVariants=nil
                return changed
            end
        ''')
        self.assertIsNone(self.capture(20694, self.native(20694, 'frFR'), 'frFR', 'zhCN'))

    def test_matched_russian_non_singular_branch_translates_without_inventing_counter(self):
        native = self.native(459611, 'ruRU')
        self.assertIn('$w', native)
        for target in matrix.OFFICIAL_LOCALES - {'ruRU'}:
            with self.subTest(target=target):
                translated = self.capture(459611, native, 'ruRU', target)
                self.assertIsNotNone(translated)
                self.assertIn(b'$w', translated)
                self.assertFalse(any(char in b'0123456789' for char in translated))

    def test_ambiguous_target_counter_grammar_still_needs_context(self):
        native = self.native(459611, 'enUS')
        self.assertIn('$w', native)
        self.assertIsNone(self.capture(459611, native, 'enUS', 'ruRU'))


if __name__ == '__main__':
    unittest.main()
