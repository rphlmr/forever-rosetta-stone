# Catalog import and resync

[Back to the project](../README.md) · [Database](database.md) · [Source adapters](../datasources/SOURCES.md)

This is the reference for import/update/resync decisions. Apply it **per entity ID, field
and target language**. Source collection, catalog changes, translation authoring and runtime
rendering are separate operations. Refreshing sources never edits catalogs.

## Source priority and provenance

**Blizzard, Wago, Questie and EG Link are trusted providers**, within their supported fields.
Trusted does not mean every row is applicable: verify Forever identity, locale, field,
English context, placeholders, input hashes and source flags first.

1. Compare declared game builds where available. A newer Blizzard build takes precedence;
   an older Blizzard snapshot cannot replace newer Wago/Questie/EG text. Unknown builds
   do not establish freshness. Git revisions and collection dates are pins, not game builds.
2. Among applicable candidates, prefer real localized native text, then localized community
   text, before English fallback. EG server hotfixes take precedence over matching client
   text at a comparable build. Unresolved competing wording stays in review.
3. Preserve a real existing localized source instead of replacing it with English fallback.
   Imported older core text may yield to a demonstrably newer core source; explicit manual
   corrections remain protected and require review.

Keep source wording and its real provenance. Questie `community` text remains `community`;
never relabel it `original`, rewrite it to agree with another language, or label a copied
English value as a native target translation. Source text may legitimately equal English.
That equality is accepted source wording, but does not prove a non-English translation
for authorizing a new AI job.

Provider ownership is detailed in [the source map](../datasources/SOURCES.md): Blizzard
supplies quest titles/descriptions; Questie supplies summaries and missing titles; EG supplies
NPC/item text, not quests. Wago supplies client-table text and structured dependencies.

## Book identities and existing source text

The [book codex pipeline](../datasources/books/README.md) reconciles Vanilla identities from
VMaNGOS with Forever item identities from Wago and observed object identities from EG Link.
Identity-only runs stay under ignored imports. Explicit `--book-texts` collection adds existing
book wording with source snapshots and field provenance; `resync.py prepare-books` prepares
new book/page records for the same immutable apply/verify boundary. VMaNGOS text retains
community origin and Vanilla-reference scope, never automatic native-Forever authorship.
Existing context-only source licences remain excluded; no AI text is authored, no official-target
AI source fields are accepted, and accepted translations/manual wording are preserved.
Missing/blank/placeholder prose, ambiguous mappings and changed English stay absent or in review.
Book-specific source ordering does not alter the other catalog kinds' priorities or new-AI
eligibility. A book-only corpus is not a general translation resync baseline.

## Target languages

Official Forever locales are `enUS`, `deDE`, `esES`, `esMX`, `frFR`, `koKR`, `ptBR`, `ruRU`,
`zhCN` and `zhTW`. Additional locales are `csCZ`, `daDK`, `hrHR`, `itIT`, `plPL`, `svSE`,
`trTR` and `ukUA`; Italian belongs to this additional group for Forever. Code owns these
sets in [`official_text.py`](../tools/catalogs/official_text.py); configured targets live in
[`catalogs/quests/metadata.json`](../catalogs/quests/metadata.json).

| Situation | Official target languages | Additional target languages |
| --- | --- | --- |
| Applicable localized source exists | Use its exact text and provenance | Use its exact text and provenance |
| No localized source exists | Use available canonical English with its real provenance | Preserve the existing accepted translation |
| New authored text is needed | Never author AI translations | Translate from English only if the eligibility rule below passes |
| Eligibility evidence is missing | Use source text; report unresolved source gaps | Keep existing translations; block new AI jobs |

Earlier AI translations in official languages yield to available source text, including
English fallback. Existing additional-language translations are **not retroactively removed**
because a new-job eligibility check fails. A genuine source update can still supply preferred
localized wording. A changed English meaning is a review issue, not permission to erase text.
When English itself retains AI authorship, copying it must retain that provenance honestly.
Never invent English, labels or objective bindings to fill missing source data.

## Eligibility for new additional-language AI translations

For the same ID and field, require **at least one verified non-English translation in an
official client language** from Blizzard, Wago, Questie or EG Link. Its English context must
match the maintained source. Require nonempty wording, normalized inequality with English,
accepted flags and non-AI source authorship. A catalog claim alone is not independent evidence.
For `books.name` and `bookpages.description` only, the user-approved book policy also accepts
VMaNGOS non-English evidence with a verified asset, the same owned page identity (for bodies),
nonempty translated wording and a matching English SHA-256. It remains Vanilla-reference
evidence with its real community authorship. This exception never applies to quests, items,
spells or other kinds and never permits authoring official-language AI text.

This is deterministic: no model decides whether a source is translated.

[`import_policy.py`](../tools/catalogs/import_policy.py) shares this check between ordinary,
foreign and fallback queues, batch validation and label tooling. The template pilot uses the
same rule with an explicitly supplied verified corpus, rather than a saved queue decision.
Without a corpus it cannot classify missing additional text as an authorized policy absence.
Existing rendered translations are tested regardless of new-job eligibility.

Item-set eligibility uses the owned item-set ID and matching English set name, backed by
hash-verified Wago `ItemSet` locale exports. GlobalStrings import and queues use the
owned tooltip-key maintenance scope. Unused labels are not coverage backfills; production
builds still ship every owned GlobalString for dynamic native tooltip lookup.

## Quest text and captured objectives

Questie English source snapshots with community authorship are valid English context when
no native English snapshot exists. Verified snapshots take precedence over catalog claims;
conflicting English candidates and AI English do not create fallback pairs.

Questie paragraph arrays with explicit empty separators retain their newline structure.
Multiple nonempty entries without paragraph separators remain ambiguous objective lists;
they are not joined or promoted to indexed client objectives.

**Preserve accepted additional-language translations of captured quest objectives**, including
their indices, types and placeholders. Missing upstream localized objective text does not
authorize removing them or retranslating them from scratch. Relationships alone never establish
client indices; progress, completion and reward values remain live client data.

## One update pipeline

Run commands from the repository root. Use a new ignored output directory for every run.
`PREVIOUS` means the corpus of the last successfully applied update, not the last download.
On a fresh checkout with no retained corpus, omit `--previous`: preparation checks the fresh
source fields against the maintained catalogs. No old download or prepared result is required.

1. Refresh the required providers, then build and verify SQLite. The refresh orchestrator
   performs these stages; see [refresh options](../datasources/README.md) for credentials,
   pins and verified reuse of unselected providers. Keep reused runs on disk.
2. Prepare affected IDs/fields against the previous corpus. Review source conflicts,
   new-entity candidates, changed text/provenance and unresolved fields before application.
   New entities remain candidates; they are not silently created by resync.
3. Apply and verify immutable prepared results through `resync.py`. Do not repair imported
   translations with manual catalog edits or agent-authored replacements.
4. Create jobs only for affected remaining gaps. Reuse accepted source wording before any
   eligible AI authoring. This stage does not call a model or translate existing text again.
5. After accepted catalog changes, check formatting, build once and run relevant tests and
   matrices. Install only the validated generated packs and intended runtime files.

After accepted catalog updates, check the
[versioned tooltip regression corpus](../tests/fixtures/tooltip-regressions/README.md).
Its source hashes identify stale selected scenarios. Prepare a new ignored proposal, review
the independent expected-text diff, replay it against the rebuilt database, then explicitly
apply the fixture update. Unrelated catalog changes do not require regenerating the corpus;
raw provider downloads never rewrite expectations or historical client captures.

```sh
uv run --no-project --with lupa==2.8 python datasources/refresh.py \
  --output datasources/imports/NEXT

uv run --no-project --with lupa==2.8 python tools/catalogs/resync.py prepare \
  --database datasources/imports/NEXT/corpus.sqlite \
  --previous datasources/imports/PREVIOUS/corpus.sqlite \
  --output datasources/imports/UPDATE

# Review UPDATE/manifest.json, changes.json, held-source-conflicts.json,
# new-entity-candidates.json and unresolved.json before applying.
python3 tools/catalogs/resync.py apply --directory datasources/imports/UPDATE
python3 tools/catalogs/resync.py verify --directory datasources/imports/UPDATE
uv run --no-project --with lupa==2.8 python tools/catalogs/resync.py queue \
  --directory datasources/imports/UPDATE

python3 tools/catalogs/format-catalogs.py --check
uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
uv run --no-project --with lupa==2.8 python tests/run-tests.py --unit-only
uv run --no-project --with lupa==2.8 python tests/python/test-template-pilot.py
```

The pilot covers selected entries, not the full catalogs. Use the relevant strict matrices
for the affected scope; see [validation](development.md#strict-id-only-coverage).
With `test-template-pilot.py --database datasources/imports/NEXT/corpus.sqlite`, missing
additional targets can be classified using the shared policy and verified source evidence.

Ordinary updates are incremental. Unchanged sources do not trigger a historical reset or
retranslation of all languages. One-time migrations are not maintained commands: any temporary
preparation script stays ignored, uses the normal apply/verify boundary, and is removed after
validation. Keep reports, queues, raw inputs and SQLite under `datasources/imports/`.

## Integrity and prepared decisions

Source/input hashes establish which evidence was used. Result hashes detect changed prepared
files; optimistic catalog hashes detect concurrent edits. Application preflights every file
before its first write. Conflicting sources stay in review, and unresolved source fields block
application. Verification checks the applied bytes against the prepared results.

A field found only upstream, absent from both maintained English and the official target,
does not require a fallback or block application. Existing official AI text without an
owned English source still requires review; preparation never invents its replacement.

Internal import decisions have no policy-version counter or compatibility/migration layer.
Prepare a new run with the current tools before applying it; after changing import rules,
discard the old preparation and prepare again. Reports and proposals under ignored imports
are disposable working files, not supported inputs to replay across tool changes.
Database-format and public API versions are separate and unchanged. The pilot uses the
shared rule directly and does not depend on a versioned queue.

## Cache lifecycle

Do not clear every cache before every update. Each refresh uses a new run directory and
verifies source hashes; explicit reuse retains pinned inputs and their original paths.
Blizzard conditional requests can reuse unchanged responses. Missing or changed input files
must fail validation or be fetched again, never silently accepted.
Blizzard GET transport timeouts/disconnects have at most three attempts, all paced by the
same request limiter. HTTP refusals and validation errors still stop the collection.

Retain the last successfully applied corpus and any raw runs it references for normal
incremental comparisons. Do not delete a run that an active preparation or reused corpus
still depends on. Old proposals, reports and abandoned runs can be removed once no longer
needed. A deliberate fresh-checkout cleanup may remove all ignored imports; the next update
then fetches sources and prepares without `--previous`. Keep local credentials/configuration
and all tracked catalogs, tools, fixtures and generated shipping addons.

## Regression coverage

| Contract | Tests |
| --- | --- |
| Builds, native/community/fallback priority, exact provenance, context and placeholders | `tests/python/test-fill-official-text.py`, `test-official-text-policy.py` |
| All four providers, official AI prohibition, new-job proof, accepted translations and captured objectives | `tests/python/test-import-policy.py` |
| First import without history, incremental scope, newer providers, manual fixes, repaired English pairs and preflight conflicts | `tests/python/test-import-policy.py` |
| Questie English pairing, paragraph preservation and ambiguous summaries | `tests/python/test-translation-corpus.py` |
| Pilot classification through verified shared policy, independently checked rendering | `tests/python/test-template-pilot-policy.py`, `test-template-pilot-harness.py` |
| Canonical JSON without text/value changes | `tests/python/test-catalog-format.py`, CI `format-catalogs.py --check` |
