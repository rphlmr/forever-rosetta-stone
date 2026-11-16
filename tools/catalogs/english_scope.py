"""Keep catalog text within the retained English source field's scope."""

import copy

TEXT_FIELDS = ('name', 'nameFemale', 'title', 'summary', 'description', 'auraDescription', 'rank',
               'nameDescription', 'setName', 'eventObjectiveLabel', 'subName', 'equipmentRequirement')


def identity_field(kind):
    return 'title' if kind == 'quests' else 'description' if kind == 'bookpages' else 'name'


def has_english_text(entity, field):
    value = entity.get('locales', {}).get('enUS', {}).get(field)
    if not value and field == 'setName':
        value = entity.get('tooltipData', {}).get('set', {}).get('name')
    elif not value and field in ('rank', 'nameDescription'):
        value = entity.get('tooltipData', {}).get(field)
    if not isinstance(value, str):
        return False
    return bool(value.strip()) if field in ('name', 'title') else bool(value)


def prune_unbacked_text(kind, entity):
    """Remove unsupported fields in all languages; an entity needs its English identity."""
    if kind == 'globalstrings':
        return copy.deepcopy(entity)
    identity = identity_field(kind)
    if not has_english_text(entity, identity):
        return None
    result = copy.deepcopy(entity)
    unsupported = [field for field in TEXT_FIELDS if not has_english_text(entity, field)]
    for record in result.get('locales', {}).values():
        metadata = record.get('translationMetadata', {}).get('fields', {})
        for field in unsupported:
            record.pop(field, None)
            metadata.pop(field, None)
    return result
