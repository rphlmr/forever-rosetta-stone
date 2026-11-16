"""Prove matrix expectations are independent displayed values, with honest gaps."""
import unittest
from unittest.mock import patch
from live_spell_fixture import FixtureUnavailable, make_fixture


def record(english, french):
    return {'locales':{locale:{'name':'Spell', 'description':text,
        'translationMetadata':{'fields':{'description':{'origin':'original'}}}}
        for locale,text in [('enUS',english),('frFR',french)]},
        'tooltipData':{'effects':[{'index':0,'basePoints':9999}]}}


class LiveSpellFixtureTests(unittest.TestCase):
    def test_display_values_are_distinct_from_static_rules_and_vary_by_profile(self):
        spells={'1':record('Hit $s1 / $s2.','Frappe $s1 / $s2.')}
        first=make_fixture(spells,1,'frFR',source='enUS')
        second=make_fixture(spells,1,'frFR','modified',source='enUS')
        self.assertNotIn('9999',first['native'])
        self.assertNotEqual(first['native'],second['native'])
        spells['1']['tooltipData']={}
        self.assertEqual(first,make_fixture(spells,1,'frFR',source='enUS'))
        self.assertEqual(first['fixture'],'synthetic displayed values')

    def test_owned_paragraphs_and_escaped_percent_signs_match_client_formatting(self):
        spells = {'1': record('Hit $s1%%. \n\n  Keep this paragraph.',
                              'Frappe $s1%%. \n\n  Conserver ce paragraphe.')}
        fixture = make_fixture(spells, 1, 'frFR', source='enUS')
        self.assertIn('\n\n', fixture['native'])
        self.assertIn('\n\n', fixture['expected'])
        self.assertIn('%.', fixture['expected'])
        self.assertNotIn('%%', fixture['expected'])
        self.assertNotIn(' \n', fixture['expected'])
        self.assertNotIn('\n ', fixture['expected'])

    def test_numeric_formulas_are_opaque_even_without_operands(self):
        spells={'1':record('Gain ${$AP/0+$unknown} for $d.','Gain ${$AP/0+$unknown} pendant $d.')}
        fixture=make_fixture(spells,1,'frFR',source='enUS')
        self.assertNotIn('$',fixture['expected'])
        self.assertIn(' sec.',fixture['expected'])

    def test_rank_alignment_preserves_reordered_values(self):
        spells={'1':record('A $m2 B $m4.','B $m2 A $m1.')}
        fixture=make_fixture(spells,1,'frFR',source='enUS')
        numbers=__import__('re').findall(r'\d+',fixture['native'])
        self.assertEqual(fixture['expected'],f'B {numbers[1]} A {numbers[0]}.')

    def test_authored_source_is_usable_but_missing_text_stays_a_gap(self):
        spells={'1':record('Hit $s1.','Frappe $s1.')}
        spells['1']['locales']['enUS']['translationMetadata']['fields']['description']['origin']='ai'
        self.assertIn('Hit ',make_fixture(spells,1,'frFR',source='enUS')['native'])
        del spells['1']['locales']['enUS']['description']
        with self.assertRaisesRegex(FixtureUnavailable,'missing source'):
            make_fixture(spells,1,'frFR',source='enUS')
        with self.assertRaisesRegex(FixtureUnavailable,'missing target'):
            make_fixture(spells,1,'deDE',source='frFR')

    def test_unknown_grammar_is_a_limitation_and_cycles_fail(self):
        for text in ('$unknown','${oops','${$s1} $s1$s2'):
            spells={'1':record(text,'Valeur $s1.')}
            with self.assertRaises(FixtureUnavailable):
                make_fixture(spells,1,'frFR',source='enUS')
        spells={'1':record('$@spelldesc1','$@spelldesc1')}
        with self.assertRaisesRegex(FixtureUnavailable,'cyclic'):
            make_fixture(spells,1,'frFR',source='enUS')

    def test_ambiguous_or_unbound_fixture_context_is_not_claimed_as_a_pass(self):
        for english,french,message in [
            ('$s1$s2','$s1$s2','adjacent'),
            ('$?s1[A][B]','$?s2[A][B]','shared source predicate'),
            ('$?s1[A][A]','$?s1[B][C]','ambiguous'),
        ]:
            with self.subTest(english=english), self.assertRaisesRegex(FixtureUnavailable,message):
                make_fixture({'1':record(english,french)},1,'frFR',source='enUS')

    def test_expected_text_never_comes_from_production_output(self):
        import id_only_spell_matrix as matrix
        # Mutation: corrupt only production output; the independent matrix must fail it.
        original=matrix.create_description_renderer
        def corrupt(harness):
            original(harness)
            return lambda *args: (b'Wrong output',None,False)
        with patch.object(matrix,'create_description_renderer',side_effect=corrupt):
            report=matrix.run_matrix(locales=['enUS'],ids=[970],profiles=['baseline'])
        failures=[row for row in report['failures'] if row['field']=='description']
        self.assertTrue(failures)
        self.assertEqual(failures[0]['reason'],'mismatch')


if __name__=='__main__': unittest.main()
