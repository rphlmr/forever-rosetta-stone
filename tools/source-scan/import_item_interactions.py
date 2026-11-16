"""Prepare owned interaction-label identities from unambiguous native API rows."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from triage_official_tooltip_matrix import normalized

sys.path.insert(0, str(gaps.ROOT))
from tools.catalogs.catalog_storage import dump_json
from tools.catalogs.import_policy import verify_sources
from tools.catalogs.english_scope import has_english_text


INTERACTION_KEYS = frozenset(('ITEM_READABLE', 'ITEM_SIGNABLE'))


def proposals(fixtures, wanted, root=gaps.ROOT):
    replay = gaps.Replay('enUS', {})
    db, found = replay.database, {}
    for observation in matrix.observations(fixtures):
        entity = observation['id']
        if observation['kind'] != 'item' or entity not in wanted:
            continue
        data = gaps.clean(observation['data'])
        if data.get('id') != entity or data.get('type') != 0:
            continue
        for position, line in enumerate(data.get('lines', []), 1):
            if not isinstance(line.get('leftText'), str):
                continue
            text = normalized(line.get('leftText'))
            if line.get('type') != 0 or line.get('rightText') or not text:
                continue
            keys = matrix.copied_rows(db.GetGlobalStringKeysByText(db, text.encode(), observation['locale'].encode())) or []
            if len(keys) != 1 or keys[0] not in INTERACTION_KEYS:
                continue
            value, label_id = db.GetGlobalStringByKey(db, keys[0].encode(), observation['locale'].encode())
            if not value or normalized(value.decode()) != text:
                continue
            capture = json.loads((root / observation['source']['fixture']).read_text())
            evidence = {'interactionLabelID': label_id, 'key': keys[0], 'lineIndex': position,
                        'source': observation['source'], 'locale': observation['locale'],
                        'build': capture['source']['build']}
            found.setdefault(entity, []).append(evidence)
    for entity, evidence in found.items():
        if len({entry['interactionLabelID'] for entry in evidence}) != 1:
            raise ValueError(f'Conflicting interaction labels for item {entity}')
    return found


def prepare(fixtures, wanted, database, output, root=gaps.ROOT):
    database = verify_sources(database, root)
    output = output.resolve()
    if output.exists() or not output.is_relative_to((root / 'datasources/imports').resolve()):
        raise ValueError('Use a new output directory under datasources/imports/')
    facts = proposals(fixtures, wanted, root)
    if set(facts) != set(wanted):
        raise ValueError('Every requested owner needs an unambiguous native interaction row')
    (output / 'results').mkdir(parents=True)
    files, inputs = [], {}
    for number, (entity, evidence) in enumerate(sorted(facts.items()), 1):
        fact = evidence[0]
        path = Path(f'catalogs/items/{entity}.json')
        before = (root / path).read_bytes()
        after = copy.deepcopy(json.loads(before))
        if not has_english_text(after, 'name'):
            raise ValueError('Interaction ownership requires an owned English item identity')
        tooltip = after.setdefault('tooltipData', {})
        if tooltip.get('interactionLabelID', fact['interactionLabelID']) != fact['interactionLabelID']:
            raise ValueError('Existing interaction ownership differs; preserve it for review')
        tooltip['interactionLabelID'] = fact['interactionLabelID']
        tooltip.setdefault('interactionLabelSourceMetadata', {
            'source': 'clientCapture', 'sourceBuild': fact['build'], 'sourceLocale': fact['locale'],
            'captureSha256': fact['source']['sha256'], 'sourceFixture': fact['source']['fixture'],
            'sourceLineType': 'None', 'sourceGlobalStringKey': fact['key']})
        owner = Path(f"catalogs/globalstrings/{fact['interactionLabelID']}.json")
        if json.loads((root / owner).read_text())['key'] != fact['key']:
            raise ValueError('GlobalString owner identity differs')
        for entry in evidence:
            inputs[entry['source']['fixture']] = entry['source']['sha256']
        inputs[str(owner)] = hashlib.sha256((root / owner).read_bytes()).hexdigest()
        result = Path(f'results/{number}.json')
        raw = dump_json(after).encode()
        (output / result).write_bytes(raw)
        files.append({'path': str(path), 'result': str(result),
                      'beforeSha256': hashlib.sha256(before).hexdigest(), 'afterSha256': hashlib.sha256(raw).hexdigest()})
    manifest = {'database': str(database), 'databaseSha256': hashlib.sha256(database.read_bytes()).hexdigest(),
                'policyInputs': inputs, 'files': files, 'counts': {'files': len(files)}, 'unresolvedFields': 0}
    (output / 'manifest.json').write_text(dump_json(manifest))
    (output / 'evidence.json').write_text(dump_json(facts))
    return {'preparedFiles': len(files)}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures', type=Path, default=gaps.ROOT / 'tests/fixtures/tooltip-campaign')
    parser.add_argument('--ids', nargs='+', type=int, required=True)
    parser.add_argument('--database', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.fixtures, set(args.ids), args.database, args.output)))
