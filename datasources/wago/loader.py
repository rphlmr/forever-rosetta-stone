"""Fetch, validate, audit and compare Wago client-table snapshots."""

import argparse
from collections import Counter
import csv
import hashlib
import io
import json
import re
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


BASELINE_BUILD = '1.60.1.70888'
USER_AGENT = (
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
)
LOCALES = ('enUS', 'deDE', 'esES', 'esMX', 'frFR', 'itIT', 'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW')
DEFAULT_TABLES = (
    'GlobalStrings', 'Talent', 'Item', 'ItemSparse', 'ItemClass', 'ItemSubClass',
    'ItemEffect', 'ItemXItemEffect', 'ItemSet', 'ItemSetSpell', 'ItemNameDescription',
    'ItemLimitCategory',
    'Spell', 'SpellName', 'SpellEffect', 'SpellMisc', 'SpellDuration',
    'SpellRange', 'SpellDescriptionVariables',
    'SpellXDescriptionVariables', 'SpellLevels', 'SpellRadius', 'SpellAuraOptions',
    'SpellItemEnchantment', 'SpellTargetRestrictions',
    'TraitDefinition', 'TraitDefinitionEffectPoints', 'CurvePoint',
    'TraitNodeEntry', 'TraitNodeXTraitNodeEntry', 'TraitNode',
)
SUPPORTED_TABLES = DEFAULT_TABLES + ('AreaTable', 'UiMap', 'Faction', 'FactionTemplate', 'CreatureType', 'ChrClasses', 'ChrRaces',
                                   'SpellClassOptions', 'SpellTotems', 'TotemCategory', 'TradeSkillCategory', 'GroupFinderActivity',
                                   'SpellShapeshift', 'SpellShapeshiftForm', 'SpellEquippedItems', 'SpellReagents', 'Holidays',
                                   'HolidayNames', 'Lock', 'LockType', 'Map', 'TraitCond', 'SharedString',
                                   'TraitNodeGroupXTraitNode', 'TraitNodeGroupXTraitCond', 'TaxiNodes', 'ItemSubClassMask')


def parse_version(version):
    if not isinstance(version, str) or not re.fullmatch(r'\d+\.\d+\.\d+\.\d+', version):
        raise ValueError(f'Expected a full build version, received {version!r}')

    return tuple(map(int, version.split('.')))


def get_published_builds(fetch=urlopen):
    """Return numeric-sorted Forever builds, excluding background downloads; fail on unknown responses."""
    request = Request('https://wago.tools/api/builds', headers={'User-Agent': USER_AGENT})

    with fetch(request, timeout=30) as response:
        products = json.load(response)

    if not isinstance(products, dict) or not isinstance(products.get('wowf'), list) or not products['wowf']:
        raise ValueError('Build response has no wowf build list; cannot establish update status')

    builds = set()

    for entry in products['wowf']:
        if not isinstance(entry, dict) or entry.get('product') != 'wowf' or type(entry.get('is_bgdl')) is not bool:
            raise ValueError('Unexpected wowf build record; cannot establish update status')

        parse_version(entry.get('version'))

        if not entry['is_bgdl']:
            builds.add(entry['version'])

    if not builds:
        raise ValueError('No published wowf builds in response')

    return sorted(builds, key=parse_version)


def is_localized_table(table, columns):
    return table != 'Talent' and any(column.endswith('_lang') for column in columns)


def validate_csv(content, table):
    """Reject error pages and duplicate or malformed record IDs; empty tables are valid."""
    reader = csv.DictReader(io.StringIO(content.decode('utf-8-sig'), newline=''))
    required = {'ID'}

    if table == 'Spell':
        required.add('Description_lang')
    elif table == 'SpellName':
        required.add('Name_lang')

    if not required.issubset(reader.fieldnames or []) or len(set(reader.fieldnames)) != len(reader.fieldnames):
        raise ValueError(f'{table}: expected columns {sorted(required)}, received {reader.fieldnames}')

    ids = set()

    for row in reader:
        record_id = row.get('ID', '')

        if None in row or any(value is None for value in row.values()):
            raise ValueError(f'{table}: malformed CSV row for ID {record_id}')

        if not record_id.isdecimal() or record_id in ids:
            raise ValueError(f'{table}: invalid or duplicate ID {record_id!r}')

        ids.add(record_id)

    return len(ids)


def write_atomic(path, content):
    """Publish a complete file without leaving a partial destination on failure."""
    temporary = None

    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(content)

        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def download_tables(build, output, tables, locales, fetch=urlopen):
    output.mkdir(parents=True, exist_ok=True)
    results = []
    failed = False
    stopped = False

    for table in tables:
        localized = False

        for locale in dict.fromkeys(('enUS', *locales)):
            if locale != 'enUS' and not localized:
                continue

            url = f'https://wago.tools/db2/{table}/csv?' + urlencode({'build': build, 'locale': locale})
            destination = output / f'{table}.{build}.{locale}.csv'
            result = {'table': table, 'locale': locale, 'url': url, 'file': destination.name}

            try:
                if destination.exists():
                    content = destination.read_bytes()
                    status = 'existing'
                else:
                    request = Request(url, headers={'User-Agent': USER_AGENT})

                    with fetch(request, timeout=30) as response:
                        content = response.read()

                    status = 'downloaded'

                count = validate_csv(content, table)
                columns = next(csv.reader(io.StringIO(content.decode('utf-8-sig'))))

                if locale == 'enUS':
                    localized = is_localized_table(table, columns)

                if status == 'downloaded':
                    write_atomic(destination, content)

                result.update(status=status, rows=count, localized=localized,
                              sha256=hashlib.sha256(content).hexdigest())
                print(f'{table} {locale}: {status}, {count:,} records', flush=True)
            except (HTTPError, URLError, OSError, ValueError, csv.Error) as error:
                failed = True
                result.update(status='failed', error=str(error))
                print(f'{table} {locale}: {error}', file=sys.stderr, flush=True)

                if isinstance(error, HTTPError) and error.code in (401, 403, 429):
                    stopped = True
                    print('Stopping: access denied or rate limited. No automatic retries.', file=sys.stderr)

            results.append(result)

            if stopped:
                break

        if stopped:
            break

    manifest = {
        'build': build,
        'capturedAt': datetime.now(timezone.utc).isoformat(),
        'requestedTables': list(tables),
        'requestedLocales': list(locales),
        'complete': not failed,
        'stoppedEarly': stopped,
        'results': results,
    }
    write_atomic(output / 'manifest.json', (json.dumps(manifest, indent=2) + '\n').encode())
    return 1 if failed else 0


def fetch(output, build=None, tables=None, locales=None):
    """Fetch the full catalog profile for the shared datasource refresh."""
    build = build or get_published_builds()[-1]
    if download_tables(build, output, tables or SUPPORTED_TABLES, locales or LOCALES):
        raise RuntimeError('Wago download incomplete; SQLite was not built')
    return build


def check_updates(baseline, fetch=urlopen):
    baseline_version = parse_version(baseline)
    ordered = get_published_builds(fetch)
    return {
        'product': 'wowf', 'baseline': baseline, 'latest': ordered[-1],
        'newerBuilds': [build for build in ordered if parse_version(build) > baseline_version],
    }


def load_snapshot(directory):
    """Validate manifest completeness and hashes before interpreting any CSV records."""
    manifest = json.loads((directory / 'manifest.json').read_text())
    parse_version(manifest['build'])

    if manifest.get('complete') is not True or manifest.get('stoppedEarly') is not False:
        raise ValueError(f'{directory}: snapshot is incomplete; rerun the downloader')

    exports = {}

    for entry in manifest['results']:
        key = (entry['table'], entry['locale'])
        filename = f'{key[0]}.{manifest["build"]}.{key[1]}.csv'

        if (entry['file'] != filename or Path(filename).name != filename or key in exports
                or entry['status'] not in ('downloaded', 'existing')):
            raise ValueError(f'{directory}: invalid or duplicate export {key}')

        content = (directory / filename).read_bytes()

        if hashlib.sha256(content).hexdigest() != entry['sha256']:
            raise ValueError(f'{filename}: hash mismatch; restore or re-export the snapshot')

        if validate_csv(content, key[0]) != entry['rows']:
            raise ValueError(f'{filename}: manifest row count mismatch')

        reader = csv.DictReader(io.StringIO(content.decode('utf-8-sig'), newline=''))
        exports[key] = {'columns': reader.fieldnames, 'rows': {row['ID']: row for row in reader}}

    expected = set()

    for table in manifest['requestedTables']:
        english = exports.get((table, 'enUS'))

        if english is None:
            raise ValueError(f'{directory}: missing English export for {table}')

        localized = is_localized_table(table, english['columns'])
        locales = {'enUS', *manifest['requestedLocales']} if localized else {'enUS'}
        expected.update((table, locale) for locale in locales)

    if not expected or set(exports) != expected:
        raise ValueError(f'{directory}: manifest exports do not match its requested tables/locales')

    return {'build': manifest['build'], 'exports': exports}


def compare_snapshots(before, after):
    if before['exports'].keys() != after['exports'].keys():
        raise ValueError('Snapshot profiles differ. Re-export both builds with the same tables and locales.')

    differences = []

    for key, old in sorted(before['exports'].items()):
        new = after['exports'][key]
        old_ids, new_ids = set(old['rows']), set(new['rows'])
        fields = sorted(set(old['columns']) & set(new['columns']) - {'ID'})
        changes = []

        for record_id in sorted(old_ids & new_ids, key=int):
            for field in fields:
                previous, current = old['rows'][record_id][field], new['rows'][record_id][field]

                if previous != current:
                    changes.append({'id': record_id, 'field': field, 'before': previous, 'after': current})

        added_fields = sorted(set(new['columns']) - set(old['columns']))
        removed_fields = sorted(set(old['columns']) - set(new['columns']))

        if changes or old_ids != new_ids or added_fields or removed_fields:
            differences.append({
                'table': key[0], 'locale': key[1],
                'addedIds': sorted(new_ids - old_ids, key=int),
                'removedIds': sorted(old_ids - new_ids, key=int),
                'addedFields': added_fields, 'removedFields': removed_fields, 'changes': changes,
            })

    stale = []

    for difference in differences:
        if difference['locale'] != 'enUS':
            continue

        for change in difference['changes']:
            if not change['field'].endswith('_lang'):
                continue

            for key, new in after['exports'].items():
                if key[0] != difference['table'] or key[1] == 'enUS':
                    continue

                old_row = before['exports'][key]['rows'].get(change['id'], {})
                new_row = new['rows'].get(change['id'], {})
                value = new_row.get(change['field'])

                if value and value == old_row.get(change['field']):
                    stale.append({'table': key[0], 'locale': key[1], 'id': change['id'], 'field': change['field']})

    return {'before': before['build'], 'after': after['build'], 'differences': differences,
            'unchangedTranslationAfterEnglishEdit': stale}


# Recognized numeric/reference tokens only; grammar/plural words are intentionally excluded.
TOKENS = re.compile(r'\$(?:@(?:spellname|spelldesc|spellaura|spelltooltip)\d+|<[^>]+>|'
                    r'(?:\d+)?[sSmMoOtTaAbBewWxX]\d+|(?:\d+)?[dDuUnNhHiIrR](?![\w]))')


def audit_translations(snapshot):
    findings = []

    for (table, locale), export in sorted(snapshot['exports'].items()):
        if locale == 'enUS':
            continue

        english = snapshot['exports'][(table, 'enUS')]
        fields = [field for field in english['columns'] if field.endswith('_lang')]

        for record_id, source in english['rows'].items():
            translated = export['rows'].get(record_id)

            if translated is None:
                findings.append({'table': table, 'locale': locale, 'id': record_id, 'kind': 'missingId'})
                continue

            for field in fields:
                value = translated.get(field, '')

                if not source[field].strip():
                    continue

                kind = None

                if not value.strip():
                    kind = 'missingText'
                elif value == source[field]:
                    kind = 'possibleEnglishFallback'
                elif Counter(TOKENS.findall(value)) != Counter(TOKENS.findall(source[field])):
                    kind = 'placeholderReview'

                if kind:
                    findings.append({'table': table, 'locale': locale, 'id': record_id,
                                     'field': field, 'kind': kind})

    return {'counts': dict(Counter(finding['kind'] for finding in findings)), 'findings': findings}


# Explicit content joins, not every foreign key in the client database.
JOINS = (
    ('ItemSparse', 'ItemSet', 'ItemSet'),
    ('ItemSparse', 'ItemNameDescriptionID', 'ItemNameDescription'),
    ('ItemSparse', 'LimitCategory', 'ItemLimitCategory'),
    ('ItemXItemEffect', 'ItemEffectID', 'ItemEffect'),
    ('ItemEffect', 'SpellID', 'Spell'),
    ('ItemSetSpell', 'ItemSetID', 'ItemSet'),
    ('ItemSetSpell', 'SpellID', 'Spell'),
    ('SpellMisc', 'DurationIndex', 'SpellDuration'),
    ('SpellMisc', 'RangeIndex', 'SpellRange'),
    ('SpellEffect', 'EffectRadiusIndex_0', 'SpellRadius'),
    ('SpellEffect', 'EffectRadiusIndex_1', 'SpellRadius'),
    ('SpellXDescriptionVariables', 'SpellDescriptionVariablesID', 'SpellDescriptionVariables'),
    ('TraitDefinition', 'SpellID', 'Spell'),
    ('TraitNodeEntry', 'TraitDefinitionID', 'TraitDefinition'),
    ('TraitDefinitionEffectPoints', 'TraitDefinitionID', 'TraitDefinition'),
    ('TraitNodeXTraitNodeEntry', 'TraitNodeEntryID', 'TraitNodeEntry'),
    ('TraitNodeXTraitNodeEntry', 'TraitNodeID', 'TraitNode'),
)


def audit_dependencies(snapshot):
    exports = snapshot['exports']
    missing_tables = sorted(set(DEFAULT_TABLES) - {table for table, locale in exports if locale == 'enUS'})
    joins = []

    for source, field, target in JOINS:
        if (source, 'enUS') not in exports or (target, 'enUS') not in exports:
            continue

        source_export = exports[(source, 'enUS')]

        if field not in source_export['columns']:
            raise ValueError(f'{source}: dependency column {field} disappeared; review the new schema')

        references = {row[field] for row in source_export['rows'].values()} - {'', '0'}
        missing = references - exports[(target, 'enUS')]['rows'].keys()
        joins.append({'source': source, 'field': field, 'target': target,
                      'referencedIds': len(references), 'missingIds': sorted(missing, key=int)})

    overrides = exports.get(('TraitDefinitionEffectPoints', 'enUS'))
    points = exports.get(('CurvePoint', 'enUS'))

    if overrides and points:
        references = {row['CurveID'] for row in overrides['rows'].values()} - {'', '0'}
        curves = {row['CurveID'] for row in points['rows'].values()}
        joins.append({'source': 'TraitDefinitionEffectPoints', 'field': 'CurveID',
                      'target': 'CurvePoint.CurveID', 'referencedIds': len(references),
                      'missingIds': sorted(references - curves, key=int)})

    templates = []
    missing_spell_references = []
    spell_export = exports.get(('Spell', 'enUS'), {'rows': {}})

    for record_id, row in spell_export['rows'].items():
        for field in ('Description_lang', 'AuraDescription_lang'):
            value = row.get(field, '')

            if '$' in value:
                templates.append({'id': record_id, 'field': field})

            references = re.findall(r'\$@(?:spellname|spelldesc|spellaura|spelltooltip)(\d+)', value)
            references += re.findall(r'\$(\d+)[sSmMoOtTaAbBewWxXdDuUnNhHiIrR](?:\d*\b)', value)

            for target in sorted(set(references), key=int):
                if target not in spell_export['rows']:
                    missing_spell_references.append({'id': record_id, 'field': field, 'targetSpellId': target})

    return {'missingProfileTables': missing_tables, 'joins': joins,
            'missingReferencedSpells': missing_spell_references,
            'templatesRequiringRenderer': templates,
            'limit': 'Content joins are checked. This is not a complete template parser or runtime renderer.'}


def write_report(output, report):
    output.mkdir(parents=True, exist_ok=True)
    write_atomic(output / 'report.json', (json.dumps(report, ensure_ascii=False, indent=2) + '\n').encode())
    lines = ['# Wago reference report', '']

    if 'differences' in report:
        lines += [f"Builds: {report['before']} → {report['after']}",
                  f"Changed exports: {len(report['differences'])}",
                  f"Translations to recheck after English edits: {len(report['unchangedTranslationAfterEnglishEdit'])}", '',
                  '| Table | Locale | Added IDs | Removed IDs | Changed cells | Schema changes |',
                  '| --- | --- | ---: | ---: | ---: | ---: |']

        for change in report['differences']:
            lines.append(f"| {change['table']} | {change['locale']} | {len(change['addedIds'])} | "
                         f"{len(change['removedIds'])} | {len(change['changes'])} | "
                         f"{len(change['addedFields']) + len(change['removedFields'])} |")
    else:
        lines += [f"Build: {report['build']}", '', '## Translation review candidates', '']
        lines += [f'- {kind}: {count}' for kind, count in report['translations']['counts'].items()]
        lines += ['', 'Equality with English can be legitimate. Placeholder differences need human review.', '',
                  '## Content dependencies', '',
                  f"Missing profile tables: {', '.join(report['dependencies']['missingProfileTables']) or 'none'}"]

        for join in report['dependencies']['joins']:
            lines.append(f"- {join['source']}.{join['field']} → {join['target']}: "
                         f"{join['referencedIds']} referenced IDs, {len(join['missingIds'])} absent")

        lines += [f"- Missing explicit template spell references: "
                  f"{len(report['dependencies']['missingReferencedSpells'])}",
                  '', report['dependencies']['limit']]

    lines += ['', 'Full IDs, fields and review candidates: [report.json](report.json)', '',
              'Catalogs are unchanged. Review before any manual catalog update.', '']
    write_atomic(output / 'report.md', '\n'.join(lines).encode())



def download(args, parser):
    if args.build is not None and not re.fullmatch(r'\d+\.\d+\.\d+\.\d+', args.build):
        parser.error('--build must be a full version, such as 1.60.1.70862')

    try:
        build = args.build if args.build is not None else get_published_builds()[-1]
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.exit(1, f'Cannot discover latest Forever build: {error}\n')

    print(f'Forever reference build: {build}', flush=True)
    output = args.output or Path(__file__).resolve().parents[2] / 'datasources/imports' / 'wago' / build
    tables = args.tables or DEFAULT_TABLES
    return download_tables(build, output, tuple(dict.fromkeys(tables)), tuple(dict.fromkeys(args.locales)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    download_parser = commands.add_parser('download', help='Fetch selected client tables without editing catalogs')
    download_parser.add_argument('--build', help='Pin a full version; default: latest published Forever build')
    download_parser.add_argument('--output', type=Path, help='Default: <project>/datasources/imports/wago/<build>')
    download_parser.add_argument('--tables', nargs='+', choices=SUPPORTED_TABLES)
    download_parser.add_argument('--locales', nargs='+', choices=LOCALES, default=LOCALES)
    check = commands.add_parser('check', help='Query published Forever builds; download nothing')
    check.add_argument('--baseline', default=BASELINE_BUILD)
    audit = commands.add_parser('audit', help='Check content joins and translation review candidates')
    audit.add_argument('snapshot', type=Path)
    audit.add_argument('--output', type=Path, required=True)
    diff = commands.add_parser('diff', help='Compare snapshots by record ID and column')
    diff.add_argument('before', type=Path)
    diff.add_argument('after', type=Path)
    diff.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()

    if args.command == 'download':
        return download(args, parser)

    try:
        if args.command == 'check':
            print(json.dumps(check_updates(args.baseline), indent=2))
            return 0

        if args.command == 'diff':
            report = compare_snapshots(load_snapshot(args.before), load_snapshot(args.after))
        else:
            snapshot = load_snapshot(args.snapshot)
            report = {'build': snapshot['build'], 'translations': audit_translations(snapshot),
                      'dependencies': audit_dependencies(snapshot)}

        write_report(args.output, report)
        print(f'Report: {args.output / "report.md"}')
        return 0
    except (OSError, ValueError, KeyError, TypeError, csv.Error) as error:
        parser.exit(1, f'Wago check failed: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
