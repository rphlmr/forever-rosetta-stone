"""Measure ID-selected spell templates against independent displayed-value fixtures."""
import sys
from id_only_matrix_harness import ROOT, CaseReporter, IdOnlyHarness, NATIVE_TEXT, PROFILES, required_locales
from live_spell_fixture import FixtureUnavailable, make_fixture
sys.path.insert(0, str(ROOT))
from tools.catalogs.catalog_storage import load_catalog

FIELDS = ('description', 'auraDescription', 'rank', 'nameDescription')


def target_field(spell, locale, field):
    return spell.get('locales', {}).get(locale, {}).get(field)


def create_description_renderer(harness):
    return harness.lua.eval(b'''function(addon, id, locale, native, field)
        local oldLocale, oldAura = addon.GetTargetLocale, addon.GetTooltipAuraData
        addon.GetTargetLocale = function() return locale end
        addon.GetTooltipAuraData = function() return {spellId=id, name='title'}, 'player' end
        local font = {GetFont=function() return 'native',12,'' end,
            GetTextScale=function() return 1 end,GetTextColor=function() return 1,1,1 end}
        local outputFont = {SetFont=function() end, SetTextScale=function() end}
        local rows = {}
        local tip = {AddLine=function(_,left) rows[#rows+1]=left end,
            AddDoubleLine=function(_,left) rows[#rows+1]=left end,
            NumLines=function() return #rows end,GetLeftLine=function() return outputFont end}
        local aura = field=='auraDescription'
        local ok,failure=pcall(addon.FillEnglishTooltip,addon,{source={GetLeftLine=function() return font end},
            tip=tip,kind='spell',id=id,name='title',data={type=aura and 7 or 1,lines={
                {type=13,leftText='title'}, {type=aura and 0 or 34,leftText=native}}}})
        addon.GetTargetLocale,addon.GetTooltipAuraData=oldLocale,oldAura
        if not ok then error(failure) end
        return rows[2], nil, rows[3]~=nil
    end''')


def run_matrix(locales=None, ids=None, profiles=None, root=ROOT):
    spells = load_catalog(root, 'spells')['catalogs']['spells']
    selected = spells if ids is None else {str(value): spells[str(value)] for value in ids if str(value) in spells}
    locales = list(required_locales(root) if locales is None else locales)
    profiles = list(PROFILES if profiles is None else profiles)
    harness, reporter = IdOnlyHarness(root=root), CaseReporter('spells', locales, profiles)
    render = create_description_renderer(harness)
    for spell_id, spell in selected.items():
        records = spell.get('locales', {})
        for locale in locales:
            for profile in profiles:
                harness.set_context(locale, int(spell_id), profile, entity_kind='spells')
                case = {'id':int(spell_id),'field':'name','locale':locale,'profile':profile}
                name = records.get(locale, {}).get('name')
                actual,error,forbidden = harness.attempt(lambda: harness.db.GetSpellName(harness.db,int(spell_id),locale.encode()))
                reporter.record(case,name,actual,error,forbidden,None if name else 'missing target translation')
                for field in FIELDS:
                    case = {'id':int(spell_id),'field':field,'locale':locale,'profile':profile}
                    if not any(record.get(field) for record in records.values()):
                        reporter.not_applicable(case,'field absent from maintained locales and retained templates'); continue
                    expected,reason,native = target_field(spell,locale,field),None,NATIVE_TEXT
                    if field in ('description','auraDescription'):
                        try:
                            fixture=make_fixture(spells,spell_id,locale,profile,field)
                            expected,native=fixture['expected'],fixture['native']
                            case.update(sourceLocale=fixture['sourceLocale'],fixture=fixture['fixture'])
                            harness.set_source_locale(fixture['sourceLocale'])
                        except FixtureUnavailable as cause:
                            reason='oracle limitation: '+str(cause)
                            case['expectationDiagnostic']={'category':cause.category,'code':cause.code,'evidence':cause.evidence}
                            expected=None
                        actual,error,forbidden=harness.attempt(lambda:render(harness.addon,int(spell_id),locale.encode(),native.encode(),field.encode()))
                    else:
                        line=harness.to_lua({'type':13,'leftText':NATIVE_TEXT,'rightText':NATIVE_TEXT})
                        def render_subtext():
                            result=harness.addon.GetLocalizedTooltipLine(harness.addon,line,b'spell',int(spell_id),locale.encode())
                            return result[1] if isinstance(result,tuple) and len(result)>1 else None
                        actual,error,forbidden=harness.attempt(render_subtext)
                        if field!='rank': reason='no ID-based renderer for this field'
                        if not expected: reason='missing target translation'
                    reporter.record(case,expected,actual,error,forbidden,reason)
    report=reporter.finish([int(value) for value in selected],full_scope=ids is None)
    report['inputContract']='Entity identity by ID; synthetic displayed values captured from maintained source templates; no character recalculation.'
    return report
