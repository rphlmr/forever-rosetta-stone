"""Reconstruct token boundaries from unanimous native template evidence.

This is offline source preparation, not runtime inference or a translation author.
The localized wording comes unchanged from the rendered provider response. Inferred
placeholders must retain explicit derivation metadata rather than raw-cache provenance.
"""
import re
from decimal import Decimal

TOKEN = re.compile(r'\$\{[^{}]+\}|\$\d*[sSmMdDtTuUbB]\d*')
NUMBER = re.compile(r'\d+(?:[.,]\d+)?')


def split(template):
    parts = TOKEN.split(template)
    tokens = TOKEN.findall(template)
    if not tokens or any('$' in part or NUMBER.search(part) for part in parts):
        raise ValueError('Unsupported syntax or literal quantities in template')
    return tokens, parts


def quantity(value):
    numbers = NUMBER.findall(value)
    if len(numbers) != 1:
        raise ValueError('Slot must contain exactly one visible quantity')
    return Decimal(numbers[0].replace(',', '.'))


def match_template(template, rendered):
    # Normalize the entire template first so whitespace next to a slot remains an anchor.
    normalized = re.sub(r'\s+', ' ', template)
    tokens, parts = split(normalized)
    pattern = re.escape(parts[0])
    for index, token in enumerate(tokens):
        pattern += f'(?P<v{index}>.+?)' + re.escape(parts[index + 1])
    match = re.fullmatch(pattern, re.sub(r'\s+', ' ', rendered))
    if not match:
        raise ValueError('Rendered provider text does not match native template')
    captures = [match.group(f'v{i}') for i in range(len(tokens))]
    for token, capture in zip(tokens, captures):
        quantity(capture)
        if not token.lower().endswith('d') and not NUMBER.fullmatch(capture):
            raise ValueError('Non-duration slot contains additional wording')
    return tokens, parts, captures


def infer_leading_percentage(known_templates, rendered, incomplete_templates):
    """Return templates only if all witnesses agree and each existing target tail matches.

    Supported gap: one missing leading percentage. Slot order, identities and API
    quantities must agree across every witness. Every existing target slot and all
    wording after its first slot must match that target's own prior native template.
    This prevents a positional guess when a target reorders the surviving quantities.
    """
    if len(known_templates) < 2 or not set(known_templates) <= set(rendered):
        raise ValueError('At least two independent native template locales are required')
    signature, values = None, None
    for locale, template in known_templates.items():
        tokens, parts, captures = match_template(template, rendered[locale])
        current = [quantity(value) for value in captures]
        if not parts[1].lstrip().startswith('%') or len(tokens) < 2:
            raise ValueError('Missing slot is not a leading percentage')
        if signature is not None and (tokens != signature or current != values):
            raise ValueError('Native template witnesses disagree')
        signature, values = tokens, current
    result = {}
    for locale, template in incomplete_templates.items():
        tokens, parts = split(re.sub(r'\s+', ' ', template))
        if tokens != signature[1:]:
            raise ValueError('Target is not missing exactly the leading token')
        text = rendered[locale]
        atoms = list(NUMBER.finditer(text))
        if [quantity(atom.group()) for atom in atoms] != values:
            raise ValueError('Target quantities or quantity order disagree with witnesses')
        if not text[atoms[0].end():].lstrip().startswith('%'):
            raise ValueError('Target leading quantity is not a percentage')
        # The surviving target tail independently establishes the positions and
        # duration unit span. All literal suffixes are anchored to owned wording.
        tail = ''
        for index, token in enumerate(tokens):
            capture = r'\d+(?:[.,]\d+)?'
            if token.lower().endswith('d'):
                capture += r'[^\d]*?'
            tail += f'(?P<v{index}>{capture})' + re.escape(parts[index + 1])
        suffix = re.sub(r'\s+', ' ', text[atoms[1].start():])
        match = re.fullmatch(tail, suffix)
        if not match or [quantity(match.group(f'v{i}')) for i in range(len(tokens))] != values[1:]:
            raise ValueError('Existing localized target tail does not match provider text')
        # Work on the provider's exact bytes; whitespace normalization is only a guard.
        original_tail = text[atoms[1].start():]
        tail_atoms = list(NUMBER.finditer(original_tail))
        replacements = [(atoms[0].start(), atoms[0].end(), signature[0])]
        for index, token in enumerate(tokens):
            atom = tail_atoms[index]
            end = atom.end()
            if token.lower().endswith('d'):
                # Recover exact duration boundaries using the final owned literal.
                if index != len(tokens) - 1 or not parts[-1]:
                    raise ValueError('Duration needs an unambiguous final literal boundary')
                end = len(original_tail) - len(parts[-1])
            replacements.append((atoms[1].start() + atom.start(), atoms[1].start() + end, token))
        for start, end, token in reversed(replacements):
            text = text[:start] + token + text[end:]
        recovered_tokens, _, captures = match_template(text, rendered[locale])
        if recovered_tokens != signature or [quantity(value) for value in captures] != values:
            raise ValueError('Recovered template does not reproduce provider text')
        result[locale] = text
    return result


def _single_condition(template):
    """Read one complete two-branch condition without interpreting its values."""
    if template.count('$?') != 1:
        raise ValueError('Exactly one condition is required')
    start = template.index('$?')
    opening = template.find('[', start)
    predicate = template[start + 2:opening]
    if opening < 0 or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', predicate):
        raise ValueError('Unsupported condition predicate')
    end = opening
    for _ in range(2):
        if end >= len(template) or template[end] != '[':
            raise ValueError('Missing condition branch')
        depth = 0
        for position in range(end, len(template)):
            depth += (template[position] == '[') - (template[position] == ']')
            if depth == 0:
                end = position + 1
                break
        else:
            raise ValueError('Unclosed condition branch')
    return template[start:end], predicate


def infer_conditional_grammar(known_templates, malformed):
    """Restore one unique delimiter/predicate boundary from unanimous native witnesses.

    No prose, branch value, predicate or token identity may be authored. This
    creates a normalized translation template, not a claim about how a broken
    client source renders. Such native garbage remains separate evidence.
    """
    if len(known_templates) < 2:
        raise ValueError('At least two independent native template locales are required')
    try:
        existing = _single_condition(malformed)
    except ValueError:
        existing = None
    if existing is not None:
        raise ValueError('Target already contains a complete condition')
    conditions = {_single_condition(template) for template in known_templates.values()}
    if len(conditions) != 1:
        raise ValueError('Native condition witnesses disagree')
    canonical, predicate = conditions.pop()
    prefix = '$?' + predicate
    if malformed.count('$?') != 1 or malformed.count(prefix) != 1:
        raise ValueError('Target predicate does not match native witnesses')
    start = malformed.index(prefix)
    candidates = set()
    opening = malformed.find('[', start)
    if opening >= 0:
        displaced = malformed[start + len(prefix):opening]
        # A predicate-boundary repair can move only literal prose. Operators,
        # numbers and other template syntax are not punctuation mistakes.
        if displaced and not re.search(r'[$\[\]0-9=<>!&|]', displaced):
            body = canonical[len(prefix):]
            if malformed.startswith(body, opening):
                candidates.add((malformed[:start] + displaced + canonical
                                + malformed[opening + len(body):], 'predicateLiteralBoundary'))
    for index, char in enumerate(canonical):
        if char != ']':
            continue
        shortened = canonical[:index] + canonical[index + 1:]
        if malformed.startswith(shortened, start):
            candidates.add((malformed[:start] + canonical + malformed[start + len(shortened):],
                            'missingBranchDelimiter'))
    if len(candidates) != 1:
        raise ValueError('No unique condition grammar repair')
    template, repair = candidates.pop()
    if _single_condition(template) != (canonical, predicate):
        raise ValueError('Reconstructed condition differs from native witnesses')
    return {'template': template, 'repair': repair, 'condition': canonical}
