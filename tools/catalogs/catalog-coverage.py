"""Report catalog text presence by locale against the maintained English inventory."""

import argparse
import json
import runpy
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.catalogs.catalog_storage import CATALOGS, canonical_locales, load_catalog
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES


ROOT = Path(__file__).resolve().parents[2]
KINDS = CATALOGS


def get_text(entity, locale, field):
    localized = entity['locales'].get(locale, {})
    tooltip = entity.get('tooltipData', {})

    if field == 'set.name':
        item_set = tooltip.get('set', {})
        return localized.get('setName') or (item_set.get('name') if locale == 'enUS' else None)

    return localized.get(field)


def count_fields(entities, locales, field):
    eligible = [entity for entity in entities if get_text(entity, 'enUS', field)]

    return {
        'eligible': len(eligible),
        'present': {locale: sum(bool(get_text(entity, locale, field)) for entity in eligible) for locale in locales},
        'uniqueMissingEnglishTexts': {
            locale: len({get_text(entity, 'enUS', field) for entity in eligible if not get_text(entity, locale, field)})
            for locale in locales
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, help='Write the generated JSON report to this path.')
    parser.add_argument('--require-complete', action='store_true', help='Fail if any inventoried target field is absent.')
    arguments = parser.parse_args()
    documents = {kind: load_catalog(ROOT, kind) for kind in KINDS}
    translation_work = runpy.run_path(str(ROOT / 'tools/catalogs/translation-work.py'))
    native_fallbacks = translation_work['create_fallback_queue'](documents)
    locales = canonical_locales(documents['quests']['locales'])
    report = {'method': {
        'locales': locales,
        'names': 'All retained entities, regardless of English name presence.',
        'otherFields': 'Entities with nonempty English field; presence is not translation quality.',
        'objectiveLines': 'English client indices with nonempty text; compared by index.',
        'questExclusions': sorted(EXCLUDED_QUEST_STATUSES),
        'tooltipSources': 'Includes source-locale templates; excludes Italian tooltip sources copied from English.',
        'nativeEnglishFallbacks': 'Excluded from target presence unless reviewed shared wording, proper names, '
                                 'or explicit structural/technical invariants. Raw native templates remain intact.',
    }, 'catalogs': {}}

    for document in documents.values():
        for kind, records in document['catalogs'].items():
            entities = [entity for entity in records.values() if kind != 'quests'
                        or entity.get('usageStatus') not in EXCLUDED_QUEST_STATUSES]
            result = {'entities': len(entities), 'excluded': len(records) - len(entities), 'fields': {}}
            result['unavailableNameSources'] = [entity_id for entity_id, entity in records.items()
                if kind != 'quests' and not any(value.get('name') for value in entity['locales'].values())]
            fields = ('title', 'summary', 'description', 'eventObjectiveLabel') if kind == 'quests' else ('name',)

            for field in fields:
                if field == 'name':
                    result['fields'][field] = {'eligible': len(entities), 'present': {
                        locale: sum(bool(get_text(entity, locale, 'name')) for entity in entities)
                        for locale in locales
                    }}
                else:
                    result['fields'][field] = count_fields(entities, locales, field)

            if kind == 'quests':
                indices = [(entity, line['index']) for entity in entities
                           for line in entity['locales'].get('enUS', {}).get('objectiveLines', []) if line.get('text')]
                result['fields']['objectiveLines'] = {'eligible': len(indices), 'present': {
                    locale: sum(any(line.get('index') == index and line.get('text')
                                    for line in entity['locales'].get(locale,
                                                                    {}).get('objectiveLines', []))
                    for entity, index in indices) for locale in locales
                }}

            if kind in ('items', 'spells'):
                detail_fields = ('description', 'auraDescription', 'rank') if kind == 'spells' else (
                    'description', 'nameDescription', 'set.name')

                for field in detail_fields:
                    result['fields'][field] = count_fields(entities, locales, field)

            report['catalogs'][kind] = result

    for job in native_fallbacks['jobs']:
        for pointer in job['pointers']:
            field = pointer['field'].removeprefix('tooltip.')
            report['catalogs'][pointer['kind']]['fields'][field]['present'][job['locale']] -= 1

    missing = []

    for kind, catalog in report['catalogs'].items():
        for field, coverage in catalog['fields'].items():
            for locale, present in coverage['present'].items():
                if present < coverage['eligible']:
                    missing.append({'catalog': kind, 'field': field, 'locale': locale,
                                    'missing': coverage['eligible'] - present})

    report['completeness'] = {
        'complete': not missing,
        'missingFieldEntries': sum(entry['missing'] for entry in missing),
        'untranslatedNativeFallbackFields': sum(len(job['pointers']) for job in native_fallbacks['jobs']),
        'gaps': missing,
        'limit': 'Text presence only; this does not verify translation quality or live game rendering.',
    }
    rendered = json.dumps(report, ensure_ascii=False, indent=2)

    if arguments.output:
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(rendered + '\n', encoding='utf-8')
    else:
        print(rendered)

    return 1 if arguments.require_complete and missing else 0


if __name__ == '__main__':
    raise SystemExit(main())
