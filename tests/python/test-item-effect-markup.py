"""Item effects preserve owned markup and plural text while transporting live values."""
import unittest
from live_value_harness import LiveValueHarness


class ItemEffectMarkupTests(LiveValueHarness, unittest.TestCase):
    def prepare(self, french, english):
        self.lua.globals().records(900100,french.encode(),english.encode())
        self.lua.execute(b'ForeverRosettaStoneDB.GetItemRules=function() return {effects={{spellID=900100,triggerType=0}}} end')

    def test_inline_color_and_literal_icon_remain_owned_target_text(self):
        self.prepare('Gain |cffffffff$s1|r |T1234:14:14:0:1|t.',
                     'Grants |cffffffff$s1|r |T1234:14:14:0:1|t.')
        result=self.lua.globals().item(900101,900100,44,b'Use: Grants 17 .',b'enUS',b'frFR')
        self.assertEqual(result[0],b'Utiliser : Gain |cffffffff17|r |T1234:14:14:0:1|t.')

    def test_fixed_count_controls_target_plural(self):
        self.prepare('Cree 5 $lobjet:objets;.','Creates 5 items.')
        result=self.lua.globals().item(900101,900100,44,b'Use: Creates 5 items.',b'enUS',b'frFR')
        self.assertEqual(result[0],b'Utiliser : Cree 5 objets.')

    def test_displayed_count_controls_target_plural(self):
        self.prepare('Cree $s1 $lobjet:objets;.','Creates $s1 $litem:items;.')
        for count,word in [(1,'item'),(17,'items')]:
            result=self.lua.globals().item(900101,900100,44,f'Use: Creates {count} {word}.'.encode(),b'enUS',b'frFR')
            expected=f'Utiliser : Cree {count} '+('objet.' if count==1 else 'objets.')
            self.assertEqual(result[0],expected.encode())


if __name__=='__main__': unittest.main()
