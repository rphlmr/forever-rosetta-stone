"""Reference ownership and grammar transport displayed values through the live engine."""
import unittest
from live_value_harness import LiveValueHarness


class LiveSpellReferenceTests(LiveValueHarness, unittest.TestCase):
    def test_nested_sibling_references_and_repetitions(self):
        self.lua.execute(b'''records(900100,'Parent $s1 : $@spelldesc900101 / $@spelldesc<900101>',
            'Parent $s1: $@spelldesc900101 / $@spelldesc<900101>');
            records(900101,'Enfant ${$s2*2} en $d.','Child ${$s2*2} over $d.')''')
        self.assertEqual(self.capture(900100,'Parent 99: Child 42 over 30 sec. / Child 42 over 30 sec.','enUS','frFR'),
                         b'Parent 99 : Enfant 42 en 30 sec. / Enfant 42 en 30 sec.')
        self.assertIsNone(self.capture(900100,'Parent 99: Child 42 over 30 sec. / Child 43 over 30 sec.','enUS','frFR'))

    def test_aura_references_have_distinct_field_ownership(self):
        self.lua.execute(b'''records(900100,'Cast $@spellaura900101','Lance $@spellaura900101');
            records(900101,'Unrelated cast.','Autre sort.');
            fakeRecords[900101].frFR.auraDescription='Aura $s2.';
            fakeRecords[900101].enUS.auraDescription='Effect $s2.';
            fakeRecords[900101].enUS.originalFields.auraDescription=true''')
        self.assertEqual(self.capture(900100,'Lance Effect 17.','enUS','frFR'),b'Cast Aura 17.')
        self.lua.execute(b'fakeRecords[900101].frFR.auraDescription=nil')
        self.assertIsNone(self.capture(900100,'Lance Effect 17.','enUS','frFR'))

    def test_cycles_and_missing_source_fail(self):
        self.lua.execute(b"records(900100,'$@spelldesc900101','$@spelldesc900101'); records(900101,'$@spelldesc900100','$@spelldesc900100')")
        self.assertIsNone(self.capture(900100,'Anything'))
        self.lua.execute(b"records(900100,'Valeur $s1.','Value $s1.');fakeRecords[900100].frFR.description=nil")
        self.assertIsNone(self.capture(900100,'Valeur 17.'))

    def test_authored_source_template_can_capture_when_it_matches(self):
        self.lua.execute(b"records(900100,'Valeur $s1.','Value $s1.');fakeRecords[900100].frFR.originalFields=nil")
        self.assertEqual(self.capture(900100,'Valeur 17.'),b'Value 17.')
        self.assertIsNone(self.capture(900100,'Texte different 17.'))

    def test_names_resolve_by_id_in_each_locale(self):
        self.lua.execute(b'''records(900100,'$@spellname900101 / $s1.','$s1 / $@spellname<900101>.');
            local original=ForeverRosettaStoneDB.GetSpellName
            ForeverRosettaStoneDB.GetSpellName=function(self,id,locale)
                if id==900101 then return locale=='frFR' and 'Nom' or 'Name' end
                return original(self,id,locale)
            end
            C_Spell={GetSpellName=function() error('No reverse name lookup') end}''')
        self.assertEqual(self.capture(900100,'Nom / 17.'),b'17 / Name.')
        self.lua.execute(b'ForeverRosettaStoneDB.GetSpellName=function() return nil end')
        self.assertIsNone(self.capture(900100,'Nom / 17.'))

    def test_numeric_expression_result_never_requires_its_operands(self):
        self.lua.execute(b'''records(900100,'Gain ${$AP*0.3+$SPH*0.1}, duree $d.',
            'Gain ${$AP*0.3+$SPH*0.1} for $d.');
            local function forbidden() error('No character calculation') end
            UnitLevel=forbidden;UnitStat=forbidden;GetSpellBonusDamage=forbidden;GetSpellBonusHealing=forbidden
            C_Traits={GetConfigsByType=forbidden}''')
        for value in (17,31):
            self.assertEqual(self.capture(900100,f'Gain {value}, duree 12 sec.'),f'Gain {value} for 12 sec.'.encode())

    def test_displayed_duration_does_not_require_duration_rules(self):
        self.lua.execute(b"records(900100,'Pendant $d.','For $d.');ForeverRosettaStoneDB.GetSpellRules=function() error('No duration rules') end")
        for seconds in (18,21,24):
            self.assertEqual(self.capture(900100,f'Pendant {seconds} sec.'),f'For {seconds} sec.'.encode())

    def test_same_locale_keeps_native_values_without_reconstruction(self):
        self.assertEqual(self.capture(970,'Live hotfix 123.','frFR','frFR'),b'Live hotfix 123.')

    def test_secret_or_nontext_native_values_are_rejected(self):
        self.lua.execute(b"assert(addon:TranslateLiveSpellDescription(970,'enUS',{secret=true})==nil)")


if __name__=='__main__':
    unittest.main()
