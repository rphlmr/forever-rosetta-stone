"""Shared harness for live-value translation regression tests."""
from lupa.lua51 import LuaRuntime
from database_harness import ROOT, install_metadata, load_database, read_metadata


class LiveValueHarness:
    def setUp(self):
        self.lua = LuaRuntime(encoding=None)
        install_metadata(self.lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc', include_pages=False))
        load_database(self.lua)
        self.lua.execute(b'''
            canaccessallvalues = function(...)
                for i=1,select('#',...) do
                    local v=select(i,...)
                    if type(v)=='table' and v.secret then return false end
                end
                return true
            end
            sourceLocale='frFR'
            GetLocale=function() return sourceLocale end
            UnitSex=function() return 2 end
            Enum={TooltipDataType={Spell=1,UnitAura=7},TooltipDataLineType={SpellName=13,SpellDescription=34}}
            Enum.TooltipDataLineType.ItemSpellTriggerOnUse=44
            Enum.TooltipDataLineType.ItemSpellTriggerOnEquip=45
            Enum.TooltipDataLineType.ItemSpellTriggerOnProc=46
            addon={itemTooltipLabels={}}
            addon.RegisterNameTooltipComponent=function() end
            addon.IsReadableEntityID=function(_,id) return type(id)=='number' and id>0 end
            for _,path in ipairs({'tooltips/english-tooltip-formats.lua','tooltips/localized-tooltip-formats.lua',
                'tooltips/client-labels.lua',
                'tooltips/spell-live-values.lua','tooltips/tooltip-descriptions.lua','tooltips/components/spell-tooltip.lua'}) do
                assert(loadfile('ForeverRosettaStone/'..path))('addon',addon)
            end
            captured=function(id,native,source,target,field)
                sourceLocale=source
                return addon:TranslateLiveSpellDescription(id,target,native,field)
            end
            fakeRecords={}
            local original=ForeverRosettaStoneDB.GetSpellDetails
            ForeverRosettaStoneDB.GetSpellDetails=function(self,id,locale)
                if fakeRecords[id] then return fakeRecords[id][locale] end
                return original(self,id,locale)
            end
            records=function(id,fr,en,field)
                field=field or 'description'
                fakeRecords[id]={frFR={[field]=fr,originalFields={[field]=true}},
                    enUS={[field]=en,originalFields={[field]=true}}}
            end
            item=function(id,spellID,lineType,native,source,target)
                sourceLocale=source
                local formats=source=='enUS' and addon.englishTooltipFormats or addon.tooltipFormatsByLocale[source]
                for key,value in pairs(formats) do _G[key]=value end
                return addon:GetLocalizedTooltipLine({type=lineType,spellID=spellID,leftText=native},'item',id,target)
            end
            render=function(id,kind,native,source,target,nativeLines)
                sourceLocale=source
                rows={}
                local font={GetTextColor=function() return 1,1,1 end,GetFont=function() return 'font',12,'' end,
                    GetTextScale=function() return 1 end,SetFont=function() end,SetTextScale=function() end}
                local tooltip={
                    AddLine=function(_,text) rows[#rows+1]={text=text} end,
                    AddDoubleLine=function(_,text,right) rows[#rows+1]={text=text,right=right} end,
                    NumLines=function() return #rows end,
                    GetLeftLine=function() return font end,
                }
                local aura={spellId=id,name='Nourriture',points={}}
                C_UnitAuras={GetAuraDataByIndex=function() return aura end}
                addon.GetTargetLocale=function() return target end
                local isAura=kind=='aura'
                addon:FillEnglishTooltip({kind=isAura and 'spell' or kind,id=id,
                    name=ForeverRosettaStoneDB:GetSpellName(id,target) or 'Name',tip=tooltip,
                    source={GetLeftLine=function() return font end,
                        GetProcessingTooltipInfo=function() return {getterName='GetUnitBuff',getterArgs={'player',1}} end},
                    data={type=isAura and 7 or 1,lines=nativeLines or {
                        {type=13,lineIndex=1,leftText=isAura and 'Nourriture' or 'Name'},
                        {type=isAura and 0 or 34,lineIndex=2,leftText=native},
                    }}})
                return rows
            end
        ''')

    def capture(self, entity_id, native, source='frFR', target='enUS', field='description'):
        return self.lua.globals().captured(entity_id, native.encode(), source.encode(), target.encode(), field.encode())
