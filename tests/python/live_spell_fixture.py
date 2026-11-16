"""Independent synthetic client text and expected translations, without formula evaluation.

Numeric slots receive controlled displayed values, unrelated to spell rules or character
stats. This verifies transport/localization, not Blizzard's calculation or linguistic quality.
Unsupported fixture grammar remains an explicit coverage limitation.
"""
import sys
import hashlib
import re
from dataclasses import dataclass
from functools import lru_cache

from database_harness import ROOT
sys.path.insert(0, str(ROOT))


def maintained_text(record, locale, field):
    entry = record.get('locales', {}).get(locale, {})
    return entry.get(field)



class FixtureUnavailable(Exception):
    def __init__(self, message, category='test_limitation', code='unsupported_live_fixture'):
        super().__init__(message)
        self.category, self.code, self.evidence = category, code, {}


@dataclass(frozen=True)
class Slot:
    owner: int
    raw: str
    shape: str
    index: int = 1
    duration: bool = False


@dataclass(frozen=True)
class Choice:
    owner: int
    predicates: tuple


@lru_cache(maxsize=1)
def duration_formats():
    from tools.catalogs.catalog_storage import load_catalog
    document = load_catalog(ROOT, 'globalstrings')['catalogs']['globalstrings']
    # Read the same format inventories as data, independently of the capture implementation.
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(encoding=None)
    addon = lua.table_from({b'itemTooltipLabels': lua.table()})
    files = ['tooltips/english-tooltip-formats.lua', 'tooltips/localized-tooltip-formats.lua',
             'database/localized-item-data.lua']
    files += ['locales/tooltips/' + name + '.lua' for name in
              ('cs-cz', 'da-dk', 'hr-hr', 'it-it', 'pl-pl', 'sv-se', 'tr-tr', 'uk-ua')]
    files += ['tooltips/tooltip-extra-formats.lua']
    for filename in files:
        lua.execute((ROOT / 'ForeverRosettaStone' / filename).read_bytes(), b'fixture', addon)
    result = {locale.decode(): {key.decode(): value.decode() for key, value in formats.items()}
              for locale, formats in addon.tooltipFormatsByLocale.items()}
    for record in document.values():
        key = record.get('key')
        for locale, entry in record.get('locales', {}).items():
            if entry.get('name'):
                result.setdefault(locale, {})[key] = entry['name']
    return result


def group(text, start, opening, closing):
    if text[start:start+1] != opening:
        raise FixtureUnavailable('malformed fixture group')
    depth = 0
    for end in range(start, len(text)):
        depth += (text[end] == opening) - (text[end] == closing)
        if depth == 0:
            return text[start+1:end], end+1
    raise FixtureUnavailable('unclosed fixture group')


def numeric_slot(owner, raw):
    simple = re.fullmatch(r'\$(\d*)([sSmMdDwWtTuUxXhniraAoObBeEfFvVqQpP])(\d*)', raw)
    if simple:
        reference, code, index = simple.groups()
        shape = 'duration' if code in 'dD' else 'maximum' if code == 'M' else 'amount' if code in 'sSmwW' else code
        return Slot(int(reference or owner), raw, shape, int(index or 1), code in 'dD')
    return Slot(owner, raw, raw)


def compile_nodes(spells, spell_id, locale, field, profile, source=False, active=()):
    identity = (int(spell_id), field)
    if identity in active or len(active) >= 12:
        raise FixtureUnavailable('cyclic or excessive fixture reference')
    record = spells.get(str(spell_id))
    if record is None:
        raise FixtureUnavailable('missing referenced spell', 'missing_data', 'missing_referenced_spell')
    entry = record.get('locales', {}).get(locale, {})
    text = maintained_text(record, locale, field) if source else entry.get(field)
    if not text:
        raise FixtureUnavailable('missing source template' if source else 'missing target translation',
                                 'missing_data', 'missing_source_template' if source else 'missing_target_translation')
    return parse(text, int(spell_id), locale, profile, spells, source, (*active, identity))


def parse(text, owner, locale, profile, spells, source, active):
    text = text.replace('\\r\\n', '\n').replace('\\n', '\n')
    nodes, offset = [], 0
    while offset < len(text):
        if text[offset] != '$':
            end = text.find('$', offset)
            end = len(text) if end < 0 else end
            nodes.append(text[offset:end]); offset = end
            continue
        rest = text[offset:]
        reference = re.match(r'\$@(spellname|spelldesc|spellaura)(?:<(\d+)>|(\d+))', rest)
        if reference:
            kind, bracket, plain = reference.groups(); reference_id = bracket or plain
            if kind == 'spellname':
                record = spells.get(reference_id, {})
                name = (maintained_text(record, locale, 'name') if source else
                        record.get('locales', {}).get(locale, {}).get('name'))
                if not name: raise FixtureUnavailable('missing referenced name', 'missing_data', 'missing_referenced_name')
                nodes.append(name)
            else:
                nodes.extend(compile_nodes(spells, reference_id, locale,
                    'description' if kind == 'spelldesc' else 'auraDescription', profile, source, active))
            offset += reference.end(); continue
        if rest.startswith('${'):
            _, end = group(rest, 1, '{', '}')
            precision = re.match(r'\.\d+', rest[end:])
            if precision: end += precision.end()
            nodes.append(numeric_slot(owner, rest[:end])); offset += end; continue
        if rest.startswith('$?'):
            branches, predicates, cursor = [], [], 1
            while rest[cursor:cursor+1] == '?':
                start = rest.find('[', cursor)
                if start < 0: raise FixtureUnavailable('malformed fixture condition')
                predicates.append(rest[cursor+1:start])
                branch, cursor = group(rest, start, '[', ']'); branches.append(branch)
            branch, cursor = group(rest, cursor, '[', ']'); branches.append(branch)
            # Numeric condition results are opaque displayed quantities, not calculated branches.
            if all(re.fullmatch(r'[+-]?\d+(?:[.,]\d+)?|\$(?:\{.*\}|\d*[a-zA-Z]+\d*|[*/].*|<\w+>)', b.strip()) for b in branches):
                nodes.append(Slot(owner, rest[:cursor], 'condition:' + ';'.join(predicates)))
            else:
                if source and len(set(branches)) != len(branches):
                    raise FixtureUnavailable('ambiguous fixture conditional branches')
                nodes.append(Choice(owner, tuple(predicates)))
                branch = branches[0 if profile == 'modified' else -1]
                nodes.extend(parse(branch, owner, locale, profile, spells, source, active))
            offset += cursor; continue
        grammar = re.match(r'\$([gGlL])([^;]*:[^;]*);', rest)
        if grammar:
            kind, forms = grammar.groups()
            nodes.append(forms.split(':')[1 if profile == 'modified' else 0] if kind.lower() == 'g'
                         else ('plural', tuple(forms.split(':'))))
            offset += grammar.end(); continue
        token = re.match(r'\$(?:[*/][\d.]+;\d*[a-zA-Z]\d*|\d+[*/][\d.]*;[a-zA-Z]\d*|<\w+>|j\d+[a-zA-Z]|[a-zA-Z][a-zA-Z0-9_]*|\d+[a-zA-Z]\d*)', rest)
        if not token: raise FixtureUnavailable('unsupported fixture token ' + rest[:30])
        raw = token.group()
        if not (re.fullmatch(r'\$\d*[sSmMdDwWtTuUxXhniraAoObBeEfFvVqQpP]\d*', raw)
                or raw.startswith(('$*', '$/', '$<', '$j'))
                or re.fullmatch(r'\$(?:PL|pl|AP|SPI|SPFI|SPH|SPA|SPS|SPFR|proccooldown|apm|rap|mcrit|bc|MW|mw|MWB|mwb|MWS|mws|ecim|RFR|RA|RF|RN|RS|ec\d+|skm?\d+|signw\d+)', raw)):
            raise FixtureUnavailable('unsupported fixture token ' + raw)
        nodes.append(numeric_slot(owner, raw)); offset += len(raw)
    return nodes


def slots(nodes):
    return list(dict.fromkeys(node for node in nodes if isinstance(node, Slot)))


def bindings(source, target, profile):
    if not {node for node in target if isinstance(node, Choice)}.issubset(
            {node for node in source if isinstance(node, Choice)}):
        raise FixtureUnavailable('target branch lacks a shared source predicate')
    previous_slot = False
    for node in source:
        if isinstance(node, Slot):
            if previous_slot:
                raise FixtureUnavailable('adjacent numeric fixture slots are ambiguous')
            previous_slot = True
        elif isinstance(node, str) and node:
            previous_slot = False
    left, right = slots(source), slots(target)
    values = {node: (17 if profile == 'baseline' else 31) +
              int(hashlib.sha256(f'{node.owner}:{node.raw}'.encode()).hexdigest()[:4], 16) % 47 for node in left}
    result = {}
    for key in {(node.owner, node.shape) for node in left+right}:
        a = sorted((n for n in left if (n.owner, n.shape) == key), key=lambda n: n.index)
        b = sorted((n for n in right if (n.owner, n.shape) == key), key=lambda n: n.index)
        if len(a) != len(b): raise FixtureUnavailable('incompatible source/target slot counts')
        if set(a) == set(b): result.update((n, values[n]) for n in b)
        else:
            if len({n.index for n in a}) != len(a) or len({n.index for n in b}) != len(b):
                raise FixtureUnavailable('ambiguous fixture slot indices')
            result.update((n, values[m]) for m, n in zip(a, b))
    return values, result


def plural(forms, amount, locale):
    if amount is None: raise FixtureUnavailable('fixture plural without quantity')
    if len(forms) == 2:
        return forms[0 if amount == 1 or amount == 0 and locale in ('frFR', 'ptBR') else 1]
    last, last_two = amount % 10, amount % 100
    if locale in ('ruRU', 'ukUA', 'hrHR'):
        index = 0 if last == 1 and last_two != 11 else 1 if 2 <= last <= 4 and not 12 <= last_two <= 14 else 2
    elif locale == 'plPL': index = 0 if amount == 1 else 1 if 2 <= last <= 4 and not 12 <= last_two <= 14 else 2
    elif locale == 'csCZ': index = 0 if amount == 1 else 1 if 2 <= amount <= 4 else 2
    else: raise FixtureUnavailable('unsupported fixture plural locale')
    return forms[index]


def render(nodes, values, locale, duration_key='INT_SPELL_DURATION_SEC'):
    output, previous = [], None
    for node in nodes:
        if isinstance(node, str):
            output.append(node)
            literal = re.search(r'(\d+)\s*$', node)
            if literal: previous = int(literal[1])
        elif isinstance(node, Slot):
            previous = values[node]
            if node.duration:
                template = duration_formats().get(locale, {}).get(duration_key)
                if not template: raise FixtureUnavailable('missing fixture duration format')
                template = re.sub(r'\|4([^;]+);', lambda m: plural(m[1].split(':'), previous, locale), template)
                output.append(re.sub(r'%[\d.$]*[dfsg]', str(previous), template))
            else: output.append(str(previous))
        elif not isinstance(node, Choice):
            output.append(plural(node[1], previous, locale))
    return normalize(''.join(output))


def normalize(text):
    return re.sub(r'[ \t\r\n]+', ' ', text.replace('\\r\\n', ' ').replace('\\n', ' ')).strip()


def make_fixture(spells, spell_id, target, profile='baseline', field='description', source=None):
    record = spells.get(str(spell_id))
    if not record: raise FixtureUnavailable('missing referenced spell', 'missing_data', 'missing_referenced_spell')
    if source is None:
        candidates = list(dict.fromkeys(['frFR', 'enUS', *record.get('locales', {})]))
        source = next((locale for locale in candidates if locale != target and
                       maintained_text(record, locale, field)), None)
        source = source or next((locale for locale in candidates if maintained_text(record, locale, field)), None)
    if not source: raise FixtureUnavailable('missing source template', 'missing_data', 'missing_source_template')
    left = compile_nodes(spells, spell_id, source, field, profile, source=True)
    right = compile_nodes(spells, spell_id, target, field, profile)
    values, translated = bindings(left, right, profile)
    duration_key = 'INT_SPELL_DURATION_SEC'
    if any(slot.duration for slot in slots(left)+slots(right)):
        formats = duration_formats()
        duration_key = next((key for key in ('INT_SPELL_DURATION_SEC', 'INT_GENERAL_DURATION_SEC', 'SECONDS_ABBR', 'D_SECONDS')
                             if formats.get(source, {}).get(key) and formats.get(target, {}).get(key)), None)
        if duration_key is None:
            raise FixtureUnavailable('missing fixture duration format', 'missing_data', 'missing_duration_format')
    return {'sourceLocale': source, 'native': render(left, values, source, duration_key),
            'expected': render(right, translated, target, duration_key), 'fixture': 'synthetic displayed values'}
