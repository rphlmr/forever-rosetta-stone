"""Deterministic source selection and eligibility for authored translations."""

import hashlib
import csv
import json
import re
from pathlib import Path

from datasources.corpus.translation_corpus import open_corpus, language_flags
from tools.catalogs.catalog_storage import load_catalog
from tools.catalogs.official_text import OFFICIAL_LOCALES, TEXT_FIELDS, SOURCE_PROVIDERS, source_build

BOOK_FIELDS = {('books', 'name'), ('bookpages', 'description')}

def normalize(text):
    return re.sub(r'\s+', ' ', text or '').strip()


def text_fields(record):
    fields = {field: record[field] for field in TEXT_FIELDS if isinstance(record.get(field), str)}
    fields.update({'objectiveLines.' + str(line['index']): line['text']
                   for line in record.get('objectiveLines', []) if isinstance(line.get('text'), str)})
    return fields


def metadata(record, field):
    return record.get('translationMetadata', {}).get('fields', {}).get(field, {})


def set_field(record, field, text, origin):
    if field.startswith('objectiveLines.'):
        index = int(field.split('.')[1])
        line = next((line for line in record.get('objectiveLines', []) if line['index'] == index), None)
        if line is None:
            raise ValueError('Cannot invent an objective binding: ' + field)
        line['text'] = text
    else:
        record[field] = text
    record.setdefault('translationMetadata', {}).setdefault('fields', {})[field] = dict(origin)


def english_source(entity, field, evidence=None):
    """Read canonical English, including the owned structural item-set name."""
    english = entity['locales'].get('enUS', {})
    fields = text_fields(english)
    if field in fields and metadata(english, field):
        return fields[field], metadata(english, field)
    if field == 'setName':
        value = entity.get('tooltipData', {}).get('set', {}).get('name')
        if isinstance(value, str) and value:
            verified = evidence.item_set_source(entity) if evidence else None
            origin = verified[1] if verified else {'origin': 'original', 'source': 'tooltipData', 'sourceLocale': 'enUS'}
            return value, origin
    return None, {}


def verify_sources(database, root):
    """Verify downloaded inputs, excluding catalog claims that resync intentionally changes."""
    database, root = Path(database).resolve(), Path(root).resolve()
    db = open_corpus(database)
    try:
        inputs = list(db.execute("SELECT path,sha256 FROM inputs WHERE path NOT LIKE 'catalogs/%'"))
        if not inputs:
            raise ValueError('A verified corpus needs external source inputs')
        for row in inputs:
            path = (root / row['path']).resolve()
            if not path.is_relative_to(root) or not path.is_file():
                raise ValueError('Missing or unsafe source input: ' + row['path'])
            if hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
                raise ValueError('Source changed since corpus refresh: ' + row['path'])
    finally:
        db.close()
    return database


class OfficialEvidence:
    """Index the latest verified official-language source for each field."""

    def __init__(self, database, root):
        self.database = verify_sources(database, root)
        self.root = Path(root).resolve()
        self.proofs = {}
        self.localized_proofs = set()
        self.source_contexts = {}
        self.item_sets = {}
        self.entities = {}
        self.extra_inputs = {}
        self.book_english = set()
        self.book_translations = set()
        db = open_corpus(self.database)
        try:
            scope = db.execute("SELECT value FROM settings WHERE key='scope'").fetchone()
            if scope and json.loads(scope[0]) == 'book-texts':
                for row in db.execute("""SELECT kind,entity_id,field,locale,text,english FROM records
                    WHERE kind IN ('books','bookpages') AND evidence='sourceSnapshot'
                    AND origin IN ('original','community') AND flags='[]'"""):
                    key = (row['kind'], row['entity_id'], row['field'])
                    text, english = normalize(row['text']), normalize(row['english'])
                    if row['locale'] == 'enUS' and text:
                        self.book_english.add((*key, text))
                    elif text and english and text != english:
                        self.book_translations.add((*key, english, row['locale']))
            roots = {(str((self.root / row['source_path']).parent), row['build']) for row in db.execute(
                "SELECT DISTINCT source_path,json_extract(provenance,'$.sourceBuild') build FROM records "
                "WHERE evidence='sourceSnapshot' AND origin='original' AND json_extract(provenance,'$.source')='wago'")}
            inputs = {row['path']: row['sha256'] for row in db.execute('SELECT path,sha256 FROM inputs')}
            paths = {self.root / name: checksum for name, checksum in inputs.items()
                     if Path(name).name.startswith('ItemSet.')}
            for folder, build in roots:
                manifest_path = Path(folder) / 'manifest.json'
                if str(manifest_path.relative_to(self.root)) not in inputs:
                    continue
                manifest = json.loads(manifest_path.read_text())
                if manifest.get('build') != build or manifest.get('complete') is not True:
                    continue
                for entry in manifest['results']:
                    if entry['table'] == 'ItemSet' and entry.get('status') in ('downloaded', 'existing'):
                        path = Path(folder) / entry['file']
                        if path.parent != Path(folder):
                            raise ValueError('Unsafe ItemSet export path')
                        paths[path] = entry['sha256']
            sets = {}
            for path, checksum in paths.items():
                match = re.fullmatch(r'ItemSet\.(\d+\.\d+\.\d+\.\d+)\.([a-z]{2}[A-Z]{2})\.csv', path.name)
                if not match or (str(path.parent), match[1]) not in roots or match[2] not in OFFICIAL_LOCALES:
                    continue
                if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
                    raise ValueError('ItemSet source changed: ' + str(path))
                self.extra_inputs[str(path.relative_to(self.root))] = checksum
                with path.open(encoding='utf-8-sig', newline='') as source:
                    for record in csv.DictReader(source):
                        sets.setdefault((match[1], record['ID']), {})[match[2]] = record['Name_lang']
            for (build, entity_id), translations in sorted(sets.items(), key=lambda item: tuple(map(int, item[0][0].split('.')))):
                english = translations.get('enUS')
                if not normalize(english):
                    continue
                proof = not language_flags('enUS', english, english, translations)
                for locale, text in translations.items():
                    if (locale != 'enUS' and normalize(text) and normalize(text) != normalize(english)
                            and not language_flags(locale, text, english, translations)):
                        self.localized_proofs.add(('items', entity_id, 'setName', normalize(english), locale))
                self.item_sets[entity_id] = (english, {'origin': 'original', 'source': 'wago',
                    'sourceLocale': 'enUS', 'sourceBuild': build}, proof)
            verified = {}
            for row in db.execute("SELECT kind,entity_id,locale,field,text,english,origin,provenance "
                                  "FROM records WHERE evidence='sourceSnapshot' AND origin IN ('original','community') "
                                  "AND flags='[]' AND source_path IN (SELECT path FROM inputs WHERE path NOT LIKE 'catalogs/%')"):
                provenance = json.loads(row['provenance'])
                provider = provenance.get('source')
                version = (provenance.get('sourceBuild') or provenance.get('sourceNamespace')
                           or provenance.get('sourceRevision'))
                vmangos_book = (row['kind'] in ('books', 'bookpages')
                    and provenance.get('source') == 'vmangos'
                    and provenance.get('scope') == 'vanillaReference'
                    and provenance.get('assetID')
                    and provenance.get('englishSha256') == hashlib.sha256((row['english'] or '').encode()).hexdigest()
                    and (row['kind'] != 'bookpages' or provenance.get('sourceRecord') == int(row['entity_id'])))
                locale = row['locale']
                text, english = normalize(row['text']), normalize(row['english'])
                if (locale not in OFFICIAL_LOCALES or provenance.get('sourceLocale') != locale or
                        (provenance.get('source') not in SOURCE_PROVIDERS and not vmangos_book)
                        or not version or not text or not english
                        or (locale == 'enUS' and (text != english or row['origin'] != 'original'))
                        or (locale != 'enUS' and text == english)):
                    continue
                identity = (row['kind'], row['entity_id'], row['field'])
                rank = (source_build(provenance) or (), provider == 'egLink')
                if identity not in verified or rank > verified[identity][0]:
                    verified[identity] = (rank, {})
                if rank == verified[identity][0]:
                    verified[identity][1].setdefault(english, provenance)
                if locale != 'enUS':
                    self.localized_proofs.add((*identity, english, locale))
            for identity, (_, contexts) in verified.items():
                self.source_contexts[identity] = frozenset(contexts)
                if len(contexts) == 1:
                    english, provenance = next(iter(contexts.items()))
                    self.proofs[(*identity, english)] = provenance
            self._index_quest_summary_proofs(db)
        finally:
            db.close()

    def _index_quest_summary_proofs(self, db):
        rows = db.execute("""
            SELECT entity_id, field, text, english, origin, provenance
            FROM records
            WHERE kind='quests' AND locale='enUS' AND evidence='sourceSnapshot' AND flags='[]'
              AND source_path IN (SELECT path FROM inputs WHERE path NOT LIKE 'catalogs/%')
              AND ((field='title' AND json_extract(provenance,'$.source')='blizzard')
                OR (field='summary' AND json_extract(provenance,'$.source')='questie'))
            """)
        confirmed_quests = set()
        summaries = {}
        for row in rows:
            provenance = json.loads(row['provenance'])
            text = normalize(row['text'])
            if not text or provenance.get('sourceLocale') != 'enUS':
                continue
            if row['field'] == 'title':
                namespace = str(provenance.get('sourceNamespace', ''))
                if row['origin'] == 'original' and re.fullmatch(r'static-[\w.]+-forever-eu', namespace):
                    confirmed_quests.add(row['entity_id'])
            elif (row['origin'] == 'community' and text == normalize(row['english'])
                  and provenance.get('layer') == 'composedStaticWithAuthoredCorrections'
                  and re.fullmatch(r'[0-9a-f]{40}', str(provenance.get('sourceRevision', '')))):
                summaries.setdefault(row['entity_id'], {})[text] = provenance
        for entity_id in confirmed_quests & summaries.keys():
            if len(summaries[entity_id]) == 1:
                text, provenance = next(iter(summaries[entity_id].items()))
                self.proofs.setdefault(('quests', entity_id, 'summary', text), provenance)

    def item_set_source(self, entity):
        set_id = entity.get('tooltipData', {}).get('itemSet')
        source = self.item_sets.get(str(set_id))
        owned = entity.get('tooltipData', {}).get('set', {}).get('name')
        if source and normalize(owned) == normalize(source[0]):
            return source
        return None

    def allows(self, kind, entity_id, field, english, entity=None):
        field = field.removeprefix('tooltip.')
        field = 'setName' if field == 'set.name' else field
        if kind == 'items' and field == 'setName':
            if entity is None:
                if not re.fullmatch(r'[1-9][0-9]*', str(entity_id)):
                    return False
                if str(entity_id) not in self.entities:
                    path = self.root / 'catalogs/items' / (str(entity_id) + '.json')
                    self.entities[str(entity_id)] = json.loads(path.read_text()) if path.is_file() else {}
                entity = self.entities[str(entity_id)]
            source = self.item_set_source(entity)
            owned = entity.get('tooltipData', {}).get('set', {}).get('name')
            return bool(source and source[2] and normalize(english if english is not None else owned) == normalize(source[0]))
        identity = (kind, str(entity_id), field)
        context = normalize(english)
        return self.source_contexts.get(identity, {context}) == {context} and (*identity, context) in self.proofs

    def has_localized_source(self, kind, entity_id, field, english, locale):
        field = field.removeprefix('tooltip.')
        field = 'setName' if field == 'set.name' else field
        return (kind, str(entity_id), field, normalize(english), locale) in self.localized_proofs


def is_captured_objective(record, line):
    origin = metadata(record, 'objectiveLines.' + str(line.get('index')))
    return (type(line.get('index')) is int and line['index'] > 0
            and bool(line.get('type'))
            and origin.get('origin') == 'original' and origin.get('source') == 'wowClient'
            and origin.get('sourceLocale') == 'enUS' and bool(origin.get('sourceBuild')))


def matches_client_objective_binding(quest, field, english, index, objective_type):
    binding = quest.get('clientObjectiveBindings', {}).get(field, {})
    return (type(index) is int and index > 0 and type(binding.get('index')) is int
            and binding['index'] == index and binding.get('type') == objective_type
            and binding.get('source') == 'wowClient' and bool(binding.get('sourceBuild'))
            and binding.get('sourceLocale') in OFFICIAL_LOCALES
            and binding.get('englishSha256') == hashlib.sha256(english.encode()).hexdigest())


def verified_catalog_quest_source(quest, field, english):
    source, origin = english_source(quest, field)
    if not normalize(source) or source != english or origin.get('sourceLocale') != 'enUS':
        return False
    record = quest['locales']['enUS']
    if field == 'summary':
        return origin.get('origin') in ('original', 'community') and bool(origin.get('source'))
    if field.startswith('objectiveLines.'):
        return any(field == 'objectiveLines.' + str(line.get('index'))
                   and (is_captured_objective(record, line)
                        or matches_client_objective_binding(quest, field, english, line['index'], line['type']))
                   for line in record.get('objectiveLines', []))
    if field == 'eventObjectiveLabel':
        if matches_client_objective_binding(quest, field, english, 1, 'event'):
            return True
        matches = [line for line in record.get('objectiveLines', [])
                   if line.get('type') == 'event' and normalize(line.get('text')) == normalize(english)]
        return len(matches) == 1 and is_captured_objective(record, matches[0])
    return False


def ai_block_reason(locale, kind, entity_id, field, english, evidence, *, quest=None):
    if (kind, field) in BOOK_FIELDS and locale != 'enUS':
        key = (kind, str(entity_id), field, normalize(english))
        if not evidence or key not in evidence.book_english:
            return 'noVerifiedEnglishBookText'
        if (*key, locale) in evidence.book_translations:
            return 'applicableBookSourceAvailable'
        return None
    if locale == 'enUS':
        return 'canonicalEnglishNeverAuthored'
    if evidence and evidence.has_localized_source(kind, entity_id, field, english, locale):
        return 'applicableOfficialSourceAvailable'
    if kind == 'quests' and quest is not None:
        if verified_catalog_quest_source(quest, field, english):
            return None
        if field == 'eventObjectiveLabel' or field.startswith('objectiveLines.'):
            return 'noVerifiedClientObjectiveBinding'
    if not evidence or not evidence.allows(kind, entity_id, field, english):
        return 'noVerifiedOfficialSource'
    return None


def pointer_block_reason(job, pointer, evidence, quests):
    field = pointer['field']
    if field == 'objectiveLines':
        field += '.' + str(pointer['index'])
    quest = quests.get(str(pointer['id'])) if pointer['kind'] == 'quests' else None
    return ai_block_reason(job['locale'], pointer['kind'], pointer['id'], field, job['source'],
                           evidence, quest=quest)


def filter_queue(queue, evidence, quests=None):
    """Apply the same policy to ordinary, foreign and fallback queue entry points."""
    result = {**queue, 'jobs': [], 'blocked': []}
    result['policyDatabase'] = str(evidence.database) if evidence else None
    for job in queue['jobs']:
        reuse = job.get('reuse', {})
        if reuse.get('metadata', {}).get('origin') in ('original', 'community'):
            result['jobs'].append(job)
            continue
        eligible, blocked, reasons = [], [], set()
        for pointer in job['pointers']:
            reason = pointer_block_reason(job, pointer, evidence, quests or {})
            if reason:
                blocked.append(pointer)
                reasons.add(reason)
            else:
                eligible.append(pointer)
        if blocked:
            result['blocked'].append({'jobId': job['jobId'], 'locale': job['locale'],
                                      'pointers': blocked, 'reasons': sorted(reasons)})
        if eligible:
            result['jobs'].append({**job, 'pointers': eligible})
    return result


def validate_queue_policy(queue, results, root):
    evidence = OfficialEvidence(queue['policyDatabase'], root) if queue.get('policyDatabase') else None
    quest_ids = {str(pointer['id']) for job in queue['jobs'] for pointer in job['pointers']
                 if pointer['kind'] == 'quests'}
    quests = load_catalog(root, 'quests', {'quests': quest_ids})['catalogs']['quests'] if quest_ids else {}
    submitted = {row['jobId']: row['translation'] for row in results}
    for job in queue['jobs']:
        reuse = job.get('reuse', {})
        if (reuse.get('metadata', {}).get('origin') in ('original', 'community')
                and submitted.get(job['jobId']) == reuse.get('text')):
            continue
        for pointer in job['pointers']:
            reason = pointer_block_reason(job, pointer, evidence, quests)
            if reason:
                raise ValueError(reason + ': ' + job['jobId'])


def validate_batch_policy(batch, results, evidence):
    for kind, entities in results.items():
        for entity_id, entity in entities.items():
            before = batch['records'][kind].get(entity_id) or {'locales': {}}
            for locale, record in entity['locales'].items():
                prior = before['locales'].get(locale, {})
                for field, text in text_fields(record).items():
                    origin = metadata(record, field)
                    if origin.get('origin') != 'ai':
                        continue
                    if text_fields(prior).get(field) == text and metadata(prior, field) == origin:
                        continue
                    english = text_fields(entity['locales'].get('enUS', {})).get(field)
                    if kind == 'quests' and field.startswith('objectiveLines.'):
                        index = int(field.split('.')[1])
                        source_type = next((line['type'] for line in entity['locales']['enUS'].get('objectiveLines', [])
                                            if line['index'] == index), None)
                        target_type = next(line['type'] for line in record['objectiveLines'] if line['index'] == index)
                        if not source_type or source_type != target_type:
                            raise ValueError('Objective type differs from English: ' + entity_id + '/' + field)
                    reason = ai_block_reason(locale, kind, entity_id, field, english, evidence,
                                             quest=before if kind == 'quests' else None)
                    if reason:
                        raise ValueError(reason + ': ' + kind + '/' + entity_id + '/' + field)
