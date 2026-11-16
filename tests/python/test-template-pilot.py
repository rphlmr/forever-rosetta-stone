"""Run one catalog-backed entry per template surface across every locale pair.

This is a bounded diagnostic pilot, separate from the exhaustive translation suite.
Exit 1 means rendering failures, missing data, or an enumeration/stage error remain.
"""

import argparse
import importlib
import itertools
import json
import sys
import time
from collections import Counter
from pathlib import Path

from template_pilot_common import ROOT, OFFICIAL_LOCALES, PilotCases, load_records, pilot_locales

SURFACES = ('spells', 'auras', 'talents', 'items', 'quests', 'globalstrings', 'npc_tooltips')
OUTPUT = ROOT / 'datasources/imports/translation-matrix/pilot'
PROFILES = ('baseline', 'modified')
MODULES = {'items': 'template_pilot_items', 'quests': 'template_pilot_quests',
           'globalstrings': 'template_pilot_labels', 'npc_tooltips': 'template_pilot_npcs'}


def expected_fields(surface):
    """Enumerate the selected catalog scope independently of emitted case reports."""
    if surface in ('spells', 'auras', 'talents'):
        from template_pilot_spells import SPELL_ID, AURA_ID, TALENT_ID
        if surface == 'spells':
            return [(SPELL_ID, 'description', None)]
        if surface == 'auras':
            return [(AURA_ID, 'auraDescription', None)]
        talent = load_records('talents', [TALENT_ID]).get(str(TALENT_ID), {})
        from template_pilot_spells import TALENT_FIXTURE
        evidence = json.loads(TALENT_FIXTURE.read_text())
        definitions = {row['ID']: row['SpellID'] for row in evidence['traitDefinitions']
                       if row['SpellID'] == talent.get('spellId')}
        scope = [(definitions[row['TraitDefinitionID']], 'description', rank)
                 for row in evidence['traitNodeEntries'] if row['TraitDefinitionID'] in definitions
                 for rank in range(1, row['MaxRanks'] + 1)]
        if not scope:
            raise ValueError('Pilot talent has no verified trait ranks')
        return scope
    if surface == 'items':
        from template_pilot_items import ITEM_ID
        return [(ITEM_ID, 'name', None), (ITEM_ID, 'effect', None)]
    if surface == 'globalstrings':
        from template_pilot_labels import LABEL_ID, SEPARATOR_ID
        return [(LABEL_ID, 'name', None), (SEPARATOR_ID, 'name', None)]
    if surface == 'npc_tooltips':
        from template_pilot_npcs import NPC_ID
        return [(NPC_ID, field, None) for field in ('name', 'level', 'creatureType', 'faction')]
    from template_pilot_quests import QUEST_ID
    quest = load_records('quests', [QUEST_ID])[str(QUEST_ID)]
    records = quest.get('locales', {}).values()
    fields = {field for field in ('title', 'summary', 'description', 'eventObjectiveLabel')
              if any(record.get(field) for record in records)}
    fields.update('objectiveLines.' + str(line['index'])
                  for record in records for line in record.get('objectiveLines', []))
    return [(int(QUEST_ID), field, None) for field in sorted(fields)]


def validate_report(report, sources, targets, profiles):
    fields = expected_fields(report['surface'])
    planned = {(source, target, profile, entity_id, field, rank)
               for source, target, profile, (entity_id, field, rank) in
               itertools.product(sources, targets, profiles, fields)}
    keys = ('sourceLocale', 'targetLocale', 'profile', 'id', 'field', 'rank')
    emitted = Counter(tuple(case.get(key) for key in keys) for case in report['cases'])
    errors = []
    missing, extra = planned - emitted.keys(), emitted.keys() - planned
    duplicates = [identity for identity, count in emitted.items() if count != 1]
    if missing or extra or duplicates:
        errors.append({'reason': 'case enumeration mismatch', 'missing': sorted(missing),
                       'extra': sorted(extra), 'duplicates': sorted(duplicates)})
    if report.get('expectedCases') != len(planned):
        errors.append({'reason': 'declared case count differs from independent scope'})
    counts = Counter(cases=len(report['cases']), passed=0, failed=0)
    for case in report['cases']:
        counts[case['status']] += 1
        if case['status'] == 'passed':
            if (case.get('expected') is None or case.get('expected') == '' and not case.get('allowsEmptyValue')
                    or case['expected'] != case.get('actual') or case.get('reason')):
                errors.append({'reason': 'invalid passing case', 'identity': [case.get(key) for key in keys]})
        elif case['status'] in ('warning', 'not_applicable', 'allowed_absence'):
            reasons = {'warning': {'official_source_empty', 'official_source_absent', 'official_target_empty', 'official_target_absent'},
                       'not_applicable': {'all_official_sources_explicitly_empty'},
                       'allowed_absence': {'blocked_by_translation_policy'}}
            if (case.get('reason') not in reasons[case['status']] or not case.get('policyEvidence')
                    or case.get('actual') is not None or case.get('expected') is not None):
                errors.append({'reason': 'invalid policy classification'})
            evidence = case.get('policyEvidence', {})
            values = evidence.get('officialValues', {})
            if case['status'] == 'warning':
                locale = case.get('sourceLocale') if case.get('reason', '').startswith('official_source_') else case.get('targetLocale')
                value = values.get(locale)
                if (locale not in OFFICIAL_LOCALES or not evidence.get('english')
                        or isinstance(value, str) and value.strip()):
                    errors.append({'reason': 'warning contradicts official catalog values'})
            elif case['status'] == 'not_applicable':
                if not all(isinstance(values.get(loc), str) and not values[loc].strip() for loc in OFFICIAL_LOCALES):
                    errors.append({'reason': 'non-applicable case lacks explicit empty official values'})
            elif case.get('targetLocale') in OFFICIAL_LOCALES or evidence.get('targetValue') or not evidence.get('database'):
                errors.append({'reason': 'allowed absence lacks an absent additional target and verified policy database'})
        elif case['status'] != 'failed' or not case.get('reason') or not case.get('category'):
            errors.append({'reason': 'invalid failure classification'})
    if dict(counts) != report['counts']:
        errors.append({'reason': 'case counts do not reconcile'})
    return errors


def write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def summary_markdown(suite):
    lines = ['# Template translation pilot', '',
             'One selected entry per surface; all configured source/target pairs and profiles.',
             'No in-game captures. This report does not establish full-catalog coverage.', '',
             '| Surface | Cases | Passed | Warnings | Not applicable | Allowed absence | Failed | Enumeration/stage errors |',
             '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
    for report in suite['surfaces']:
        counts = report.get('counts', {})
        lines.append(f'| {report["surface"]} | {counts.get("cases", 0)} | {counts.get("passed", 0)} '
                     f'| {counts.get("warning", 0)} | {counts.get("not_applicable", 0)} | {counts.get("allowed_absence", 0)} '
                     f'| {counts.get("failed", 0)} | {len(report.get("enumerationErrors", [])) + bool(report.get("stageError"))} |')
    for report in suite['surfaces']:
        lines += ['', '## ' + report['surface'], '',
                  'Selection: `' + json.dumps(report.get('selection', {}), ensure_ascii=False) + '`', '']
        if report.get('stageError'):
            lines += [report['stageError'], '']
        for (category, reason), count in Counter(
                (row.get('category'), row.get('reason')) for row in report.get('cases', [])
                if row['status'] != 'passed').most_common():
            lines.append(f'- {category}: {reason} ({count} cases)')
        if report.get('counts', {}).get('cases') == report.get('counts', {}).get('passed') and not report.get('stageError'):
            lines.append('All selected cases passed.')
        lines += ['', f'Full cases: [{report["surface"]}.json]({report["surface"]}.json)']
    return '\n'.join(lines) + '\n'


def main(argv=None):
    sources, targets = pilot_locales()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--surface', choices=SURFACES, action='append')
    parser.add_argument('--source', choices=sources, action='append')
    parser.add_argument('--target', choices=targets, action='append')
    parser.add_argument('--profile', choices=PROFILES, action='append')
    parser.add_argument('--database', type=Path, help='Verified source corpus for deterministic missing-target classification')
    args = parser.parse_args(argv)
    PilotCases.configure_policy_database(args.database)
    chosen = list(dict.fromkeys(args.surface or SURFACES))
    sources, targets = list(dict.fromkeys(args.source or sources)), list(dict.fromkeys(args.target or targets))
    profiles = list(dict.fromkeys(args.profile or PROFILES))
    reports, spell_reports, spell_error = [], None, None
    for surface in chosen:
        print('Running pilot: ' + surface, flush=True)
        started = time.monotonic()
        try:
            if surface in ('spells', 'auras', 'talents'):
                if spell_error:
                    raise RuntimeError(spell_error)
                if spell_reports is None:
                    from template_pilot_spells import run_matrices
                    try:
                        spell_reports = {row['surface']: row for row in run_matrices(sources, targets, profiles)}
                    except Exception as cause:
                        spell_error = str(cause)
                        raise
                report = spell_reports[surface]
            else:
                report = importlib.import_module(MODULES[surface]).run_matrix(sources, targets, profiles)
            report['enumerationErrors'] = validate_report(report, sources, targets, profiles)
            report['passed'] = not report['enumerationErrors'] and report['counts']['failed'] == 0
        except Exception as cause:
            report = {'surface': surface, 'stageError': f'{type(cause).__name__}: {cause}', 'passed': False}
        report['seconds'] = round(time.monotonic() - started, 3)
        reports.append(report)
        write_report(OUTPUT / (surface + '.json'), report)
        print(surface + ': ' + json.dumps(report.get('counts', {'stageError': report.get('stageError')})), flush=True)
    suite = {'pilot': True, 'fullCatalogCoverage': False, 'sources': sources, 'targets': targets,
             'policyDatabase': str(PilotCases.policy_evidence.database) if PilotCases.policy_evidence else None,
             'profiles': profiles, 'surfaces': reports, 'passed': all(report['passed'] for report in reports)}
    write_report(OUTPUT / 'suite.json', suite)
    (OUTPUT / 'summary.md').write_text(summary_markdown(suite), encoding='utf-8')
    print('Report: ' + str(OUTPUT / 'summary.md'), flush=True)
    return 0 if suite['passed'] else 1


if __name__ == '__main__':
    sys.exit(main())
