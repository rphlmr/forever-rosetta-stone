# Tests

- `python/`: Python checks, matrix drivers and shared database harnesses.
- `lua/`: addon and renderer harnesses.
- `fixtures/`: captured data used by checks. `fixtures/client-api/` holds in-game API captures
  replayed by `lua/support/client-api-fixture.lua`, which also serves catalog GlobalStrings; see
  [the API fixture pass](../tools/source-scan/rosetta-tooltip-check/README.md#api-fixture-pass).
- `run-tests.py`: repository test entry point.

Run from the repository root:

```sh
# Unit/integration checks only. Does not run translation matrices.
uv run --no-project --with lupa==2.8 python tests/run-tests.py --unit-only

# Replay every tooltip suite across three local worker processes, as in CI.
uv run --no-project --with lupa==2.8 python tests/python/run_replays.py --workers 3

# Focused checks can run directly.
uv run --no-project --with lupa==2.8 python tests/python/test-lua-database.py
uv run --no-project --with lupa==2.8 python tests/python/test-release.py

# Full translation and variable-rendering matrices.
uv run --no-project --with lupa==2.8 python tests/python/test-translation-matrix.py
uv run --no-project --with lupa==2.8 python tests/python/test-translation-matrix.py --strict-coverage
```

Running the entry point without `--unit-only` also runs translation matrices. Only run those
when requested. Generated packs live in `ForeverRosettaStone_Data/`; fixtures and release tests preserve
the flat installed addon layout.

The [versioned tooltip regression corpus](fixtures/tooltip-regressions/README.md) provides
1,800 fixed source/target/profile/rank cases for three template surfaces. CI replays those
expectations directly. `tooltip_regression_corpus.py status` detects source drift;
`prepare` writes a proposed update and diff under ignored imports, and `apply` promotes the
reviewed files after hash preflight. Historical capture replays and their matrices remain separate.

`python/test-debug-pick-context.py` exercises the manual picker against recorded French
unit/item and English aura captures. Picks retain readable native payloads plus a
`tooltipEvidence.replayContext` snapshot: player/unit state, typed item/spell lookups,
owned spell conditions, and aura instance/caster context. Each API call records its
arguments and all returns, or an explicit missing/error/restricted status. Essential
missing context marks the snapshot `partial`; `captured` does not promise that optional
APIs or hidden engine state were available. Extra linked lookups are bounded without
truncating the native tooltip payload. Failure tests inject faults into recorded inputs;
those injected states are not presented as native game captures.

GitHub CI and Release run `--unit-only` plus database and packaging checks. The manual
**Translation coverage** workflow runs the strict matrices and uploads its reports even when
coverage is incomplete. Missing text remains a failed coverage case.

## Bounded template pilot

The pilot runs one selected entry per surface, independently of the full matrices:

```sh
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot.py
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot.py --surface items --source zhTW --target frFR
```

It covers spells, auras, talents, items, quests, GlobalStrings and NPC tooltips across the
ten official source languages, all eighteen FRS target languages, and two controlled contexts.
Italian is a target; Forever's Italian client exports English fallback, so it is not a
separate original source language. Same-language source/target pairs are included.
Each surface writes a complete case report under ignored
`datasources/imports/translation-matrix/pilot/`, alongside `suite.json` and `summary.md`.
Exit status 1 includes rendering failures, missing data and enumeration/stage errors.

Selections are deliberately small: spell 16757 (Arctic Reach, including identical English
official descriptions), aura 433, talent 1001 and its three verified
trait ranks on spell 17783, item 118 and its spell 439, quest 95317, GlobalStrings 11886 (`ITEM_MIN_LEVEL`)
and 22544 (`LARGE_NUMBER_SEPERATOR`, including valid empty separators), and
NPC 823 with its owned faction and structured creature type. Entity IDs select test fixtures;
they introduce no runtime exceptions. Only selected catalog records and linked dependencies
are loaded. Existing generated database packs must already be available; the pilot does not
refresh sources, rebuild, install addons, or collect in-game data.

The tests feed maintained source templates with synthetic displayed values to the real spell,
aura, talent and item renderers. Quests use target templates and structured client context;
native quest prose is diagnostic, not a matching prerequisite. Names are selected by ID.
GlobalStrings and NPC cases exercise whole-tooltip rendering, including incomplete footers.
Talent ranks come from the retained build-70938 `TraitDefinition`/`TraitNodeEntry` rows in
`tests/fixtures/template-pilot-talents.json`, with their source export hashes. Curve points
provide distinct rank inputs (23, 47, 70); the engine only captures these displayed amounts.
Legacy `Talent.SpellRank` IDs are not treated as separate active spells. Enumeration includes
rank in each case identity, so omitting a rank cannot be hidden by repeated spell IDs.
Expected text is constructed independently from maintained templates and controlled values,
never from the production renderer's output. The NPC level targets currently come from the
versioned `database/npc-tooltip-data.lua` format declarations, read separately as data.

An independent inventory verifies every planned ID/field/source/target/context identity,
rejects duplicates and omitted cases, and reconciles the reported counts. Missing source
templates needed for native-text matching and missing target data are classified explicitly:

- Identical English source/target wording is a valid rendered result.
- A field explicitly empty in every official locale is `not_applicable`; absent data alone
  does not establish this condition.
- Nonempty English with an empty/absent official source or target produces a nonblocking
  `warning`, retaining the values and distinguishing empty from absent. It is not a rendered pass.
- The separator case checks `''` as a real exported value, plus number formatting through
  the production formatter. Additional-language separators absent from the catalog are optional
  dependencies: their absence is accepted only alongside the independently expected locale-default
  number. A missing separator in an official source, a wrong export or incorrect number still fails.
- An absent additional-language field is `allowed_absence` only with an explicitly supplied
  verified source corpus and the shared import-policy decision for the current ID, field,
  locale and English text. Existing
  translated text is still checked. Without that evidence, missing data remains failed.

Use `--database datasources/imports/<source-run>/corpus.sqlite` to supply this evidence.
The pilot calls the shared deterministic rule directly; it does not read versioned queues,
refresh sources, scan the full catalogs or create translation jobs.
Reports retain separate counts for rendered passes, warnings, non-applicable cases,
authorized absences and failures. Warning-only runs exit successfully without claiming
complete rendered coverage. `test-template-pilot-policy.py` exercises these boundaries using
controlled catalog states and the two concrete records above. This pilot
does not establish full-catalog coverage or exercise every grammar branch, plural, duration
or value shape; its two contexts exercise the selected templates only.

Run the focused guards directly:

```sh
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot-harness.py
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot-policy.py
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot-spells.py
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot-items.py
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot-quests.py
uv run --no-project --with lupa==2.8 python tests/python/test-item-cooldown-delimiters.py
```

Spell, talent, aura and item-effect rendering uses only the shipping live capture engine.
`live_spell_fixture.py` independently creates synthetic displayed values from maintained source templates
and target wording; it never evaluates spell formulas. Numeric profiles vary the displayed values,
not character stats. The matrix checks ID selection, value capture/localization and explicit
incomplete fallbacks. Recorded client examples remain separate from synthetic fixtures. Quest
matrices keep their existing structured-progress and reward contract.

The matrices enforce both complete target translations and correct variable rendering against
independent expectations. Missing data and checker limitations remain failed, unverified coverage
cases; classification never turns them into passes. A zero count of confirmed addon bugs does not
mean complete coverage.

Completeness checks required target fields. Rendering compares owned target wording with the
production result while independently supplying its displayed variables. These checks cannot certify
that the stored prose is in the right language or faithfully translates the source meaning;
linguistic review is separate.

The catalog-placeholder stage checks text fields in every catalog, including nonshipping
quests, against original fields in official client languages. It reports changed or missing
value tokens, repeated-token counts, formula expressions and referenced spell IDs. Positional
printf arguments may be reordered; color codes and literal quest gender wording may vary.
It uses a translation's original official source language when recorded, otherwise original
English or another original official field. Differences between original official fields
are retained as informational variations; each original keeps its own tokens. AI text never
becomes reference evidence. Missing text
is counted by the separate completeness gate. See
`datasources/imports/translation-matrix/catalog-placeholders.json` for exact expected/actual tokens.

Fields without an official English source are outside catalog scope. Unsupported translated
fields are removed in every language, and records without an English name (quest title)
are excluded entirely. Do not create an English translation from another language to
retain unsupported text. The importer, translation queues and build projection enforce
this boundary; indexed quest progress labels retain their structured client-data contract.

Shared labels are checked in every configured language. The speed-label check requires
both `SPEED` and `WEAPON_SPEED`, instead of asserting that an unidentified speed row stays
untranslated. Fixtures require a concrete client scenario and sufficient structured context.
Live quantity substitution is covered separately.

Captured tooltips must render without a missing-translation warning. Preserving a native
line is safe runtime behavior, but it is not a passing translation-completeness result.
Shared GlobalStrings labels and formats are translated through the whole-tooltip renderer;
entity descriptions and names still require owned IDs. The shared-label matrices expect
actual target wording rather than accepting a nil translation. Integration checks require translated rows and no incomplete footer when every row is supported.

Read `datasources/imports/translation-matrix/classification.md` for the human summary, or
`classification.json` for the reconciled machine-readable breakdown:

- `addon_bug`: an independently expected result disagrees with production output, or production
  raises an error or uses a forbidden native-text dependency.
- `missing_data`: an owned target, source field, reference, numeric rule, or verified client index
  is absent or invalid. This does not establish that upstream data is unavailable.
- `test_limitation`: the matrix lacks a verified row identity, client context, or a supported
  independent expectation. The production result remains unverified.
- `unclassified`: a new diagnostic requiring investigation. It remains a failure.

Execution, stale-report and enumeration errors appear separately as `stage_error`; they cannot
be mistaken for missing translations. Individual case reports retain locale, field, profile,
surface, expected/actual previews, and available dependency evidence. Group summaries distinguish
case counts from affected targets, collapsing profiles only. The repeated spell-shard stage is
excluded from the aggregate case totals. The UI fallback checks are counted separately from
catalog completeness.

The separate all-catalog presence gate includes all configured kinds/locales and nonshipping
quests. It reports missing English-source-backed target fields, missing English-source fields,
and unverified alternate sources separately. Alternate AI or client text is not automatically
accepted as usable source evidence. Those field counts remain separate from rendering-case counts.

`suite.json` lists each stage and its detailed report. Both matrix commands above still fail
when strict catalog completeness is unverified; `--strict-coverage` additionally enforces the
supplemental stage review groups. No runtime or catalog text is changed by the matrix runner.

## Fresh tooltip capture evidence

`context-recapture-scope-20261116.json` under `tests/fixtures/` records the incomplete historical
cases superseded by the complete native French context recapture. The replacement captures
must pass every official direction with the actual required sex/faction and unit API evidence.
Once corresponding scenarios are covered, the listed historical context gaps and their blocked
generation consequences are not active release blockers. Never transplant new calls into old
observations or retire translation/source failures through this scope. Mixed historical fixture
files remain useful to other replay tests; a raw all-history audit is separate from the current
release evidence view. `test-captured-context-recapture.py` verifies the new native inventory,
human and female-night-elf context, directional success, and pinned replacement scope.
