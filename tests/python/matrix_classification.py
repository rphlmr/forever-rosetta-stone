"""Explain failed coverage cases without promoting unverified output to a pass."""

from collections import Counter


CATEGORIES = ('addon_bug', 'missing_data', 'test_limitation', 'unclassified')
LABELS = {'addon_bug': 'Confirmed addon failures', 'missing_data': 'Missing or invalid owned data',
          'test_limitation': 'Test context or independent-checker limitations',
          'unclassified': 'Needs investigation'}

# Exact diagnostics only: new/unknown reasons must remain visible for investigation.
REASONS = {
    'missing target translation': ('missing_data', 'missing_target_field'),
    'missingTranslation': ('missing_data', 'missing_target_field'),
    'missing linked spell translation': ('missing_data', 'missing_linked_target_field'),
    'missing linked spell source description': ('missing_data', 'missing_linked_source_field'),
    'missing referenced spell': ('missing_data', 'missing_referenced_record'),
    'missing verified client objective index': ('missing_data', 'missing_objective_index'),
    'missing verified live objective type': ('missing_data', 'missing_objective_type'),
    'invalid linked spell identity': ('missing_data', 'invalid_linked_identity'),
    'unknown or malformed set bonus threshold': ('missing_data', 'invalid_set_threshold'),
    'missing target tooltip format': ('missing_data', 'missing_target_format'),
    'unknown or malformed set bonus format': ('missing_data', 'invalid_target_format'),
    'unverified structured row identity': ('test_limitation', 'unverified_row_identity'),
    'unsupported item trigger type': ('test_limitation', 'unverified_trigger_surface'),
    'offered objective amounts unavailable in test context': ('test_limitation', 'missing_offered_context'),
    'reputation standing unavailable from structured test context': ('test_limitation', 'missing_standing_context'),
    'unsupported context-dependent slash selector': ('test_limitation', 'unsupported_selector_expectation'),
    'unrecognized dollar template token': ('test_limitation', 'unknown_template_expectation'),
    'unrecognized symbolic brace token': ('test_limitation', 'unknown_template_expectation'),
    'unknown player labels for locale': ('test_limitation', 'missing_player_label_fixture'),
    'no ID-based renderer for this field': ('test_limitation', 'unverified_row_identity'),
}
BUG_REASONS = {'mismatch', 'runtimeError', 'forbiddenDependency', 'untranslated', 'nativeFallback'}


def classify_failure(kind, row):
    reason = row.get('reason', '')
    if reason in ('runtimeError', 'forbiddenDependency', 'mismatch') or row.get('errorPreview'):
        return {'category': 'addon_bug', 'code': reason if reason in BUG_REASONS else 'runtimeError'}
    if reason in ('untranslated', 'nativeFallback') and row.get('inputLimitation'):
        category, code = REASONS.get(row['inputLimitation'], ('unclassified', 'unknown_input_limitation'))
        return {'category': category, 'code': code}
    diagnostic = row.get('expectationDiagnostic')
    if diagnostic:
        if diagnostic.get('category') not in ('missing_data', 'test_limitation', 'unclassified'):
            return {'category': 'unclassified', 'code': 'invalid_expectation_diagnostic'}
        return {'category': diagnostic['category'], 'code': diagnostic.get('code') or 'unknown_expectation'}
    if reason in BUG_REASONS:
        return {'category': 'addon_bug', 'code': reason}
    if reason in REASONS:
        category, code = REASONS[reason]
        return {'category': category, 'code': code}
    if reason.startswith('objective amount has no verified client index: '):
        return {'category': 'missing_data', 'code': 'missing_objective_index'}
    return {'category': 'unclassified', 'code': 'unknown_failure_reason'}


def target_identity(kind, row):
    """Keep locales, surfaces and linked slots; collapse only controlled profiles."""
    return (row.get('entityKind', kind), str(row.get('id')), row.get('field'), row.get('locale'), row.get('index'),
            row.get('surface'), row.get('effectSpellId'))


def summarize_failures(kind, failures):
    counts = Counter()
    targets = {category: set() for category in CATEGORIES}
    groups = {}
    for row in failures:
        diagnostic = classify_failure(kind, row)
        category, code = diagnostic['category'], diagnostic['code']
        if (row.get('category', category) != category or row.get('diagnosticCode', code) != code):
            raise ValueError('Failure annotation does not match its evidence')
        counts[category] += 1
        identity = target_identity(kind, row)
        targets[category].add(identity)
        key = (category, code, row.get('reason', ''))
        group = groups.setdefault(key, {'category': category, 'code': code, 'reason': key[2],
                                        'cases': 0, 'targets': set(), 'examples': []})
        group['cases'] += 1
        group['targets'].add(identity)
        if len(group['examples']) < 3:
            group['examples'].append({key: value for key, value in row.items()
                                      if key not in ('category', 'diagnosticCode')})
    for group in groups.values():
        group['affectedTargets'] = len(group.pop('targets'))
    return {'unverifiedCases': len(failures),
            'buckets': {category: {'label': LABELS[category], 'cases': counts[category],
                                   'affectedTargets': len(targets[category])} for category in CATEGORIES},
            'groups': sorted(groups.values(), key=lambda group: (-group['cases'], group['category'], group['code'])),
            'counting': 'Cases include each locale/profile/surface. Affected targets collapse profiles only; '
                        'these counts are not distinct bugs. Unavailable expectations never count as verified.'}


def summarize_report(report):
    counts = report['counts']
    failures = report['failures']
    if (counts.get('failed', 0) != len(failures)
            or counts.get('cases', 0) != counts.get('passed', 0) + len(failures)):
        raise ValueError('Coverage counts do not reconcile with individual failed cases')
    result = summarize_failures(report['kind'], failures)
    result.update({'verifiedCases': counts.get('passed', 0), 'totalCases': counts.get('cases', 0),
                   'coverageComplete': not failures, 'kind': report['kind']})
    return result


def combine_summaries(summaries):
    """Sum disjoint kinds or shards; callers must validate their entity coverage first."""
    buckets = {category: {'label': LABELS[category], 'cases': 0, 'affectedTargets': 0}
               for category in CATEGORIES}
    for summary in summaries:
        for category in CATEGORIES:
            for key in ('cases', 'affectedTargets'):
                buckets[category][key] += summary['buckets'][category][key]
    return {'totalCases': sum(row['totalCases'] for row in summaries),
            'verifiedCases': sum(row['verifiedCases'] for row in summaries),
            'unverifiedCases': sum(row['unverifiedCases'] for row in summaries),
            'coverageComplete': all(row['coverageComplete'] for row in summaries), 'buckets': buckets}


def write_summary_markdown(path, classification):
    """Keep the human summary on the same reconciled data as the JSON report."""
    catalog = classification.get('catalogCoverage')
    overall = classification.get('overall')
    lines = ['# Translation matrix classification', '',
             '**Strict completeness remains required.** Missing data and checker limitations '
             'are failed, unverified cases; they are never counted as passes.', '']
    if catalog and overall:
        lines += [f'Catalog rendering cases verified against independent variable expectations: '
                  f'**{catalog["verifiedCases"]:,} / {catalog["totalCases"]:,}**.', '',
                  '| Category | Failed cases | Affected targets |', '| --- | ---: | ---: |']
        for category in CATEGORIES:
            bucket = overall['buckets'][category]
            lines.append(f'| {bucket["label"]} | {bucket["cases"]:,} | {bucket["affectedTargets"]:,} |')
        lines += ['', 'Case counts include locale, profile and surface combinations. Affected targets '
                  'collapse profiles only. These are not distinct bugs. The duplicate spell-shard stage '
                  'is not counted again; UI fallback checks are separate from catalog rendering cases.', '',
                  'Translation presence and variable/output rendering are checked. The expected wording comes '
                  'from the owned catalog; this does not independently certify linguistic meaning.', '']
    lines += ['Linked-spell source checks cover candidate technical surfaces. An execution link alone '
              'does not establish that a description is visible, so a missing linked description '
              'does not necessarily indicate missing player-facing wording. Unverified surfaces '
              'remain failed until their native row identity and expectations are established.', '']
    gate = classification.get('catalogTranslationCompleteness')
    if gate:
        lines += ['## All-catalog translation presence', '',
                  f'- English-source-backed missing target fields: **{gate["missingTargetPointers"]:,}**.',
                  f'- Missing English-source fields blocking completeness: **{gate["missingEnglishSourceFields"]:,}**.',
                  f'- Fields with no text in any locale: **{gate["noTextInAnyLocaleFields"]:,}**.',
                  f'- Unverified alternate-source fields: **{gate["unverifiedOtherSourceFields"]:,}** '
                  f'({gate["unverifiedOtherSourceTargetPointers"]:,} potential target pointers).', '',
                  'Alternate text is not automatically usable evidence. This gate includes nonshipping '
                  'quests and all configured entity kinds/locales; its field counts are not added to '
                  'the rendering-case totals.', '']
    placeholders = classification.get('catalogPlaceholderContracts')
    if placeholders:
        counts = placeholders['counts']
        lines += ['## All-catalog placeholder contracts', '',
                  f'- Verified comparisons: **{counts["passed"]:,}/{counts["cases"]:,}**.',
                  f'- Mismatched or unverified comparisons: **{counts["failed"]:,}**.', '',
                  'These compare protected placeholders against original official-language fields, '
                  'including exact referenced IDs, formulas and occurrence counts. Official disagreements '
                  'are informational and retain their original tokens. Counts are separate from translation presence and rendering.', '',
                  f'Detailed report: `{placeholders["path"]}`.', '']
    records = [(row['kind'], row['diagnostics']) for row in classification.get('caseReports', [])]
    if placeholders:
        records.append(('placeholders', placeholders['diagnostics']))
    records += [(row['kind'], row) for row in classification.get('additionalChecks', [])]
    def cell(value):
        return str(value).replace('|', '\\|').replace('\n', ' ').replace('\r', '')
    for category in CATEGORIES:
        lines += ['## ' + LABELS[category], '']
        groups = [(kind, group) for kind, summary in records for group in summary['groups']
                  if group['category'] == category]
        if not groups:
            lines += ['No cases recorded in this category.', '']
            continue
        lines += ['| Kind | Diagnostic | Cases | Example |', '| --- | --- | ---: | --- |']
        for kind, group in sorted(groups, key=lambda row: -row[1]['cases']):
            example = group['examples'][0]
            identity = '/'.join(str(example.get(key, '')) for key in ('id', 'field', 'locale', 'surface'))
            detail = ('unverified native row identity' if group['code'] == 'unverified_row_identity'
                      else group['reason'])
            if category == 'addon_bug':
                detail += f' — expected {example.get("expectedPreview")!r}; actual {example.get("actualPreview")!r}'
            lines.append(f'| {cell(kind)} | {cell(detail)} | {group["cases"]:,} | {cell(identity)} |')
        lines.append('')
    lines += ['## Report integrity', '',
              'Stage execution, stale-report and enumeration failures are reported separately. '
              'Unknown reasons remain failures requiring investigation.', '',
              f'Stage errors: {", ".join(classification.get("stageErrors", [])) or "none"}.', '',
              'Complete per-case evidence and category groups: `classification.json`, '
              '`suite.json`, and the linked per-kind report paths in the JSON.']
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
