# Book identity codex

The identity stage reconciles owner/page identities. The explicit text stage reuses existing
source wording and prepares maintained catalogs; it generates no translations and adds no UI.
All source snapshots, SQLite files and generated JSON stay under ignored `datasources/imports/`.

## Build

```sh
# Defaults to vmangos, wago and eg-link; no Blizzard credentials or Lua dependency needed.
python3 datasources/refresh.py --book-codex-only \
  --output datasources/imports/BOOK_CODEX

# Replay the selected release asset, Wago build and EG revision into a new run.
python3 datasources/refresh.py --book-codex-only \
  --pins datasources/imports/BOOK_CODEX/pins.json \
  --output datasources/imports/BOOK_CODEX_REPLAY
```

The identity-only path fetches Wago `ItemSparse` in English and EG object caches, skips
translation catalogs and ingestion of translation records, and needs only Python 3.
The VMaNGOS raw distribution contains bodies/locales; these remain ignored source evidence,
not imported text. The projection reads only owner identities and page links.

A successful run publishes `sources.json`, `pins.json`, verified `corpus.sqlite`,
`book-codex.json` and `complete.json`. Do not use an unfinished run as a resync baseline.
Normal refreshes skip books and letters. EG Link keeps its NPC/item scope in a normal refresh.

## Identity and reconciliation

- Item IDs, object IDs and page IDs are separate namespaces. A book entry is grouped by its
  selected **first-page ID**, with every item/object owner and title retained separately.
  This grouping is not a claim that every entry is reachable or a unique literary work.
- VMaNGOS selects the latest template row at patch <= 10 **before** filtering readable
  entries. Items use `page_text`; type-9 objects use `data0`; type-10 objects use `data7`.
- Wago's Forever `ItemSparse.ID`, `Display_lang`, `PageID` override the Vanilla item identity.
  Zero-page values withdraw a previously readable item instead of resurrecting the old entry.
- EG's sparse `object_details.enUS` exports are retained across published `wowf` builds at
  one pinned revision. The newest observation per object wins, even if it is no longer a
  readable object. Absence from a later sparse export does not mean removal.
- `titleConflict` and `firstPageConflict` preserve both observations. Changes never disappear
  behind an automatically chosen value. Same-build contradictory EG observations fail.
- Owner status is `foreverClient` (Wago), `foreverObserved` (EG), or `vanillaCandidate`
  (VMaNGOS only). These statuses concern owner identity, not the page prose or reachability.
- Page links come from VMaNGOS. `completeVanillaReference` means the chain terminates in that
  reference. `foreverPageSequenceVerified` remains false. Missing pages, cycles and pages
  shared by different first-page entries are explicit issues; partial chains are retained.
- A per-owner newer observation with no readable first page appears under `excludedOwners`.

The SQLite `book_codex` table has one JSON document per first-page ID; `book_codex_metadata`
contains scope, counts and exclusions. No book text enters the translation `records` table.
Every source file read by the codex participates in the corpus input-hash inventory.
VMaNGOS snapshots retain GitHub asset metadata, archive digest, raw SQLite, projection and
attribution. Network replay fails if an upstream asset disappears or its bytes change.

## Offline rebuild and export

```sh
python3 datasources/corpus/translation_corpus.py build \
  --config datasources/imports/BOOK_CODEX/sources.json \
  --output datasources/imports/BOOK_CODEX/rebuilt.sqlite
python3 datasources/corpus/translation_corpus.py verify \
  --database datasources/imports/BOOK_CODEX/rebuilt.sqlite
python3 -m datasources.books.codex \
  --database datasources/imports/BOOK_CODEX/rebuilt.sqlite \
  --output datasources/imports/BOOK_CODEX/rebuilt-codex.json
```

The saved `scope: book-identities` also controls offline rebuilds: no catalog scan or
translation import occurs. JSON export verifies all retained source hashes first and refuses
an existing output path. It does not fetch sources or apply catalog changes.

## Validation

```sh
python3 tests/python/test-book-codex.py
```

Fixtures exercise patch selection, typed namespaces, missing/shared/cyclic chains, changed
Forever identities, non-readable overrides, checksum/path rejection, asset replay, verified
SQLite export, deterministic offline rebuild and the absence of body/catalog ingestion.


## Existing source texts and translations

```sh
python3 datasources/refresh.py --book-texts --output datasources/imports/BOOK_TEXTS
python3 tools/catalogs/resync.py prepare-books \
  --database datasources/imports/BOOK_TEXTS/corpus.sqlite \
  --output datasources/imports/BOOK_TEXTS_PREPARED
# Inspect manifest.json, changes.json, held-source-conflicts.json and source-issues.json.
python3 tools/catalogs/resync.py apply --directory datasources/imports/BOOK_TEXTS_PREPARED
python3 tools/catalogs/resync.py verify --directory datasources/imports/BOOK_TEXTS_PREPARED
python3 tools/catalogs/resync.py queue --directory datasources/imports/BOOK_TEXTS_PREPARED
```

`--book-texts` selects VMaNGOS, Wago ItemSparse locales, EG book captures, the Wowhead
Forever snapshots mirrored in `salty-max/wow-data`, CMaNGOS Classic, AzerothCore and the
existing book community providers. Use `--sources book-archives --reuse <completed book run>`
to refresh the three archives while retaining the other inputs. Each archive is pinned and hashed.
No unrelated maintained catalogs are scanned. The corpus contains only `books.name` and
`bookpages.description` source records, together with the codex and explicit source issues.

- VMaNGOS bodies and localized owner names retain `community` authorship and Vanilla-reference
  scope. Missing Text placeholders and rendered-empty HTML pages never become prose.
- Wago contributes localized names only for the selected item owner, with matching page and
  English title. An unambiguous EG or Wowhead first-page observation can use the first page ID
  provided by an identified Forever owner. Later observations need an existing page ID and
  matching English. The first-page link remains incomplete when the subsequent IDs are absent.
- CMaNGOS and AzerothCore backfill identified reference pages with the same next-page link.
  AzerothCore localizations also require matching English. Spanish copies shared with `esES`
  are insufficient to establish `esMX`. Preserve archive provenance and review terms before
  publishing source wording.
- ClassicUA page arrays require a unique title and matching complete chain; Czech Forever,
  PolishForever and ForeverTR require a unique English fingerprint in the owned page scope.
  Original/community/AI source authorship remains explicit. No new AI translation is generated.
- Gender-variant source tables and unsupported markup stay unresolved. Existing unresolved
  translation-data terms for WoWLang, WoWForeverIT/QuestIT and QuestTranslator TR remain
  context-only, even when their archives contain relevant books.
- Sources with nonmatching English context, same-priority conflicting wording or unsafe flags
  are held. Upstream AI text remains excluded from official-language source imports.
- Prepared writes preserve manual and accepted non-AI text; differences appear in the held report.
  Matching non-AI source text replaces existing AI fields. Source and prepared-result hashes and
  optimistic destination hashes are checked before any write. New files use a null before hash.
- Before authoring missing titles, preparation also reuses maintained item names for the
  selected item owner and exactly matching English title. It copies wording and field
  provenance unchanged, excludes official-language AI text, and hashes each scoped item
  input in the immutable manifest. Reuse is not independent evidence for new AI jobs.

Maintained `catalogs/books/<firstPageID>.json` owns titles, owners, source owner names and page
order. `catalogs/bookpages/<pageID>.json` owns bodies in `locales[locale].description`, next-page
links and book memberships. Every localized field has inline field provenance, source text/input
hashes, actual source locale and the retained provider version. Native aliases in `ownerNames`
retain their exact source observation. Page links remain Vanilla references, not verified Forever
sequences. Bodies with no usable English source are not created.

The regular database build compiles book names, bodies and structural rules into the existing
language/rules packs. UI adapters and live reading controls remain a separate stage. Standard
resync source priorities for quests/items/spells and AI eligibility are not changed by this path.


After applying verified source additions, the book queue uses the verified English body or
title to prepare missing official and community targets with no applicable source translation.
Run the translation pass separately with GPT-6.1 Tera at medium effort. Assign one catalog entity
(a book title or a page) and all its missing target languages per mission. Include the other
known pages as context for terminology and tone. AI metadata records origin, source and sourceLocale.
