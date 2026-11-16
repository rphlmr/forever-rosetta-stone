"""Scoped cross-client pilot for a real item and its displayed spell effect."""

from id_only_matrix_harness import IdOnlyHarness, ROOT
from id_only_item_matrix import get_format, load_referenced_spells, render_line
from live_spell_fixture import FixtureUnavailable, make_fixture, maintained_text
from template_pilot_common import PilotCases, load_records

ITEM_ID = 118
SPELL_ID = 439


def _format_cooldown(harness, locale, value):
    template = get_format(harness, locale, 'ITEM_COOLDOWN_TOTAL_MIN')
    if not template:
        raise FixtureUnavailable('missing cooldown format', 'missing_data', 'missing_cooldown_format')
    try:
        return template % value
    except (TypeError, ValueError) as error:
        raise FixtureUnavailable('unsupported cooldown format') from error


def _result(harness, operation):
    result, error, forbidden = harness.attempt(operation)
    if forbidden:
        error = error or 'forbidden calls: ' + ', '.join(forbidden)
    if isinstance(result, tuple):
        values = result
        result = values[0] if values else None
        if len(values) > 2 and values[2]:
            error = error or 'production returned incomplete translation'
        elif len(values) == 2 and result is None and values[1]:
            error = error or str(harness.from_lua(values[1]))
    return harness.from_lua(result), error


def run_matrix(sources, targets, profiles):
    sources, targets, profiles = list(sources), list(targets), list(profiles)
    items = load_records('items', [ITEM_ID])
    item = items.get(str(ITEM_ID))
    # Resolve only this linked spell and any references its selected templates require.
    spells = load_referenced_spells(ROOT, {str(SPELL_ID)},
                                    set(sources) | set(targets))
    harness = IdOnlyHarness()
    cases = PilotCases('items')
    for source in sources:
        for target in targets:
            for profile in profiles:
                harness.set_context(target, ITEM_ID, profile, entity_kind='items')
                harness.set_source_locale(source)
                base = {'sourceLocale': source, 'targetLocale': target, 'profile': profile, 'id': ITEM_ID}
                source_name = maintained_text(item or {}, source, 'name')
                target_name = (item or {}).get('locales', {}).get(target, {}).get('name')
                if not cases.apply_policy({**base, 'field': 'name'}, item or {}, 'name', 'items'):
                    reason = None if target_name else 'missing target item name'
                    actual, error = _result(harness, lambda: harness.db.GetItemName(
                        harness.db, ITEM_ID, target.encode()))
                    cases.check({**base, 'field': 'name'}, target_name, actual, source_text=source_name,
                                error=error, reason=reason, category='missing_data' if reason else None)

                identity = {**base, 'field': 'effect', 'spellID': SPELL_ID, 'triggerType': 0}
                if cases.apply_policy(identity, spells.get(str(SPELL_ID), {}), 'description', 'spells',
                                      entity_id=SPELL_ID, source_required=True):
                    continue
                native = expected = None
                reason = category = None
                try:
                    links = (item or {}).get('tooltipData', {}).get('effects', [])
                    if not any(link.get('spellID') == SPELL_ID and link.get('triggerType') == 0 for link in links):
                        raise FixtureUnavailable('missing linked item effect', 'missing_data', 'missing_item_effect')
                    fixture = make_fixture(spells, SPELL_ID, target, profile, source=source)
                    source_prefix = get_format(harness, source, 'ITEM_SPELL_TRIGGER_ONUSE')
                    target_prefix = get_format(harness, target, 'ITEM_SPELL_TRIGGER_ONUSE')
                    if not source_prefix or not target_prefix:
                        raise FixtureUnavailable('missing trigger format', 'missing_data', 'missing_trigger_format')
                    minutes = 2 if profile == 'baseline' else 1
                    native = source_prefix + ' ' + fixture['native'] + ' ' + _format_cooldown(harness, source, minutes)
                    expected = target_prefix + ' ' + fixture['expected'] + ' ' + _format_cooldown(harness, target, minutes)
                except FixtureUnavailable as cause:
                    reason, category = str(cause), cause.category
                actual = error = None
                if native is not None:
                    actual, error = _result(harness, lambda: render_line(
                        harness, ITEM_ID, target, {'leftText': native, 'spellID': SPELL_ID, 'type': 44}))
                cases.check(identity, expected, actual, source_text=native, error=error,
                            reason=reason, category=category)
    selection = {'sources': sources, 'targets': targets, 'profiles': profiles, 'ids': [ITEM_ID]}
    report = cases.finish(selection)
    report['expectedCases'] = len(sources) * len(targets) * len(profiles) * 2
    return report
