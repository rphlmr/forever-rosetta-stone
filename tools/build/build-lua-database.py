"""Build the runtime database from Forever Rosetta Stone's maintained catalogs without modifying them."""

import argparse
import collections
import base64
import hashlib
import json
import re
import zlib
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.catalogs.catalog_storage import CATALOGS, load_catalogs
from tools.build.database_storage import write_localized_records, write_pages
from tools.build.database_packs import write_pack
from tools.build.runtime_catalog import (EXCLUDED_QUEST_STATUSES, decode_client_escapes, project_localized_record,
                                         project_tooltip_rules, equipment_requirement_sources, project_dialogue)
from tools.catalogs.english_scope import has_english_text, identity_field


CATALOG_FILES = CATALOGS
KINDS = CATALOG_FILES + ('maps',)
LOCALE_NAMES = {
    'deDE': 'Deutsch', 'enUS': 'English', 'esES': 'Español (España)',
    'esMX': 'Español (México)', 'frFR': 'Français', 'itIT': 'Italiano', 'koKR': '한국어',
    'ptBR': 'Português (Brasil)', 'ruRU': 'Русский', 'zhCN': '简体中文', 'zhTW': '繁體中文',
}


class MetadataEncoder:
    """Encode deterministic CBOR and write chunked TOC metadata."""

    def __init__(self):
        from lupa.lua51 import LuaRuntime

        self.lua = LuaRuntime(encoding=None)
        encoding = Path(__file__).with_name('encoding')
        self.codec = self.lua.execute((encoding / 'blizzard-cbor.lua').read_bytes())
        self.writer = self.lua.execute((encoding / 'toc-metadata.lua').read_bytes())
        self.options = self.lua.table_from({b'deterministicMapOrder': True})

    def to_lua(self, value):
        if isinstance(value, str):
            return value.encode('utf-8')

        if isinstance(value, dict):
            return self.lua.table_from({self.to_lua(key): self.to_lua(item) for key, item in value.items()})

        if isinstance(value, list):
            return self.lua.table_from([self.to_lua(item) for item in value])

        return value

    def serialize(self, value):
        return self.codec[b'SerializeCBOR'](self.to_lua(value), self.options)

    def encode(self, value, compressed=False):
        encoded = self.serialize(value)

        if compressed:
            encoded = zlib.compress(encoded, level=9)

        return base64.b64encode(encoded)

    def create_sink(self, pieces):
        sink = self.lua.table()
        sink[b'write'] = lambda _, *parts: pieces.append(b''.join(
            part if isinstance(part, bytes) else str(part).encode('ascii') for part in parts
        ))

        return sink

    def write(self, sink, key, value):
        if isinstance(sink, dict):
            sink[key] = value
            return

        self.writer[b'writeMetadata'](sink, key.encode('ascii'), value, 1000)


CLIENT_LITERAL_LETTER = re.compile(r'[A-Za-z\u0080-\U0010ffff]')
CLIENT_FORMAT = re.compile(r'%[0-9.$]*[dscfFg]')


def normalize_client_literal(text):
    """Mirror client-labels.lua Normalize so build and runtime agree byte for byte."""
    text = re.sub(r'\|[cC][0-9a-fA-F]{8}', '', text)
    text = re.sub(r'\|[rR]', '', text)
    text = re.sub(r'\|T.*?\|t', '', text, flags=re.S)
    text = text.replace('|n', '\n').replace('\u00a0', ' ').replace('\u202f', ' ')
    return re.sub(r'[ \t\n\r\v\f]+', ' ', text).strip(' ')


def export_database(documents, output, dev_debug=False, globalstring_keys=None):
    """Emit a small manifest and grouped load-on-demand database addons."""
    for kind in CATALOG_FILES:
        if kind in ('races', 'globalstrings', 'professioncategories', 'activities', 'taxinodes', 'books', 'bookpages', 'totemcategories', 'shapeshiftforms', 'itemlimitcategories', 'itemenchantments', 'holidaynames', 'locktypes', 'itemsubclasses', 'gossipoptions', 'sharedstrings') and kind not in documents:
            continue
        if documents[kind].get('schemaVersion') != 1:
            raise ValueError('Expected schema 1 catalog: ' + kind)

    quests = documents['quests']
    combined = {kind: entities for document in documents.values() for kind, entities in document['catalogs'].items()}
    combined.setdefault('races', {})
    combined.setdefault('globalstrings', {})
    combined.setdefault('professioncategories', {})
    combined.setdefault('activities', {})
    combined.setdefault('taxinodes', {})
    combined.setdefault('books', {})
    combined.setdefault('bookpages', {})
    combined.setdefault('totemcategories', {})
    combined.setdefault('shapeshiftforms', {})
    for kind in ('itemlimitcategories', 'itemenchantments', 'holidaynames', 'locktypes', 'itemsubclasses', 'gossipoptions', 'sharedstrings'):
        combined.setdefault(kind, {})
    if globalstring_keys is not None:
        combined['globalstrings'] = {entity_id: entity for entity_id, entity in combined['globalstrings'].items()
                                     if entity.get('key') in globalstring_keys}
    locale_names = dict(LOCALE_NAMES)
    locale_names.update({locale: details['nativeName'] for locale, details in quests.get('rosettaLocales', {}).items()})
    locales = sorted(set(quests['locales']) | {
        locale for catalog in combined.values() for entity in catalog.values() for locale in entity['locales']
    })

    if any(not re.fullmatch(r'[a-z]{2}[A-Z]{2}', locale) for locale in locales):
        raise ValueError('Invalid catalog locale')

    digest = hashlib.sha256(b'format8')

    for kind in CATALOG_FILES:
        if kind in ('races', 'globalstrings', 'professioncategories', 'activities', 'taxinodes', 'books', 'bookpages', 'totemcategories', 'shapeshiftforms', 'itemlimitcategories', 'itemenchantments', 'holidaynames', 'locktypes', 'itemsubclasses', 'gossipoptions', 'sharedstrings') and kind not in documents:
            continue
        document = documents[kind]
        if kind == 'globalstrings' and globalstring_keys is not None:
            document = {**document, 'catalogs': {'globalstrings': combined['globalstrings']}}
        digest.update(json.dumps(document, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode())

    version = digest.hexdigest()
    encoder = MetadataEncoder()
    pieces = []
    sink = encoder.create_sink(pieces)
    encoder.write(sink, 'X-Rosetta-Format', b'8')
    encoder.write(sink, 'X-Rosetta-Catalog', version.encode('ascii'))
    encoder.write(sink, 'X-Rosetta-Locales', encoder.encode(
        {locale: locale_names.get(locale, locale) for locale in locales}, compressed=True,
    ))
    packs = {'ForeverRosettaStone_Rules': {}}
    equipment_sources = equipment_requirement_sources(combined['spells'])

    for locale in locales:
        packs['ForeverRosettaStone_Data_' + locale] = {}

    for kind in KINDS:
        catalog = {entity_id: entity for entity_id, entity in combined[kind].items()
                   if kind == 'globalstrings' or has_english_text(entity, identity_field(kind))}

        if kind == 'quests':
            catalog = {entity_id: entity for entity_id, entity in catalog.items()
                       if entity.get('usageStatus') not in EXCLUDED_QUEST_STATUSES}

        ids = sorted(int(entity_id) for entity_id in catalog)

        if any(not re.fullmatch(r'[1-9][0-9]*', entity_id) for entity_id in catalog):
            raise ValueError('Expected positive decimal entity IDs in ' + kind)

        locale_records = {locale: {} for locale in locales}
        dialogue_records = {locale: {} for locale in locales} if kind in ('quests', 'npcs') else None
        rule_records = {}
        global_keys = set()
        gossip_icons = set()

        for entity_id in ids:
            entity = catalog[str(entity_id)]
            if kind == 'globalstrings':
                if not isinstance(entity.get('key'), str) or not entity['key']:
                    raise ValueError(f'GlobalString {entity_id} has no source key')
                if entity['key'] in global_keys:
                    raise ValueError('Duplicate GlobalString key: ' + entity['key'])
                global_keys.add(entity['key'])
                rule_records[entity_id] = {'name': entity['key'], 'hasAITranslation': False}
            if 'enGB' in entity['locales']:
                raise ValueError('enGB is not supported; write English fields under enUS')
            rules = project_tooltip_rules(entity) if kind in ('items', 'spells') else {}
            if kind == 'spells' and entity_id in equipment_sources:
                rules['equipmentRequirementSources'] = equipment_sources[entity_id]
            if kind == 'gossipoptions' and 'sharedIcon' in entity:
                icon = entity['sharedIcon']
                if type(icon) is not int or icon <= 0 or icon in gossip_icons:
                    raise ValueError(f'Gossip option {entity_id} has an invalid or duplicate shared icon')
                gossip_icons.add(icon)
                rule_records[entity_id] = {'name': str(icon), 'hasAITranslation': False}
            if kind == 'itemenchantments' and entity.get('duration', 0) > 0:
                rule_records[entity_id] = {'name': 'temporary', 'hasAITranslation': False}
            if kind == 'sharedstrings' and 'usage' in entity:
                usage = entity.get('usage')
                if not isinstance(usage, str) or not re.fullmatch(r'[a-z][A-Za-z]+', usage):
                    raise ValueError(f'SharedString {entity_id} has no valid usage')
                rule_records[entity_id] = {'name': usage, 'hasAITranslation': False}
            if kind == 'npcs' and 'factionId' in entity:
                faction_id = entity['factionId']
                if type(faction_id) is not int or faction_id < 1 or str(faction_id) not in combined['factions']:
                    raise ValueError(f'NPC {entity_id} references an invalid or missing faction: {faction_id!r}')
                rules = {'factionId': faction_id}

            if kind == 'books':
                rules = {key: entity[key] for key in ('owners', 'pages', 'chainStatus') if key in entity}

            if rules:
                rule_records[entity_id] = {'details': rules, 'hasAITranslation': False}

            for locale in entity['locales']:
                if dialogue_records is not None and entity['locales'][locale].get('dialogue'):
                    dialogue = project_dialogue(kind, entity_id, entity, locale)
                    if dialogue is not None:
                        dialogue_records[locale][entity_id] = dialogue
                localized = project_localized_record(kind, entity_id, entity, locale, combined['items'], combined['npcs'])

                if localized is None:
                    continue

                if kind == 'spells':
                    for references in equipment_sources.get(entity_id, {}).values():
                        owner = combined['spells'].get(str(references.get(locale)), {})
                        field = (owner.get('locales', {}).get(locale, {}).get('translationMetadata', {})
                                 .get('fields', {}).get('equipmentRequirement', {}))
                        if field.get('origin') == 'ai':
                            localized['hasAITranslation'] = True

                locale_records[locale][entity_id] = localized

        for locale, records in sorted(locale_records.items()):
            if locale == 'enUS' and kind in ('items', 'spells'):
                for entity_id, record in records.items():
                    if 'details' not in record:
                        continue

                    rules = rule_records.get(entity_id, {}).get('details', {})
                    record['details'] = {key: value for key, value in record['details'].items()
                                         if key not in rules or key == 'set'}

                    if 'set' in record['details']:
                        record['details']['set'] = {
                            key: value for key, value in record['details']['set'].items()
                            if key == 'name'
                        }

            write_localized_records(encoder, packs['ForeverRosettaStone_Data_' + locale], kind, locale, records)
            if dialogue_records is not None:
                dialogue_kind = 'questdialogue' if kind == 'quests' else 'npcdialogue'
                write_localized_records(encoder, packs['ForeverRosettaStone_Data_' + locale],
                                        dialogue_kind, locale, dialogue_records[locale])

        if rule_records:
            write_localized_records(encoder, packs['ForeverRosettaStone_Rules'], kind, 'shared', rule_records)
        if kind == 'globalstrings':
            # Search by the source key without decoding the complete label inventory at runtime.
            entries = sorted((record['name'], entity_id) for entity_id, record in rule_records.items())
            write_pages(encoder, packs['ForeverRosettaStone_Rules'], 'X-Rosetta-shared-globalstringkeys',
                        entries, lambda page: [[key for key, _ in page], [entity_id for _, entity_id in page]])
            # Native literal -> IDs, per locale pack: hover resolves one bounded page by binary
            # search instead of scanning the label inventory. Format strings are excluded.
            for locale in locales:
                literals = collections.defaultdict(list)
                for entity_id in ids:
                    text = catalog[str(entity_id)]['locales'].get(locale, {}).get('name')
                    normalized = normalize_client_literal(decode_client_escapes(text)) if isinstance(text, str) else ''
                    if normalized and CLIENT_LITERAL_LETTER.search(normalized) \
                            and not CLIENT_FORMAT.search(normalized):
                        literals[normalized].append(entity_id)
                if literals:
                    entries = sorted(literals.items(), key=lambda item: item[0].encode('utf-8'))
                    write_pages(encoder, packs['ForeverRosettaStone_Data_' + locale],
                                f'X-Rosetta-{locale}-globalstringtext', entries,
                                lambda page: [[text for text, _ in page], [found for _, found in page]])

    # Live reading identifies a book by its owner (bag item or world object), not by its title.
    # Item and object IDs are separate namespaces; an owner shared by several books stays unmapped.
    for owner_kind in ('item', 'object'):
        first_pages = collections.defaultdict(set)
        for entity_id, entity in combined['books'].items():
            if not has_english_text(entity, identity_field('books')):
                continue
            for owner in entity.get('owners', []):
                if owner.get('kind') == owner_kind and type(owner.get('id')) is int and owner['id'] > 0:
                    first_pages[owner['id']].add(int(entity_id))
        records = {owner_id: {'name': next(iter(found)), 'hasAITranslation': False}
                   for owner_id, found in first_pages.items() if len(found) == 1}
        if records:
            write_localized_records(encoder, packs['ForeverRosettaStone_Rules'], 'book' + owner_kind + 's',
                                    'shared', records)

    # A bind-location token carries a localized label, not an AreaTable ID. Index
    # its owned wording separately; runtime translation requires every matching
    # area's target label to agree and never returns an inferred area identity.
    for locale in locales:
        labels = collections.defaultdict(list)
        for entity_id, entity in combined['areas'].items():
            if not has_english_text(entity, 'name'):
                continue
            text = entity['locales'].get(locale, {}).get('name')
            if not isinstance(text, str) or not text:
                continue
            key = normalize_client_literal(text).replace('’', "'").replace('‘', "'")
            labels[key].append(int(entity_id))
        if labels:
            entries = sorted(labels.items(), key=lambda entry: entry[0].encode('utf-8'))
            write_pages(encoder, packs['ForeverRosettaStone_Data_' + locale],
                        f'X-Rosetta-{locale}-locationlabels', entries,
                        lambda page: [[text for text, _ in page], [sorted(ids) for _, ids in page]])

    # World-object tooltips carry only the native name (no GUID or ID), so object-owned books are
    # also indexed by their normalized client-language title. The runtime resolves a title only when
    # it names exactly one book; ambiguous or unknown names stay native.
    for locale in locales:
        titles = collections.defaultdict(set)
        for entity_id, entity in combined['books'].items():
            if not has_english_text(entity, identity_field('books')):
                continue
            if not any(owner.get('kind') == 'object' for owner in entity.get('owners', [])):
                continue
            text = entity['locales'].get(locale, {}).get('name')
            normalized = normalize_client_literal(text) if isinstance(text, str) else ''
            if normalized:
                # Vanilla and Forever clients differ in capitalization ("guerre" / "Guerre"), so the
                # key folds ASCII case only; the runtime applies the same fold.
                titles[re.sub(r'[A-Z]', lambda m: m.group().lower(), normalized)].add(int(entity_id))
        if titles:
            entries = sorted(((text, sorted(found)) for text, found in titles.items()),
                             key=lambda item: item[0].encode('utf-8'))
            write_pages(encoder, packs['ForeverRosettaStone_Data_' + locale],
                        f'X-Rosetta-{locale}-bookobjectnames', entries,
                        lambda page: [[text for text, _ in page], [found for _, found in page]])

    template = get_manifest(dev_debug)
    interface = re.search(rb'^## Interface: (.+)$', template, re.MULTILINE).group(1).decode('ascii')

    for directory in output.parent.parent.glob('ForeverRosettaStone_Source_*'):
        if directory.is_dir():
            expected = {directory.name + '.toc', 'data.lua'}

            if {path.name for path in directory.iterdir()} != expected or not (
                directory / 'data.lua'
            ).read_text().startswith('-- Generated by tools/build/build-lua-database.py.'):
                raise ValueError('Retired source pack contains unexpected files: ' + str(directory))

            for path in directory.iterdir():
                path.unlink()

            directory.rmdir()

    for name, pages in sorted(packs.items()):
        write_pack(output.parent.parent / 'ForeverRosettaStone_Data', name, version, pages, interface)

    encoder.write(sink, 'X-Rosetta-Packs', ','.join(sorted(packs)).encode('ascii'))

    generated = b'# Generated by tools/build/build-lua-database.py. Do not edit.\n'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(generated + b''.join(pieces) + b'\n' + template)

    return version, len(packs)


def get_manifest(dev_debug=False):
    template = Path(__file__).with_name('addon-manifest.toc').read_bytes()

    if dev_debug:
        template = template.replace(
            b'## SavedVariables: ForeverRosettaStoneSettings\n',
            b'## SavedVariables: ForeverRosettaStoneSettings, ForeverRosettaStoneDevTrace\n',
        )
        template = template.replace(b'core/safety.lua\n', b'diagnostics/dev-debug.lua\ncore/safety.lua\n', 1)
        template = template.replace(
            b'diagnostics/benchmark.lua\n',
            b'diagnostics/benchmark.lua\ndiagnostics/dev-benchmark.lua\ndiagnostics/dev-api-probe.lua\n', 1,
        )

    return template


def refresh_manifest(output, dev_debug=False):
    """Replace the load manifest while preserving existing generated database metadata."""
    metadata, separator, _ = output.read_bytes().partition(b'\n## Interface:')

    if not separator:
        raise ValueError(f'Cannot refresh manifest in {output}: missing ## Interface header')

    template = get_manifest(dev_debug)
    output.write_bytes(metadata + b'\n' + template)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--output', type=Path, default=Path('ForeverRosettaStone/ForeverRosettaStone.toc'))
    parser.add_argument(
        '--manifest-only', action='store_true',
        help='Preserve database metadata and refresh only the load manifest',
    )
    parser.add_argument(
        '--dev-debug', action='store_true',
        help='Enable local tooltip tracing and its SavedVariables; omitted from normal builds',
    )
    args = parser.parse_args()

    if args.manifest_only:
        refresh_manifest(args.output, args.dev_debug)
        print(f'Refreshed load manifest in {args.output}; database metadata preserved')
        return

    documents = load_catalogs(args.root)
    labels = documents.get('globalstrings', {}).get('catalogs', {}).get('globalstrings', {})
    # Every owned GlobalString ships: any native client line may need its translation.
    version, files = export_database(documents, args.output, args.dev_debug)
    print(f'GlobalStrings: {len(labels)} catalog records shipped')
    print(f'Generated {files} load-on-demand data addons; catalogVersion={version}')


if __name__ == '__main__':
    main()
