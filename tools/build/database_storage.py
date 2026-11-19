"""Write compressed column pages for lazy runtime ID lookup."""

import base64
import zlib

from tools.build.runtime_catalog import QUEST_FIELDS


PAGE_RECORD_LIMIT = 128
PAGE_BYTE_LIMIT = 64 * 1024


def pack_records(kind, entries):
    fields = (QUEST_FIELDS if kind == 'quests' else ('description',) if kind == 'bookpages'
              else ('dialogue',) if kind in ('questdialogue', 'npcdialogue')
              else ('name', 'details') if kind in ('items', 'spells', 'npcs', 'books', 'races') else ('name',))
    flags = bytearray((len(entries) + 7) // 8)

    for position, (_, record) in enumerate(entries):
        if record['hasAITranslation']:
            flags[position // 8] |= 1 << (position % 8)

    return [
        [entity_id for entity_id, _ in entries],
        *[{position: record[field] for position, (_, record) in enumerate(entries, start=1) if field in record}
          for field in fields],
        bytes(flags).rstrip(b'\x00'),
    ]


def write_pages(encoder, sink, prefix, entries, pack):
    """Bound each native decode by record count and encoded bytes, except a single oversized record."""
    starts = []

    def write_page(page):
        raw = encoder.serialize(pack(page))

        if len(raw) > PAGE_BYTE_LIMIT and len(page) > 1:
            middle = len(page) // 2
            write_page(page[:middle])
            write_page(page[middle:])
            return

        starts.append(page[0][0])
        encoder.write(sink, prefix + '-' + str(len(starts)), base64.b64encode(zlib.compress(raw, level=9)))

    for offset in range(0, len(entries), PAGE_RECORD_LIMIT):
        write_page(entries[offset:offset + PAGE_RECORD_LIMIT])

    if starts:
        encoder.write(sink, prefix + '-INDEX', encoder.encode(starts, compressed=True))


def write_localized_records(encoder, sink, kind, locale, records):
    prefix = f'X-Rosetta-{locale}-{kind}'
    write_pages(encoder, sink, prefix, sorted(records.items()), lambda entries: pack_records(kind, entries))
