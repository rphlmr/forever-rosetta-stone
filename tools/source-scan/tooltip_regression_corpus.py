#!/usr/bin/env python3
"""Prepare, review, apply and replay bounded multilingual regression fixtures.

Expected text comes from the independent synthetic fixture builder, never from
production output. Generated proposals and reports stay under ignored imports.
"""
import argparse
import difflib
import hashlib
import itertools
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
CORPUS = Path('tests/fixtures/tooltip-regressions')
sys.path.insert(0, str(ROOT / 'tests/python'))
sys.path.insert(0, str(ROOT))

from tools.catalogs.official_text import OFFICIAL_LOCALES


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def encode(value):
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + '\n'


def checksum(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def inventory(root):
    directory = root / CORPUS
    return {path.name: checksum(path) for path in sorted(directory.glob('*.json'))
            if path.name != 'selection.json'}


def plan(root=ROOT):
    from template_pilot_spells import talent_rank_contexts
    selection = read(root / CORPUS / 'selection.json')
    sources = sorted(OFFICIAL_LOCALES)
    targets = selection['targetLocales']
    if len(targets) != len(set(targets)) or not set(sources) <= set(targets):
        raise ValueError('Invalid regression locale inventory')
    scenarios = {}
    for chosen in selection['selections']:
        surface, entity, field = chosen['surface'], chosen['id'], chosen['field']
        if surface not in ('spells', 'auras', 'talents') or field not in ('description', 'auraDescription'):
            raise ValueError('Unsupported regression surface or field')
        ranks = [None]
        if surface == 'talents':
            talent = read(root / f'catalogs/talents/{entity}.json')
            ranks = talent_rank_contexts(talent, read(root / 'tests/fixtures/template-pilot-talents.json'))
        for rank, profile in itertools.product(ranks, selection['profiles']):
            if profile not in ('baseline', 'modified'):
                raise ValueError('Unsupported synthetic profile')
            scenario = dict(surface=surface, id=rank['spellId'] if rank else entity,
                            field=field, profile=profile)
            if rank:
                scenario.update(talentId=entity, rank=rank['rank'])
            name = f'{surface}-{entity}' + (f'-rank-{rank["rank"]}' if rank else '') + f'-{profile}.json'
            if name in scenarios:
                raise ValueError('Duplicate regression selection: ' + name)
            scenarios[name] = (scenario, rank)
    if not scenarios:
        raise ValueError('Regression selection is empty')
    return sources, targets, scenarios


def dependencies(root, scenario):
    """Read only selected records and their explicit spell references."""
    files = {CORPUS / 'selection.json',
             Path(__file__).relative_to(ROOT), Path('tests/python/live_spell_fixture.py'),
             Path('tests/python/template_pilot_spells.py')}
    if scenario['surface'] == 'talents':
        files.update({Path(f'catalogs/talents/{scenario["talentId"]}.json'),
                      Path('tests/fixtures/template-pilot-talents.json')})
    spells, pending = {}, [scenario['id']]
    while pending:
        entity = pending.pop()
        if str(entity) in spells:
            continue
        if len(spells) >= 100:
            raise ValueError('Regression dependency scope exceeds 100 spells')
        path = Path(f'catalogs/spells/{entity}.json')
        record = read(root / path)
        spells[str(entity)] = record
        files.add(path)
        for localized in record.get('locales', {}).values():
            for field in ('description', 'auraDescription'):
                text = localized.get(field, '')
                for match in re.finditer(r'\$(?:@(?:spellname|spelldesc|spellaura)<?(\d+)>?|(\d+)[sSmMoOtTdD]\d*)', text):
                    pending.append(int(match[1] or match[2]))
    return spells, {str(path): checksum(root / path) for path in sorted(files)}


def generate(root=ROOT):
    from live_spell_fixture import compile_nodes, make_fixture, slots
    from template_pilot_spells import talent_fixture
    sources, targets, scenarios = plan(root)
    documents = {}
    for name, (scenario, rank) in scenarios.items():
        spells, pins = dependencies(root, scenario)
        inputs, expected = {}, {}
        for locale in set(sources) | set(targets):
            nodes = compile_nodes(spells, scenario['id'], locale, scenario['field'], scenario['profile'])
            if any(slot.duration for slot in slots(nodes)):
                raise ValueError('Duration fixtures need explicit format dependency pins before entering this corpus')
        for source, target in itertools.product(sources, targets):
            args = (spells, rank, source, target, scenario['profile'], scenario['field'])
            fixture = (talent_fixture(*args) if rank else make_fixture(
                spells, scenario['id'], target, scenario['profile'], scenario['field'], source=source))
            for values, key, text in ((inputs, source, fixture['native']), (expected, target, fixture['expected'])):
                if not isinstance(text, str) or not text.strip():
                    raise ValueError('Missing regression input or expectation: ' + name)
                if key in values and values[key] != text:
                    raise ValueError('Locale-dependent slot alignment needs an explicit paired fixture: ' + name)
                values[key] = text
        documents[name] = {'scenario': scenario, 'sourceInputs': pins, 'inputs': inputs, 'expected': expected,
                           'provenance': 'Independent synthetic displayed values from maintained catalog templates; not an in-game capture.',
                           'caseCount': len(sources) * len(targets)}
    return documents


def validate(root=ROOT, directory=None):
    directory = Path(directory) if directory else root / CORPUS
    sources, targets, scenarios = plan(root)
    found = {path.name for path in directory.glob('*.json') if path.name != 'selection.json'}
    if found != set(scenarios):
        raise ValueError('Regression inventory mismatch; missing=' + str(sorted(set(scenarios) - found))
                         + ', extra=' + str(sorted(found - set(scenarios))))
    documents = {}
    for name, (scenario, _) in scenarios.items():
        document = read(directory / name)
        if (document['scenario'] != scenario or set(document['inputs']) != set(sources)
                or set(document['expected']) != set(targets)
                or document['caseCount'] != len(sources) * len(targets)):
            raise ValueError('Regression case enumeration mismatch: ' + name)
        if any(not isinstance(text, str) or not text.strip()
               for key in ('inputs', 'expected') for text in document[key].values()):
            raise ValueError('Missing regression text: ' + name)
        # Recompute the bounded dependency inventory too, so deleting a pin cannot hide drift.
        _, pins = dependencies(root, scenario)
        if document['sourceInputs'] != pins:
            changed = sorted(key for key in pins.keys() | document['sourceInputs'].keys()
                             if pins.get(key) != document['sourceInputs'].get(key))
            raise ValueError('Stale regression fixture: ' + name + '; prepare a reviewed update for ' + ', '.join(changed))
        documents[name] = document
    return documents


def replay(root=ROOT, directory=None):
    from id_only_matrix_harness import IdOnlyHarness, to_python
    from template_pilot_spells import _renderer
    documents = validate(root, directory)
    harness = IdOnlyHarness(root)
    render = _renderer(harness)
    failures, checked = [], 0
    for name, document in documents.items():
        scenario = document['scenario']
        for source, native in document['inputs'].items():
            for target, expected in document['expected'].items():
                checked += 1
                harness.set_context(target, scenario['id'], scenario['profile'], entity_kind='spells')
                harness.set_source_locale(source)
                result, error, forbidden = harness.attempt(lambda: render(
                    harness.addon, scenario['id'], target.encode(), native.encode(), scenario['surface'].encode()))
                actual, incomplete = result if result is not None else (None, True)
                actual = to_python(actual)
                if error or forbidden or incomplete or actual != expected:
                    failures.append({'fixture': name, 'source': source, 'target': target,
                                     'expected': expected, 'actual': actual, 'error': error,
                                     'forbidden': list(forbidden), 'incomplete': incomplete})
    return {'fixtures': len(documents), 'cases': checked, 'failures': failures}


def proposal_path(root, directory):
    path = Path(directory).resolve()
    if not path.is_relative_to((root / 'datasources/imports').resolve()):
        raise ValueError('Prepared proposals belong under datasources/imports/')
    return path


def prepare(root, directory):
    directory = proposal_path(root, directory)
    if directory.exists():
        raise ValueError('Use a new proposal directory')
    documents = generate(root)
    previous = inventory(root)
    files, changes, patch = {}, {}, []
    directory.mkdir(parents=True)
    (directory / 'cases').mkdir()
    for name in sorted(previous.keys() | documents.keys()):
        before = (root / CORPUS / name).read_text() if name in previous else ''
        after = encode(documents[name]) if name in documents else ''
        if name in documents:
            path = directory / 'cases' / name
            path.write_text(after, encoding='utf-8')
            files[name] = checksum(path)
        if before != after:
            changes[name] = 'added' if not before else 'removed' if not after else 'changed'
            patch.extend(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                             fromfile=str(CORPUS / name), tofile=str(CORPUS / name)))
    pins = {key: value for document in documents.values() for key, value in document['sourceInputs'].items()}
    manifest = {'previous': previous, 'files': files, 'sourceInputs': pins,
                'changes': changes, 'cases': sum(document['caseCount'] for document in documents.values())}
    (directory / 'manifest.json').write_text(encode(manifest), encoding='utf-8')
    (directory / 'diff.patch').write_text(''.join(patch), encoding='utf-8')
    return {'changedFixtures': len(changes), 'cases': manifest['cases'], 'proposal': str(directory)}


def apply(root, directory):
    directory = proposal_path(root, directory)
    manifest = read(directory / 'manifest.json')
    documents = validate(root, directory / 'cases')
    expected = {name: checksum(directory / 'cases' / name) for name in documents}
    if manifest['files'] != expected:
        raise ValueError('Prepared regression files changed; prepare again')
    pins = {key: value for document in documents.values() for key, value in document['sourceInputs'].items()}
    if manifest['sourceInputs'] != pins:
        raise ValueError('Prepared source inventory changed; prepare again')
    if inventory(root) != manifest['previous']:
        raise ValueError('Versioned regression files changed since preparation')
    # Preflight every input and existing fixture before the first write.
    for name in sorted(manifest['previous'].keys() | documents.keys()):
        path = root / CORPUS / name
        if name in documents:
            text = (directory / 'cases' / name).read_text(encoding='utf-8')
            if path.exists() and path.read_text(encoding='utf-8') == text:
                continue
            temporary = path.with_suffix('.json.tmp')
            temporary.write_text(text, encoding='utf-8')
            temporary.replace(path)
        else:
            path.unlink()
    return {'fixtures': len(documents), 'cases': sum(document['caseCount'] for document in documents.values())}


def main():
    from live_spell_fixture import FixtureUnavailable
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('status')
    check = commands.add_parser('check')
    check.add_argument('--directory', type=Path, help='Prepared cases directory, for validation before apply')
    for name in ('prepare', 'apply'):
        command = commands.add_parser(name)
        command.add_argument('--directory', type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == 'status':
            result = {'fixtures': len(validate()), 'status': 'current'}
        elif args.command == 'check':
            result = replay(directory=args.directory)
        else:
            result = (prepare if args.command == 'prepare' else apply)(ROOT, args.directory)
    except (ValueError, KeyError, OSError, FixtureUnavailable) as error:
        parser.exit(1, str(error) + '\n')
    print(encode(result), end='')
    return 1 if result.get('failures') else 0


if __name__ == '__main__':
    sys.exit(main())
