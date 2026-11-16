"""Run the addon harness and syntax checks with Lupa's Lua 5.1 runtime."""

from pathlib import Path
import argparse
import sys
import xml.etree.ElementTree as ET
import runpy
import unittest

from lupa.lua51 import LuaRuntime

sys.path.insert(0, str(Path(__file__).resolve().parent / 'python'))
from database_harness import install_metadata, read_metadata


root = Path(__file__).resolve().parents[1]
assert Path.cwd() == root, "Run tests from the repository root"
for legacy in ('references', 'scripts'):
    assert not (root / legacy).exists(), f"Legacy workspace {legacy}/ must not be recreated; use datasources/ or tools/"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--unit-only', action='store_true', help='Run unit and integration checks without translation matrices')
options, matrix_arguments = parser.parse_known_args()
if options.unit_only and matrix_arguments:
    parser.error('--unit-only cannot be combined with translation matrix arguments')
sys.argv = [sys.argv[0]]
for filename, class_name in (
    ('test-clean.py', 'CleanTests'),
    ('test-release.py', 'ReleaseTests'),
    ('test-wago-download.py', 'DownloadTests'),
    ('test-wago-updates.py', 'UpdateTests'),
    ('test-catalog-format.py', 'CatalogFormatTests'),
    ('test-book-codex.py', 'BookCodexTests'),
    ('test-book-texts.py', 'BookTextTests'),
    ('test-curseforge-source.py', 'CurseForgeSourceTests'),
    ('test-import-policy.py', 'ImportPolicyTests'),
    ('test-client-label-scope.py', 'ClientLabelScopeTests'),
    ('test-item-requirements.py', 'ItemRequirementTests'),
    ('test-live-tooltip-contract.py', 'LiveTooltipContractTests'),
    ('test-live-spell-references.py', 'LiveSpellReferenceTests'),
    ('test-talent-description-source.py', 'TalentDescriptionSourceTests'),
    ('test-live-spell-fixture.py', 'LiveSpellFixtureTests'),
    ('test-client-label-batches.py', 'ClientLabelBatchTests'),
    ('test-client-labels.py', 'ClientLabelTests'),
    ('test-catalog-effect-runtime.py', 'CatalogEffectRuntimeTests'),
    ('test-catalog-links.py', 'CatalogLinkTests'),
    ('test-catalog-placeholder-contract.py', 'CatalogPlaceholderTests'),
    ('test-tooltip-check.py', 'TooltipCheckTests'),
    ('test-client-api-fixture.py', 'ClientApiFixtureTests'),
    ('test-debug-pick-context.py', 'DebugPickContextTests'),
    ('test-api-only-mode.py', 'APIOnlyModeTests'),
    ('test-tooltip-gap-tools.py', 'TooltipGapToolTests'),
    ('test-captured-tooltip-campaign.py', 'CapturedTooltipCampaignTests'),
    ('test-captured-tooltip-campaign.py', 'EnglishCapturedTooltipCampaignTests'),
    ('test-captured-tooltip-campaign.py', 'LegacyCapturedAPITooltipCampaignTests'),
    ('test-captured-tooltip-campaign.py', 'AllCapturedHoverTests'),
    ('test-captured-tooltip-campaign.py', 'RemainingCapturedTooltipCampaignTests'),
    ('test-captured-auras.py', 'CapturedAuraTests'),
    ('test-tooltip-roundtrip.py', 'TooltipRoundtripTests'),
    ('test-picked-unit-tooltips.py', 'PickedUnitTooltipTests'),
    ('test-official-tooltip-matrix.py', 'OfficialTooltipMatrixTests'),
    ('test-captured-matrix-regressions.py', 'CapturedMatrixRegressionTests'),
    ('test-captured-bind-location.py', 'CapturedBindLocationTests'),
    ('test-captured-replay-contexts.py', 'CapturedReplayContextTests'),
    ('test-captured-german-tooltips.py', 'CapturedGermanTooltipTests'),
    ('test-captured-native-locales.py', 'CapturedNativeLocaleTests'),
    ('test-captured-reference-surfaces.py', 'CapturedReferenceSurfaceTests'),
    ('test-captured-form-name-reuse.py', 'CapturedFormNameReuseTests'),
    ('test-captured-equipment-labels.py', 'CapturedEquipmentLabelTests'),
    ('test-captured-literal-percentages.py', 'CapturedLiteralPercentageTests'),
    ('test-captured-api-spell-templates.py', 'CapturedApiSpellTemplateTests'),
    ('test-captured-conditional-source-repairs.py', 'CapturedConditionalSourceRepairTests'),
    ('test-captured-description-variants.py', 'CapturedDescriptionVariantTests'),
    ('test-captured-context-recapture.py', 'CapturedContextRecaptureTests'),
    ('test-map-hover-location.py', 'MapHoverLocationTests'),
    ('test-client-hotfix.py', 'ClientHotfixTests'),
    ('test-shared-tooltip-rows.py', 'SharedTooltipRowsTests'),
    ('test-official-text-policy.py', 'OfficialTextPolicyTests'),
    ('test-english-catalog-scope.py', 'EnglishCatalogScopeTests'),
    ('test-matrix-classification.py', 'MatrixClassificationTests'),
    ('test-id-only-matrix-harness.py', 'IdOnlyHarnessTests'),
    ('test-id-only-quest-matrix.py', 'IdOnlyQuestMatrixTests'),
    ('test-quest-capture-import.py', 'QuestCaptureImportTests'),
    ('test-quest-reputation-structured.py', 'QuestReputationStructuredTests'),
    ('test-id-only-spell-matrix.py', 'IdOnlySpellMatrixTests'),
    ('test-id-only-item-matrix.py', 'IdOnlyItemMatrixTests'),
    ('test-item-trigger-coverage.py', 'ItemTriggerCoverageTests'),
    ('test-item-description-row.py', 'DescriptionRowTests'),
    ('test-id-only-row-fixes.py', 'IdOnlyRowTests'),
    ('test-id-only-failure-groups.py', 'IdOnlyFailureGroupTests'),
    ('test-id-only-source-boundary.py', 'TooltipSourceBoundaryTests'),
    ('test-id-only-quest-sources.py', 'QuestSourcesTests'),
    ('test-id-only-quest-fallbacks.py', 'QuestFallbackTests'),
    ('test-id-only-auxiliary-names.py', 'AuxiliaryNamesTests'),
    ('test-minimap-refresh.py', 'StackedTooltipOwnershipTests'),
    ('test-update-plan.py', 'UpdatePlanTests'),
):
    checks = runpy.run_path(str(root / 'tests/python' / filename))
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(checks[class_name])
    assert unittest.TextTestRunner().run(suite).wasSuccessful(), filename + ' failed'
quest_fallbacks = runpy.run_path(str(root / 'tests/python/test-quest-ui-fallback-matrix.py'))
assert not quest_fallbacks['run_matrix']()['failures'], 'Quest text fallback regressions failed'
spell_refresh = runpy.run_path(str(root / 'tests/python/test-spell-value-refresh.py'))
spell_refresh_suite = unittest.defaultTestLoader.loadTestsFromTestCase(spell_refresh['SpellValueRefreshTests'])
assert unittest.TextTestRunner().run(spell_refresh_suite).wasSuccessful(), "Spell numeric refresh failed"
boundary_checks = runpy.run_path(str(root / "tests/python/test-local-scan-boundary.py"))
boundary_suite = unittest.defaultTestLoader.loadTestsFromTestCase(boundary_checks["LocalScanBoundaryTests"])
assert unittest.TextTestRunner().run(boundary_suite).wasSuccessful(), "Local scan leaked into shipping addons"
preparation_checks = runpy.run_path(str(root / "tests/python/test-quest-scan-preparation.py"))
preparation_suite = unittest.defaultTestLoader.loadTestsFromTestCase(preparation_checks["QuestScanPreparationTests"])
assert unittest.TextTestRunner().run(preparation_suite).wasSuccessful(), "Quest scan preparation failed"
runpy.run_path(str(root / "tests/python/test-quest-scan.py"))
source_preparation_checks = runpy.run_path(str(root / "tests/python/test-source-scan-preparation.py"))
source_preparation_suite = unittest.defaultTestLoader.loadTestsFromTestCase(
    source_preparation_checks["SourceScanPreparationTests"]
)
assert unittest.TextTestRunner().run(source_preparation_suite).wasSuccessful(), "Source scan preparation failed"
runpy.run_path(str(root / "tests/python/test-source-scan.py"))
github_checks = runpy.run_path(str(root / 'tests/python/test-github-community.py'))
github_suite = unittest.defaultTestLoader.loadTestsFromTestCase(github_checks['GithubCommunityTests'])
assert unittest.TextTestRunner().run(github_suite).wasSuccessful(), "GitHub community datasource checks failed"
lua = LuaRuntime(encoding=None)
compile_lua = lua.eval(
    "function(text, name) local chunk, reason = loadstring(text, name); assert(chunk, reason) end"
)

for path in sorted(root.rglob("*.lua")):
    if path.is_relative_to(root / "datasources/imports"):
        continue

    compile_lua(path.read_bytes(), str(path.relative_to(root)).encode())

for path in root.rglob("*.xml"):
    if path.is_relative_to(root / "datasources/imports"):
        continue

    ET.parse(path)

toc = root / "ForeverRosettaStone/ForeverRosettaStone.toc"
for entry in toc.read_text().splitlines():
    if entry and not entry.startswith("#"):
        assert (toc.parent / entry).is_file(), f"Missing TOC file: {entry}"

panel_xml = ET.parse(toc.parent / "quests/quest-panel.xml")
namespace = {"ui": "http://www.blizzard.com/wow/ui/"}
panel_template = panel_xml.find("ui:Frame", namespace)
assert panel_template.attrib["inherits"] == "PortraitFrameTemplateNoCloseButton"
layout = panel_template.find("ui:KeyValues/ui:KeyValue[@key='layoutType']", namespace)
assert layout.attrib["value"] == "ButtonFrameTemplateNoPortrait", "Panel must have no corner portrait"
assert toc.read_text().index("quests/quest-panel.xml") < toc.read_text().index("quests/quest-ui.lua")

install_metadata(lua, read_metadata(toc))
lua.execute((root / "tests/lua/test-addon.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-tooltip-hook-boundaries.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-tooltip-state.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-dev-debug.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-tooltip-descriptions.lua").read_bytes())
live_spell_checks = runpy.run_path(str(root / "tests/python/test-spell-live-values.py"))
live_spell_suite = unittest.defaultTestLoader.loadTestsFromTestCase(live_spell_checks["SpellLiveValueTests"])
assert unittest.TextTestRunner().run(live_spell_suite).wasSuccessful(), "Live spell, talent and aura values failed"
aura_checks = runpy.run_path(str(root / "tests/python/test-structured-auras.py"))
aura_suite = unittest.defaultTestLoader.loadTestsFromTestCase(aura_checks["StructuredAuraTests"])
assert unittest.TextTestRunner().run(aura_suite).wasSuccessful(), "Structured aura rendering failed"
LuaRuntime(encoding=None).execute((root / "tests/lua/test-tooltip-format-priority.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-npc-factions.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-npc-subnames.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-npc-owner-titles.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-npc-unit-ids.lua").read_bytes())
runpy.run_path(str(root / "tests/python/test-npc-unit-catalog.py"))
LuaRuntime(encoding=None).execute((root / "tests/lua/test-location-capture.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-api-probe.lua").read_bytes())
LuaRuntime(encoding=None).execute((root / "tests/lua/test-raw-tooltip-capture.lua").read_bytes())
location_checks = runpy.run_path(str(root / "tests/python/test-player-location.py"))
location_suite = unittest.defaultTestLoader.loadTestsFromTestCase(location_checks["PlayerLocationTests"])
assert unittest.TextTestRunner().run(location_suite).wasSuccessful(), "Live player location resolution failed"
runpy.run_path(str(root / "tests/python/test-tooltip-item-fallback.py"))
translation_checks = runpy.run_path(str(root / "tests/python/test-translation-work.py"))
translation_suite = unittest.defaultTestLoader.loadTestsFromTestCase(translation_checks["TranslationWorkTests"])
assert unittest.TextTestRunner().run(translation_suite).wasSuccessful(), "Translation batch validation failed"
storage_checks = runpy.run_path(str(root / "tests/python/test-catalog-storage.py"))
storage_suite = unittest.defaultTestLoader.loadTestsFromTestCase(storage_checks["CatalogStorageTests"])
assert unittest.TextTestRunner().run(storage_suite).wasSuccessful(), "Catalog storage validation failed"
corpus_checks = runpy.run_path(str(root / "tests/python/test-translation-corpus.py"))
datasource_checks = runpy.run_path(str(root / "tests/python/test-datasources.py"))
datasource_suite = unittest.defaultTestLoader.loadTestsFromTestCase(datasource_checks["DatasourceTests"])
assert unittest.TextTestRunner().run(datasource_suite).wasSuccessful(), "Datasource validation failed"
corpus_suite = unittest.defaultTestLoader.loadTestsFromTestCase(corpus_checks["TranslationCorpusTests"])
assert unittest.TextTestRunner().run(corpus_suite).wasSuccessful(), "Translation corpus validation failed"
official_fill_checks = runpy.run_path(str(root / "tests/python/test-fill-official-text.py"))
official_fill_suite = unittest.defaultTestLoader.loadTestsFromTestCase(official_fill_checks["OfficialSourceFillTests"])
assert unittest.TextTestRunner().run(official_fill_suite).wasSuccessful(), "Official source fill validation failed"
single_english_checks = runpy.run_path(str(root / "tests/python/test-single-english.py"))
single_english_suite = unittest.defaultTestLoader.loadTestsFromTestCase(single_english_checks["SingleEnglishTests"])
assert unittest.TextTestRunner().run(single_english_suite).wasSuccessful(), "Single English storage validation failed"
batch_checks = runpy.run_path(str(root / "tests/python/test-catalog-batch.py"))
batch_suite = unittest.defaultTestLoader.loadTestsFromTestCase(batch_checks["CatalogBatchTests"])
assert unittest.TextTestRunner().run(batch_suite).wasSuccessful(), "Catalog batch validation failed"
runpy.run_path(str(root / "tests/python/test-tooltip-catalog.py"))
runpy.run_path(str(root / "tests/python/test-wowhead-hotfixes.py"))
runpy.run_path(str(root / "tests/python/test-effect-index-alias.py"))
runpy.run_path(str(root / "tests/python/test-spelltooltip-probe.py"))
assert "Dependencies:" not in toc.read_text(), "The addon must remain standalone"
assert "## SavedVariables: ForeverRosettaStoneSettings" in toc.read_text(), "Preferences must not overwrite the API"
print("PASS: Lua syntax, XML syntax, TOC references, and standalone manifest")

if options.unit_only:
    print("PASS: unit and integration checks; translation matrices not run (--unit-only)")
else:
    sys.argv.extend(matrix_arguments)
    translation_matrix = runpy.run_path(str(root / "tests/python/test-translation-matrix.py"))
    translation_matrix["main"]()
