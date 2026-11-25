"""Shared reporting for bounded, catalog-backed template translation pilots."""

import sys
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tools.catalogs.catalog_storage import load_catalog
from tools.catalogs.official_text import OFFICIAL_LOCALES
from tools.catalogs.import_policy import OfficialEvidence, ai_block_reason


def load_records(kind, ids):
    return load_catalog(ROOT, kind, ids={kind: {str(value) for value in ids}})['catalogs'][kind]


def pilot_locales():
    targets = load_catalog(ROOT, 'quests', ids={})['locales']
    return sorted(OFFICIAL_LOCALES), list(targets)


def original_text(record, locale, field='name', allow_empty=False):
    localized = record.get('locales', {}).get(locale, {})
    text = localized.get(field)
    if not isinstance(text, str) or not allow_empty and not text.strip():
        raise ValueError(f'Missing catalog source: {locale}/{field}')
    return text


def field_value(record, field):
    if field.startswith('objectiveLines.'):
        index = int(field.split('.')[1])
        return next((line.get('text') for line in record.get('objectiveLines', []) if line['index'] == index), None)
    return record.get(field)


def plain(value):
    if isinstance(value, bytes):
        return value.decode('utf-8')
    if isinstance(value, tuple):
        return [plain(item) for item in value]
    return value


class PilotCases:
    """Retain every case, including passes, so enumeration can be audited."""

    policy_evidence = None

    @classmethod
    def configure_policy_database(cls, path=None, root=ROOT):
        cls.policy_evidence = None
        if path is not None:
            cls.policy_evidence = OfficialEvidence(path, root)

    def __init__(self, surface):
        self.surface = surface
        self.cases = []

    def apply_policy(self, identity, entity, field, kind, entity_id=None, source_required=False, allow_empty=False):
        """Record non-rendering cases explicitly; unknown missing data remains a failure."""
        locales = entity.get('locales', {})
        values = {locale: field_value(record, field) for locale, record in locales.items()}
        english, source, target = values.get('enUS'), identity['sourceLocale'], identity['targetLocale']
        blank = lambda text: not isinstance(text, str) or not text.strip()
        status = reason = None
        if not allow_empty and all(isinstance(values.get(locale), str) and not values[locale].strip()
                                   for locale in OFFICIAL_LOCALES):
            status, reason = 'not_applicable', 'all_official_sources_explicitly_empty'
        elif not allow_empty and not blank(english):
            if source_required and blank(values.get(source)):
                status, reason = 'warning', 'official_source_empty' if isinstance(values.get(source), str) else 'official_source_absent'
            elif target in OFFICIAL_LOCALES and blank(values.get(target)):
                status, reason = 'warning', 'official_target_empty' if isinstance(values.get(target), str) else 'official_target_absent'
            elif target not in OFFICIAL_LOCALES and blank(values.get(target)):
                if self.policy_evidence is not None and ai_block_reason(
                        target, kind, str(entity_id or identity['id']), field, english,
                        self.policy_evidence, quest=entity if kind == 'quests' else None) in (
                            'noVerifiedOfficialTranslation', 'noVerifiedClientObjectiveBinding'):
                    status, reason = 'allowed_absence', 'blocked_by_translation_policy'
        if status is None:
            return False
        self.cases.append({**identity, 'status': status, 'reason': reason, 'category': 'catalog_policy',
                           'expected': None, 'actual': None, 'sourceText': values.get(source),
                           'policyEvidence': {'kind': kind, 'id': entity_id or identity['id'], 'field': field,
                                              'english': english, 'officialValues': {loc: values.get(loc) for loc in sorted(OFFICIAL_LOCALES)},
                                              'targetValue': values.get(target),
                                              'database': str(self.policy_evidence.database) if status == 'allowed_absence' else None}})
        return True

    def check(self, identity, expected, actual, source_text=None, error=None, reason=None, category=None, allow_empty=False):
        expected, actual = plain(expected), plain(actual)
        if error:
            reason, category = reason or 'runtime error', 'addon_bug'
        elif reason:
            category = category or 'missing_data'
        elif expected is None or expected == '' and not allow_empty:
            reason, category = 'missing target expectation', 'missing_data'
        elif actual != expected:
            reason, category = 'rendered text differs from independent expectation', 'addon_bug'
        status = 'failed' if reason else 'passed'
        row = {**identity, 'status': status, 'expected': expected, 'actual': actual,
               'sourceText': plain(source_text)}
        if allow_empty:
            row['allowsEmptyValue'] = True
        if reason:
            row.update(reason=str(reason), category=category)
        if error:
            row['error'] = str(error)
        self.cases.append(row)
        return status == 'passed'

    def finish(self, selection):
        counts = Counter(cases=len(self.cases), passed=0, failed=0)
        for case in self.cases:
            counts[case['status']] += 1
        return {'surface': self.surface, 'selection': selection, 'counts': dict(counts), 'cases': self.cases}
