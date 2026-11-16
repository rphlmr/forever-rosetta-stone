"""Debug picks retain real captured API context and survive unsupported getters."""
import copy
import json
from pathlib import Path
import sys
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/source-scan'))
from audit_tooltip_hovers import restore


class DebugPickContextTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.units = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/context-recapture-frFR-70938.json').read_text()))
        cls.auras = restore(json.loads((ROOT / 'tests/fixtures/tooltip-campaign/auras-1.60.1.70938-enUS.json').read_text()))

    def lua_value(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k.encode() if isinstance(k, str) else k: self.lua_value(v) for k, v in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.lua_value(v) for v in value])
        return value.encode() if isinstance(value, str) else value

    def prepare(self, aura=False, female=False, item=False):
        self.lua = LuaRuntime(encoding=None)
        run = self.auras['runs'][0] if aura else self.units['runs'][0 if item else 1]
        sample = run['samples'][-1] if aura else run['samples'][0] if item else next(s for s in run['samples']
            if s['details'].get('unit', {}).get('apis', {}).get('UnitRace', {}).get('values', {}).get(3) == (4 if female else 1))
        details, context = copy.deepcopy(sample['details']), sample['context']
        if item:
            details['data'] = details['calls']['C_TooltipInfo.GetItemByID']['117']['values'][1]
        self.expected_level = context['level']['values'][1]
        calls = copy.deepcopy(details.get('calls', details.get('dependencies', {})))
        fixture = self.lua.execute((ROOT / 'tests/lua/support/client-api-fixture.lua').read_bytes())
        player = fixture.Key(b'player').decode()
        for field, api in (('sex', 'UnitSex'), ('faction', 'UnitFactionGroup'), ('race', 'UnitRace'),
                           ('class', 'UnitClass'), ('level', 'UnitLevel'), ('attackPower', 'UnitAttackPower'),
                           ('powerType', 'UnitPowerType')):
            if field in context:
                calls.setdefault(api, {}).setdefault(player, context[field])
        for field, api in (('time', 'GetTime'), ('form', 'GetShapeshiftFormID'),
                           ('stealth', 'IsStealthed'), ('healingBonus', 'GetSpellBonusHealing')):
            if field in context:
                calls.setdefault(api, {})[''] = context[field]
        for school, response in context['damageBySchool'].items():
            calls.setdefault('GetSpellBonusDamage', {})[str(school)] = response
        calls['GetBuildInfo'], calls['GetLocale'] = {'': run['build']}, {'': run['locale']}
        unit = details.get('unit', {})
        token = unit.get('token', {}).get('values', {}).get(2)
        if token:
            key = fixture.Key(token.encode()).decode()
            for api, response in unit['apis'].items():
                calls.setdefault(api, {})[key] = response
        fixture.Install(self.lua_value({'calls': calls}), self.lua_value({'strict': True}))
        self.lua.globals().Recorded = self.lua_value(details)
        self.lua.globals().RecordedTypes = self.lua_value(run['tooltipTypes'])
        self.lua.execute(b'''
            canaccessallvalues=function(...)
                for i=1,select('#',...) do
                    local v=select(i,...)
                    if type(v)=='table' and v.restricted then return false end
                end
                return true
            end
            Enum={TooltipDataType=RecordedTypes}
            addon={preferences={}}
            assert(loadfile('ForeverRosettaStone/diagnostics/diagnostics.lua'))('FRS',addon)
            addon.IsDebugPicking=function() return true end
            addon.GetTooltipInputMode=function() return 'fixture' end
            addon.RefreshDebugPickedList=function() end
            local function Return(response)
                if not response or response.status~='ok' then error('No readable captured frame return') end
                local values={}
                for i=1,response.returnCount do
                    if response.values[i]~='<nil>' then values[i]=response.values[i] end
                end
                return unpack(values,1,response.returnCount)
            end
            source={IsForbidden=function() return false end,GetName=function() return 'RecordedTooltip' end,
                GetPrimaryTooltipData=function() return Recorded.data end,
                GetPrimaryTooltipInfo=function() return Return(Recorded.primaryInfo) end,
                GetProcessingTooltipInfo=function() return Return(Recorded.processingInfo) end,
                GetUnit=function() return Return(Recorded.unit and Recorded.unit.token) end,
                GetItem=function() return Return(Recorded.item) end,
                GetSpell=function() return Return(Recorded.spell) end,
                NumLines=function() return #Recorded.data.lines end,
                GetLeftLine=function(_,i) return {GetText=function() return Recorded.data.lines[i].leftText end} end,
                GetRightLine=function(_,i) return {GetText=function() return Recorded.data.lines[i].rightText end} end}
            capture=function()
                addon:RecordDebugSurface(source,'tooltip','captured','tooltip',Recorded.data)
                assert(not addon.debugPicker.captureError,addon.debugPicker.captureError)
                return addon.debugPicker.byID['tooltip:captured']
            end
        ''')
        return details

    def context(self):
        entry = self.lua.globals().capture()
        self.assertIsNotNone(entry[b'data'])
        return entry[b'tooltipEvidence'][b'replayContext']

    def test_player_pick_retains_actual_sex_faction_race_and_unit_returns(self):
        self.prepare()
        context = self.context()
        self.assertEqual(context[b'status'], b'captured')
        self.assertEqual(context[b'player'][b'UnitSex'][b'values'][1], 2)
        self.assertEqual(context[b'player'][b'UnitFactionGroup'][b'values'][1], b'Alliance')
        self.assertEqual(context[b'player'][b'UnitRace'][b'values'][3], 1)
        self.assertEqual(context[b'unitSex'][b'values'][1], 2)
        self.lua.execute(b'UnitSex=function() error("Unit changed after capture") end')
        self.assertEqual(context[b'unitSex'][b'values'][1], 2)

    def test_aura_pick_keeps_actual_instance_getter_and_caster_level(self):
        self.prepare(aura=True)
        context = self.context()
        self.assertEqual(context[b'status'], b'captured')
        self.assertEqual(context[b'aura'][b'instanceID'], 27)
        self.assertEqual(context[b'aura'][b'spellID'], 6074)
        self.assertEqual(context[b'aura'][b'byInstance'][b'values'][1][b'auraInstanceID'], 27)
        self.assertEqual(context[b'aura'][b'caster'][b'level'][b'values'][1], self.expected_level)

    def test_picked_female_unit_does_not_inherit_the_male_players_sex(self):
        self.prepare(female=True)
        context = self.context()
        self.assertEqual(context[b'player'][b'UnitSex'][b'values'][1], 2)
        self.assertEqual(context[b'unitSex'][b'values'][1], 3)

    def test_unavailable_caster_level_does_not_fall_back_to_player_level(self):
        self.prepare(aura=True)
        # Fault injection changes caster availability, not the recorded aura payload.
        self.lua.execute(b'UnitLevel=function() error("Unit no longer available") end')
        context = self.context()
        self.assertEqual(context[b'status'], b'partial')
        self.assertEqual(context[b'aura'][b'caster'][b'level'][b'status'], b'error')
        self.assertIsNone(context[b'aura'][b'caster'][b'level'][b'values'])

    def test_item_lookups_use_the_captured_item_identity(self):
        self.prepare(item=True)
        context = self.context()
        self.assertEqual(context[b'item'][b'id'], 117)
        self.assertEqual(context[b'item'][b'info'][b'status'], b'ok')
        self.assertEqual(context[b'item'][b'stats'][b'status'], b'ok')

    def test_missing_and_throwing_aura_apis_keep_native_payload_and_mark_partial(self):
        for mutation in (b'C_UnitAuras=nil',
                         b'C_UnitAuras.GetAuraDataByAuraInstanceID=function() error("Unsupported target") end',
                         b'C_UnitAuras.GetAuraDataByAuraInstanceID=function() return nil end'):
            with self.subTest(mutation=mutation):
                self.prepare(aura=True)
                self.lua.execute(mutation)
                context = self.context()
                self.assertEqual(context[b'status'], b'partial')
                self.assertGreater(len(context[b'issues']), 0)
                self.assertEqual(self.lua.globals().addon[b'debugPicker'][b'byID'][b'tooltip:captured'][b'data'][b'id'], 6074)

    def test_api_lookup_errors_are_isolated_from_other_capture_calls(self):
        self.prepare(aura=True)
        self.lua.execute(b'C_Spell=setmetatable({},{__index=function() error("Unavailable API member") end})')
        context = self.context()
        self.assertEqual(context[b'calls'][b'C_Spell.GetSpellInfo'][1][b'result'][b'status'], b'lookup error')
        self.assertEqual(context[b'aura'][b'byInstance'][b'status'], b'ok')

    def test_restricted_required_values_are_marked_without_dereferencing_them(self):
        self.prepare()
        self.lua.execute(b'UnitSex=function() return {restricted=true} end')
        context = self.context()
        self.assertEqual(context[b'status'], b'partial')
        self.assertEqual(context[b'player'][b'UnitSex'][b'values'][1], b'<restricted>')

    def test_extra_lookup_budget_keeps_the_full_native_payload(self):
        self.prepare(aura=True)
        # Fault-derived oversized input; these injected IDs are not native evidence.
        self.lua.execute(b'''
            for i=1,50 do Recorded.data.lines[#Recorded.data.lines+1]={spellID=900000+i} end
        ''')
        context = self.context()
        self.assertEqual(context[b'status'], b'partial')
        self.assertEqual(len(context[b'calls'][b'C_Spell.GetSpellInfo']), 32)
        self.assertEqual(len(self.lua.globals().addon[b'debugPicker'][b'byID'][b'tooltip:captured'][b'data'][b'lines']), 53)


if __name__ == '__main__':
    unittest.main()
