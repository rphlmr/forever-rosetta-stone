"""Prepare a bounded, staged corpus pilot and measure submitted results without catalog writes."""

import argparse
import copy
import hashlib
import json
import runpy
import time
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.catalogs.catalog_storage import dump_json, read_json
from datasources.corpus.translation_corpus import localized_fields, open_corpus, packet


ROOT = Path(__file__).resolve().parents[2]
BATCH = runpy.run_path(str(ROOT / 'tools/catalogs/catalog-batch.py'))


def prepare(directory, database, scope, holdouts):
    directory = Path(directory).resolve()

    if not directory.is_relative_to(ROOT / 'datasources/imports') or directory.exists():
        raise ValueError('Use a new pilot directory under datasources/imports/')

    started = time.time()
    directory.mkdir(parents=True)
    db = open_corpus(database)
    assignments = []

    try:
        for index, batch in enumerate(BATCH['prepare_batches'](ROOT, scope, 1)):
            kind = next(iter(batch['records']))
            entity_id = next(iter(batch['records'][kind]))
            name = f'{index:05d}'
            selected = [row for row in holdouts if row['kind'] == kind and str(row['id']) == entity_id]
            before = batch['records'][kind][entity_id]
            result = copy.deepcopy(batch['records'])
            context = packet(db, ROOT, kind, entity_id, batch['localeConfig']['locales'], 2)
            keys = []

            for holdout in selected:
                locale, field = holdout['locale'], holdout['field']
                keys.append({'locale': locale, 'field': field, 'mode': holdout['mode']})

                for entity in (result[kind][entity_id], context['entity']):
                    del entity['locales'][locale][field]
                    del entity['locales'][locale]['translationMetadata']['fields'][field]

            (directory / f'{name}.batch.json').write_text(dump_json(batch))
            (directory / f'{name}.results.json').write_text(dump_json(result))
            (directory / f'{name}.context.json').write_text(dump_json(context))
            assignments.append({'name': name, 'kind': kind, 'id': entity_id, 'holdouts': keys,
                                'sourceSha256': hashlib.sha256(dump_json(before).encode()).hexdigest(),
                                'packetBytes': (directory / f'{name}.context.json').stat().st_size})
    finally:
        db.close()

    manifest = {'startedEpoch': started, 'preparedEpoch': time.time(), 'database': str(Path(database).resolve()),
                'scope': scope, 'assignments': assignments,
                'rules': 'Staging only; original batch snapshots are coordinator-only held-out answers.'}
    (directory / 'manifest.json').write_text(dump_json(manifest))

    return manifest


def evaluate(directory, corrected=False):
    directory = Path(directory)
    manifest = read_json(directory / 'manifest.json')
    results = []

    for assignment in manifest['assignments']:
        name, kind, entity_id = assignment['name'], assignment['kind'], assignment['id']
        batch = read_json(directory / f'{name}.batch.json')
        corrected_path = directory / f'{name}.corrected.results.json'
        result_path = corrected_path if corrected and corrected_path.exists() else directory / f'{name}.results.json'
        result = read_json(result_path)
        BATCH['validate_batch'](ROOT, batch, result)
        before, after = batch['records'][kind][entity_id], result[kind][entity_id]
        holdouts = {(row['locale'], row['field']): row['mode'] for row in assignment['holdouts']}
        changes, recovery = [], []
        english = dict(localized_fields(before['locales']['enUS']))

        if {key: value for key, value in before.items() if key != 'locales'} != {
            key: value for key, value in after.items() if key != 'locales'
        }:
            raise ValueError('Pilot must preserve relationships and source templates: ' + name)

        for locale, localized in after['locales'].items():
            original = before['locales'].get(locale, {})
            old_fields, new_fields = dict(localized_fields(original)), dict(localized_fields(localized))

            for field, text in new_fields.items():
                old = old_fields.get(field)
                metadata = localized.get('translationMetadata', {}).get('fields', {}).get(field)
                old_metadata = original.get('translationMetadata', {}).get('fields', {}).get(field)

                if (locale, field) in holdouts:
                    recovery.append({'locale': locale, 'field': field, 'mode': holdouts[(locale, field)],
                                     'exactBaselineMatch': old == text, 'text': text,
                                     'baseline': old, 'metadata': metadata})

                if text == old and metadata == old_metadata:
                    continue

                if old is not None and (locale, field) not in holdouts:
                    raise ValueError(f'Unexpected rewrite outside controlled holdouts: {name}/{locale}/{field}')

                if field not in english:
                    raise ValueError(f'Pilot added a field outside English source scope: {name}/{locale}/{field}')

                changes.append({'locale': locale, 'field': field, 'before': old, 'after': text,
                                'metadata': metadata, 'controlledHoldout': (locale, field) in holdouts})

        metrics = read_json(directory / f'{name}.metrics.json')
        results.append({'name': name, 'kind': kind, 'id': entity_id, 'batchValidation': 'passed',
                        'holdouts': recovery, 'changes': changes, 'worker': metrics,
                        'correctionApplied': result_path == corrected_path})

    report = {'manifest': manifest, 'evaluatedEpoch': time.time(), 'results': results,
              'catalogWrites': 0, 'limitations': ['Reference recovery is not novel translation accuracy.',
                                                 'Generated text requires semantic assessment; contract checks alone do not score meaning.']}
    filename = 'evaluation-corrected.json' if corrected else 'evaluation.json'
    (directory / filename).write_text(dump_json(report))

    return report


def summarize(directory):
    directory = Path(directory)
    first = read_json(directory / 'evaluation.json')
    accepted = read_json(directory / 'evaluation-corrected.json')
    assessments = {path.name: read_json(path) for path in sorted(directory.glob('*.assessment.json'))}
    workers = {row['name']: row['worker'] for row in first['results']}
    manifest = first['manifest']
    worker_end = max(row['finishedEpoch'] for row in workers.values())
    corrections = {path.name: read_json(path) for path in sorted(directory.glob('*.correction.json'))}
    reference = [field for row in first['results'] for field in row['holdouts']
                 if field['mode'] != 'authoredTranslation']
    summary = {
        'model': 'gpt-6.1-terra', 'reasoningEffort': 'medium', 'files': len(workers),
        'locales': len(BATCH['get_locale_config'](ROOT)['locales']),
        'preparationSeconds': manifest['preparedEpoch'] - manifest['startedEpoch'],
        'dispatchToLastWorkerResultSeconds': worker_end - manifest['preparedEpoch'],
        'workerReportedSeconds': {name: row['finishedEpoch'] - row['startedEpoch'] for name, row in workers.items()},
        'elapsedThroughReportSeconds': time.time() - manifest['startedEpoch'],
        'referenceHoldouts': len(reference),
        'exactReferenceRecoveries': sum(row['exactBaselineMatch'] for row in reference),
        'authoredControlledFields': sum(field['mode'] == 'authoredTranslation'
                                       for row in first['results'] for field in row['holdouts']),
        'originallyAbsentLocaleFieldsFilled': sum(not field['controlledHoldout']
                                                  for row in accepted['results'] for field in row['changes']),
        'firstAttemptFilesPassedBatchValidation': sum(row['batchValidation'] == 'passed' for row in first['results']),
        'correctedFilesPassedBatchValidation': sum(row['batchValidation'] == 'passed' for row in accepted['results']),
        'corrections': corrections, 'assessments': assessments, 'catalogWrites': 0,
        'fullRunStarted': False,
        'limitations': [
            'Earlier inherited-model workers were interrupted and excluded after the explicit Terra correction.',
            'Worker timing is self-reported: item start has whole-second precision; spell start excludes initial inspection.',
            'Reference holdout recovery is not novel translation accuracy.',
            'Only Danish was newly authored; existing translations in the other locales were preserved.',
            'Assessments use a separate Terra agent, not native-speaker certification; client rendering is untested.',
            'One first-attempt readability uncertainty came from an overly strict coordinator gender-token instruction.',
            'Nine real gaps are absent localized fields with native text already available in references, not nine newly discovered translations.',
            'Some recovered provenance is an inherited catalog claim; matching later source text does not verify an older build/source attribution.',
            'No comparable old-run baseline or no-corpus control was measured; no speed multiplier or reliable full-run ETA is established.',
            'Native/community evidence recovery dominates this tiny sample; its throughput is not a full-catalog forecast.',
        ],
        'artifactFiles': sorted(path.name for path in directory.glob('*.json')),
    }
    (directory / 'summary.json').write_text(dump_json(summary))

    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    create = commands.add_parser('prepare')
    create.add_argument('--directory', type=Path, required=True)
    create.add_argument('--database', type=Path, required=True)
    create.add_argument('--scope', type=Path, required=True)
    create.add_argument('--holdouts', type=Path, required=True)
    check = commands.add_parser('evaluate')
    check.add_argument('--directory', type=Path, required=True)
    check.add_argument('--corrected', action='store_true')
    report_command = commands.add_parser('summarize')
    report_command.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()

    if args.command == 'prepare':
        report = prepare(args.directory, args.database, read_json(args.scope), read_json(args.holdouts))
    elif args.command == 'evaluate':
        report = evaluate(args.directory, args.corrected)
    else:
        report = summarize(args.directory)

    print(dump_json(report), end='')


if __name__ == '__main__':
    main()
