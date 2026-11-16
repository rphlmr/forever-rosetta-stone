"""Check the shared tooltip GlobalString boundary, including dynamic dependencies."""

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tools.build.client_label_scope import tooltip_globalstring_keys


class ClientLabelScopeTests(unittest.TestCase):
    def test_owned_adapters_direct_lookups_aliases_and_dynamic_families(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            addon = root / 'ForeverRosettaStone'
            (addon / 'tooltips').mkdir(parents=True)
            adapter = addon / 'tooltips/english-tooltip-formats.lua'
            adapter.write_text('local _, Addon = ...\nAddon.englishTooltipFormats = {BASE_LABEL="Base"}\n')
            runtime = addon / 'tooltips/consumer.lua'
            runtime.write_text('''local _, Addon = ...
local duration = "SECONDS_ABBR"
local decimal = formats.DECIMAL_SEPERATOR
local grouping = LARGE_NUMBER_SEPERATOR
local key = "SPELL_SCHOOL" .. index .. "_CAP"
local dispel = "AURA_DISPEL_" .. kind
local aliases = {"PROFESSIONS_", "CHARACTER_PROFESSION_"}
local key = owner.slot -- appearanceSlot
local kind = "appearanceSlot"
''')
            (addon / 'ForeverRosettaStone.toc').write_text('tooltips/english-tooltip-formats.lua\ntooltips/consumer.lua\n')
            needed = {'BASE_LABEL', 'SECONDS_ABBR', 'DECIMAL_SEPERATOR', 'LARGE_NUMBER_SEPERATOR',
                      'SPELL_SCHOOL2_CAP', 'AURA_DISPEL_MAGIC', 'HEADSLOT', 'PROFESSIONS_BASE_LABEL',
                      'CHARACTER_PROFESSION_BASE_LABEL'}
            unused = {'PLACEHOLDER_SCENE', 'PROFESSIONS_UNUSED', 'SPELL_SCHOOL_UNUSED'}
            self.assertEqual(tooltip_globalstring_keys(root, needed | unused), needed)

    def test_runtime_scope_contains_numeric_dependencies_and_excludes_unrelated_ui(self):
        keys = {'DECIMAL_SEPERATOR', 'LARGE_NUMBER_SEPERATOR', 'INT_SPELL_DURATION_SEC',
                'ITEM_CLASSES_ALLOWED', 'HEADSLOT', 'PLACEHOLDER_SCENE'}
        selected = tooltip_globalstring_keys(ROOT, keys)
        self.assertEqual(selected, keys - {'PLACEHOLDER_SCENE'})


if __name__ == '__main__':
    unittest.main()
