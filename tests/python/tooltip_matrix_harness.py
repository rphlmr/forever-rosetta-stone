"""Shared independent synthetic tooltip template fixtures."""

import hashlib
import re

from tools.build.runtime_catalog import get_tooltip_source_text, project_tooltip_details

spells = {}

class UnsupportedFixture(Exception):
    """A format or missing catalog field the independent fixture renderer cannot supply."""


fixture_duration = None
fixture_duration_value = None
fixture_numeric = None
fixture_seen = None
fixture_area = None
TOKEN_PATTERN = re.compile(r'\$(?:\$\d+[sSmMoOtTaAbBxXnNuUhHiIrRdDqQeEvVwWfFpPcC]\d*'
                           r'|\d+[/*];\d*[sSmMoOtTaAbBxXnNuUhHiIrRdDqQeEvVwWfFpPcC]\d*|rad#'
                           r'|@[a-zA-Z]+|\?|[lLgG](?=[^;]*;)|\{[^}]*\}(?:\.\d+)?'
                           r'|[/*][\d.]+;\d*[a-zA-Z]\d*|<[^>]*>|\d*[a-zA-Z]+\d*|[^\s])')


def get_token_families(template):
    without_level_predicates = re.sub(r'(?<=\?)\$pl(?=[<>]=?\d+\[)', '', template)
    tokens = TOKEN_PATTERN.findall(without_level_predicates)
    return {'${...}' if token.startswith('${') else re.sub(r'\d+', '#', token) for token in tokens}


assert '$pl' not in get_token_families('$?$pl>=55[$s1][${340+($pl-46)*12}]')
assert '$PL' in get_token_families('Level $PL target')


def get_fixture_binding(spell_id, token):
    effect = re.fullmatch(r'(\$(?:[/*][\d.]+;)?)(\d*)([sSmMoOtTaAxX])(\d*)', token)
    if effect:
        prefix, reference, code, index = effect.groups()
        token = prefix + reference + code + (index or '1')
    return str(spell_id) + ':' + token


def read_group(text, start, opening, closing):
    """Read a balanced group from a trusted catalog template."""
    if start >= len(text) or text[start] != opening:
        raise UnsupportedFixture('malformed group')

    depth = 1

    for index in range(start + 1, len(text)):
        depth += (text[index] == opening) - (text[index] == closing)

        if depth == 0:
            return text[start + 1:index], index + 1

    raise UnsupportedFixture('unclosed group')


def render_fixture(text, spell_id, locale, known, depth=0, native=False):
    """Produce a client snapshot and the set of numeric fields used by that snapshot."""
    if depth > 8:
        raise UnsupportedFixture('reference depth')

    output, fields, offset, previous = [], set(), 0, None

    while offset < len(text):
        if text[offset] != '$':
            output.append(text[offset])
            offset += 1
            continue

        rest = text[offset:]
        if fixture_seen is not None:
            token = TOKEN_PATTERN.match(rest)
            if token:
                fixture_seen.update(get_token_families(token.group()))
                if token.group() in ('$g', '$G'):
                    fixture_seen.add(token.group())
        grammar = re.match(r'\$([lLgG])([^;]+);', rest)

        if grammar:
            kind, forms = grammar.groups()
            literal_count = re.search(r'(?:^|\s)(\d+)\s+$', ''.join(output))
            if kind.lower() == 'l' and literal_count:
                previous = int(literal_count.group(1))
            choices = forms.split(':')
            if len(choices) < 2:
                raise UnsupportedFixture('malformed grammar')
            single, multiple = choices[:2]
            index = 0 if (known if kind.lower() == 'g' else previous == 1) else 1
            if kind.lower() == 'l' and len(choices) == 3:
                if previous is None:
                    raise UnsupportedFixture('plural without number')
                if locale in ('ruRU', 'ukUA', 'hrHR'):
                    last, last_two = previous % 10, previous % 100
                    index = 0 if last == 1 and last_two != 11 else (
                        1 if 2 <= last <= 4 and not 12 <= last_two <= 14 else 2)
                elif locale == 'plPL':
                    index = 0 if previous == 1 else (1 if 2 <= previous % 10 <= 4 and
                                                     not 12 <= previous % 100 <= 14 else 2)
                elif locale == 'csCZ':
                    index = 0 if previous == 1 else (1 if 2 <= previous <= 4 else 2)
                else:
                    raise UnsupportedFixture('unsupported three-form plural')
            neutral = { 'his:her': 'their', 'His:Her': 'Their', 'he:she': 'they',
                        'He:She': 'They', 'him:her': 'them', 'Him:Her': 'Them',
                        'himself:herself': 'themself', 'Himself:Herself': 'Themself' }.get(single + ':' + multiple)
            output.append(neutral if not native and locale == 'enUS' and kind.lower() == 'g' and neutral else choices[index])
            offset += grammar.end()
            continue

        if rest.startswith('$@expandkey['):
            section, finish = read_group(text, offset + len('$@expandkey'), '[', ']')
            rendered, nested_fields = render_fixture(section if known else '', spell_id, locale, known, depth + 1, native)
            output.append(rendered)
            fields.update(nested_fields)
            offset = finish
            continue

        if rest.startswith('$?'):
            cursor, branches, conditions = offset + 1, [], []

            while text[cursor:cursor + 1] == '?':
                start = text.find('[', cursor)
                conditions.append(text[cursor + 1:start].strip())
                branch, cursor = read_group(text, start, '[', ']')
                branches.append(branch)

            fallback, cursor = read_group(text, cursor, '[', ']')
            selected = fallback

            for condition, branch in zip(conditions, branches):
                comparison = re.fullmatch(r'\$[pP][lL]([<>]=?)(\d+)', condition)
                if not comparison and not re.fullmatch(
                    r'(?:s\d+|(?:a\d+)(?:\|a\d+)*|(?:pc|p|\$p)\d+|\$w=\d+)', condition
                ):
                    raise UnsupportedFixture('unsupported conditional ' + condition[:50])
                matches = known

                if condition.startswith('$w='):
                    key = str(spell_id) + ':$w'
                    amount = 1 if known else 2 + int(hashlib.sha256(key.encode()).hexdigest()[:4], 16) % 47
                    matches = amount == int(condition[3:])

                if comparison:
                    operator, threshold = comparison.groups()
                    level, threshold = 60 if known else 5, int(threshold)
                    matches = {'<': level < threshold, '>': level > threshold,
                               '<=': level <= threshold, '>=': level >= threshold}[operator]

                if matches:
                    selected = branch
                    break
            rendered, nested_fields = render_fixture(selected, spell_id, locale, known, depth + 1, native)
            output.append(rendered)
            fields.update(nested_fields)
            if rendered.isdigit():
                previous = int(rendered)
            offset = cursor
            continue

        reference = re.match(r'\$@(spellname|spelldesc|spellicon|spellaura)(?:<(\d+)>|(\d+))', rest)

        if reference:
            kind, bracket_id, plain_id = reference.groups()
            referenced_id = bracket_id or plain_id
            record = spells.get(referenced_id, {})

            if kind == 'spellicon':
                output.append(f'|T{int(referenced_id) + 100000}:16:16|t')
            elif kind == 'spellname':
                if not record:
                    raise UnsupportedFixture('missing referenced spell')
                name = (get_tooltip_source_text(record, locale, 'name') if native else
                        record.get('locales', {}).get(locale, {}).get('name'))

                if not name:
                    raise UnsupportedFixture('missing localized reference name')

                output.append(name)
            else:
                if not record:
                    raise UnsupportedFixture('missing referenced spell')
                field = 'auraDescription' if kind == 'spellaura' else 'description'
                original = record.get('locales', {}).get(locale, {})
                description = (get_tooltip_source_text(record, locale, field)
                               if native else project_tooltip_details(record, original, locale).get(field))
                if native and not description:
                    description = get_tooltip_source_text(record, 'enUS', field)

                if not description:
                    raise UnsupportedFixture('missing referenced description')

                rendered, nested_fields = render_fixture(description, referenced_id, locale, known, depth + 1, native)
                output.append(rendered)
                fields.update(nested_fields)

            offset += reference.end()
            continue

        if rest.startswith('$z') and fixture_area is not None:
            name = fixture_area(locale, native)
            if not name:
                raise UnsupportedFixture('missing localized area name')
            fields.add(str(spell_id) + ':$z')
            output.append(name)
            offset += 2
            continue

        if rest.startswith('${'):
            _, finish = read_group(rest, 1, '{', '}')
            precision = re.match(r'\.\d+', rest[finish:])
            token = rest[:finish + (precision.end() if precision else 0)]
            code = 'expression'
        else:
            opaque_match = re.match(
                r'\$(?:\$\d+[sSmMoOtTaAbBxXnNuUhHiIrRdDqQeEvVwWfFpPcC]\d*'
                r'|\d+[/*];\d*[sSmMoOtTaAbBxXnNuUhHiIrRdDqQeEvVwWfFpPcC]\d*|rad#|\d+(?![a-zA-Z\d]))', rest)
            token_match = opaque_match or re.match(
                r'\$(?:[/*][\d.]+;\d*[sSmMoOtTaAbBxXnNuUhHiIrRdDqQeEvVwWfFpPcC]\d*'
                r'|<[\w]+>|proccooldown|ecim|ec\d+|sk\d+|PL|RFR|R[AFNS]'
                r'|\d*[sSmMoOtTaAbBxXnNuUhHiIrRdDqQeEvVwWfFpPcC]\d*)(?![a-zA-Z\d])', rest)

            if not token_match:
                token_match = re.match(r'\$(?:\d*[dD]\d*(?=lang\b|Sek\b)|\d+[dD](?=s\b)|[eE](?=fache\b))', rest)

            if not token_match:
                raise UnsupportedFixture('unsupported token ' + rest.split()[0][:50])

            token = token_match.group()
            code = 'd' if re.fullmatch(r'\$\d*[dD]\d*', token) else 'number'

        key = get_fixture_binding(spell_id, token)
        fields.add(key)
        previous = 1 if known else 2 + int(hashlib.sha256(key.encode()).hexdigest()[:4], 16) % 47
        if code == 'd' and fixture_duration_value is not None:
            previous = fixture_duration_value
        output.append(fixture_duration(locale, native) if code == 'd' and fixture_duration else (
            f'{previous} sec' if code == 'd' else fixture_numeric(locale, native) if fixture_numeric else str(previous)))
        offset += len(token)

    return ''.join(output), fields
