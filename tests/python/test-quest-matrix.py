"""Run exhaustive quest objective, summary, and variable regression matrices."""

import runpy
import unittest
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))


TESTS = Path(__file__).resolve().parent


def main():
    objectives = runpy.run_path(str(TESTS / 'test-quest-objective-matrix.py'))
    objectives['run_matrix']()
    summaries = runpy.run_path(str(TESTS / 'test-quest-summary-matrix.py'))
    summaries['main']()
    variables = runpy.run_path(str(TESTS / 'test-quest-variable-matrix.py'))
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(variables['QuestVariableMatrix'])
    result = unittest.TextTestRunner().run(suite)
    assert result.wasSuccessful(), 'Quest variable matrix failed; see datasources/imports/quest-matrix/variables.json'
    print('PASS: quest matrices; full coverage diagnostics in datasources/imports/quest-matrix/')


if __name__ == '__main__':
    main()
