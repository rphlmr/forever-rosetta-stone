"""Run tooltip replay suites in isolated workers and report each suite's duration."""

import argparse
from concurrent.futures import ProcessPoolExecutor, as_completed
import io
import os
from pathlib import Path
import runpy
import sys
import time
import unittest


SUITES = (
    # Start the longest suites early so a single worker does not hold up CI.
    ('test-captured-replay-contexts.py', 'CapturedReplayContextTests'),
    ('test-captured-reference-surfaces.py', 'CapturedReferenceSurfaceTests'),
    ('test-captured-context-recapture.py', 'CapturedContextRecaptureTests'),
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
    ('test-captured-german-tooltips.py', 'CapturedGermanTooltipTests'),
    ('test-captured-native-locales.py', 'CapturedNativeLocaleTests'),
    ('test-captured-form-name-reuse.py', 'CapturedFormNameReuseTests'),
    ('test-captured-equipment-labels.py', 'CapturedEquipmentLabelTests'),
    ('test-captured-literal-percentages.py', 'CapturedLiteralPercentageTests'),
    ('test-captured-api-spell-templates.py', 'CapturedApiSpellTemplateTests'),
    ('test-captured-conditional-source-repairs.py', 'CapturedConditionalSourceRepairTests'),
    ('test-captured-description-variants.py', 'CapturedDescriptionVariantTests'),
)
TESTS = Path(__file__).resolve().parent
sys.path.insert(0, str(TESTS.parents[1]))


def run_suite(spec):
    filename, class_name = spec
    started = time.monotonic()
    module = runpy.run_path(str(TESTS / filename))
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(module[class_name])
    log = io.StringIO()
    result = unittest.TextTestRunner(stream=log).run(suite)
    return class_name, result.testsRun, time.monotonic() - started, result.wasSuccessful(), log.getvalue()


def report(result):
    name, count, elapsed, passed, log = result
    print(f"{name}: {count} tests, {elapsed:.2f}s", flush=True)
    if not passed:
        raise AssertionError(f"{name} failed\n{log}")


def run_replays(workers=1):
    # Several campaign suites write the same optional report in registry order.
    if workers == 1 or os.environ.get('FRS_CAPTURE_REPORT'):
        for spec in SUITES:
            report(run_suite(spec))
    else:
        with ProcessPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(run_suite, spec) for spec in SUITES]
            for future in as_completed(futures):
                report(future.result())
    print('PASS: tooltip replay checks')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workers', type=int, default=1)
    options = parser.parse_args()
    if options.workers < 1:
        parser.error('--workers must be positive')
    run_replays(options.workers)
