"""Exercise the native source probe against mocked client APIs in Lua 5.1."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'tools/source-scan/rosetta-source-probe/probe.lua').read_text()


def create():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        clock, requests, output, behavior = 0, {}, {}, {}
        locale, build, combat = 'enUS', '70888', false
        function time() return 1000 + clock end
        function GetTime() return clock end
        function GetLocale() return locale end
        function GetBuildInfo() return '1.60.1', build end
        function InCombatLockdown() return combat end
        function UnitClass() return 'Mage', 'MAGE' end
        function UnitRace() return 'Human', 'HUMAN' end
        function UnitLevel() return 60 end
        function UnitSex() return 2 end
        function print(message) output[#output + 1] = message end
        SlashCmdList = {}
        function CreateFrame()
            local frame = { scripts = {} }
            function frame:RegisterEvent() end
            function frame:SetScript(name, callback) self.scripts[name] = callback end
            probeFrame = frame
            return frame
        end
        function Fire(event, id, success) probeFrame.scripts.OnEvent(probeFrame, event, id, success) end
        function Tick(seconds) clock = clock + seconds; probeFrame.scripts.OnUpdate(probeFrame) end
        C_QuestLog = {
            RequestLoadQuestByID = function(id)
                requests[#requests + 1] = { id = id, clock = clock }
                if behavior[id] == 'requestError' then error('request failed') end
            end,
            GetTitleForQuestID = function(id)
                if behavior[id] == 'readError' then error('read failed') end
                return 'Quest ' .. id
            end,
            GetQuestObjectives = function() return {{ text = '0/6 slain' }} end,
            IsOnQuest = function() return true end,
        }
        C_Spell = {
            RequestLoadSpellData = function(id) requests[#requests + 1] = { id = id, clock = clock } end,
            GetSpellInfo = function() return { name = 'Spell' } end,
            GetSpellDescription = function() return 'Deals 42 damage' end,
            GetSpellSubtext = function() return 'Rank 1' end,
        }
        C_TooltipInfo = { GetHyperlink = function() return { lines = {{ leftText = 'Deals 42 damage' }} } end }
        RosettaSourceProbeQueue = { hash = 'queue1', catalogHash = 'catalog1', profiles = {
            enUS = { jobs = {
                {kind='quests', id=1, fields={'title', 'objectiveLines'}},
                {kind='quests', id=2, fields={'title'}},
                {kind='quests', id=3, fields={'title'}},
                {kind='quests', id=4, fields={'title'}},
                {kind='spells', id=5, fields={'name', 'description'}},
            } },
            frFR = { jobs = {{kind='quests', id=1, fields={'title'}}} },
        } }
    ''')
    load(lua)
    return lua


def load(lua):
    lua.execute('assert(loadstring(...))("rosetta-source-probe")', SOURCE)
    lua.execute('Fire("ADDON_LOADED", "rosetta-source-probe")')


lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='globals', key='FACTION_STANDING_LABEL1', fields={'value'}}}
    secret = {}; function issecretvalue(v) return v == secret end
    FACTION_STANDING_LABEL1 = secret
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    local r = RosettaSourceProbeData.sessions[1].results[1]
    assert(r.status == 'unavailable' and r.values.observation.returns[1].status == 'restricted')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='factions', id=92, fields={'data'}}}
    secret = {}; function issecretvalue(v) return v == secret end
    C_Reputation = { GetFactionDataByID = function(id)
        assert(id == 92); return { name='Faction', rank=3, hidden=secret, nested={flag=false} }
    end }
    function GetFactionInfoByID(id) assert(id == 92); return 'Faction', nil, 3, secret end
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    assert(#requests == 0, 'faction reads must not request server data')
    local r = RosettaSourceProbeData.sessions[1].results[1]
    assert(r.status == 'captured' and r.values.modern.returnCount == 1)
    local f = r.values.modern.returns[1].fields
    assert(f.name.value == 'Faction' and f.rank.value == 3 and f.hidden.status == 'restricted')
    assert(f.nested.fields.flag.status == 'available' and f.nested.fields.flag.value == false)
    assert(r.values.legacy.returnCount == 4 and r.values.legacy.returns[2].status == 'unavailable')
    assert(r.values.legacy.returns[4].status == 'restricted' and r.values.playerLevel.returns[1].value == 60)
    assert(r.values.build == '70888' and r.values.locale == 'enUS')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='factions', id=93, fields={'data'}}}
    C_Reputation = { GetFactionDataByID = function() error('failed') end }
    GetFactionInfoByID = nil
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    local v = RosettaSourceProbeData.sessions[1].results[1].values
    assert(v.modern.status == 'error' and v.legacy.status == 'unavailable')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='items', id=8, fields={'name'}}}
    C_Item = { RequestLoadItemDataByID = function() end, GetItemInfo = function() return 'Item', 'item:8' end }
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('ITEM_DATA_LOAD_RESULT', 8, true)
    local result = RosettaSourceProbeData.sessions[1].results[1]
    assert(result.values.name == 'Item' and result.contextSnapshot == nil)
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='spells', id=5, fields={'name'}, captureContext=1, knownSpellIds={11151,12952}}}
    function UnitStat(unit, index) assert(unit == 'player' and index == 5); return 10, 20, nil, -2 end
    secret = {}; function issecretvalue(v) return v == secret end
    function UnitAttackPower() return 100, 25, -3 end
    function UnitRangedAttackPower() error('restricted API') end
    function GetSpellBonusDamage(school) if school == 3 then return nil end; return school * 10 end
    function GetSpellBonusHealing() return secret end
    C_SpellBook = { IsSpellKnown = function(id) return id == 11151 end }
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('SPELL_DATA_LOAD_RESULT', 5, true)
    local s = RosettaSourceProbeData.sessions[1].results[1].contextSnapshot
    assert(s.locale == 'enUS' and s.build == '70888' and s.unit == 'player')
    assert(s.level[1].value == 60 and s.spirit[2].value == 20 and s.spirit[3].status == 'unavailable')
    assert(s.attackPower[3].value == -3 and s.rangedAttackPower[1].status == 'error')
    assert(s.damageBySchool[2][1].value == 20 and s.damageBySchool[3][1].status == 'unavailable')
    assert(s.spellHealing[1].status == 'restricted' and s.knownSpells[11151][1].value == true)
    assert(s.knownSpells[12952][1].status == 'available' and s.knownSpells[12952][1].value == false)
''')

lua = create()
lua.execute('''
    Tick(0)
    assert(#requests == 0, 'loading must not start collection')
    SlashCmdList.ROSETTASOURCEPROBE('start')
    combat = true; Tick(1); assert(#requests == 0)
    combat = false; Tick(0); assert(#requests == 1)
    Fire('ITEM_DATA_LOAD_RESULT', 1, true)
    Fire('QUEST_DATA_LOAD_RESULT', 999, true)
    assert(#RosettaSourceProbeData.sessions[1].results == 0)
    SlashCmdList.ROSETTASOURCEPROBE('pause')
    Fire('QUEST_DATA_LOAD_RESULT', 1, true)
    Tick(10); assert(#requests == 1, 'pause must prevent new requests')
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    Fire('QUEST_DATA_LOAD_RESULT', 2, false)
    Tick(0.1); assert(#requests == 2, 'requests must be paced')
    Tick(0.1); assert(#requests == 3)
    Tick(10); Fire('QUEST_DATA_LOAD_RESULT', 3, true)
    behavior[4] = 'readError'; Tick(0); Fire('QUEST_DATA_LOAD_RESULT', 4, true)
    Tick(0.2); Fire('SPELL_DATA_LOAD_RESULT', 5, true); Tick(0)
    local session = RosettaSourceProbeData.sessions[1]
    assert(session.results[1].status == 'captured')
    assert(session.results[1].values.objectives[1].text == '0/6 slain')
    assert(session.results[2].status == 'loadFailed')
    assert(session.results[3].status == 'timeout')
    assert(session.results[4].status == 'readError')
    assert(session.results[5].values.descriptionKind == 'rendered')
    assert(session.results[5].values.tooltipKind == 'rendered')
    assert(session.results[5].values.description == 'Deals 42 damage')
    SlashCmdList.ROSETTASOURCEPROBE('report')
    assert(table.concat(output, '\\n'):find('timeout: 1', 1, true))
''')

lua = create()
lua.execute('''
    locale = 'xxXX'; SlashCmdList.ROSETTASOURCEPROBE('start')
    assert(#RosettaSourceProbeData.sessions == 0)
    assert(table.concat(output, '\\n'):find('No queue for locale xxXX', 1, true))
    locale = 'enUS'; SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    Fire('QUEST_DATA_LOAD_RESULT', 1, true); SlashCmdList.ROSETTASOURCEPROBE('pause')
''')
load(lua)
lua.execute('''
    Tick(10); assert(#requests == 1, 'reload must not start collection')
    locale = 'frFR'; SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    Fire('QUEST_DATA_LOAD_RESULT', 1, true); Tick(0)
    assert(#RosettaSourceProbeData.sessions == 2)
''')
load(lua)
lua.execute('''
    locale, build = 'enUS', '99999'; SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    assert(#RosettaSourceProbeData.sessions == 3)
''')
load(lua)
lua.execute('''
    locale, build = 'enUS', '70888'; SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    assert(#RosettaSourceProbeData.sessions == 3)
    assert(requests[#requests].id == 2, 'matching session resumes at its cursor')
    assert(RosettaSourceProbeData.sessions[2].locale == 'frFR')
    assert(RosettaSourceProbeData.sessions[3].build == '99999')
''')
lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='spells', id=5, fields={'name', 'description'}}}
    local ready = false
    C_Spell.GetSpellDescription = function() return ready and 'Deals 42 damage' or '' end
    C_Spell.GetSpellSubtext = function() return ready and 'Rank 2' or '' end
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('SPELL_DATA_LOAD_RESULT', 5, true)
    assert(#RosettaSourceProbeData.sessions[1].results == 0, 'spell text must settle before capture')
    ready = true; Fire('SPELL_TEXT_UPDATE', 5); Tick(0)
    local result = RosettaSourceProbeData.sessions[1].results[1]
    assert(result.values.description == 'Deals 42 damage')
    assert(result.values.subtext == 'Rank 2')
    assert(result.values.textStatus == 'available')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='spells', id=5, fields={'name', 'description'}}}
    C_Spell.GetSpellDescription = function() return '' end
    C_Spell.GetSpellSubtext = function() return nil end
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('SPELL_DATA_LOAD_RESULT', 5, true)
    SlashCmdList.ROSETTASOURCEPROBE('pause'); Tick(1.1)
    local result = RosettaSourceProbeData.sessions[1].results[1]
    assert(result.values.textStatus == 'unavailableAfterSettle')
    assert(result.values.subtext == nil)
    Tick(10); assert(#requests == 1, 'pause must wait for settle and prevent further requests')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeData = { schemaVersion = 999, sessions = {}, sentinel = 'preserve' }
    original = RosettaSourceProbeData
''')
load(lua)
lua.execute('''
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    assert(RosettaSourceProbeData == original and original.sentinel == 'preserve')
    assert(#requests == 0, 'invalid saved data must disable collection')
''')

for saved in (
    "'corrupt'",
    "{schemaVersion=1, sessions='corrupt'}",
    "{schemaVersion=1, sessions={{nextIndex=1, results='corrupt'}}}",
    "{schemaVersion=1, sessions={{nextIndex=0, results={}}}}",
):
    lua = create()
    lua.execute('RosettaSourceProbeData = ' + saved + '; original = RosettaSourceProbeData')
    load(lua)
    lua.execute('''
        SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
        SlashCmdList.ROSETTASOURCEPROBE('pause')
        SlashCmdList.ROSETTASOURCEPROBE('status')
        SlashCmdList.ROSETTASOURCEPROBE('report')
        assert(RosettaSourceProbeData == original and #requests == 0)
    ''')

lua = create()
lua.execute('''
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('QUEST_DATA_LOAD_RESULT', 1, true)
    Tick(7200); assert(#requests == 1, 'two-hour limit must pause new requests')
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0)
    assert(#requests == 2 and requests[2].id == 2, 'restart must resume at the next job')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='spells', id=5, fields={'name'}}}
    C_TooltipInfo.GetHyperlink = function()
        local cyclic = {}; cyclic.self = cyclic
        return { lines = {{leftText='Example', bad=function() end}}, cycle=cyclic }
    end
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('SPELL_DATA_LOAD_RESULT', 5, true); Tick(0)
    local result = RosettaSourceProbeData.sessions[1].results[1]
    assert(result.values.tooltipError or result.values.tooltip)
    local function serializable(value, seen)
        local kind = type(value)
        if kind == 'number' then return value == value and value ~= math.huge and value ~= -math.huge end
        if kind ~= 'table' then return kind == 'string' or kind == 'boolean' or kind == 'nil' end
        if seen[value] then return false end
        seen[value] = true
        for key, child in pairs(value) do
            if not serializable(key, seen) or not serializable(child, seen) then return false end
        end
        seen[value] = nil
        return true
    end
    assert(serializable(RosettaSourceProbeData, {}), 'saved observations must be serializable')
''')

lua = create()
lua.execute('''
    RosettaSourceProbeQueue.profiles.enUS.jobs = {{kind='quests', id=1, fields={'title'}}}
    SlashCmdList.ROSETTASOURCEPROBE('start'); Tick(0); Fire('QUEST_DATA_LOAD_RESULT', 1, false); Tick(0)
    local text = table.concat(output, '\\n')
    assert(text:find('All jobs attempted', 1, true))
    assert(text:find('report', 1, true))
    SlashCmdList.ROSETTASOURCEPROBE('report')
    assert(table.concat(output, '\\n'):find('loadFailed: 1', 1, true))
''')
print('PASS: source probe lifecycle, pacing, failures, rendered observations and session boundaries')
