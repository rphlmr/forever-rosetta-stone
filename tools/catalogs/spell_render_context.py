"""Derive spell schools and flat duration dependencies from verified client rows."""


def spell_render_context(spell_id, tables):
    def unique(table, identity):
        rows = [row for row in tables[table] if int(row['SpellID']) == identity
                and row.get('DifficultyID', '0') == '0']
        if len(rows) != 1:
            raise ValueError(f'Expected one {table} row for {identity}')
        return rows[0]

    misc = unique('SpellMisc', spell_id)
    target = unique('SpellClassOptions', spell_id)
    families = {int(row['SpellID']): row for row in tables['SpellClassOptions']}
    modifiers = []
    for effect in tables['SpellEffect']:
        if (effect['DifficultyID'] != '0' or int(effect['Effect']) != 6
                or int(effect['EffectAura']) not in (107, 108) or int(effect['EffectMiscValue_0']) != 1):
            continue
        source_id = int(effect['SpellID'])
        source = families.get(source_id)
        if not source or source['SpellClassSet'] != target['SpellClassSet']:
            continue
        if not any(int(effect[f'EffectSpellClassMask_{part}']) & int(target[f'SpellClassMask_{part}'])
                   for part in range(4)):
            continue
        if int(effect['EffectAura']) != 107 or float(effect['EffectBasePointsF']) < 0:
            raise ValueError('Unsupported percent or negative duration modifier')
        modifiers.append({'operation': 'add', 'spellID': source_id,
                          'effectIndex': int(effect['EffectIndex'])})
    return {'schoolMask': int(misc['SchoolMask']),
            **({'durationModifiers': sorted(modifiers, key=lambda row: (row['spellID'], row['effectIndex']))}
               if modifiers else {})}
