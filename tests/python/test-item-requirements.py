"""Item restrictions resolve only names owned by the selected item's ID bindings."""
import unittest
from live_value_harness import LiveValueHarness


class ItemRequirementTests(LiveValueHarness, unittest.TestCase):
    def setUp(self):
        super().setUp()
        self.lua.execute(b'''
            Enum.TooltipDataLineType.UsageRequirement=43
            addon.itemSubclasses={}
            for key,value in pairs(addon.tooltipFormatsByLocale.frFR) do _G[key]=value end
            requirement=function(id,text,target)
                return addon:GetLocalizedTooltipLine({type=43,leftText=text},'item',id,target or 'enUS')
            end
        ''')

    def test_recorded_scroll_restrictions_translate(self):
        g=self.lua.globals()
        self.assertEqual(g.requirement(211787,'Classes : Mage'.encode())[0],b'Classes: Mage')
        self.assertEqual(g.requirement(211787,'Compréhension (1) requis'.encode())[0],b'Requires Comprehension (1)')
        self.assertEqual(g.requirement(211787,'Compréhension (17) requis'.encode())[0],b'Requires Comprehension (17)')

    def test_banner_keeps_the_recorded_values_without_static_calculation(self):
        native=('Utiliser : Vous déployez une bannière qui vous permet, ainsi qu’aux membres '
                'de l’Alliance à proximité, de gagner 14 au score d’Esprit. Effet mutuellement '
                'incompatible avec Esprit divin.\n\nNécessite un feu de camp à proximité. '
                'Les effets de campement partagent un temps de recharge de 1 heure.')
        result=self.lua.globals().item(279973,1307239,44,native.encode(),b'frFR',b'enUS')
        self.assertIsNotNone(result[0])
        self.assertIn(b'14 increased Spirit',result[0])
        self.assertIn(b'1 hour',result[0])
        self.assertNotIn('Vous déployez'.encode(),result[0])

    def test_scroll_whole_tooltip_has_no_incomplete_warning(self):
        self.lua.execute('''
            Enum.TooltipDataLineType.FlavorText=37
            render(211787,'item','','frFR','enUS',{
                {type=13,leftText='Scroll'},
                {type=43,leftText='Classes : Mage'},
                {type=43,leftText='Compréhension (1) requis'},
                {type=37,leftText='Native flavor'},
            })
            assert(#rows==4,tostring(#rows))
            assert(rows[2].text=='Classes: Mage')
            assert(rows[3].text=='Requires Comprehension (1)')
            assert(rows[4].text=='A Mage can decipher this with their Comprehension skill.')
        '''.encode())

    def test_unowned_names_missing_bindings_and_untyped_rows_stay_native(self):
        g=self.lua.globals()
        self.assertIsNone(g.requirement(211787,b'Classes : Unknown')[0])
        self.assertIsNone(g.requirement(211787,'Autre compétence (1) requis'.encode())[0])
        self.lua.execute(b"assert(addon:GetLocalizedTooltipLine({type=0,leftText='Classes : Mage'},'item',211787,'enUS')==nil)")
        self.lua.execute(b'''ForeverRosettaStoneDB.GetItemRules=function() return nil end
            assert(requirement(211787,'Classes : Mage')==nil)
        ''')

    def test_generic_bindings_handle_other_ids_and_multiple_classes(self):
        self.lua.execute(br'''
            ForeverRosettaStoneDB.GetItemRules=function(_,id)
                if id==999001 then return {requirements={classIDs={8,5},skillCategoryID=2757}} end
            end
            assert(requirement(999001,'Classes : Mage, Pr\195\170tre')=='Classes: Mage, Priest')
            assert(requirement(999001,'Classes : Mage, Mage')==nil)
            assert(requirement(999001,'Classes : Mage')==nil)
            assert(requirement(999001,'Classes : Unknown, Mage')==nil)
        ''')

    def test_missing_target_name_and_secret_input_fail_closed(self):
        self.lua.execute(b'''
            ForeverRosettaStoneDB.GetClassName=function(_,_,locale)
                if locale=='frFR' then return 'Mage' end
            end
            assert(requirement(211787,'Classes : Mage')==nil)
            assert(addon:GetLocalizedTooltipLine({type=43,leftText={secret=true}},'item',211787,'enUS')==nil)
        ''')


if __name__=='__main__': unittest.main()
