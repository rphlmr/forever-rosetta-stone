"""Exercise the local scanner's asynchronous lifecycle in Lua 5.1."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import runpy
import tempfile
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / 'tools/quest-scan/rosetta-quest-probe/probe.lua').read_text()
prepare = runpy.run_path(str(ROOT / 'tools/quest-scan/prepare.py'))['prepare_probe']


def create(dependencies=None):
    lua = LuaRuntime(unpack_returned_tuples=True)

    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        output = root / 'datasources/imports/quest-scan/probe'
        queue = prepare([16, 32, 77, 81, 105, 171, 254], output, root=root, item_dependencies=dependencies)
        lua.execute((output / 'queue.lua').read_text())
        assert lua.globals().RosettaQuestProbeQueue.hash == queue['hash']

    lua.execute('''
        UIParent, UISpecialFrames, ChatFontNormal = {}, {}, "font"
        C_Timer = { After = function(_, callback) callback() end }
        clock, requests, output, behavior = 0, {}, {}, {}
        itemRequests, itemBehavior, objectiveText = {}, {}, 'before'
        locale, build, combat = 'enUS', '70888', false
        function time() return 1000 + clock end
        function GetTime() return clock end
        function GetLocale() return locale end
        function GetBuildInfo() return '1.60.1', build end
        function InCombatLockdown() return combat end
        function print(message) output[#output + 1] = message end
        SlashCmdList = {}
        function CreateFrame(kind, name, parent)
            local frame = { scripts = {}, events = {}, name = name }
            function frame:RegisterEvent(event) self.events[event] = true end
            function frame:SetScript(event, fn) self.scripts[event] = fn end
            function frame:SetText(text) self.text = text end
            function frame:GetText() return self.text end
            function frame:GetName() return self.name end
            function frame:Show() self.shown = true end
            function frame:Hide() self.shown = false end
            function frame:SetFocus() self.focused = true end
            function frame:ClearFocus() self.focused = false end
            function frame:HighlightText() self.highlighted = true end
            function frame:CreateFontString() return CreateFrame("FontString", nil, self) end
            for _, method in ipairs({"SetSize", "SetPoint", "SetFrameStrata", "SetFrameLevel", "EnableMouse",
                "SetClampedToScreen", "SetBackdrop", "SetAutoFocus", "SetMultiLine", "SetMaxLetters",
                "SetFontObject", "SetTextColor", "SetWidth", "SetHeight", "SetScrollChild"}) do frame[method] = function() end end
            if not name and not parent then probeFrame = frame end
            if name == "FRSQuestProbeReport" then reportFrame = frame end
            return frame
        end
        function Fire(id, success)
            probeFrame.scripts.OnEvent(probeFrame, 'QUEST_DATA_LOAD_RESULT', id, success)
        end
        function FireItem(id, success)
            probeFrame.scripts.OnEvent(probeFrame, 'ITEM_DATA_LOAD_RESULT', id, success)
        end
        C_Item = { RequestLoadItemDataByID = function(id)
            itemRequests[#itemRequests + 1] = id
            if itemBehavior[id] == 'error' then error('item request failed') end
            if itemBehavior[id] == 'sync' then FireItem(id, true) end
        end }
        function Tick(seconds)
            clock = clock + seconds
            probeFrame.scripts.OnUpdate(probeFrame)
        end
        C_QuestLog = {}
        function C_QuestLog.IsOnQuest(id) return id == 16 end
        function C_QuestLog.GetTitleForQuestID(id) return 'Quest ' .. id end
        function C_QuestLog.GetQuestObjectives(id)
            if behavior[id] == 'readError' then error('read failed') end
            if behavior[id] == 'nil' then return nil end
            if behavior[id] == 'empty' then return {} end
            return {{ type = 'monster', text = '0/6 Wolf slain', numRequired = 6, numFulfilled = 0 }}
        end
        function C_QuestLog.RequestLoadQuestByID(id)
            requests[#requests + 1] = { id = id, clock = clock }
            if behavior[id] == 'requestError' then error('request failed') end
            if behavior[id] == 'pending' then return end
            Fire(id, behavior[id] ~= 'failed')
        end
    ''')
    lua.execute('assert(loadstring(...))("rosetta-quest-probe")', SOURCE)
    lua.execute('assert(SLASH_ROSETTAQUESTPROBE1 == "/frsscan", "FRS scanner command must be registered")')
    lua.execute('probeFrame.scripts.OnEvent(probeFrame, "ADDON_LOADED", "rosetta-quest-probe")')
    return lua


lua = create()
lua.execute('''
    Tick(0)
    assert(#requests == 0, 'loading must not start the scanner')
    behavior[32], behavior[77], behavior[81] = 'empty', 'nil', 'failed'
    behavior[105], behavior[171], behavior[254] = 'pending', 'requestError', 'readError'
    SlashCmdList.ROSETTAQUESTPROBE('start')
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    assert(#requests == 1)
    Tick(0.1)
    assert(#requests == 1, 'requests must be spaced apart')
    Tick(0.1)
    Tick(0.2)
    Tick(0.2)
    Tick(0.2)
    assert(#requests == 5, 'five immediate responses must be requested within 0.8 seconds')
    Fire(99999, true)
    assert(RosettaQuestProbeData.nextIndex == 5, 'unrelated events must be ignored')
    Tick(9)
    assert(#requests == 5 and RosettaQuestProbeData.nextIndex == 5)
    Tick(1)
    assert(RosettaQuestProbeData.results[105].status == 'timeout')
    Fire(105, true)
    assert(RosettaQuestProbeData.results[105].status == 'timeout', 'late events must not replace results')
    Tick(0)
    Tick(0.2)
    Tick(0)
    assert(RosettaQuestProbeData.nextIndex == 8)
    local expected = { 'loadedWithObjectives', 'loadedEmpty', 'loadedWithoutObjectiveData',
        'loadFailed', 'timeout', 'requestError', 'readError' }
    for index, id in ipairs(RosettaQuestProbeQueue.ids) do
        assert(RosettaQuestProbeData.results[id].status == expected[index], id)
    end
    assert(RosettaQuestProbeData.results[81].loadSuccess == false)
    assert(RosettaQuestProbeData.results[16].rows[1].text == '0/6 Wolf slain')
    assert(RosettaQuestProbeData.results[16].inLog == true)
    for index = 2, #requests do
        assert(requests[index].clock - requests[index-1].clock >= 0.2 - 1e-9)
    end
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(100)
    assert(#requests == 7, 'completed scans must not repeat')
    SlashCmdList.ROSETTAQUESTPROBE('quest 16')
    assert(reportFrame.shown and reportFrame.editBox.text:find('Quest 16', 1, true))
    assert(reportFrame.editBox.text:find('0/6 Wolf slain', 1, true), 'raw objective text is copyable')
    reportFrame.selectOutput.scripts.OnClick()
    assert(reportFrame.editBox.focused and reportFrame.editBox.highlighted)
''')

lua = create()
lua.execute('''
    behavior[16] = 'pending'
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    Tick(1)
    assert(#requests == 1)
    Fire(16, true)
    Tick(10)
    assert(#requests == 1 and RosettaQuestProbeData.nextIndex == 2)
''')
lua.execute('assert(loadstring(...))("rosetta-quest-probe")', SOURCE)
lua.execute('''
    probeFrame.scripts.OnEvent(probeFrame, 'ADDON_LOADED', 'rosetta-quest-probe')
    Tick(0)
    assert(#requests == 1, 'reload must not resume automatically')
    locale = 'frFR'
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    assert(#requests == 1, 'different locales must not be mixed')
    locale, build = 'enUS', '99999'
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    assert(#requests == 1, 'different builds must not be mixed')
    build, combat = '70888', true
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    assert(#requests == 1, 'combat must delay new requests')
    combat = false
    Tick(0)
    assert(#requests == 2 and requests[2].id == 32, 'resume must preserve the cursor')
    Tick(7200)
    Tick(1)
    assert(#requests == 2, 'session duration must be bounded')
''')
print('PASS: manual start, seven result categories, spacing, unrelated/late events, pause in flight, reload/resume, locale/build boundaries, combat, completion, session limit.')

lua = create({'16': [201, 202, 203, 204]})
lua.execute('''
    Tick(0)
    assert(#itemRequests == 0, 'comparison must never start automatically')
    SlashCmdList.ROSETTAQUESTPROBE('compare 16')
    Tick(0)
    assert(#itemRequests == 0, 'quest must first have a successful saved result')
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    local original = RosettaQuestProbeData.results[16]
    C_QuestLog.GetQuestObjectives = function() return {{text = objectiveText}} end
    SlashCmdList.ROSETTAQUESTPROBE('compare 16')
    assert(#itemRequests == 0)
    Tick(0)
    assert(itemRequests[1] == 201)
    FireItem(999, true)
    Tick(0.2)
    assert(#itemRequests == 1, 'unrelated item event must not advance')
    FireItem(201, true)
    objectiveText = 'after'
    Tick(0)
    FireItem(202, false)
    itemBehavior[203] = 'error'
    Tick(0.2)
    Tick(0.2)
    Tick(10)
    FireItem(204, true)
    local result = RosettaQuestProbeData.comparisons[1]
    assert(result.status == 'complete' and result.before.rows[1].text == 'before' and result.after.rows[1].text == 'after')
    assert(result.dependencies[1].status == 'loaded' and result.dependencies[2].status == 'failed')
    assert(result.dependencies[3].status == 'requestError' and result.dependencies[4].status == 'timeout')
    assert(result.dependencies[1].cacheBefore == 'unavailable' and result.dependencies[1].cacheAfter == 'unavailable')
    assert(RosettaQuestProbeData.results[16] == original and original.rows[1].text == '0/6 Wolf slain')
    assert(RosettaQuestProbeData.nextIndex == 2)
''')

lua = create({'16': [201, 202, 203]})
lua.execute('''
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    C_Item.IsItemDataCachedByID = function(id)
        if id == 201 then return true end
        if id == 202 then error('cache read failed') end
        return false
    end
    SlashCmdList.ROSETTAQUESTPROBE('compare 16')
    Tick(0)
    Tick(0)
    assert(#itemRequests == 1 and itemRequests[1] == 202, 'cached items must not wait for an event')
    FireItem(202, false)
    Tick(0.2)
    FireItem(203, true)
    Tick(0)
    local deps = RosettaQuestProbeData.comparisons[1].dependencies
    assert(deps[1].cacheBefore == 'cached' and deps[1].cacheAfter == 'cached' and deps[1].status == 'alreadyCached')
    assert(deps[2].cacheBefore == 'error' and deps[2].cacheAfter == 'error' and deps[2].status == 'failed')
    assert(deps[3].cacheBefore == 'notCached' and deps[3].cacheAfter == 'notCached' and deps[3].status == 'loaded')
''')
print('PASS: explicit paired comparison, matching events, failures, timeout, and saved result preservation.')

lua = create({'16': [201, 202]})
lua.execute('''
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    itemBehavior[201] = 'sync'
    SlashCmdList.ROSETTAQUESTPROBE('compare 16')
    Tick(0)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    Tick(1)
    assert(#itemRequests == 1 and RosettaQuestProbeData.comparisons[1].status == 'paused')
    assert(RosettaQuestProbeData.comparisons[1].dependencies[1].status == 'loaded')
    SlashCmdList.ROSETTAQUESTPROBE('compare 16')
    Tick(0)
    Tick(0.2)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    FireItem(202, true)
    Tick(0)
    assert(#itemRequests == 3 and RosettaQuestProbeData.comparisons[2].status == 'paused')
''')

lua = create()
lua.execute('''
    local reads = 0
    C_QuestLog.GetQuestObjectives = function(id)
        reads = reads + 1
        if reads < 3 then return {{type = 'item', text = '0/1 ', numFulfilled = 0, numRequired = 1}} end
        return {{type = 'item', text = '0/1 Pelt', numFulfilled = 0, numRequired = 1}}
    end
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    assert(RosettaQuestProbeData.results[16] == nil and reads == 1)
    Tick(0.2)
    Tick(0.2)
    assert(RosettaQuestProbeData.results[16].rows[1].text == '0/1 Pelt')
    assert(RosettaQuestProbeData.results[16].labelRetry == 'resolved')
''')
lua = create()
lua.execute('''
    C_QuestLog.GetQuestObjectives = function() return {{type = 'item', text = '0/1 ', numFulfilled = 0, numRequired = 1}} end
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    SlashCmdList.ROSETTAQUESTPROBE('pause')
    Tick(10)
    local row = RosettaQuestProbeData.results[16]
    assert(row.status == 'loadedWithObjectives' and row.labelRetry == 'incomplete' and row.rows[1].text == '0/1 ')
    Tick(1)
    assert(#requests == 1, 'pause must stop subsequent quests after retry deadline')
''')
lua = create()
lua.execute('''
    local shared = {{type = 'monster', text = '0/6   slain', numFulfilled = 0, numRequired = 6}}
    C_QuestLog.GetQuestObjectives = function() return shared end
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    assert(RosettaQuestProbeData.results[16] == nil, 'blank monster name must trigger a retry')
    shared[1].type, shared[1].text = 'item', '0/6 Wrong'
    Tick(10)
    local record = RosettaQuestProbeData.results[16]
    assert(record.labelRetry == 'incomplete' and record.rows[1].type == 'monster')
    assert(record.rows[1].text == '0/6   slain', 'saved observation must not alias client tables')
''')
lua = create()
lua.execute('''
    local reads = 0
    C_QuestLog.GetQuestObjectives = function()
        reads = reads + 1
        return {{type = 'item', text = reads == 1 and '   ' or '0/1 Pelt', numFulfilled = 0, numRequired = 1}}
    end
    SlashCmdList.ROSETTAQUESTPROBE('start')
    Tick(0)
    Tick(0.2)
    assert(RosettaQuestProbeData.results[16].labelRetry == 'resolved')
''')
