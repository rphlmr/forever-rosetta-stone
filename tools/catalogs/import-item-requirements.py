#!/usr/bin/env python3
"""Record item usage restrictions from one verified Wago build in `tooltipData.requirements`.

Only IDs are recorded: allowed classes, a uniquely bound profession category, the minimum
reputation faction and a required ability spell. The runtime compares a requirement row only
with the names those owned IDs carry. Required ranks, standings and levels stay live.
"""

import argparse
import csv
import hashlib
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def table(wago, name):
    matches = sorted(wago.glob(f'{name}.*.enUS.csv'))
    if len(matches) != 1:
        raise SystemExit(f'Expected one enUS {name} export in {wago}')
    path = matches[0]
    build = path.name[len(name) + 1:-len('.enUS.csv')]
    with path.open(encoding='utf-8', newline='') as handle:
        return path, build, list(csv.DictReader(handle))


def integer(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def owned_ids(root, kind):
    return {int(path.stem) for path in (root / 'catalogs' / kind).glob('*.json') if path.stem.isdigit()}


def english_name(root, kind, entity_id):
    path = root / 'catalogs' / kind / f'{entity_id}.json'
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding='utf-8')).get('locales', {}).get('enUS', {}).get('name')


def unique_categories(rows, owned):
    """Map a SkillLine to its profession category only when one owned root category uses it."""
    by_skill = defaultdict(set)
    for row in rows:
        if integer(row.get('ParentTradeSkillCategoryID')) == 0 and integer(row.get('SkillLineID')) > 0:
            by_skill[integer(row['SkillLineID'])].add(integer(row['ID']))
    return {skill: next(iter(ids)) for skill, ids in by_skill.items() if len(ids) == 1 and ids <= owned}


def requirements_for(row, classes, categories, factions, root):
    result, files = {}, {'ItemSparse'}
    mask = integer(row.get('AllowableClass'))
    if mask > 0:
        allowed = sorted(class_id for class_id in classes if mask & (1 << (class_id - 1)))
        if allowed and len(allowed) < len(classes):
            result['classIDs'] = allowed
    skill = integer(row.get('RequiredSkill'))
    if skill in categories:
        result['skillCategoryID'], result['skillLineID'] = categories[skill], skill
        files.add('TradeSkillCategory')
    faction = integer(row.get('MinFactionID'))
    if faction in factions:
        result['factionID'] = faction
    ability = integer(row.get('RequiredAbility'))
    if ability > 0 and english_name(root, 'spells', ability):
        result['abilitySpellID'] = ability
    return result, files


def run(root, wago, write):
    sparse_path, build, sparse = table(wago, 'ItemSparse')
    category_path, category_build, category_rows = table(wago, 'TradeSkillCategory')
    if category_build != build:
        raise SystemExit('ItemSparse and TradeSkillCategory must come from the same build')
    hashes = {'ItemSparse': sha256(sparse_path), 'TradeSkillCategory': sha256(category_path)}
    classes = sorted(owned_ids(root, 'classes'))
    categories = unique_categories(category_rows, owned_ids(root, 'professioncategories'))
    factions = owned_ids(root, 'factions')
    items = root / 'catalogs/items'
    counts = defaultdict(int)
    for row in sparse:
        path = items / f"{integer(row.get('ID'))}.json"
        if not path.exists():
            continue
        data = json.loads(path.read_text(encoding='utf-8'))
        tooltip = data.setdefault('tooltipData', {})
        requirements, files = requirements_for(row, classes, categories, factions, root)
        metadata = {'source': 'wago', 'sourceBuild': build,
                    'sourceFiles': {name: hashes[name] for name in sorted(files)}, 'sourceLocale': 'enUS'}
        if requirements:
            if tooltip.get('requirements') == requirements and tooltip.get('requirementsSourceMetadata') == metadata:
                continue
            tooltip['requirements'], tooltip['requirementsSourceMetadata'] = requirements, metadata
            counts['written'] += 1
            for key in requirements:
                counts[key] += 1
        elif 'requirements' in tooltip:
            tooltip.pop('requirements')
            tooltip.pop('requirementsSourceMetadata', None)
            counts['removed'] += 1
        else:
            continue
        if write:
            path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return dict(counts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wago', type=Path, required=True, help='Verified Wago export folder for one build')
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--write', action='store_true', help='Write changed item catalogs')
    args = parser.parse_args()
    print(json.dumps(run(args.root, args.wago, args.write), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
