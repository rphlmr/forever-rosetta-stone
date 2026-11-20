#!/usr/bin/env python3
"""Replay captured client tooltips through the addon and report rows behind the incomplete notice.

Input is a backed-up `/frsverify api` SavedVariables capture: its `C_TooltipInfo.GetSpellByID` and
`C_TooltipInfo.GetItemByID` responses are the structured rows the addon translates in game, and its
captured GlobalStrings are the client's own values. Every capture is rendered with the shipping
tooltip code and the built database packs into each target language. Rows that would show
"Some lines are not translated yet." are grouped by line type and number-normalized native text,
so one missing mapping or unmatched format appears once with its count and example IDs.

Nothing here edits catalogs, runtime files or packs; reports are written under datasources/imports/.
"""

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / 'tests/python'))
from datasources.lua_data import assignments

ROOT_NAME = 'RosettaTooltipCheckData'
APIS = {'spell': 'C_TooltipInfo.GetSpellByID', 'item': 'C_TooltipInfo.GetItemByID'}


def context_calls(calls, context):
    """Reuse recorded player Context() calls without assigning them to another unit."""
    result = dict(calls)
    for field, api in (('level', 'UnitLevel'), ('sex', 'UnitSex'), ('faction', 'UnitFactionGroup')):
        response = (context or {}).get(field)
        if isinstance(response, dict):
            result[api] = {'"player"': response, **calls.get(api, {})}
    return result
# TooltipDataLineType order for the Classic Forever client (index = enum value).
LINE_TYPES = json.loads((ROOT / 'tests/fixtures/tooltip-inventory-70862.json').read_text())['line_types']
MODULES = ('tooltips/tooltip-layout.lua', 'database/item-data.lua', 'tooltips/english-tooltip-formats.lua',
           'tooltips/localized-tooltip-formats.lua', 'database/localized-item-data.lua',
           'database/npc-tooltip-data.lua', 'tooltips/components/npc-tooltip.lua',
           'tooltips/spell-live-values.lua', 'tooltips/tooltip-descriptions.lua',
           'tooltips/components/spell-tooltip.lua', 'tooltips/components/quest-link-tooltip.lua')
LATE_MODULES = ('tooltips/appearance-tooltip-formats.lua', 'tooltips/tooltip-extra-formats.lua',
                'tooltips/item-stat-formats.lua', 'tooltips/client-labels.lua')
# Each place FillEnglishTooltip marks a tooltip incomplete, with the reason recorded for the row.
GAP_HOOKS = (
    ('incomplete = HasTranslatableText(subtext)',
     'incomplete = HasTranslatableText(subtext) and RosettaGap(nameLine, "subtext") or false'),
    ('if requirementIncomplete[line] then incomplete = true end',
     'if requirementIncomplete[line] then incomplete = RosettaGap(line, "requirement") end'),
    ('if untranslated then incomplete = true end', 'if untranslated then incomplete = RosettaGap(line, "unmatched") end'),
    ('if HasTranslatableText(left) then incomplete = true end',
     'if HasTranslatableText(left) then incomplete = RosettaGap(line, "left kept") end'),
    ('if HasTranslatableText(right) then incomplete = true end',
     'if HasTranslatableText(right) then incomplete = RosettaGap(line, "right kept") end'),
)
# Observe the shipping renderer's actual row ownership; do not reproduce its
# selection, suppression or expansion decisions in the Python replay adapter.
ROW_HOOKS = (
    ('for field, value in pairs(key and metadata[key] or {}) do row[field] = value end',
     'for field, value in pairs(key and metadata[key] or {}) do row[field] = value end\n'
     '        ReplayVisibleOrigins[row] = {}\n'
     '        for _, original in ipairs(lines) do\n'
     '            if key and Key(original.leftText, original.rightText) == key then\n'
     '                ReplayVisibleOrigins[row][#ReplayVisibleOrigins[row]+1] = original\n'
     '            end\n'
     '        end'),
    ('local nameLine = lines[1]',
     'ReplayEffectiveLines = lines\n    local nameLine = lines[1]'),
    ('if subtext then tip:AddDoubleLine(titleText, subtext,',
     'ReplayRowContext = {line = nameLine, role = "title"}\n    if subtext then tip:AddDoubleLine(titleText, subtext,'),
    ('for _, line in ipairs(lines) do\n        if canaccessallvalues(line.type, line.leftText, line.rightText)',
     'for _, line in ipairs(lines) do\n        ReplayRowContext = {line = line, role = "row"}\n        if canaccessallvalues(line.type, line.leftText, line.rightText)'),
    ('IsTalentPurchaseRequirement(line, formats) then',
     'ReplayPurchaseGate(line, IsTalentPurchaseRequirement(line, formats)) then'),
    ('local requirementIncomplete = {}',
     'ReplaySkippedRows = liveSkipped\n    local requirementIncomplete = {}'),
)
NUMBER = re.compile(r'\d+(?:[.,\u00a0 ]\d+)*')
MARKUP = re.compile(r'\|c[0-9a-fA-F]{8}|\|r|\|T.*?\|t|\|A.*?\|a')
NATIVE_TOKEN = re.compile(r'\$\{[^}]+\}(?:\.\d+)?|\$<[A-Za-z0-9_]+>|\$(?:\d+)?[A-Za-z_]+[0-9]*')


def native_token_rows(data):
    """Record already-unresolved client text separately from missing FRS translations."""
    return [{'lineIndex': row.get('lineIndex'), 'text': row['leftText'],
             'tokens': NATIVE_TOKEN.findall(row['leftText'])}
            for row in data.get('lines', [])
            if isinstance(row.get('leftText'), str) and NATIVE_TOKEN.search(row['leftText'])]


def missing_player_context(replay, kind, entity_id, data, calls, target, rows):
    """Explain unresolved rows whose required player API was never recorded.

    This classifies unavailable evidence; it never supplies a current or invented
    player response to a historical tooltip and never counts the row as translated.
    """
    missing = []
    if kind == 'player' and rows:
        unit = getattr(replay, 'unit_evidence', None) or {}
        apis = unit.get('apis', {})
        race = apis.get('UnitRace', {}).get('values', {})
        if not apis.get('UnitSex') and type(race.get(3)) is int and isinstance(race.get(1), str):
            db = replay.database
            source = [db.GetRaceName(db, race[3], replay.client_locale.encode(), sex) for sex in (2, 3)]
            targets = [db.GetRaceName(db, race[3], target.encode(), sex) for sex in (2, 3)]
            if source[0] == source[1] == race[1].encode() and all(targets) and targets[0] != targets[1] \
                    and all(race[1] in (row.get('text') or '') for row in rows):
                return [{'text': row.get('text'), 'requiredApis': ['UnitSex'],
                         'reason': 'Native race wording cannot distinguish different target gender variants'} for row in rows]
    sex_absent = not calls.get('UnitSex', {}).get('"player"')
    faction_absent = not calls.get('UnitFactionGroup', {}).get('"player"')
    if not rows:
        return []
    # A template mentioning gender is not proof that missing UnitSex caused the
    # failure. The observer records only complete matches with different outputs
    # whose successful decoder choices differ exclusively on gender.
    grammar = []
    for issue in (replay.lua.globals().ReplayGrammarIssues or {}).values():
        native = issue[b'native']
        grammar.append((native.decode() if isinstance(native, bytes) else native,
                        [value.decode() for value in issue[b'units'].values()]))
    for row in rows:
        rank = any(line.get('leftText') == row.get('text') and type(line.get('rank')) is int
                   and line['rank'] > 0 for line in data.get('lines', []))
        if rank and (sex_absent or faction_absent):
            missing.append({'text': row.get('text'), 'requiredApis':
                            [name for name, absent in [('UnitSex', sex_absent), ('UnitFactionGroup', faction_absent)] if absent]})
        elif row.get('lineType') in ('SpellDescription', 'ItemSpellTriggerOnUse',
                                     'ItemSpellTriggerOnEquip', 'ItemSpellTriggerOnProc'):
            normalize = lambda text: re.sub(r'\s+', ' ', MARKUP.sub('', text or '')).strip()
            units = {unit for native, units in grammar if native and normalize(native) in normalize(row.get('text')) for unit in units}
            if not units:
                return []
            missing.append({'text': row.get('text'), 'requiredApis': ['UnitSex'], 'unitArguments': sorted(units),
                            'reason': 'Complete decoder matches differ exclusively on unrecorded gender choices'})
        else:
            return []
    return missing


def sequence(value):
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and value and set(value) == set(range(1, len(value) + 1)):
        return [value[index] for index in range(1, len(value) + 1)]
    return None


def api_observations(calls, tooltip_types=None):
    """Keep every recorded tooltip surface, including traits, recipe outputs and chat links."""
    types = tooltip_types or {'Item': 0, 'Spell': 1}
    kinds = {types['Item']: 'item', types['Spell']: 'spell'}
    getters = (*APIS.values(), 'C_TooltipInfo.GetTraitEntry', 'C_TooltipInfo.GetRecipeResultItem',
               'C_TooltipInfo.GetRecipeReagentItem', 'C_TooltipInfo.GetHyperlink')
    for api in getters:
        for key, response in sorted(calls.get(api, {}).items()):
            values = sequence(response.get('values')) or []
            data = values[0] if response.get('status') == 'ok' and values else None
            if not isinstance(data, dict):
                continue
            kind, entity_id = kinds.get(data.get('type')), data.get('id')
            lines = sequence(data.get('lines'))
            if kind and type(entity_id) is int and entity_id > 0 and lines:
                yield {'kind': kind, 'id': entity_id, 'data': dict(data, lines=lines),
                       'api': api, 'arguments': key, 'processingInfo': {'status': 'ok', 'values': {
                           1: {'getterName': api.rsplit('.', 1)[1]}}}}


def read_capture(path, run_index=None):
    """Read one API run, or a manually stopped targeted hover run without merging contexts."""
    parsed = list(assignments(path.read_text(encoding='utf-8'), [(ROOT_NAME,)]))
    if len(parsed) != 1:
        raise SystemExit('Expected one literal ' + ROOT_NAME + ' assignment')
    runs = sequence(parsed[0][1].get('runs')) or []
    api_runs = [index for index, run in enumerate(runs, 1)
                if (run.get('profile') == 'api' and run.get('stoppedReason') in ('api complete', 'api timeout'))
                or (run.get('profile') == 'cible' and run.get('stoppedReason') == 'manual stop')]
    if not api_runs:
        raise SystemExit('The capture has no finished api or cible run')
    run_index = run_index or api_runs[-1]
    if run_index not in api_runs:
        raise SystemExit(f'Run {run_index} is not a finished api or cible run; finished: {api_runs}')
    run = runs[run_index - 1]
    locale = sequence(run['locale']['values'])[0]
    samples = sequence(run.get('samples')) or []
    evidence = {'profile': run['profile'], 'build': run.get('build'), 'label': run.get('label'),
                'tooltipTypes': run.get('tooltipTypes') or {'Item': 0, 'Spell': 1, 'UnitAura': 7},
                'observations': [], 'ignoredSamples': []}
    if run['profile'] == 'cible':
        tooltips = {kind: {} for kind in APIS}
        for index, sample in enumerate(samples, 1):
            details = sample.get('details') or {}
            kind = {'Item': 'item', 'Spell': 'spell', 'UnitAura': 'spell'}.get(details.get('dataType'))
            data = details.get('data') or {}
            entity_id = details.get('entityID')
            if sample.get('kind') != 'hover' or not kind or not isinstance(entity_id, int) or not sequence(data.get('lines')):
                evidence['ignoredSamples'].append(index)
                continue
            data = dict(data, lines=sequence(data['lines']))
            tooltips[kind][entity_id] = data
            evidence['observations'].append({'kind': kind, 'id': entity_id, 'data': data, 'sample': index,
                'calls': context_calls(details.get('dependencies') or {}, sample.get('context')),
                'globals': details.get('globals') or run.get('globals') or {},
                'processingInfo': details.get('processingInfo'), 'context': sample.get('context'),
                'visible': captured_visible_rows(details)})
        return locale, {}, tooltips, run_index, evidence
    details = next(sample for sample in samples if sample.get('kind') == 'api')['details']
    evidence.update(calls=context_calls(details.get('calls') or {}, next(s for s in samples if s.get('kind')=='api').get('context')),
                    pendingAtCapture=sequence(details.get('pendingAtCapture')) or [],
                    loadResults=details.get('loadResults') or {}, unavailableTooltips=[])
    tooltips = {}
    for kind, api in APIS.items():
        tooltips[kind] = {}
        for key, response in (details['calls'].get(api) or {}).items():
            values = sequence(response.get('values')) or []
            if response.get('status') == 'ok' and values and isinstance(values[0], dict):
                lines = sequence(values[0].get('lines'))
                if lines:
                    tooltips[kind][int(key)] = dict(values[0], lines=lines)
                    continue
            evidence['unavailableTooltips'].append({'kind': kind, 'key': key,
                'status': response.get('status'), 'error': response.get('error'), 'reason': 'no readable tooltip rows'})
    client_globals = {key: value for key, value in (details.get('globals') or {}).items() if value != '<nil>'}
    evidence['observations'] = [dict(observation, calls=evidence['calls'], globals=client_globals)
                                for observation in api_observations(evidence['calls'], evidence['tooltipTypes'])]
    return locale, client_globals, tooltips, run_index, evidence


def clean(value):
    """Drop captured method placeholders and nil sentinels so rows look like client tables."""
    if isinstance(value, dict):
        items = sequence(value)
        if items is not None:
            return [clean(item) for item in items]
        return {key: clean(child) for key, child in value.items()
                if child not in ('<function>', '<nil>')}
    if isinstance(value, list):
        return [clean(item) for item in value]
    return value


def captured_visible_rows(details):
    """Retain native rows, including appended rank previews, without replaying FRS into itself."""
    if 'nativeVisible' in details:
        return sequence(details['nativeVisible']) or []
    visible = details.get('visible') or {}
    rows = sequence(visible) or []
    marker = next((index for index, row in enumerate(rows, 1)
                   if 'Interface\\AddOns\\ForeverRosettaStone\\media\\icon:' in
                   str(row.get('left', {}).get('values', {}).get(1, '')).replace('\\\\', '\\')), None)
    if marker is None:
        return rows
    # FillStackedTooltip appends a blank and its own header after the original rows.
    indices = set(range(1, max(1, marker - 1)))
    for line in sequence((details.get('data') or {}).get('lines')) or []:
        index = line.get('lineIndex')
        if isinstance(index, int) and index >= marker:
            indices.add(index)
    return [row for index, row in enumerate(rows, 1) if index in indices]


class Replay:
    _compiled_packs = {}

    def __init__(self, client_locale, client_globals, calls=None, tooltip_types=None):
        from lupa.lua51 import LuaRuntime
        from database_harness import install_metadata, load_database, read_metadata
        self.lua = LuaRuntime(encoding=None)
        metadata = read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc', include_pages=False)
        install_metadata(self.lua, metadata, compiled_packs=self._compiled_packs)
        self.database = load_database(self.lua)
        self.client_locale = client_locale
        lua_globals = self.lua.globals()
        for key, value in client_globals.items():
            if isinstance(value, str):
                lua_globals[key.encode()] = value.encode()
        enum = self.lua.table_from({name.encode(): index for index, name in enumerate(LINE_TYPES)})
        lua_globals.Enum = self.lua.table_from({b'TooltipDataLineType': enum,
            b'TooltipDataType': self.to_lua(tooltip_types or {'Item': 0, 'Spell': 1, 'UnitAura': 7})})
        lua_globals.ReplayClientLocale = client_locale.encode()
        self.lua.execute(b'''
canaccessallvalues = function() return true end
GetLocale = function() return ReplayClientLocale end
InRepairMode = function() return false end
GameTooltipMoneyFormat = {}
MoneyFormatterUtil = { FormatMoney = function(amount) return amount .. "|Tcoin|t" end }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
ReplayGaps = {}
ReplayRecordDecoderProof = function() end
RosettaGap = function(line, reason)
    ReplayGaps[#ReplayGaps + 1] = { line = line, reason = reason }
    return true
end
ReplayAddon = { replayComponents = {}, RegisterTooltipComponent = function() end }
ReplayAddon.RegisterNameTooltipComponent = function(self, component)
    self.replayComponents[component.kind] = component
end
''')
        addon = lua_globals.ReplayAddon
        self.fixture = self.lua.execute((ROOT / 'tests/lua/support/client-api-fixture.lua').read_bytes())
        self.install_calls(calls or {})
        for name in MODULES:
            source = (ROOT / 'ForeverRosettaStone' / name).read_text(encoding='utf-8')
            if name == 'tooltips/tooltip-descriptions.lua':
                for old, new in GAP_HOOKS + ROW_HOOKS:
                    if source.count(old) != 1:
                        raise SystemExit(f'tooltip-descriptions.lua changed; update GAP_HOOKS for: {old}')
                    source = source.replace(old, new)
            if name == 'tooltips/spell-live-values.lua':
                for old, new in (
                    ('local attempts,outputs=0,{}', 'local attempts,outputs,proofs=0,{},{}'),
                    ('outputs[rendered]=true', 'outputs[rendered]=true\n'
                     '        ReplayRecordDecoderProof(id,field,sourceLocale,targetLocale,native,rendered,values,choices)\n'
                     '        local proof={choices={}};for key,value in pairs(choices) do proof.choices[key]=value end\n'
                     '        proofs[#proofs+1]=proof'),
                    ('if plain and plain ~= uncolored then return end',
                     'if plain and plain ~= uncolored then ReplayGrammarAmbiguity(native,proofs);return end'),
                ):
                    if source.count(old) != 1:
                        raise SystemExit('Update decoder observation hook: ' + old)
                    source = source.replace(old, new)
            if name == 'tooltips/components/npc-tooltip.lua':
                replacements = (
                    ('subtext, incomplete = nameLine.rightText, true',
                     'subtext, incomplete = nameLine.rightText, RosettaGap(nameLine, "subtext")'),
                    ('if Normalize(left):match("%S") and not IsNativePlayerFaction(left, unitLabels) then\n'
                     '                        incomplete = true\n',
                     'if Normalize(left):match("%S") and not IsNativePlayerFaction(left, unitLabels) then\n'
                     '                        incomplete = RosettaGap(line, "left kept")\n'),
                    ('right, incomplete = line.rightText, true',
                     'right, incomplete = line.rightText, RosettaGap(line, "right kept")'),
                    ('if quest and quest.incomplete then incomplete = true end',
                     'if quest and quest.incomplete then incomplete = RosettaGap(line, "quest objective") end'),
                )
                for old, new in replacements:
                    if source.count(old) != 1:
                        raise SystemExit(f'npc-tooltip.lua changed; update gap hooks for: {old}')
                    source = source.replace(old, new)
            self.lua.execute(source.encode(), b'ForeverRosettaStone', addon)
        for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
            self.lua.execute(path.read_bytes(), b'ForeverRosettaStone', addon)
        for name in LATE_MODULES:
            self.lua.execute((ROOT / 'ForeverRosettaStone' / name).read_bytes(), b'ForeverRosettaStone', addon)
        self.lua.execute(b'''
local addon = ReplayAddon
C_Item = C_Item or {}
C_Item.GetItemSubClassInfo = function(classID, subclassID)
    local locale = addon.itemSubclassesByLocale and addon.itemSubclassesByLocale[ReplayClientLocale]
    return locale and locale[classID] and locale[classID][subclassID]
end
local font = { GetFont = function() return "native", 12, "" end,
    GetTextScale = function() return 1 end, GetTextColor = function() return 1, 1, 1 end }
ReplayRender = function(kind, id, name, target, data, processing, visible, unit)
    ReplayGaps = {}
    ReplayGrammarIssues = {}
    ReplayDecoderProofs = {}
    ReplayRecordDecoderProof = function(id, field, source, destination, native, rendered, values, choices)
        local slots, selected = {}, {}
        for key, value in pairs(values) do
            slots[#slots + 1] = {key=key, canonical=value.canonical, amount=value.amount,
                text=value.text, unresolved=value.unresolved}
        end
        table.sort(slots, function(a,b) return a.key < b.key end)
        for key, value in pairs(choices) do
            if type(key) == "string" then selected[key] = value end
        end
        ReplayDecoderProofs[#ReplayDecoderProofs + 1] = {owner=id, field=field,
            sourceLocale=source, targetLocale=destination, nativeText=native,
            renderedText=rendered, slots=slots, choices=selected}
    end
    ReplayGrammarAmbiguity = function(native, proofs)
        local first, units
        units = {}
        for _, proof in ipairs(proofs) do
            local other, count = {}, 0
            for key, value in pairs(proof.choices) do
                if type(key) == "string" and key:sub(1, 7) == "gender:" then units[key:sub(8)] = true
                else other[key], count = value, count + 1 end
            end
            if first then
                local expected = 0
                for key, value in pairs(first) do
                    if other[key] ~= value then return end
                    expected = expected + 1
                end
                if expected ~= count then return end
            else first = other end
        end
        local names = {}
        for unit in pairs(units) do names[#names + 1] = unit end
        if #names > 0 then ReplayGrammarIssues[#ReplayGrammarIssues+1] = {native=native,units=names} end
    end
    ReplayRowContext, ReplaySkippedRows, ReplayPurchaseRows = nil, {}, {}
    ReplayVisibleOrigins = {}
    ReplayEffectiveLines, ReplayOutputBindings = data.lines, {}
    ReplayPurchaseGate = function(line, matched)
        if matched then ReplayPurchaseRows[line] = true end
        return matched
    end
    local rendered = {}
    ReplayLastRendered = rendered
    local function originalIndex(line)
        for index, native in ipairs(data.lines or {}) do
            if native == line then return index end
        end
        local origins = line and ReplayVisibleOrigins[line]
        if origins and #origins > 1 then return nil, true end
        if origins and #origins == 1 then
            for index, native in ipairs(data.lines or {}) do
                if native == origins[1] then return index end
            end
        end
        local original, ambiguous
        for index, native in ipairs(data.lines or {}) do
            if native == line or line and native.lineIndex ~= nil and native.lineIndex == line.lineIndex
                and native.leftText == line.leftText and (native.rightText or "") == (line.rightText or "") then
                if original then ambiguous = true end
                original = index
            end
        end
        return not ambiguous and original or nil, ambiguous
    end
    local function add(left, right)
        rendered[#rendered + 1] = { left = left, right = right,
            SetFont = function() end, SetTextScale = function() end }
        local line = ReplayRowContext and ReplayRowContext.line
        local original, ambiguous = originalIndex(line)
        ReplayOutputBindings[#rendered] = {originalIndex = not ambiguous and original or nil,
            ambiguous = ambiguous, role = ReplayRowContext and ReplayRowContext.role, line = line}
    end
    local tip = { AddLine = function(_, left) add(left) end,
        AddDoubleLine = function(_, left, right) add(left, right) end,
        NumLines = function() return #rendered end,
        GetLeftLine = function(_, index) return rendered[index] end }
    addon.GetTargetLocale = function() return target end
    local source = { GetLeftLine = function() return font end,
        GetProcessingTooltipInfo = function() return processing end }
    if unit and unit.token and unit.token.status == "ok" then
        source.GetUnit = function()
            return unpack(unit.token.values, 1, unit.token.returnCount)
        end
    end
    if visible then
        local function textLine(index, side)
            local line = {}
            for key, value in pairs(font) do line[key] = value end
            line.GetText = function()
                local response = visible[index] and visible[index][side]
                local value = response and response.status == "ok" and response.values[1]
                return value ~= "<nil>" and value or nil
            end
            return line
        end
        source.NumLines = function() return #visible end
        source.GetLeftLine = function(_, index) return textLine(index, "left") end
        source.GetRightLine = function(_, index) return textLine(index, "right") end
    end
    local fill = (kind == "npc" or kind == "player") and addon.FillNpcTooltip or addon.FillEnglishTooltip
    if data.type == Enum.TooltipDataType.UnitAura then
        local component = addon.replayComponents.spell
        local resolved = component and component.ResolveData(source, data)
        if resolved ~= id then return false, "Captured aura instance does not resolve to the requested spell", ReplayGaps end
    end
    local spec = { tip = tip,
        source = source,
        kind = kind, id = id, name = name, data = data }
    ReplayLastSourceRows = data.lines
    if (kind == "npc" or kind == "player") and addon.GetUnitTooltipSelection then
        local _, _, _, selected = addon:GetUnitTooltipSelection(spec, target)
        ReplayLastSourceRows = selected
    end
    local ok, failure = pcall(fill, addon, spec)
    ReplaySuppressions = {}
    for rows, reason in pairs({[ReplaySkippedRows] = "description_span", [ReplayPurchaseRows] = "purchase_gate"}) do
        for line in pairs(rows) do
            local index = originalIndex(line)
            if index then ReplaySuppressions[index] = reason end
        end
    end
    return ok, failure, ReplayGaps
end
''')
        self.render = lua_globals.ReplayRender
        self.names = {'item': self.database.GetItemName, 'spell': self.database.GetSpellName,
                      'npc': self.database.GetNpcName}

    def install_calls(self, calls, unit=None):
        self.unit_evidence = unit
        # Only renderer dependencies are installed; behavioural mocks remain explicit.
        selected = {key: value for key, value in calls.items()
                    if key in ('GetBindLocation', 'UnitFactionGroup', 'UnitLevel', 'UnitSex', 'C_TradeSkillUI.GetRecipeSchematic', 'C_UnitAuras.GetAuraDataByIndex',
                               'C_UnitAuras.GetAuraDataByAuraInstanceID')}
        self.lua.globals().C_TradeSkillUI = None
        self.lua.globals().C_UnitAuras = None
        self.lua.globals().UnitSex = None
        self.lua.globals().GetBindLocation = None
        self.lua.globals().UnitLevel = None
        self.lua.globals().UnitFactionGroup = None
        unit_apis = ('UnitGUID', 'UnitCreatureType', 'UnitClass', 'UnitIsDead', 'UnitIsPlayer',
                     'UnitRace', 'UnitSex', 'UnitLevel', 'UnitFactionGroup', 'GetGuildInfo')
        for key in unit_apis:
            self.lua.globals()[key.encode()] = None
        self.lua.globals().CORPSE = None
        if unit:
            token = unit.get('token', {}).get('values', {}).get(2) or unit.get('unitToken')
            if isinstance(token, str):
                argument_key = self.fixture.Key(token.encode()).decode()
                for api, response in unit.get('apis', {}).items():
                    if api in unit_apis:
                        selected[api] = {**selected.get(api, {}), argument_key: response}
            label = unit.get('corpseLabel')
            if isinstance(label, str):
                self.lua.globals().CORPSE = label.encode()
        self.fixture.Install(self.to_lua({'calls': selected}), self.to_lua({'strict': True}))

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({(key.encode() if isinstance(key, str) else key): self.to_lua(child)
                                        for key, child in value.items()})
        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(child) for child in value])
        return value.encode() if isinstance(value, str) else value

    def targets(self):
        return sorted(locale.decode() for locale in self.database.GetLocales(self.database)
                      if locale.decode() != self.client_locale)

    def run(self, kind, entity_id, data, target, processing=None, visible=None, unit=None):
        native_title = data['lines'][0].get('leftText') or ''
        name = native_title.encode() if kind == 'player' else self.names[kind](self.database, entity_id, target.encode())
        surface = 'talent' if processing and processing.get('getterName') in ('GetTraitEntry', 'GetTalent') else kind
        ok, failure, gaps = self.render(surface.encode(), entity_id, name or native_title.encode(),
                                        target.encode(), self.to_lua(data), self.to_lua(processing),
                                        self.to_lua(visible), self.to_lua(unit))
        if not ok:
            return None, failure.decode('utf-8', 'replace') if isinstance(failure, bytes) else str(failure), name
        rows = []
        for gap in gaps.values():
            line, reason = gap[b'line'], gap[b'reason'].decode()
            side = 'rightText' if reason in ('subtext', 'right kept') else 'leftText'
            text = line[side.encode()] if line else None
            line_type = line[b'type'] if line else None
            rows.append({'reason': reason, 'lineType': LINE_TYPES[line_type] if isinstance(line_type, int)
                         and 0 <= line_type < len(LINE_TYPES) else line_type,
                         'text': (text or b'').decode('utf-8', 'replace') if isinstance(text, bytes) else text})
        return rows, None, name


def pattern(text):
    text = MARKUP.sub('', text or '').replace('\u00a0', ' ')
    return NUMBER.sub('#', text).strip()


def report(capture, run_index=None, targets=None, kinds=('spell', 'item')):
    locale, client_globals, tooltips, run_index, evidence = read_capture(capture, run_index)
    replay = Replay(locale, client_globals, evidence.get('calls'), evidence['tooltipTypes'])
    targets = targets or replay.targets()
    groups = defaultdict(lambda: {'ids': set(), 'targets': set(), 'count': 0, 'example': None})
    errors, missing_names, rendered, incomplete = [], defaultdict(set), 0, 0
    # The client shows this placeholder until a referenced item (a reagent, a set piece) is
    # cached; such captures are incomplete evidence, not missing mappings.
    loading = client_globals.get('RETRIEVING_ITEM_INFO')
    not_loaded = defaultdict(list)
    dependency_statuses = defaultdict(int)
    observations = evidence['observations'] or [
        {'kind': kind, 'id': entity_id, 'data': data, 'calls': evidence['calls'], 'globals': client_globals}
        for kind in kinds for entity_id, data in sorted(tooltips[kind].items())]
    for observation in observations:
        kind, entity_id, data = observation['kind'], observation['id'], observation['data']
        if kind not in kinds:
            continue
        if evidence['profile'] == 'cible':
            replay.install_calls(observation['calls'])
            for key, value in observation['globals'].items():
                replay.lua.globals()[key.encode()] = value.encode() if isinstance(value, str) and value != '<nil>' else None
        if kind == 'spell':
            response = observation['calls'].get('C_TradeSkillUI.GetRecipeSchematic', {}).get(f'{entity_id}, false')
            status = response.get('status', 'not captured') if response else 'not captured'
            if status == 'ok':
                values = sequence(response.get('values')) or []
                status = 'ok: table' if values and isinstance(values[0], dict) else 'ok: no schematic'
            dependency_statuses[status] += 1
        data = clean(data)
        loading = observation['globals'].get('RETRIEVING_ITEM_INFO', loading)
        if loading and any(loading in (line.get('leftText') or '') for line in data['lines']):
            not_loaded[kind].append(entity_id)
            continue
        for target in targets:
            info = observation.get('processingInfo') or {}
            values = sequence(info.get('values')) or []
            processing = clean(values[0]) if info.get('status') == 'ok' and values and isinstance(values[0], dict) else None
            rows, failure, name = replay.run(kind, entity_id, data, target, processing, observation.get('visible'))
            rendered += 1
            if not name:
                missing_names[target].add(f'{kind}:{entity_id}')
            if failure:
                errors.append({'kind': kind, 'id': entity_id, 'target': target, 'sample': observation.get('sample'), 'error': failure})
                continue
            incomplete += bool(rows)
            for row in rows:
                key = (kind, row['lineType'], row['reason'], pattern(row['text']))
                group = groups[key]
                group['ids'].add(entity_id)
                group['targets'].add(target)
                group['count'] += 1
                group['example'] = group['example'] or row['text']
    ordered = sorted(groups.items(), key=lambda item: (-len(item[1]['ids']), -len(item[1]['targets']), item[0]))
    return {
        'capture': str(capture), 'run': run_index, 'clientLocale': locale, 'targets': targets,
        'profile': evidence['profile'], 'label': evidence.get('label'), 'build': evidence['build'],
        'observations': len(observations), 'ignoredSamples': evidence['ignoredSamples'],
        'pendingAtCapture': evidence.get('pendingAtCapture', []),
        'loadResults': evidence.get('loadResults', {}),
        'unavailableTooltips': evidence.get('unavailableTooltips', []),
        'observationContexts': [{'sample': o['sample'], 'kind': o['kind'], 'id': o['id'], 'context': o.get('context')}
                                for o in observations if 'sample' in o],
        'recipeSchematicEvidence': dict(dependency_statuses),
        'provenance': provenance(capture),
        'tooltips': {kind: len(tooltips[kind]) for kind in kinds},
        'notLoaded': {kind: ids for kind, ids in not_loaded.items()},
        'rendered': rendered, 'incomplete': incomplete, 'errors': errors[:200], 'errorCount': len(errors),
        'nativeUnresolvedTokens': [{'kind': o['kind'], 'id': o['id'], 'rows': native_token_rows(clean(o['data']))}
                                   for o in observations if native_token_rows(clean(o['data']))],
        'missingTargetNames': {target: len(ids) for target, ids in sorted(missing_names.items())},
        'groups': [{'kind': kind, 'lineType': line_type, 'reason': reason, 'pattern': text,
                    'example': group['example'], 'ids': len(group['ids']), 'targets': len(group['targets']),
                    'targetLocales': sorted(group['targets']), 'exampleIds': sorted(group['ids'])[:12],
                    'rows': group['count']}
                   for (kind, line_type, reason, text), group in ordered],
    }


def markdown(result):
    lines = [f"# Tooltip gaps: {result['clientLocale']} client, run {result['run']}", '',
             f"- Tooltips: {result['tooltips']} rendered into {len(result['targets'])} targets "
             f"({result['rendered']} renders, {result['incomplete']} with the incomplete notice).",
             f"- Skipped, not loaded when captured: "
             f"{ {kind: len(ids) for kind, ids in result['notLoaded'].items()} } (recapture them).",
             f"- Render errors: {result['errorCount']}.", '',
             f"- Native observations already containing unresolved tokens: {len(result.get('nativeUnresolvedTokens', []))}. "
             'These remain symbolic even when the surrounding text translates.',
             f"- Profile: {result['profile']}; observations: {result['observations']}.",
             f"- Recipe schematic evidence (per spell observation): {result['recipeSchematicEvidence']}.",
             f"- Unavailable tooltip responses: {len(result['unavailableTooltips'])}; "
             f"ignored samples: {result['ignoredSamples']}; pending IDs: {result['pendingAtCapture']}.",
             '- These are captured-context results, not exhaustive in-game coverage. Missing API evidence '
             'must be distinguished from a captured unavailable API or an empty response.', '',
             '| IDs | Targets | Kind | Line type | Reason | Native pattern | Example IDs |',
             '| ---: | ---: | --- | --- | --- | --- | --- |']
    for group in result['groups']:
        text = group['pattern'].replace('|', '\\|').replace('\n', ' ⏎ ')
        if len(text) > 120:
            text = text[:117] + '…'
        lines.append(f"| {group['ids']} | {group['targets']} | {group['kind']} | {group['lineType']} | "
                     f"{group['reason']} | {text} | {', '.join(map(str, group['exampleIds'][:6]))} |")
    if result['errors']:
        lines += ['', '## Render errors', '']
        lines += [f"- {error['kind']} {error['id']} → {error['target']}: {error['error'][:200]}"
                  for error in result['errors'][:30]]
    return '\n'.join(lines) + '\n'


def provenance(capture):
    paths = [ROOT / 'ForeverRosettaStone' / name for name in MODULES + LATE_MODULES]
    paths += sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua'))
    paths += sorted((ROOT / 'ForeverRosettaStone_Data').rglob('*.lua'))
    paths += [ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc', Path(__file__)]
    paths += [ROOT / 'tests/python/database_harness.py', ROOT / 'tests/lua/support/client-api-fixture.lua']
    return {'captureSha256': hashlib.sha256(capture.read_bytes()).hexdigest(),
            'files': {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--capture', required=True, type=Path, help='Backed-up rosetta-tooltip-check.lua')
    parser.add_argument('--run', type=int, help='1-based api run (default: the last finished api run)')
    parser.add_argument('--output', required=True, type=Path, help='New directory under datasources/imports/')
    parser.add_argument('--targets', nargs='+', help='Target locales (default: every pack except the client)')
    parser.add_argument('--kinds', nargs='+', choices=sorted(APIS), default=sorted(APIS))
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / 'datasources/imports').resolve()) or output.exists():
        parser.error('--output must be a new directory under datasources/imports/')
    result = report(args.capture, args.run, args.targets, tuple(args.kinds))
    output.mkdir(parents=True)
    (output / 'report.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (output / 'report.md').write_text(markdown(result), encoding='utf-8')
    print(f"{result['rendered']} renders, {result['incomplete']} incomplete, {len(result['groups'])} gap groups, "
          f"{result['errorCount']} errors → {output / 'report.md'}")


if __name__ == '__main__':
    main()
