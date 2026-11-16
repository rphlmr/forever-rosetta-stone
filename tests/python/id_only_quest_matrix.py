"""Measure quest rendering with IDs and structured client data only."""

import re
import sys
import json
import hashlib

from id_only_matrix_harness import ROOT, CaseReporter, IdOnlyHarness, NATIVE_TEXT, PROFILES, required_locales

sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog
from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES, indexed_client_targets, project_objectives


FIELDS = ('title', 'summary', 'description', 'eventObjectiveLabel')
AMOUNT = re.compile(r'\$(\d+)oa')
UNRESOLVED_DOLLAR = re.compile(r'\$[A-Za-z0-9]+')
SYMBOLIC_BRACE = re.compile(r'\{[A-Za-z_][A-Za-z0-9_]*\}')
SLASH_FORM = re.compile(r'<[^<>\s/]+/[^<>\s/]+>')
PLAYER_LABELS = {
    'enUS': ('Warrior', 'Human', 'Warrior', 'Human'),
    'deDE': ('Krieger', 'Mensch', 'Kriegerin', 'Mensch'),
    'esES': ('Guerrero', 'Humano', 'Guerrera', 'Humana'),
    'esMX': ('Guerrero', 'Humano', 'Guerrera', 'Humana'),
    'frFR': ('Guerrier', 'Humain', 'Guerrière', 'Humaine'),
    'itIT': ('Guerriero', 'Umano', 'Guerriera', 'Umana'),
    'ptBR': ('Guerreiro', 'Humano', 'Guerreira', 'Humana'),
    'ruRU': ('Воин', 'Человек', 'Воительница', 'Человек'),
    'koKR': ('전사', '인간', '전사', '인간'), 'zhCN': ('战士', '人类', '战士', '人类'),
    'zhTW': ('戰士', '人類', '戰士', '人類'),
    'csCZ': ('Válečník', 'Člověk', 'Válečnice', 'Člověk'),
    'daDK': ('Kriger', 'Menneske', 'Kriger', 'Menneske'),
    'hrHR': ('Ratnik', 'Čovjek', 'Ratnica', 'Čovjek'),
    'plPL': ('Wojownik', 'Człowiek', 'Wojowniczka', 'Człowiek'),
    'svSE': ('Krigare', 'Människa', 'Krigare', 'Människa'),
    'trTR': ('Savaşçı', 'İnsan', 'Savaşçı', 'İnsan'),
    'ukUA': ('Воїн', 'Людина', 'Воїтелька', 'Людина'),
}

# Independently retained expectations for the two controlled reactions. The API shape was
# captured for faction IDs 92/93 on build 70938; profile reactions are synthetic test inputs.
STANDING_LABELS = {
    'enUS': ('Neutral', 'Friendly'), 'csCZ': ('Neutrální', 'Přátelský'),
    'daDK': ('Neutral', 'Venlig'), 'deDE': ('Neutral', 'Freundlich'),
    'esES': ('Neutral', 'Amistoso'), 'esMX': ('Neutral', 'Amistoso'),
    'frFR': ('Neutre', 'Amical'), 'hrHR': ('Neutralan', 'Prijateljski'),
    'itIT': ('Neutrale', 'Amichevole'), 'koKR': ('중립', '약간 우호적'),
    'plPL': ('Neutralny', 'Przyjazny'), 'ptBR': ('Tolerado', 'Respeitado'),
    'ruRU': ('Равнодушие', 'Дружелюбие'), 'svSE': ('Neutral', 'Vänlig'),
    'trTR': ('Tarafsız', 'Dostane'), 'ukUA': ('Байдужість', 'Приязнь'),
    'zhCN': ('中立', '友善'), 'zhTW': ('中立', '友善'),
}


def localized_record(entity, locale):
    return entity['locales'].get(locale, {})


def format_expected(template, profile, indices, locale, faction_id=None):
    if not template:
        return None, 'missing target translation'

    standing = None
    if '{standing}' in template:
        reaction = profile.get('factionReactions', {}).get(faction_id)
        labels = STANDING_LABELS.get(locale)
        if not labels or reaction not in (4, 5):
            return None, 'reputation standing unavailable from structured test context'
        standing = labels[reaction - 4]
    if SLASH_FORM.search(template):
        return None, 'unsupported context-dependent slash selector'

    unknown = [int(match) for match in AMOUNT.findall(template) if int(match) not in indices]
    if unknown:
        return None, 'objective amount has no verified client index: ' + ', '.join(map(str, unknown))

    text = AMOUNT.sub(lambda match: str(profile.get('objectiveRequired', {}).get(
        int(match[1]), profile['required'])), template)
    if standing is not None:
        text = text.replace('{standing}', standing)
    text = text.replace('{current}', str(profile['current'])).replace('{required}', str(profile['required']))
    labels = PLAYER_LABELS.get(locale)
    if not labels:
        return None, 'unknown player labels for locale'
    player_class, race = labels[:2] if profile['sex'] == 2 else labels[2:]
    replacements = {'name': 'TestName', 'class': player_class, 'race': race}
    aliases = {'nom': 'name', 'nombre': 'name', 'имя': 'name', 'klasse': 'class', 'classe': 'class',
               'clase': 'class', 'volk': 'race', 'raza': 'race'}
    for token, name in (('N', 'name'), ('R', 'race'), ('C', 'class')):
        text = re.sub(r'\$[' + token + token.lower() + r'](?![A-Za-z])', lambda _: replacements[name], text)
    def replace_named(match):
        token = (match[1] or match[2]).lower()
        return replacements.get(aliases.get(token, token), match[0])

    text = re.sub(r'<([^<>\n]+)>|\{([A-Za-z]+)\}', replace_named, text)
    text = re.sub(r'\$[Gg]([^:;$\n.!?]+):([^:;$\n.!?]+);',
                  lambda match: match[1] if profile['sex'] == 2 else match[2], text)
    text = text.replace('$B', '\n')
    text = re.sub(r'\$b(?![A-Za-z])', '\n', text)
    if UNRESOLVED_DOLLAR.search(text):
        return None, 'unrecognized dollar template token'
    if SYMBOLIC_BRACE.search(text):
        return None, 'unrecognized symbolic brace token'

    return text, None


def read_actual_quest(harness, quest_id, field):
    quest = harness.addon.GetQuest(harness.addon, quest_id)
    value = quest and quest[field.encode()]
    return harness.addon.FormatQuestText(harness.addon, value, quest_id) if value else None


def get_objective_types(entity, observed=None):
    index_types = {}
    missing_relationships = {}

    for localized in entity['locales'].values():
        for line in localized.get('objectiveLines', []):
            index_types.setdefault(line['index'], set()).add(line['type'])

    for index, target in indexed_client_targets(entity):
        types = index_types.setdefault(index, set())
        if types:
            continue
        if target['kind'] == 'item':
            types.add('item')
        elif target['kind'] == 'npc' and target.get('type') == 'monster':
            types.add('monster')
        else:
            missing_relationships[index] = target['kind']

    for index, kind in enumerate(observed or [], 1):
        types = index_types.setdefault(index, set())
        if kind:
            if types and types != {kind}:
                raise ValueError('Owned objective type conflicts with client capture')
            types.add(kind)
            missing_relationships.pop(index, None)
        elif not types:
            missing_relationships[index] = 'untyped captured row'

    return index_types, missing_relationships


def verified_faction_targets(entity):
    return {index: target['id'] for index, target in indexed_client_targets(entity)
            if target.get('kind') == 'faction' and target.get('type') == 'reputation'
            and target.get('index') == index and type(target.get('id')) is int and target['id'] > 0}


def captured_objective_types(root, quests):
    path = root / 'tests/fixtures/quest-objectives-70938.json'
    if not path.exists():
        return {}
    fixture = json.loads(path.read_text())
    if fixture.get('sourceLocale') != 'enUS' or fixture.get('sourceBuild') != '70938':
        raise ValueError('Invalid objective capture fixture identity')
    result = {}
    for identity, entry in fixture['quests'].items():
        if identity not in quests:
            continue
        title = quests[identity].get('locales', {}).get('enUS', {}).get('title', '')
        if hashlib.sha256(title.encode()).hexdigest() != entry['titleSha256']:
            raise ValueError('Captured quest title changed: ' + identity)
        if not isinstance(entry['types'], list) or any(not isinstance(value, str) for value in entry['types']):
            raise ValueError('Invalid captured objective types: ' + identity)
        result[identity] = entry['types']
    return result


def run_matrix(locales=None, ids=None, profiles=None, root=ROOT):
    document = load_catalog(root, 'quests', None if ids is None else {'quests': {str(value) for value in ids}})
    quests = document['catalogs']['quests']
    locales = list(required_locales(root) if locales is None else locales)
    profiles = list(PROFILES if profiles is None else profiles)
    exclusions = {str(key): value['usageStatus'] for key, value in quests.items()
                  if value.get('usageStatus') in EXCLUDED_QUEST_STATUSES}
    included = {key: value for key, value in quests.items() if key not in exclusions}
    item_ids = {str(target['id']) for quest in included.values()
                for target in quest.get('clientObjectiveTargets', []) if target['kind'] == 'item'}
    items = load_catalog(root, 'items', {'items': item_ids})['catalogs']['items']
    npc_ids = {str(target['id']) for quest in included.values()
               for target in quest.get('clientObjectiveTargets', []) if target['kind'] == 'npc'}
    npcs = load_catalog(root, 'npcs', {'npcs': npc_ids})['catalogs']['npcs'] if npc_ids else {}
    observed = captured_objective_types(root, included)
    harness = IdOnlyHarness(root=root)
    reporter = CaseReporter('quests', locales, profiles)

    for quest_id, entity in included.items():
        records = entity['locales']
        lines = {}
        for locale in locales:
            original = localized_record(entity, locale)
            item_locale = locale
            lines[locale] = {line['index']: line for line in project_objectives(
                entity, original, item_locale, items, npcs)[0]}

        index_types, missing_relationships = get_objective_types(entity, observed.get(quest_id))
        factions = verified_faction_targets(entity)
        indices = set(index_types)

        for locale in locales:
            record = localized_record(entity, locale)
            for profile_name in profiles:
                harness.set_context(locale, int(quest_id), profile_name, entity_kind='quests')
                harness.set_verified_factions(set(factions.values()), profile_name)
                profile = {**harness.profile,
                           'objectiveRequired': {index: harness.profile['required'] + 3 * (index - 1)
                                                 for index in indices}}

                def line_profile(index):
                    return {**profile, 'current': profile['current'] + index - 1,
                            'required': profile['objectiveRequired'][index]}
                rows = []
                for index in range(1, max(indices, default=0) + 1):
                    target = lines[locale].get(index)
                    kinds = index_types.get(index, set())
                    kind = target['type'] if target and target['type'] in kinds else next(iter(sorted(kinds)),
                                                                                           'matrix-placeholder')
                    amounts = line_profile(index) if index in indices else profile
                    rows.append({'type': kind, 'text': NATIVE_TEXT, 'numFulfilled': amounts['current'],
                                 'numRequired': amounts['required']})
                harness.set_objectives(rows)
                for field in FIELDS:
                    case = {'id': int(quest_id), 'field': field, 'locale': locale, 'profile': profile_name}
                    applicable = field == 'title' or any(value.get(field) for value in records.values())
                    if not applicable:
                        reporter.not_applicable(case, 'field absent from maintained locales and source evidence')
                        continue

                    template = record.get(field)
                    expected, reason = format_expected(template, profile, indices, locale)
                    actual, error, forbidden = harness.attempt(
                        lambda field=field: read_actual_quest(harness, int(quest_id), field))
                    reporter.record(case, expected, actual, error, forbidden, reason)

                    if field == 'eventObjectiveLabel':
                        harness.set_objectives([{'type': 'event', 'text': NATIVE_TEXT}])
                        event_case = {**case, 'surface': 'event'}
                        indexed_event = lines[locale].get(1)
                        event_template = (indexed_event['text'] if indexed_event and indexed_event['type'] == 'event'
                                          else template)
                        event_expected, event_reason = format_expected(event_template, profile, indices, locale)
                        def render_event():
                            result = harness.addon.GetProgressLines(harness.addon, int(quest_id))
                            return result[1][b'translated'] if result and result[1] else None

                        actual, error, forbidden = harness.attempt(render_event)
                        reporter.record(event_case, event_expected, actual, error, forbidden, event_reason)
                        harness.set_objectives(rows)

                if not any(index_types.values()) and not missing_relationships:
                    objective_case = {'id': int(quest_id), 'field': 'objectiveLines', 'locale': locale,
                                      'profile': profile_name}
                    if entity.get('objectiveTargets'):
                        reporter.record(objective_case, None, None, reason='missing verified client objective index')
                    else:
                        reporter.not_applicable(objective_case, 'no objective evidence')
                for index, kind in missing_relationships.items():
                    reporter.record({'id': int(quest_id), 'field': 'objectiveLines', 'locale': locale,
                                     'profile': profile_name, 'index': index, 'surface': kind},
                                    None, None, reason='missing verified live objective type')
                for index, kinds in sorted(index_types.items()):
                    for kind in sorted(kinds):
                        case = {'id': int(quest_id), 'field': 'objectiveLines', 'locale': locale,
                                'profile': profile_name, 'index': index, 'surface': kind}
                        target = lines[locale].get(index)
                        template = target.get('text') if target and target.get('type') == kind else None
                        amounts = line_profile(index)
                        expected, reason = format_expected(template, amounts, indices, locale,
                                                           factions.get(index) if kind == 'reputation' else None)
                        live = list(rows)
                        live[index - 1] = {'type': kind, 'text': NATIVE_TEXT, 'numFulfilled': amounts['current'],
                                           'numRequired': amounts['required']}
                        harness.set_objectives(live)

                        def render():
                            result = harness.addon.GetProgressLines(harness.addon, int(quest_id))
                            line = result[index] if result else None
                            return line and line[b'translated']

                        actual, error, forbidden = harness.attempt(render)
                        reporter.record(case, expected, actual, error, forbidden, reason)
                harness.set_objectives(None)

    return reporter.finish([int(value) for value in included], exclusions=exclusions, full_scope=ids is None)
