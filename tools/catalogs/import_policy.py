"""Deterministic source selection and eligibility for authored translations."""

import hashlib
import csv
import json
import re
from pathlib import Path

from datasources.corpus.translation_corpus import open_corpus, language_flags
from tools.catalogs.official_text import OFFICIAL_LOCALES, TEXT_FIELDS, SOURCE_PROVIDERS

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
    """Index verified evidence for authoring additional-language translations."""

    def __init__(self, database, root):
        self.database = verify_sources(database, root)
        self.root = Path(root).resolve()
        self.proofs = {}
        self.item_sets = {}
        self.entities = {}
        self.extra_inputs = {}
        db = open_corpus(self.database)
        try:
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
                proof = any(locale != 'enUS' and normalize(text) and normalize(text) != normalize(english)
                            and not language_flags(locale, text, english, translations)
                            for locale, text in translations.items())
                self.item_sets[entity_id] = (english, {'origin': 'original', 'source': 'wago',
                    'sourceLocale': 'enUS', 'sourceBuild': build}, proof)
            for row in db.execute("SELECT kind,entity_id,locale,field,text,english,provenance,flags "
                                  "FROM records WHERE evidence='sourceSnapshot' AND origin IN ('original','community') "
                                  "AND locale!='enUS' AND flags='[]'"):
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
                if (row['locale'] not in OFFICIAL_LOCALES or
                        (provenance.get('source') not in SOURCE_PROVIDERS and not vmangos_book)
                        or not version
                        or not normalize(row['english']) or not normalize(row['text'])
                        or normalize(row['text']) == normalize(row['english'])):
                    continue
                key = (row['kind'], row['entity_id'], row['field'], normalize(row['english']))
                self.proofs.setdefault(key, {'locale': row['locale'], **provenance})
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
        return (kind, str(entity_id), field, normalize(english)) in self.proofs


def ai_block_reason(locale, kind, entity_id, field, english, evidence):
    if locale in OFFICIAL_LOCALES:
        return 'officialLocaleNeverAuthored'
    if not evidence or not evidence.allows(kind, entity_id, field, english):
        return 'noVerifiedOfficialTranslation'
    return None


def filter_queue(queue, evidence):
    """Apply the same policy to ordinary, foreign and fallback queue entry points."""
    result = {**queue, 'jobs': [], 'blocked': []}
    result['policyDatabase'] = str(evidence.database) if evidence else None
    for job in queue['jobs']:
        reuse = job.get('reuse', {})
        if reuse.get('metadata', {}).get('origin') in ('original', 'community'):
            result['jobs'].append(job)
            continue
        reasons = {ai_block_reason(job['locale'], pointer['kind'], pointer['id'], pointer['field'],
                                   job['source'], evidence) for pointer in job['pointers']}
        reasons.discard(None)
        if reasons:
            result['blocked'].append({'jobId': job['jobId'], 'locale': job['locale'],
                                      'pointers': job['pointers'], 'reasons': sorted(reasons)})
        else:
            result['jobs'].append(job)
    return result


def validate_queue_policy(queue, results, root):
    evidence = OfficialEvidence(queue['policyDatabase'], root) if queue.get('policyDatabase') else None
    submitted = {row['jobId']: row['translation'] for row in results}
    for job in queue['jobs']:
        reuse = job.get('reuse', {})
        if (reuse.get('metadata', {}).get('origin') in ('original', 'community')
                and submitted.get(job['jobId']) == reuse.get('text')):
            continue
        for pointer in job['pointers']:
            reason = ai_block_reason(job['locale'], pointer['kind'], pointer['id'], pointer['field'],
                                     job['source'], evidence)
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
                    reason = ai_block_reason(locale, kind, entity_id, field, english, evidence)
                    if reason:
                        raise ValueError(reason + ': ' + kind + '/' + entity_id + '/' + field)
