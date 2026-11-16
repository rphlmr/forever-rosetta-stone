"""Exercise bounded translation surfaces across native and target locales."""

import json
import re
import sys
from collections import Counter

from lupa.lua51 import LuaRuntime

from database_harness import ROOT, install_metadata, load_database, read_metadata

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


def run_matrix():
    config = load_catalog(ROOT, 'quests', ids={})
    targets = config['locales']
    clients = [locale for locale in targets if locale not in config['rosettaLocales']]
    lua = LuaRuntime(encoding=None, unpack_returned_tuples=True)
    lua.execute(b'''
        addon = {}
        canaccessallvalues = function() return true end
        function GetLocale() return sourceLocale end
        function addon:GetTargetLocale() return targetLocale end
        function addon:BeginBenchmarkSample() end
        function addon:EndBenchmarkSample() end
        function UnitName() return 'Rosetta' end
        function UnitRace() return 'Human', 'Human' end
        function UnitClass() return 'Mage', 'MAGE' end
        function UnitSex() return 2 end
        C_QuestLog = { GetQuestObjectives = function() return liveObjectives end }
        assert(loadfile('ForeverRosettaStone/database/item-data.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/tooltips/english-tooltip-formats.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/tooltips/character-stat-formats.lua'))('addon', addon)
        nativeStatFormats = {}
        for locale, formats in pairs(addon.characterStatFormats) do nativeStatFormats[locale] = formats end
        assert(loadfile('ForeverRosettaStone/locales/character-stat-locales.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/tooltips/localized-tooltip-formats.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/database/localized-item-data.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/tooltips/spell-live-values.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/tooltips/tooltip-descriptions.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/quests/quest-data.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/quests/missing-quest.lua'))('addon', addon)
        assert(loadfile('ForeverRosettaStone/quests/quest-page.lua'))('addon', addon)
        for i = 1, 20 do
            local name, value = debug.getupvalue(addon.CreateQuestPage, i)
            if name == 'GetRewardName' then rewardName = value end
        end
        assert(rewardName, 'quest reward name renderer not found')
        function rewardSource(kind, text)
            return { objectType = kind, type = rewardType, GetID = function() return 1 end,
                Name = { GetText = function() return text end } }
        end
        function GetQuestLogChoiceInfo() return nil, nil, nil, nil, nil, rewardID end
        function GetQuestLogRewardInfo() return nil, nil, nil, nil, nil, rewardID end
        function setStats(locale)
            for _, formats in pairs(nativeStatFormats) do
                for key in pairs(formats) do _G[key] = nil end
            end
            for key, value in pairs(nativeStatFormats[locale]) do _G[key] = value end
        end
    ''')
    for path in sorted((ROOT / 'ForeverRosettaStone/locales/tooltips').glob('*.lua')):
        lua.execute(path.read_bytes(), b'addon', lua.globals().addon)
    for name in ('tooltips/appearance-tooltip-formats.lua', 'tooltips/tooltip-extra-formats.lua'):
        lua.execute((ROOT / 'ForeverRosettaStone' / name).read_bytes(), b'addon', lua.globals().addon)
    install_metadata(lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
    db = load_database(lua)
    globals_ = lua.globals()
    addon = globals_.addon
    report = {'missingTarget': [], 'missingSource': [], 'unsupportedShape': [], 'statCandidates': [],
              'boundaries': [], 'failures': []}
    counts = Counter()
    english_stats = addon.characterStatFormats.enUS
    italian_stats = globals_.nativeStatFormats.itIT
    assert dict(italian_stats.items()) == dict(english_stats.items()), (
        'Italian stat export changed; update its target-coverage classification'
    )
    for locale in config['rosettaLocales']:
        stat_formats = addon.characterStatFormats[locale.encode()]
        shared_formats = addon.tooltipFormatsByLocale[locale.encode()]
        expected_keys = set(addon.characterStatFormats.enUS.keys()) & set(shared_formats.keys())
        assert set(stat_formats.keys()) == set(english_stats.keys()), f'Incomplete stat target keys for {locale}'
        for key in expected_keys:
            assert stat_formats[key] == shared_formats[key], (locale, key)
        counts['reused stat keys'] += len(expected_keys)

    def failure(kind, client, target, field, expected, actual, source=None):
        report['failures'].append({'kind': kind, 'client': client, 'target': target, 'field': field,
                                   'source': source, 'expected': expected, 'actual': actual})

    def normalize_stat(value):
        value = re.sub(rb'\|[cC][0-9a-fA-F]{8}|\|[rR]|\|T.*?\|t', b'', value)
        return re.sub(rb'[ \t\r\n]+', b' ', value.replace(b'\xc2\xa0', b' ').replace(b'\xe2\x80\xaf', b' '))

    token = re.compile(rb'%(?:[-+0-9.]*[dsfFgc%])')

    def synthesize(value):
        return token.sub(lambda match: {
            b'd': b'17', b's': b'17', b'f': b'17.25', b'F': b'17.25', b'g': b'17.25',
            b'c': b'+', b'%': b'%',
        }[match.group()[-1:]], value)

    assert set(addon.characterStatFormats.itIT.keys()) == set(english_stats.keys())
    assert dict(addon.characterStatFormats.itIT.items()) != dict(italian_stats.items()), 'Italian targets use English fallback'
    for client in clients:
        globals_.sourceLocale = client.encode()
        globals_.setStats(client.encode())
        source_formats = globals_.nativeStatFormats[client.encode()]
        missing = addon.GetMissingQuestText(addon)
        for key in ('title', 'summary', 'description', 'questID', 'beer', 'report'):
            counts['missing quest fields'] += 1
            if not missing[key.encode()]:
                failure('missing quest', client, None, key, 'nonempty string', None)

        for target in targets:
            globals_.targetLocale = target.encode()
            for reward_type in (b'choice', b'reward'):
                globals_.rewardType = reward_type
                globals_.rewardID = 100
                native_reward = b'Native item'
                expected_reward = db.GetItemName(db, 100, target.encode()) or native_reward
                actual_reward = globals_.rewardName(globals_.rewardSource(b'item', native_reward))
                counts['reward item names'] += 1
                if actual_reward != expected_reward:
                    failure('reward', client, target, reward_type.decode(), expected_reward.decode(),
                            actual_reward.decode() if actual_reward else None)
                globals_.rewardID = 999999999
                actual_reward = globals_.rewardName(globals_.rewardSource(b'item', native_reward))
                counts['unknown reward items'] += 1
                if actual_reward != native_reward:
                    failure('reward', client, target, 'unknown item', native_reward.decode(),
                            actual_reward.decode() if actual_reward else None)
            counts['numeric rewards'] += 1
            assert globals_.rewardName(globals_.rewardSource(b'currency', b'1050')) == b'1050'
            for key in ('description', 'rewards', 'complete', 'receive'):
                counts['quest labels'] += 1
                if not addon.GetQuestLabel(addon, key.encode()):
                    failure('quest label', client, target, key, 'nonempty string', None)

            # Objective counts come from the live API rather than translated prose.
            globals_.liveObjectives = lua.table_from([lua.table_from({b'numRequired': 7})])
            formatted = addon.FormatQuestText(addon, b'$N $R $C $1oa', 123)
            counts['quest placeholders'] += 1
            if b'Rosetta' not in formatted or b'7' not in formatted or b'$' in formatted:
                failure('quest placeholders', client, target, 'player and objective', 'substituted', formatted.decode())

            target_formats = addon.characterStatFormats[target.encode()]
            if target_formats is None:
                report['missingTarget'].append({'kind': 'character stat', 'client': client, 'target': target,
                                                'field': 'formats', 'reason': 'no target stat format map'})
            source_keys = sorted(set(source_formats.keys()) | (set(target_formats.keys()) if target_formats else set()))
            matching_keys = {}
            for source_key in source_formats.keys():
                source_format = source_formats[source_key]
                if source_key in (b'STAT_FORMAT', b'WEAPON_SKILL_PAPERDOLLFRAME_FORMAT',
                                  b'PAPERDOLLFRAME_TOOLTIP_FORMAT'):
                    source_format = source_format.replace(b'%s', source_formats[b'HEALTH'])
                matching_keys.setdefault(normalize_stat(synthesize(source_format)), []).append(source_key)
            for key in (source_keys if target_formats else ()):
                source, expected = source_formats[key], target_formats[key]
                if not source or not expected:
                    report['missingSource' if not source else 'missingTarget'].append(
                        {'kind': 'character stat', 'client': client, 'target': target, 'field': key.decode(),
                         'reason': 'missing keyed format'})
                    continue
                if any(marker in source or marker in expected for marker in (b'|4', b'|2', b'$')):
                    report['unsupportedShape'].append({'kind': 'character stat', 'client': client,
                        'target': target, 'field': key.decode(), 'reason': 'grammar or positional format'})
                    continue
                if key in (b'STAT_FORMAT', b'WEAPON_SKILL_PAPERDOLLFRAME_FORMAT', b'PAPERDOLLFRAME_TOOLTIP_FORMAT'):
                    source = source.replace(b'%s', source_formats[b'HEALTH'])
                    expected = expected.replace(b'%s', target_formats[b'HEALTH'])
                source, expected = synthesize(source), synthesize(expected)
                if source == b'-':
                    expected = source
                if key == b'HEALTH':
                    source = b'|cffffffff' + source + b' 123|r'
                    expected = b'|cffffffff' + expected + b' 123|r'
                label_key = b'HEALTH' if key == b'HEALTH' else None
                actual = addon.TranslateCharacterStatText(addon, source, target.encode(), label_key)
                counts['stat probes'] += 1
                if actual != expected:
                    conflicts = [other.decode() for other in matching_keys.get(normalize_stat(source), [])
                                 if other != key and target_formats[other] and target_formats[other] != target_formats[key]]
                    if not conflicts:
                        failure('character stat', client, target, key.decode(), expected.decode(),
                                actual.decode() if actual else None, source.decode())
                        continue
                    report['statCandidates'].append({
                        'kind': 'character stat', 'client': client, 'target': target, 'field': key.decode(),
                        'source': source.decode(), 'expected': expected.decode(),
                        'actual': actual.decode() if actual else None,
                        'conflictingKeys': conflicts,
                        'reason': ('same source format has conflicting target formats' if conflicts
                                   else 'synthetic probe differs; check live client formatting'),
                    })

            globals_.liveObjectives = lua.table_from([lua.table_from({
                b'type': b'item', b'text': b'Unknown matrix item: 3/7', b'numFulfilled': 3, b'numRequired': 7,
            })])
            addon.GetQuest = lua.eval(b'function() return { objectiveLines = {} } end')
            db.GetQuestSource = lua.eval(b'function() return nil end')
            unknown = addon.GetProgressLines(addon, 123)[1].translated
            counts['unknown item objectives'] += 1
            if unknown != b'Unknown matrix item: 3/7':
                failure('item', client, target, 'unknown objective', 'Unknown matrix item: 3/7', unknown.decode())

    # Area IDs and UI-map IDs are distinct namespaces, even when their values overlap.
    assert db.GetAreaName(db, 1, b'enUS') and db.GetMapName(db, 1411, b'enUS')
    counts['location namespace lookups'] += 2
    report['boundaries'].append({'kind': 'missing quest UI', 'reason': 'unknown client locales use enUS'})
    report['boundaries'].append({'kind': 'character stat',
        'reason': 'synthetic format probes do not establish that a row appears in the live client'})
    report['boundaries'].append({'kind': 'quest rewards',
        'reason': 'production name renderer is exercised directly; frame layout is covered by test-addon.lua'})
    report['boundaries'].append({'kind': 'location and item objective',
        'reason': 'one area and item ID exercise wiring; name-catalog matrices cover catalog fields'})
    globals_.sourceLocale = b'unknown'
    assert addon.GetMissingQuestText(addon).title == b'Sorry we missed it'
    report['counts'] = dict(counts)
    output = ROOT / 'datasources/imports/translation-matrix/surfaces.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('Surface matrix:', dict(counts), 'gaps:', {key: len(value) for key, value in report.items()
                                                     if isinstance(value, list)})
    if report['failures']:
        raise AssertionError(f'{len(report["failures"])} surface failures; see {output}')
    return report


def main():
    run_matrix()


if __name__ == '__main__':
    main()
