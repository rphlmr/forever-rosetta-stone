"""Verify the opt-in local tooltip collector preserves complete, labelled evidence."""

import unittest
import json
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]


class TooltipCheckTests(unittest.TestCase):
    def test_explicit_clear_stops_collection_and_preserves_other_addon_settings(self):
        self.lua.execute('''
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            ForeverRosettaStoneSettings={locale='frFR'}
            SlashCmdList.ROSETTATOOLTIPCHECK('cible cleanup')
            local previous=RosettaTooltipCheckData.runs[1]
            SlashCmdList.ROSETTATOOLTIPCHECK('clear')
            assert(previous.stoppedReason=='manual clear')
            assert(RosettaTooltipCheckData.schemaVersion==1 and #RosettaTooltipCheckData.runs==0)
            frame.OnEvent(frame,'UNIT_AURA','player')
            assert(#RosettaTooltipCheckData.runs==0,'Inactive collector must stay empty')
            assert(ForeverRosettaStoneSettings.locale=='frFR')
            SlashCmdList.ROSETTATOOLTIPCHECK('cible fresh')
            assert(#RosettaTooltipCheckData.runs==1)
            assert(RosettaTooltipCheckData.runs[1]~=previous)
        ''')

    def test_talent_next_frame_capture_keeps_the_actual_late_purchase_footer(self):
        fixture = json.loads((ROOT / 'tests/fixtures/tooltip-campaign/1.60.1.70938-frFR.json').read_text())
        run = next(r for r in fixture['runs'] if r['run'] == 13)
        sample = next(s for s in run['samples'] if s['details']['entityID'] == 1326159)
        details = sample['details']

        def to_lua(value):
            if isinstance(value, dict):
                return self.lua.table_from({int(k) if k.isdigit() else k: to_lua(v) for k, v in value.items()})
            if isinstance(value, list):
                return self.lua.table_from([to_lua(v) for v in value])
            return value

        self.lua.globals().talentData = to_lua(details['data'])
        self.lua.globals().talentInfo = to_lua(details['processingInfo']['values']['1'])
        self.lua.globals().talentVisible = to_lua(details['visible'])
        self.lua.execute('''
            local pending, count = {}, 5
            C_Timer = {After = function(_, callback) pending[#pending+1] = callback end}
            local tip = {
                GetPrimaryTooltipData = function() return talentData end,
                GetProcessingTooltipInfo = function() return talentInfo end,
                NumLines = function() return count end,
                GetLeftLine = function(_, index)
                    return {GetText = function() return talentVisible[index].left.values[1] end}
                end,
            }
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('cible talents')
            hooks[1](tip, talentData)
            local samples = RosettaTooltipCheckData.runs[1].samples
            assert(#samples == 1 and #samples[1].details.visible == 5)
            count = #talentVisible
            assert(#pending == 1)
            pending[1]()
            assert(#samples == 2 and samples[2].details.phase == 'nextFrame')
            assert(#samples[2].details.visible == #talentVisible)
            assert(samples[2].details.visible[count].left.values[1] == talentVisible[count].left.values[1])
            hooks[1](tip, talentData)
            local before = #samples
            SlashCmdList.ROSETTATOOLTIPCHECK('stop')
            pending[2]()
            assert(#samples == before, 'A deferred hover must not leak into a stopped run')
        ''')

    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.execute('''
            messages, hooks, auraCalls = {}, {}, 0
            print = function(text) messages[#messages+1] = text end
            SlashCmdList = {}
            frame = {RegisterEvent = function() end, SetScript = function(self, key, value) self[key] = value end}
            CreateFrame = function() return frame end
            GetTime = function() return 100 end
            time = GetTime
            GetLocale = function() return 'frFR' end
            GetBuildInfo = function() return '1.60.1', '70938' end
            UnitLevel = function(unit) return unit == 'party1' and 60 or 19 end
            UnitStat = function() return 10, 20 end
            UnitAttackPower = function() return 5, 0, 0 end
            GetSpellBonusHealing = function() return 17 end
            GetSpellBonusDamage = function() return 17 end
            InCombatLockdown = function() return false end
            canaccessallvalues = function(value) return not (type(value) == 'table' and value.secret) end
            Enum = {TooltipDataType = {Item = 0, Spell = 1, Unit = 2, UnitAura = 7}}
            TooltipDataProcessor = {AddTooltipPostCall = function(kind, callback) hooks[kind] = callback end}
            C_Spell = {
                RequestLoadSpellData = function() end,
                GetSpellInfo = function(id) return {spellID = id} end,
                GetSpellDescription = function() return 'Rendered description', nil, 0, false end,
            }
            C_Item = {
                RequestLoadItemDataByID = function() end,
                GetItemInfo = function(id) return 'Item', 'item:' .. id, nil, 4 end,
                GetItemStats = function() return {stat = 8} end,
            }
            aura = {spellId = 777, auraInstanceID = 12, points = {}, duration = 15, sourceUnit = 'party1'}
            C_UnitAuras = {
                GetAuraDataByIndex = function(unit, index, filter)
                    auraCalls = auraCalls + 1
                    if unit == 'player' and index == 1 and filter == 'HELPFUL' then return aura end
                end,
                GetAuraDataByAuraInstanceID = function() return aura end,
            }
            C_TooltipInfo = {
                GetSpellByID = function(id) return {id = id, lines = {{leftText = 'Spell amount 18'}}} end,
                GetItemByID = function(id) return {id = id, lines = {{leftText = 'Item amount 234'}}} end,
                GetUnitAuraByAuraInstanceID = function() return {lines = {{leftText = 'Heals 18 every 3 seconds'}}} end,
            }
            probe = {cases = {spells = {{id = 999, code = 'S99'}},
                items = {{id = 888, code = 'O99'}}, auraSpells = {777}, traitNodes = {}}}
        ''')
        source = (ROOT / 'tools/source-scan/rosetta-tooltip-check/probe.lua').read_text()
        self.lua.execute('assert(loadstring(...))("rosetta-tooltip-check", probe)', source)

    def test_explicit_start_complete_returns_and_distinct_profiles(self):
        self.lua.execute('''
            assert(auraCalls == 0 and RosettaTooltipCheckData == nil)
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            assert(#RosettaTooltipCheckData.runs == 0 and auraCalls == 0)
            SlashCmdList.ROSETTATOOLTIPCHECK('equip')
            local first = RosettaTooltipCheckData.runs[1]
            assert(first.profile == 'equip' and #first.samples == 3)
            local spell = first.samples[1].details.description
            assert(spell.returnCount == 4 and spell.values[2] == '<nil>')
            assert(spell.values[3] == 0 and spell.values[4] == false)
            local captured = first.samples[3].details
            assert(captured.aura.values[1].sourceUnit == 'party1')
            assert(captured.casterLevel.values[1] == 60)
            assert(captured.tooltip.values[1].lines[1].leftText == 'Heals 18 every 3 seconds')
            aura.points[1] = 55
            frame.OnEvent(frame, 'UNIT_AURA', 'player')
            assert(next(captured.aura.values[1].points) == nil, 'Earlier snapshots must not mutate')
            SlashCmdList.ROSETTATOOLTIPCHECK('stop')
            local count, calls = #first.samples, auraCalls
            frame.OnEvent(frame, 'UNIT_AURA', 'player')
            hooks[0](nil, {id = 888})
            assert(#first.samples == count and auraCalls == calls)
            SlashCmdList.ROSETTATOOLTIPCHECK('zero')
            assert(#RosettaTooltipCheckData.runs == 2 and first.profile == 'equip')
        ''')

    def test_hover_has_no_field_or_depth_truncation_and_preserves_errors(self):
        self.lua.execute('''
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('equip')
            local data = {id = 888, points = {}, restricted = {secret = true}}
            for i = 1, 150 do data['field' .. i] = i end
            data.deep = {}; local cursor = data.deep
            for i = 1, 20 do cursor.child = {}; cursor = cursor.child end
            cursor.value = 73
            data.self = data
            hooks[0]({GetPrimaryTooltipData = function() error('Injected API error') end}, data)
            local samples = RosettaTooltipCheckData.runs[1].samples
            local record = samples[#samples].details
            assert(record.data.field150 == 150 and record.data.self == '<cycle>')
            assert(record.data.restricted == '<restricted>')
            cursor = record.data.deep
            for i = 1, 20 do cursor = cursor.child end
            assert(cursor.value == 73)
            assert(record.primaryData.status == 'error' and record.primaryData.error:find('Injected API error'))
            assert(record.processingInfo.status == 'missing API')
        ''')

    def test_unit_profile_records_unit_api_returns_on_hover(self):
        self.lua.execute('''
            CORPSE = 'Cadavre'
            UnitCreatureType = function() return 'Humanoïde' end
            UnitIsDead = function() return true end
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('unites')
            local run = RosettaTooltipCheckData.runs[1]
            assert(run.profile == 'unites' and #run.samples == 0, 'The unit profile makes no direct calls')
            hooks[2]({GetUnit = function() return 'Pillard', 'mouseover' end}, {guid = 'Creature-1'})
            local record = run.samples[1].details
            assert(record.dataType == 'Unit' and record.unit.corpseLabel == 'Cadavre')
            local creatureType = record.unit.apis.UnitCreatureType
            assert(creatureType.returnCount == 1 and creatureType.values[1] == 'Humanoïde')
            assert(record.unit.apis.UnitIsDead.values[1] == true)
            assert(record.unit.apis.UnitGUID.status == 'missing API')
        ''')

    def test_existing_invalid_saved_data_is_not_overwritten(self):
        self.lua.execute('''
            RosettaTooltipCheckData = {schemaVersion = 9, preserved = true}
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('equip')
            assert(RosettaTooltipCheckData.schemaVersion == 9 and RosettaTooltipCheckData.preserved)
            assert(auraCalls == 0)
        ''')

    def test_targeted_hovers_capture_dependencies_and_character_state_without_direct_inventory(self):
        self.lua.execute('''
            probe.cases.api = {globals = {'SPELL_REAGENTS'}}
            SPELL_REAGENTS = 'Composants : '
            GetShapeshiftFormID = function() return 3 end
            C_TradeSkillUI = {GetRecipeSchematic = function(id, recraft)
                assert(id == 999 and recraft == false)
                return {recipeID = id, reagentSlotSchematics = {}}
            end}
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('cible forme-chat')
            local run = RosettaTooltipCheckData.runs[1]
            assert(run.profile == 'cible' and run.label == 'forme-chat' and #run.samples == 0)
            hooks[1](nil, {id = 999, lines = {{leftText = 'Spell'}}})
            local sample = run.samples[1]
            assert(sample.context.form.values[1] == 3 and sample.details.entityID == 999)
            assert(run.globals.SPELL_REAGENTS == SPELL_REAGENTS and sample.details.globals == nil)
            assert(sample.details.dependencies['C_TradeSkillUI.GetRecipeSchematic']['999, false'].status == 'ok')
            assert(sample.details.dependencies['C_Spell.GetSpellPowerCost']['999'].status == 'missing API')
            SlashCmdList.ROSETTATOOLTIPCHECK('stop')
            hooks[1](nil, {id = 999})
            assert(#run.samples == 1 and run.stoppedReason == 'manual stop')
        ''')

    def test_targeted_aura_hover_resolves_spell_from_instance_instead_of_tooltip_id(self):
        self.lua.execute('''
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            SlashCmdList.ROSETTATOOLTIPCHECK('cible aura')
            hooks[7]({GetProcessingTooltipInfo = function()
                return {getterName = 'GetUnitAuraByAuraInstanceID', getterArgs = {'player', 12}}
            end}, {id = 12, type = 7, lines = {{leftText = 'Aura'}}})
            local details = RosettaTooltipCheckData.runs[1].samples[1].details
            assert(details.entityID == 777 and details.data.id == 12)
            assert(details.dependencies['C_UnitAuras.GetAuraDataByAuraInstanceID']['"player", 12'].values[1].spellId == 777)
        ''')

    def test_aura_profile_snapshots_existing_and_changed_auras_without_hovers_or_inventory_calls(self):
        self.lua.execute('''
            probe.cases.auraSpells = {}
            UnitSex = function(unit) assert(unit == 'player'); return 2 end
            C_Spell.RequestLoadSpellData = function() error('Unexpected spell inventory scan') end
            C_Item.RequestLoadItemDataByID = function() error('Unexpected item inventory scan') end
            frame.OnEvent(frame, 'ADDON_LOADED', 'rosetta-tooltip-check')
            assert(auraCalls == 0)
            SlashCmdList.ROSETTATOOLTIPCHECK('auras')
            local run = RosettaTooltipCheckData.runs[1]
            assert(run.profile == 'auras' and #run.samples == 1)
            local first = run.samples[1].details
            assert(first.aura.values[1].spellId == 777 and first.byInstance.values[1].auraInstanceID == 12)
            assert(first.unitSex.values[1] == 2)
            assert(first.tooltipGetter == 'C_TooltipInfo.GetUnitAuraByAuraInstanceID')
            assert(first.tooltipArguments[1] == 'player' and first.tooltipArguments[2] == 12
                and first.tooltipArguments.n == 2)
            assert(first.tooltip.status == 'ok' and first.casterLevel.values[1] == 60)
            hooks[0](nil, {id = 888})
            assert(#run.samples == 1, 'Unrelated hover data must not enter the aura campaign')
            aura.points[1] = 55
            frame.OnEvent(frame, 'UNIT_AURA', 'player')
            assert(#run.samples == 2 and run.samples[2].details.aura.values[1].points[1] == 55)
            assert(next(first.aura.values[1].points) == nil)
            SlashCmdList.ROSETTATOOLTIPCHECK('stop')
            local count, calls = #run.samples, auraCalls
            frame.OnEvent(frame, 'UNIT_AURA', 'player')
            assert(#run.samples == count and auraCalls == calls)
        ''')


if __name__ == '__main__':
    unittest.main()
