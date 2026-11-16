"""Parse literal Lua data without executing downloaded addon code."""
import re

LONG = re.compile(r'\[(=*)\[')
TOKEN = re.compile(r'0[xX][0-9a-fA-F]+|\d+(?:\.\d+)?|[A-Za-z_]\w*|\.\.')
DECIMAL = re.compile(r'\d{1,3}')


def tokenize(text):
    index = 0
    while index < len(text):
        char = text[index]
        if char.isspace():
            index += 1
            continue
        comment = text.startswith('--', index)
        start = index + 2 if comment else index
        match = LONG.match(text, start)
        if match:
            marker = ']' + match[1] + ']'
            end = text.find(marker, match.end())
            if end < 0:
                raise ValueError('Unterminated Lua long string/comment')
            if not comment:
                value = text[match.end():end]
                if value.startswith('\r\n'):
                    value = value[2:]
                elif value.startswith(('\n', '\r')):
                    value = value[1:]
                yield ('string', value.replace('\r\n', '\n'))
            index = end + len(marker)
        elif comment:
            end = text.find('\n', index)
            index = len(text) if end < 0 else end + 1
        elif char in ('"', "'"):
            quote, value = char, bytearray()
            index += 1
            escapes = {'a': '\a', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v'}
            while index < len(text) and text[index] != quote:
                if text[index] != '\\':
                    value.extend(text[index].encode())
                    index += 1
                    continue
                index += 1
                if index >= len(text):
                    raise ValueError('Unterminated Lua escape')
                escaped = text[index]
                if escaped.isdigit():
                    match = DECIMAL.match(text, index)
                    value.append(int(match[0]))
                    index = match.end()
                elif escaped in escapes or escaped in ('\\', '"', "'", '\n'):
                    value.extend(escapes.get(escaped, escaped).encode())
                    index += 1
                else:
                    # Lua 5.1 treats an otherwise unrecognized escape as that character.
                    value.extend(escaped.encode())
                    index += 1
            if index >= len(text):
                raise ValueError('Unterminated Lua string')
            yield ('string', value.decode())
            index += 1
        else:
            match = TOKEN.match(text, index)
            value = match[0] if match else char
            index += len(value)
            if value[0].isdigit():
                yield ('number', float(value) if '.' in value else int(value, 16) if value.lower().startswith('0x') else int(value))
            else:
                yield ('symbol', value)


class Reader:
    def __init__(self, text, allow_duplicates=False):
        self.allow_duplicates = allow_duplicates
        self.tokens = list(tokenize(text))
        self.index = 0

    def symbol(self, value, offset=0):
        return self.index + offset < len(self.tokens) and self.tokens[self.index + offset] == ('symbol', value)

    def expect(self, value):
        if not self.symbol(value):
            raise ValueError('Expected Lua ' + value)
        self.index += 1

    def literal(self, depth=0):
        if depth > 40 or self.index >= len(self.tokens):
            raise ValueError('Malformed/deep Lua literal')
        kind, value = self.tokens[self.index]
        self.index += 1
        if kind in ('number', 'string'):
            result = value
        elif value in ('nil', 'true', 'false'):
            result = {'nil': None, 'true': True, 'false': False}[value]
        elif value == '-':
            result = self.literal(depth + 1)
            if type(result) not in (int, float):
                raise ValueError('Invalid Lua negation')
            result = -result
        elif value == '{':
            result, position = {}, 1
            while not self.symbol('}'):
                if self.symbol('['):
                    self.index += 1
                    key = self.literal(depth + 1)
                    self.expect(']')
                    self.expect('=')
                elif self.index + 1 < len(self.tokens) and self.symbol('=', 1):
                    key = self.tokens[self.index][1]
                    self.index += 2
                else:
                    key, position = position, position + 1
                if key in result and not self.allow_duplicates:
                    raise ValueError('Duplicate Lua literal key')
                result[key] = self.literal(depth + 1)
                if self.symbol(',') or self.symbol(';'):
                    self.index += 1
                elif not self.symbol('}'):
                    raise ValueError('Non-literal expression in Lua table')
            self.index += 1
        else:
            raise ValueError('Non-literal Lua expression')
        while self.symbol('..'):
            self.index += 1
            other = self.literal(depth + 1)
            if not isinstance(result, str) or not isinstance(other, str):
                raise ValueError('Invalid Lua concatenation')
            result += other
        return result


def assignments(text, roots, allow_duplicates=False):
    reader = Reader(text, allow_duplicates)
    names = {root[0] for root in roots}
    while reader.index < len(reader.tokens):
        start = reader.index
        kind, name = reader.tokens[start]
        reader.index += 1
        if kind != 'symbol' or name not in names:
            continue
        path, dynamic = [name], False
        while reader.symbol('.') or reader.symbol('['):
            if reader.symbol('.'):
                reader.index += 1
                if reader.index >= len(reader.tokens):
                    raise ValueError('Incomplete Lua assignment')
                path.append(reader.tokens[reader.index][1])
                reader.index += 1
            else:
                reader.index += 1
                if reader.index >= len(reader.tokens) or (reader.tokens[reader.index][0] not in ('number', 'string') and not reader.symbol('-')):
                    dynamic = True
                    break
                path.append(reader.literal())
                reader.expect(']')
        target = next((root for root in roots if tuple(path[:len(root)]) == root), None)
        if dynamic or not target or not reader.symbol('='):
            reader.index = start + 1
            continue
        lhs = reader.tokens[start:reader.index]
        reader.index += 1
        # A literal fallback initializes an existing table/field without executing expressions.
        if reader.tokens[reader.index:reader.index + len(lhs)] == lhs and reader.symbol('or', len(lhs)):
            reader.index += len(lhs) + 1
        if reader.index < len(reader.tokens) and (reader.tokens[reader.index][0] in ('number', 'string') or reader.tokens[reader.index][1] in ('{', '-', 'nil', 'true', 'false')):
            yield path, reader.literal()
        elif len(path) > len(target):
            raise ValueError('Non-literal selected Lua assignment')
        else:
            reader.index = start + 1
