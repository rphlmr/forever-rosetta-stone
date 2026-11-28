"""Check the `/frsverify api` capture, its fixture importer and the Lua replay shim end to end."""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_globalstring_ids

IMPORTER = ROOT / 'tools/source-scan/import_client_api_fixture.py'


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


importer = load_module('import_client_api_fixture', IMPORTER)
sampler = load_module('prepare_api_sample', ROOT / 'tools/source-scan/prepare_api_sample.py')

PROBE_MOCKS = '''
    messages, hooks, timers, requested = {}, {}, {}, {}
    print = function(text) messages[#messages+1] = text end
    SlashCmdList = {}
    frame = {RegisterEvent = function() end, SetScript = function(self, key, value) self[key] = value end}
    CreateFrame = function() return frame end
    GetTime = function() return 100 end
    time = GetTime
    GetLocale = function() return 'frFR' end
    GetBuildInfo = function() return '1.60.1', '70938', 'Nov 1 2026', 11508 end
    UnitLevel = function() return 19 end
    UnitStat = function() return 10, 20 end
    UnitAttackPower = function() return 5, 0, 0 end
    GetSpellBonusHealing = function() return 17 end
    GetSpellBonusDamage = function() return 17 end
    InCombatLockdown = function() return false end
    Enum = {TooltipDataType = {Item = 0, Spell = 1, Unit = 2, UnitAura = 7}}
    TooltipDataProcessor = {AddTooltipPostCall = function(kind, callback) hooks[kind] = callback end}
    C_Timer = {After = function(delay, callback) timers[#timers+1] = callback end}
    CORPSE = 'Cadavre'
    C_Spell = {
        IsSpellDataCached = function() return true end,
        RequestLoadSpellData = function(id) requested[#requested+1] = 'spell:' .. id end,
        GetSpellName = function(id) return 'Sort ' .. id end,
        GetSpellDescription = function() return 'Inflige\\n"18" points', nil, 0 end,
    }
    cached = {[1205] = true}
    C_Item = {
        IsItemDataCachedByID = function(id) return cached[id] == true end,
        RequestLoadItemDataByID = function(id) requested[#requested+1] = 'item:' .. id end,
        GetItemInfo = function(id)
            if not cached[id] then return nil end
            return 'Jus de melon', 'item:' .. id, 1, nil, 5
        end,
        GetItemStats = function(link) return {ITEM_MOD_STAMINA_SHORT = 3, link = link} end,
    }
    C_TooltipInfo = {
        GetHyperlink = function(link) return {lines = {{leftText = link}}} end,
        GetItemByID = function(id) error('Tooltip unavailable for ' .. id) end,
    }
    probe = {cases = {spells = {}, items = {}, auraSpells = {}, traitNodes = {}, api = {
        calls = {
            spell = {'C_Spell.GetSpellName', 'C_Spell.GetSpellDescription', 'C_Spell.GetSpellSubtext'},
            item = {'C_Item.GetItemInfo', 'C_TooltipInfo.GetItemByID',
                {api = 'C_Item.GetItemStats', format = 'item:%d'},
                {api = 'C_TooltipInfo.GetHyperlink', format = 'item:%d'}},
            quest = {{api = 'C_TooltipInfo.GetHyperlink', format = 'quest:%d'}},
            none = {'GetBuildInfo', 'GetLocale'},
        },
        ids = {spell = {598}, item = {1205, 118}, quest = {95317}},
        globals = {'CORPSE', 'MISSING_GLOBAL'},
    }}}
'''


def python_value(value):
    if hasattr(value, 'items'):
        return {key: python_value(child) for key, child in value.items()}
    return value


class ClientApiFixtureTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute(PROBE_MOCKS)
        source = (ROOT / 'tools/source-scan/rosetta-tooltip-check/probe.lua').read_text()
        self.lua.execute('assert(loadstring(...))("rosetta-tooltip-check", probe)', source)
        self.lua.execute('''
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('api')
        ''')

    def run_record(self):
        return self.lua.eval('RosettaTooltipCheckData.runs[1]')

    def test_api_recipe_call_preserves_false_argument(self):
        self.lua.execute('''
            local count = 0
            C_TradeSkillUI = {GetRecipeSchematic = function(id, recraft)
                assert(id == 598 and recraft == false)
                count = count + 1
                return {recipeID = id, reagentSlotSchematics = {}}
            end}
            table.insert(probe.cases.api.calls.spell, {api = 'C_TradeSkillUI.GetRecipeSchematic', suffix = {false}})
            cached[118] = true
            frame.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)
            local response = RosettaTooltipCheckData.runs[1].samples[1].details.calls
                ['C_TradeSkillUI.GetRecipeSchematic']['598, false']
            assert(count == 1 and response.status == 'ok' and response.values[1].recipeID == 598)
        ''')

    def test_exact_calls_preserve_captured_trait_entry_and_rank_arguments(self):
        self.lua.execute('''
            C_TooltipInfo.GetTraitEntry = function(entry, rank)
                assert(entry == 130559 and rank == 2)
                return {type = 1, id = 15275, lines = {}}
            end
            probe.cases.api.exactCalls = {{api = 'C_TooltipInfo.GetTraitEntry', args = {130559, 2}}}
            cached[118] = true
            frame.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)
            local response = RosettaTooltipCheckData.runs[1].samples[1].details.calls
                ['C_TooltipInfo.GetTraitEntry']['130559, 2']
            assert(response.status == 'ok' and response.values[1].id == 15275)
        ''')

    def test_api_run_waits_for_uncached_items_then_captures_once(self):
        self.lua.execute('''
            local run = RosettaTooltipCheckData.runs[1]
            assert(#requested == 1 and requested[1] == 'item:118', 'Only uncached data is requested')
            assert(#run.samples == 0 and #timers == 1)
            hooks[0](nil, {id = 1205})
            assert(#run.samples == 0, 'Hovers are not recorded by the api profile')
            cached[118] = true
            frame.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)
            assert(run.stoppedReason == 'api complete' and #run.samples == 1)
            timers[1]()
            assert(#run.samples == 1, 'The timeout never captures twice')
            local api = run.samples[1].details
            assert(api.calls['C_Item.GetItemInfo']['118'].values[1] == 'Jus de melon')
            assert(api.calls['C_TooltipInfo.GetHyperlink']['"quest:95317"'].status == 'ok')
            assert(api.calls['C_Spell.GetSpellSubtext']['598'].status == 'missing API')
            assert(api.calls.GetLocale[''].values[1] == 'frFR')
            assert(api.globals.MISSING_GLOBAL == '<nil>' and #api.pendingAtCapture == 0)
        ''')

    def test_api_run_waits_for_items_linked_from_tooltips(self):
        self.lua.execute('''
            RETRIEVING_ITEM_INFO = "Récupération des informations de l'objet"
            local linked = false
            C_TooltipInfo.GetItemByID = function(id)
                return {lines = {{leftText = 'Objet ' .. id}, {leftText = linked and 'Composant' or RETRIEVING_ITEM_INFO}}}
            end
            local run = RosettaTooltipCheckData.runs[1]
            cached[118] = true
            frame.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)
            assert(#run.samples == 0 and run.settleRounds == 1 and #timers == 2, 'A loading row delays the capture')
            timers[1]()
            assert(#run.samples == 0, 'The load timeout never interrupts the settle wait')
            linked = true
            timers[2]()
            assert(run.stoppedReason == 'api complete' and #run.samples == 1)
            local details = run.samples[1].details
            assert(details.settleRounds == 1)
            assert(details.calls['C_TooltipInfo.GetItemByID']['118'].values[1].lines[2].leftText == 'Composant')
        ''')

    def test_timeout_records_what_was_still_loading(self):
        self.lua.execute('''
            timers[1]()
            local run = RosettaTooltipCheckData.runs[1]
            assert(run.stoppedReason == 'api timeout')
            assert(run.samples[1].details.pendingAtCapture[1] == 'item:118')
            assert(run.samples[1].details.calls['C_Item.GetItemInfo']['118'].values[1] == '<nil>')
        ''')

    def test_failed_load_event_is_preserved_as_false(self):
        self.lua.execute('''
            frame.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, false)
            local details = RosettaTooltipCheckData.runs[1].samples[1].details
            assert(details.loadResults.item[118] == false)
            assert(details.calls['C_Item.GetItemInfo']['118'].values[1] == '<nil>')
        ''')

    def test_import_and_replay_preserve_returns_errors_and_missing_apis(self):
        self.lua.execute("cached[118] = true; frame.OnEvent(frame, 'ITEM_DATA_LOAD_RESULT', 118, true)")
        saved = python_value(self.lua.eval('RosettaTooltipCheckData'))
        with tempfile.TemporaryDirectory() as directory:
            capture = Path(directory) / 'rosetta-tooltip-check.lua'
            capture.write_text('\nRosettaTooltipCheckData = ' + importer.to_lua(saved) + '\n', encoding='utf-8')
            output = Path(directory) / 'fixture.lua'
            command = [sys.executable, str(IMPORTER), '--capture', str(capture), '--run', '1', '--output', str(output)]
            subprocess.run(command, check=True, capture_output=True)
            refused = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(refused.returncode, 0)
            self.assertIn('already exists', refused.stderr)

            replay = LuaRuntime()
            replay.execute('''
                local path = ...
                local Fixture = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
                local capture = Fixture.Load(path)
                assert(capture.build == '1.60.1.70938' and capture.locale == 'frFR')
                local env = Fixture.Install(capture, {target = {}})
                local name, link, quality, missing, level = env.C_Item.GetItemInfo(118)
                assert(name == 'Jus de melon' and quality == 1 and missing == nil and level == 5)
                assert(select('#', env.C_Item.GetItemInfo(118)) == 5, 'Return count is replayed')
                assert(select('#', env.C_Spell.GetSpellDescription(598)) == 3)
                assert(env.C_Spell.GetSpellDescription(598) == 'Inflige\\n"18" points')
                assert(env.C_Item.GetItemStats('item:1205').ITEM_MOD_STAMINA_SHORT == 3)
                assert(env.C_Spell.GetSpellSubtext == nil, 'A missing client API stays missing')
                local ok, message = pcall(env.C_TooltipInfo.GetItemByID, 118)
                assert(not ok and message:find('Tooltip unavailable for 118'), 'Errors are replayed')
                local first = env.C_TooltipInfo.GetHyperlink('quest:95317')
                first.lines[1].leftText = 'mutated'
                assert(env.C_TooltipInfo.GetHyperlink('quest:95317').lines[1].leftText == 'quest:95317')
                local strictOk, strictMessage = pcall(env.C_Item.GetItemInfo, 999)
                assert(not strictOk and strictMessage:find('No captured C_Item.GetItemInfo%(999%)'))
                assert(select('#', env.GetBuildInfo()) == 4 and env.GetLocale() == 'frFR')
                assert(env.CORPSE == nil, 'Captured GlobalStrings are not replayed; tests read the catalog')
                local loose = Fixture.Install(capture, {target = {}, strict = false})
                assert(select('#', loose.C_Item.GetItemInfo(999)) == 0)
            ''', str(output))

    def test_globals_report_compares_capture_with_the_catalog(self):
        report = importer.compare_globals({'SPELL_PASSIVE': 'Passive', 'SPELL_TOTEMS': 'Outils\u00a0: ',
                                           'ARMOR': 'Blindage', 'NOT_A_REAL_KEY': 'x', 'CORPSE': '<nil>'}, 'frFR')
        statuses = {row['key']: row['status'] for row in report['differences']}
        self.assertEqual(report['counts']['identical'], 1)
        self.assertEqual(statuses, {'SPELL_TOTEMS': 'export escapes', 'ARMOR': 'different',
                                    'NOT_A_REAL_KEY': 'not in catalog', 'CORPSE': 'absent in client'})

    def test_catalog_sample_is_stable_and_extends_the_probe_inventory(self):
        ids = list(range(1, 1000))
        self.assertEqual(sampler.sample(ids, 10, 'seed', 'item'), sampler.sample(ids, 10, 'seed', 'item'))
        self.assertNotEqual(sampler.sample(ids, 10, 'seed', 'item'), sampler.sample(ids, 10, 'other', 'item'))
        source = sampler.render({'item': [1205, 7], 'map': []}, ['CORPSE', 'SPELL_PASSIVE'],
                                {'seed': 'seed', 'perKind': 2}, 30)
        lua = LuaRuntime()
        lua.execute('probe = {}')
        lua.execute('assert(loadfile("tools/source-scan/rosetta-tooltip-check/cases.lua"))("rosetta-tooltip-check", probe)')
        lua.execute('assert(loadstring(...))("rosetta-tooltip-check", probe)', source)
        lua.execute('''
            local api = probe.cases.api
            local items, count = {}, 0
            for _, id in ipairs(api.ids.item) do items[id] = (items[id] or 0) + 1; count = count + 1 end
            assert(items[1205] == 1 and items[7] == 1 and items[5861] == 1, 'Sampled IDs merge without duplicates')
            local globals = {}
            for _, key in ipairs(api.globals) do globals[key] = (globals[key] or 0) + 1 end
            assert(globals.CORPSE == 1 and globals.SPELL_PASSIVE == 1 and api.loadTimeout == 30)
        ''')
        with tempfile.TemporaryDirectory() as directory:
            counts = sampler.prepare(Path(directory), 3, 'seed', 30)
            toc = (Path(directory) / 'rosetta-tooltip-check/rosetta-tooltip-check.toc').read_text().splitlines()
            self.assertEqual(toc[-3:], ['cases.lua', 'api-sample.lua', 'probe.lua'])
            self.assertEqual(counts['item']['sampled'], 3)
            self.assertEqual(counts['globals']['sampled'], counts['globals']['catalog'])

    def test_catalog_globals_match_the_client_rendering(self):
        count = sum(1 for path in (ROOT / 'catalogs/globalstrings').glob('*.json') if path.stem.isdigit())
        lua = install_globalstring_ids(LuaRuntime())
        indexed, opened = lua.execute('''
            -- Count only catalog opens and fail if the loader probes a gap.
            local existing, opened = {}, 0
            for _, id in ipairs(FRS_TestGlobalStringIDs) do existing[id] = true end
            local open = io.open
            io.open = function(path, mode)
                local id = tonumber(path:match("^catalogs/globalstrings/(%d+)%.json$"))
                if id then
                    assert(existing[id], "Unexpected GlobalString file probe " .. path)
                    opened = opened + 1
                end
                return open(path, mode)
            end
            local F = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
            assert(F.CatalogGlobal("SPELL_PASSIVE", "frFR") == "Passive")
            assert(F.CatalogGlobal("SPELL_TOTEMS", "frFR"):sub(-1) == " ", "The export \\\\32 renders as a space")
            assert(F.CatalogGlobal("NOT_A_REAL_KEY", "frFR") == nil)
            local ok = pcall(F.InstallGlobals, "frFR", {"NOT_A_REAL_KEY"}, {})
            assert(not ok, "Missing catalog values are errors, never silent")
            local target = F.InstallGlobals("frFR", {"CORPSE"}, {})
            assert(target.CORPSE == "Cadavre")
            local reloaded = assert(loadfile("tests/lua/support/client-api-fixture.lua"))()
            return reloaded.CatalogGlobalCount(), opened
        ''')
        self.assertEqual(indexed, count, 'Every catalog record is indexed')
        self.assertEqual(opened, count, 'The runtime opens each existing GlobalString only once')

    def test_fixture_limit_keeps_explicit_test_ids(self):
        keep = importer.explicit_ids(ROOT / 'tools/source-scan/rosetta-tooltip-check/cases.lua')
        self.assertIn(5861, keep['item'])
        self.assertIn(7418, keep['spell'])
        calls = {'C_Item.GetItemNameByID': {str(i): {'status': 'ok'} for i in (1, 2, 3, 5861)},
                 'C_TooltipInfo.GetHyperlink': {f'"item:{i}"': {'status': 'ok'} for i in (1, 2, 5861)}}
        limited = importer.limit_calls(calls, 2, keep)
        self.assertEqual(sorted(limited['C_Item.GetItemNameByID']), ['1', '2', '5861'])
        self.assertEqual(sorted(limited['C_TooltipInfo.GetHyperlink']), ['"item:1"', '"item:2"', '"item:5861"'])
        self.assertEqual(importer.decode_export_escapes('Outils\u00a0:\\32 \\"%s\\" \\\\21 \\21'),
                         'Outils\u00a0:  "%s" \\21 \x15')

    def test_importer_rejects_unfinished_or_non_api_runs(self):
        self.lua.execute("SlashCmdList.ROSETTATOOLTIPCHECK('stop'); SlashCmdList.ROSETTATOOLTIPCHECK('unites')")
        saved = python_value(self.lua.eval('RosettaTooltipCheckData'))
        with self.assertRaisesRegex(ValueError, 'did not finish'):
            importer.build_fixture(saved, 1, 'hash')
        with self.assertRaisesRegex(ValueError, 'not an api run'):
            importer.build_fixture(saved, 2, 'hash')
        with self.assertRaisesRegex(ValueError, 'does not exist'):
            importer.build_fixture(saved, 3, 'hash')

    def test_probe_and_shim_argument_keys_match(self):
        probe = (ROOT / 'tools/source-scan/rosetta-tooltip-check/probe.lua').read_text()
        shim = (ROOT / 'tests/lua/support/client-api-fixture.lua').read_text()
        body = lambda text, start: text[text.index(start):].split('\nend\n', 1)[0]
        self.assertEqual(body(probe, 'local function ArgumentKey(...)').split('\n', 1)[1],
                         body(shim, 'function Fixture.Key(...)').split('\n', 1)[1])


if __name__ == '__main__':
    unittest.main()
