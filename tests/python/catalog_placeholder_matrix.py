"""Audit maintained text placeholders against original official-language fields."""

import collections
import re
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))
from tools.catalogs.official_text import OFFICIAL_LOCALES
TEXT_FIELDS = ('name', 'title', 'summary', 'description', 'auraDescription', 'rank',
               'nameDescription', 'setName', 'eventObjectiveLabel')
PRINTF = re.compile(r'%(?:(\d+)\$)?([\d.]*)([dscfg])')


def signature(text, kind):
    """Keep value identities, multiplicity, references and expressions; permit argument reordering."""
    tokens = WORK['get_quest_tokens'](text)
    # Argument positions refer to text order, not the sorted order of protected tokens.
    positions = {}
    for index, match in enumerate(PRINTF.finditer(text.replace('%%', '')), 1):
        positions.setdefault(match.group(), []).append(
            '%' + (match[1] or str(index)) + '$' + match[2] + match[3])
    result = []
    for token in tokens:
        # Plural inflection words may differ by language; nested value tokens remain protected.
        if token in ('$l', '$L'):
            continue
        if token in positions:
            token = positions[token].pop(0)
        if re.fullmatch(r'\|(?:[cC][0-9a-fA-F]{8}|cn[A-Z0-9_]+:|[rRnN])', token):
            continue
        result.append(token)
    return sorted(result)


def fields(record):
    result = {key: value for key in TEXT_FIELDS if isinstance(value := record.get(key), str) and value.strip()}
    for line in record.get('objectiveLines', []):
        if isinstance(line.get('text'), str) and line['text'].strip():
            result['objectiveLines.' + str(line['index'])] = line['text']
    return result


def audit_documents(documents):
    locales = documents['quests']['locales']
    counts = collections.Counter(cases=0, passed=0, failed=0, entities=0, placeholderFields=0)
    failures = []
    official_variations = []
    for catalog, document in documents.items():
        for kind, entities in document['catalogs'].items():
            for entity_id, entity in entities.items():
                counts['entities'] += 1
                records = entity.get('locales', {})
                texts = {locale: fields(record) for locale, record in records.items() if locale in locales}
                for field in sorted({field for values in texts.values() for field in values}):
                    values = {locale: record[field] for locale, record in texts.items() if field in record}
                    signatures = {}
                    invalid = set()
                    for locale, text in values.items():
                        try:
                            signatures[locale] = signature(text, kind)
                        except ValueError:
                            signatures[locale] = []
                            invalid.add(locale)
                    if not invalid and not any(signatures.values()):
                        continue
                    counts['placeholderFields'] += 1
                    originals = [locale for locale in values if locale in OFFICIAL_LOCALES
                                 and records[locale].get('translationMetadata', {}).get('fields', {})
                                 .get(field, {}).get('origin') == 'original']
                    originals.sort(key=lambda locale: (locale != 'enUS', locale))
                    baseline = originals[0] if originals else None
                    for locale in originals:
                        if baseline and locale not in invalid and signatures[locale] != signatures[baseline]:
                            official_variations.append({'catalog': catalog, 'entityKind': kind, 'id': int(entity_id),
                                'field': field, 'locale': locale, 'referenceLocale': baseline,
                                'referenceTokens': signatures[baseline], 'officialTokens': signatures[locale]})
                    for locale, actual in signatures.items():
                        counts['cases'] += 1
                        source_locale = records[locale].get('translationMetadata', {}).get('fields', {}) \
                            .get(field, {}).get('sourceLocale')
                        reference = (locale if locale in originals else source_locale
                                     if source_locale in originals else baseline)
                        reason = None
                        if locale in invalid:
                            reason = 'malformed placeholder syntax'
                        elif reference is None:
                            reason = 'no original official-language placeholder reference'
                        elif reference in invalid:
                            reason = 'malformed official-language placeholder reference'
                        elif actual != signatures[reference]:
                            reason = 'translation placeholder mismatch'
                        if reason is None:
                            counts['passed'] += 1
                            continue
                        counts['failed'] += 1
                        failures.append({'catalog': catalog, 'entityKind': kind, 'id': int(entity_id),
                                         'field': field, 'locale': locale, 'reason': reason,
                                         'sourceLocale': reference, 'expected': signatures.get(reference),
                                         'actual': actual, 'sourcePreview': values.get(reference, '')[:240],
                                         'actualPreview': values[locale][:240],
                                         'expectationDiagnostic': {
                                             'category': 'missing_data' if reason == 'translation placeholder mismatch'
                                             else 'test_limitation',
                                             'code': reason.replace(' ', '_').replace('-', '_')}})
    return {'kind': 'placeholders', 'counts': dict(counts), 'failures': failures,
            'officialVariations': official_variations,
            'scope': {'catalogs': sorted(documents), 'locales': locales, 'includesExcludedQuests': True,
                      'missingTranslations': 'Reported separately by the all-catalog completeness gate.',
                      'reference': 'Original fields in official client languages; AI text is never a reference.',
                      'comparison': 'Exact protected values, references and formulas with occurrence counts; '
                                    'printf arguments may move. Color codes and literal quest gender wording '
                                    'do not change the value contract. Each original official field retains its own '
                                    'tokens; differences between official locales are informational, not translation defects.'}}
