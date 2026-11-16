"""Create and validate deduplicated, provenance-aware translation work queues."""

import argparse
import collections
import difflib
import hashlib
import json
import re
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tools.catalogs.catalog_storage import (CATALOGS, canonical_locales, dump_json, get_entity_path, load_catalog,
                             load_catalogs, parse_json, read_json)
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES, get_tooltip_source_text


ROOT = Path(__file__).resolve().parents[2]
SOURCE_CLIENT_LOCALES = frozenset(('enUS', 'frFR', 'deDE', 'esES', 'esMX', 'itIT',
                                 'ptBR', 'ruRU', 'koKR', 'zhCN', 'zhTW'))
QUEST_FIELDS = ('title', 'summary', 'description', 'eventObjectiveLabel')
TOKEN = re.compile(
    r'%(?:\d+\$)?[\d.]*[dscfg](?![A-Za-z])|%%|%'
    r'|\$(?:\$\d+[A-Za-z]\d*|\d+[/*];\d*[A-Za-z]\d*|rad#|\{[^}]*\}(?:\.\d+)?|<[^>]*>|\?[^\[\s]+|[/*][\d.]+;\d*[A-Za-z]\d*'
    r'|@[A-Za-z]+(?:<\d+>|\d*)|[gGlL]|(?:proccooldown|ecim|ec\d+|sk\d+|PL|RFR|R[AFNS])'
    r'|\d+o[A-Za-z]|\d*[A-Za-z]\d*|\d+|.)'
    r'|\|[TA][^|]*\|[ta]|\|H[^|]*\|h'
    r'|\|(?:cn[A-Z0-9_]+:|[cC][0-9a-fA-F]{8}|[rRnN]|4|[HhTtAa]|[KkEe])'
    r'|\{[\w.]+\}|<(?:name|class|race|NO LOG DESCRIPTION)>'
    r'|(?<=\])\?[^\[\s]+(?=\[)'
)
TECHNICAL_NAMES = frozenset((
    '!deepS', '1d6', 'AEDM', 'AOD', 'CHECKMEOUT', 'ClearAllo', 'DNT', 'DO NOT TRANSLATE',
    'DONOTREUSE', 'GGOODMANTEST', 'Kev', 'MHTest01', 'MHTest02', 'MHTest03', 'NefTest',
    'RAF', 'Revall', 'Sol H', 'Sol L', 'Sol M', 'Sol U', 'TESTT', 'TWEEP', '[DNT]',
    'aedm', 'dmg', 'dmg10', 'dmg11', 'dmg2', 'dmg3', 'dmg4', 'dmg5', 'dmg6', 'dmg7',
    'dmg8', 'dmg9', 'hh10', 'r-h', 'rf', 'rfo', 'trans', 'trans2', 'wr', 'ggggfg',
    'PLACEHOLDER_ASHBRINGER_QUESTITEM_01', '[DNT] Crafted Tier Piece Placeholder', '[DNT] REUSE',
))
NATIVE_SHARED_TEXT = {
    'csCZ': {'Test'},
    'deDE': {'Test', 'test', 'Arrrrrgh!', 'SI:7', 'Raptor', 'Gorilla', 'Wolf', 'Scooby-dooby-doo!', 'E Pluribus Mithril'},
    'esES': {'Racial', 'General', 'Raptor', 'Derrotado.'},
    'esMX': {'Racial', 'Raptor', 'Derrotado.'},
    'frFR': {'Test', 'test', 'Expert', 'Artisan', 'Racial', 'Scorpion', 'Champion', 'Fragile.', 'Raptor',
             'Volume I', 'Volume II', 'Volume III', 'Arrrrrgh!', 'SI:7', 'E Pluribus Mithril', 'TOP SECRET'},
    'ptBR': {'Racial', 'General', 'Volume I', 'Volume II', 'Volume III', 'Scooby-dooby-doo!', 'Raptor'},
    'koKR': {'SI:7'},
    'daDK': {'Eureka!'},
    'hrHR': {'Eureka!'},
    'itIT': {'Oh no...', 'Volume I', 'Volume II', 'Volume III', 'Eureka!'},
    'plPL': {'Eureka!', 'Test'},
    'svSE': {'Eureka!', 'S. A. F. T. B. O. M. B. SAF-T. Bomb.'},
    'trTR': {'Test'},
}


def get_digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def get_tokens(value):
    tokens, offset = [], 0

    for match in TOKEN.finditer(value):
        if match.start() < offset:
            continue

        finish = match.end()

        if value.startswith('${', match.start()):
            depth, cursor = 1, match.start() + 2

            while cursor < len(value) and depth:
                depth += (value[cursor] == '{') - (value[cursor] == '}')
                cursor += 1

            if not depth:
                precision = re.match(r'\.\d+', value[cursor:])
                finish = cursor + (len(precision[0]) if precision else 0)

        tokens.append(value[match.start():finish])
        offset = finish

    return sorted(tokens)


def get_quest_tokens(value):
    """Ignore literal gender inflection controls without hiding protected value tokens."""
    pieces, protected, offset = [], [], 0
    while offset < len(value):
        if value.startswith('${', offset):
            start, depth = offset, 1
            offset += 2
            while offset < len(value) and depth:
                depth += (value[offset] == '{') - (value[offset] == '}')
                offset += 1
            pieces.append(value[start:offset])
            continue
        if value[offset:offset + 2] in ('$g', '$G'):
            match = re.match(r'\$[gG]([^:;$\n.!?]+):([^:;$\n.!?]+);', value[offset:])
            if not match or not match[1].strip() or not match[2].strip():
                raise ValueError('Malformed quest gender selector')
            selector = match.group()
            if (get_tokens(match[1]) or get_tokens(match[2]) or
                    re.search(r'[{}<>\[\]|%]', match[1] + match[2])):
                protected.append(selector)
            pieces.append(' ')
            offset += len(selector)
            continue
        match = TOKEN.match(value, offset)
        if match:
            pieces.append(match.group())
            offset = match.end()
        else:
            pieces.append(value[offset])
            offset += 1
    return sorted(get_tokens(''.join(pieces)) + protected)


def get_book_tokens(value):
    """Separate the book newline control from adjacent literal numbers."""
    return sorted('$B' if re.fullmatch(r'\$B\d*', token) else token
                  for token in get_quest_tokens(value))


def matching_tokens(context, source, target):
    try:
        getter = (get_book_tokens if context.startswith(('books.', 'bookpages.')) else
                  get_quest_tokens if context.startswith('quests.') else get_tokens)
        return getter(source) == getter(target)
    except ValueError:
        return False


def get_invariant_reason(job):
    text, context = job['source'], job['context']

    if context.endswith('.name') and text in TECHNICAL_NAMES:
        return 'technicalIdentifier'

    if text in ('<NO LOG DESCRIPTION>', 'NYI', 'NYI.', 'TEST', 'DND', 'DNT', 'QASpell'):
        return 'structuralSentinel'

    if context.startswith('quests.') and (text in ('x', 'zzOLD UNUSED', 'UNUSED', 'REUSE', 'reuse') or re.fullmatch(
        r'(?:<(?:UNUSED|NYI|TXT)>\s*)+', text, re.IGNORECASE
    )):
        return 'structuralSentinel'

    if text == 'K.D.':
        return 'characterInitials'

    if text == 'Thro mo mo tar!':
        return 'sourcePhoneticWordplay'

    if text == 'Umbrinoth':
        return 'properName'

    if text == 'Scooby-dooby-doo!':
        return 'characterCatchphrase'

    if text == 'STONE HENDGE' and context == 'items.tooltip.description':
        return 'opaqueIdentifierFromDeleteMeTestItem5378'

    if text == '-Feralas' and job.get('locale') in ('csCZ', 'daDK', 'hrHR', 'itIT', 'plPL', 'svSE', 'trTR', 'ukUA'):
        return 'maintainedPlaceNameMatchesSource'

    if text == 'SI:7' and job.get('locale') in ('csCZ', 'daDK', 'hrHR', 'itIT', 'plPL', 'svSE', 'trTR', 'ukUA'):
        return 'organizationAcronym'

    if text in NATIVE_SHARED_TEXT.get(job.get('locale'), set()):
        return 'reviewedSharedLocaleWording'

    if context in ('items.tooltip.description', 'spells.tooltip.description', 'spells.tooltip.auraDescription') \
            and not any(character.isalpha() for character in TOKEN.sub('', text)):
        return 'structuralTemplate'

    return None


def expand_translations(queue, rows, context):
    jobs = {(job['locale'], job['source']): job for job in queue['jobs'] if job['context'] == context}
    results = []
    selected = []

    for row in rows:
        source = row['source']

        for locale, translation in row.items():
            if locale == 'source':
                continue

            job = jobs.get((locale, source))

            if job is None:
                raise ValueError(f'Unknown translation source/locale: {context}/{locale}/{source}')

            selected.append(job)
            results.append({'jobId': job['jobId'], 'sourceHash': job['sourceHash'], 'translation': translation})

    batch = {**queue, 'jobs': selected}
    validate_results(batch, results)

    return batch, results


def split_patch(patch, maximum):
    chunks = []

    for section in re.split(r'(?=^\*\*\* Update File: )', patch, flags=re.MULTILINE):
        if not section.startswith('*** Update File: '):
            continue

        header, body = section.split('\n', 1)
        body = body.removesuffix('*** End Patch\n')
        prefix = '*** Begin Patch\n' + header + '\n'
        current = prefix

        for block in re.split(r'(?=^@@\n)', body, flags=re.MULTILINE):
            if not block:
                continue

            if len(current) > len(prefix) and len(current) + len(block) > maximum:
                chunks.append(current + '*** End Patch\n')
                current = prefix

            current += block

        if len(current) > len(prefix):
            chunks.append(current + '*** End Patch\n')

    return chunks


def read_submitted_results(queue, directory):
    jobs = {job['jobId']: job for job in queue['jobs']}
    results = {}
    priorities = {}
    inputs = []
    pattern = re.compile(r'item-descriptions-\d{4}\.json|spell-(?:descriptions|aura|main|nordic-croatian|record)-\d+-text\.json')

    for path in sorted(directory.glob('*.json')):
        manual = pattern.fullmatch(path.name)
        family = re.fullmatch(r'numeric-reuse-\d+-results\.json', path.name) or path.name in (
                               'recipe-family-0001-results.json', 'spell-family-results.json',
                               'reference-family-results.json', 'learned-spell-family-0001-results.json',
                               'enchant-family-0001-results.json')

        if not manual and not family:
            continue

        raw = path.read_text(encoding='utf-8')
        rows = parse_json(raw, path)

        if not rows:
            continue

        if 'source' in rows[0]:
            context = 'spells.tooltip.auraDescription' if path.name.startswith('spell-aura-') else 'spells.tooltip.description'
            _, rows = expand_translations(queue, rows, context)

        for result in rows:
            job_id = result['jobId']

            if job_id not in jobs:
                raise ValueError('Unknown submitted job: ' + job_id)

            priority = 1 if manual else 0

            if job_id in results and results[job_id]['translation'] != result['translation']:
                if priorities[job_id] == priority:
                    raise ValueError('Conflicting submitted translations: ' + job_id)

                if priorities[job_id] > priority:
                    continue

            results[job_id] = result
            priorities[job_id] = priority

        inputs.append({'path': str(path), 'sha256': get_digest(raw)})

    return results, inputs


def collect_results(queue, directory, documents):
    jobs = {job['jobId']: job for job in queue['jobs']}
    results, inputs = read_submitted_results(queue, directory)
    selected = []
    selected_results = []

    for job_id, result in sorted(results.items()):
        job = jobs[job_id]
        missing = []

        for pointer in job['pointers']:
            entity = documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']]
            target = get_target(entity, job['locale'], pointer['field'], pointer.get('index'))

            if target and target != result['translation']:
                raise ValueError('Submitted translation differs from written target: ' + job_id)

            if not target:
                missing.append(pointer)

        if missing:
            selected.append({**job, 'pointers': missing})
            selected_results.append(result)

    batch = {**queue, 'jobs': selected, 'submissionSources': inputs}
    validate_results(batch, selected_results, documents)

    return batch, selected_results


def get_reference_frame(source, translation=None):
    references = {}

    def replace_source(match):
        token = match.group()
        reference = re.fullmatch(r'\$\d*([somdtaerhbuvx])\d*', token)

        if not reference or not any(character.isdigit() for character in token):
            return token

        if token not in references:
            references[token] = '\x00' + str(len(references)) + ':' + reference[1] + '\x00'

        return references[token]

    frame = TOKEN.sub(replace_source, source)

    if not references:
        return None

    target_frame = None

    if translation is not None:
        if get_tokens(source) != get_tokens(translation):
            raise ValueError('Reference prototype changed protected tokens')

        target_frame = TOKEN.sub(lambda match: references.get(match.group(), match.group()), translation)

    return frame, tuple(references), target_frame


def create_reference_reuse(queue, submissions, documents):
    jobs = {job['jobId']: job for job in queue['jobs']}
    prototypes = collections.defaultdict(set)

    for job_id, result in submissions.items():
        job = jobs[job_id]

        if not job['context'].endswith(('tooltip.description', 'tooltip.auraDescription')):
            continue

        frame = get_reference_frame(job['source'], result['translation'])

        if frame:
            prototypes[(job['context'], job['locale'], frame[0])].add(frame[2])

    selected, results = [], []

    for job in queue['jobs']:
        if job['jobId'] in submissions or not job['context'].endswith(('tooltip.description', 'tooltip.auraDescription')):
            continue

        frame = get_reference_frame(job['source'])

        if not frame:
            continue

        candidates = prototypes.get((job['context'], job['locale'], frame[0]), set())

        if len(candidates) != 1:
            continue

        translation = next(iter(candidates))

        for index, token in enumerate(frame[1]):
            letter = re.fullmatch(r'\$\d*([somdtaerhbuvx])\d*', token)[1]
            translation = translation.replace('\x00' + str(index) + ':' + letter + '\x00', token)

        missing = [pointer for pointer in job['pointers'] if not get_target(
            documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']],
            job['locale'], pointer['field'], pointer.get('index'))]

        if missing:
            selected.append({**job, 'pointers': missing})
            results.append({'jobId': job['jobId'], 'sourceHash': job['sourceHash'], 'translation': translation})

    batch = {**queue, 'jobs': selected}
    validate_results(batch, results, documents)

    return batch, results


VALUE_REFERENCE = re.compile(
    r'\$\{[^}]*\}|\$[/*][\d.]+;\d*[somdtaerhbuvx]\d*|\$\d*[somdtaerhbuvx]\d*(?![A-Za-z])'
)


def get_value_kind(token):
    if token.startswith('${'):
        return 'expression'

    reference = re.fullmatch(r'\$[/*][\d.]+;\d*([somdtaerhbuvx])\d*', token) \
        if token.startswith(('$/', '$*')) else re.fullmatch(r'\$\d*([somdtaerhbuvx])\d*', token)

    return reference[1]


def get_value_frame(source, translation=None):
    """Keep wording and binding identity exact while abstracting numeric value tokens."""
    references = {}

    def replace_source(match):
        token = match.group()
        references.setdefault(token, '\x00' + str(len(references)) + ':' + get_value_kind(token) + '\x00')

        return references[token]

    frame = VALUE_REFERENCE.sub(replace_source, source)

    if not references:
        return None

    target_frame = None

    if translation is not None:
        if get_tokens(source) != get_tokens(translation):
            raise ValueError('Numeric prototype changed protected tokens')

        target_frame = VALUE_REFERENCE.sub(lambda match: references.get(match.group(), match.group()), translation)

    return frame, tuple(references), target_frame


def create_value_reuse(queue, submissions, documents):
    jobs = {job['jobId']: job for job in queue['jobs']}
    prototypes = collections.defaultdict(set)

    for job_id, result in submissions.items():
        job = jobs[job_id]

        if job['context'] not in ('spells.tooltip.description', 'spells.tooltip.auraDescription'):
            continue

        frame = get_value_frame(job['source'], result['translation'])

        if frame:
            prototypes[(job['context'], job['locale'], frame[0])].add(frame[2])

    selected, results = [], []

    for job in queue['jobs']:
        if job['jobId'] in submissions or job['context'] not in ('spells.tooltip.description', 'spells.tooltip.auraDescription'):
            continue

        frame = get_value_frame(job['source'])
        candidates = prototypes.get((job['context'], job['locale'], frame[0]), set()) if frame else set()

        if len(candidates) != 1:
            continue

        translation = next(iter(candidates))

        for index, token in enumerate(frame[1]):
            translation = translation.replace('\x00' + str(index) + ':' + get_value_kind(token) + '\x00', token)

        missing = [pointer for pointer in job['pointers'] if not get_target(
            documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']],
            job['locale'], pointer['field'], pointer.get('index'))]

        if missing:
            selected.append({**job, 'pointers': missing})
            results.append({'jobId': job['jobId'], 'sourceHash': job['sourceHash'], 'translation': translation})

    batch = {**queue, 'jobs': selected}
    validate_results(batch, results, documents)

    return batch, results


def get_objective_lines(localized):
    return {line['index']: line['text'] for line in localized.get('objectiveLines', []) if line.get('text')}


def iter_fields(kind, entity):
    english = entity['locales'].get('enUS', {})

    if kind == 'quests':
        for field in QUEST_FIELDS:
            yield field, english.get(field), None

        for index, text in get_objective_lines(english).items():
            yield 'objectiveLines', text, index

        return

    yield 'name', english.get('name'), None

    if kind in ('items', 'spells'):
        tooltip = entity.get('tooltipData', {})
        yield 'tooltip.description', english.get('description'), None

        if kind == 'spells':
            yield 'tooltip.auraDescription', english.get('auraDescription'), None
            yield 'tooltip.rank', english.get('rank') or tooltip.get('rank'), None
        else:
            yield 'tooltip.nameDescription', english.get('nameDescription') or tooltip.get('nameDescription'), None
            yield 'tooltip.set.name', english.get('setName') or tooltip.get('set', {}).get('name'), None


def get_pointer_source(pointer, entity):
    locale = pointer.get('sourceLocale', 'enUS')

    if locale != 'enUS':
        return get_target(entity, locale, pointer['field'], pointer.get('index'))

    return next((text for field, text, index in iter_fields(pointer['kind'], entity)
                 if field == pointer['field'] and index == pointer.get('index')), None)


def create_foreign_queue(documents, include_excluded_quests=False):
    """Report excluded fields; never author an English source from another language."""
    initial = collect_translation_candidates(documents, include_excluded_quests)
    locales = canonical_locales(documents['quests']['locales'])
    unavailable = []
    for pointer in initial['missingSource']:
        entity = documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']]
        if not any(get_target(entity, locale, pointer['field'], pointer.get('index'))
                   for locale in locales if locale != 'enUS'):
            unavailable.append(pointer)
    return {'schemaVersion': 1, 'jobs': [], 'missingSource': unavailable,
            'excludedWithoutEnglish': initial['missingSource']}


def get_owned_target(entity, locale, field):
    localized_field = field.removeprefix('tooltip.')

    if localized_field == 'set.name':
        localized_field = 'setName'

    return entity['locales'].get(locale, {}).get(localized_field)


def needs_target_translation(job, pointer, entity):
    target = get_target(entity, job['locale'], pointer['field'], pointer.get('index'))

    if pointer.get('nativeFallback'):
        return target == job['source'] and not get_owned_target(entity, job['locale'], pointer['field'])

    return not target


def create_fallback_queue(documents):
    locales = canonical_locales(documents['quests']['locales'])
    groups = {}
    areas = list(documents['areas']['catalogs']['areas'].values())

    for kind in ('items', 'spells'):
        for entity_id, entity in documents[kind]['catalogs'][kind].items():
            for field, source, _ in iter_fields(kind, entity):
                context = kind + '.' + field

                if not source or not field.startswith('tooltip.'):
                    continue

                if get_invariant_reason({'context': context, 'source': source}):
                    continue

                for locale in locales:
                    if locale == 'enUS' or source in NATIVE_SHARED_TEXT.get(locale, set()):
                        continue

                    if source.startswith('-') and any(
                        area['locales'].get('enUS', {}).get('name') == source[1:]
                        and area['locales'].get(locale, {}).get('name') == source[1:] for area in areas
                    ):
                        continue

                    if get_owned_target(entity, locale, field) or get_target(entity, locale, field, None) != source:
                        continue

                    pointer = {'catalog': kind, 'kind': kind, 'id': entity_id, 'field': field,
                               'nativeFallback': True}
                    groups.setdefault((locale, context, source), []).append(pointer)

    wanted = {(context, source) for _, context, source in groups}
    reusable = collections.defaultdict(dict)

    for kind in ('items', 'spells'):
        for entity_id, entity in documents[kind]['catalogs'][kind].items():
            for field, source, _ in iter_fields(kind, entity):
                context = kind + '.' + field

                if (context, source) not in wanted:
                    continue

                for locale in locales:
                    key = (locale, context, source)

                    if key not in groups:
                        continue

                    target = get_target(entity, locale, field, None)
                    metadata = get_metadata(entity, locale, field, None)

                    if target and target != source and metadata and get_tokens(target) == get_tokens(source):
                        reusable[key].setdefault(target, {**metadata,
                            'reusedFrom': {'catalog': kind, 'id': entity_id, 'field': field}})

    jobs = []

    for (locale, context, source), pointers in groups.items():
        job_id = get_digest(json.dumps([locale, context, source], ensure_ascii=False, separators=(',', ':')))
        job = {'jobId': job_id, 'locale': locale, 'context': context, 'source': source,
               'sourceHash': get_digest(source), 'tokens': get_tokens(source), 'pointers': pointers}
        candidates = reusable.get((locale, context, source), {})

        if len(candidates) == 1:
            text, metadata = next(iter(candidates.items()))
            job['reuse'] = {'text': text, 'metadata': metadata}

        jobs.append(job)

    return {'schemaVersion': 1, 'jobs': sorted(jobs, key=lambda job: job['jobId']), 'missingSource': []}


def get_target(entity, locale, field, index):
    localized = entity['locales'].get(locale, {})

    if field == 'objectiveLines':
        return get_objective_lines(localized).get(index)

    if field.startswith('tooltip.'):
        detail_field = field.removeprefix('tooltip.')
        localized_field = 'setName' if detail_field == 'set.name' else detail_field

        if localized.get(localized_field):
            return localized[localized_field]

        return get_tooltip_source_text(entity, locale, detail_field)

    return localized.get(field)


def get_metadata(entity, locale, field, index):
    localized = entity['locales'].get(locale, {})
    key = 'objectiveLines.' + str(index) if field == 'objectiveLines' else field

    if field.startswith('tooltip.'):
        detail_field = field.removeprefix('tooltip.')
        localized_field = 'setName' if detail_field == 'set.name' else detail_field

        key = localized_field

    return localized.get('translationMetadata', {}).get('fields', {}).get(key)


def collect_translation_candidates(documents, include_excluded_quests=False):
    """Inventory missing targets and deduplicate them; this does not authorize AI work."""
    locales = canonical_locales(documents['quests']['locales'])
    groups = {}
    reusable = collections.defaultdict(dict)
    missing_source = []

    for document_name, document in documents.items():
        for kind, records in document['catalogs'].items():
            for entity_id, entity in records.items():
                if kind == 'quests' and not include_excluded_quests \
                        and entity.get('usageStatus') in EXCLUDED_QUEST_STATUSES:
                    continue

                for field, english, index in iter_fields(kind, entity):
                    context = kind + '.' + field
                    pointer = {'catalog': document_name, 'kind': kind, 'id': entity_id, 'field': field}

                    if index is not None:
                        pointer['index'] = index

                    if not english:
                        if kind == 'globalstrings' and isinstance(english, str):
                            continue
                        if field in ('name', 'title') or any(
                            get_target(entity, locale, field, index) for locale in locales if locale != 'enUS'
                        ):
                            missing_source.append(pointer)
                        continue

                    for locale in locales:
                        if locale == 'enUS':
                            continue

                        target = get_target(entity, locale, field, index)
                        key = (locale, context, english)

                        if target or kind == 'globalstrings' and isinstance(target, str):
                            metadata = get_metadata(entity, locale, field, index)

                            if metadata and matching_tokens(context, english, target):
                                reusable[key].setdefault(target, metadata)
                            continue

                        groups.setdefault(key, []).append(dict(pointer))

    jobs = []

    for (locale, context, english), pointers in groups.items():
        source_hash = get_digest(english)
        job_id = get_digest(json.dumps([locale, context, english], ensure_ascii=False, separators=(',', ':')))
        candidates = reusable.get((locale, context, english), {})
        job = {'jobId': job_id, 'locale': locale, 'context': context, 'source': english,
               'sourceHash': source_hash, 'tokens': get_tokens(english), 'pointers': pointers}

        if len(candidates) == 1:
            text, metadata = next(iter(candidates.items()))
            job['reuse'] = {'text': text, 'metadata': metadata}
        elif candidates:
            job['reuseConflict'] = len(candidates)

        jobs.append(job)

    return {'schemaVersion': 1, 'jobs': sorted(jobs, key=lambda job: job['jobId']),
            'missingSource': missing_source}


def create_queue(documents, include_excluded_quests=False, evidence=None, root=ROOT):
    from tools.catalogs.import_policy import filter_queue
    from tools.build.client_label_scope import scope_globalstring_documents
    documents = scope_globalstring_documents(documents, root)
    return filter_queue(collect_translation_candidates(documents, include_excluded_quests), evidence)


def validate_results(queue, results, documents=None):
    jobs = {job['jobId']: job for job in queue['jobs']}
    result_ids = [result['jobId'] for result in results]

    if len(jobs) != len(queue['jobs']) or len(result_ids) != len(set(result_ids)) or set(result_ids) != set(jobs):
        raise ValueError('Result IDs must match the queue exactly, without duplicates')

    pointers = set()

    for result in results:
        job = jobs[result['jobId']]
        translation = result.get('translation')
        expected_id = get_digest(json.dumps([job['locale'], job['context'], job['source']],
                                           ensure_ascii=False, separators=(',', ':')))

        if job['jobId'] != expected_id or job['tokens'] != get_tokens(job['source']):
            raise ValueError('Queue content changed: ' + job['jobId'])

        if result.get('sourceHash') != get_digest(job['source']) or job['sourceHash'] != get_digest(job['source']):
            raise ValueError('Source hash mismatch: ' + job['jobId'])

        structural_whitespace = (isinstance(translation, str) and translation == job['source']
                                 and get_invariant_reason(job) == 'structuralTemplate')

        if not isinstance(translation, str) or (not translation.strip() and not structural_whitespace):
            raise ValueError('Empty translation: ' + job['jobId'])

        if not matching_tokens(job['context'], job['source'], translation):
            raise ValueError('Placeholder mismatch: ' + job['jobId'])

        if documents is not None:
            for pointer in job['pointers']:
                identity = (job['locale'], pointer['catalog'], pointer['kind'], pointer['id'],
                            pointer['field'], pointer.get('index'))

                if identity in pointers:
                    raise ValueError('Duplicate target pointer: ' + job['jobId'])

                pointers.add(identity)

                if job['context'] != pointer['kind'] + '.' + pointer['field']:
                    raise ValueError('Catalog context mismatch: ' + job['jobId'])

                entity = documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']]
                if not get_target(entity, 'enUS', pointer['field'], pointer.get('index')):
                    raise ValueError('Text without an English source is outside catalog scope: ' + job['jobId'])
                source = get_pointer_source(pointer, entity)

                if source != job['source']:
                    raise ValueError('Catalog source changed: ' + job['jobId'])

                target = get_target(entity, job['locale'], pointer['field'], pointer.get('index'))
                replace_native_fallback = pointer.get('nativeFallback') and target == source \
                    and not get_owned_target(entity, job['locale'], pointer['field'])
                replace_owned_english = pointer.get('ownedEnglishFallback') and pointer['kind'] == 'quests' \
                    and pointer['field'] in ('title', 'summary', 'description') \
                    and job['locale'] != 'enUS' and target == source \
                    and get_owned_target(entity, job['locale'], pointer['field']) == source \
                    and isinstance(pointer.get('existingMetadata'), dict) \
                    and pointer.get('existingMetadata') == get_metadata(entity, job['locale'], pointer['field'], None)

                if pointer.get('ownedEnglishFallback') and (not replace_owned_english or translation == source):
                    raise ValueError('Owned English replacement no longer matches its reviewed snapshot: ' + job['jobId'])

                if target and not replace_native_fallback and not replace_owned_english:
                    raise ValueError('Target already exists: ' + job['jobId'])


def get_object_entries(raw, start):
    decoder = json.JSONDecoder()
    position = start + 1
    entries = {}

    while True:
        while raw[position].isspace() or raw[position] == ',':
            position += 1

        if raw[position] == '}':
            return entries, position

        key, position = decoder.raw_decode(raw, position)

        while raw[position].isspace() or raw[position] == ':':
            position += 1

        value_start = position
        _, position = decoder.raw_decode(raw, position)
        entries[key] = (value_start, position)


def get_json_path(raw, path):
    start = 0

    for key in path:
        entries, _ = get_object_entries(raw, start)
        start = entries[key][0]

    return start


def append_object_entries(raw, object_start, values, insertions):
    entries, end = get_object_entries(raw, object_start)
    position = end

    while position > object_start + 1 and raw[position - 1].isspace():
        position -= 1

    multiline = '\n' in raw[object_start:end]
    indent = re.match(r'[ \t]*', raw[raw.rfind('\n', 0, end) + 1:end]).group() + '  ' if multiline else ''
    separator = ',\n' + indent if multiline else ', '
    prefix = (',' if entries else '') + ('\n' + indent if multiline else ' ')
    text = prefix + separator.join(json.dumps(key, ensure_ascii=False) + ': ' + json.dumps(value, ensure_ascii=False)
                                   for key, value in values.items())
    insertions[position].append(text)


def create_small_catalog_patch(raw, document, updates):
    if any(key[2] == 'enGB' for key in updates):
        raise ValueError('enGB is not supported; write English fields under enUS')

    insertions = collections.defaultdict(list)
    replacements = []

    for (kind, entity_id, locale), fields in updates.items():
        entity = document['catalogs'][kind][entity_id]
        localized = entity['locales'].get(locale)
        locales_start = get_json_path(raw, ('catalogs', kind, entity_id, 'locales'))
        locale_start = get_json_path(raw, ('catalogs', kind, entity_id, 'locales', locale)) \
            if localized is not None else None
        locale_values = {}
        metadata_values = {}
        objectives = []

        for update in fields:
            field, index, translation, metadata = update[:4]
            expected = update[4] if len(update) > 4 else None
            if field == 'objectiveLines':
                if localized and any(line.get('index') == index for line in localized.get('objectiveLines', [])):
                    raise ValueError(f'Existing objective index: {kind}/{entity_id}/{locale}/{index}')

                source_line = next(line for line in entity['locales']['enUS']['objectiveLines']
                                   if line['index'] == index)
                objectives.append({key: source_line[key] for key in ('index', 'type') if key in source_line}
                                  | {'text': translation})
                metadata_key = 'objectiveLines.' + str(index)
            else:
                detail = field.removeprefix('tooltip.')
                metadata_key = 'setName' if detail == 'set.name' else detail

                if localized is not None and metadata_key in localized:
                    if expected is None or localized[metadata_key] != expected:
                        raise ValueError(f'Existing localized field: {kind}/{entity_id}/{locale}/{metadata_key}')

                    entries, _ = get_object_entries(raw, locale_start)
                    start, end = entries[metadata_key]
                    replacements.append((start, end, json.dumps(translation, ensure_ascii=False)))
                    metadata_start = get_json_path(raw, ('catalogs', kind, entity_id, 'locales', locale,
                                                       'translationMetadata', 'fields'))
                    metadata_entries, _ = get_object_entries(raw, metadata_start)
                    start, end = metadata_entries[metadata_key]
                    replacements.append((start, end, json.dumps(metadata, ensure_ascii=False)))
                    continue

                locale_values[metadata_key] = translation

            metadata_values[metadata_key] = metadata

        if localized is None:
            if objectives:
                locale_values['objectiveLines'] = objectives

            locale_values['translationMetadata'] = {'fields': metadata_values}
            append_object_entries(raw, locales_start, {locale: locale_values}, insertions)
            continue

        if objectives:
            if 'objectiveLines' in localized:
                line_start = get_json_path(raw, ('catalogs', kind, entity_id, 'locales', locale, 'objectiveLines'))
                _, line_end = json.JSONDecoder().raw_decode(raw, line_start)
                prefix = ', ' if localized['objectiveLines'] else ' '
                insertions[line_end - 1].append(prefix + ', '.join(json.dumps(line, ensure_ascii=False)
                                                                   for line in objectives) + ' ')
            else:
                locale_values['objectiveLines'] = objectives

        if metadata_values:
            metadata = localized.get('translationMetadata')

            if metadata and any(key in metadata.get('fields', {}) for key in metadata_values):
                raise ValueError(f'Existing translation metadata: {kind}/{entity_id}/{locale}')

            if metadata is None:
                locale_values['translationMetadata'] = {'fields': metadata_values}
            elif 'fields' not in metadata:
                metadata_start = get_json_path(raw, ('catalogs', kind, entity_id, 'locales', locale, 'translationMetadata'))
                append_object_entries(raw, metadata_start, {'fields': metadata_values}, insertions)
            else:
                metadata_start = get_json_path(raw, ('catalogs', kind, entity_id, 'locales', locale,
                                                     'translationMetadata', 'fields'))
                append_object_entries(raw, metadata_start, metadata_values, insertions)

        if locale_values:
            append_object_entries(raw, locale_start, locale_values, insertions)

    pieces = []
    previous = 0
    edits = replacements + [(position, position, ''.join(values)) for position, values in insertions.items()]

    for start, end, value in sorted(edits):
        if start < previous:
            raise ValueError('Overlapping catalog field edits')

        pieces.extend((raw[previous:start], value))
        previous = end

    pieces.append(raw[previous:])

    return ''.join(pieces)


def create_catalog_patch(raw, document, updates, return_edits=False):
    if any(key[2] == 'enGB' for key in updates):
        raise ValueError('enGB is not supported; write English fields under enUS')

    records = collections.defaultdict(dict)

    for key, fields in updates.items():
        records[key[:2]][key] = fields

    spans = {}

    for kind, _ in records:
        if kind not in spans:
            start = get_json_path(raw, ('catalogs', kind))
            spans[kind], _ = get_object_entries(raw, start)

    edits = []

    for (kind, entity_id), fields in records.items():
        start, end = spans[kind][entity_id]
        prefix = '{"catalogs":{' + json.dumps(kind) + ':{' + json.dumps(entity_id) + ':'
        wrapper = prefix + raw[start:end] + '}}}'
        record_document = {'catalogs': {kind: {entity_id: document['catalogs'][kind][entity_id]}}}
        edited = create_small_catalog_patch(wrapper, record_document, fields)
        edits.append((start, end, edited[len(prefix):-3]))

    if return_edits:
        return edits

    pieces = []
    previous = 0

    for start, end, replacement in sorted(edits):
        pieces.extend((raw[previous:start], replacement))
        previous = end

    pieces.append(raw[previous:])

    return ''.join(pieces)


def get_result_metadata(job, pointer, result, documents):
    if job.get('reuse', {}).get('text') == result['translation']:
        return job['reuse']['metadata']

    invariant = result['translation'] == job['source'] and get_invariant_reason(job)

    if invariant:
        entity = documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']]
        english_origin = get_metadata(entity, pointer.get('sourceLocale', 'enUS'),
                                      pointer['field'], pointer.get('index'))

        if not english_origin or english_origin.get('origin') not in ('original', 'community', 'ai'):
            raise ValueError('Missing English origin for source reuse: ' + job['jobId'])

        return {key: value for key, value in english_origin.items() if value is not None}

    return {'origin': 'ai', 'source': 'ForeverRosettaStoneAI', 'sourceLocale': pointer.get('sourceLocale', 'enUS'),
            'sourceTextSha256': job['sourceHash']}


def verify_applied(queue, results, documents):
    validate_results(queue, results)
    by_id = {result['jobId']: result for result in results}
    fields = 0

    for job in queue['jobs']:
        result = by_id[job['jobId']]

        for pointer in job['pointers']:
            entity = documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']]
            source = get_pointer_source(pointer, entity)
            target = get_target(entity, job['locale'], pointer['field'], pointer.get('index'))
            metadata = get_metadata(entity, job['locale'], pointer['field'], pointer.get('index'))

            if source != job['source'] or target != result['translation']:
                raise ValueError('Applied text differs from the validated batch: ' + job['jobId'])

            if metadata != get_result_metadata(job, pointer, result, documents):
                raise ValueError('Applied provenance differs from the validated batch: ' + job['jobId'])

            fields += 1

    return fields


def create_patch(queue, results, documents, root):
    validate_results(queue, results, documents)
    results_by_id = {result['jobId']: result for result in results}
    grouped = collections.defaultdict(lambda: collections.defaultdict(list))

    for job in queue['jobs']:
        result = results_by_id[job['jobId']]

        for pointer in job['pointers']:
            metadata = get_result_metadata(job, pointer, result, documents)
            key = (pointer['kind'], pointer['id'], job['locale'])
            update = (pointer['field'], pointer.get('index'), result['translation'], metadata)

            if pointer.get('ownedEnglishFallback'):
                update += (job['source'],)

            grouped[pointer['catalog']][key].append(update)

    patch = []

    for catalog, updates in grouped.items():
        selected = collections.defaultdict(set)

        for kind, entity_id, _ in updates:
            selected[kind].add(entity_id)

        current = load_catalog(root, catalog, selected)

        for kind, entity_ids in selected.items():
            for entity_id in entity_ids:
                if current['catalogs'][kind][entity_id] != documents[catalog]['catalogs'][kind][entity_id]:
                    raise ValueError('Catalog changed during patch generation: ' + kind + '/' + entity_id)

        raw = dump_json(current)
        edited = json.loads(create_catalog_patch(raw, current, updates))

        for kind, entity_ids in sorted(selected.items()):
            for entity_id in sorted(entity_ids, key=int):
                path = get_entity_path(root, kind, entity_id)
                original = path.read_text(encoding='utf-8')

                if json.loads(original) != current['catalogs'][kind][entity_id]:
                    raise ValueError('Catalog changed during patch generation: ' + kind + '/' + entity_id)

                before = original.splitlines(keepends=True)
                after = dump_json(edited['catalogs'][kind][entity_id]).splitlines(keepends=True)
                diff = list(difflib.unified_diff(before, after, n=max(len(before), len(after))))

                if diff:
                    patch.append('*** Update File: ' + str(path) + '\n')
                    patch.extend('@@\n' if line.startswith('@@ ') else line for line in diff[2:])

    return '*** Begin Patch\n' + ''.join(patch) + '*** End Patch\n'


def load_queue_catalogs(root, queue):
    scope = collections.defaultdict(set)

    for job in queue['jobs']:
        for pointer in job['pointers']:
            scope[pointer['kind']].add(pointer['id'])

    return load_catalogs(root, scope)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--database', type=Path, help='Verified source corpus for deterministic AI eligibility.')
    commands = parser.add_subparsers(dest='command', required=True)
    queue_parser = commands.add_parser('queue')
    queue_parser.add_argument('--output', type=Path, required=True)
    queue_parser.add_argument('--locale', help='Restrict jobs to one target locale.')
    queue_parser.add_argument('--limit', type=int, help='Limit the number of jobs in this batch.')
    queue_parser.add_argument('--offset', type=int, default=0, help='Skip this many jobs before applying the limit.')
    queue_parser.add_argument('--scope', type=Path, help='JSON kind-to-ID selection; include every affected entity.')
    queue_parser.add_argument('--include-excluded-quests', action='store_true',
                              help='Include maintained quest files excluded from the runtime export.')
    foreign_parser = commands.add_parser('foreign-queue')
    foreign_parser.add_argument('--output', type=Path, required=True)
    foreign_parser.add_argument('--include-excluded-quests', action='store_true',
                                help='Include maintained quest files excluded from the runtime export.')
    fallback_parser = commands.add_parser('fallback-queue')
    fallback_parser.add_argument('--output', type=Path, required=True)
    validate_parser = commands.add_parser('validate')
    validate_parser.add_argument('--queue', type=Path, required=True)
    validate_parser.add_argument('--results', type=Path, required=True)
    verify_parser = commands.add_parser('verify')
    verify_parser.add_argument('--queue', type=Path, required=True)
    verify_parser.add_argument('--results', type=Path, required=True)
    patch_parser = commands.add_parser('patch')
    patch_parser.add_argument('--queue', type=Path, required=True)
    patch_parser.add_argument('--results', type=Path, required=True)
    patch_parser.add_argument('--output', type=Path, required=True)
    expand_parser = commands.add_parser('expand')
    expand_parser.add_argument('--queue', type=Path, required=True)
    expand_parser.add_argument('--translations', type=Path, required=True)
    expand_parser.add_argument('--context', required=True)
    expand_parser.add_argument('--results', type=Path, required=True)
    expand_parser.add_argument('--batch-queue', type=Path, required=True)
    reuse_parser = commands.add_parser('reuse')
    reuse_parser.add_argument('--queue', type=Path, required=True)
    reuse_parser.add_argument('--results', type=Path, required=True)
    reuse_parser.add_argument('--batch-queue', type=Path, required=True)
    split_parser = commands.add_parser('split')
    split_parser.add_argument('--patch', type=Path, required=True)
    split_parser.add_argument('--output-dir', type=Path, required=True)
    split_parser.add_argument('--max-characters', type=int, default=900000)
    collect_parser = commands.add_parser('collect')
    collect_parser.add_argument('--queue', type=Path, required=True)
    collect_parser.add_argument('--directory', type=Path, required=True)
    collect_parser.add_argument('--results', type=Path, required=True)
    collect_parser.add_argument('--batch-queue', type=Path, required=True)
    for command in ('reference-reuse', 'value-reuse'):
        reference_parser = commands.add_parser(command)
        reference_parser.add_argument('--queue', type=Path, required=True)
        reference_parser.add_argument('--directory', type=Path, required=True)
        reference_parser.add_argument('--results', type=Path, required=True)
        reference_parser.add_argument('--batch-queue', type=Path, required=True)
    args = parser.parse_args()

    if args.command == 'split':
        if args.max_characters < 1000:
            parser.error('--max-characters must be at least 1000')

        args.output_dir.mkdir(parents=True, exist_ok=True)
        manifest = []

        for index, chunk in enumerate(split_patch(args.patch.read_text(encoding='utf-8'), args.max_characters)):
            path = args.output_dir / (str(index).zfill(5) + '.patch')
            path.write_text(chunk, encoding='utf-8')
            manifest.append({'path': str(path), 'characters': len(chunk), 'sha256': get_digest(chunk)})

        (args.output_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        print(f'Prepared {len(manifest)} dedicated-tool patch chunks')
        return

    if args.command in ('expand', 'reuse', 'collect', 'reference-reuse', 'value-reuse'):
        queue = read_json(args.queue)

        if args.command == 'expand':
            batch, results = expand_translations(queue, read_json(args.translations), args.context)
        elif args.command in ('collect', 'reference-reuse', 'value-reuse'):
            documents = load_queue_catalogs(args.root, queue)

            if args.command in ('reference-reuse', 'value-reuse'):
                submissions, inputs = read_submitted_results(queue, args.directory)
                reuse = create_value_reuse if args.command == 'value-reuse' else create_reference_reuse
                batch, results = reuse(queue, submissions, documents)
                batch['submissionSources'] = inputs
            else:
                batch, results = collect_results(queue, args.directory, documents)
        else:
            documents = load_queue_catalogs(args.root, queue)
            selected = []

            for job in queue['jobs']:
                if not (job.get('reuse') or get_invariant_reason(job)):
                    continue

                missing = [pointer for pointer in job['pointers'] if needs_target_translation(job, pointer,
                    documents[pointer['catalog']]['catalogs'][pointer['kind']][pointer['id']])]

                if missing:
                    selected.append({**job, 'pointers': missing})

            batch = {**queue, 'jobs': selected}
            results = [{'jobId': job['jobId'], 'sourceHash': job['sourceHash'],
                        'translation': job.get('reuse', {}).get('text', job['source'])} for job in selected]
            validate_results(batch, results)

        from tools.catalogs.import_policy import validate_queue_policy
        validate_queue_policy(batch, results, args.root)
        args.results.write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        args.batch_queue.write_text(json.dumps(batch, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f'Prepared {len(results)} validated results')
        return

    if args.command in ('queue', 'foreign-queue', 'fallback-queue'):
        scope = read_json(args.scope) if args.command == 'queue' and args.scope else None
        documents = load_catalogs(args.root, scope)
        from tools.build.client_label_scope import scope_globalstring_documents
        documents = scope_globalstring_documents(documents, args.root)

        if args.command == 'foreign-queue':
            queue = create_foreign_queue(documents, args.include_excluded_quests)
            from tools.catalogs.import_policy import filter_queue, OfficialEvidence
            queue = filter_queue(queue, OfficialEvidence(args.database, args.root) if args.database else None)
            args.output.write_text(json.dumps(queue, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            print(f"Created {len(queue['jobs'])} foreign-source jobs; "
                  f"{len(queue['missingSource'])} fields have no source in any language")
            return

        if args.command == 'fallback-queue':
            queue = create_fallback_queue(documents)
            from tools.catalogs.import_policy import filter_queue, OfficialEvidence
            queue = filter_queue(queue, OfficialEvidence(args.database, args.root) if args.database else None)
            args.output.write_text(json.dumps(queue, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
            print(f"Created {len(queue['jobs'])} English-fallback target jobs")
            return

        from tools.catalogs.import_policy import OfficialEvidence
        queue = create_queue(documents, args.include_excluded_quests,
                             OfficialEvidence(args.database, args.root) if args.database else None, root=args.root)

        if args.locale:
            if args.locale not in documents['quests']['locales'] or args.locale == 'enUS':
                parser.error('--locale must name a target catalog locale')

            queue['jobs'] = [job for job in queue['jobs'] if job['locale'] == args.locale]

        if args.offset < 0:
            parser.error('--offset must not be negative')

        if args.limit is not None:
            if args.limit < 1:
                parser.error('--limit must be positive')

        end = args.offset + args.limit if args.limit is not None else None
        queue['jobs'] = queue['jobs'][args.offset:end]

        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(queue, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(f"Created {len(queue['jobs'])} jobs; {len(queue['missingSource'])} fields lack English source")
        return

    queue = read_json(args.queue)
    results = read_json(args.results)
    documents = load_queue_catalogs(args.root, queue)

    if args.command == 'verify':
        fields = verify_applied(queue, results, documents)
        print(f'Verified {len(results)} jobs across {fields} written fields, including source hashes and provenance')
        return
    validate_results(queue, results, documents)
    from tools.catalogs.import_policy import validate_queue_policy
    validate_queue_policy(queue, results, args.root)

    if args.command == 'patch':
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(create_patch(queue, results, documents, args.root), encoding='utf-8')
        print(f'Generated patch for {len(results)} results')
        return

    print(f'Validated {len(results)} results')


if __name__ == '__main__':
    main()
