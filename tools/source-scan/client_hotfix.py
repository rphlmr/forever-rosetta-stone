"""Read build-matched Spell templates from native XFTH v9 hotfix captures.

This read-only developer tool never runs in the addon. XFTH layout and table
hashing follow wowdev/DBCD and wow.tools.local (MIT); field order is validated
against an explicitly supplied WoWDBDefs Spell definition for the exact build.
See THIRD-PARTY-NOTICES.md in this directory for upstream credits and licence.
"""
import struct
import re
from pathlib import Path


def table_hash(name):
    constants = (0x486E26EE, 0xDCAA16B3, 0xE1918EEF, 0x202DAFDB,
                 0x341C7DC7, 0x1C365303, 0x40EF2D37, 0x65FD5E49,
                 0xD6057177, 0x904ECE93, 0x1C38024F, 0x98FD323B,
                 0xE3061AE7, 0xA39B0FA1, 0x9797F25F, 0xE4444563)
    value, seed = 0x7FED7FED, 0xEEEEEEEE
    for char in name.upper().encode('ascii'):
        value = ((value + seed) ^ (constants[char >> 4] - constants[char & 15])) & 0xFFFFFFFF
        seed = (seed * 33 + value + char + 3) & 0xFFFFFFFF
    return value


def spell_records(cache, definition, build):
    """Return active rows with offsets/push IDs; fail closed on unknown layouts."""
    blocks = Path(definition).read_text().split('\n\n')
    matching = [block for block in blocks if any(
        build in line.removeprefix('BUILD ').split(', ')
        for line in block.splitlines() if line.startswith('BUILD '))]
    if len(matching) != 1:
        raise ValueError('Missing or ambiguous exact-build Spell definition')
    fields = [line for line in matching[0].splitlines()
              if line and not line.startswith(('LAYOUT ', 'BUILD ', 'COMMENT '))]
    if fields != ['$noninline,id$ID<32>', 'NameSubtext_lang', 'Description_lang', 'AuraDescription_lang']:
        raise ValueError('Unsupported Spell field layout')
    data = Path(cache).read_bytes()
    if len(data) < 44 or data[:4] != b'XFTH':
        raise ValueError('Invalid hotfix header')
    version, number = struct.unpack_from('<II', data, 4)
    if version != 9 or number != int(build.rsplit('.', 1)[1]):
        raise ValueError('Unsupported version or mismatched build')
    offset, entries = 44, []
    while offset < len(data):
        if offset + 32 > len(data) or data[offset:offset + 4] != b'XFTH':
            raise ValueError('Invalid hotfix entry header')
        region, push, unique, table, entity_id, size, status = struct.unpack_from('<iiiIiiB', data, offset + 4)
        if size < 0 or offset + 32 + size > len(data):
            raise ValueError('Truncated hotfix entry')
        if table == table_hash('Spell'):
            entries.append((push, offset, entity_id, status, data[offset + 32:offset + 32 + size]))
        offset += 32 + size
    result = {}
    for push, offset, entity_id, status, payload in sorted(entries, key=lambda row: row[0]):
        if status != 1 or not payload:
            result.pop(entity_id, None)
            continue
        strings = payload.split(b'\0')
        if len(strings) != 4 or strings[-1] != b'':
            raise ValueError('Invalid Spell string payload')
        result[entity_id] = dict(zip(('rank', 'description', 'auraDescription'),
                                    (text.decode('utf-8') for text in strings[:-1])))
        result[entity_id].update(pushID=push, offset=offset, payloadHex=payload.hex())
    return result


def sparse_item_records(cache, definition, build):
    """Decode ItemSparse's exact-build field layout, including variable UTF-8 strings."""
    schema = Path(definition).read_text()
    columns = {}
    for line in schema.split('\n\n', 1)[0].splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 2:
            columns[fields[1].split('?')[0]] = fields[0].split('<')[0]
    blocks = [block for block in schema.split('\n\n') if any(
        build in line.removeprefix('BUILD ').split(', ')
        for line in block.splitlines() if line.startswith('BUILD '))]
    if len(blocks) != 1:
        raise ValueError('Missing or ambiguous exact-build ItemSparse definition')
    fields = []
    for line in blocks[0].splitlines():
        if line.startswith(('LAYOUT ', 'BUILD ', 'COMMENT ')) or not line:
            continue
        match = re.fullmatch(r'(?:\$([^$]+)\$)?(\w+)(?:<(u?)(\d+)>)?(?:\[(\d+)\])?', line)
        if not match:
            raise ValueError('Unsupported ItemSparse field declaration')
        flags, name, unsigned, bits, count = match.groups()
        if flags:
            if flags != 'noninline,id':
                raise ValueError('Unsupported ItemSparse field flags')
            continue
        kind = columns.get(name)
        if kind not in ('int', 'float', 'locstring', 'string'):
            raise ValueError('Unsupported ItemSparse field type')
        fields.append((name, kind, unsigned == 'u', int(bits or 32), int(count or 1)))
    data = Path(cache).read_bytes()
    if len(data) < 44 or data[:4] != b'XFTH' or struct.unpack_from('<II', data, 4) != (9, int(build.rsplit('.', 1)[1])):
        raise ValueError('Invalid hotfix header or mismatched build')
    offset, entries = 44, []
    while offset < len(data):
        if offset + 32 > len(data) or data[offset:offset + 4] != b'XFTH':
            raise ValueError('Invalid hotfix entry header')
        _, push, _, table, entity_id, size, status = struct.unpack_from('<iiiIiiB', data, offset + 4)
        if size < 0 or offset + 32 + size > len(data):
            raise ValueError('Truncated hotfix entry')
        if table == table_hash('ItemSparse'):
            entries.append((push, offset, entity_id, status, data[offset + 32:offset + 32 + size]))
        offset += 32 + size
    result = {}
    for push, offset, entity_id, status, payload in sorted(entries, key=lambda row: row[0]):
        if status != 1 or not payload:
            result.pop(entity_id, None)
            continue
        cursor, row = 0, {}
        for name, kind, unsigned, bits, count in fields:
            values = []
            for _ in range(count):
                if kind in ('string', 'locstring'):
                    end = payload.find(b'\0', cursor)
                    if end < 0:
                        raise ValueError('Unterminated ItemSparse string')
                    value, cursor = payload[cursor:end].decode('utf-8'), end + 1
                else:
                    code = 'f' if kind == 'float' else {8: 'B' if unsigned else 'b',
                        16: 'H' if unsigned else 'h', 32: 'I' if unsigned else 'i',
                        64: 'Q' if unsigned else 'q'}.get(bits)
                    if code is None or cursor + struct.calcsize(code) > len(payload):
                        raise ValueError('Unsupported or truncated ItemSparse numeric field')
                    value = struct.unpack_from('<' + code, payload, cursor)[0]
                    cursor += struct.calcsize(code)
                values.append(value)
            row[name] = values if count > 1 else values[0]
        if cursor != len(payload):
            raise ValueError('ItemSparse payload does not match the exact-build schema')
        result[entity_id] = {'fields': row, 'pushID': push, 'offset': offset, 'payloadHex': payload.hex()}
    return result
