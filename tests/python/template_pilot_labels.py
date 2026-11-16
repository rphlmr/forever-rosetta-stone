"""One owned GlobalString through the whole-tooltip production renderer."""

import re

from id_only_matrix_harness import IdOnlyHarness, to_python
from template_pilot_common import PilotCases, load_records, original_text

LABEL_ID = 11886
LABEL_KEY = 'ITEM_MIN_LEVEL'
SEPARATOR_ID = 22544
SEPARATOR_KEY = 'LARGE_NUMBER_SEPERATOR'
# Independent expectations for the numeric formatter's additional-language defaults.
DEFAULT_GROUPING = {'csCZ': ' ', 'daDK': '.', 'hrHR': '.', 'itIT': '.',
                    'plPL': ' ', 'svSE': ' ', 'trTR': '.', 'ukUA': ' '}


def render_integer(template, amount):
    if len(re.findall(r'%(?:1\$)?d', template)) != 1:
        raise ValueError('Pilot requires exactly one integer argument')
    return re.sub(r'%(?:1\$)?d', str(amount), template)


def run_matrix(sources, targets, profiles):
    record = load_records('globalstrings', [LABEL_ID]).get(str(LABEL_ID), {})
    cases = PilotCases('globalstrings')
    harness = IdOnlyHarness()
    render = harness.lua.eval(b'''function(addon, native)
        local rows = {}
        local font = {GetFont=function() return 'font',12,'' end,
            GetTextScale=function() return 1 end, GetTextColor=function() return 1,1,1 end,
            SetFont=function() end, SetTextScale=function() end}
        local tip = {AddLine=function(_,text) rows[#rows+1]=text end,
            AddDoubleLine=function(_,text) rows[#rows+1]=text end,
            NumLines=function() return #rows end,GetLeftLine=function() return font end}
        addon:FillEnglishTooltip({kind='item',id=0,name='Pilot',tip=tip,
            source={GetLeftLine=function() return font end},data={lines={
                {type=22,lineIndex=1,leftText='Pilot'}, {type=0,lineIndex=2,leftText=native}}}})
        return rows[2], #rows~=2
    end''')
    for source in sources:
        for target in targets:
            for profile in profiles:
                identity = {'sourceLocale': source, 'targetLocale': target, 'profile': profile,
                            'id': LABEL_ID, 'field': 'name', 'key': LABEL_KEY}
                if cases.apply_policy(identity, record, 'name', 'globalstrings', source_required=True):
                    continue
                native = expected = actual = None
                reason = category = error = None
                try:
                    source_template = original_text(record, source)
                    target_template = record.get('locales', {}).get(target, {}).get('name')
                    if not target_template:
                        raise ValueError('Missing target GlobalString')
                    amount = 17 if profile == 'baseline' else 53
                    native = render_integer(source_template, amount)
                    expected = render_integer(target_template, amount)
                    harness.set_context(target, 0, profile, 'items')
                    harness.set_source_locale(source)
                    harness.lua.globals()[LABEL_KEY.encode()] = source_template.encode()
                    result, error, forbidden = harness.attempt(lambda: render(harness.addon, native.encode()))
                    if forbidden:
                        error = error or str(forbidden)
                    if result is not None:
                        actual, incomplete = result
                        actual = to_python(actual)
                        if incomplete:
                            reason, category = 'production reported incomplete translation', 'addon_bug'
                except ValueError as cause:
                    reason = str(cause)
                    category = 'missing_data' if reason.startswith('Missing') else 'test_limitation'
                cases.check(identity, expected, actual, source_text=native, error=error,
                            reason=reason, category=category)
    separator = load_records('globalstrings', [SEPARATOR_ID]).get(str(SEPARATOR_ID), {})
    for source in sources:
        for target in targets:
            for profile in profiles:
                identity = {'sourceLocale': source, 'targetLocale': target, 'profile': profile,
                            'id': SEPARATOR_ID, 'field': 'name', 'key': SEPARATOR_KEY}
                native = separator.get('locales', {}).get(source, {}).get('name')
                expected = separator.get('locales', {}).get(target, {}).get('name')
                harness.set_context(target, 0, profile, 'items')
                harness.set_source_locale(source)
                result, error, forbidden = harness.attempt(lambda: harness.db.GetGlobalStringByKey(
                    harness.db, SEPARATOR_KEY.encode(), target.encode()))
                actual = to_python(result[0] if isinstance(result, tuple) else result)
                if forbidden:
                    error = error or str(forbidden)
                amount = str(1703 if profile == 'baseline' else 5307)
                if native is None:
                    cases.check(identity, None, actual, reason='missing source separator')
                    continue
                displayed = amount[:1] + native + amount[1:]
                grouping = '\u202f' if target == 'frFR' else expected if expected is not None else DEFAULT_GROUPING.get(target)
                expected_number = amount if not native else amount[:1] + grouping + amount[1:] if grouping is not None else None
                formatted, number_error, forbidden = harness.attempt(lambda: harness.addon.TranslateLiveTooltipValue(
                    harness.addon, displayed.encode(), target.encode(), False))
                if forbidden:
                    number_error = number_error or str(forbidden)
                # A missing optional target label is valid only together with the correct locale-default number.
                expectation = {'catalogSeparator': expected, 'formattedNumber': expected_number}
                output = {'catalogSeparator': actual, 'formattedNumber': to_python(formatted)}
                cases.check(identity, expectation, output, source_text=displayed, error=error or number_error,
                            reason='missing numeric expectation' if expected_number is None else None)
    report = cases.finish({'ids': [LABEL_ID, SEPARATOR_ID], 'keys': [LABEL_KEY, SEPARATOR_KEY]})
    report['expectedCases'] = len(sources) * len(targets) * len(profiles) * 2
    return report
