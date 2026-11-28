"""Emulate WoW metadata and native encoding using QuestieDB's pinned Blizzard CBOR mock."""

import base64
import hashlib
import json
import os
import re
import zlib
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.build.database_packs import pack_directory


def catalog_record_ids(root, kind):
    """List existing entity files without opening their JSON."""
    # Both the Lua fixtures and spell shards only need names to determine their scope.
    with os.scandir(root / 'catalogs' / kind) as entries:
        return sorted(int(entry.name[:-5]) for entry in entries
                      if re.fullmatch(r'[1-9][0-9]*\.json', entry.name) and entry.is_file())


def install_globalstring_ids(lua, root=ROOT):
    """Supply the Lua fixtures with the current catalog's existing record IDs."""
    ids = catalog_record_ids(root, 'globalstrings')
    lua.globals()[b'FRS_TestGlobalStringIDs'] = lua.table_from(ids)
    return lua


class DatabaseMetadata(dict):
    """Expose stored pages for assertions while keeping their runtime loading independent."""

    def __init__(self, pack_root):
        super().__init__()
        self.pack_root = pack_root


def read_metadata(path, *, include_pages=False):
    metadata = DatabaseMetadata(path.parent.parent / 'ForeverRosettaStone_Data')

    for line in path.read_bytes().splitlines():
        if not line.startswith(b'## ') or b': ' not in line:
            continue

        key, value = line[3:].split(b': ', 1)
        assert len(line) <= 1023, f'TOC metadata line too long: {key!r}'
        assert key.lower() not in metadata, f'Duplicate metadata key: {key!r}'
        metadata[key.lower()] = value.strip()

    # Runtime replays load pack files through LoadAddOn. Only database contract tests
    # need a second, decoded inventory of their stored pages for direct inspection.
    if not include_pages:
        return metadata

    pack_names = metadata.get(b'x-rosetta-packs', b'')

    if pack_names.startswith(b'~'):
        pack_names = b''.join(metadata[b'x-rosetta-packs-' + str(index).encode()]
                              for index in range(1, int(pack_names[1:-1]) + 1))

    for name in pack_names.decode().split(','):
        if not name:
            continue

        source = (pack_directory(metadata.pack_root, name) / 'data.lua').read_text(encoding='ascii')

        for key, value in re.findall(r'^    \[("[^"]+")\] = ("[^"]*"),$', source, re.MULTILINE):
            key = json.loads(key).encode().lower()
            assert key not in metadata, f'Duplicate stored page: {key!r}'
            metadata[key] = json.loads(value).encode()

    return metadata


def install_metadata(lua, metadata, *, compiled_packs=None):
    codec = lua.execute((ROOT / 'tools/build/encoding/blizzard-cbor.lua').read_bytes())
    counts = {'base64': 0, 'inflate': 0, 'cbor': 0, 'decoded_bytes': 0, 'packs': []}
    loaded = set()

    def get_metadata(addon, key):
        if re.match(rb'x-rosetta-(?:[a-z]{4}|shared)-', key.lower()):
            return None

        return metadata.get(key.lower())

    def load_addon(name):
        if name in loaded:
            return lua.table_from([True])

        path = pack_directory(getattr(metadata, 'pack_root', ROOT / 'ForeverRosettaStone_Data'), name.decode()) / 'data.lua'

        if not path.is_file():
            return lua.table_from([False, b'MISSING'])

        source = path.read_bytes()
        if compiled_packs is None:
            lua.execute(source)
        else:
            # Share compiled code only. Each replay registers its own Lua tables.
            digest = hashlib.sha256(source).digest()
            cached = compiled_packs.get(path)
            if cached is None or cached[0] != digest:
                compile_pack = lua.eval(b'function(src, name) return string.dump(assert(loadstring(src, name))) end')
                cached = digest, compile_pack(source, b'@' + name + b'/data.lua')
                compiled_packs[path] = cached
            lua.execute(cached[1], mode='b')
        loaded.add(name)
        counts['packs'].append(name)
        return lua.table_from([True])

    def decode_base64(value):
        counts['base64'] += 1

        return base64.b64decode(value, validate=True)

    def decompress(value, method):
        assert method == 1
        counts['inflate'] += 1

        return zlib.decompress(value)

    def deserialize(value):
        counts['cbor'] += 1
        counts['decoded_bytes'] += len(value)

        return codec[b'DeserializeCBOR'](value)

    lua.globals().C_AddOns = lua.table_from({
        b'GetAddOnMetadata': get_metadata,
        b'LoadAddOn': lua.eval(b'''function(load)
            return function(name)
                local result = load(name)
                return result[1], result[2]
            end
        end''')(load_addon),
    })
    lua.globals().C_EncodingUtil = lua.table_from({
        b'DecodeBase64': decode_base64,
        b'DecompressString': decompress,
        b'DeserializeCBOR': deserialize,
    })

    return counts


def load_database(lua):
    load = lua.eval(b'function(source) assert(loadstring(source))("ForeverRosettaStone", {}) end')
    load((ROOT / 'ForeverRosettaStone/database/database-api.lua').read_bytes())

    return lua.globals().ForeverRosettaStoneDB
