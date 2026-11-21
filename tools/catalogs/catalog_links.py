"""Inspect explicit owned catalog relationships without inferring identities from text."""

import re

KINDS = ('areas', 'classes', 'creaturetypes', 'factions', 'items', 'maps', 'npcs',
         'quests', 'spells', 'talents')


def spell_references(template):
    """Return template dependencies, keeping cast, aura and name fields separate."""
    references = set()
    for token, reference in re.findall(r'\$@(spelldesc|spelltooltip|spellaura|spellname)<?(\d+)>?', template):
        references.add((int(reference), {'spelldesc': 'description', 'spellaura': 'auraDescription',
                                       'spellname': 'name', 'spelltooltip': 'description'}[token]))
    for reference in re.findall(r'\$(\d+)[sSmMdDtTuUxXhniraAoOwW]\d*', template):
        references.add((int(reference), None))
    for reference in re.findall(r'\$[*/]\d+\.?\d*;(\d+)[sSmM]\d*', template):
        references.add((int(reference), None))
    return references


def entity_links(kind, entity):
    """Yield (field path, target kind, ID, required text field, locale)."""
    def link(path, target, value, field=None, locale=None):
        if type(value) is int and value > 0:
            return [(path, target, value, field, locale)]
        return []

    if kind == 'quests':
        yield from link('areaId', 'areas', entity.get('areaId'), 'name')
        for target_kind, entries in entity.get('objectiveTargets', {}).items():
            target = {'item': 'items', 'npc': 'npcs', 'faction': 'factions'}.get(target_kind)
            if target:
                for index, entry in enumerate(entries):
                    yield from link(f'objectiveTargets.{target_kind}.{index}', target, entry.get('id'), 'name')
        for index, entry in enumerate(entity.get('clientObjectiveTargets', [])):
            target = {'item': 'items', 'npc': 'npcs', 'faction': 'factions'}.get(entry.get('kind'))
            if target:
                yield from link(f'clientObjectiveTargets.{index}', target, entry.get('id'), 'name')
        for locale, text in entity.get('locales', {}).items():
            for line in text.get('objectiveLines', []):
                yield from link(f'objectiveLines.{line["index"]}.factionID', 'factions',
                                line.get('factionID'), 'name', locale)
    elif kind == 'npcs':
        yield from link('factionId', 'factions', entity.get('factionId'), 'name')
    elif kind == 'talents':
        yield from link('spellId', 'spells', entity.get('spellId'), 'name')
        for index, spell in enumerate(entity.get('spellRankIds', [])):
            yield from link(f'spellRankIds.{index}', 'spells', spell, 'name')
    tooltip = entity.get('tooltipData', {})
    for field, target in (('requiredForms', 'shapeshiftforms'), ('requiredReagentItems', 'items'),
                          ('createdItemIDs', 'items'), ('recipeSpellIDs', 'spells'), ('boundAreaIDs', 'areas'),
                          ('requiredHolidayNames', 'holidaynames'), ('requiredTransmogHolidayNames', 'holidaynames'),
                          ('requiredLockTypes', 'locktypes'), ('requiredItemSubclasses', 'itemsubclasses')):
        for index, entity_id in enumerate(tooltip.get(field, [])):
            yield from link(f'tooltipData.{field}.{index}', target, entity_id, 'name')
    if kind == 'items':
        yield from link('tooltipData.limitCategoryID', 'itemlimitcategories', tooltip.get('limitCategoryID'), 'name')
        reputation = tooltip.get('requirements', {}).get('reputation', {})
        yield from link('tooltipData.requirements.reputation.factionID', 'factions', reputation.get('factionID'), 'name')
        for index, effect in enumerate(tooltip.get('effects', [])):
            yield from link(f'tooltipData.effects.{index}', 'spells', effect.get('spellID'))
        binding = tooltip.get('descriptionRow', {})
        yield from link('tooltipData.descriptionRow', 'spells', binding.get('spellID'))
        item_set = tooltip.get('set', {})
        for index, item in enumerate(item_set.get('items', [])):
            yield from link(f'tooltipData.set.items.{index}', 'items', item, 'name')
        for index, bonus in enumerate(item_set.get('bonuses', [])):
            yield from link(f'tooltipData.set.bonuses.{index}', 'spells', bonus.get('spellID'))
    elif kind == 'spells':
        for index, category_id in enumerate(tooltip.get('requiredToolCategories', [])):
            yield from link(f'tooltipData.requiredToolCategories.{index}', 'totemcategories', category_id, 'name')
        for index, item_id in enumerate(tooltip.get('requiredToolItems', [])):
            yield from link(f'tooltipData.requiredToolItems.{index}', 'items', item_id, 'name')
        for index, modifier in enumerate(tooltip.get('durationModifiers', [])):
            yield from link(f'tooltipData.durationModifiers.{index}', 'spells', modifier.get('spellID'))
        for locale, text in entity.get('locales', {}).items():
            for field in ('description', 'auraDescription'):
                for reference, target_field in spell_references(text.get(field, '')):
                    yield from link(field, 'spells', reference, target_field, locale)
        variables = tooltip.get('variables', [])
        entries = variables.items() if isinstance(variables, dict) else enumerate(variables)
        for variable, template in entries:
            if isinstance(template, str):
                for reference, target_field in spell_references(template):
                    yield from link(f'tooltipData.variables.{variable}', 'spells', reference, target_field)
