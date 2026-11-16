"""Bounded quest pilot using owned text and controlled client context."""

import re

from id_only_matrix_harness import IdOnlyHarness, PROFILES, to_python
from id_only_quest_matrix import PLAYER_LABELS
from template_pilot_common import PilotCases, load_records

QUEST_ID = '95317'
SCALAR_FIELDS = ('title', 'summary', 'description', 'eventObjectiveLabel')


def field_text(localized, field):
    if field.startswith('objectiveLines.'):
        index = int(field.split('.')[1])
        return next((line.get('text') for line in localized.get('objectiveLines', [])
                     if line.get('index') == index), None)
    return localized.get(field)


def expected_text(template, source, target, profile, field):
    """Render only the independently supported grammar of this pilot record."""
    values = PROFILES[profile]
    labels = PLAYER_LABELS.get(target)
    if not labels:
        return None, 'unknown player labels'
    sex = values['sex']
    class_name, race = labels[:2] if sex == 2 else labels[2:]
    if source == target:
        class_name, race = 'NativeWarrior', 'NativeHuman'
    text = template.replace('{name}', 'Alice' if profile == 'baseline' else 'Bianca')
    text = text.replace('{class}', class_name).replace('{race}', race)
    text = text.replace('$1oa', str(values['required']))
    if field.startswith('objectiveLines.'):
        text = text.replace('{current}', str(values['current'])).replace('{required}', str(values['required']))
    if re.search(r'\$[A-Za-z0-9]|\{[A-Za-z]+\}|<[^<>]+>', text):
        return None, 'unsupported template grammar in quest pilot'
    return text, None


def run_matrix(sources, targets, profiles):
    records = load_records('quests', [QUEST_ID])
    quest = records[QUEST_ID]
    locales = quest['locales']
    objective_indices = sorted({line['index'] for localized in locales.values()
                                for line in localized.get('objectiveLines', [])})
    fields = [field for field in SCALAR_FIELDS if any(field_text(record, field) is not None
                                                       for record in locales.values())]
    fields += ['objectiveLines.' + str(index) for index in objective_indices]
    planned = len(sources) * len(targets) * len(profiles) * len(fields)
    cases = PilotCases('quests')
    harness = IdOnlyHarness()
    lua = harness.lua
    lua.execute(b"""
        UnitName = function() return PilotName end
        UnitClass = function() return 'NativeWarrior', 'WARRIOR' end
        UnitRace = function() return 'NativeHuman', 'Human' end
    """)
    for source in sources:
        for target in targets:
            for profile in profiles:
                harness.set_context(target, int(QUEST_ID), profile, 'quests')
                harness.set_source_locale(source)
                lua.globals().PilotName = (b'Alice' if profile == 'baseline' else b'Bianca')
                values = PROFILES[profile]
                harness.set_objectives([{'type': 'item', 'text': '__NATIVE__',
                                         'numFulfilled': values['current'],
                                         'numRequired': values['required']}])
                for field in fields:
                    identity = {'sourceLocale': source, 'targetLocale': target,
                                'profile': profile, 'id': int(QUEST_ID), 'field': field}
                    if cases.apply_policy(identity, quest, field, 'quests'):
                        continue
                    source_record = locales.get(source, {})
                    source_text = field_text(source_record, field)
                    target_text = field_text(locales.get(target, {}), field)
                    if not target_text:
                        cases.check(identity, None, None, source_text=source_text,
                                    reason='missing target text', category='missing_data')
                        continue
                    expected, limitation = expected_text(target_text, source, target, profile, field)
                    if limitation:
                        cases.check(identity, None, None, source_text=source_text,
                                    reason=limitation, category='test_limitation')
                        continue
                    try:
                        if field.startswith('objectiveLines.'):
                            lines = harness.addon.GetProgressLines(harness.addon, int(QUEST_ID))
                            row = lines[int(field.split('.')[1])]
                            actual = row and row[b'translated']
                        else:
                            record = harness.addon.GetQuest(harness.addon, int(QUEST_ID))
                            text = record and record[field.encode()]
                            actual = harness.addon.FormatQuestText(harness.addon, text, int(QUEST_ID)) if text else None
                        cases.check(identity, expected, to_python(actual), source_text=source_text)
                    except Exception as exc:
                        cases.check(identity, expected, None, source_text=source_text, error=str(exc))
    report = cases.finish({'ids': [int(QUEST_ID)], 'fields': fields})
    report['expectedCases'] = planned
    return report
