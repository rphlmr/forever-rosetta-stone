"""Prepare, apply and verify deterministic source updates under the translation policy."""

import argparse
import collections
import copy
import hashlib
import json
import runpy
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from datasources.corpus.translation_corpus import open_corpus
from tools.catalogs.catalog_storage import KINDS, dump_json, get_entity_path, load_catalog, load_catalogs, read_json
from tools.catalogs.import_policy import (OfficialEvidence, english_source, filter_queue, metadata, normalize,
                                         set_field, text_fields, verify_sources)
from tools.catalogs.official_text import OFFICIAL_LOCALES, newer_core_source
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES

FILL = runpy.run_path(str(ROOT / 'tools/catalogs/fill-official-text.py'))
PLAN = runpy.run_path(str(ROOT / 'tools/catalogs/plan-update.py'))
WORK = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify_policy_inputs(root, manifest):
    for relative, checksum in manifest.get('policyInputs', {}).items():
        path = (Path(root) / relative).resolve()
        if not path.is_relative_to(Path(root).resolve()) or digest(path.read_bytes()) != checksum:
            raise ValueError('Policy source changed: ' + relative)


def reconcile_official_targets(entity, affected_fields, locales):
    """Copy available English source, without generating or relabeling authored text."""
    result = copy.deepcopy(entity)
    counts = collections.Counter()
    unresolved = []
    english_fields = text_fields(entity['locales'].get('enUS', {}))
    for locale in sorted(set(locales) & (OFFICIAL_LOCALES - {'enUS'})):
        record = result['locales'].get(locale, {})
        current = text_fields(record)
        for field in sorted(affected_fields):
            origin = metadata(record, field).get('origin')
            missing = field not in current or (current[field] == '' and origin == 'ai')
            if not missing:
                if origin == 'ai' and english_source(entity, field)[0] is None:
                    unresolved.append({'locale': locale, 'field': field, 'reason': 'missingOwnedEnglishSource'})
                continue
            source, source_metadata = english_source(entity, field)
            if missing and field not in english_fields and source is None:
                # Upstream-only fields do not create catalog coverage obligations.
                continue
            if source is None or not source_metadata:
                unresolved.append({'locale': locale, 'field': field, 'reason': 'missingOwnedEnglishSource'})
                continue
            if missing and field.startswith('objectiveLines.'):
                # A source string does not authorize inventing a client objective binding.
                continue
            if current.get(field) == source and metadata(record, field) == source_metadata:
                continue
            record = result['locales'].setdefault(locale, {})
            set_field(record, field, source, source_metadata)
            counts['officialEnglishFallback'] += 1
            if source_metadata.get('origin') == 'ai':
                counts['fallbackRetainsEnglishSourceAIProvenance'] += 1
    return result, counts, unresolved


def select_scope(plan, source_db):
    scope, held = set(), []
    for row in plan['changes']:
        if row['status'] not in ('added', 'changed', 'contextChanged', 'originChanged', 'flagsChanged'):
            if row['status'] == 'conflict':
                held.append(row)
            continue
        valid = [r for r in row['newCandidates'] if r['origin'] in ('original', 'community') and
                 (not r['flags'] or r['origin'] == 'original' and all(
                     flag == 'equalsEnglish:inspectBeforeReuse' or flag.startswith('sharedProseAcrossLanguages:')
                     for flag in r['flags']))]
        owned = row.get('ownedMetadata') or {}
        source_fallback = (row['locale'] in OFFICIAL_LOCALES - {'enUS'} and
                           owned.get('sourceLocale') == 'enUS' and len(valid) == 1 and
                           valid[0]['english'] is not None and
                           row.get('ownedTextSha256') == PLAN['text_hash'](valid[0]['english']))
        newer_provider = False
        if len(valid) == 1 and row['manualOrOwnedConflict'] and owned.get('origin') in ('original', 'community'):
            for candidate in source_db.execute(
                    "SELECT text,english,origin,provenance FROM records WHERE evidence='sourceSnapshot' "
                    "AND kind=? AND entity_id=? AND locale=? AND field=?",
                    (row['kind'], row['id'], row['locale'], row['field'])):
                provenance = json.loads(candidate['provenance'])
                if (provenance.get('source') == row['provider'] and
                        all(candidate[key] == valid[0][key] for key in ('text', 'english', 'origin')) and
                        newer_core_source(provenance, owned)):
                    newer_provider = True
                    break
        if len(valid) != 1 or (row['manualOrOwnedConflict'] and owned.get('origin') != 'ai'
                               and not source_fallback and not newer_provider):
            held.append(row)
            continue
        scope.add((row['kind'], row['id'], row['locale'], row['field'], row['provider']))
    return scope, held


def prepare(root, database, previous, output):
    root, output = Path(root).resolve(), Path(output).resolve()
    if not output.is_relative_to(root / 'datasources/imports') or output.exists():
        raise ValueError('Use a new output directory under datasources/imports/')
    database = verify_sources(database, root)
    output.mkdir(parents=True)
    plan = PLAN['plan'](root, previous, database)
    source_db = open_corpus(database)
    try:
        scope, held = select_scope(plan, source_db)
    finally:
        source_db.close()
    (output / 'held-source-conflicts.json').write_text(dump_json(held))
    (output / 'new-entity-candidates.json').write_text(dump_json(plan['newEntityCandidates']))
    affected_by_entity = collections.defaultdict(set)
    for row in plan['changes']:
        if row['oldCandidates'] != row['newCandidates']:
            affected_by_entity[(row['kind'], row['id'])].add(row['field'])
    for kind, entity_id, locale, field, provider in scope:
        affected_by_entity[(kind, entity_id)].add(field)
    evidence = OfficialEvidence(database, root) if affected_by_entity else None
    locales = read_json(root / 'catalogs/quests/metadata.json')['document']['locales']
    from tools.build.client_label_scope import tooltip_globalstring_keys
    label_directory = root / 'catalogs/globalstrings'
    labels = (load_catalog(root, 'globalstrings')['catalogs']['globalstrings']
              if any(kind == 'globalstrings' for kind, _ in affected_by_entity)
              and (label_directory / 'metadata.json').exists() else {})
    label_keys = tooltip_globalstring_keys(root, {r['key'] for r in labels.values()}) if labels else set()
    db = open_corpus(database)
    files, changes, unresolved = [], [], []
    totals = collections.Counter()
    translation_scope = collections.defaultdict(set)
    try:
        for kind in sorted(KINDS):
            ids = sorted(entity_id for entity_kind, entity_id in affected_by_entity if entity_kind == kind)
            for entity_id in ids:
                path = get_entity_path(root, kind, entity_id)
                if not path.is_file():
                    continue
                key = (kind, entity_id)
                candidates = list(FILL['source_rows'](db, entity=key))
                raw = path.read_bytes()
                before = json.loads(raw)
                if kind == 'globalstrings' and before.get('key') not in label_keys:
                    totals['unusedGlobalStringsSkipped'] += 1
                    continue
                after = copy.deepcopy(before)
                counts = collections.Counter()
                selected = [row for row in candidates if
                            (*key, row['locale'], row['field'], json.loads(row['provenance']).get('source')) in scope]
                selected_fields = {(row['locale'], row['field']) for row in selected}
                # Compare every applicable provider for an affected localized field.
                selected = [row for row in candidates if (row['locale'], row['field']) in selected_fields]
                new_english = {row['field'] for row in selected if row['locale'] == 'enUS'
                               and normalize(row['text']) != normalize(text_fields(after['locales'].get('enUS', {})).get(row['field']))}
                if new_english:
                    selected = [row for row in candidates if row in selected or row['field'] in new_english]
                if kind == 'quests' and before.get('usageStatus') in EXCLUDED_QUEST_STATUSES:
                    selected = []
                after, source_counts = FILL['update_entity'](after, selected, update_english=True)
                counts.update(source_counts)
                affected = affected_by_entity[key]
                after, policy_counts, issues = reconcile_official_targets(after, affected, locales)
                counts.update(policy_counts)
                totals.update(counts)
                unresolved.extend({'kind': kind, 'id': path.stem, **issue} for issue in issues)
                if before == after:
                    continue
                replacement = dump_json(after)
                name = f'{len(files):05d}'
                (output / (name + '.patch')).write_text('*** Begin Patch\n' +
                    FILL['patch_text'](path.relative_to(root), raw.decode(), replacement) + '*** End Patch\n')
                (output / (name + '.json')).write_text(replacement)
                files.append({'path': str(path.relative_to(root)), 'result': name + '.json',
                              'beforeSha256': digest(raw), 'afterSha256': digest(replacement.encode())})
                translation_scope[kind].add(path.stem)
                for locale in set(before['locales']) | set(after['locales']):
                    old, new = before['locales'].get(locale, {}), after['locales'].get(locale, {})
                    for field in set(text_fields(old)) | set(text_fields(new)):
                        a, b = text_fields(old).get(field), text_fields(new).get(field)
                        if (a, metadata(old, field)) != (b, metadata(new, field)):
                            changes.append({'kind': kind, 'id': path.stem, 'locale': locale, 'field': field,
                                            'before': a, 'after': b, 'metadata': metadata(new, field)})
    finally:
        db.close()
    manifest = {'database': str(database), 'databaseSha256': PLAN['file_sha'](database),
                'counts': dict(totals), 'files': files,
                'heldConflicts': len(held), 'newEntities': len(plan['newEntityCandidates']),
                'unresolvedFields': len(unresolved), 'changedFields': len(changes)}
    manifest['policyInputs'] = evidence.extra_inputs if evidence else {}
    manifest['tooltipGlobalStringKeys'] = len(label_keys)
    (output / 'changes.json').write_text(dump_json(changes))
    (output / 'unresolved.json').write_text(dump_json(unresolved))
    (output / 'translation-scope.json').write_text(dump_json({k: sorted(v) for k, v in translation_scope.items()}))
    (output / 'manifest.json').write_text(dump_json(manifest))
    return {k: v for k, v in manifest.items() if k != 'files'} | {'changedFiles': len(files)}


def verify_prepared_sources(root, manifest):
    verify_policy_inputs(root, manifest)
    if manifest.get('sourceType') == 'questDialogue' and manifest.get('policyInputs'):
        return
    database = verify_sources(manifest['database'], root)
    if PLAN['file_sha'](database) != manifest['databaseSha256']:
        raise ValueError('Source database changed since preparation')


def apply(root, directory):
    root, directory = Path(root).resolve(), Path(directory).resolve()
    manifest = read_json(directory / 'manifest.json')
    if manifest.get('unresolvedFields', 0):
        raise ValueError('Prepared source issues must be resolved before application')
    verify_prepared_sources(root, manifest)
    # Check every file before the first write; a conflict must not cause a partial application.
    pending = []
    for row in manifest['files']:
        path = (root / row['path']).resolve()
        if not path.is_relative_to(root / 'catalogs'):
            raise ValueError('Unsafe catalog destination')
        raw = (directory / row['result']).read_bytes()
        if digest(raw) != row['afterSha256']:
            raise ValueError('Prepared result changed: ' + row['path'])
        current = digest(path.read_bytes()) if path.exists() else None
        if current not in (row['beforeSha256'], row['afterSha256']):
            raise ValueError('Concurrent catalog edit: ' + row['path'])
        if current != row['afterSha256']:
            pending.append((path, raw))
    for path, raw in pending:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(raw)
    return {'writtenFiles': len(pending), 'verifiedFiles': len(manifest['files'])}


def verify(root, directory):
    manifest = read_json(Path(directory) / 'manifest.json')
    verify_prepared_sources(root, manifest)
    for row in manifest['files']:
        if digest((Path(root) / row['path']).read_bytes()) != row['afterSha256']:
            raise ValueError('Applied result mismatch: ' + row['path'])
    return {'verifiedFiles': len(manifest['files'])}


def queue(root, directory, output=None):
    directory = Path(directory)
    manifest = read_json(directory / 'manifest.json')
    if manifest.get('sourceType') == 'questDialogue':
        from tools.catalogs.dialogue_jobs import queue as queue_dialogue
        verify_prepared_sources(root, manifest)
        return queue_dialogue(root, output or directory, manifest)
    if output is not None:
        raise ValueError('An explicit queue output is supported only for quest dialogue')
    verify(root, directory)
    documents = load_catalogs(root, read_json(directory / 'translation-scope.json'))
    candidates = WORK['collect_translation_candidates'](documents)
    if manifest.get('scope') != 'book-texts':
        affected = {(row['kind'], row['id'], row['field']) for row in read_json(directory / 'changes.json')}
        jobs = []
        for job in candidates['jobs']:
            selected = []
            for pointer in job['pointers']:
                field = pointer['field'].removeprefix('tooltip.')
                field = 'setName' if field == 'set.name' else field
                if field == 'objectiveLines':
                    field += '.' + str(pointer['index'])
                if (pointer['kind'], pointer['id'], field) in affected:
                    selected.append(pointer)
            if selected:
                jobs.append({**job, 'pointers': selected})
        candidates['jobs'] = jobs
    result = filter_queue(candidates, OfficialEvidence(manifest['database'], root),
                          documents['quests']['catalogs']['quests'])
    (directory / 'translation-queue.json').write_text(dump_json(result))
    return {'eligibleJobs': len(result['jobs']), 'blockedJobs': len(result['blocked'])}


def install(root, directory, addons, runtime_files=()):
    """Copy verified generated packs plus explicitly selected, manifest-owned runtime files."""
    root, directory, addons = Path(root).resolve(), Path(directory).resolve(), Path(addons).resolve()
    verify(root, directory)
    addon = root / 'ForeverRosettaStone'
    manifest = addon / 'ForeverRosettaStone.toc'
    entries = {line.strip() for line in manifest.read_text().splitlines() if line and not line.startswith('#')}
    copies = [(manifest, addons / addon.name / manifest.name)]
    for relative in runtime_files:
        source = (addon / relative).resolve()
        if not source.is_relative_to(addon) or relative not in entries:
            raise ValueError('Runtime file is outside the shipping manifest: ' + relative)
        copies.append((source, addons / addon.name / relative))
    for pack in sorted((root / 'ForeverRosettaStone_Data').iterdir()):
        if not pack.is_dir():
            continue
        tocs = list(pack.glob('*.toc'))
        if len(tocs) != 1:
            raise ValueError('Expected one manifest per generated pack')
        for source in pack.iterdir():
            if not source.is_file() or source.suffix not in ('.lua', '.toc'):
                raise ValueError('Unexpected generated pack file: ' + str(source))
            copies.append((source, addons / tocs[0].stem / source.name))
    for source, target in copies:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        if digest(source.read_bytes()) != digest(target.read_bytes()):
            raise ValueError('Installed file mismatch: ' + str(target))
    result = {'verifiedCopiedFiles': len(copies), 'runtimeFiles': list(runtime_files)}
    (directory / 'installed.json').write_text(dump_json(result))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    commands = parser.add_subparsers(dest='command', required=True)
    command = commands.add_parser('prepare-item-enchantments')
    command.add_argument('--database', type=Path, required=True)
    command.add_argument('--output', type=Path, required=True)
    command = commands.add_parser('prepare-books')
    command.add_argument('--database', type=Path, required=True)
    command.add_argument('--output', type=Path, required=True)
    command = commands.add_parser('prepare-quest-dialogue')
    command.add_argument('--audit', type=Path, required=True)
    command.add_argument('--snapshots', type=Path, required=True)
    command.add_argument('--output', type=Path, required=True)
    command = commands.add_parser('prepare')
    command.add_argument('--database', type=Path, required=True)
    command.add_argument('--previous', type=Path, help='Last applied corpus; omit for a first import without local history')
    command.add_argument('--output', type=Path, required=True)
    for name in ('apply', 'verify'):
        commands.add_parser(name).add_argument('--directory', type=Path, required=True)
    command = commands.add_parser('queue')
    command.add_argument('--directory', type=Path, required=True)
    command.add_argument('--output', type=Path)
    command = commands.add_parser('install')
    command.add_argument('--directory', type=Path, required=True)
    command.add_argument('--addons', type=Path, required=True)
    command.add_argument('--runtime-file', action='append', default=[])
    args = parser.parse_args()
    if args.command == 'prepare-item-enchantments':
        from datasources.wago.enchantments import prepare as prepare_enchantments
        result = prepare_enchantments(args.root, args.database, args.output)
    elif args.command == 'prepare-books':
        from datasources.books.catalogs import prepare as prepare_books
        result = prepare_books(args.root, args.database, args.output)
    elif args.command == 'prepare-quest-dialogue':
        from datasources.spoken.catalogs import prepare as prepare_dialogue
        result = prepare_dialogue(args.root, args.audit, args.snapshots, args.output)
    elif args.command == 'prepare':
        result = prepare(args.root, args.database, args.previous, args.output)
    elif args.command == 'install':
        result = install(args.root, args.directory, args.addons, args.runtime_file)
    elif args.command == 'queue':
        result = queue(args.root, args.directory, args.output)
    else:
        result = globals()[args.command](args.root, args.directory)
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
