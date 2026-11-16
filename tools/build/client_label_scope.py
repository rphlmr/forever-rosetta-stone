"""Derive shipping GlobalString keys from tooltip adapters and runtime key consumers."""

import re
from pathlib import Path


def tooltip_globalstring_keys(root, available):
    """Evaluate owned declarations, include direct consumers and expand runtime aliases."""
    from lupa.lua51 import LuaRuntime

    root, available = Path(root), set(available)
    addon_root = root / 'ForeverRosettaStone'
    lua = LuaRuntime()
    lua.execute('canaccessallvalues = function() return true end; GetLocale = function() return "enUS" end; '
                'addon = {itemTooltipLabels = {}, itemSubclasses = {}}')
    addon = lua.globals().addon
    declarations = [addon_root / (name + '.lua') for name in (
        'database/item-data', 'tooltips/english-tooltip-formats', 'tooltips/character-stat-formats',
        'tooltips/localized-tooltip-formats', 'database/localized-item-data',
        'locales/character-stat-locales')]
    declarations.extend(sorted((addon_root / 'locales/tooltips').glob('*.lua')))
    declarations.append(addon_root / 'tooltips/tooltip-extra-formats.lua')
    for path in declarations:
        if path.exists():
            lua.execute(path.read_text(), 'scope', addon)
    keys = set()
    for name in ('englishTooltipFormats', 'itemTooltipLabels'):
        values = addon[name]
        if values is not None:
            keys.update(values.keys())
    for name in ('tooltipFormatsByLocale', 'characterStatFormats'):
        values = addon[name]
        if values is not None:
            for locale_values in values.values():
                keys.update(locale_values.keys())

    manifest = addon_root / 'ForeverRosettaStone.toc'
    paths = [addon_root / line.strip() for line in manifest.read_text().splitlines()
             if line.strip().endswith('.lua') and not line.startswith('#')]
    runtime = []
    for path in paths:
        source = path.read_text()
        source = re.sub(r'--\[\[.*?\]\]', '', source, flags=re.S)
        source = re.sub(r'--[^\n]*', '', source)
        literals = re.findall(r'["\']([A-Z][A-Z0-9_]+)["\']', source)
        keys.update(literals)
        unquoted = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '', source)
        keys.update(re.findall(r'\b[A-Z][A-Z0-9_]+\b', unquoted))
        keys.update(re.findall(r'\b_G\.([A-Z][A-Z0-9_]+)', source))
        if not path.is_relative_to(addon_root / 'locales'):
            runtime.append(source)
    source = '\n'.join(runtime)
    # Explicitly constructed key families, such as RESISTANCE .. index .. _NAME.
    expression = r'"([A-Z][A-Z0-9_]+)"\s*\.\.\s*[\w.]+\s*\.\.\s*"([A-Z0-9_]+)"'
    for prefix, suffix in re.findall(expression, source):
        keys.update(key for key in available if key.startswith(prefix) and key.endswith(suffix))
    for prefix in re.findall(r'"([A-Z][A-Z0-9_]+)"\s*\.\.\s*[\w.]+', re.sub(expression, '', source)):
        keys.update(key for key in available if key.startswith(prefix))
    # Appearance tooltips receive slot label keys from Blizzard's owner.slot field.
    if 'owner.slot' in source and 'appearanceSlot' in source:
        keys.update(key for key in available if re.fullmatch(r'[A-Z]+SLOT', key))
    # Index() constructs profession aliases of known tooltip keys, never an entire locale scan.
    aliases = re.findall(r'"((?:CHARACTER_)?PROFESSIONS?_)"', source)
    base = set(keys)
    for prefix in aliases:
        keys.update(prefix + key for key in base if prefix + key in available)
    return keys & available


def scope_globalstring_documents(documents, root):
    """Use the same import, job, diagnostic and shipping boundary."""
    document = documents.get('globalstrings')
    if not document:
        return documents
    entities = document['catalogs']['globalstrings']
    keys = tooltip_globalstring_keys(root, {r['key'] for r in entities.values()})
    return {**documents, 'globalstrings': {**document, 'catalogs': {'globalstrings': {
        entity_id: entity for entity_id, entity in entities.items() if entity['key'] in keys}}}}
