"""Bounded live-value pilots for one spell, one aura, and one talent.

The fixtures synthesize displayed values independently of runtime calculations. They
exercise translation transport, not Blizzard's numeric calculations or prose quality.
"""
import json

from id_only_matrix_harness import IdOnlyHarness, to_python
from live_spell_fixture import FixtureUnavailable, make_fixture, compile_nodes, bindings, render
from template_pilot_common import ROOT, PilotCases, load_records

SPELL_ID = 16757
AURA_ID = 433
TALENT_ID = 1001
TALENT_FIXTURE = ROOT / 'tests/fixtures/template-pilot-talents.json'


def talent_rank_contexts(talent, evidence=None):
    """Select actual trait ranks; legacy Talent.SpellRank links are not live rank IDs."""
    evidence = json.loads(TALENT_FIXTURE.read_text()) if evidence is None else evidence
    definitions = {row['ID']: row for row in evidence['traitDefinitions']
                   if row['SpellID'] == talent.get('spellId')}
    contexts = []
    for entry in evidence['traitNodeEntries']:
        definition = definitions.get(entry['TraitDefinitionID'])
        if not definition:
            continue
        for rank in range(1, entry['MaxRanks'] + 1):
            values = {}
            for effect in evidence['traitDefinitionEffectPoints']:
                if effect['TraitDefinitionID'] != definition['ID']:
                    continue
                points = [row for row in evidence['curvePoints']
                          if row['CurveID'] == effect['CurveID'] and row['rank'] == rank]
                if effect['OperationType'] != 0 or len(points) != 1:
                    raise ValueError('Pilot trait rank requires one verified override value per effect')
                values['$s' + str(effect['EffectIndex'] + 1)] = points[0]['value']
            if not values:
                raise ValueError('Pilot trait rank has no verified displayed values')
            contexts.append({'spellId': definition['SpellID'], 'rank': rank,
                             'entryId': entry['ID'], 'displayedValues': values})
    if not contexts:
        raise ValueError('Pilot talent has no verified trait rank definition')
    return contexts


def talent_fixture(spells, context, source, target, profile, field):
    spell_id = context['spellId']
    left = compile_nodes(spells, spell_id, source, field, profile, source=True)
    right = compile_nodes(spells, spell_id, target, field, profile)
    source_values, target_values = bindings(left, right, profile)
    for values in (source_values, target_values):
        matched = set()
        for slot in values:
            if slot.owner == spell_id and slot.raw in context['displayedValues']:
                values[slot] = context['displayedValues'][slot.raw]
                matched.add(slot.raw)
        if matched != set(context['displayedValues']):
            raise FixtureUnavailable('rank displayed values do not match this template')
    return {'native': render(left, source_values, source), 'expected': render(right, target_values, target)}


def _renderer(harness):
    return harness.lua.eval(b'''function(addon, id, locale, native, surface)
        local oldLocale, oldAura = addon.GetTargetLocale, addon.GetTooltipAuraData
        addon.GetTargetLocale = function() return locale end
        addon.GetTooltipAuraData = function() return {spellId=id, name='title', points={}}, 'player' end
        local texts = {'title', native}
        local function font(index)
            return {GetText=function() return texts[index] end,
                GetFont=function() return 'native',12,'' end,
                GetTextScale=function() return 1 end, GetTextColor=function() return 1,1,1 end}
        end
        local outputFont = {SetFont=function() end, SetTextScale=function() end}
        local rows = {}
        local tip = {AddLine=function(_,left) rows[#rows+1]=left end,
            AddDoubleLine=function(_,left) rows[#rows+1]=left end,
            NumLines=function() return #rows end, GetLeftLine=function() return outputFont end}
        local aura = surface=='auras'
        local talent = surface=='talents'
        local source = {GetLeftLine=function(_,index) return font(index) end,
            NumLines=function() return 2 end}
        local ok, failure = pcall(addon.FillEnglishTooltip, addon, {
            source=source, tip=tip, kind=talent and 'talent' or 'spell', id=id, name='title',
            data={type=aura and 7 or 1,lines={
                {type=13,lineIndex=1,leftText='title'},
                {type=(aura or talent) and 0 or 34,lineIndex=2,leftText=native}}}})
        addon.GetTargetLocale, addon.GetTooltipAuraData = oldLocale, oldAura
        if not ok then error(failure) end
        return rows[2], rows[3]~=nil
    end''')


def run_matrices(sources, targets, profiles):
    sources, targets, profiles = list(sources), list(targets), list(profiles)
    talent = load_records('talents', [TALENT_ID]).get(str(TALENT_ID), {})
    ranks = talent_rank_contexts(talent)
    spell_ids = [SPELL_ID, AURA_ID, *(row['spellId'] for row in ranks)]
    spells = load_records('spells', spell_ids)
    harness = IdOnlyHarness()
    render = _renderer(harness)
    reports = []
    for surface, entities, field in (
        ('spells', [(SPELL_ID, None)], 'description'),
        ('auras', [(AURA_ID, None)], 'auraDescription'),
        ('talents', [(row['spellId'], row['rank']) for row in ranks], 'description'),
    ):
        cases = PilotCases(surface)
        for spell_id, rank in entities:
            for source in sources:
                for target in targets:
                    for profile in profiles:
                        identity = {'sourceLocale': source, 'targetLocale': target, 'profile': profile,
                                    'id': spell_id, 'field': field}
                        if rank is not None:
                            identity.update(talentId=TALENT_ID, rank=rank)
                        if cases.apply_policy(identity, spells.get(str(spell_id), {}), field, 'spells', source_required=True):
                            continue
                        expected = actual = native = error = reason = category = None
                        try:
                            if surface == 'talents':
                                context = next(row for row in ranks if row['spellId'] == spell_id and row['rank'] == rank)
                                fixture = talent_fixture(spells, context, source, target, profile, field)
                            else:
                                fixture = make_fixture(spells, spell_id, target, profile, field, source=source)
                            expected, native = fixture['expected'], fixture['native']
                            harness.set_context(target, spell_id, profile, entity_kind='spells')
                            harness.set_source_locale(source)
                            result, error, forbidden = harness.attempt(
                                lambda: render(harness.addon, spell_id, target.encode(), native.encode(), surface.encode()))
                            if forbidden:
                                error = error or 'Forbidden calls: ' + ', '.join(forbidden)
                            if result is not None:
                                actual, incomplete = result
                                actual = to_python(actual)
                                if incomplete:
                                    reason, category = 'production reported incomplete translation', 'addon_bug'
                        except FixtureUnavailable as cause:
                            reason, category = str(cause), cause.category
                        cases.check(identity, expected, actual, source_text=native, error=error,
                                    reason=reason, category=category)
        selection = {'ids': sorted({entity[0] for entity in entities}), 'field': field,
                     'expectedCases': len(entities) * len(sources) * len(targets) * len(profiles)}
        if surface == 'talents':
            selection.update(talentId=TALENT_ID, ranks=ranks, rankSource=str(TALENT_FIXTURE.relative_to(ROOT)))
        report = cases.finish(selection)
        report['expectedCases'] = selection['expectedCases']
        reports.append(report)
    return reports
