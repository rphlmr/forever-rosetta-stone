"""Run production with ID-based identity and forbidden reverse lookups/recalculation."""

import collections
import functools
import hashlib
import json
import math
import re
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from lupa.lua51 import LuaRuntime

from database_harness import install_metadata, read_metadata
from matrix_classification import classify_failure, summarize_report


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


NATIVE_TEXT = '__ID_ONLY_NATIVE_TEXT_MUST_NOT_BE_RENDERED__'
PROFILES = {
    'baseline': {'level': 1, 'known': False, 'sex': 2, 'current': 0, 'required': 5,
                 'factionReactions': {92: 4, 93: 4}},
    'modified': {'level': 60, 'known': True, 'sex': 3, 'current': 2, 'required': 9,
                 'factionReactions': {92: 5, 93: 5}},
}


def required_locales(root=ROOT):
    return list(load_catalog(root, 'quests', ids={})['locales'])


def to_python(value):
    if isinstance(value, bytes):
        return value.decode('utf-8')

    if hasattr(value, 'items'):
        entries = dict(value.items())

        if entries and set(entries) == set(range(1, len(entries) + 1)):
            return [to_python(entries[index]) for index in range(1, len(entries) + 1)]

        return {to_python(key): to_python(child) for key, child in entries.items()}

    if isinstance(value, (list, tuple)):
        return [to_python(child) for child in value]

    if isinstance(value, dict):
        return {to_python(key): to_python(child) for key, child in value.items()}

    return value


class CaseReporter:
    """Count every required case; missing expectations and native fallbacks fail coverage."""

    def __init__(self, kind, locales, profiles):
        self.kind = kind
        self.locales = list(locales)
        self.profiles = list(profiles)
        self.counts = collections.Counter(cases=0, passed=0, failed=0)
        self.failures = []
        self.not_applicable_cases = {}
        self.mandatory_masks = {}
        self.mandatory_field = 'title' if kind == 'quests' else 'name'
        self.interface_errors = []

    def record(self, case, expected, actual, error=None, forbidden=None, reason=None):
        if case.get('field') == self.mandatory_field:
            try:
                bit = 1 << (self.locales.index(case['locale']) * len(self.profiles)
                            + self.profiles.index(case['profile']))
                previous = self.mandatory_masks.get(int(case['id']), 0)

                if previous & bit:
                    self.interface_errors.append({**case, 'reason': 'duplicate mandatory case'})

                self.mandatory_masks[int(case['id'])] = previous | bit
            except (KeyError, ValueError):
                self.interface_errors.append({**case, 'reason': 'invalid mandatory case identity'})

        if isinstance(actual, tuple):
            returned = actual
            actual = returned[0] if returned else None

            if len(returned) > 2 and returned[2]:
                reason = reason or 'nativeFallback'
            elif len(returned) == 2 and actual is None and returned[1] is not None:
                error = error or str(to_python(returned[1]))

        expected, actual = to_python(expected), to_python(actual)
        self.counts['cases'] += 1

        if forbidden:
            failure = 'forbiddenDependency'
        elif error:
            failure = 'runtimeError'
        elif reason:
            failure = reason
        elif expected is None or expected == '':
            failure = 'missingTranslation'
        elif actual is None or actual == '':
            failure = 'untranslated'
        elif NATIVE_TEXT in str(actual):
            failure = 'nativeFallback'
        elif actual != expected:
            failure = 'mismatch'
        else:
            self.counts['passed'] += 1
            return True

        self.counts['failed'] += 1
        self.counts[failure] += 1
        row = {**case, 'reason': failure}
        if reason and reason != failure:
            row['expectationReason'] = reason

        for key, value in (('expected', expected), ('actual', actual), ('error', error)):
            if value is not None:
                text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, sort_keys=True)
                row[key + 'Preview'] = text[:160]
                row[key + 'Sha256'] = hashlib.sha256(text.encode()).hexdigest()

        if forbidden:
            row['forbiddenCalls'] = list(forbidden)

        diagnostic = classify_failure(self.kind, row)
        row.update(category=diagnostic['category'], diagnosticCode=diagnostic['code'])
        self.failures.append(row)
        return False

    def not_applicable(self, case, reason):
        identity = {key: value for key, value in case.items() if key not in ('locale', 'profile')}
        key = json.dumps([identity, reason], sort_keys=True)
        row = self.not_applicable_cases.setdefault(key, {**identity, 'reason': reason, 'caseCount': 0})
        row['caseCount'] += 1
        self.counts['notApplicable'] += 1

    def finish(self, entity_ids, exclusions=None, full_scope=True):
        entity_ids = sorted(map(int, entity_ids))
        missing = []

        for entity_id in entity_ids:
            mask = self.mandatory_masks.get(entity_id, 0)

            for locale_index, locale in enumerate(self.locales):
                for profile_index, profile in enumerate(self.profiles):
                    bit = 1 << (locale_index * len(self.profiles) + profile_index)

                    if not mask & bit:
                        missing.append({'id': entity_id, 'locale': locale, 'profile': profile})

        report = {
            'kind': self.kind,
            'entityCount': len(entity_ids),
            'entityIds': entity_ids,
            'locales': self.locales,
            'profiles': self.profiles,
            'fullScope': full_scope,
            'counts': dict(self.counts),
            'failures': self.failures,
            'notApplicable': list(self.not_applicable_cases.values()),
            'excluded': exclusions or [],
            'mandatoryCoverage': {'field': self.mandatory_field,
                                  'requiredPerEntity': len(self.locales) * len(self.profiles),
                                  'missingCases': missing},
            'interfaceErrors': self.interface_errors,
        }
        report['diagnostics'] = summarize_report(report)
        return report


class IdOnlyHarness:
    """Load shipped records and allow live values only after an entity has been selected by ID."""

    def __init__(self, root=ROOT):
        self.root = Path(root)
        self.lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
        self.forbidden_calls = []
        self.runtime_sources = {}
        self.spell_icons = {}
        for name in ('spell-icons-70888.json', 'spell-icons-70938.json'):
            fixture = json.loads((self.root / 'tests/fixtures' / name).read_text())
            self.spell_icons.update({int(spell_id): icon for spell_id, icon in fixture['icons'].items()})
        self.lua_icons = self.to_lua(self.spell_icons)
        install_metadata(self.lua, read_metadata(self.root / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        codec = self.lua.globals().C_EncodingUtil

        for key in (b'DecodeBase64', b'DecompressString', b'DeserializeCBOR'):
            codec[key] = functools.lru_cache(maxsize=None)(codec[key])

        self._load(self.root / 'ForeverRosettaStone/database/database-api.lua', self.lua.table())
        self.db = self.lua.globals().ForeverRosettaStoneDB
        self.lua.globals().HarnessForbidden = self._forbidden
        self.lua.globals().HarnessNative = NATIVE_TEXT.encode()
        self.lua.execute(b'''
            local function Blocked(name)
                return function(...) return HarnessForbidden(name) end
            end
            local matchingFields = {
                sourceNames = true, sourceDescriptions = true, sourceAuraDescriptions = true,
                sourceRanks = true, sourceNameDescriptions = true, sourceTitles = true,
                sourceSummaries = true, sourceObjectiveLines = true,
            }
            local cleaned = {}
            local function Clean(value)
                if type(value) ~= 'table' then return value end
                if cleaned[value] then return cleaned[value] end
                local result = {}
                cleaned[value] = result
                for key, child in pairs(value) do
                    if not matchingFields[key] then result[key] = Clean(child) end
                end
                return result
            end
            local db = ForeverRosettaStoneDB
            for _, key in ipairs({'GetSpellDetails', 'GetItemDetails', 'GetQuest'}) do
                local getter = db[key]
                db[key] = function(self, ...) return Clean(getter(self, ...)) end
            end
            for _, key in ipairs({'GetQuestSource', 'GetSpellSourceDetails', 'GetItemSourceDetails',
                'GetSourceSpellName', 'GetFactionSourceName', 'TranslateItemName', 'TranslateAreaName',
                'ResolveQuestID'}) do db[key] = Blocked('database:' .. key) end
            GetLocale = function() return 'enUS' end
            canaccessallvalues = function() return true end
            UnitName = function() return 'TestName' end
            UnitClass = function() return 'Warrior', 'WARRIOR' end
            UnitRace = function() return 'Human', 'Human' end
            UnitSex = function() return HarnessProfile.sex end
            UnitLevel = function(unit)
                if unit ~= 'player' then return HarnessForbidden('unsupportedContext:UnitLevel') end
                return HarnessProfile.level
            end
            UnitStat = Blocked('recalculation:UnitStat')
            GetSpellBonusDamage = Blocked('recalculation:GetSpellBonusDamage')
            GetSpellBonusHealing = Blocked('recalculation:GetSpellBonusHealing')
            C_UnitAuras = {GetAuraDataByAuraInstanceID = function()
                return {spellId = HarnessEntityID, points = {}, expirationTime = 0}
            end}
            C_SpellBook = {IsSpellKnown = Blocked('recalculation:C_SpellBook')}
            C_QuestLog = {GetQuestObjectives = function() return HarnessObjectives end}
            C_Reputation = {GetFactionDataByID = function(id)
                local reaction = HarnessProfile.factionReactions[id]
                if reaction then return {factionID = id, reaction = reaction} end
            end}
            GetQuestID = function() return HarnessOffer and HarnessEntityID or 0 end
            GetObjectiveText = Blocked('client:GetObjectiveText')
            GetQuestText = Blocked('client:GetQuestText')
            GetSpellDescription = Blocked('client:GetSpellDescription')
            GetSpellInfo = Blocked('client:GetSpellInfo')
            GetItemInfo = Blocked('client:GetItemInfo')
            C_Spell = {
                GetSpellTexture = function(spellID) return HarnessIcons[spellID] end,
                GetSpellDescription = Blocked('client:C_Spell.GetSpellDescription'),
                GetSpellName = Blocked('client:C_Spell.GetSpellName'),
                GetSpellSubtext = Blocked('client:C_Spell.GetSpellSubtext'),
            }
            C_Item = {GetItemInfo = Blocked('client:C_Item.GetItemInfo')}
            GetTime = function() return 100 end
            Enum = {TooltipDataType = {Spell = 1, Item = 2, UnitAura = 7}, TooltipDataLineType = {
                ItemName = 22, SpellName = 13, SpellDescription = 34, EquipSlot = 21,
                SellPrice = 11, FlavorText = 37, ItemSpellTriggerLearn = 38, ItemSpellTriggerOnUse = 44,
                ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46,
            }, TraitConfigType = {Generic = 3}}
            C_Traits = {GetConfigsByType = Blocked('recalculation:C_Traits')}
            addon = {
                GetTargetLocale = function() return HarnessTargetLocale end,
                BeginBenchmarkSample = function() end, EndBenchmarkSample = function() end,
                GetTooltipAuraData = function() return HarnessAura end,
            }
        ''')
        self.addon = self.lua.globals().addon

        for name in ('locales/faction-standing-locales', 'database/item-data', 'tooltips/english-tooltip-formats', 'tooltips/localized-tooltip-formats',
                     'database/localized-item-data', 'tooltips/client-labels', 'tooltips/spell-live-values', 'tooltips/tooltip-descriptions', 'quests/quest-data'):
            self._load(self.root / 'ForeverRosettaStone' / (name + '.lua'), self.addon)

        for path in sorted((self.root / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
            self._load(path, self.addon)

        self._load(self.root / 'ForeverRosettaStone/tooltips/tooltip-extra-formats.lua', self.addon)
        self.lua.globals().HarnessIcons = self.lua_icons
        self.profile_cache = {}
        self.client_strings = json.loads((self.root / 'tests/fixtures/tooltip-client-strings.json').read_text())['strings']
        self.set_context('enUS', 1, 'baseline')

    def _load(self, path, addon):
        source = path.read_bytes()
        self.runtime_sources[str(path.relative_to(self.root))] = hashlib.sha256(source).hexdigest()
        self.lua.eval(b'function(source, addon) assert(loadstring(source))("id-only-matrix", addon) end')(source, addon)

    def _forbidden(self, name):
        label = to_python(name)
        self.forbidden_calls.append(label)
        raise RuntimeError('Native-text dependency disabled: ' + label)

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({key.encode() if isinstance(key, str) else key: self.to_lua(child)
                                        for key, child in value.items()})

        if isinstance(value, (list, tuple)):
            return self.lua.table_from([self.to_lua(child) for child in value])

        return value.encode() if isinstance(value, str) else value

    def from_lua(self, value):
        return to_python(value)

    def set_context(self, locale, entity_id, profile_name, entity_kind=None):
        key = (entity_kind, int(entity_id), profile_name)
        if key not in self.profile_cache:
            profile = dict(PROFILES[profile_name])
            lua_profile = self.to_lua(profile)
            profile['spellIcons'] = self.spell_icons
            self.profile_cache[key] = (profile, lua_profile)
        self.profile, lua_profile = self.profile_cache[key]
        state = self.lua.globals()
        self.set_source_locale('enUS')
        state.HarnessTargetLocale = locale.encode()
        state.HarnessEntityID = int(entity_id)
        state.HarnessProfile = lua_profile
        state.HarnessOffer = False
        state.HarnessObjectives = self.lua.table()
        state.HarnessAura = None
        self.forbidden_calls.clear()

    def set_source_locale(self, locale):
        self.lua.globals().GetLocale = self.lua.eval(b'function(locale) return function() return locale end end')(locale.encode())
        # Clear the previous client's globals before installing the next client's formats.
        for key, values in self.client_strings.items():
            value = values.get(locale)
            self.lua.globals()[key.encode()] = value.encode() if value is not None else None

    def set_objectives(self, rows):
        self.lua.globals().HarnessObjectives = self.to_lua(rows)

    def set_verified_factions(self, faction_ids, profile_name):
        # Synthetic test values are assigned only to explicit verified quest bindings.
        reaction = 4 if profile_name == 'baseline' else 5
        self.profile = {**self.profile, 'factionReactions': {faction_id: reaction for faction_id in faction_ids}}
        self.lua.globals().HarnessProfile = self.to_lua(self.profile)

    def set_offer(self, offered):
        self.lua.globals().HarnessOffer = bool(offered)

    def attempt(self, operation):
        self.forbidden_calls.clear()

        try:
            actual = operation()
            error = None
        except Exception as cause:
            actual, error = None, str(cause)

        return actual, error, list(self.forbidden_calls)
