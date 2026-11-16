"""Fail coverage for every untranslated maintained quest, spell, and item case."""

import argparse
import hashlib
import importlib
import json
import subprocess
import sys
import time
import uuid
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from id_only_matrix_harness import ROOT, PROFILES, required_locales
from matrix_classification import CATEGORIES, combine_summaries, summarize_report


KINDS = ('quests', 'spells', 'items')
MODULES = {'quests': 'id_only_quest_matrix', 'spells': 'id_only_spell_matrix', 'items': 'id_only_item_matrix'}
STAGE_TIMEOUT_SECONDS = 600


def expected_entities(kind, ids=None):
    from tools.catalogs.catalog_storage import load_catalog
    from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES

    scope = None if ids is None else {kind: {str(value) for value in ids}}
    records = load_catalog(ROOT, kind, scope)['catalogs'][kind]
    return sorted(int(entity_id) for entity_id, entity in records.items()
                  if kind != 'quests' or entity.get('usageStatus') not in EXCLUDED_QUEST_STATUSES)


def validate_report(report, kind, entity_ids, locales, profiles):
    """Reject incomplete enumeration even when a stage reports no rendering failures."""
    errors = []

    for key, expected in (('kind', kind), ('entityIds', entity_ids), ('locales', locales), ('profiles', profiles)):
        if report.get(key) != expected:
            errors.append('stage ' + key + ' does not match requested scope')

    counts = report.get('counts', {})

    if report.get('entityCount') != len(entity_ids):
        errors.append('entity count does not match enumerated IDs')

    if counts.get('cases') != counts.get('passed', 0) + counts.get('failed', 0):
        errors.append('case totals do not reconcile')

    if counts.get('failed') != len(report.get('failures', [])):
        errors.append('every failed case must have an individual failure record')

    if entity_ids and not counts.get('cases'):
        errors.append('nonempty entity scope produced no cases')

    mandatory = report.get('mandatoryCoverage')

    field = 'title' if kind == 'quests' else 'name'

    if (mandatory is None or mandatory.get('missingCases') or 'missingCases' not in mandatory
            or mandatory.get('field') != field
            or mandatory.get('requiredPerEntity') != len(locales) * len(profiles)):
        errors.append('mandatory name/title cases were omitted')

    if report.get('interfaceErrors'):
        errors.append('duplicate or invalid case identities')

    if report.get('diagnostics') != summarize_report(report):
        errors.append('failure classification does not match individual cases')

    return errors


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('w', encoding='utf-8') as handle:
        json.dump(value, handle, ensure_ascii=False, separators=(',', ':'))
        handle.write('\n')
    temporary.replace(path)


def file_digest(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def run_worker(args, kind, locales, profiles):
    started = time.monotonic()
    module = importlib.import_module(MODULES[kind])
    report = module.run_matrix(locales=locales, ids=args.ids, profiles=profiles)
    errors = validate_report(report, kind, expected_entities(kind, args.ids), locales, profiles)
    report['enumerationErrors'] = errors
    report['runId'] = args.run_id
    report['strictCoverage'] = True
    report['reverseIdentityMatchingDisabled'] = True
    report['liveValueCaptureEnabled'] = kind != 'quests'
    report['fullScope'] = args.ids is None and locales == required_locales() and profiles == list(PROFILES)
    report['seconds'] = round(time.monotonic() - started, 2)
    report['passed'] = not errors and report['counts']['failed'] == 0
    report['scopeNote'] = ('All maintained target fields and owned links in the requested deterministic contexts; '
                           'not every possible live-client state or undiscovered UI row.')
    write_json(args.output, report)
    summary = {key: report[key] for key in ('kind', 'runId', 'strictCoverage', 'reverseIdentityMatchingDisabled', 'liveValueCaptureEnabled',
                                           'seconds', 'passed', 'counts', 'entityCount', 'locales', 'profiles',
                                           'fullScope', 'enumerationErrors', 'diagnostics')}
    summary['report'] = str(args.output)
    summary['reportSha256'] = file_digest(args.output)
    write_json(args.output.with_suffix('.summary.json'), summary)
    print(kind + ': ' + json.dumps(summary['counts'], sort_keys=True), flush=True)
    return 0 if report['passed'] else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=KINDS, action='append', help='Restrict entity kinds; default all three.')
    parser.add_argument('--locale', action='append', help='Restrict target locales; default every supported locale.')
    parser.add_argument('--profile', choices=tuple(PROFILES), action='append', help='Restrict displayed-value / quest test profiles.')
    parser.add_argument('--ids', type=int, nargs='+', help='Scoped debug selection; requires exactly one --kind.')
    parser.add_argument('--output', type=Path, default=ROOT / 'datasources/imports/id-only-matrix/report.json')
    parser.add_argument('--worker', choices=KINDS, help=argparse.SUPPRESS)
    parser.add_argument('--run-id', default=None, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    kinds = list(dict.fromkeys(args.kind or KINDS))
    supported = required_locales()
    locales = list(dict.fromkeys(args.locale or supported))
    profiles = list(dict.fromkeys(args.profile or PROFILES))

    if Path.cwd() != ROOT:
        parser.error('run from the repository root')

    if any(locale not in supported for locale in locales):
        parser.error('--locale must name a supported target locale')

    if args.ids and (len(kinds) != 1 or any(value <= 0 for value in args.ids)):
        parser.error('--ids requires exactly one --kind and positive IDs')

    if args.ids:
        from tools.catalogs.catalog_storage import load_catalog
        records = load_catalog(ROOT, kinds[0], {kinds[0]: set(map(str, args.ids))})['catalogs'][kinds[0]]

        if set(map(str, args.ids)) - records.keys():
            parser.error('--ids includes entities absent from the maintained catalog')

    args.output = args.output.resolve()

    if args.worker:
        return run_worker(args, args.worker, locales, profiles)

    run_id = uuid.uuid4().hex
    results = []

    for kind in kinds:
        output = args.output.with_name(args.output.stem + '-' + kind + '.json')
        command = [sys.executable, str(Path(__file__).resolve()), '--worker', kind, '--kind', kind,
                   '--run-id', run_id, '--output', str(output)]

        for locale in locales:
            command += ['--locale', locale]

        for profile in profiles:
            command += ['--profile', profile]

        if args.ids:
            command += ['--ids', *map(str, args.ids)]

        print('Running strict ID-only ' + kind + ' matrix...', flush=True)
        try:
            process = subprocess.run(command, timeout=STAGE_TIMEOUT_SECONDS, check=False)
            summary = json.loads(output.with_suffix('.summary.json').read_text())
            fresh = summary.get('runId') == run_id and summary.get('reportSha256') == file_digest(output)

            if not fresh or process.returncode not in (0, 1) or (process.returncode == 0) != summary.get('passed'):
                raise ValueError('stage output is incomplete, stale, or inconsistent with its exit status')

            results.append(summary)
        except (OSError, ValueError, subprocess.TimeoutExpired) as cause:
            results.append({'kind': kind, 'passed': False, 'infrastructureError': str(cause)})

    counts = {key: sum(result.get('counts', {}).get(key, 0) for result in results)
              for key in ('cases', 'passed', 'failed')}
    report = {
        'runId': run_id,
        'strictCoverage': True,
        'reverseIdentityMatchingDisabled': True,
        'liveValueCaptureEnabled': any(kind != 'quests' for kind in kinds),
        'fullScope': kinds == list(KINDS) and locales == supported and profiles == list(PROFILES) and args.ids is None,
        'passed': len(results) == len(kinds) and all(result['passed'] for result in results),
        'counts': counts,
        'stages': results,
        'limitations': ['Synthetic displayed-value profiles and structured quest profiles do not prove all possible live states.',
                        'Unsupported independent expectations fail coverage rather than being skipped.',
                        'Optional fields absent across every maintained locale are reported as not applicable.',
                        'Only product-excluded quest statuses are omitted, with IDs and reasons recorded.'],
    }
    classified = [result['diagnostics'] for result in results if 'diagnostics' in result]
    report['diagnostics'] = combine_summaries(classified)
    report['classificationComplete'] = len(classified) == len(kinds)
    write_json(args.output, report)
    print(('FULL' if report['fullScope'] else 'SCOPED') + ' ID-only coverage: '
          + json.dumps(counts, sort_keys=True) + '; report ' + str(args.output), flush=True)
    print('Failure categories (cases, not distinct bugs): ' + json.dumps({
        category: report['diagnostics']['buckets'][category]['cases'] for category in CATEGORIES}), flush=True)
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
