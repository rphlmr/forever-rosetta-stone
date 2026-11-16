"""Entity effects must use catalog prose and the client's displayed values."""
import unittest

from database_harness import ROOT
import json
import re

from live_value_harness import LiveValueHarness


class SpellLiveValueTests(LiveValueHarness, unittest.TestCase):
    def test_unresolved_client_tokens_remain_symbolic_and_cannot_change_identity(self):
        self.lua.globals().records(900073, 'Valeur $w pendant $d.'.encode(), b'Value $w for $d.')
        self.assertEqual(self.capture(900073, 'Value $w for 12 sec.', 'enUS', 'frFR'),
                         'Valeur $w pendant 12 sec.'.encode())
        self.assertIsNone(self.capture(900073, 'Value $unknown for 12 sec.', 'enUS', 'frFR'))
        self.lua.globals().records(900074, b'Valeur $s2.', b'Value $s1.')
        self.assertIsNone(self.capture(900074, 'Value $s1.', 'enUS', 'frFR'))
        self.lua.globals().records(900075, b'Valeur ${$w/10}.1.', b'Value ${$w/10}.1.')
        self.assertEqual(self.capture(900075, 'Value $w/10${$w/10}.1.', 'enUS', 'frFR'),
                         b'Valeur $w/10${$w/10}.1.')
        self.assertIsNone(self.capture(900075, 'Value $unknown${$w/10}.1.', 'enUS', 'frFR'))
        self.lua.globals().records(900076, b'2 puis $w $lpoint:points;.', b'2 then $w $lpoint:points;.')
        self.assertIsNone(self.capture(900076, '2 then $w points.', 'enUS', 'frFR'))

    def test_magnitude_units_preserve_the_displayed_quantity(self):
        self.lua.globals().records(900072, 'Valeur $s1.'.encode(), b'Value $s1.')
        self.assertEqual(self.capture(900072, 'Value 77 million.', 'enUS', 'frFR'),
                         'Valeur 77\u202f000\u202f000.'.encode())
        self.assertEqual(self.capture(900072, 'Valeur 1,25 million.'), b'Value 1,250,000.')
        self.assertEqual(self.capture(900072, 'Valeur 77 |7million:millions; de.'), b'Value 77,000,000.')
        self.assertIsNone(self.capture(900072, 'Value 77 unknown.', 'enUS', 'frFR'))

    def test_numeric_conditional_ranges_keep_endpoints_precision_and_target_grammar(self):
        self.lua.globals().records(900071,
            'Inflige $?s1[de ${$m1*1}.1 à ${$M1*1}.1][$s1] points.'.encode(),
            b'Deals $?s1[${$m1*1}.1 to ${$M1*1}.1][$s1] damage.')
        self.assertEqual(self.capture(900071, 'Inflige de 1.5 à 2.5 points.'), b'Deals 1.5 to 2.5 damage.')
        self.assertEqual(self.capture(900071, 'Deals 1.5 to 2.5 damage.', 'enUS', 'frFR'),
                         'Inflige de 1,5 à 2,5 points.'.encode())
        self.assertIsNone(self.capture(900071, 'Deals 1.5 to unknown damage.', 'enUS', 'frFR'))

    def test_hearthstone_uses_live_bind_location_and_the_reported_typed_row(self):
        # Reported in-game on 2026-11-14: type=44, spellID=8690, and this exact text.
        native = ("Utiliser : Vous renvoie à Vallée de Comté-du-Nord. Parlez à l'aubergiste d'une autre ville "
                  "pour changer votre foyer. (1 h de recharge.)")
        self.lua.execute('GetBindLocation=function() return "Vallée de Comté-du-Nord" end'.encode())
        result=self.lua.globals().item(6948,8690,44,native.encode(),b'frFR',b'enUS')
        self.assertEqual(result[0],('Use: Returns you to Northshire Valley. Speak to an Innkeeper in a '
                                   'different place to change your home location. (1 Hr Cooldown)').encode())
        self.lua.execute(b'GetBindLocation=function() return "Another inn" end')
        self.assertIsNone(self.lua.globals().item(6948,8690,44,native.encode(),b'frFR',b'enUS')[0])
        self.lua.execute(b'GetBindLocation=nil')
        self.assertIsNone(self.capture(8690,native))

    def test_numeric_families_require_displayed_numbers_without_recalculation(self):
        for token in ('$H','$N','$R','$R1','$c','$rad#','$1','$2','$3826'):
            with self.subTest(token=token):
                self.lua.globals().records(900051,('Valeur '+token+'.').encode(),('Value '+token+'.').encode())
                self.assertEqual(self.capture(900051,'Valeur 2,50.'),b'Value 2.50.')
                self.assertIsNone(self.capture(900051,'Valeur Someone.'))
        self.lua.execute(b"records(900051,'Rayon $rad.', 'Radius $rad#.')")
        self.assertEqual(self.capture(900051,'Rayon 12.'),b'Radius 12.')

    def test_modified_slots_and_attached_suffixes_keep_their_identity(self):
        self.assertEqual(self.capture(1219153,'Les attaques infligées par cette cible rendent 4 % de points de vie.',
                                      field='auraDescription'),b'Hits from this target restore 4% health.')
        self.lua.execute(b"records(900052,'A $s~1, B $s1.', 'B $s1, A $s~1.')")
        self.assertEqual(self.capture(900052,'A 10, B 20.'),b'B 20, A 10.')
        self.lua.execute(b"records(900052,'Toutes les $t2secondi, $s2x.', 'Every $t2seconds, $s2x.')")
        self.assertEqual(self.capture(900052,'Toutes les 3secondi, 2x.'),b'Every 3seconds, 2x.')
        self.lua.execute(b"records(900052,'Valeur $unsupported.', 'Value $unsupported.')")
        self.assertIsNone(self.capture(900052,'Valeur 10nsupported.'))

    def test_nested_plural_forms_use_visible_quantity_and_target_locale_rules(self):
        # The maintained French 408255 template puts $m2 inside its plural form.
        native='Vos 2 prochaines incantations de Feu stellaire bénéficient d’un temps d’incantation réduit de 1,50 s.'
        self.assertEqual(self.capture(408255,native,field='auraDescription'),
                         b'Your next 2 Starfire casts have 1.50 sec reduced cast time.')
        self.assertEqual(self.capture(408255,'Your next 2 Starfire casts have 1.50 sec reduced cast time.',
                                      'enUS','frFR','auraDescription'),native.replace(' 2 ', ' 2\u00a0').replace(' s.', '\u00a0s.').encode())
        self.lua.execute(b"records(900053,'$s1 $lpoint:point;.', '$s1 $lpoint:points;.')")
        self.assertEqual(self.capture(900053,'0 point.'),b'0 points.')
        self.assertEqual(self.capture(900053,'2 point.'),b'2 points.')
        self.assertIsNone(self.capture(900053,'1 points.'))
        self.lua.execute(b"records(900053,'$gIl gagne $s1:Elle gagne $s1;', '$gHe gains $s1:She gains $s1;')")
        self.assertEqual(self.capture(900053,'Il gagne 12'),b'He gains 12')

    def test_expansion_blocks_follow_the_native_presence_not_keyboard_state(self):
        self.lua.execute(br'''
            records(900054,'Valeur $s1.$@expandkey[\nDetail ${$PL+1}.]',
                'Value $s1.$@expandkey[\nDetail ${$PL+1}.]')
            IsShiftKeyDown=function() error('Do not infer the captured tooltip state from keyboard state') end
        ''')
        self.assertEqual(self.capture(900054,'Valeur 10.'),b'Value 10.')
        self.assertEqual(self.capture(900054,'Valeur 10.\nDetail 21.'),b'Value 10.\nDetail 21.')
        self.lua.execute(br"records(900054,'$?s1[Oui $s1.]\n[Non $s2.]', '$?s1[Yes $s1.]\n[No $s2.]')")
        self.assertEqual(self.capture(900054,'Non 12.'),b'No 12.')
        self.lua.execute(b"records(900054,'A$@expandkey[B$@expandkey[C]]D$@expandkey[E]',"
                         b"'a$@expandkey[b$@expandkey[c]]d$@expandkey[e]')")
        self.assertEqual(self.capture(900054,'ABD'),b'abd')

    def test_referenced_icons_keep_the_displayed_markup_without_synthesizing_images(self):
        self.lua.execute(b"records(900055,'Premier $@spellicon123, second $@spellicon456.',"
                         b"'Second $@spellicon456, first $@spellicon123.')")
        self.assertEqual(self.capture(900055,'Premier |T111:16|t, second |A:second:16:16|a.'),
                         b'Second |A:second:16:16|a, first |T111:16|t.')
        self.assertEqual(self.capture(900055,'Premier , second .'),b'Second , first .')
        self.assertIsNone(self.capture(900055,'Premier arbitrary text, second |T222:16|t.'))

    def test_unverified_reference_types_and_malformed_sources_stay_native(self):
        for token in ('$@auracaster','$@auradesc123','$@spelltooltip123','$@null','$@spellaura','$$123s1','$%','$l'):
            self.lua.globals().records(900056,token.encode(),token.encode())
            self.assertIsNone(self.capture(900056,'Some displayed text.'))

    def test_collapsed_weapon_skill_matches_the_client_appended_hint(self):
        # Native text reported in-game on 2026-11-14, including the appended hint.
        native=('Vous bénéficiez de 0/5 de maîtrise des Épées à une main.\n\n'
                'Cible de niveau 1 :\nChances de toucher, d’esquiver et de parer : -0,2 %\n'
                'Chances de coup critique : -0,1 %\nPénalité de coup dévié : 100 %\n'
                'Chances de coup dévié : 20 %\n\nMaintenir MAJ pour en savoir plus.')
        expected=('You have 0/5 skill in One-Handed Swords.\n\nLevel 1 target:\n'
                  'Hit, Dodge, and Parry: -0.2%\nCritical Hit: -0.1%\nGlancing Blow Penalty: 100%\n'
                  'Glancing Blow Chance: 20%\n\n|cffBCBCBCHold SHIFT for additional info.|r')
        self.assertEqual(self.capture(1296663,native),expected.encode())
        self.assertIsNone(self.capture(1296663,native.replace('MAJ','unknown modifier')))

    def test_camp_benefits_prune_absent_branches_using_the_displayed_text(self):
        native='Obtention des avantages de camp suivants :\n\nBougie d’encens : Intelligence augmentée de 2.'
        expected=b'Gained the following camp benefits:\n\nIncense Candle: Intellect increased by 2.'
        self.assertEqual(self.capture(1229741,native,field='auraDescription'),expected)
        rows=self.lua.globals().render(1229741,b'aura',native.encode(),b'frFR',b'enUS')
        self.assertEqual(len(rows),2)
        self.assertEqual(rows[2][b'text'],expected)
        native=('Obtention des avantages de camp suivants :\n\nMeule à aiguiser : Force augmentée de 3.'
                '\n\nBougie d’encens : Intelligence augmentée de 2.')
        expected=(b'Gained the following camp benefits:\n\nSharpening Wheel: Strength increased by 3.'
                  b'\n\nIncense Candle: Intellect increased by 2.')
        self.assertEqual(self.capture(1229741,native,field='auraDescription'),expected)

    def test_inline_references_keep_paragraphs_and_icon_lines(self):
        self.lua.execute(br"records(900057,'Avant.\\n\\n$@spellicon123\\nApres $s1.', 'Before.\\n\\n$@spellicon123\\nAfter $s1.')")
        self.assertEqual(self.capture(900057,'Avant.\n\n|T111:16|t\nApres 2.'),
                         b'Before.\n\n|T111:16|t\nAfter 2.')

    def test_pain_real_captured_profiles_keep_total_and_duration(self):
        # Native text from the two retained build-70938 campaign profiles, not reconstructed amounts.
        for total in (149, 126):
            native = f"Un mot des ténèbres qui inflige {total} points de dégâts d'Ombre en 21 sec."
            expected = f'A word of darkness that causes {total} Shadow damage over 21 sec.'
            self.assertEqual(self.capture(970, native), expected.encode())
        self.lua.execute(b"GetSpellBonusDamage=function() error('No power recalculation') end; C_Traits=nil")
        self.assertIn(b'149', self.capture(970, "Un mot des ténèbres qui inflige 149 points de dégâts d'Ombre en 21 sec."))

    def test_recorded_priest_profiles_keep_every_displayed_amount(self):
        fixture=json.loads((ROOT / 'tests/fixtures/priest-damage-periodic-level19.json').read_text())
        for sample in fixture['samples']:
            for code,spell_id in fixture['cases'].items():
                native=sample[code]
                rendered=self.capture(spell_id,native)
                self.assertIsNotNone(rendered,(code,native))
                native_numbers=re.findall(r'\d+',native)
                target_numbers=re.findall(r'\d+',rendered.decode())
                self.assertEqual(native_numbers,target_numbers,(code,rendered))
        direct=json.loads((ROOT / 'tests/fixtures/priest-heal-scaling-70938.json').read_text())
        for sample in direct['samples']:
            rendered=self.capture(direct['spellID'],sample['description'])
            self.assertIsNotNone(rendered)
            self.assertEqual(re.findall(r'\d+',rendered.decode()),[str(sample['minimum']),str(sample['maximum'])])

    def test_food_and_renew_auras_do_not_require_points(self):
        self.assertEqual(self.capture(433, 'Rend 2 points de vie par seconde.',field='auraDescription'),
                         b'Restores 2 health per second.')
        self.assertEqual(self.capture(6074, 'Soigne 18 points de dégâts toutes les 3 secondes.',field='auraDescription'),
                         b'Healing 18 damage every 3 seconds.')

    def test_expressions_are_opaque_and_case_sensitive(self):
        self.lua.execute(b"records(900001,'De ${$m1+($<APRatio>*$apm)} a ${$M1+($<APRatio>*$apm)}.',"
                         b"'From ${$m1+($<APRatio>*$apm)} to ${$M1+($<APRatio>*$apm)}.')")
        self.assertEqual(self.capture(900001, 'De 10,10 a 20,20.'), b'From 10.10 to 20.20.')
        self.assertEqual(self.capture(15275, 'Augmente la durée de votre sort Mot de l’ombre : Douleur de 3 s.'),
                         b'Increases the duration of your Shadow Word: Pain spell by 3 sec.')

    def test_exact_tokens_can_move_and_repeat(self):
        self.lua.execute(b"records(900002,'Premier $s1, second $s2, encore $s1.',"
                         b"'Second $s2, first $s1, again $s1.')")
        self.assertEqual(self.capture(900002, 'Premier 15, second 20, encore 15.'), b'Second 20, first 15, again 15.')
        self.assertIsNone(self.capture(900002, 'Premier 15, second 20, encore 16.'))

    def test_template_boundary_whitespace_matches_normalized_native_text(self):
        self.lua.execute(b"records(900030,'  Valeur $s1.  ','Value $s1.')")
        self.assertEqual(self.capture(900030, 'Valeur 12.'), b'Value 12.')
        self.lua.execute(b"records(900031,'  Texte fixe.  ','Fixed text.')")
        self.assertEqual(self.capture(900031, 'Texte fixe.'), b'Fixed text.')

    def test_index_correspondence_is_general_and_bidirectional(self):
        self.lua.execute(b"records(900003,'A $m8 B $m16 C $m24.', 'C $w11 B $w7 A $w3.')")
        self.assertEqual(self.capture(900003, 'A 10 B 20 C 30.'), b'C 30 B 20 A 10.')
        self.assertEqual(self.capture(900003, 'C 30 B 20 A 10.','enUS','frFR'), b'A 10 B 20 C 30.')
        native='Augmente les dégâts infligés par vos poisons de 30 % et vos chances d’appliquer des poisons de 20 %.'
        self.assertEqual(self.capture(1310703,native),
                         b'Increases the damage of your Poisons by 30% and your chance to apply Poisons by 20%.')
        self.assertEqual(self.capture(1310703,native,field='auraDescription'),
                         b'Increases the damage of your Poisons by 30% and your chance to apply Poisons by 20%.')
        self.lua.execute(b"records(900003,'A $m2 B $m4.', 'B $m2 A $m1.')")
        self.assertEqual(self.capture(900003,'A 10 B 20.'),b'B 20 A 10.')
        self.assertEqual(self.capture(900003,'B 20 A 10.','enUS','frFR'),b'A 10 B 20.')

    def test_decimal_precision_grouping_ranges_and_percent(self):
        self.lua.execute(b"records(900004,'Valeur $s1 %, plage $s2.', 'Value $s1%, range $s2.')")
        self.assertEqual(self.capture(900004,'Valeur 1\u202f234,50 %, plage 1,10-2,20.'),
                         b'Value 1,234.50%, range 1.10-2.20.')
        self.assertEqual(self.capture(900004,'Value 1,234.50%, range 1.10-2.20.','enUS','frFR'),
                         'Valeur 1\u202f234,50 %, plage 1,10-2,20.'.encode())
        self.assertIsNone(self.capture(900004,'Valeur 12 34,50 %, plage 1,10-2,20.'))
        self.lua.execute(b"fakeRecords[900004].esMX=fakeRecords[900004].enUS")
        self.assertEqual(self.capture(900004,'Value 1,234.50%, range 1.10-2.20.','esMX','frFR'),
                         'Valeur 1\u202f234,50 %, plage 1,10-2,20.'.encode())

    def test_numeric_condition_chain_captures_the_whole_result(self):
        self.lua.execute(b"records(900005,'Gain $?$PL<12[3]?$PL<24[8]?$PL<60[45][$1230124s1].',"
                         b"'Grants $?$PL<12[3]?$PL<24[8]?$PL<60[45][$1230124s1].')")
        self.assertEqual(self.capture(900005,'Gain 8.'),b'Grants 8.')

    def test_references_keep_catalog_text_and_their_numeric_owners(self):
        self.lua.execute(b"records(900006,'$@spelldesc900007 Puis $s1.', '$s1 then $@spelldesc900007');"
                         b"records(900007,'Lie $s1.', 'Linked $s1.')")
        self.assertEqual(self.capture(900006,'Lie 20. Puis 10.'),b'10 then Linked 20.')
        self.lua.execute(b"records(900006,'$@spelldesc900006', '$s1.')")
        self.assertIsNone(self.capture(900006,'Anything 20.'))

    def test_text_branches_and_plural_use_target_prose(self):
        self.lua.execute(b"records(900008,'$?s12[Valeur $s1.][Autre $s2.]',"
                         b"'$?s12[Value $s1.][Other $s2.]')")
        self.assertEqual(self.capture(900008,'Autre 12.'),b'Other 12.')
        self.lua.execute(b"records(900009,'$s1 $lpoint:points;.', '$s1 $lpoint:points;.')")
        self.assertEqual(self.capture(900009,'2 points.'),b'2 points.')
        self.assertEqual(self.capture(900009,'1 point.'),b'1 point.')
        self.lua.execute(b"records(900009,'$s1 $lpoint:point;.', '$s1 $lpoint:points;.')")
        self.assertEqual(self.capture(900009,'2 point.'),b'2 points.')

    def test_duration_decimals_and_fixed_numbers_keep_their_roles(self):
        self.lua.execute(b"records(900013,'Duree $d. Fixe 30.', 'Duration $d. Fixed 30.')")
        self.assertEqual(self.capture(900013,'Duree 1,10 sec. Fixe 30.'),b'Duration 1.10 sec. Fixed 30.')
        self.assertIsNone(self.capture(900013,'Duree 1,10 sec. Fixe 31.'))

    def test_gender_uses_client_context_not_foreign_words(self):
        self.lua.execute(b"records(900010,'Valeur $s1.', '$ghis:her; value $s1.')")
        self.assertEqual(self.capture(900010,'Valeur 2.'),b'his value 2.')
        self.lua.execute(b'UnitSex=function() return 3 end')
        self.assertEqual(self.capture(900010,'Valeur 2.'),b'her value 2.')

    def test_unsupported_mismatched_and_ambiguous_inputs_fail_closed(self):
        self.lua.execute(b"records(900011,'Valeur $s1.', 'Value $s1 and $s2.')")
        self.assertIsNone(self.capture(900011,'Valeur 1.'))
        self.lua.execute(b"records(900011,'$s1$s2', '$s1 / $s2')")
        self.assertIsNone(self.capture(900011,'1234'))
        self.lua.execute(b"records(900011,'$?s1[Valeur $s1.][Valeur $s1.]', '$?s1[One $s1.][Two $s1.]')")
        self.assertIsNone(self.capture(900011,'Valeur 1.'))
        self.lua.execute(b"records(900011,'Valeur $unsupported.', 'Value $s1.')")
        self.assertIsNone(self.capture(900011,'Valeur 1.'))

    def test_integration_spell_talent_and_aura_never_use_static_fallback(self):
        g=self.lua.globals()
        for kind in ('spell','talent'):
            rows=g.render(970,kind.encode(),b"Un mot des t\xc3\xa9n\xc3\xa8bres qui inflige 149 points de d\xc3\xa9g\xc3\xa2ts d'Ombre en 21 sec.",b'frFR',b'enUS')
            self.assertEqual(rows[2][b'text'],b'A word of darkness that causes 149 Shadow damage over 21 sec.')
            self.assertEqual(len(rows),2)
            rows=g.render(970,kind.encode(),b"Un mot des tenebres inconnu 149.",b'frFR',b'enUS')
            self.assertEqual(rows[2][b'text'],b'Un mot des tenebres inconnu 149.')
            self.assertEqual(rows[3][b'text'], self.lua.globals().addon.GetIncompleteTranslationNotice(self.lua.globals().addon))
        rows=g.render(433,b'aura','Rend 2 points de vie par seconde.'.encode(),b'frFR',b'enUS')
        self.assertEqual(rows[2][b'text'],b'Restores 2 health per second.')
        self.assertEqual(len(rows),2)

    def test_multiline_spell_and_untyped_talent_descriptions(self):
        self.lua.execute(br'''
            records(900014,'Premier $s1.\nDeuxieme $s2.','Second $s2.\nFirst $s1.')
            for _,kind in ipairs({'spell','talent'}) do
                local rowType=kind=='spell' and 34 or 0
                render(900014,kind,'','frFR','enUS',{
                    {type=13,lineIndex=1,leftText='Name'},
                    {type=rowType,lineIndex=2,leftText='Premier 10.'},
                    {type=rowType,lineIndex=3,leftText='Deuxieme 20.'},
                })
                assert(#rows==2 and rows[2].text=='Second 20.\nFirst 10.')
            end
        ''')

    def test_item_thunderfury_captures_distinct_references_and_duration(self):
        native = ('Chance on hit: Blasts your enemy with lightning, dealing 35 Nature damage and then jumping '
                  'to additional nearby enemies. Each jump reduces that victim\'s Nature resistance by 3. '
                  'Affects 5 targets. Your primary target is also consumed by a cyclone, slowing its attack '
                  'speed by 20% for 12 sec.')
        expected = ('Chances quand vous touchez : Votre ennemi est frappé par la foudre, qui lui inflige 35 '
                    'points de dégâts de Nature avant de sauter vers d’autres ennemis proches. Chaque saut '
                    'réduit de 3 la résistance à la Nature de la victime touchée. Affecte 5 victimes. Votre '
                    'cible est également engloutie par un cyclone, qui ralentit sa vitesse d’attaque de 20% '
                    'pendant 12 sec.')
        self.assertEqual(self.lua.globals().item(19019, 21992, 46, native.encode(), b'enUS', b'frFR')[0],
                         expected.encode())

    def test_item_formula_results_move_without_character_calculation(self):
        self.lua.execute(br'''
            records(900020,'Pendant $d, gain ${$s1*2} puis $123s1.',
                'Gain ${$s1*2}, then $123s1 for $d.')
            ForeverRosettaStoneDB.GetItemRules=function()
                return {effects={{spellID=900020,triggerType=1}}}
            end
            local function forbidden() error('Item effects must not recalculate character values') end
            UnitLevel=forbidden; UnitStat=forbidden; GetSpellBonusDamage=forbidden
            GetSpellBonusHealing=forbidden; C_Traits={GetConfigsByType=forbidden}
            local text=item(900021,900020,45,'Equip: Gain 17, then 4 for 1.10 sec.','enUS','frFR')
            assert(text=='Equip\195\169 : Pendant 1,10 sec, gain 17 puis 4.',tostring(text))
        ''')

    def test_item_unknown_text_keeps_native_without_static_fallback(self):
        self.lua.execute(b'''
            local text,_,incomplete=item(118,439,44,'Use: Unknown healing text 12.','enUS','frFR')
            assert(text==nil and incomplete)
        ''')

    def test_same_language_item_effect_preserves_native_typography(self):
        native='Utiliser : Rend 46\u00a0points de mana en 36 sec. Vous devez rester en position assise pendant que vous buvez.'
        result=self.lua.globals().item(159,430,44,native.encode(),b'frFR',b'frFR')
        self.assertEqual(result[0],native.encode())

    def test_item_ranges_and_cooldown_use_the_displayed_values(self):
        self.lua.execute('''
            local text=item(118,439,44,'Use: Restores 12-34 health. (2 Min Cooldown)','enUS','frFR')
            assert(text=='Utiliser : Rend 12-34 points de vie. (2 min de recharge.)',tostring(text))
            text=item(118,439,44,'Use: Restores 31-47 health. (1 Min Cooldown)','enUS','frFR')
            assert(text=='Utiliser : Rend 31-47 points de vie. (1 min de recharge.)',tostring(text))
            text=item(118,439,44,'Utiliser : Rend 12-34 points de vie. (1,10 sec de recharge.)','frFR','enUS')
            assert(text=='Use: Restores 12-34 health. (1.10 sec Cooldown)',tostring(text))
            text=item(118,439,44,'Use: Restores 12-34 health. (Unknown cooldown)','enUS','frFR')
            assert(text==nil)
        '''.encode())

    def test_item_literal_parentheses_are_part_of_the_owned_description(self):
        self.lua.execute(b'''
            records(900020,'Gain $s1 (personnel).','Gain $s1 (self only).')
            ForeverRosettaStoneDB.GetItemRules=function()
                return {effects={{spellID=900020,triggerType=0}}}
            end
            local text=item(900021,900020,44,'Use: Gain 12 (self only).','enUS','frFR')
            assert(text=='Utiliser : Gain 12 (personnel).',tostring(text))
            records(900020,'Gain $s1 (personnel)','Gain $s1 (self only)')
            text=item(900021,900020,44,'Use: Gain 12 (self only)','enUS','frFR')
            assert(text=='Utiliser : Gain 12 (personnel)',tostring(text))
        ''')

    def test_item_tooltip_keeps_native_row_and_incomplete_status_when_capture_fails(self):
        self.lua.execute(b'''
            for key,value in pairs(addon.englishTooltipFormats) do _G[key]=value end
            local native='Use: Restores 12-34 health.'
            local lines={{type=13,lineIndex=1,leftText='Potion'},
                {type=44,lineIndex=2,spellID=439,leftText=native}}
            render(118,'item','','enUS','frFR',lines)
            assert(#rows==2 and rows[2].text=='Utiliser : Rend 12-34 points de vie.')
            native='Use: Unknown healing text 12-34.'
            lines[2].leftText=native
            render(118,'item','','enUS','frFR',lines)
            assert(#rows==3 and rows[2].text==native)
            assert(rows[3].text=='Some lines are not translated yet.')
        ''')


if __name__ == '__main__':
    unittest.main()
