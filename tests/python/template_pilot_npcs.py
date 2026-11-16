"""One NPC's name, level, structured creature type and owned faction."""

from lupa.lua51 import LuaRuntime

from id_only_matrix_harness import IdOnlyHarness, to_python
from template_pilot_common import ROOT, PilotCases, load_records, original_text
from template_pilot_labels import render_integer

NPC_ID = 823
CREATURE_TYPE_ID = 7
LEVEL_LABEL_ID = 10253


def run_matrix(sources, targets, profiles):
    npc = load_records('npcs', [NPC_ID]).get(str(NPC_ID), {})
    faction_id = npc.get('factionId')
    faction = load_records('factions', [faction_id]).get(str(faction_id), {}) if faction_id else {}
    creature = load_records('creaturetypes', [CREATURE_TYPE_ID]).get(str(CREATURE_TYPE_ID), {})
    level_label = load_records('globalstrings', [LEVEL_LABEL_ID]).get(str(LEVEL_LABEL_ID), {})
    # Load versioned format declarations as data in a separate VM, without the translator.
    data_lua = LuaRuntime(encoding=None)
    data = data_lua.table()
    data_lua.execute((ROOT / 'ForeverRosettaStone/database/npc-tooltip-data.lua').read_bytes(), b'pilot-data', data)
    formats = data[b'npcTooltipData']
    harness = IdOnlyHarness()
    harness.lua.execute(b'''
        addon.RegisterNameTooltipComponent=function() end
        Enum.TooltipDataLineType.UnitName=2
        Enum.TooltipDataLineType.UnitLevel=47
        Enum.TooltipDataLineType.UnitType=48
        UnitGUID=function() return 'Creature-Pilot' end
        UnitCreatureType=function() return 'NativeHumanoid',7 end
        UnitIsPlayer=function() return false end
    ''')
    for filename in ('database/npc-tooltip-data.lua', 'tooltips/components/npc-tooltip.lua'):
        harness._load(ROOT / 'ForeverRosettaStone' / filename, harness.addon)
    render = harness.lua.eval(b'''function(addon,id,name,level,creature,faction)
        local rows = {}
        local font = {GetFont=function() return 'font',12,'' end,
            GetTextScale=function() return 1 end,GetTextColor=function() return 1,1,1 end,
            SetFont=function() end,SetTextScale=function() end}
        local tip = {AddLine=function(_,text) rows[#rows+1]=text end,
            AddDoubleLine=function(_,text) rows[#rows+1]=text end,
            NumLines=function() return #rows end,GetLeftLine=function() return font end}
        addon:FillEnglishTooltip({kind='npc',id=id,name=name,tip=tip,
            source={GetLeftLine=function() return font end,GetUnit=function() return 'Pilot','target' end},
            data={guid='Creature-Pilot',lines={
                {type=2,lineIndex=1,leftText='Native title'},
                {type=47,lineIndex=2,leftText=level},
                {type=48,lineIndex=3,leftText=creature},
                {type=0,lineIndex=4,leftText=faction}}}})
        return rows
    end''')
    cases = PilotCases('npc_tooltips')
    records = {'name': npc, 'level': level_label, 'creatureType': creature, 'faction': faction}
    for source in sources:
        for target in targets:
            for profile in profiles:
                native, expected, issues = {}, {}, {}
                amount = 17 if profile == 'baseline' else 53
                for field, record in records.items():
                    try:
                        # The title is selected by ID; its native spelling is not matched.
                        native[field] = (record.get('locales', {}).get(source, {}).get('name')
                                         if field == 'name' else original_text(record, source))
                        if field == 'level':
                            native[field] = render_integer(native[field], amount)
                            # Additional-language NPC formats are currently declared in Lua.
                            template = to_python(formats[target.encode()][b'formats'][1])
                            expected[field] = render_integer(template, amount)
                        else:
                            expected[field] = record.get('locales', {}).get(target, {}).get('name')
                            if not expected[field]:
                                raise ValueError('Missing target text')
                    except (ValueError, TypeError, KeyError) as cause:
                        issues[field] = str(cause)
                harness.set_context(target, NPC_ID, profile, 'npcs')
                harness.set_source_locale(source)
                rows = error = None
                if not issues:
                    def operation():
                        name = harness.db.GetNpcName(harness.db, NPC_ID, target.encode())
                        return render(harness.addon, NPC_ID, name, native['level'].encode(),
                                      native['creatureType'].encode(), native['faction'].encode())
                    rows, error, forbidden = harness.attempt(operation)
                    if forbidden:
                        error = error or str(forbidden)
                for index, field in enumerate(records, 1):
                    identity = {'sourceLocale': source, 'targetLocale': target, 'profile': profile,
                                'id': NPC_ID, 'field': field}
                    kind = {'name': 'npcs', 'level': 'globalstrings', 'creatureType': 'creaturetypes', 'faction': 'factions'}[field]
                    record_id = {'name': NPC_ID, 'level': LEVEL_LABEL_ID, 'creatureType': CREATURE_TYPE_ID, 'faction': faction_id}[field]
                    if cases.apply_policy(identity, records[field], 'name', kind, entity_id=record_id,
                                          source_required=field in ('level', 'faction')):
                        continue
                    actual = to_python(rows[index]) if rows is not None else None
                    reason = issues.get(field)
                    category = 'missing_data' if reason else None
                    if issues and not reason:
                        reason, category = 'tooltip dependencies missing: ' + ', '.join(issues), 'missing_data'
                    if rows is not None and len(rows) != len(records):
                        reason, category = 'production reported incomplete tooltip', 'addon_bug'
                    cases.check(identity, expected.get(field), actual, source_text=native.get(field),
                                error=error, reason=reason, category=category)
    report = cases.finish({'ids': [NPC_ID], 'factionId': faction_id,
                           'creatureTypeId': CREATURE_TYPE_ID, 'levelLabelId': LEVEL_LABEL_ID,
                           'fields': list(records), 'levelTargetOwner': 'database/npc-tooltip-data.lua'})
    report['expectedCases'] = len(sources) * len(targets) * len(profiles) * len(records)
    return report
