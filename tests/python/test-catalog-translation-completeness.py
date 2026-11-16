"""Fail when any maintained catalog field lacks a translation or usable source."""

import collections
import json
import runpy
import sys
from pathlib import Path

from matrix_classification import classify_failure, summarize_report

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
WORK = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))
OUTPUT = ROOT / 'datasources/imports/translation-matrix/catalog-completeness.json'


def run_gate():
    documents = WORK['load_catalogs'](ROOT, None)
    from tools.build.client_label_scope import scope_globalstring_documents
    documents = scope_globalstring_documents(documents, ROOT)
    english = WORK['collect_translation_candidates'](documents, include_excluded_quests=True)
    foreign = WORK['create_foreign_queue'](documents, include_excluded_quests=True)
    failures = []
    for source_type, queue in (('english', english),):
        for job in queue['jobs']:
            for pointer in job['pointers']:
                row = {'entityKind': pointer['kind'], 'catalog': pointer['catalog'],
                       'id': pointer['id'], 'field': pointer['field'], 'index': pointer.get('index'),
                       'locale': job['locale'], 'reason': 'missing target translation',
                       'jobId': job['jobId'], 'sourceLocale': pointer.get('sourceLocale', 'enUS'),
                       'sourceType': source_type}
                diagnostic = classify_failure(pointer['kind'], row)
                failures.append({**row, 'category': diagnostic['category'], 'diagnosticCode': diagnostic['code']})

    for pointer in english['missingSource']:
        row = {'entityKind': pointer['kind'], 'catalog': pointer['catalog'], 'id': pointer['id'],
               'field': pointer['field'], 'index': pointer.get('index'), 'locale': None,
               'reason': 'missing English source field; alternate source not verified',
               'expectationDiagnostic': {'category': 'missing_data', 'code': 'missing_english_source_field'}}
        diagnostic = classify_failure(pointer['kind'], row)
        failures.append({**row, 'category': diagnostic['category'], 'diagnosticCode': diagnostic['code']})

    by_kind = collections.defaultdict(list)
    for row in failures:
        by_kind[row['entityKind']].append(row)
    by_kind_diagnostics = {
        kind: summarize_report({'kind': kind, 'counts': {'cases': len(rows), 'passed': 0,
                                                          'failed': len(rows)}, 'failures': rows})
        for kind, rows in sorted(by_kind.items())
    }
    missing_targets = sum(len(job['pointers']) for job in english['jobs'])
    source_gaps = len(english['missingSource'])
    alternate_candidates = {}
    for job in foreign['jobs']:
        for pointer in job['pointers']:
            identity = (pointer['catalog'], pointer['kind'], pointer['id'], pointer['field'], pointer.get('index'))
            if identity in alternate_candidates:
                continue
            entity = documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']]
            locale = pointer['sourceLocale']
            metadata = WORK['get_metadata'](entity, locale, pointer['field'], pointer.get('index'))
            text = WORK['get_target'](entity, locale, pointer['field'], pointer.get('index'))
            flags = []
            if (metadata or {}).get('origin') == 'ai':
                flags.append('ai_origin')
            if not any(char.isalpha() for char in text):
                flags.append('no_letters')
            if len(text.split()) == 1:
                flags.append('single_word_or_fragment')
            if text.count('[') != text.count(']'):
                flags.append('unbalanced_square_brackets')
            alternate_candidates[identity] = {'entityKind': pointer['kind'], 'catalog': pointer['catalog'],
                                               'id': pointer['id'], 'field': pointer['field'],
                                               'index': pointer.get('index'), 'sourceLocale': locale,
                                               'text': text, 'metadata': metadata, 'qualityFlags': flags,
                                               'status': 'unverified'}
    counts = {'englishSourceJobs': len(english['jobs']),
              'unverifiedOtherSourceJobs': len(foreign['jobs']),
              'unverifiedOtherSourceTargetPointers': sum(len(job['pointers']) for job in foreign['jobs']),
              'unverifiedOtherSourceFields': len(alternate_candidates),
              'noTextInAnyLocaleFields': len(foreign['missingSource']),
              'missingTargetPointers': missing_targets, 'missingEnglishSourceFields': source_gaps,
              'failed': len(failures), 'passed': int(not failures),
              'cases': len(failures) if failures else 1}
    report = {'kind': 'catalogs', 'counts': counts, 'failures': failures,
              'byKindDiagnostics': by_kind_diagnostics,
              'unverifiedAlternateSources': list(alternate_candidates.values()),
              'scope': {'catalogs': sorted(documents), 'entityKinds': sorted({kind for doc in documents.values()
                                                                           for kind in doc['catalogs']}),
                        'locales': documents['quests']['locales'], 'includesExcludedQuests': True,
                        'counting': 'Failures count missing locale/field pointers and source-less fields; '
                                    'jobs are deduplicated source/context/locale groups. A single overall '
                                    'presence check passes only when no gaps exist. These counts do not '
                                    'measure verified translations, language quality, or rendering cases.',
                        'limitations': 'Uses the existing translation-work field and source selection rules. '
                                    'Fields without official English are outside catalog scope and must be removed; '
                                    'foreign text does not authorize creating an English source. '
                                    'A present field is not proof of correct '
                                       'wording or provenance.'}}
    report['diagnostics'] = summarize_report(report)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f"Catalog completeness: {missing_targets} missing targets, {source_gaps} missing English sources; "
          f"{len(english['jobs'])} English-source jobs; {len(foreign['jobs'])} unverified alternate-source "
          f"jobs. Report: {OUTPUT}", flush=True)
    return 1 if failures else 0


if __name__ == '__main__':
    raise SystemExit(run_gate())
