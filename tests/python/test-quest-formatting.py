"""Exercise quest substitutions with target locale and live objective data."""

import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

class QuestFormattingTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            addon = { locale = 'enUS' }
            function addon:GetTargetLocale() return self.locale end
            function addon:BeginBenchmarkSample() end
            function addon:EndBenchmarkSample() end
            function GetLocale() return 'frFR' end
            function UnitName() return 'Rosetta' end
            function UnitClass() return 'Mage', 'MAGE' end
            function UnitRace() return 'Humaine', 'Human' end
            function UnitSex() return 3 end
            C_QuestLog = {
                GetQuestObjectives = function(id)
                    if id == 95317 then return { { numRequired = 7 }, { numRequired = 0 } } end
                end,
            }
        """)
        source = (ROOT / 'ForeverRosettaStone/quests/quest-data.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)
        self.addon = self.lua.globals().addon

    def format(self, text, quest_id=95317):
        return self.addon.FormatQuestText(self.addon, text, quest_id)

    def test_unavailable_text_does_not_block_native_fallback(self):
        for text in (None, '', ' \t\n'):
            with self.subTest(text=text):
                self.assertIsNone(self.format(text))
        self.assertEqual(self.format('  Available text.  '), '  Available text.  ')

    def test_dialogue_matches_full_sentence_gender_branches(self):
        self.lua.execute("""
            addon.locale = 'frFR'
            function GetLocale() return 'enUS' end
            ForeverRosettaStoneDB = {
                GetQuestDialogue = function(_, _, _, locale)
                    local text = locale == 'enUS'
                        and '$gWelcome, sir. Need help?:Hello! Need help?;$b$bFollow me.'
                        or '$gBonjour, monsieur. Besoin d’aide ?:Bonjour ! Besoin d’aide ?;$b$bSuivez-moi.'
                    return {{key = 'greeting', stage = 'gossip', text = text}}
                end,
            }
        """)
        source = (ROOT / 'ForeverRosettaStone/quests/quest-dialogue.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)
        self.assertEqual(self.addon.MatchQuestDialogue(self.addon, 32, None, 'gossip', 'Hello! Need help?\n\nFollow me.'),
                         'Bonjour ! Besoin d’aide ?\n\nSuivez-moi.')
        self.lua.execute("function UnitSex() return 2 end")
        self.assertEqual(self.addon.MatchQuestDialogue(self.addon, 32, None, 'gossip', 'Welcome, sir. Need help?\n\nFollow me.'),
                         'Bonjour, monsieur. Besoin d’aide ?\n\nSuivez-moi.')

    def test_dialogue_renders_player_tokens_before_localized_characters(self):
        self.lua.execute("""
            addon.locale = 'zhCN'
            function GetLocale() return 'enUS' end
            ForeverRosettaStoneDB = {
                GetQuestDialogue = function(_, _, _, locale)
                    local text = locale == 'enUS' and 'Hello, $N. You are a $c.'
                        or '$N，你是一名$c。'
                    return {{key = 'greeting', stage = 'gossip', text = text}}
                end,
            }
        """)
        source = (ROOT / 'ForeverRosettaStone/quests/quest-dialogue.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)
        self.assertEqual(self.addon.MatchQuestDialogue(self.addon, 32, None, 'gossip', 'Hello, Rosetta. You are a Mage.'),
                         'Rosetta，你是一名法师。')
        self.assertEqual(self.format('$Notice $b下一段'), '$Notice \n下一段')

    def test_unmapped_summary_objective_stays_native(self):
        self.lua.execute("""
            addon.locale = 'frFR'
            function addon:GetQuestLabel() return 'Terminé' end
            ForeverRosettaStoneDB = {
                GetQuest = function() return { title = 'Quest', summary = 'Apporter les lettres.' } end,
                GetQuestSource = function(_, id, locale)
                    if id == 900002 and locale == 'enUS' then return { summary = 'Deliver the letters.' } end
                end,
            }
            function GetLocale() return 'enUS' end
            objective = { type = 'log', text = 'Deliver the letters.', numFulfilled = 0, numRequired = 1 }
            C_QuestLog.GetQuestObjectives = function() return { objective } end
        """)
        self.lua.execute("ForeverRosettaStoneDB.GetQuestSource = function() error('source lookup') end")
        lines = self.addon.GetProgressLines(self.addon, 900002)
        self.assertEqual(lines[1].native, 'Deliver the letters.')
        self.assertEqual(lines[1].translated, 'Deliver the letters.')
        self.lua.execute("objective.finished = true")
        self.assertEqual(self.addon.GetProgressLines(self.addon, 900002)[1].translated,
                         'Deliver the letters.')
        self.lua.execute("objective.finished = false; objective.text = 'Letters: 1/3'")
        self.assertEqual(self.addon.GetProgressLines(self.addon, 900002)[1].translated, 'Letters: 1/3')
        self.lua.execute("objective.text = 'Deliver the letters.'; function GetLocale() return 'frFR' end")
        self.assertEqual(self.addon.GetProgressLines(self.addon, 900002)[1].translated, 'Deliver the letters.')
        self.assertEqual(self.addon.GetProgressLines(self.addon, 900003)[1].translated, 'Deliver the letters.')

    def test_quest_page_omits_only_progress_identical_to_its_summary(self):
        self.lua.execute("""
            function QuestUtils_DecorateQuestText(_, text) return text end
            function addon:GetQuestLabel() return 'Description' end
        """)
        source = (ROOT / 'ForeverRosettaStone/quests/quest-page.lua').read_text()
        self.lua.execute("assert(loadstring(...))('addon', addon)", source)
        entry = self.lua.table_from({
            'questID': 900002, 'title': 'Quest', 'objectives': 'Apporter les lettres.',
            'progress': 'Apporter les lettres.', 'description': 'Description',
        })
        sections = self.addon.GetQuestPageSections(self.addon, entry)
        self.assertEqual(sections[2].text, 'Apporter les lettres.')
        self.assertEqual(sections[3].text, '')
        for progress in ['Apporter les lettres. (Terminé)', 'Lettres : 1/3', 'Un autre objectif.']:
            entry.progress = progress
            self.assertEqual(self.addon.GetQuestPageSections(self.addon, entry)[3].text, progress)

    def test_a_new_threat_uses_translated_objectives_and_live_counts(self):
        catalog = load_catalog(ROOT, 'quests', ids={'quests': ['170']})
        quest = catalog['catalogs']['quests']['170']['locales']['enUS']
        self.lua.execute("""
            ForeverRosettaStoneDB = { GetQuest = function() return { title = 'A New Threat', objectiveLines = {} } end }
            C_QuestLog.GetQuestObjectives = function() return {
                { type = 'monster', text = 'Trogg Mâcheroc : 0/6 personnages tués', numFulfilled = 0, numRequired = 6 },
                { type = 'monster', text = 'Trogg Mâcheroc forcené : 3/6 personnages tués', numFulfilled = 3, numRequired = 6 },
            } end
        """)
        record = self.lua.table_from({'title': quest['title']})
        record.objectiveLines = self.lua.table_from([
            self.lua.table_from(line) for line in quest['objectiveLines']
        ])
        self.lua.globals().ForeverRosettaStoneDB.GetQuest = lambda *_: record
        lines = self.addon.GetProgressLines(self.addon, 170)
        self.assertEqual(lines[1].translated, '0/6 Rockjaw Trogg slain')
        self.assertEqual(lines[2].translated, '3/6 Burly Rockjaw Trogg slain')

    def test_target_names_are_used_for_every_locale(self):
        expected = {
            'enUS': ('Mage', 'Human'),
            'deDE': ('Magierin', 'Mensch'), 'esES': ('Maga', 'Humana'),
            'esMX': ('Maga', 'Humana'), 'frFR': ('Mage', 'Humaine'),
            'itIT': ('Maga', 'Umana'), 'ptBR': ('Maga', 'Humana'),
            'ruRU': ('Маг', 'Человек'), 'koKR': ('마법사', '인간'),
            'zhCN': ('法师', '人类'), 'zhTW': ('法師', '人類'),
            'csCZ': ('Mágyně', 'Člověk'), 'daDK': ('Magiker', 'Menneske'),
            'hrHR': ('Maga', 'Čovjek'), 'plPL': ('Magini', 'Człowiek'),
            'svSE': ('Magiker', 'Människa'), 'trTR': ('Büyücü', 'İnsan'),
            'ukUA': ('Магиня', 'Людина'),
        }
        for locale, (class_name, race_name) in expected.items():
            with self.subTest(locale=locale):
                self.addon.locale = locale
                self.assertEqual(self.format('{class} <race> $N'), f'{class_name} {race_name} Rosetta')

    def test_live_amounts_zero_missing_and_unrelated_tokens(self):
        self.assertEqual(self.format('$1oa/$2oa'), '7/0')
        self.assertIsNone(self.format('$1oa/$2oa/$3oa $123s1 $B$name'))
        self.assertIsNone(self.format('$1oa', 94902))
        self.assertIsNone(self.format('$1oa', None))

    def test_unresolved_slash_forms_preserve_native_text(self):
        self.assertIsNone(self.format('young <fella/lady>'))
        self.assertIsNone(self.format('reputação de <Honrado/Honrada>'))
        self.assertEqual(self.format('<The player nods.>'), '<The player nods.>')

    def test_unknown_identity_preserves_tokens_instead_of_using_french(self):
        self.lua.execute("function UnitClass() return 'Inconnu', 'UNKNOWN' end")
        self.addon.locale = 'daDK'
        self.assertIsNone(self.format('{class} $C'))

    def test_removed_english_locale_does_not_resolve_player_labels(self):
        self.addon.locale = 'enGB'
        self.assertIsNone(self.format('{class} {race}'))

    def test_explicit_source_locale_uses_actual_client_names(self):
        self.lua.execute("function UnitClass() return 'Nom client', 'MAGE' end")
        self.addon.locale = 'daDK'
        self.assertEqual(self.addon.FormatQuestText(self.addon, '$C', 95317, 'frFR'), 'Nom client')

    def test_text_without_objective_tags_does_not_query_quest_log(self):
        self.lua.execute("C_QuestLog.GetQuestObjectives = function() error('unexpected lookup') end")
        self.assertEqual(self.format('Hello $N'), 'Hello Rosetta')

    def test_gender_branches_use_player_sex_for_every_target_locale(self):
        locales = ('enUS', 'deDE', 'esES', 'esMX', 'frFR', 'itIT', 'ptBR', 'ruRU',
                   'koKR', 'zhCN', 'zhTW', 'csCZ', 'daDK', 'hrHR', 'plPL', 'svSE', 'trTR', 'ukUA')
        for locale in locales:
            with self.subTest(locale=locale):
                self.addon.locale = locale
                self.lua.execute('function UnitSex() return 2 end')
                self.assertEqual(self.format('$gSir $N:Lady $N;'), 'Sir Rosetta')
                self.lua.execute('function UnitSex() return 3 end')
                self.assertEqual(self.format('$GSir $N:Lady $N;'), 'Lady Rosetta')
        self.lua.execute('function UnitSex() return 1 end')
        self.assertIsNone(self.format('$gSir:Lady;'))
        self.assertEqual(self.format('$gSir:Lady. Next;'), '$gSir:Lady. Next;')

    def test_adjacent_breaks_and_unverified_plural_remain_distinct(self):
        self.assertEqual(self.format('$B$BProve. $olitem:items;'), '\n\nProve. $olitem:items;')

    def test_offer_amount_does_not_match_native_gender_template(self):
        self.lua.execute("""
            function GetQuestID() return 94902 end
            function GetObjectiveText() return 'Madame, récupérez 12 objets.' end
            ForeverRosettaStoneDB = {
                GetQuestSource = function(_, id, locale)
                    if id == 94902 and locale == 'frFR' then
                        return { summary = '$gMonsieur:Madame;, récupérez $1oa objets.' }
                    end
                end,
            }
        """)
        self.lua.execute("ForeverRosettaStoneDB.GetQuestSource = function() error('source lookup') end")
        self.assertIsNone(self.format('Count $1oa', 94902))

    def test_offer_amount_does_not_match_native_summary(self):
        self.lua.execute("""
            function GetQuestID() return 94902 end
            function GetObjectiveText() return 'Mage, récupérez 12 objets (12).' end
            ForeverRosettaStoneDB = {
                GetQuestSource = function(_, id, locale)
                    if id ~= 94902 then return nil end
                    if locale == 'frFR' then
                        return { summary = '$C, récupérez $1oa objets ($1oa).' }
                    end
                end,
            }
        """)
        self.lua.execute("ForeverRosettaStoneDB.GetQuestSource = function() error('source lookup') end")
        self.assertIsNone(self.format('Count $1oa', 94902))
        self.assertIsNone(self.format('Count $1oa', 95318))
        self.lua.execute("function GetObjectiveText() return 'Mage, récupérez 12 objets (13).' end")
        self.assertIsNone(self.format('Count $1oa', 94902))
        self.lua.execute("function GetObjectiveText() return 'Mage, récupérez 12 objets (12)!' end")
        self.assertIsNone(self.format('Count $1oa', 94902))

    def test_offer_amount_does_not_match_english_source(self):
        self.lua.execute("""
            function GetQuestID() return 94902 end
            function GetObjectiveText() return 'Mage: bring 4 crystals.' end
            ForeverRosettaStoneDB = {
                GetQuestSource = function(_, id, locale)
                    if id == 94902 and locale == 'enUS' then
                        return { summary = '$C: bring $1oa crystals.' }
                    end
                end,
            }
        """)
        self.lua.execute("ForeverRosettaStoneDB.GetQuestSource = function() error('source lookup') end")
        self.assertIsNone(self.format('$1oa', 94902))

    def test_reputation_standing_does_not_match_source_objective(self):
        self.lua.execute("""
            FACTION_STANDING_LABEL4 = 'Neutre'
            FACTION_STANDING_LABEL5 = 'Amical'
            ForeverRosettaStoneDB = {
                GetQuest = function() return { title = 'Quest', objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Faction: {standing} / {current}/{required}' },
                } } end,
                GetQuestSource = function() return { objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Ligue : {standing} / Amical {current}/{required}' },
                } } end,
            }
            C_QuestLog.GetQuestObjectives = function() return {
                { type = 'reputation', text = 'Ligue : Neutre / Amical 2/3', numFulfilled = 2, numRequired = 3 },
            } end
        """)
        self.lua.execute("ForeverRosettaStoneDB.GetQuestSource = function() error('source lookup') end")
        expected = {
            'enUS': 'Neutral', 'deDE': 'Neutral', 'esES': 'Neutral',
            'esMX': 'Neutral', 'frFR': 'Neutre', 'itIT': 'Neutrale', 'ptBR': 'Tolerado',
            'ruRU': 'Равнодушие', 'koKR': '중립적', 'zhCN': '中立', 'zhTW': '中立',
            'csCZ': 'Neutrální', 'daDK': 'Neutral', 'hrHR': 'Neutralan', 'plPL': 'Neutralny',
            'svSE': 'Neutral', 'trTR': 'Tarafsız', 'ukUA': 'Байдужість',
        }
        for locale, standing in expected.items():
            with self.subTest(locale=locale):
                self.addon.locale = locale
                lines = self.addon.GetProgressLines(self.addon, 8260)
                self.assertEqual(lines[1].translated, 'Ligue : Neutre / Amical 2/3')

    def test_reputation_unknown_or_ambiguous_standing_keeps_native(self):
        self.lua.execute("""
            FACTION_STANDING_LABEL4 = 'Neutre'
            FACTION_STANDING_LABEL5 = 'Neutre'
            ForeverRosettaStoneDB = {
                GetQuest = function() return { title = 'Quest', objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Faction: {standing}' },
                } } end,
                GetQuestSource = function() return { objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Ligue : {standing}' },
                } } end,
            }
            nativeText = 'Ligue : Neutre'
            C_QuestLog.GetQuestObjectives = function() return {
                { type = 'reputation', text = nativeText },
            } end
        """)
        self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated, 'Ligue : Neutre')
        self.lua.execute("FACTION_STANDING_LABEL5 = 'Amical'; nativeText = 'Ligue : Inconnu'")
        self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated, 'Ligue : Inconnu')
        self.lua.execute("nativeText = 'Other : Amical'")
        self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated, 'Other : Amical')
        self.lua.execute("ForeverRosettaStoneDB.GetQuestSource = function() return nil end; nativeText = 'Ligue : Amical'")
        self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated, 'Ligue : Amical')

    def test_reputation_english_source_stays_native(self):
        self.lua.execute("""
            function GetLocale() return 'enUS' end
            FACTION_STANDING_LABEL4 = 'Neutral'
            FACTION_STANDING_LABEL5 = 'Friendly'
            ForeverRosettaStoneDB = {
                GetQuest = function() return { title = 'Quest', objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Faction : {standing} / Amical' },
                } } end,
                GetQuestSource = function() return { objectiveLines = {
                    { index = 1, type = 'reputation', text = '{standing} / Friendly The League of Arathor' },
                } } end,
            }
            C_QuestLog.GetQuestObjectives = function() return {
                { type = 'reputation', text = 'Neutral / Friendly The League of Arathor' },
            } end
        """)
        self.addon.locale = 'frFR'
        self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated,
                         'Neutral / Friendly The League of Arathor')

    def test_each_french_client_standing_stays_native(self):
        self.lua.execute("""
            ForeverRosettaStoneDB = {
                GetQuest = function() return { title = 'Quest', objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Faction: {standing}' },
                } } end,
                GetQuestSource = function() return { objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Ligue : {standing} / Amical' },
                } } end,
            }
            C_QuestLog.GetQuestObjectives = function() return {
                { type = 'reputation', text = nativeText },
            } end
        """)
        french = ('Détesté', 'Hostile', 'Inamical', 'Neutre', 'Amical', 'Honoré', 'Révéré', 'Exalté')
        english = ('Hated', 'Hostile', 'Unfriendly', 'Neutral', 'Friendly', 'Honored', 'Revered', 'Exalted')
        self.addon.locale = 'enUS'
        for rank, (source, target) in enumerate(zip(french, english), 1):
            self.lua.globals()[f'FACTION_STANDING_LABEL{rank}'] = source
        for source, target in zip(french, english):
            with self.subTest(source=source):
                self.lua.globals().nativeText = f'Ligue : {source} / Amical'
                self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated,
                                 f'Ligue : {source} / Amical')

    def test_female_client_standing_stays_native(self):
        self.lua.execute("""
            FACTION_STANDING_LABEL1 = 'Détesté'
            FACTION_STANDING_LABEL1_FEMALE = 'Haïe'
            ForeverRosettaStoneDB = {
                GetQuest = function() return { title = 'Quest', objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Faction: {standing}' },
                } } end,
                GetQuestSource = function() return { objectiveLines = {
                    { index = 1, type = 'reputation', text = 'Ligue : {standing}' },
                } } end,
            }
            C_QuestLog.GetQuestObjectives = function() return {
                { type = 'reputation', text = 'Ligue : Haïe' },
            } end
        """)
        self.assertEqual(self.addon.GetProgressLines(self.addon, 8260)[1].translated, 'Ligue : Haïe')


if __name__ == '__main__':
    unittest.main()
