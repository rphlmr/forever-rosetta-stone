"""API-only startup keeps production catalog access without UI initialization."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime
from database_harness import install_metadata, load_database, read_metadata

ROOT = Path(__file__).resolve().parents[2]


class APIOnlyModeTests(unittest.TestCase):
    def prepare(self, enabled=True):
        self.lua = LuaRuntime(encoding=None)
        self.counts = install_metadata(self.lua, read_metadata(ROOT / 'ForeverRosettaStone/ForeverRosettaStone.toc'))
        self.db = load_database(self.lua)
        self.lua.globals().Enabled = enabled
        self.lua.execute(b'''
            date=function() return 'test' end
            messages={}
            print=function(message) messages[#messages+1]=message end
            SlashCmdList={}
            ForeverRosettaStoneSettings={apiOnly=Enabled,locale='frFR',features={questPanel=false}}
            addon={}
            bootstrap={events={}}
            function bootstrap:RegisterEvent(event) self.events[event]=true end
            function bootstrap:UnregisterAllEvents() self.events={} end
            function bootstrap:SetScript(event,callback) self[event]=callback end
            CreateFrame=function() assert(not CreatedFrame,'Unexpected UI frame');CreatedFrame=true;return bootstrap end
            hooksecurefunc=function() error('UI hook installed') end
            DisplayInterfaceActionBlockedMessage=function() end
            C_Timer={After=function() error('UI callback scheduled') end}
            assert(loadfile('ForeverRosettaStone/core/safety.lua'))('ForeverRosettaStone',addon)
            assert(loadfile('ForeverRosettaStone/core.lua'))('ForeverRosettaStone',addon)
            login=function() bootstrap.OnEvent(bootstrap,'PLAYER_LOGIN') end
        ''')

    def test_api_only_startup_keeps_real_database_and_skips_all_ui_initializers(self):
        self.prepare()
        self.lua.globals().login()
        self.assertEqual(self.lua.globals().addon[b'lifecycle'], b'apiOnly')
        self.assertTrue(self.lua.globals().addon.IsAPIOnly(self.lua.globals().addon))
        self.assertEqual(self.counts['packs'], [b'ForeverRosettaStone_Rules'])
        self.assertEqual(self.db.GetItemName(self.db, 6948, b'frFR'), 'Pierre de foyer'.encode())
        self.assertEqual(self.db.GetItemName(self.db, 6948, b'enUS'), b'Hearthstone')
        self.assertIsNone(self.db.GetItemName(self.db, 0, b'frFR'))
        self.assertIsNone(self.lua.globals().addon[b'panel'])
        self.assertIsNone(self.lua.globals().addon[b'preferences'])
        self.assertEqual(len(self.lua.globals().addon[b'frames']), 1)

    def test_api_only_commands_and_restart_cannot_open_ui(self):
        self.prepare()
        self.lua.execute(b'''
            login()
            for _,command in ipairs({'','settings','pick','quest','reset','api status','api invalid'}) do
                SlashCmdList.FOREVERROSETTASTONE(command)
            end
            addon:Restart()
            assert(addon.lifecycle=='apiOnly')
            assert(#messages==8)
        ''')

    def test_switches_are_persistent_explicit_and_take_effect_only_after_reload(self):
        self.prepare()
        self.lua.execute(b'''
            login()
            SlashCmdList.FOREVERROSETTASTONE('api off')
            assert(ForeverRosettaStoneSettings.apiOnly==false)
            assert(addon:IsAPIOnly())
            assert(ForeverRosettaStoneSettings.locale=='frFR')
            assert(ForeverRosettaStoneSettings.features.questPanel==false)
            SlashCmdList.FOREVERROSETTASTONE('api on')
            assert(ForeverRosettaStoneSettings.apiOnly==true)
            SlashCmdList.FOREVERROSETTASTONE('api auto')
            assert(ForeverRosettaStoneSettings.apiOnly==nil)
            assert(addon:IsAPIOnly(),'Mode stays active until reload')
            assert(not pcall(addon.SetAPIOnly,addon,'yes'))
        ''')

    def test_normal_mode_remains_default_and_enters_existing_ui_startup(self):
        for enabled in (False, None, 'true'):
            with self.subTest(enabled=enabled):
                self.prepare(enabled)
                self.lua.execute(b'''
                    preferencesLoaded=false
                    addon.Suspend=function(self,_,reason) self.failure=reason end
                    addon.LoadPreferences=function() preferencesLoaded=true;error('Normal UI startup reached') end
                    login()
                    assert(preferencesLoaded)
                    assert(not addon:IsAPIOnly())
                ''')

    def test_dependency_request_precedes_login_and_respects_explicit_player_choice(self):
        for choice, expected in ((None, True), (False, False), (True, True)):
            with self.subTest(choice=choice):
                self.prepare(choice)
                self.lua.execute(b'''
                    local choice=ForeverRosettaStoneSettings.apiOnly
                    accepted=addon:RequestAPIOnly()
                    assert(ForeverRosettaStoneSettings.apiOnly==choice,'Request must not persist a mode')
                ''')
                self.assertEqual(self.lua.globals().accepted, expected)
                if expected:
                    self.lua.execute(b'''
                        login()
                        assert(addon:IsAPIOnly())
                        local accepted,reason=addon:RequestAPIOnly()
                        assert(not accepted and reason)
                    ''')

    def test_dependency_request_works_on_a_fresh_install_without_saved_settings(self):
        self.prepare(None)
        self.lua.execute(b'''
            ForeverRosettaStoneSettings=nil
            assert(addon:RequestAPIOnly())
            login()
            assert(addon:IsAPIOnly())
            assert(ForeverRosettaStoneSettings==nil,'Session request must not create preferences')
        ''')


if __name__ == '__main__':
    unittest.main()
