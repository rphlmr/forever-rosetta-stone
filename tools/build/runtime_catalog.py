"""Project full source catalogs into the fields shipped in the addon database."""

import hashlib
import re
from tools.catalogs.english_scope import has_english_text, identity_field

QUEST_FIELDS = ('title', 'summary', 'description', 'eventObjectiveLabel', 'objectiveLines')
QUEST_DIALOGUE_STAGES = frozenset(('accept', 'progress', 'complete'))
NPC_DIALOGUE_STAGES = frozenset(('gossip', 'option'))
EXCLUDED_QUEST_STATUSES = frozenset(('test', 'notImplemented', 'placeholder', 'unused'))
TOOLTIP_RULE_FIELDS = frozenset((
    'effects', 'rangeMaxByTarget', 'rangeMin', 'rangeMinByTarget', 'rangeMax', 'durationMs',
    'procChance', 'baseLevel', 'spellLevel', 'maxLevel', 'maxStacks', 'maxTargets', 'procCharges', 'variables',
    'requiredToolCategories', 'requiredToolItems', 'requiredForms', 'requiredReagentItems', 'createdItemIDs', 'recipeSpellIDs',
    'classID', 'inventoryType', 'subclassID', 'quality', 'requiredLevel', 'itemSet', 'limitCategory',
    'containerSlots', 'descriptionRow', 'schoolMask', 'durationModifiers', 'requirements',
    'limitCategoryID', 'boundAreaIDs', 'requiredHolidayNames', 'requiredTransmogHolidayNames', 'requiredLockTypes',
    'requiredItemSubclasses',
    'equipmentRequirementType',
    'requiredEquipment',
    'interactionLabelID',
))


LUA_SIMPLE_ESCAPES = {'a': '\a', 'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v'}


def decode_client_escapes(text):
    """Decode the Lua 5.1 string escapes that GlobalStrings exports keep (`\\32`, `\\"`, `\\\\`).

    The client loads these strings as Lua source, so it shows the decoded text. Unknown escapes
    keep the escaped character, like Lua 5.1; a trailing lone backslash stays as written.
    """
    out, index = [], 0
    while index < len(text):
        char = text[index]
        if char != '\\' or index + 1 == len(text):
            out.append(char)
            index += 1
            continue
        digits = re.match(r'[0-9]{1,3}', text[index + 1:])
        if digits and int(digits[0]) < 256:
            out.append(chr(int(digits[0])))
            index += 1 + len(digits[0])
            continue
        following = text[index + 1]
        out.append(LUA_SIMPLE_ESCAPES.get(following, following))
        index += 2
    return ''.join(out)


def get_has_ai_translation(kind, entity_id, locale, original):
    metadata = original.get('translationMetadata', {}).get('fields', {})
    text_fields = [field for field in QUEST_FIELDS if field != 'objectiveLines' and field in original]
    text_fields += ['objectiveLines.' + str(line['index']) for line in original.get('objectiveLines', [])]

    if kind != 'quests':
        text_fields = [identity_field(kind)] if original.get(identity_field(kind)) else []

        if kind in ('items', 'spells'):
            text_fields.extend(field for field in ('description', 'auraDescription', 'rank', 'nameDescription', 'setName', 'equipmentRequirement')
                               if field in original)
        elif kind == 'npcs' and 'subName' in original:
            text_fields.append('subName')
        elif kind == 'races' and 'nameFemale' in original:
            text_fields.append('nameFemale')
        elif kind == 'itemenchantments' and 'nameHorde' in original:
            text_fields.append('nameHorde')

    has_ai_translation = False

    for field in text_fields:
        origin = metadata.get(field, {}).get('origin')

        if origin not in ('original', 'community', 'ai'):
            raise ValueError(f'Expected field translationMetadata: {kind}/{entity_id}/{locale}/{field}')

        has_ai_translation = has_ai_translation or origin == 'ai'

    return has_ai_translation


def indexed_client_targets(quest):
    """Resolve explicit captured indices or the legacy contiguous list positions."""
    result, seen = [], set()
    for position, target in enumerate(quest.get('clientObjectiveTargets', []), start=1):
        index = target.get('index', position)
        if type(index) is not int or index <= 0 or index in seen:
            raise ValueError(f'Invalid or duplicate client objective index: {index!r}')
        seen.add(index)
        result.append((index, target))
    return result


def project_objectives(quest, original, locale, items, npcs=None):
    lines = [{key: line[key] for key in ('index', 'type', 'text') if key in line}
             for line in original.get('objectiveLines', [])]
    indices = {line['index'] for line in lines}
    has_ai_translation = False

    for index, target in indexed_client_targets(quest):
        if (target.get('kind') == 'faction' and target.get('type') == 'reputation'
                and 'index' in target and type(target.get('id')) is int and target['id'] > 0):
            for line in lines:
                if line.get('index') == index and line.get('type') == 'reputation':
                    line['factionID'] = target['id']
                    break
            continue
        if index in indices:
            continue
        if target['kind'] == 'item':
            kind, objective_type, entities = 'items', 'item', items
        elif target['kind'] == 'npc' and target.get('type') == 'monster':
            kind, objective_type, entities = 'npcs', 'monster', npcs or {}
        else:
            continue
        item = entities.get(str(target['id']), {}).get('locales', {}).get(locale)

        if not item or not item.get('name'):
            continue

        has_ai_translation |= get_has_ai_translation(kind, target['id'], locale, item)
        lines.append({'index': index, 'type': objective_type, 'text': item['name'] + ': {current}/{required}'})

    return sorted(lines, key=lambda line: line['index']), has_ai_translation


def matches_canonical_english(entity, field, metadata):
    fingerprint = metadata.get('canonicalEnglishSha256')
    if fingerprint is None:
        return True
    source = entity['locales'].get('enUS', {}).get(field)
    return isinstance(source, str) and hashlib.sha256(source.encode()).hexdigest() == fingerprint


def get_tooltip_source_text(entity, locale, field):
    """Read non-AI catalog evidence for offline translation tooling."""
    localized = entity['locales'].get(locale, {})
    key = 'setName' if field == 'set.name' else field
    metadata = localized.get('translationMetadata', {}).get('fields', {}).get(key, {})

    if metadata.get('origin') == 'ai' or not matches_canonical_english(entity, key, metadata):
        return None

    value = localized.get(key)
    if value is None and locale == 'enUS' and key == 'setName':
        return entity.get('tooltipData', {}).get('set', {}).get('name')
    return value


def project_tooltip_details(entity, original, locale):
    tooltip = entity.get('tooltipData', {})
    details = {}

    if locale == 'enUS':
        details = {key: value for key, value in tooltip.items()
                   if key in TOOLTIP_RULE_FIELDS}

        if 'set' in tooltip:
            details['set'] = {key: value for key, value in tooltip['set'].items()
                              if key in ('name', 'items', 'bonuses')}

    for field in ('rank', 'nameDescription', 'equipmentRequirement'):
        value = original.get(field)

        if value and has_english_text(entity, field):
            details[field] = value

    if 'reputationRequirement' in original:
        text = original['reputationRequirement']
        proof = original.get('translationMetadata', {}).get('fields', {}).get('reputationRequirement', {})
        if (not tooltip.get('requirements', {}).get('reputation')
                or not isinstance(text, str) or not text.strip()
                or proof.get('origin') != 'original' or proof.get('source') != 'clientCapture'
                or proof.get('sourceLocale') != locale or not proof.get('sourceBuild')
                or proof.get('sourceTextSha256') != hashlib.sha256(text.encode()).hexdigest()):
            raise ValueError('Invalid item reputation requirement capture')
        details['reputationRequirement'] = text

    if 'set' in tooltip:
        name = original.get('setName')

        if name and has_english_text(entity, 'setName'):
            details['set'] = {**details.get('set', {}), 'name': name}

    for field in ('description', 'auraDescription'):
        value = original.get(field)

        if value and has_english_text(entity, field):
            details[field] = value
        variants = original.get(field + 'Variants')
        if variants is not None:
            english = entity.get('locales', {}).get('enUS', {}).get(field)
            if (not isinstance(english, str) or not english or not isinstance(variants, list)
                    or not 1 <= len(variants) <= 4 or any(not isinstance(text, str) for text in variants)
                    or len(set(variants)) != len(variants)):
                raise ValueError('Invalid owned description variants')
            metadata = original.get('translationMetadata', {}).get('fields', {})
            for index, text in enumerate(variants):
                proof = metadata.get(f'{field}Variants.{index}', {})
                if (not isinstance(text, str) or not text or text == value
                        or proof.get('origin') != 'original'
                        or proof.get('canonicalEnglishSha256') != hashlib.sha256(english.encode()).hexdigest()):
                    raise ValueError('Missing or stale native variant provenance')
            details[field + 'Variants'] = list(variants)

    original_fields = {field: True for field in ('description', 'auraDescription')
                       if field in details and original.get('translationMetadata', {}).get('fields', {})
                       .get(field, {}).get('origin') == 'original'}
    if original_fields:
        details['originalFields'] = original_fields

    return details


def project_localized_record(kind, entity_id, entity, locale, items, npcs=None):
    """Select runtime text and derive its AI flag without modifying source records."""
    english = entity.get('locales', {}).get('enUS', {}).get('name')
    if kind == 'globalstrings' and (not isinstance(english, str) or english == ''):
        return None
    if kind != 'globalstrings' and not has_english_text(entity, identity_field(kind)):
        return None
    original = entity['locales'][locale]
    if kind in ('spells', 'talents') and locale != 'enUS':
        metadata = original.get('translationMetadata', {}).get('fields', {})
        outdated = {field for field, proof in metadata.items()
                    if field in original and not matches_canonical_english(entity, field, proof)}
        if outdated:
            # Keep the owned translations available for review without rendering obsolete text.
            original = {field: value for field, value in original.items() if field not in outdated}
    has_ai_translation = get_has_ai_translation(kind, entity_id, locale, original)

    if kind == 'bookpages':
        localized = {'description': original['description']} if original.get('description') else {}
    elif kind == 'quests':
        localized = {key: original[key] for key in QUEST_FIELDS if key in original
                     and (key == 'objectiveLines' or has_english_text(entity, key))}
        offer = original.get('dialogue', {}).get('description')
        if offer is not None:
            context = entity.get('dialogueContexts', {}).get('description', {})
            source = entity['locales']['enUS'].get('description')
            origin = original.get('translationMetadata', {}).get('fields', {}).get('dialogue.description', {}).get('origin')
            if (locale == 'enUS' or context.get('stage') != 'accept' or context.get('sourceField') != 'description'
                    or not isinstance(source, str) or not source.strip()
                    or not isinstance(offer, str) or not offer.strip() or origin not in ('original', 'community', 'ai')):
                raise ValueError(f'Invalid canonical quest offer: quests/{entity_id}/{locale}')
            current = localized.get('description')
            if (context.get('sourceDescriptionSha256') == hashlib.sha256(source.encode()).hexdigest()
                    and (not current or current.split() == source.split())):
                localized['description'] = offer
                has_ai_translation |= origin == 'ai'
        objective_lines, objectives_have_ai = project_objectives(entity, original, locale, items, npcs)

        if objective_lines:
            localized['objectiveLines'] = objective_lines

        has_ai_translation |= objectives_have_ai
    else:
        has_name = (isinstance(original.get('name'), str) if kind == 'globalstrings' else bool(original.get('name')))
        localized = {'name': original['name']} if has_name else {}

        if kind == 'globalstrings' and has_name:
            # Owned records keep the export's raw Lua source; ship the text the client shows.
            localized['name'] = decode_client_escapes(localized['name'])

        if kind in ('items', 'spells'):
            details = project_tooltip_details(entity, original, locale)

            if details:
                localized['details'] = details
        elif kind == 'npcs' and original.get('subName') and has_english_text(entity, 'subName'):
            # NPC subnames ship in the details column; faction rules stay in the shared pack.
            localized['details'] = {'subName': original['subName']}
        elif kind == 'races' and original.get('nameFemale') and has_english_text(entity, 'nameFemale'):
            localized['details'] = {'nameFemale': original['nameFemale']}
        elif kind == 'itemenchantments':
            if has_name:
                localized['name'] = decode_client_escapes(original['name'])
            if original.get('nameHorde') and has_english_text(entity, 'nameHorde'):
                localized['details'] = {'nameHorde': decode_client_escapes(original['nameHorde'])}

    if not localized:
        return None

    return {**localized, 'hasAITranslation': has_ai_translation}


def project_dialogue(kind, entity_id, entity, locale):
    original = entity['locales'][locale]
    lines = original.get('dialogue', {})
    english = entity['locales']['enUS'].get('dialogue', {})
    contexts = entity.get('dialogueContexts', {})
    metadata = original.get('translationMetadata', {}).get('fields', {})
    stages = QUEST_DIALOGUE_STAGES if kind == 'quests' else NPC_DIALOGUE_STAGES
    dialogue, has_ai = [], False
    for key, text in sorted(lines.items()):
        origin = metadata.get('dialogue.' + key, {}).get('origin')
        context = contexts.get(key, {})
        if kind == 'quests' and key == 'description' and context.get('sourceField') == 'description':
            continue
        if (key not in english or context.get('stage') not in stages or not isinstance(text, str)
                or not text.strip() or origin not in ('original', 'community', 'ai')):
            raise ValueError(f'Invalid dialogue: {kind}/{entity_id}/{locale}/{key}')
        npc_id, object_id, sex = context.get('npcId'), context.get('objectId'), context.get('playerSex')
        if kind == 'quests':
            speakers = [value for value in (npc_id, object_id) if value is not None]
            if len(speakers) != 1 or type(speakers[0]) is not int or speakers[0] <= 0:
                raise ValueError(f'Invalid dialogue speaker: quests/{entity_id}/{key}')
        if sex not in (None, 2, 3):
            raise ValueError(f'Invalid dialogue player sex: {kind}/{entity_id}/{key}')
        row = {'key': key, 'stage': context['stage'], 'text': text}
        if context.get('scope') == 'forever':
            row['scope'] = 'forever'
        if npc_id is not None:
            row['npcID'] = npc_id
        if object_id is not None:
            row['objectID'] = object_id
        if sex is not None:
            row['playerSex'] = sex
        dialogue.append(row)
        has_ai |= origin == 'ai'
    if dialogue:
        return {'dialogue': dialogue, 'hasAITranslation': has_ai}


def project_tooltip_rules(entity):
    """Separate language-independent tooltip facts from localized source text."""
    tooltip = entity.get('tooltipData', {})
    interaction = tooltip.get('interactionLabelID')
    if interaction is not None and (type(interaction) is not int or interaction <= 0):
        raise ValueError('Invalid interactionLabelID')
    equipment = tooltip.get('requiredEquipment')
    if equipment is not None:
        if (not isinstance(equipment, dict)
                or set(equipment) != {'itemClassID', 'subclassMask', 'inventoryTypeMask'}
                or any(type(value) is not int for value in equipment.values())
                or equipment['itemClassID'] < 0):
            raise ValueError('Invalid requiredEquipment')
    # TotemCategory IDs and item IDs are separate namespaces with separate fields.
    for field in ('requiredToolCategories', 'requiredToolItems', 'requiredForms', 'requiredReagentItems', 'createdItemIDs', 'recipeSpellIDs',
                  'boundAreaIDs', 'requiredHolidayNames', 'requiredTransmogHolidayNames', 'requiredLockTypes', 'requiredItemSubclasses'):
        if field in tooltip:
            values = tooltip[field]
            if (not isinstance(values, list) or not values
                    or any(type(value) is not int or value <= 0 for value in values)
                    or len(set(values)) != len(values)):
                raise ValueError('Invalid ' + field + ' IDs')
    if 'limitCategoryID' in tooltip and (type(tooltip['limitCategoryID']) is not int or tooltip['limitCategoryID'] <= 0):
        raise ValueError('Invalid limitCategoryID')
    if 'equipmentRequirementType' in tooltip and (type(tooltip['equipmentRequirementType']) is not int
                                                or tooltip['equipmentRequirementType'] < 0):
        raise ValueError('Invalid equipmentRequirementType')
    reputation = tooltip.get('requirements', {}).get('reputation')
    if reputation is not None:
        if (not isinstance(reputation, dict) or set(reputation) != {'factionID', 'standing'}
                or type(reputation['factionID']) is not int or reputation['factionID'] <= 0
                or type(reputation['standing']) is not int or not 1 <= reputation['standing'] <= 8
                or not any('reputationRequirement' in row for row in entity['locales'].values())):
            raise ValueError('Invalid item reputation requirement binding')
    if 'descriptionRow' in tooltip:
        binding = tooltip['descriptionRow']
        metadata = tooltip.get('descriptionRowSourceMetadata', {})
        source = entity.get('locales', {}).get('enUS', {}).get('description')
        if (not isinstance(binding, dict) or binding.get('lineType') != 'ItemSpellTriggerLearn'
                or binding.get('triggerType') != 6 or type(binding.get('spellID')) is not int
                or binding['spellID'] <= 0 or not isinstance(source, str) or not source.strip()
                or not isinstance(metadata, dict) or metadata.get('source') != 'clientCapture'
                or metadata.get('sourceLocale') != 'enUS' or not metadata.get('sourceBuild')
                or not isinstance(metadata.get('captureSha256'), str)
                or not re.fullmatch(r'[0-9a-f]{64}', metadata['captureSha256'])
                or metadata.get('sourceDescriptionSha256') != hashlib.sha256(source.encode()).hexdigest()
                or not isinstance(tooltip.get('effects'), list)
                or len([e for e in tooltip.get('effects', []) if isinstance(e, dict)
                        and e.get('spellID') == binding['spellID'] and e.get('triggerType') == 6]) != 1):
            raise ValueError('Invalid or stale item description row binding')
    rules = {key: value for key, value in tooltip.items() if key in TOOLTIP_RULE_FIELDS}

    if 'set' in tooltip:
        shared_set = {key: value for key, value in tooltip['set'].items() if key in ('items', 'bonuses')}

        if shared_set:
            rules['set'] = shared_set

    return rules


def equipment_requirement_sources(spells):
    """Share owned UI labels only across identical sourced equipment restrictions.

    References retain their catalog owners. Conflicting localized labels are not
    exported for that locale; no entity IDs or translated wording are inferred.
    """
    def signature(record):
        equipment = record.get('tooltipData', {}).get('requiredEquipment')
        if not equipment:
            return None
        project_tooltip_rules(record)
        return (equipment['itemClassID'], equipment['subclassMask'] & 0xFFFFFFFF,
                equipment['inventoryTypeMask'] & 0xFFFFFFFF)

    groups = {}
    for entity_id, record in spells.items():
        key = signature(record)
        kind = record.get('tooltipData', {}).get('equipmentRequirementType')
        english = record.get('locales', {}).get('enUS', {}).get('equipmentRequirement')
        if key is None or type(kind) is not int or kind < 0 or not isinstance(english, str) or not english:
            continue
        group = groups.setdefault(key, {}).setdefault(kind, {})
        for locale, localized in record['locales'].items():
            label = localized.get('equipmentRequirement')
            if isinstance(label, str) and label:
                group.setdefault(locale, {}).setdefault(label, []).append(int(entity_id))
    result = {}
    for entity_id, record in spells.items():
        group = groups.get(signature(record), {})
        references = {kind: {locale: min(next(iter(labels.values())))
                             for locale, labels in locales.items() if len(labels) == 1}
                      for kind, locales in group.items()}
        if references:
            result[int(entity_id)] = references
    return result
