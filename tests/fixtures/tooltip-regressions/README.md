# Versioned multilingual tooltip regressions

This bounded synthetic corpus checks translation transport against fixed, readable expectations.
It is not an in-game capture, full-catalog coverage, or a linguistic quality check.

The initial selection covers spell 16757, aura 433 and the three verified talent ranks of
talent 1001 / spell 17783. Ten scenario files cover baseline/modified contexts, all ten
official source locales and all eighteen configured target locales, including same-language
pairs: 1,800 rendered cases. `inputs` and `expected` factor out repeated locale strings;
every source/target pair is still executed.

`selection.json` owns the scope. Expectations are produced by the independent fixture builder
in `tests/python/live_spell_fixture.py`, using maintained templates and controlled displayed
values. Production renderer output never supplies or updates expected text. Trait values come
from the versioned trait fixture, not computed player stats. The corpus currently supports
these spell/aura/talent text surfaces; duration cases require explicit format dependency pins
before they can be added. Existing captured-context tests and exhaustive matrices remain in place.

## Replay in CI or locally

Build the production database before replaying after a catalog update:

```sh
uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
uv run --no-project --with lupa==2.8 python tools/source-scan/tooltip_regression_corpus.py check
```

`tests/run-tests.py --unit-only` includes the corpus replay and workflow guards. Check mode
does not generate expectations, fetch sources, modify catalogs or install the addon. It
rejects omitted locales/ranks, unexpected fixtures, stale source pins, changed text, runtime
errors, forbidden API calls and incomplete translations. The small corpus supplements the
historical replays; it does not replace their distinct coverage or promise the same CI speedup
as removing those replays.

## Refresh after source updates

Follow [import/resync](../../../docs/import-resync.md) first: refresh providers only as needed,
prepare/review/apply/verify catalog changes, then build once. Raw downloads alone do not
change this corpus. It tracks accepted catalog records and their explicit spell references,
the locale inventory, rank evidence and independent generator code using SHA-256 pins.
Runtime implementation changes are deliberately not baseline inputs: a renderer regression
must fail against the existing expectation.

```sh
# Read-only freshness check. Exit 1 names the fixture and changed inputs.
uv run --no-project --with lupa==2.8 python tools/source-scan/tooltip_regression_corpus.py status

# Use a fresh ignored directory for each proposed update.
uv run --no-project --with lupa==2.8 python tools/source-scan/tooltip_regression_corpus.py prepare \
  --directory datasources/imports/tooltip-regressions-NEXT
```

Review `manifest.json` (changed fixture names and hashes) and `diff.patch` (old/new inputs,
expected wording and provenance pins). Unchanged fixtures remain byte-identical. A changed
selected spell affects only its dependent scenarios; unrelated source updates need no corpus
refresh. Missing translations, unsupported grammar or ambiguous slot alignment fail preparation
without dropping accepted cases. Do not change an expected value merely to silence a failing
renderer. Native captures retain their original text and build; synthetic updates do not turn
them into captures from a newer client.

After review, validate the proposed expectations against the rebuilt runtime, then apply:

```sh
uv run --no-project --with lupa==2.8 python tools/source-scan/tooltip_regression_corpus.py check \
  --directory datasources/imports/tooltip-regressions-NEXT/cases
uv run --no-project --with lupa==2.8 python tools/source-scan/tooltip_regression_corpus.py apply \
  --directory datasources/imports/tooltip-regressions-NEXT
uv run --no-project --with lupa==2.8 python tools/source-scan/tooltip_regression_corpus.py check
```

Application checks every proposed file hash, source dependency and existing fixture before
its first write. Edits made after preparation require a fresh proposal. Commit reviewed fixture
changes alongside the accepted source/catalog update; keep drafts and diffs under ignored
`datasources/imports/`. Extending `selection.json` is an explicit scope change, not an automatic
consequence of discovering upstream entities.
