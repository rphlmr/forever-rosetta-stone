"""Capture-bound item description rows use structured identity only."""

import copy
import hashlib
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

from lupa.lua51 import LuaRuntime
import id_only_item_matrix as matrix
from tools.catalogs.catalog_storage import get_digest
from tools.build.runtime_catalog import project_tooltip_rules

spec = importlib.util.spec_from_file_location('description_import', Path('tools/source-scan/import_description_rows.py'))
source_import = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source_import)


class DescriptionRowTests(unittest.TestCase):
    def setUp(self):
        self.item = {'locales': {'enUS': {'description': 'Teaches Example.'}}, 'tooltipData': {
            'effects': [{'spellID': 42, 'triggerType': 6}]}}
        self.job = {'kind': 'items', 'id': 1, 'fields': ['name', 'description']}
        self.queue = {'schemaVersion': 1, 'catalogHash': get_digest({'items/1': self.item}),
                      'profiles': {'enUS': {'jobs': [self.job]}}}
        self.queue['hash'] = get_digest(self.queue)
        self.capture = {'schemaVersion': 1, 'sessions': {1: {'locale': 'enUS', 'build': 70938, 'nextIndex': 2,
            'queueHash': self.queue['hash'], 'catalogHash': self.queue['catalogHash'], 'results': {1: {
                'status': 'captured', 'job': self.job, 'values': {'tooltip': {'id': 1, 'lines': {1: {
                    'type': 38, 'spellID': 42, 'leftText': 'Use: Teaches Example.'}}}}}}}}}

    def propose(self):
        with patch.object(source_import, 'load_entity', return_value=copy.deepcopy(self.item)):
            return source_import.prepare(self.queue, self.capture, '1', [1], 'Use:', '1.60.1.70938')

    def test_import_requires_matching_capture_and_unchanged_catalog(self):
        self.assertEqual(self.propose()[0]['spellID'], 42)
        line = self.capture['sessions'][1]['results'][1]['values']['tooltip']['lines'][1]
        for field, invalid in [('type', 0), ('spellID', 43), ('leftText', 'Use: Other')]:
            old = line[field]
            line[field] = invalid
            with self.assertRaises(ValueError): self.propose()
            line[field] = old
        self.item['locales']['enUS']['description'] = 'Changed.'
        with self.assertRaises(ValueError): self.propose()

    def test_import_rejects_ambiguous_link_and_mismatched_session(self):
        self.item['tooltipData']['effects'].append({'spellID': 42, 'triggerType': 6})
        self.queue['catalogHash'] = get_digest({'items/1': self.item})
        self.queue['hash'] = get_digest({k: v for k, v in self.queue.items() if k != 'hash'})
        session = self.capture['sessions'][1]
        session['queueHash'], session['catalogHash'] = self.queue['hash'], self.queue['catalogHash']
        with self.assertRaises(ValueError): self.propose()

    def test_import_rejects_incomplete_noncontiguous_or_changed_jobs(self):
        session = self.capture['sessions'][1]
        session['nextIndex'] = 1
        with self.assertRaises(ValueError): self.propose()
        session['nextIndex'] = 2
        session['results'] = {2: session['results'][1]}
        with self.assertRaises(ValueError): self.propose()
        session['results'] = {1: session['results'][2]}
        session['results'][1]['job'] = {**self.job, 'unexpected': True}
        with self.assertRaises(ValueError): self.propose()
        session['locale'] = 'frFR'
        with self.assertRaises(ValueError): self.propose()

    def test_runtime_requires_bound_unique_identity_and_target(self):
        lua = LuaRuntime(encoding=None)
        lua.execute(b'''
            canaccessallvalues = function(...) for i=1, select('#', ...) do
                if type(select(i, ...)) == 'table' then return false end end return true end
            GetLocale = function() return 'deDE' end
            Enum = {TooltipDataLineType = {ItemSpellTriggerLearn = 38, FlavorText = 37}}
            rule = {descriptionRow = {lineType='ItemSpellTriggerLearn', spellID=42, triggerType=6},
                effects={{spellID=42, triggerType=6}}}
            target = {description='Target text'}
            ForeverRosettaStoneDB = {GetItemRules=function() return rule end,
                GetItemDetails=function() return target end}
            addon = {englishTooltipFormats={ITEM_SPELL_TRIGGER_ONUSE='Use:'},
                tooltipFormatsByLocale={frFR={ITEM_SPELL_TRIGGER_ONUSE='Utiliser :'}}}
            assert(loadfile('ForeverRosettaStone/tooltips/tooltip-descriptions.lua'))('addon', addon)
            local function render(row, locale)
                return addon:GetLocalizedTooltipLine(row, 'item', 1, locale)
            end
            row = {type=38, spellID=42, leftText='arbitrary native text'}
            assert(render(row, 'frFR') == 'Utiliser : Target text')
            assert(addon:GetEnglishTooltipLine({}, row, 'item', 1) == 'Use: Target text')
            assert(render({type=37, leftText='unrelated flavor'}, 'frFR') == nil)
            assert(addon:GetEnglishTooltipLine({}, {type=37, leftText='unrelated flavor'}, 'item', 1) == nil)
            row.spellID=43; assert(render(row, 'frFR') == nil)
            row.spellID={}; assert(render(row, 'frFR') == nil)
            row.spellID=42; rule.effects[2]={spellID=42, triggerType=6}; assert(render(row, 'frFR') == nil)
            rule.effects[2]=nil; target.description=nil; assert(render(row, 'frFR') == nil)
            target.description='  '; assert(render(row, 'frFR') == nil)
            target.description='Target text'; addon.tooltipFormatsByLocale.frFR=nil; assert(render(row, 'frFR') == nil)
            addon.tooltipFormatsByLocale.frFR={ITEM_SPELL_TRIGGER_ONUSE='Utiliser :'}
            addon.tooltipFormatsByLocale.frFR.ITEM_SPELL_TRIGGER_ONUSE='  '; assert(render(row, 'frFR') == nil)
            addon.tooltipFormatsByLocale.frFR.ITEM_SPELL_TRIGGER_ONUSE='Utiliser :'
            rule.effects='bad'; assert(render(row, 'frFR') == nil)
            rule.effects={{spellID=42, triggerType=6}}
            rule.descriptionRow=nil; assert(render(row, 'frFR') == nil)
        ''')

    def test_rule_export_and_matrix_require_valid_binding(self):
        binding = {'lineType': 'ItemSpellTriggerLearn', 'spellID': 42, 'triggerType': 6}
        self.item['tooltipData']['descriptionRow'] = binding
        self.item['tooltipData']['descriptionRowSourceMetadata'] = {
            'source': 'clientCapture', 'sourceLocale': 'enUS', 'sourceBuild': '1.60.1.70938',
            'captureSha256': 'a' * 64,
            'sourceDescriptionSha256': hashlib.sha256(b'Teaches Example.').hexdigest()}
        self.assertEqual(project_tooltip_rules(self.item)['descriptionRow'], binding)
        self.assertEqual(matrix.verified_description_row(self.item['tooltipData']), binding)
        self.item['locales']['enUS']['description'] = 'Changed.'
        with self.assertRaises(ValueError): project_tooltip_rules(self.item)
        self.item['locales']['enUS']['description'] = 'Teaches Example.'
        self.item['tooltipData']['effects'].append({'spellID': 42, 'triggerType': 6})
        self.assertIsNone(matrix.verified_description_row(self.item['tooltipData']))

    def test_matrix_uses_bound_item_description_for_both_cases(self):
        binding = {'lineType': 'ItemSpellTriggerLearn', 'spellID': 42, 'triggerType': 6}
        self.item['tooltipData']['descriptionRow'] = binding
        self.item['locales']['enUS']['name'] = 'Item'
        class Harness:
            def __init__(self, root=None): self.db, self.profile = self, {}
            def set_context(self, *args, **kwargs): pass
            def GetItemName(self, *args): return 'Item'
            def attempt(self, fn): return fn(), None, []
        def load(root, kind, ids=None):
            return {'catalogs': {kind: {'1': self.item} if kind == 'items' else {}}}
        rows = []
        def render(harness, item_id, locale, row):
            rows.append(row)
            return 'Use: Teaches Example.'
        with patch.object(matrix, 'load_catalog', side_effect=load), \
                patch.object(matrix, 'IdOnlyHarness', Harness), \
                patch.object(matrix, 'get_format', return_value='Use:'), \
                patch.object(matrix, 'render_line', side_effect=render):
            report = matrix.run_matrix(locales=['enUS'], ids=[1], profiles=['baseline'])
        self.assertFalse(report['failures'])
        self.assertEqual([(row['type'], row['spellID']) for row in rows], [(38, 42), (38, 42)])


if __name__ == '__main__':
    unittest.main()
