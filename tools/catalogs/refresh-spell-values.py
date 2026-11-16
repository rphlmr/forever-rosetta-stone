"""Prepare reviewable numeric spell updates from hash-validated Wago snapshots; never edit catalogs."""

import argparse
import collections
import copy
import csv
import difflib
import hashlib
import io
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'datasources'))
from datasources.wago.loader import parse_version, validate_csv, write_atomic

TABLES = (
    'SpellEffect', 'SpellLevels', 'TraitDefinition', 'TraitDefinitionEffectPoints',
    'CurvePoint', 'TraitNodeEntry', 'TraitNodeXTraitNodeEntry', 'TraitNode',
)
TOOLTIP_TABLES = ('SpellEffect', 'SpellRadius', 'SpellMisc', 'SpellDuration')
SPELL_FIELD_TABLES = ('SpellMisc', 'SpellRange', 'SpellAuraOptions', 'SpellTargetRestrictions')
EFFECT_LEVEL_TABLES = TABLES
EFFECT_FIELDS = {
    'index': 'EffectIndex', 'effectType': 'Effect', 'auraType': 'EffectAura',
    'basePoints': 'EffectBasePointsF', 'perLevel': 'EffectRealPointsPerLevel',
    'variance': 'Variance', 'apCoefficient': 'BonusCoefficientFromAP',
    'bonusCoefficient': 'EffectBonusCoefficient', 'scalingClass': 'ScalingClass',
    'periodMs': 'EffectAuraPeriod', 'chainTargets': 'EffectChainTargets',
}


def number(row, field):
    value = float(row[field])

    if not math.isfinite(value):
        raise ValueError(f'Nonfinite {field} in row {row["ID"]}')

    return int(value) if value.is_integer() else value


def load_tables(directories, required=TABLES):
    """Read only required English tables, rejecting mixed builds or changed exports."""
    tables, build = {}, None

    for directory in directories:
        manifest = json.loads((directory / 'manifest.json').read_text())
        parse_version(manifest['build'])

        if not manifest['complete'] or manifest.get('stoppedEarly') is not False:
            raise ValueError(f'Incomplete snapshot: {directory}')

        if build is not None and build != manifest['build']:
            raise ValueError('Snapshots must use the same build')

        build = manifest['build']

        for entry in manifest['results']:
            table = entry['table']

            if table not in required or entry['locale'] != 'enUS':
                continue

            filename = f'{table}.{build}.enUS.csv'

            if entry['file'] != filename or entry['status'] not in ('downloaded', 'existing'):
                raise ValueError(f'Invalid export: {table}')

            content = (directory / filename).read_bytes()

            if hashlib.sha256(content).hexdigest() != entry['sha256']:
                raise ValueError(f'Hash mismatch: {filename}')

            if validate_csv(content, table) != entry['rows']:
                raise ValueError(f'Row count mismatch: {filename}')

            rows = list(csv.DictReader(io.StringIO(content.decode('utf-8-sig'), newline='')))

            if table in tables and tables[table] != rows:
                raise ValueError(f'Conflicting exports: {table}')

            tables[table] = rows

    missing = set(required) - tables.keys()

    if missing:
        raise ValueError('Missing tables: ' + ', '.join(sorted(missing)))

    return build, tables


def group(rows, key):
    grouped = collections.defaultdict(list)

    for row in rows:
        grouped[int(row[key])].append(row)

    return grouped


def index_traits(tables, build):
    definitions = {int(row['ID']): row for row in tables['TraitDefinition']}
    entries = group(tables['TraitNodeEntry'], 'TraitDefinitionID')
    links = group(tables['TraitNodeXTraitNodeEntry'], 'TraitNodeEntryID')
    nodes = {int(row['ID']) for row in tables['TraitNode']}
    curves = group(tables['CurvePoint'], 'CurveID')
    modifiers = collections.defaultdict(list)

    for override in tables['TraitDefinitionEffectPoints']:
        definition_id = int(override['TraitDefinitionID'])
        definition = definitions.get(definition_id)

        if definition is None:
            raise ValueError(f'Missing trait definition {definition_id}')

        candidates = entries[definition_id]
        modifier = {'error': 'Trait definition has multiple or missing entries'}

        if len(candidates) == 1:
            entry = candidates[0]
            node_links = links[int(entry['ID'])]

            if len(node_links) == 1 and int(node_links[0]['TraitNodeID']) in nodes:
                points = [
                    {'rank': number(point, 'Pos_0'), 'value': number(point, 'Pos_1')}
                    for point in curves[int(override['CurveID'])]
                ]
                ranks = [point['rank'] for point in points]
                expected = set(range(1, int(entry['MaxRanks']) + 1))

                if len(ranks) == len(set(ranks)) and expected.issubset(ranks):
                    modifier = {
                        'definitionID': definition_id, 'entryID': int(entry['ID']),
                        'nodeID': int(node_links[0]['TraitNodeID']),
                        'operationType': int(override['OperationType']),
                        'curveID': int(override['CurveID']),
                        'curvePoints': sorted(points, key=lambda point: point['rank']),
                        'sourceBuild': build,
                    }
                else:
                    modifier = {'error': 'Curve lacks unique values for every learned rank'}
            else:
                modifier = {'error': 'Trait entry has multiple or missing node links'}

        key = int(definition['SpellID']), int(override['EffectIndex'])
        modifiers[key].append(modifier)

    return modifiers


def refresh_entity(entity, spell_id, effects, levels, modifiers, replace_existing=False):
    """Refresh represented effect and level fields, preserving text and unrelated metadata."""
    rows = [row for row in effects.get(spell_id, []) if row['DifficultyID'] == '0']

    if not rows:
        raise ValueError('No default-difficulty SpellEffect rows; existing data preserved')

    if len({row['EffectIndex'] for row in rows}) != len(rows):
        raise ValueError('Duplicate default effect indices')

    result = copy.deepcopy(entity)
    tooltip = result.setdefault('tooltipData', {})
    old_effects = {effect['index']: effect for effect in tooltip.get('effects', [])}
    updated = []

    for row in sorted(rows, key=lambda row: int(row['EffectIndex'])):
        index = int(row['EffectIndex'])
        effect = copy.deepcopy(old_effects.get(index, {}))

        for field, column in EFFECT_FIELDS.items():
            value = number(row, column)

            if field in effect and effect[field] != value and not replace_existing:
                raise ValueError(f'Existing effect {index} {field} differs: {effect[field]} -> {value}; review required')

            if field in effect or value != 0 or field in ('index', 'basePoints', 'effectType', 'auraType'):
                effect[field] = value

        candidates = modifiers.get((spell_id, index), [])

        if len(candidates) > 1 or candidates and 'error' in candidates[0]:
            raise ValueError('Ambiguous trait override: ' + str(candidates))

        if candidates:
            effect['traitModifier'] = candidates[0]
        else:
            effect.pop('traitModifier', None)

        updated.append(effect)

    tooltip['effects'] = updated
    level_rows = [row for row in levels.get(spell_id, []) if row['DifficultyID'] == '0']

    if len(level_rows) > 1:
        raise ValueError('Ambiguous default SpellLevels rows')

    if level_rows:
        for field, column in (('baseLevel', 'BaseLevel'), ('spellLevel', 'SpellLevel'), ('maxLevel', 'MaxLevel')):
            value = number(level_rows[0], column)

            if field in tooltip and tooltip[field] != value and not replace_existing:
                raise ValueError(f'Existing {field} differs: {tooltip[field]} -> {value}; review required')

            tooltip[field] = value
    elif any(field in tooltip for field in ('baseLevel', 'spellLevel', 'maxLevel')):
        raise ValueError('Existing level data has no matching SpellLevels row; preserved for review')

    return result


def fill_missing_tooltip_values(entity, spell_id, effects, misc, radii, durations, provenance):
    result = copy.deepcopy(entity)
    tooltip = result.get('tooltipData', {})
    rows = [row for row in effects.get(spell_id, []) if row['DifficultyID'] == '0']
    by_index = group(rows, 'EffectIndex')

    def source_radius(effect):
        candidates = by_index.get(effect['index'], [])
        if len(candidates) != 1:
            return None
        row = candidates[0]
        if effect.get('effectType') != number(row, 'Effect') or effect.get('auraType') != number(row, 'EffectAura'):
            return None
        references = {int(row[column]) for column in ('EffectRadiusIndex_0', 'EffectRadiusIndex_1')
                      if int(row[column]) != 0}
        if len(references) != 1:
            return None
        radius = radii.get(next(iter(references)))
        if radius and number(radius, 'RadiusPerLevel') == 0 and number(radius, 'Radius') > 0 \
                and number(radius, 'RadiusMax') == number(radius, 'Radius'):
            return number(radius, 'Radius')
        return None

    owned_effects = tooltip.get('effects', [])
    can_add_radius = (tooltip.get('radiusSourceMetadata', provenance['radius']) == provenance['radius']
                      and all(source_radius(effect) == effect['radius']
                              for effect in owned_effects if 'radius' in effect))

    for effect in owned_effects:
        candidates = by_index.get(effect['index'], [])
        if len(candidates) != 1:
            continue
        row = candidates[0]
        if effect.get('effectType') != number(row, 'Effect') or effect.get('auraType') != number(row, 'EffectAura'):
            continue
        if ('periodMs' not in effect and number(row, 'EffectAuraPeriod') > 0
                and tooltip.get('periodSourceMetadata', provenance['period']) == provenance['period']):
            effect['periodMs'] = number(row, 'EffectAuraPeriod')
            tooltip['periodSourceMetadata'] = provenance['period']
        if 'radius' in effect or not can_add_radius:
            continue
        radius = source_radius(effect)
        if radius is not None:
            effect['radius'] = radius
            tooltip['radiusSourceMetadata'] = provenance['radius']

    candidates = [row for row in misc.get(spell_id, []) if row['DifficultyID'] == '0']
    if ('durationMs' not in tooltip and len(candidates) == 1
            and tooltip.get('durationSourceMetadata', provenance['duration']) == provenance['duration']):
        duration = durations.get(int(candidates[0]['DurationIndex']))
        if duration and number(duration, 'Duration') > 0 and number(duration, 'DurationPerLevel') == 0 \
                and number(duration, 'DurationPerResource') == 0 \
                and number(duration, 'MaxDuration') == number(duration, 'Duration'):
            tooltip['durationMs'] = number(duration, 'Duration')
            tooltip['durationSourceMetadata'] = provenance['duration']

    return result


def fill_missing_spell_fields(entity, spell_id, tables, provenance):
    """Add scalar dependencies only from unique default rows, preserving owned values."""
    result = copy.deepcopy(entity)
    tooltip = result.get('tooltipData', {})

    def unique(table):
        rows = [row for row in tables[table].get(spell_id, []) if row['DifficultyID'] == '0']
        return rows[0] if len(rows) == 1 else None

    def add(field, row, column, source):
        if field not in tooltip and row is not None:
            value = number(row, column)
            if value >= 0:
                result['tooltipData'] = tooltip
                tooltip[field] = value
                tooltip[field + 'SourceMetadata'] = provenance[source]

    aura = unique('SpellAuraOptions')
    for field, column in (('maxStacks', 'CumulativeAura'), ('procChance', 'ProcChance'),
                          ('procCharges', 'ProcCharges')):
        add(field, aura, column, 'SpellAuraOptions')
    add('maxTargets', unique('SpellTargetRestrictions'), 'MaxTargets', 'SpellTargetRestrictions')
    misc = unique('SpellMisc')
    if misc is not None:
        ranges = tables['SpellRange'].get(int(misc['RangeIndex']), [])
        if len(ranges) == 1 and number(ranges[0], 'RangeMax_0') == number(ranges[0], 'RangeMax_1'):
            add('rangeMax', ranges[0], 'RangeMax_0', 'SpellRange')
    return result


def fill_missing_effect_levels(entity, spell_id, effects, levels, provenance, modifiers, skipped=None):
    """Fill missing dependencies from unique rows without replacing owned values."""
    result = copy.deepcopy(entity)
    tooltip = result.get('tooltipData', {})
    rows = [row for row in effects.get(spell_id, []) if row['DifficultyID'] == '0']
    by_index = group(rows, 'EffectIndex')
    owned = tooltip.get('effects', [])
    owned_indices = [effect['index'] for effect in owned]
    compatible = (len(owned_indices) == len(set(owned_indices))
                  and all(len(candidates) == 1 for candidates in by_index.values())
                  and tooltip.get('effectValuesSourceMetadata', provenance['effects']) == provenance['effects'])
    if compatible:
        for effect in owned:
            candidates = by_index.get(effect['index'], [])
            if len(candidates) != 1 or any(
                    field in effect and effect[field] != number(candidates[0], column)
                    for field, column in EFFECT_FIELDS.items()):
                compatible = False
                break
    if compatible and rows:
        updated = copy.deepcopy(owned)
        by_owned_index = {effect['index']: effect for effect in updated}
        changed = False
        for index, candidates in sorted(by_index.items()):
            row = candidates[0]
            effect = by_owned_index.get(index)
            new_effect = effect is None
            if effect is None:
                if modifiers.get((spell_id, index)):
                    if skipped is not None:
                        skipped.append({'id': spell_id, 'field': f'effects.{index}',
                                        'reason': 'Trait override requires separate review'})
                    continue
                effect = {'index': index}
                updated.append(effect)
                changed = True
            for field, column in EFFECT_FIELDS.items():
                value = number(row, column)
                # A zero period is not a periodic interval, even when the row exists.
                if (field not in effect and (new_effect or field == 'chainTargets')
                        and (field != 'periodMs' or value > 0)):
                    effect[field] = value
                    changed = True
        if changed:
            result['tooltipData'] = tooltip
            tooltip['effects'] = sorted(updated, key=lambda effect: effect['index'])
            tooltip['effectValuesSourceMetadata'] = provenance['effects']
    level_rows = [row for row in levels.get(spell_id, []) if row['DifficultyID'] == '0']
    if not compatible and skipped is not None:
        skipped.append({'id': spell_id, 'field': 'effects and dependent levels',
                        'reason': 'Owned effect conflict or ambiguous source rows'})
    if compatible and len(level_rows) == 1:
        row = level_rows[0]
        fields = (('baseLevel', 'BaseLevel'), ('spellLevel', 'SpellLevel'), ('maxLevel', 'MaxLevel'))
        # Conflicts may indicate a different client build; never combine them silently.
        if all(field not in tooltip or tooltip[field] == number(row, column) for field, column in fields):
            for field, column in fields:
                metadata = field + 'SourceMetadata'
                if field not in tooltip and tooltip.get(metadata, provenance['levels']) == provenance['levels']:
                    result['tooltipData'] = tooltip
                    tooltip[field] = number(row, column)
                    tooltip[metadata] = provenance['levels']
        elif skipped is not None:
            skipped.append({'id': spell_id, 'field': 'levels', 'reason': 'Owned level conflict'})
    elif compatible and len(level_rows) > 1 and skipped is not None:
        skipped.append({'id': spell_id, 'field': 'levels', 'reason': 'Ambiguous default SpellLevels rows'})
    return result


def effect_level_provenance(build, hashes):
    """Keep value provenance narrow; the preparation report owns guard inputs."""
    return {
        field: {'source': 'wowClient', 'sourceBuild': build, 'sourceLocale': 'enUS',
                'sourceFileSha256': {table: hashes[table]}}
        for field, table in (('effects', 'SpellEffect'), ('levels', 'SpellLevels'))
    }


def prepare(root, directories, output, ids=None, replace_existing=False, missing_tooltip_values=False,
            missing_spell_fields=False, missing_effect_levels=False):
    required = (EFFECT_LEVEL_TABLES if missing_effect_levels else SPELL_FIELD_TABLES if missing_spell_fields
                else TOOLTIP_TABLES if missing_tooltip_values else TABLES)
    build, tables = load_tables(directories, required)
    modifiers = None if missing_tooltip_values or missing_spell_fields else index_traits(tables, build)
    effects = group(tables.get('SpellEffect', []), 'SpellID')
    levels = {} if missing_tooltip_values or missing_spell_fields else group(tables['SpellLevels'], 'SpellID')
    misc = group(tables['SpellMisc'], 'SpellID') if missing_tooltip_values else {}
    radii = {int(row['ID']): row for row in tables.get('SpellRadius', [])}
    durations = {int(row['ID']): row for row in tables.get('SpellDuration', [])}
    provenance = {}
    field_tables = {}
    verified_inputs = None
    if missing_effect_levels:
        hashes = {entry['table']: entry['sha256'] for directory in directories
                  for entry in json.loads((directory / 'manifest.json').read_text())['results']
                  if entry['locale'] == 'enUS' and entry['table'] in EFFECT_LEVEL_TABLES}
        verified_inputs = {table: hashes[table] for table in EFFECT_LEVEL_TABLES}
        provenance.update(effect_level_provenance(build, hashes))
    if missing_spell_fields:
        field_tables = {table: group(rows, 'ID' if table == 'SpellRange' else 'SpellID')
                        for table, rows in tables.items()}
        hashes = {entry['table']: entry['sha256'] for directory in directories
                  for entry in json.loads((directory / 'manifest.json').read_text())['results']
                  if entry['locale'] == 'enUS' and entry['table'] in SPELL_FIELD_TABLES}
        for table in SPELL_FIELD_TABLES:
            dependencies = ('SpellMisc', 'SpellRange') if table == 'SpellRange' else (table,)
            provenance[table] = {'source': 'wowClient', 'sourceBuild': build, 'sourceLocale': 'enUS',
                                 'sourceFileSha256': {name: hashes[name] for name in dependencies}}
    if missing_tooltip_values:
        hashes = {}
        for directory in directories:
            manifest = json.loads((directory / 'manifest.json').read_text())
            for entry in manifest['results']:
                if entry['locale'] == 'enUS' and entry['table'] in TOOLTIP_TABLES:
                    hashes[entry['table']] = entry['sha256']
        for field, names in (('period', ('SpellEffect',)), ('radius', ('SpellEffect', 'SpellRadius')),
                             ('duration', ('SpellMisc', 'SpellDuration'))):
            provenance[field] = {'source': 'wowClient', 'sourceBuild': build, 'sourceLocale': 'enUS',
                                 'sourceFileSha256': {name: hashes[name] for name in names}}
    paths = sorted((root / 'catalogs/spells').glob('[0-9]*.json'), key=lambda path: int(path.stem))
    report = {'build': build, 'checked': 0, 'changed': [], 'skipped': []}
    if verified_inputs is not None:
        report['verifiedInputs'] = verified_inputs
    patch = ['*** Begin Patch\n']

    for path in paths:
        spell_id = int(path.stem)

        if ids is not None and spell_id not in ids:
            continue

        report['checked'] += 1
        before = path.read_text()
        entity = json.loads(before)

        try:
            refreshed = (fill_missing_effect_levels(entity, spell_id, effects, levels, provenance,
                                                     modifiers, report['skipped'])
                         if missing_effect_levels else
                         fill_missing_spell_fields(entity, spell_id, field_tables, provenance)
                         if missing_spell_fields else
                         fill_missing_tooltip_values(entity, spell_id, effects, misc, radii, durations, provenance)
                         if missing_tooltip_values else
                         refresh_entity(entity, spell_id, effects, levels, modifiers, replace_existing))
        except (ValueError, KeyError) as error:
            report['skipped'].append({'id': spell_id, 'reason': str(error)})
            continue

        if refreshed == entity:
            continue

        after = json.dumps(refreshed, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
        diff = list(difflib.unified_diff(before.splitlines(True), after.splitlines(True)))[2:]
        patch.append('*** Update File: ' + path.relative_to(root).as_posix() + '\n')
        patch.extend('@@\n' if line.startswith('@@ ') else line for line in diff)
        report['changed'].append(spell_id)

    patch.append('*** End Patch\n')
    output.mkdir(parents=True, exist_ok=True)
    write_atomic(output / 'updates.patch', ''.join(patch).encode())
    write_atomic(output / 'report.json', (json.dumps(report, indent=2) + '\n').encode())
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot', type=Path, nargs='+', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--ids', type=int, nargs='+')
    parser.add_argument('--ids-file', type=Path, help='JSON array of spell IDs to check')
    parser.add_argument('--replace-existing', action='store_true', help='Allow reviewed numeric value replacements')
    parser.add_argument('--missing-tooltip-values', action='store_true',
                        help='Only add missing unscaled radius, duration and period values')
    parser.add_argument('--missing-spell-fields', action='store_true',
                        help='Only add missing stack, proc, target-count and unambiguous range fields')
    parser.add_argument('--missing-effect-level-values', action='store_true',
                        help='Only add missing effect and level dependencies from compatible unique rows')
    args = parser.parse_args()
    if args.ids and args.ids_file:
        parser.error('Use either --ids or --ids-file')
    ids = args.ids
    if args.ids_file:
        ids = json.loads(args.ids_file.read_text())
        if not isinstance(ids, list) or any(type(value) is not int or value <= 0 for value in ids):
            parser.error('--ids-file must contain a JSON array of positive integer spell IDs')
    if sum((args.replace_existing, args.missing_tooltip_values, args.missing_spell_fields,
            args.missing_effect_level_values)) > 1:
        parser.error('Replacement and missing-only modes cannot be combined')
    report = prepare(args.root, args.snapshot, args.output, set(ids) if ids is not None else None,
                     args.replace_existing, args.missing_tooltip_values, args.missing_spell_fields,
                     args.missing_effect_level_values)
    print(f'{report["checked"]} checked; {len(report["changed"])} changed; {len(report["skipped"])} skipped')
    print(f'Review {args.output / "report.json"}; apply {args.output / "updates.patch"} with the dedicated patch tool.')


if __name__ == '__main__':
    main()
