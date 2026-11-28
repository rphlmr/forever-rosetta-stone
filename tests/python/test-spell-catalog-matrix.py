"""Run the strict ID-only spell matrix over a deterministic catalog shard."""

import argparse
import json
import sys

from database_harness import catalog_record_ids
from id_only_matrix_harness import ROOT
from id_only_spell_matrix import run_matrix as run_id_only_matrix
from matrix_classification import classify_failure

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog


def run_matrix(shard_index=0, shard_count=1):
    if shard_count < 1 or not 0 <= shard_index < shard_count:
        raise ValueError('Expected 0 <= shard_index < shard_count')
    # Select the shard from filenames before loading its records and references.
    catalog_ids = catalog_record_ids(ROOT, 'spells')
    ids = [spell_id for spell_id in catalog_ids if spell_id % shard_count == shard_index]
    report = run_id_only_matrix(ids=ids)
    locale_config = load_catalog(ROOT, 'quests', ids={})
    targets = locale_config['locales']
    clients = [locale for locale in targets if locale not in locale_config['rosettaLocales']]
    errors = [row for row in report['failures'] if classify_failure('spells', row)['category'] == 'addon_bug']
    unrenderable = [row for row in report['failures'] if classify_failure('spells', row)['category'] != 'addon_bug']
    report.update({'shardIndex': shard_index, 'shardCount': shard_count,
                   'totalCatalogCount': len(catalog_ids), 'fullScope': shard_count == 1,
                   'spells': len(ids), 'spellIds': ids, 'clientLocales': clients,
                   'targetLocales': targets, 'unrenderable': unrenderable, 'errors': errors})
    filename = 'spells.json' if shard_count == 1 else f'spells-{shard_index}-of-{shard_count}.json'
    path = ROOT / 'datasources/imports/tooltip-matrix' / filename
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    counts = report['counts']
    print(f'Spell matrix: {len(ids)} spells, {counts}, report {path}', flush=True)
    assert report['entityIds'] == ids and not report['mandatoryCoverage']['missingCases']
    assert not report['interfaceErrors']
    assert counts['cases'] == counts['passed'] + counts['failed']
    return 1 if counts['failed'] else 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--shard-index', type=int, default=0)
    parser.add_argument('--shard-count', type=int, default=1)
    args = parser.parse_args()
    raise SystemExit(run_matrix(args.shard_index, args.shard_count))
