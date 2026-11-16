"""Check maintained item text against the built database and tooltip renderer.

Native text comes from retained catalog evidence. These inputs are synthetic tooltip
lines, not captures from a running client. Unsupported fixture grammar is reported as a gap.
"""

import json
import re
import sys
import time
from collections import Counter
from functools import lru_cache

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from id_only_matrix_harness import PROFILES
from live_spell_fixture import FixtureUnavailable, make_fixture


FIELDS = ('description', 'nameDescription', 'setName')
def get_source(entity, locale, field):
    tooltip = entity.get('tooltipData', {})
    original = entity.get('locales', {}).get(locale, {})
    metadata = original.get('translationMetadata', {}).get('fields', {}).get(field, {})

    if metadata.get('origin') == 'ai':
        return None

    value = original.get(field)

    if field == 'setName' and locale == 'enUS':
        value = value or tooltip.get('set', {}).get('name')

    return value


def get_target(entity, locale, field):
    original = entity.get('locales', {}).get(locale)
    if not original:
        return None

    if field == 'setName' and locale == 'enUS':
        return original.get(field) or entity.get('tooltipData', {}).get('set', {}).get('name')

    return original.get(field)


def main(item_ids=None):
    document = load_catalog(ROOT, 'items')
    items = document['catalogs']['items']
    if item_ids is not None:
        items = {item_id: items[item_id] for item_id in item_ids}
    configuration = load_catalog(ROOT, 'quests', ids=[])
    targets = configuration['locales']
    sources = [locale for locale in targets if locale not in configuration['rosettaLocales']]
    spells = load_catalog(ROOT, 'spells')['catalogs']['spells']
    client_strings = json.loads((ROOT / 'tests/fixtures/tooltip-client-strings.json').read_text())['strings']
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
    codec = lua.globals().C_EncodingUtil
    for name in (b'DecodeBase64', b'DecompressString', b'DeserializeCBOR'):
        codec[name] = lru_cache(maxsize=None)(codec[name])
    load_database(lua)
    run_item = lua.execute(b'''
        canaccessallvalues = function() return true end
        GetLocale = function() return sourceLocale end
        C_Spell = { GetSpellTexture = function(id) return id + 100000 end }
        Enum = { TooltipDataLineType = { FlavorText = 37, ItemSpellTriggerLearn = 38, ItemSpellTriggerOnUse = 44,
            ItemSpellTriggerOnEquip = 45, ItemSpellTriggerOnProc = 46 } }
        local addon = {}
        for _, path in ipairs({"database/item-data", "tooltips/english-tooltip-formats", "tooltips/localized-tooltip-formats",
            "database/localized-item-data", "tooltips/client-labels", "tooltips/spell-live-values", "tooltips/tooltip-descriptions"}) do
            assert(loadfile("ForeverRosettaStone/" .. path .. ".lua"))("ForeverRosettaStone", addon)
        end
        for _, path in ipairs({"cs-cz", "da-dk", "hr-hr", "it-it", "pl-pl", "sv-se", "tr-tr", "uk-ua"}) do
            assert(loadfile("ForeverRosettaStone/locales/tooltips/" .. path .. ".lua"))("ForeverRosettaStone", addon)
        end
        local database = ForeverRosettaStoneDB
        ForeverRosettaStoneDB = { GetItemDetails = function() return {description = "Translated"} end,
            GetItemRules = function() return nil end }
        sourceLocale = "frFR"
        assert(addon:GetLocalizedTooltipLine({type = 37, leftText = "Native"}, "item", 1, "deDE") == "Translated")
        assert(addon:GetLocalizedTooltipLine({leftText = "Native"}, "item", 1, "deDE") == nil)
        assert(addon:GetEnglishTooltipLine({}, {leftText = "Native"}, "item", 1) == nil)
        ForeverRosettaStoneDB = database
        MatrixTargetFormats = addon.tooltipFormatsByLocale
        MatrixSourceGlobals = {}
        local function setSource(source)
            sourceLocale = source
            for _, key in ipairs({"SECONDS_ABBR", "MINUTES_ABBR", "HOURS_ABBR", "DAYS_ABBR",
                "SECOND_ONELETTER_ABBR", "MINUTE_ONELETTER_ABBR", "HOUR_ONELETTER_ABBR",
                "DAY_ONELETTER_ABBR", "SPELL_DURATION_UNTIL_CANCELLED"}) do _G[key] = nil end
            for key, value in pairs(MatrixSourceGlobals[source] or {}) do _G[key] = value end
        end
        return function(id, sources, targets, linked)
            local failures, checked = {}, 0
            local rules = ForeverRosettaStoneDB:GetItemRules(id)
            local binding = rules and rules.descriptionRow
            for locale, expected in pairs(targets) do
                local name = ForeverRosettaStoneDB:GetItemName(id, locale)
                local details = ForeverRosettaStoneDB:GetItemDetails(id, locale)
                for field, value in pairs(expected) do
                    local actual = field == "name" and name or field == "setName" and details and details.set
                        and details.set.name or details and details[field]
                    checked = checked + 1
                    if actual ~= value then failures[#failures + 1] = {"database", locale, field, value, actual} end
                end
            end
            for source, fields in pairs(sources) do
                setSource(source)
                local details = ForeverRosettaStoneDB:GetItemDetails(id, source)
                for field, value in pairs(fields) do
                    if field ~= "name" then
                        local actual = field == "setName" and details and details.set and details.set.name
                            or details and details[field]
                        checked = checked + 1
                        if actual ~= value then failures[#failures + 1] = {"source database", source, field, value, actual} end
                        for target, translations in pairs(targets) do
                            local expected = translations[field]
                            if expected and field == "description" then
                                local line = {type = 37, leftText = value}
                                if binding then
                                    line = {type = 38, spellID = binding.spellID, leftText = "Unrelated native row"}
                                    local formats = target == "enUS" and addon.englishTooltipFormats
                                        or addon.tooltipFormatsByLocale[target]
                                    local prefix = formats and formats.ITEM_SPELL_TRIGGER_ONUSE
                                    expected = prefix and prefix .. " " .. expected
                                end
                                local actualText, _, incomplete = addon:GetLocalizedTooltipLine(
                                    line, "item", id, target)
                                checked = checked + 1
                                if not expected or actualText ~= expected or incomplete then
                                    failures[#failures + 1] = {"render", source, target, field, value, expected,
                                        actualText, incomplete}
                                end
                                if binding then
                                    local flavor = addon:GetLocalizedTooltipLine(
                                        {type = 37, leftText = "Unrelated native flavor"}, "item", id, target)
                                    local expectedFlavor = source == target and "Unrelated native flavor" or nil
                                    checked = checked + 1
                                    if flavor ~= expectedFlavor then
                                        failures[#failures + 1] = {"render", source, target, field,
                                            "Unrelated native flavor", expectedFlavor, flavor, false}
                                    end
                                end
                            end
                        end
                    end
                end
            end
            for _, case in ipairs(linked) do
                setSource(case.source)
                local profile = MatrixProfiles[case.profile]
                local function forbidden() error('Effect descriptions must capture displayed values') end
                C_SpellBook = { IsSpellKnown = forbidden }
                UnitLevel = forbidden
                UnitSex = function() return profile.sex end
                UnitStat, GetSpellBonusDamage, GetSpellBonusHealing = forbidden, forbidden, forbidden
                _G[case.key] = case.nativeFormat
                local formats = addon.tooltipFormatsByLocale[case.target]
                local targetFormat = formats and formats[case.key]
                local native = case.bonus and string.format(case.nativeFormat, case.native)
                    or case.nativeFormat .. " " .. case.native
                local expected = targetFormat and (case.bonus and string.format(targetFormat, case.expected):gsub("%%%%", "%%")
                    or targetFormat .. " " .. case.expected)
                if expected then
                    local actual, _, incomplete = addon:GetLocalizedTooltipLine(
                        {type = case.lineType, spellID = tonumber(case.spell), leftText = native}, "item", id, case.target)
                    checked = checked + 1
                    if actual ~= expected or incomplete then
                        failures[#failures + 1] = {"linked render", case.source, case.target, case.spell,
                            native, expected, actual, incomplete}
                    end
                else
                    failures[#failures + 1] = {"missing target format", case.target, case.key}
                end
                _G[case.key] = nil
            end
            return checked, failures
        end
    ''')
    counts = Counter()
    gaps, failures = [], []
    def to_lua(value):
        if isinstance(value, dict):
            return lua.table_from({(key.encode() if isinstance(key, str) else key): to_lua(child)
                                   for key, child in value.items()})
        if isinstance(value, (list, tuple)):
            return lua.table_from([to_lua(child) for child in value])
        return value.encode() if isinstance(value, str) else value

    lua.globals().MatrixProfiles = to_lua(PROFILES)
    duration_keys = ('SECONDS_ABBR', 'MINUTES_ABBR', 'HOURS_ABBR', 'DAYS_ABBR',
                     'SECOND_ONELETTER_ABBR', 'MINUTE_ONELETTER_ABBR', 'HOUR_ONELETTER_ABBR',
                     'DAY_ONELETTER_ABBR', 'SPELL_DURATION_UNTIL_CANCELLED')
    for source in sources:
        source_key = source
        source_globals = {key.encode(): client_strings[key][source_key].encode() for key in duration_keys
                          if source_key in client_strings.get(key, {})}
        lua.globals().MatrixSourceGlobals[source.encode()] = lua.table_from(source_globals)

    @lru_cache(maxsize=None)
    def get_linked_case(spell_id, source, target, key, bonus, known):
        if bonus:
            return None, 'unsupported structured set bonus row identity'
        spell = spells.get(str(spell_id))
        if not spell:
            return None, 'missing linked spell'
        native = get_source(spell, source, 'description')
        translated = get_target(spell, target, 'description')
        if not native and not translated:
            return None, 'missing native source and target wording'
        if not native:
            return None, 'missing native source'
        if not translated:
            return None, 'missing target wording'
        native_format = client_strings.get(key, {}).get(source)
        if not native_format:
            return None, 'missing native format'
        try:
            display = make_fixture(spells, spell_id, target,
                                   'modified' if known else 'baseline', source=source)
            native_text, target_text = display['native'], display['expected']
        except FixtureUnavailable as cause:
            return None, 'unsupported live-value fixture: ' + str(cause)
        return {'source': source, 'target': target, 'spell': str(spell_id), 'key': key, 'bonus': bonus,
                'lineType': {'ITEM_SPELL_TRIGGER_ONUSE': 44, 'ITEM_SPELL_TRIGGER_ONEQUIP': 45,
                             'ITEM_SPELL_TRIGGER_ONPROC': 46}[key],
                'known': known, 'profile': 'modified' if known else 'baseline',
                'nativeFormat': native_format, 'native': native_text, 'expected': target_text}, None

    for index, (item_id, entity) in enumerate(items.items(), start=1):
        item_started = time.monotonic()
        if index % 1000 == 0:
            print(f'Item matrix progress: {index}/{len(items)} items, current item {item_id}', flush=True)
        source_values = {locale: {field: value for field in ('name', *FIELDS)
                                  if (value := get_source(entity, locale, field))} for locale in sources}
        target_values = {locale: {field: value for field in ('name', *FIELDS)
                                  if (value := get_target(entity, locale, field))} for locale in targets}
        present_fields = {field for values in (*source_values.values(), *target_values.values()) for field in values}
        for field in present_fields:
            missing_sources = [locale for locale in sources if field not in source_values[locale]]
            missing_targets = [locale for locale in targets if field not in target_values[locale]]
            if missing_sources:
                gaps.append({'item': item_id, 'field': field, 'kind': 'missing native source', 'locales': missing_sources})
            if missing_targets:
                gaps.append({'item': item_id, 'field': field, 'kind': 'missing target wording', 'locales': missing_targets})
            counts['field locale pairs accounted'] += len(sources) * len(targets)
            if field in ('nameDescription', 'setName'):
                gaps.append({'item': item_id, 'field': field, 'kind': 'unsupported structured row identity',
                             'cases': len(sources) * len(targets)})

        tooltip = entity.get('tooltipData', {})
        trigger_keys = {0: 'ITEM_SPELL_TRIGGER_ONUSE', 1: 'ITEM_SPELL_TRIGGER_ONEQUIP',
                        2: 'ITEM_SPELL_TRIGGER_ONPROC'}
        links = [('effect', effect.get('spellID'), trigger_keys.get(effect.get('triggerType')), False)
                 for effect in tooltip.get('effects', [])]
        links += [('set bonus', bonus.get('spellID'), 'ITEM_SET_BONUS', True)
                  for bonus in tooltip.get('set', {}).get('bonuses', [])]
        linked_cases = []
        for field, spell_id, key, bonus in links:
            grouped_gaps = {}
            for source in sources:
                for target in targets:
                    for known in (False, True):
                        case, reason = (get_linked_case(spell_id, source, target, key, bonus, known)
                                        if key and spell_id else (None, 'unsupported trigger or missing spell ID'))
                        if case:
                            linked_cases.append(case)
                        else:
                            grouped_gaps.setdefault(reason, []).append([source, target, known])
                            counts['linked synthetic cases unverified'] += 1
            for reason, pairs in grouped_gaps.items():
                gap = {'item': item_id, 'field': field, 'spell': spell_id, 'kind': reason, 'cases': pairs}
                if reason.startswith(('unsupported renderer grammar', 'unsupported fixture', 'ambiguous aura',
                                      'unverified differing level')):
                    spell = spells[str(spell_id)]
                    gap['templates'] = [{'source': source, 'target': target,
                                         'native': get_source(spell, source, 'description'),
                                         'translated': get_target(spell, target, 'description')}
                                        for source, target in sorted({(source, target) for source, target, _ in pairs})]
                gaps.append(gap)
        counts['linked synthetic cases attempted'] += len(linked_cases)

        encode = lambda value: value.encode() if isinstance(value, str) else value
        to_lua = lambda values: lua.table_from({encode(k): lua.table_from({encode(f): encode(v) for f, v in row.items()})
                                                for k, row in values.items()})
        linked_lua = lua.table_from([lua.table_from({encode(k): encode(v) for k, v in case.items()})
                                     for case in linked_cases])
        checked, item_failures = run_item(int(item_id), to_lua(source_values), to_lua(target_values), linked_lua)
        counts['database and renderer checks'] += checked
        for row in item_failures.values():
            size = {b'database': 5, b'source database': 5, b'render': 8, b'linked render': 8,
                    b'missing target format': 3}[row[1]]
            values = [row[position] for position in range(1, size + 1)]
            failures.append([item_id] + [value.decode() if isinstance(value, bytes) else value for value in values])
        item_seconds = time.monotonic() - item_started
        if item_seconds >= 5:
            print(f'Slow item {item_id}: {item_seconds:.1f} seconds', flush=True)

    report = ROOT / ('datasources/imports/tooltip-matrix/items.json' if item_ids is None
                     else 'datasources/imports/tooltip-matrix/items-focused.json')
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({'synthetic': True, 'items': len(items), 'sources': sources, 'targets': targets,
                                  'counts': counts, 'gaps': gaps, 'failures': failures}, ensure_ascii=False))
    print(f'Item matrix: {len(items)} items, {len(sources)} sources x {len(targets)} targets; {dict(counts)}')
    print(f'{len(gaps)} grouped gaps, {len(failures)} mismatches: {report}')
    assert not failures, f'Item matrix has {len(failures)} mismatches; see {report}'


if __name__ == '__main__':
    main(sys.argv[1:] or None)
