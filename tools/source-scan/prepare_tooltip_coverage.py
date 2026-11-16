#!/usr/bin/env python3
"""Prepare a coverage-selected copy of the local tooltip-check probe; never install or start it.

Instead of random IDs, every tooltip feature that drives a distinct native row or value
extrapolation is covered by at least `--per-feature` owned IDs that exist in the client build:

- spells: each description/aura template token shape (`$s1`, `${$m1/-1000}`, `$lpoint:points;`,
  `$?s123[...]`, `$@spellname`), rank/subtext shape, cast time, range, duration, school, passive,
  and the owned tooltip facts (tools, reagents items, stacks, charges, targets, variables);
- items: class/subclass, slot, binding, quality, each stat type, requirements (class, race,
  skill, reputation, level, PvP rank, ability), set, quest starter, page, limit/unique, flags,
  weapon damage, duration, container, and each effect trigger with its spell's token shapes.

Features are filled rarest first from a seeded, stable order, so the same catalog, Wago snapshot
and seed give the same IDs. The selection is a test inventory, never a runtime allowlist.
"""

import argparse
import csv
import hashlib
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from prepare_api_sample import catalog_ids, global_keys, write_probe_copy

TOKEN = re.compile(r'\$(?:\{[^}]*\}|\?[^\[]*|@[a-z]+|[lgL][^;]*;|[*/]\d+;?|<[^>]*>|\d*[a-zA-Z]+\d*)')
PASSIVE = 0x40  # SpellAttr0 passive
OWNED_SPELL_FACTS = ('requiredToolCategories', 'requiredToolItems', 'procCharges', 'maxStacks',
                     'maxTargets', 'variables', 'procChance', 'durationMs')


def token_shapes(text):
    """Template token shapes with IDs and amounts removed: `$s1` → `$s`, `${$m1/-1000}` → `${$m/-}`."""
    shapes = set()
    for token in TOKEN.findall(text or ''):
        if token[1] in 'lgL':
            shapes.add('$' + token[1] + ':' + str(token.count(':') + 1))
        else:
            shapes.add(re.sub(r'\d+', '', token).strip())
    if '|4' in (text or ''):
        shapes.add('|4plural')
    return shapes


def read_table(directory, name):
    paths = sorted(directory.glob(f'{name}.*.enUS.csv'))
    if len(paths) != 1:
        raise SystemExit(f'Expected one {name} enUS export in {directory}, found {len(paths)}')
    with paths[0].open(encoding='utf-8', newline='') as handle:
        return {int(row['ID']): row for row in csv.DictReader(handle)}, paths[0].name.split('.', 1)[1][:-9]


def number(row, key):
    try:
        return int(row.get(key) or 0)
    except ValueError:
        return int(float(row[key]))


def bits(value):
    return [bit for bit in range(32) if value & (1 << bit)]


def spell_features(wago, root=ROOT):
    spells, build = read_table(wago, 'Spell')
    names, _ = read_table(wago, 'SpellName')
    misc = {number(row, 'SpellID'): row for row in read_table(wago, 'SpellMisc')[0].values()}
    owned = set(catalog_ids('spells', root))
    features = defaultdict(set)
    for spell_id in owned & set(names):
        spell = spells.get(spell_id, {})
        found = {'spell'}
        found |= {'description:' + shape for shape in token_shapes(spell.get('Description_lang'))}
        found |= {'aura:' + shape for shape in token_shapes(spell.get('AuraDescription_lang'))}
        if spell.get('AuraDescription_lang'):
            found.add('aura')
        subtext = spell.get('NameSubtext_lang')
        if subtext:
            found.add('subtext:' + re.sub(r'\d+', '#', subtext))
        row = misc.get(spell_id)
        if row:
            for key in ('CastingTimeIndex', 'RangeIndex', 'DurationIndex', 'SchoolMask'):
                found.add(f'{key}:{number(row, key)}')
            if number(row, 'Attributes_0') & PASSIVE:
                found.add('passive')
        record = json.loads((root / 'catalogs/spells' / f'{spell_id}.json').read_text(encoding='utf-8'))
        facts = record.get('tooltipData') or {}
        found |= {'owned:' + key for key in OWNED_SPELL_FACTS if facts.get(key)}
        for shape in found:
            features[shape].add(spell_id)
    return features, build


def item_features(wago, root=ROOT):
    sparse, build = read_table(wago, 'ItemSparse')
    items, _ = read_table(wago, 'Item')
    spells, _ = read_table(wago, 'Spell')
    effects, _ = read_table(wago, 'ItemEffect')
    links = defaultdict(list)
    for row in read_table(wago, 'ItemXItemEffect')[0].values():
        effect = effects.get(number(row, 'ItemEffectID'))
        if effect:
            links[number(row, 'ItemID')].append(effect)
    owned = set(catalog_ids('items', root))
    features = defaultdict(set)
    for item_id in owned & set(sparse):
        row, item = sparse[item_id], items.get(item_id, {})
        found = {'item', f'class:{number(item, "ClassID")}:{number(item, "SubclassID")}',
                 f'inventoryType:{number(row, "InventoryType")}', f'bonding:{number(row, "Bonding")}',
                 f'quality:{number(row, "OverallQualityID")}'}
        found |= {f'stat:{number(row, f"StatModifier_bonusStat_{index}")}' for index in range(10)
                  if number(row, f'StatModifier_bonusStat_{index}') >= 0
                  and number(row, f'StatPercentEditor_{index}') != 0}
        classes = number(row, 'AllowableClass')
        if classes > 0:
            count = len(bits(classes))
            found.add('classes:' + ('1' if count == 1 else '2-3' if count <= 3 else 'many'))
        if number(row, 'AllowableRace_0') > 0:
            found.add('races')
        for key, feature in (('RequiredSkill', 'skill'), ('MinFactionID', 'reputation'),
                             ('RequiredPVPRank', 'pvpRank'), ('RequiredAbility', 'ability'),
                             ('ItemSet', 'set'), ('StartQuestID', 'questStarter'), ('PageID', 'page'),
                             ('LimitCategory', 'limitCategory'), ('ItemNameDescriptionID', 'nameDescription'),
                             ('DurationInInventory', 'duration'), ('ContainerSlots', 'container'),
                             ('TotemCategoryID', 'totemCategory'), ('LockID', 'lock'),
                             ('RequiredHoliday', 'holiday'), ('ZoneBound_0', 'zoneBound'),
                             ('InstanceBound', 'instanceBound'), ('BagFamily', 'bagFamily')):
            if number(row, key) > 0:
                found.add(feature)
        if number(row, 'MinFactionID') > 0:
            found.add(f'reputation:{number(row, "MinReputation")}')
        if number(row, 'RequiredLevel') > 1:
            found.add('requiredLevel')
        if number(row, 'MaxCount') == 1:
            found.add('unique')
        if number(row, 'Stackable') > 1:
            found.add('stackable')
        if number(row, 'ItemDelay') > 0:
            found.add(f'weapon:{number(row, "DamageType")}')
        if number(row, 'SellPrice') == 0:
            found.add('noSellPrice')
        if row.get('Description_lang'):
            found.add('flavor')
        for index in range(5):
            found |= {f'flags{index}:{bit}' for bit in bits(number(row, f'Flags_{index}'))}
        for effect in links.get(item_id, []):
            trigger = number(effect, 'TriggerType')
            found.add(f'effect:{trigger}')
            if number(effect, 'Charges'):
                found.add(f'effect:{trigger}:charges' + ('-' if number(effect, 'Charges') < 0 else '+'))
            if number(effect, 'CoolDownMSec') > 0 or number(effect, 'CategoryCoolDownMSec') > 0:
                found.add(f'effect:{trigger}:cooldown')
            spell = spells.get(number(effect, 'SpellID'), {})
            found |= {f'effect:{trigger}:{shape}' for shape in token_shapes(spell.get('Description_lang'))}
        for shape in found:
            features[shape].add(item_id)
    return features, build


def select(features, per_feature, seed, kind):
    """Cover each feature `per_feature` times, rarest first, in a seeded stable ID order."""
    rank = {}

    def order(entity_id):
        if entity_id not in rank:
            rank[entity_id] = hashlib.sha256(f'{seed}:{kind}:{entity_id}'.encode()).hexdigest()
        return rank[entity_id]

    chosen = set()
    for feature in sorted(features, key=lambda name: (len(features[name]), name)):
        ids = features[feature]
        missing = per_feature - len(ids & chosen)
        if missing > 0:
            chosen.update(sorted(ids - chosen, key=order)[:missing])
    return sorted(chosen)


def coverage(features, chosen, per_feature):
    chosen = set(chosen)
    short = {name: len(ids & chosen) for name, ids in features.items() if len(ids & chosen) < per_feature}
    return {'features': len(features), 'underCovered': dict(sorted(short.items()))}


def prepare(output, wago, per_feature, seed, timeout, root=ROOT):
    spell_map, spell_build = spell_features(wago, root)
    item_map, item_build = item_features(wago, root)
    selection = {'spell': select(spell_map, per_feature, seed, 'spell'),
                 'item': select(item_map, per_feature, seed, 'item')}
    keys = global_keys(root)
    counts = {
        'spell': {'candidates': len(spell_map.get('spell', ())), 'sampled': len(selection['spell']),
                  **coverage(spell_map, selection['spell'], per_feature)},
        'item': {'candidates': len(item_map.get('item', ())), 'sampled': len(selection['item']),
                 **coverage(item_map, selection['item'], per_feature)},
        'globals': {'catalog': len(keys), 'sampled': len(keys)},
    }
    sample = {'mode': 'coverage', 'seed': seed, 'perFeature': per_feature,
              'wagoBuild': spell_build if spell_build == item_build else f'{spell_build}/{item_build}'}
    write_probe_copy(output, selection, keys, sample, timeout, counts)
    features = {'spell': {name: sorted(set(ids) & set(selection['spell'])) for name, ids in sorted(spell_map.items())},
                'item': {name: sorted(set(ids) & set(selection['item'])) for name, ids in sorted(item_map.items())}}
    (output / 'features.json').write_text(json.dumps(features, indent=1) + '\n', encoding='utf-8')
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--output', required=True, type=Path, help='New directory under datasources/imports/')
    parser.add_argument('--wago', required=True, type=Path,
                        help='Wago snapshot directory of the client build (Spell, SpellName, SpellMisc, Item, '
                             'ItemSparse, ItemEffect, ItemXItemEffect enUS CSVs)')
    parser.add_argument('--per-feature', type=int, default=3, help='IDs per feature (default 3)')
    parser.add_argument('--seed', default='frs-tooltip-coverage-1', help='Ordering seed for equally useful IDs')
    parser.add_argument('--load-timeout', type=int, default=300, help='Seconds to wait for the client cache')
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / 'datasources/imports').resolve()):
        parser.error('--output must be under datasources/imports/')
    if output.exists():
        parser.error(f'{output} already exists; choose a new directory')
    if args.per_feature <= 0 or args.load_timeout <= 0:
        parser.error('--per-feature and --load-timeout must be positive')
    output.mkdir(parents=True)
    counts = prepare(output, args.wago.resolve(), args.per_feature, args.seed, args.load_timeout)
    for kind in ('spell', 'item'):
        count = counts[kind]
        print(f"{kind}: {count['sampled']} IDs cover {count['features']} features "
              f"({len(count['underCovered'])} have fewer than {args.per_feature} candidates)")
    print(f'Probe copy: {output / "rosetta-tooltip-check"}')


if __name__ == '__main__':
    main()
