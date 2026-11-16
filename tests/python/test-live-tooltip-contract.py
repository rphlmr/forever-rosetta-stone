"""Shipping tooltips must expose only the live-value translation engine."""
import unittest
from database_harness import ROOT


class LiveTooltipContractTests(unittest.TestCase):
    def test_legacy_engines_are_not_shipped_or_loaded(self):
        for name in ('spell-description-renderer', 'spell-template-capture'):
            self.assertFalse((ROOT / f'ForeverRosettaStone/tooltips/{name}.lua').exists())
            for manifest in ('tools/build/addon-manifest.toc', 'ForeverRosettaStone/ForeverRosettaStone.toc'):
                self.assertNotIn(name, (ROOT / manifest).read_text())

    def test_tooltip_adapter_never_collects_character_values_for_recalculation(self):
        source = (ROOT / 'ForeverRosettaStone/tooltips/tooltip-descriptions.lua').read_text()
        for name in ('RenderStaticSpellDescription', 'GetSpellBonusDamage', 'GetSpellBonusHealing',
                     'UnitStat', 'GetLiveTraitRank', 'SpellDescriptionRenderer'):
            self.assertNotIn(name, source)


if __name__ == '__main__':
    unittest.main()
