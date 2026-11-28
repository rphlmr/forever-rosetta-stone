"""Check translation rendering and completeness; strict mode also enforces supplemental review groups."""

import argparse
import json
import subprocess
import sys
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from matrix_classification import CATEGORIES, combine_summaries, summarize_report as classify_report, write_summary_markdown


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / 'tests/python'
LUA_TESTS = ROOT / 'tests/lua'
STAGES = [
    ('all-catalog translation completeness', 'test-catalog-translation-completeness.py',
     ['datasources/imports/translation-matrix/catalog-completeness.json']),
    ('all-catalog placeholder contracts against official languages', 'test-catalog-placeholder-matrix.py',
     ['datasources/imports/translation-matrix/catalog-placeholders.json']),
    ('ID-selected quest data and live spell/item capture coverage', 'test-id-only-matrix.py',
     ['datasources/imports/id-only-matrix/report.json']),
    ('quest objectives, summaries and variables', 'test-quest-matrix.py',
     ['datasources/imports/quest-matrix/objectives.json', 'datasources/imports/quest-matrix/summaries.json',
      'datasources/imports/quest-matrix/variables.json']),
    ('quest title and description fields', 'test-quest-fields-matrix.py',
     ['datasources/imports/translation-matrix/quest-fields.json']),
    ('quest UI native-text fallbacks', 'test-quest-ui-fallback-matrix.py',
     ['datasources/imports/translation-matrix/quest-ui-fallbacks.json']),
    ('item catalog and linked effects', 'test-item-catalog-matrix.py', ['datasources/imports/tooltip-matrix/items.json']),
    ('spell catalog, ranks and auras', 'test-spell-catalog-matrix.py', ['datasources/imports/tooltip-matrix/spells.json']),
    ('item, spell, talent, NPC, area and map names', 'test-name-catalog-matrix.py',
     ['datasources/imports/translation-matrix/names.json']),
    ('character stats, quest labels, locations and rewards', 'test-translation-surfaces-matrix.py',
     ['datasources/imports/translation-matrix/surfaces.json']),
    ('item comparisons', 'test-item-comparison-matrix.py', []),
    ('weapon speed labels in every language', 'test-item-speed-matrix.py', []),
    ('recipe reagent tooltips', 'test-recipe-tooltip-matrix.py', []),
    ('shared client tooltip formats', 'test-tooltip-client-labels.py', []),
    ('shared target tooltip formats', 'test-rosetta-tooltip-locales.py', []),
    ('item subclasses', 'test-item-subclasses.py', []),
    ('NPC factions and visible phrases', 'test-npc-factions.py', []),
    ('NPC subnames', 'test-npc-subnames.py', []),
    ('character stat tooltip fixtures', 'test-character-stat-translations.py', []),
    ('captured tooltips without missing translations', 'test-captured-tooltips.py',
     ['datasources/imports/translation-matrix/captured-tooltips.json']),
    ('live aura translation completeness', 'test-structured-auras.py', []),
    ('live spell, talent and aura values', 'test-spell-live-values.py', []),
    ('nested tooltip duration substitutions', 'test-nested-tooltip-duration.py', []),
    ('item effect markup and fixed plurals', 'test-item-effect-markup.py', []),
]
LUA_STAGES = [
    ('whole tooltip rendering', 'test-whole-tooltip-rendering.lua'),
    ('aura tooltip behavior', 'test-aura-tooltips.lua'),
    ('NPC tooltip rendering', 'test-npc-whole-tooltip.lua'),
]
UNITTEST_CLASSES = {
    'test-spell-live-values.py': 'SpellLiveValueTests',
    'test-structured-auras.py': 'StructuredAuraTests',
    'test-item-comparison-matrix.py': 'ComparisonMatrix',
    'test-item-speed-matrix.py': 'ItemSpeedMatrix',
    'test-recipe-tooltip-matrix.py': 'RecipeMatrix',
    'test-nested-tooltip-duration.py': 'NestedTooltipDurationTests',
    'test-item-effect-markup.py': 'ItemEffectMarkupTests',
}
GAP_KEYS = ('gaps', 'unrenderable', 'missingTargets', 'missingNativeSources',
            'missingNativeSource', 'missingTargetSummary', 'unavailableOffers',
            'boundaries', 'unsupported', 'missingSources', 'missingTargetsByField',
            'missingNativeEvidence', 'reputationFallback', 'fallback', 'missingTarget',
            'missingSource', 'unsupportedReverse', 'missingReverseTarget', 'ambiguous',
            'unsupportedShape', 'statCandidates', 'notApplicable', 'missingEntitySource')
STAGE_TIMEOUT_SECONDS = 3600


def summarize_report(path):
    data = json.loads(path.read_text(encoding='utf-8'))
    gaps = {key: len(data[key]) for key in GAP_KEYS if isinstance(data.get(key), (list, dict))}
    actionable = Counter()
    for key in ('missingTarget', 'missingTargets', 'missingTargetSummary', 'missingReverseTarget'):
        if isinstance(data.get(key), list):
            actionable[key] += len(data[key])
    for row in data.get('gaps', []):
        if row.get('kind') == 'missing target wording':
            actionable['item missing target wording groups'] += 1
    for row in data.get('unrenderable', []):
        reason = row.get('reason', '')
        if reason in ('missing target text', 'missing target name',
                      'spell name-description line has no corresponding renderer') or reason.startswith(
                          'unsupportedRendererGrammar'):
            actionable['spell ' + reason] += 1
    ambiguous_stats = {
        (row.get('client'), row.get('target'), row.get('field'), row.get('source'),
         row.get('expected'), row.get('actual'), tuple(sorted(row.get('conflictingKeys') or ())))
        for row in data.get('statCandidates', [])
        if row.get('actual') != row.get('expected') and row.get('conflictingKeys')
    }
    if ambiguous_stats:
        actionable['ambiguous stat render groups'] = len(ambiguous_stats)
    result = {'path': str(path.relative_to(ROOT)), 'counts': data.get('counts', {}), 'gaps': gaps,
              'actionableGroups': dict(actionable)}
    integrity_errors = list(data.get('enumerationErrors', [])) + list(data.get('interfaceErrors', []))
    if data.get('mandatoryCoverage', {}).get('missingCases'):
        integrity_errors.append('Mandatory target cases are missing')
    if data.get('classificationComplete') is False:
        integrity_errors.append('Some required entity-kind reports could not be classified')
    for stage in data.get('stages', []):
        if stage.get('infrastructureError'):
            integrity_errors.append(stage['infrastructureError'])
        integrity_errors.extend(stage.get('enumerationErrors', []))
    if integrity_errors:
        result['integrityErrors'] = integrity_errors
    if 'diagnostics' in data:
        if 'kind' in data and 'failures' in data:
            diagnostic = classify_report(data)
            if diagnostic != data['diagnostics']:
                raise ValueError('Stale or inconsistent failure classification: ' + str(path))
        else:
            diagnostic = data['diagnostics']
        result['diagnostics'] = diagnostic
    if data.get('classificationComplete') and data.get('stages'):
        result['caseReports'] = [{'kind': stage['kind'], 'report': stage['report'],
                                  'reportSha256': stage['reportSha256'], 'diagnostics': stage['diagnostics']}
                                 for stage in data['stages']]
    if data.get('kind') == 'catalogs':
        result['translationCompleteness'] = {
            key: data['counts'][key] for key in (
                'englishSourceJobs', 'missingTargetPointers', 'missingEnglishSourceFields',
                'noTextInAnyLocaleFields', 'unverifiedOtherSourceFields',
                'unverifiedOtherSourceTargetPointers')}
    return result


def execute_stage(command):
    try:
        result = subprocess.run(command, cwd=ROOT, check=False, timeout=STAGE_TIMEOUT_SECONDS)
        return result.returncode == 0, None
    except subprocess.TimeoutExpired:
        return False, f'timed out after {STAGE_TIMEOUT_SECONDS} seconds'


def merge_spell_reports(reports, expected_ids):
    if len(reports) != 3:
        raise ValueError('Expected exactly three spell shard reports')
    counts, ids, unrenderable, errors = Counter(), set(), [], []
    clients, targets = reports[0]['clientLocales'], reports[0]['targetLocales']
    for index, report in enumerate(reports):
        if 'diagnostics' in report and report['diagnostics'] != classify_report(report):
            raise ValueError(f'Stale spell shard classification: {index}')
        if report['counts'].get('failed', 0) != len(report['errors']) + len(report['unrenderable']):
            raise ValueError(f'Spell shard failure categories do not reconcile: {index}')
        shard_ids = report['spellIds']
        if (report['shardIndex'] != index or report['shardCount'] != 3
                or report['totalCatalogCount'] != len(expected_ids)
                or report['spells'] != len(shard_ids)
                or report['clientLocales'] != clients or report['targetLocales'] != targets):
            raise ValueError(f'Invalid spell shard metadata: {index}')
        if len(set(shard_ids)) != len(shard_ids) or ids.intersection(shard_ids):
            raise ValueError(f'Duplicate spell IDs in shard {index}')
        if any(spell_id % 3 != index for spell_id in shard_ids):
            raise ValueError(f'Spell ID assigned to the wrong shard: {index}')
        ids.update(shard_ids)
        counts.update(report['counts'])
        unrenderable.extend(report['unrenderable'])
        errors.extend(report['errors'])
    if ids != expected_ids:
        raise ValueError(f'Spell shards do not cover the catalog: missing {len(expected_ids - ids)}, '
                         f'extra {len(ids - expected_ids)}')
    result = {'counts': dict(counts), 'spells': len(ids), 'totalCatalogCount': len(expected_ids),
            'spellIds': sorted(ids), 'shardCount': 3, 'clientLocales': clients, 'targetLocales': targets,
            'unrenderable': unrenderable, 'errors': errors}
    if all('diagnostics' in report for report in reports):
        result['diagnostics'] = combine_summaries([report['diagnostics'] for report in reports])
    return result


def stage_status(result):
    diagnostics = [report['diagnostics'] for report in result['reports'] if 'diagnostics' in report]
    if any(report.get('integrityErrors') for report in result['reports']):
        return 'stage_error'
    if not result['passed']:
        if result.get('missingReport') or not diagnostics:
            return 'stage_error'
        if any(row['buckets']['addon_bug']['cases'] for row in diagnostics):
            return 'addon_failure'
        if any(row['buckets']['unclassified']['cases'] for row in diagnostics):
            return 'needs_investigation'
        return 'coverage_incomplete'
    gap_count = sum(sum(value for key, value in report['gaps'].items() if key != 'notApplicable')
                    for report in result['reports'])
    return 'verified_with_gaps' if gap_count else 'verified_scope' if result['reports'] else 'verified_fixture'


def execute_spell_shards():
    paths = [ROOT / f'datasources/imports/tooltip-matrix/spells-{index}-of-3.json' for index in range(3)]
    previous = [path.stat().st_mtime_ns if path.exists() else None for path in paths]
    commands = [[sys.executable, str(TESTS / 'test-spell-catalog-matrix.py'),
                 '--shard-index', str(index), '--shard-count', '3'] for index in range(3)]
    with ThreadPoolExecutor(max_workers=3) as executor:
        results = list(executor.map(execute_stage, commands))
    if any(not path.is_file() or (old is not None and path.stat().st_mtime_ns == old)
           for path, old in zip(paths, previous)):
        return False, 'A spell shard did not produce a fresh report'
    try:
        reports = [json.loads(path.read_text(encoding='utf-8')) for path in paths]
        expected_ids = {int(path.stem) for path in (ROOT / 'catalogs/spells').glob('*.json')
                        if path.stem.isdecimal()}
        merged = merge_spell_reports(reports, expected_ids)
    except (OSError, ValueError, KeyError, TypeError) as error:
        return False, f'Cannot merge spell shards: {error}'
    output = ROOT / 'datasources/imports/tooltip-matrix/spells.json'
    output.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Merged {len(merged["spellIds"])} spell IDs; {len(merged["unrenderable"])} grouped gaps: {output}')
    if not all(passed for passed, _ in results) or merged['errors'] or merged['counts'].get('failed'):
        return False, (f'Spell coverage: {merged["counts"].get("failed", 0)} failed cases; '
                       f'{len(merged["errors"])} rendering failures. Full reports retained at {output}')
    return True, None


def main(partial=False):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--list', action='store_true', help='List the translation surfaces without running them')
    parser.add_argument('--strict-coverage', action='store_true',
                        help='Fail on missing target text, known unsupported renderer grammar or ambiguous stat labels')
    args = parser.parse_args()
    if args.list:
        for label, filename, _ in STAGES:
            print(f'{label}: {filename}')
        for label, filename in LUA_STAGES:
            print(f'{label}: {filename}')
        return

    assert Path.cwd() == ROOT, 'Run tests from the repository root'
    results = []
    unittest_runner = ('import runpy,sys,unittest; from pathlib import Path; '
                       'sys.path.insert(0,str(Path(sys.argv[1]).resolve().parent)); '
                       'namespace=runpy.run_path(sys.argv[1]); '
                       'suite=unittest.defaultTestLoader.loadTestsFromTestCase(namespace[sys.argv[2]]); '
                       'assert suite.countTestCases() > 0, "No tests discovered"; '
                       'sys.exit(not unittest.TextTestRunner().run(suite).wasSuccessful())')
    for label, filename, reports in STAGES:
        print(f'\nRunning {label}: {filename}', flush=True)
        previous = {report: (ROOT / report).stat().st_mtime_ns if (ROOT / report).exists() else None
                    for report in reports}
        started = time.monotonic()
        command = ([sys.executable, '-c', unittest_runner, str(TESTS / filename), UNITTEST_CLASSES[filename]]
                   if filename in UNITTEST_CLASSES else [sys.executable, str(TESTS / filename)])
        passed, error = (execute_spell_shards() if filename == 'test-spell-catalog-matrix.py'
                         else execute_stage(command))
        result = {'surface': label, 'test': filename, 'passed': passed,
                  'seconds': round(time.monotonic() - started, 2), 'reports': []}
        if error:
            result['error'] = error
        for report in reports:
            path = ROOT / report
            fresh = path.is_file() and (previous[report] is None or path.stat().st_mtime_ns != previous[report])
            if fresh:
                try:
                    result['reports'].append(summarize_report(path))
                except (ValueError, KeyError, TypeError) as cause:
                    result['passed'] = False
                    result['reports'].append({'path': report, 'counts': {}, 'gaps': {}, 'actionableGroups': {},
                                              'integrityErrors': [str(cause)]})
            elif result['passed']:
                result['passed'] = False
                result['missingReport'] = report
                print(f'Missing fresh report: {report}', flush=True)
        results.append(result)

    # Standalone Lua stages need the same file inventory as the core test runner.
    lua_runner = ('from pathlib import Path; from lupa.lua51 import LuaRuntime; import sys; '
                  'path = Path(sys.argv[1]); sys.path.insert(0, str(path.parent.parent / "python")); '
                  'from database_harness import install_globalstring_ids; '
                  'install_globalstring_ids(LuaRuntime(encoding=None)).execute(path.read_bytes())')
    for label, filename in LUA_STAGES:
        print(f'\nRunning {label}: {filename}', flush=True)
        started = time.monotonic()
        passed, error = execute_stage([sys.executable, '-c', lua_runner, str(LUA_TESTS / filename)])
        result = {'surface': label, 'test': filename, 'passed': passed,
                  'seconds': round(time.monotonic() - started, 2), 'reports': []}
        if error:
            result['error'] = error
        results.append(result)

    for result in results:
        result['status'] = stage_status(result)
    actionable_count = sum(sum(report['actionableGroups'].values())
                           for result in results for report in result['reports'])
    output = ROOT / ('datasources/imports/translation-matrix/suite-partial.json' if partial
                     else 'datasources/imports/translation-matrix/suite.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    # The spell shard stage repeats the spell cases in the ID-only stage. Count them once.
    authoritative = next((report.get('diagnostics') for result in results
                          if result['test'] == 'test-id-only-matrix.py' for report in result['reports']), None)
    supplemental = [report['diagnostics'] for result in results
                    if result['test'] == 'test-quest-ui-fallback-matrix.py' for report in result['reports']
                    if 'diagnostics' in report]
    overall = combine_summaries([authoritative, *supplemental]) if authoritative else None
    completeness_gate = next((report.get('translationCompleteness') for result in results
                              for report in result['reports'] if 'translationCompleteness' in report), None)
    placeholder_gate = next((report for result in results for report in result['reports']
                             if result['test'] == 'test-catalog-placeholder-matrix.py'), None)
    classification_path = ROOT / 'datasources/imports/translation-matrix/classification.json'
    classification = {'strictCompletenessRequired': True, 'catalogTranslationCompleteness': completeness_gate,
                      'catalogPlaceholderContracts': placeholder_gate,
                      'catalogCoverage': authoritative, 'overall': overall,
                      'source': 'datasources/imports/id-only-matrix/report.json',
                      'caseReports': [row for result in results for report in result['reports']
                                      for row in report.get('caseReports', [])],
                      'additionalChecks': supplemental,
                      'duplicateSpellStageCountedAgain': False,
                      'stageErrors': [result['test'] for result in results if result['status'] == 'stage_error'],
                      'linguisticMeaningIndependentlyVerified': False,
                      'scope': 'Owned quest/item/spell target fields in every configured locale and controlled profile. '
                               'This is not proof of every live-client state.'}
    classification_path.write_text(json.dumps(classification, ensure_ascii=False, indent=2) + '\n')
    write_summary_markdown(classification_path.with_suffix('.md'), classification)
    output.write_text(json.dumps({'partial': partial, 'strictCoverage': args.strict_coverage,
                                  'classification': str(classification_path.relative_to(ROOT)),
                                  'actionableGroups': actionable_count, 'stages': results},
                                 ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('\nPartial translation matrix results:' if partial else '\nTranslation matrix results:')
    for result in results:
        print(f"{result['status']}: {result['surface']} ({result['seconds']}s)")
        if result.get('error'):
            print(f"  {result['error']}")
        for report in result['reports']:
            print(f"  {report['path']}: recorded gaps/boundaries {report['gaps']}; "
                  f"actionable groups {report['actionableGroups']}")
            if 'diagnostics' in report:
                diagnostic = report['diagnostics']
                print('    Categories: ' + ', '.join(
                    f'{category}={diagnostic["buckets"][category]["cases"]}' for category in CATEGORIES))
    if authoritative:
        print(f'Verified catalog rendering cases: {authoritative["verifiedCases"]}/{authoritative["totalCases"]}')
        print('Target presence and variable rendering are checked; linguistic meaning is not independently certified.')
        for category in CATEGORIES:
            bucket = overall['buckets'][category]
            print(f'{bucket["label"]}: {bucket["cases"]} cases, {bucket["affectedTargets"]} affected targets')
        print('Every unverified case still fails strict completeness. Detailed groups/examples: '
              'datasources/imports/id-only-matrix/report-{quests,items,spells}.json')
    if completeness_gate:
        print('All-catalog translation gate (separate field counts): '
              f'{completeness_gate["missingTargetPointers"]} English-source-backed missing targets; '
              f'{completeness_gate["missingEnglishSourceFields"]} blocked source fields; '
              f'{completeness_gate["unverifiedOtherSourceFields"]} unverified alternate-source fields.')
    print(f'Additional review groups: {actionable_count} (not deduplicated across supplemental stages).')
    print(f'Classification: {classification_path}; stage results: {output}')
    if not all(result['passed'] for result in results) or (args.strict_coverage and actionable_count):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
