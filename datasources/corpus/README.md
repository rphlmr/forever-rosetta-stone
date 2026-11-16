# Translation reference corpus

The corpus is an offline, searchable reference library for agents. It generates no translations,
queues, patches, or catalog edits. Catalog JSON remains the maintained source of truth.

## Book codex

The optional [book identity pipeline](../books/README.md) stores reconciled owner identities and
VMaNGOS page links in separate `book_codex` tables, never in translation records. Saved
`scope: book-identities` configurations rebuild without reading maintained catalogs or page
bodies. Normal corpus input verification covers both paths; book-only runs are reference
artifacts, not translation resync baselines.

## Storage and source selection

Use SQLite with FTS5 for storage and JSON for agent packets. One database contains separate
locale-indexed records, English/target pairs, provenance, input SHA-256 hashes, and language flags.
Agents retrieve compact evidence instead of loading every language's corpus into context.
English is stored once as `enUS`; `enGB` lookup inputs are rejected. Catalog configuration,
corpus language lists and generated work queues contain 18 languages, with one English entry.
Historical source-locale provenance remains unchanged; completed migration commands are retired.
Quest player variables are normalized during SQLite ingestion to `{name}`, `{class}` and
`{race}`, and recognized line-break markers become newlines. This includes the audited
community aliases; downloaded evidence and its checksums remain unchanged. Spell/item formulas,
quest objective-count expressions and gender selectors retain their functional syntax.
Ambiguous community grammar, entity and selector markup receives `unsupportedQuestMarkup`
flags and is excluded from reuse candidates. Rebuild an older corpus to apply these rules.
Python's standard library handles catalog/Wago/EG Link ingestion and retrieval. Questie lookup
ingestion uses the project's existing pinned `lupa==2.8` dependency.

[datasources/refresh.py](../refresh.py) fetches the selected providers into a new
ignored `datasources/imports/<run>/` directory, then builds and verifies SQLite. Follow the
[refresh guide](../README.md) for the ignored Blizzard `.env` setup and commands.
`datasources/corpus/sources.json` is the layout template; each successful fetch produces
`datasources/imports/<run>/sources.json` with concrete snapshot paths and pinned revisions. Use the generated
config for builds. Builds fail on missing inputs, incomplete Blizzard collections, unsupported
source shapes, or checksum mismatches. Existing databases are never replaced.

| Evidence | Meaning |
| --- | --- |
| `sourceSnapshot` | Text read directly from the selected Blizzard, Wago, EG NPC/item, or Questie data file; still verify language, build applicability and context. |
| `catalogClaim` | Original/community text retained in the catalog, including credited upstream AI text with its real origin. Provenance is a claim, not independent verification. |

Rosetta-authored AI text is excluded from reference evidence. Complete entity packets retain the
current translations, including AI text, so workers can preserve valid work. Credited community
AI sources remain indexed with `origin: ai`; they are never relabeled as native or human-authored.
There are no raw community archives in this selection: community evidence comes from the catalog's
retained credited fields. Missing Danish/Croatian references are gaps, not instructions to invent text.

Questie imports composed English item/quest text and literal locale tables without executing loader scripts. Quest
fields compose base and per-field trace overrides. Item names retain their base locale table;
different or trace-only item names are retained as `unverifiedItemNameTrace` observations,
excluded from automatic reuse and fills because they can contain random enchantment suffixes.
Community prose fills also require protected placeholders to match the maintained English
source. A conflicting candidate leaves the existing translation intact and is counted as
`communityPlaceholderMismatch`; verified official wording retains its own source tokens.
NPC names use the first tuple slot,
compose base and per-field trace overrides, and match corrected exported English identities.
A single objective-summary string can supply `summary`;
paragraphs separated by explicit empty entries retain their newline separators. Multiple
nonempty entries without paragraph separators remain ambiguous and are not joined or
interpreted as client-indexed objectives. Blizzard supplies quest
titles and full descriptions, with Questie as the missing-title fallback. It supplies no summaries.
Italian Blizzard quest slots are excluded; other fallback text remains flagged. EG quest inputs are
rejected. EG Link supplies NPC names and text from valid
item-hotfix rows; removed and invalid items are excluded. English pairs from other evidence are attached only when
original English candidates for the same entity and field agree. Verified community English
snapshots, including Questie, provide the fallback when no original English snapshot exists;
they take precedence over catalog claims. Conflicting candidates and AI English never create
a fallback pair. Disagreement leaves the pair absent.

## Import/resync decisions

The [canonical policy and workflow](../../docs/import-resync.md) owns source priority,
target-language rules, accepted-translation preservation, review stages and apply/verify.
Use `tools/catalogs/resync.py` for updates. `fill-official-text.py` is its source-selection
helper; `audit-authored` is a read-only diagnostic for source-backed official replacements.
Shared eligibility lives in `tools/catalogs/import_policy.py`; provider/build ordering lives
in `tools/catalogs/official_text.py`. Neither uses a model to classify source translations.

Provenance does not gate runtime capture: a maintained template of any origin is usable
only when it matches the visible client text unambiguously. GlobalStrings use the same
owned tooltip-key scope for import, queues and production builds.

## Build and inspect

Run `datasources/refresh.py` before source-driven catalog work. It discovers current versions,
fetches every selected provider, and only then builds and verifies a new SQLite database.
For an exact offline rebuild, retain the run's raw files and pass its generated `sources.json`.
Use only collected, hash-verified inputs from the selected `datasources/imports/` run. Trusted text
updates take precedence over AI drafts; review conflicts with explicit manual fixes. Check every
supported language when source meaning changes and fill affected translation gaps.
Keep all selected Wago tables on that build. Older builds are comparison evidence, not fallback
inputs for the current client corpus. Other providers retain their actual independently published
build/revision; do not relabel their older evidence as current client data.
Item subtitles join `ItemSparse.ItemNameDescriptionID` to `ItemNameDescription.ID` in the same
build and locale, and export as `items.nameDescription`.

Run from the repository root. The build indexes catalogs once, then the selected upstream files.
It never fetches data, installs an addon, or resumes translation work.

```sh
uv run --no-project --with lupa==2.8 python datasources/corpus/translation_corpus.py build \
  --config datasources/imports/RUN/sources.json \
  --output datasources/imports/RUN/corpus.sqlite

python3 datasources/corpus/translation_corpus.py coverage \
  --database datasources/imports/RUN/corpus.sqlite \
  --output datasources/imports/RUN/coverage.json

python3 datasources/corpus/translation_corpus.py verify \
  --database datasources/imports/RUN/corpus.sqlite
```

`coverage` reports evidence rows by language, kind, evidence and origin, plus flagged counts and
known limitations. These are reference counts, not unique translations or a completeness score.
The database records every selected input's hash. `verify` checks those inputs against disk and
returns a failing exit status on changes. Run it once before using a frozen corpus for a run.
New catalog JSON files also invalidate verification.
Build into a new output path after relevant source changes; do not overwrite a frozen run's evidence.

## Search and prepare an entity packet

```sh
python3 datasources/corpus/translation_corpus.py search \
  --database datasources/imports/RUN/corpus.sqlite \
  --locale frFR csCZ --kind spells --field description --query 'fire damage' --limit 3

python3 datasources/corpus/translation_corpus.py packet \
  --database datasources/imports/RUN/corpus.sqlite \
  --kind quests --id 1289 --locale frFR itIT csCZ --limit 2 \
  --output datasources/imports/RUN/quest-1289.context.json

# Restrict reference retrieval to the fields being translated.
python3 datasources/corpus/translation_corpus.py packet \
  --database datasources/imports/RUN/corpus.sqlite \
  --kind spells --id 348 --locale frFR itIT --field description auraDescription

python3 datasources/corpus/translation_corpus.py lookup \
  --database datasources/imports/RUN/corpus.sqlite \
  --kind items --id 25 --locale frFR --limit 10
```

Search returns ranked, deduplicated examples in the requested languages. Queries are treated as
literal words, not FTS instructions. `--limit` is bounded to 1–10; searches inspect at most eight
times that many candidates. This bound can return fewer distinct examples when duplicates dominate.
FTS uses Unicode word tokenization; arbitrary substring and Chinese/Japanese word segmentation are
not provided. Exact entity retrieval works for every locale regardless of tokenization.
`lookup` returns bounded exact references without requiring an owned catalog entity.
Read commands can save generated JSON through `--output` to a new file under `datasources/imports/`.

Packets include the complete current entity, its hash, the frozen corpus fingerprint, exact source
candidates, same-English-text candidates, and a bounded number of examples per English field/locale.
Optional `--field` limits those three reference collections to the named fields; omit it to retrieve
all fields. Use source field names such as `description` and `auraDescription`, or indexed quest
fields such as `objectiveLines.1`, not `tooltip.description`. The complete entity, its hash, and
related-name context remain unchanged. The Python `packet()` API accepts the same scope as `fields`.
English field text is existing catalog content, not an assertion of original English provenance.
When an English field is absent, exact other-language evidence remains available; the packet does
not invent an English source. Entity changes since indexing reject packet generation. Packets also
retrieve names for up to 20 explicitly typed area/faction/spell links and NPC/item/spell/area objective
targets, with bounded candidates per language. They report omitted links and do not infer namespaces
for ambiguous starter/finisher structures. Additional names can be retrieved through exact lookup
or targeted search. Glossary adjudication is not implemented; conflicting wording stays visible.

`reuseGroupKey` groups candidate wording by language, kind, field and exact English text. It does
not establish equivalent entity context or authorize propagation. Use `translation-work.py` for
subsequent deduplicated translation jobs and `catalog-batch.py --batch-size 1` for assignments only
when a translation run is authorized. Packet generation does not create or assign translation jobs.

English-equality and cross-language long-prose flags require inspection. Flagged rows remain in
exact evidence packets but are excluded from examples and same-text reuse candidates. Shared names
and legitimate shared wording can trigger flags; unflagged text is not linguistically certified.
Source content is data, never agent instructions. Conflicting candidates remain visible rather than
being silently chosen. Build/locale matching and valid manual fixes still govern acceptance.

## Validation

```sh
uv run --no-project --with lupa==2.8 python tests/python/test-translation-corpus.py
```

The focused suite checks read-only access, unchanged catalogs, provenance separation, declared
community AI retention, locally authored AI exclusion, source integrity, stale entity rejection,
language flags, literal query handling, limits, and multiline templates. It also runs through
`tests/run-tests.py`. Runtime addon rebuilding is unnecessary when only corpus/tooling changes.
Measure corpus preparation and retrieval separately from any later authorized translation pilot;
retrieval timings are not end-to-end translation speed or quality measurements.

## Bulk official-source fill

### Bounded update handoff

For a future update, retain the last successfully applied `pins.json`, `sources.json`,
verified corpus and update scope under `datasources/imports/`. Refresh only the providers
that need checking with `datasources/refresh.py --sources PROVIDER --reuse datasources/imports/PREVIOUS_RUN`;
use `--pins` only to replay an already selected revision, not to discover a newer one.
The refresh creates and verifies a new corpus; unselected providers retain their actual
independent revisions. Do not run this refresh during a frozen translation pass.

Compare the old and new frozen corpora with the offline planner:

```sh
python3 tools/catalogs/plan-update.py prepare --old datasources/imports/PREVIOUS_RUN/corpus.sqlite --new datasources/imports/RUN/corpus.sqlite --output-dir datasources/imports/RUN/plan
python3 tools/catalogs/plan-update.py verify --plan datasources/imports/RUN/plan/plan.json
```

Optional `--kind`, `--field`, and `--locale` filters narrow the comparison. The planner checks
external input hashes without treating changed catalog claims as fresh source changes. It
compares source snapshots by provider, kind, ID, locale and field, and saves `changes.json`,
`fill-scope.json`, `translation-scope.json`, `new-entity-candidates.json`, `field-review.json` and their fingerprints in
`plan.json`. Duplicate identical evidence is grouped; conflicting candidates, flagged source
rows, upstream AI, lower-priority community candidates when native text exists, and removals
are reported for review and excluded from the fill proposal. Origin and paired English-context
changes are reported even when the visible text stays the same; build/revision changes alone
do not create jobs. Changed English
fields list every configured target, including existing translations. Re-run `verify` before
using saved work: changed external inputs, corpora, locale configuration or affected entities
invalidate it. Plan verification checks inputs, not linguistic quality or review decisions.

The fill scope is a **proposal**, not authorization to overwrite: it may include a field marked
`manualOrOwnedConflict`. Review each change and remove rejected or unresolved tuples before
passing the scope to fill. Resolve provider precedence and manual fixes explicitly; a source
removal is never an instruction to delete catalog text. The fill and translation scopes exclude
new entities: inspect `new-entity-candidates.json`, verify real source and supported languages,
then use the null-record `catalog-batch.py prepare` path in
[catalog maintenance](../../catalogs/AGENTS.md#assign-bounded-batches-to-agents) or a direct
reviewed entity edit. Fill cannot create entities, and an ID-only translation queue is not a
new-entity importer. A numeric-only change follows the Wago
numeric workflow and does not itself create translation work.

Prepare the provider-qualified scope with `fill-official-text.py prepare --database
datasources/imports/RUN/corpus.sqlite --output datasources/imports/RUN/fill --scope
datasources/imports/RUN/scope.json --update-english --include-community`, review its
reports and patches, then run `apply --directory datasources/imports/RUN/fill` and
`verify --directory datasources/imports/RUN/fill`. The apply command performs hash-checked
deterministic writes; do not treat review as automatic. It checks source files and before/after
entity hashes, but currently filters scope after fetching matching SQLite rows. A narrow scope
therefore limits writes, not necessarily source scanning.

For changed source meaning, check all configured target languages; retain valid wording and
its origin, prefer verified applicable source text, then context-matched existing translations,
and author only remaining gaps. Record affected field and target before/after fingerprints,
decisions, result files and unresolved conflicts in the ignored run directory. These records
record decisions and completed results alongside the plan; the planner does not schedule or
resume workers. Revalidate saved work against current source and targets before applying it.
Packets reject changed entities;
after catalog changes, build and verify a new corpus before requesting fresh packets. A frozen
corpus is not silently updated to include accepted AI translations.

Create `entity-scope.json` as a kind-to-ID selection and prepare the missing-field queue once:

```sh
python3 tools/catalogs/translation-work.py queue --scope datasources/imports/RUN/entity-scope.json --output datasources/imports/RUN/queue.json
python3 tools/catalogs/translation-work.py validate --queue datasources/imports/RUN/queue.json --results datasources/imports/RUN/results.json
python3 tools/catalogs/translation-work.py patch --queue datasources/imports/RUN/queue.json --results datasources/imports/RUN/results.json --output datasources/imports/RUN/translations.patch
# Review and apply translations.patch with apply_patch, then:
python3 tools/catalogs/translation-work.py verify --queue datasources/imports/RUN/queue.json --results datasources/imports/RUN/results.json
```

The queue deduplicates jobs by locale, field context and exact source text, records source hashes
and reports missing source. Inspect reuse candidates and conflicts, including context, before
accepting them. `reuse`, `reference-reuse`, `value-reuse` and `collect` can prepare results or
remaining queues; use their `--help` for the required saved inputs. Scoped queue reuse searches
the selected records, so use the corpus for additional evidence. Queue scope selects IDs, not
individual fields, and the missing-field queue does not independently determine which existing
translations became stale after source meaning changed. Manually review those targets and
scope changes; do not assume a queue proves they are current. `catalog-batch.py prepare`,
`check`, and `patch` provide fingerprinted, disjoint entity assignments when delegation is
authorized. Neither queue validation nor batch checks establish linguistic correctness.

`--kinds npcs classes creaturetypes talents` limits writes to those catalog types.
Maintained external community snapshots are included by default, retaining their true origin.
`--original-only` limits candidates to original game text; `--include-community` remains accepted.
Titles/names do not replace an existing original field by default. Questie summaries follow the selected summary policy. Inherited catalog claims are never source-fill evidence.

Run the complete refresh described in [datasources/README.md](../README.md).
Use its generated `sources.json` for all catalog kinds, then limit any proposed catalog writes
with `--kinds`. This uses one source snapshot rather than separate name-only download setups.

`fill-official-text.py` copies official source snapshots from SQLite into existing catalog entities.
It automatically fills missing fields and synchronizes verified names by their entity IDs.
For prose/templates it replaces differing target text when the source English
matches the current canonical English field (or no English field exists), and confirms source
provenance for identical text. Matching native text keeps its existing metadata. Canonical English
differences, ambiguous candidates, flagged language fallbacks, and unresolved source templates are
preserved/skipped. It never creates entities, invents text, or treats community/catalog claims as
independent official evidence. Source input checksums are checked before matching.

```sh
python3 tools/catalogs/fill-official-text.py prepare \
  --database datasources/imports/RUN/corpus.sqlite \
  --output datasources/imports/official-source-fill-next
python3 tools/catalogs/fill-official-text.py apply --directory datasources/imports/official-source-fill-next
python3 tools/catalogs/fill-official-text.py verify --directory datasources/imports/official-source-fill-next
```

Preparation saves machine-generated diffs and before/after hashes. `apply` writes the deterministic
generator output directly, checking those hashes before every write. `verify` checks every generated
result automatically. No model reviews individual records. New English fields are stored only
under `enUS`; remaining community-language gaps require a separately authorized translation step.
Build and run catalog tests once after the bulk fill. The old corpus remains a frozen reference;
rebuild into a new corpus path before generating packets for the changed entities.

For a reviewed upstream update, prepare a scope containing `[kind, ID, locale, field]` tuples
for fields changed or added since the previous trusted snapshot. A fifth tuple value can name
the provider (`blizzard`, `questie`, `egLink`, or `wago`); use it for upstream deltas so an unchanged older
snapshot cannot override the provider's actual update. Add missing target fields for
affected English text. Pass `--scope PATH --update-english --include-community` to `prepare`.
This explicit mode accepts trusted changes over older catalog claims, including English prose;
the default bulk-fill mode keeps its canonical-English and original-over-community safeguards.
For quests, Blizzard titles/descriptions take priority and Questie supplies summaries and missing titles.
For NPC/item fields, build-matched EG Link server text takes precedence over client CSV text.
Trusted summaries with literal required counts do not need objective placeholders added. Unknown source names
and unsupported English client markup are skipped. Equivalent English placeholder/newline
representations are preserved. Keep source-unchanged local corrections out of the update scope,
review other manual-fix conflicts, and complete affected translations before the final build.

## Bounded translation pilots

`translation-pilot.py` prepares one entity per staging assignment using the existing batch and
corpus tools. Supply an explicit scope and optional controlled holdouts as JSON records with
`kind`, `id`, `locale`, `field`, and `mode`. Holdouts remove those fields from worker results and
entity context only; `.batch.json` snapshots retain coordinator-only baseline answers. Workers
must not open the original catalog file or batch snapshots during controlled tests. Reference
answers remain in the corpus intentionally: recovery measures lookup, not novel translation quality.

```sh
python3 tools/catalogs/translation-pilot.py prepare \
  --directory datasources/imports/translation-corpus/pilot-next \
  --database datasources/imports/RUN/corpus.sqlite \
  --scope datasources/imports/translation-corpus/pilot-20261112-scope.json \
  --holdouts datasources/imports/translation-corpus/pilot-20261112-holdouts.json

python3 tools/catalogs/translation-pilot.py evaluate \
  --directory datasources/imports/translation-corpus/pilot-next
```

This prepares files; it does not launch workers or modify catalogs. Workers must use the user's
requested model/effort, own one results file at a time, and save separate timing/decision metrics.
The evaluator validates completed results against current batch snapshots and distinguishes
controlled holdouts from originally absent fields. It requires unchanged unmasked text and
relationships, and rejects added fields without the scoped English source. Linguistic assessment
is separate. Keep first-attempt outputs; store narrowly corrected versions as
`NNNNN.corrected.results.json`, then use `evaluate --corrected` for a separate evaluation artifact.
After the separate assessments are complete, `summarize --directory RUN_DIRECTORY` gathers the
first-attempt measurements, corrections, evidence limitations, and assessment artifacts in `summary.json`.
Translate visible gender-choice words while preserving `$g<masculine>:<feminine>;` syntax; freezing
English branch words can produce a structurally valid but visibly mixed-language translation.
