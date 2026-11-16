"""Measure ID-selected item text and effects with controlled displayed values."""

import re
import sys

from id_only_matrix_harness import ROOT, CaseReporter, IdOnlyHarness, NATIVE_TEXT, PROFILES, required_locales
from live_spell_fixture import FixtureUnavailable, make_fixture

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import project_tooltip_details


FIELDS = ('name', 'description', 'nameDescription', 'setName')
TRIGGER_KEYS = {0: 'ITEM_SPELL_TRIGGER_ONUSE', 1: 'ITEM_SPELL_TRIGGER_ONEQUIP', 2: 'ITEM_SPELL_TRIGGER_ONPROC'}
TRIGGER_LINE_TYPES = {0: 44, 1: 45, 2: 46}


def verified_description_row(tooltip):
    binding = tooltip.get('descriptionRow')
    if not isinstance(binding, dict) or binding.get('lineType') != 'ItemSpellTriggerLearn':
        return None
    spell_id = binding.get('spellID')
    if type(spell_id) is not int or spell_id <= 0 or binding.get('triggerType') != 6:
        return None
    links = [effect for effect in tooltip.get('effects', [])
             if effect.get('spellID') == spell_id and effect.get('triggerType') == 6]
    return binding if len(links) == 1 else None


def get_target(entity, locale, field):
    effective_locale = locale
    localized = entity.get('locales', {}).get(effective_locale, {})
    if field == 'name':
        return localized.get(field)
    details = project_tooltip_details(entity, localized, effective_locale)
    if field == 'setName':
        return details.get('set', {}).get('name')
    return details.get(field)


def is_applicable(entity, field):
    if field == 'name':
        return True
    tooltip = entity.get('tooltipData', {})
    if any(record.get(field) for record in entity.get('locales', {}).values()):
        return True
    if field == 'setName':
        item_set = tooltip.get('set', {})
        return bool(item_set.get('name'))
    return False


def get_format(harness, locale, key):
    addon = harness.addon
    if locale == 'enUS':
        formats = addon.englishTooltipFormats
    else:
        all_formats = addon.tooltipFormatsByLocale
        formats = all_formats and all_formats[locale.encode()]
    value = formats and formats[key.encode()]
    return harness.from_lua(value) if value else None


def render_line(harness, item_id, locale, line):
    lua_line = harness.to_lua(line)
    if locale == 'enUS':
        result = harness.addon.GetEnglishTooltipLine(harness.addon, harness.to_lua({}), lua_line, b'item', item_id)
    else:
        result = harness.addon.GetLocalizedTooltipLine(harness.addon, lua_line, b'item', item_id, locale.encode())
    return result


def get_spell_expectation(spells, spell_id, locale, profile, diagnostics=None):
    spell = spells.get(str(spell_id))
    if not spell:
        return None, 'missing referenced spell'
    effective_locale = locale
    localized = spell.get('locales', {}).get(effective_locale, {})
    template = project_tooltip_details(spell, localized, effective_locale).get('description')
    if not template:
        return None, ('missing linked spell translation' if spell.get('locales', {}).get('enUS', {}).get('description')
                      else 'missing linked spell source description')
    try:
        fixture = make_fixture(spells, spell_id, locale, 'modified' if profile.get('known') else 'baseline')
        return fixture['expected'], None
    except FixtureUnavailable as error:
        if diagnostics is not None:
            diagnostics.update(category=error.category, code=error.code, evidence=error.evidence)
        return None, str(error)


def load_referenced_spells(root, spell_ids, locales):
    spells = {}
    pending = {spell_id for spell_id in spell_ids if spell_id.isdecimal() and int(spell_id) > 0}
    visited = set()
    effective_locales = set(locales) | {'enUS'}
    while pending:
        visited.update(pending)
        batch = load_catalog(root, 'spells', {'spells': pending})['catalogs']['spells']
        spells.update(batch)
        references = set()
        for spell in batch.values():
            for locale in effective_locales:
                localized = spell.get('locales', {}).get(locale, {})
                details = project_tooltip_details(spell, localized, locale)
                templates = [details.get(field, '') for field in ('description', 'auraDescription')]
                templates.extend(spell.get('tooltipData', {}).get('variables', []))
                for template in templates:
                    references.update(re.findall(r'\$(\d+)[sSmMdDtTxXuhniraAoO]\d*', template))
                    references.update(re.findall(r'\$[*/]\d+\.?\d*;(\d+)[sSmM]\d*', template))
                    for angle, plain in re.findall(r'\$@spell(?:desc|name)(?:<(\d+)>|(\d+)(?![A-Za-z0-9_]))', template):
                        references.add(angle or plain)
        pending = {reference for reference in references if int(reference) > 0} - visited
    return spells


def run_matrix(locales=None, ids=None, profiles=None, root=ROOT):
    scope = None if ids is None else {'items': {str(value) for value in ids}}
    items = load_catalog(root, 'items', scope)['catalogs']['items']
    spell_ids = {str(link.get('spellID')) for item in items.values()
                 for link in (item.get('tooltipData', {}).get('effects', [])
                              + item.get('tooltipData', {}).get('set', {}).get('bonuses', []))
                 if link.get('spellID') is not None}
    locales = list(required_locales(root) if locales is None else locales)
    profiles = list(PROFILES if profiles is None else profiles)
    spells = (load_catalog(root, 'spells')['catalogs']['spells'] if ids is None
              else load_referenced_spells(root, spell_ids, locales))
    harness = IdOnlyHarness(root=root)
    reporter = CaseReporter('items', locales, profiles)

    for item_key, entity in items.items():
        item_id = int(item_key)
        tooltip = entity.get('tooltipData', {})
        description_row = verified_description_row(tooltip)
        links = [('effect', index, effect) for index, effect in enumerate(tooltip.get('effects', []))]
        links += [('setBonus', index, bonus) for index, bonus in enumerate(tooltip.get('set', {}).get('bonuses', []))]
        for locale in locales:
            for profile_name in profiles:
                harness.set_context(locale, item_id, profile_name, entity_kind='items')
                for field in FIELDS:
                    case = {'id': item_id, 'field': field, 'locale': locale, 'profile': profile_name}
                    if not is_applicable(entity, field):
                        reporter.not_applicable(case, 'field absent from maintained locales and source evidence')
                        continue
                    expected = get_target(entity, locale, field)
                    if field == 'name':
                        call = lambda: harness.db.GetItemName(harness.db, item_id, locale.encode())
                    else:
                        line = {'leftText': NATIVE_TEXT}
                        if field == 'description' and description_row:
                            line.update(type=38, spellID=description_row['spellID'])
                            prefix = get_format(harness, locale, 'ITEM_SPELL_TRIGGER_ONUSE')
                            expected = prefix + ' ' + expected if prefix and expected else None
                        elif field == 'description':
                            line['type'] = 37
                        else:
                            case['inputLimitation'] = 'unverified structured row identity'
                        call = lambda: render_line(harness, item_id, locale, line)
                    actual, error, forbidden = harness.attempt(call)
                    reporter.record(case, expected, actual, error, forbidden,
                                    None if expected else 'missing target translation')

                for kind, index, link in links:
                    spell_id = link.get('spellID')
                    case = {'id': item_id, 'field': kind, 'locale': locale, 'profile': profile_name,
                            'index': index, 'effectSpellId': spell_id, 'triggerType': link.get('triggerType')}
                    if kind == 'setBonus':
                        case['inputLimitation'] = 'unverified structured row identity'
                    if kind == 'effect' and description_row and link is not None and link.get('triggerType') == 6 \
                            and link.get('spellID') == description_row['spellID']:
                        prefix = get_format(harness, locale, 'ITEM_SPELL_TRIGGER_ONUSE')
                        body = get_target(entity, locale, 'description')
                        expected = prefix + ' ' + body if prefix and body else None
                        reason = None if expected else ('missing target tooltip format' if not prefix
                                                        else 'missing target translation')
                        actual, error, forbidden = harness.attempt(lambda: render_line(
                            harness, item_id, locale, {'leftText': NATIVE_TEXT, 'type': 38, 'spellID': spell_id}))
                        reporter.record(case, expected, actual, error, forbidden, reason)
                        continue
                    key = TRIGGER_KEYS.get(link.get('triggerType')) if kind == 'effect' else 'ITEM_SET_BONUS'
                    diagnostic = {}
                    fixture = None
                    description, reason = get_spell_expectation(spells, spell_id, locale, harness.profile, diagnostic)
                    if description and kind == 'effect' and link.get('triggerType') in TRIGGER_LINE_TYPES:
                        fixture = make_fixture(spells, spell_id, locale, profile_name)
                        harness.set_source_locale(fixture['sourceLocale'])
                        case.update(sourceLocale=fixture['sourceLocale'], fixture=fixture['fixture'])
                    if diagnostic:
                        case['expectationDiagnostic'] = diagnostic
                    target_format = get_format(harness, locale, key) if key else None
                    expected = None
                    if not isinstance(spell_id, int) or spell_id <= 0:
                        reason = 'invalid linked spell identity'
                        case.pop('expectationDiagnostic', None)
                    elif not key:
                        reason = 'unsupported item trigger type'
                        case.pop('expectationDiagnostic', None)
                    elif kind == 'setBonus' and (type(link.get('threshold')) is not int or link['threshold'] <= 0):
                        reason = 'unknown or malformed set bonus threshold'
                        case.pop('expectationDiagnostic', None)
                    elif not target_format:
                        reason = 'missing target tooltip format'
                        case.pop('expectationDiagnostic', None)
                    elif description:
                        try:
                            expected = (target_format + ' ' + description if kind == 'effect'
                                        else target_format % description)
                        except (TypeError, ValueError):
                            reason = 'unknown or malformed set bonus format'
                            case.pop('expectationDiagnostic', None)
                    if kind == 'effect' and link.get('triggerType') not in TRIGGER_LINE_TYPES:
                        # ItemEffect trigger values alone do not establish a client tooltip row.
                        # Keep the required case failing until its structured surface is verified.
                        reporter.record(case, expected, None, reason=reason)
                        continue
                    native = NATIVE_TEXT
                    if fixture and kind == 'effect' and key:
                        source_format = get_format(harness, fixture['sourceLocale'], key)
                        if source_format:
                            native = source_format + ' ' + fixture['native']
                    actual, error, forbidden = harness.attempt(lambda: render_line(
                        harness, item_id, locale, {'leftText': native, 'spellID': spell_id,
                                                   **({'type': TRIGGER_LINE_TYPES[link['triggerType']]}
                                                      if kind == 'effect' and link.get('triggerType') in TRIGGER_LINE_TYPES
                                                      else {})}))
                    reporter.record(case, expected, actual, error, forbidden, reason)

    return reporter.finish(items.keys(), full_scope=ids is None)
