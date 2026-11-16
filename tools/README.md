# Development tools

These tools are not shipped in the addon. Run commands from the repository root.

## Cleanup

`python3 tools/clean.py --dry-run` lists disposable outputs; omit `--dry-run` to remove
them after validation. Tracked files and local credentials are preserved. See
[the release guide](../docs/releases.md#clean-local-build-outputs) for the cache lifecycle.

## Build

`build/` contains the database builder, format generator, manifest template, runtime
projection/encoding helpers, and their third-party encoding dependencies.

```sh
uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
python3 tools/build/build-character-stat-formats.py --help
```

## Release

`release/` owns ZIP packaging and version-specific release notes. CI and release
workflows call the packager directly; the release workflow publishes the result on GitHub. Generated data addons are flattened beside the main
addon in release archives.

```sh
python3 tools/release/build-release.py
```

## Catalog maintenance

`catalogs/` contains shared catalog storage and the operational commands:

- `format-catalogs.py --check|--write [paths...]`: enforce the shared JSON layout, including
  metadata. Defaults to the whole catalog tree; writing verifies JSON values are unchanged.
  The format is UTF-8, two spaces, recursively sorted keys, expanded arrays and a final LF.
  `.editorconfig` and VS Code's built-in JSON formatter keep saves stable without Node tooling.
  VS Code tasks check all catalogs or normalize the current file after adding unsorted keys.
- `translation-work.py`: translation queues, reuse, validation and proposed patches.
- `plan-update.py`: compare frozen source corpora and prepare review-only update scopes and fingerprints.
- `catalog-batch.py`: disjoint assignments and validated submissions when delegation is authorized.
  Its `prepare-labels`, `check-labels` and `patch-labels` commands manage the readable
  GlobalStrings records under `catalogs/globalstrings/` with per-key guards and field provenance.
- `translation-pilot.py`: bounded, explicitly requested translation pilots.
- `fill-official-text.py`: reviewed source-backed text updates.
- `resync.py`: the catalog import/update entry point: prepare, apply, verify and queue under the shared policy.
- `import_policy.py`: deterministic source verification and AI eligibility; no model calls.
- `refresh-spell-values.py`: proposed numeric spell updates from verified snapshots.
- `spell_render_context.py`: school masks and flat duration dependencies derived from verified spell family/effect masks.
- `rendered_spell_templates.py`: guarded offline reconstruction of a missing leading percentage token
  or a uniquely broken conditional delimiter/prose boundary, using unanimous native template witnesses.
  Scoped import preparation and capture-backed API/conditional-template tests use it; it never writes
  catalogs or treats provider values as runtime constants. Derived token provenance remains explicit;
  normalizing an output template does not prove a malformed native input can be decoded.
- `catalog-coverage.py`: missing-text reports.

The [import/resync reference](../docs/import-resync.md) owns source priority, official and
additional-language rules, exact commands, review artifacts and regression coverage.
`resync.py` is the operational entry point; the other catalog tools are its shared helpers,
scoped authoring tools or read-only diagnostics. Source collection never writes catalogs.

`tools/build/client_label_scope.py` derives GlobalString scope from the owned tooltip adapters,
direct runtime consumers, dynamically constructed key families, appearance slots and profession
aliases. Import/resync, translation queues and completeness diagnostics share this
maintenance boundary; unused labels are not backfilled. Production builds ship every
owned GlobalString so dynamic native tooltip lines can resolve their labels. No fixed
key count is used. Empty localized separators are valid source values.

Maintained JSON files remain under the repository's top-level `catalogs/`. These tools do
not make downloaded sources authoritative or authorize an automatic catalog merge.

`tools/build/runtime_catalog.py` projects up to four original-source `descriptionVariants`
or `auraDescriptionVariants` per locale/field, with indexed field provenance and an exact
`canonicalEnglishSha256` guard. The primary native text stays intact. Variants are owned
source-backed alternatives, not generated translations; the runtime requires full input
matching, unchanged slot identities/counts and one unique fallback output.

## Sources and local collectors

Source fetching, validation and snapshot comparison live under [`datasources/`](../datasources/README.md).
The reference-corpus builder and lookup tools live under [`datasources/corpus/`](../datasources/corpus/README.md).
GitHub and CurseForge community translations remain active datasources; the complete registry and
per-source attribution/licence notes are under `datasources/`. CurseForge sources discover
current public releases without a Core API key. Retain accepted catalog text, provenance
and shipping credits during refreshes.

`quest-scan/` and `source-scan/` prepare separate local collectors. Neither is shipped,
installed or started by the source refresh. In-game collection requires an explicit request.
`source-scan/rosetta-tooltip-check/` provides the opt-in `/frsverify` calibration campaign
for full item, spell and active-aura payloads with labelled gear profiles. Its `/frsverify api`
pass feeds `source-scan/import_client_api_fixture.py`, which writes replayable Lua test fixtures
and a GlobalStrings catalog report; `source-scan/prepare_api_sample.py` samples the catalog for it.
`source-scan/prepare_tooltip_coverage.py` selects IDs by tooltip feature from a Wago snapshot, and
`source-scan/report_tooltip_gaps.py` replays the captured tooltips through the shipping renderer
and groups the rows that would show the incomplete-translation notice.
`source-scan/prepare_tooltip_campaign.py` prepares a bounded recapture inventory from a gap
report. `/frsverify cible <label>` preserves individual hover contexts and renderer API
dependencies for replay; see the [targeted campaign](source-scan/rosetta-tooltip-check/README.md#targeted-recapture-campaign).
`source-scan/import_description_rows.py` validates a completed raw capture and proposes
capture-backed item description row bindings; see its [workflow and limits](source-scan/README.md#propose-item-description-row-bindings).

`source-scan/client_hotfix.py` reads native XFTH v9 Spell and ItemSparse cache captures with
exact-build WoWDBDefs definitions. Scoped import preparation and `test-client-hotfix.py` call
it to retain raw templates/text, typed item fields, active push IDs and entry offsets.
It never rewrites catalogs or uses rendered
values as replacement templates; captured cache inputs stay under `datasources/imports/`.

See [`tests/README.md`](../tests/README.md) for validation commands.

`source-scan/roundtrip_tooltip_campaign.py` derives reverse spell test inputs from bounded
native captures. It reports untranslated rows, changed quantities and text differences
separately; generated reverse inputs never count as native target-client captures.
The five-capture, 17-target pilot runs in `tests/python/test-tooltip-roundtrip.py`.

`source-scan/official_tooltip_matrix.py` replays the versioned native tooltip corpus in
the 90 ordered directions between the ten official locales. Foreign source inputs are
derived from successful renderer output, with captured typed metadata retained. A missing
forward translation or unsupported row alignment blocks generation explicitly; it never
counts as a passing direction. Reports retain each failed direction's fixture hash,
case fingerprint, rows and numeric evidence, alongside grouped summaries.

`source-scan/derived_tooltip_rows.py` maps output back to captured row owners using
renderer provenance observed by the replay harness. Visible talent previews remain a
separate surface: the adapter does not manufacture structured header fields, API
responses, or row types. Ambiguous ownership blocks generation. Player replay retains
captured names and APIs. Recorded `Context()` level, sex and faction responses are
replayed only for their actual `"player"` argument; explicit API observations take
precedence. Missing gender is reported only when successful decoding proves that
the absent choice changes the result.

Live bind-location labels use a compiled index of owned area names. Translation is
allowed only when every matching source label agrees on the target wording; this
does not establish an area ID or substitute the player's current location. Unknown
or ambiguous labels stay native and are reported as incomplete.

`source-scan/triage_official_tooltip_matrix.py` separates missing captured APIs, missing
owned translations, replay alignment gaps and remaining decoder/source candidates.
Missing set names or equipment labels are catalog coverage gaps, not missing gameplay
context. Numeric differences remain review candidates; reverse tests cannot establish
linguistic accuracy or correct localization of live place names.
Derived requirement failures retain their captured typed owner when it is unique,
so absent official form/equipment labels are also reported as source coverage gaps.
Word/digit differences are classified separately only when both complete rows decode
through the same owned spell template to identical text in another official locale;
the report retains that proof and does not rewrite the native capture.

```sh
uv run --no-project --with lupa==2.8 python tools/source-scan/official_tooltip_matrix.py \
  --output datasources/imports/tooltip-matrix
uv run --no-project --with lupa==2.8 python tools/source-scan/triage_official_tooltip_matrix.py \
  --report datasources/imports/tooltip-matrix/report.json \
  --output datasources/imports/tooltip-matrix/triage.json
```

`tests/run-tests.py --unit-only` runs bounded matrix accounting and real-capture regressions;
it does not run the complete 90-direction corpus matrix.

For a fast gate using both native French and English corpora and their derived return
inputs, pass `--locales frFR enUS` to `official_tooltip_matrix.py`. It checks exactly
two ordered directions per replayable variant. This subset gate does not certify
other locales; omitting `--locales` retains the full ten-locale, 90-direction matrix.
Reports separate `native_to_target`, `return_to_native` and `cross_target` paths.
A failure in a third language is not an unsuccessful return to the native capture.
Failed true returns retain observed generation values, grammar choices and raw row
origins. These are diagnostic evidence only: they never supply hints or invented
API answers to the shipping renderer. A preserved unresolved client token and a
localized label that collapses multiple source meanings remain unvalidated.

`source-scan/import_item_interactions.py` prepares an `interactionLabelID` relationship
from scoped native item API rows. It accepts only an unambiguous owned `ITEM_READABLE`
or `ITEM_SIGNABLE` literal on an untyped row; visible addon extras and generated
translations are not evidence. Apply and verify its manifest with `catalogs/resync.py`,
then build once. The numeric ID names a versioned GlobalStrings owner, not an item
exception or translated text. Conflicting identities remain in review.
