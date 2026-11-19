# Refresh catalog sources

For source priority, target-language decisions and applying an update, use the
[import/resync reference](../docs/import-resync.md). This guide owns source collection options.

Run from the repository root. Python 3 handles downloads and SQLite; the existing pinned
`lupa==2.8` dependency runs Questie's composed-data exporter. Nothing here edits catalogs,
builds or installs the addon, or runs the translation matrix.

## Select sources

```sh
# Refresh the four core providers and active GitHub/CurseForge community sources.
uv run --no-project --with lupa==2.8 python datasources/refresh.py

# Refresh only Wago. No Blizzard credentials or requests are needed.
python3 datasources/refresh.py --sources wago

# Fetch Wago and EG Link, retaining the other providers from a completed run.
python3 datasources/refresh.py --sources wago eg-link --reuse datasources/imports/PREVIOUS_RUN
```

`--sources` accepts the four core providers (`wago`, `questie`, `blizzard`, `eg-link`)
plus the GitHub community providers listed below. Only selected providers are fetched.
Without `--reuse`, unselected providers are omitted from the new corpus. Existing catalog
translations, including community languages, are still indexed; they are not deleted.
With `--reuse`, unselected raw sources keep their original paths and pins. Their hashes
are checked against the previous corpus before reuse. Every refresh builds a new SQLite
corpus and records `fetchedSources` and `reusedSources` in `complete.json`. Keep reused runs
on disk. `--pins` controls selected providers only; it does not fetch unselected ones.

When Blizzard and Questie are selected together, Questie completes first to supply extra
quest IDs. A Blizzard-only run uses its own discovery plus reused Questie IDs, if available;
it does not silently fetch Questie. Only selected Blizzard runs require credentials.

## Books and letters

Use `python3 datasources/refresh.py --book-codex-only --output datasources/imports/BOOK_CODEX`
for the VMaNGOS + Wago + EG reconciled codex. This targeted path needs only Python 3, fetches
English item/object identities and page links, and skips translation catalogs and body text.
See the [codex workflow](books/README.md) for pins, statuses, limitations, existing-source text collection (`--book-texts`) and offline rebuilds.
VMaNGOS, book captures and the book archives are scoped to explicit book runs.

## Provider ownership and credit

Each provider folder keeps `loader.py` beside `SOURCE.md`, which records its scope,
upstream, credit, terms and attribution. Wago's manual commands are documented in
[wago/README.md](wago/README.md): `python3 -m datasources.wago download|check|audit|diff`.

Active community sources remain refreshable:

| Provider | Languages | Upstream |
| --- | --- | --- |
| `classic-ua` | Ukrainian | [ClassicUA](https://github.com/greenya/ClassicUA) |
| `czech-forever` | Czech | [Czech Forever](https://www.curseforge.com/wow/addons/czechforever) |
| `forever-translated-polish` | Polish | [Forever Translated](https://www.curseforge.com/wow/addons/forever-translated) |
| `varlden-av-krigskraft` | Swedish | [Världen av Krigskraft](https://www.curseforge.com/wow/addons/varlden-av-krigskraft) |
| `forever-tr` | Turkish | [ForeverTR](https://www.curseforge.com/wow/addons/forevertr) |
| `polish-forever` | Polish | [PolishForever](https://github.com/JSlomian/PolishForever) |
| `wowita-quests` | Italian | [WoWita-quests](https://github.com/deemonder/WoWita-quests) |
| `wow-forever-it` | Italian | [WoWForeverIT / QuestIT](https://github.com/polletto/WoWForeverIT) |
| `wow-forver-italiano` | Italian | [WOW Forver - Italiano](https://github.com/z4mbo/WOW-Forver-Italiano) |
| `wow-lang` | Polish, Turkish, Ukrainian | [WoWLang](https://github.com/DiNaSoR/WoWLang) |
| `questtranslator-tr` | Turkish | [QuestTranslator Vanilla Turkish](https://github.com/devteabct78/questtranslator-vanilla-turkish) |

```sh
python3 datasources/refresh.py --sources classic-ua czech-forever polish-forever \
  wowita-quests wow-forever-it wow-forver-italiano wow-lang questtranslator-tr \
  --reuse datasources/imports/PREVIOUS_COMPLETED_RUN
```

For a targeted Wago dependency investigation, `--wago-tables` and `--wago-locales`
restrict the refresh while retaining the fetch, SQLite build and verification boundary.
`SpellClassOptions` supplies family masks when checking duration-changing talent dependencies.

Each adapter retains raw text, original licence/credit files, commit/release pins and hashes.
Exact upstream notices are also retained under each loader's `licenses/` folder; `SOURCE.md`
distinguishes translation-data terms from code licences and records unresolved terms.
Lua data is parsed without executing upstream code. English-text hash keys are not entity IDs.
Classic/server variants, unresolved fingerprints, unsupported placeholders, conflicts and
missing/contradictory licences are flagged as context for review, not automatic catalog fills.
Original/community/AI origins are preserved; community does not imply human-only authorship.

WoWForeverIT includes translations from QuestIT, maintained with its Discord community and
#italyforazeroth (https://italy-for-azeroth.vercel.app/). Its translation terms are separate from
MIT engine code and are retained verbatim. WoWita and the Turkish Vanilla fork have no located
translation-data licence. WoWLang's README/LICENSE conflict remains explicit. These unresolved
sources can supply labelled local context but cannot authorize copying into shipped catalogs.

Czech Forever, Forever Translated Polish, Världen av Krigskraft and ForeverTR use the public
CurseForge website file endpoint (`www.curseforge.com/api/v1/mods/<projectID>/files`).
Every ordinary refresh reads all pages and selects the newest approved, public release for
WoW Forever matching the project's text archive, ordered by publication date and file ID.
Voice-only files, beta/alpha release types, other flavors and early-access files are excluded.
The release type is CurseForge's classification, independent of a version's name.
Downloads come directly from `edge.forgecdn.net`. No Core API key or publication token is used.
The adapter records file ID, filename, release date, discovery/download URLs, length and SHA-256.
`--pins` deliberately replays a saved version instead of checking latest. A discovery failure
stops refresh; it never silently falls back to an older seed. This public website endpoint is
not a guaranteed API contract: if it changes, the adapter must be updated.

Only supported text is extracted; bundled audio is retained only inside the raw archive.
Polish source fingerprints remain review context; Turkish hash-keyed spell tables are excluded.
Existing accepted text, provenance and credits remain protected by the normal import policy.

No usable Croatian content dataset has been established. The Danish lead contains addon UI
translations rather than quest/item/spell content. These gaps do not prove no projects exist.

## Blizzard credentials

Create a Battle.net developer application at <https://develop.battle.net/access/clients>.
Copy `.env.example` to `.env`, then set these two values locally:

```dotenv
BLIZZARD_CLIENT_ID=your-client-id
BLIZZARD_CLIENT_SECRET=your-client-secret
```

`.env` is ignored by Git. Do not paste secrets into chat or commit them. The loader reads
plain `KEY=value` or quoted values; it does not execute shell substitutions. Environment
variables override the file. Use `--env-file /absolute/path/to/file` for another location.
Tokens stay in memory and are never written into imported responses or manifests.

## Fetch everything and build SQLite

```sh
uv run --no-project --with lupa==2.8 python datasources/refresh.py
```

Each run creates a new ignored `datasources/imports/<UTC timestamp>/` directory. Existing runs are
never overwritten. `--output datasources/imports/my-refresh` selects another new run directory.
For runs selecting Blizzard, missing credentials stop the run before any downloads. The refresh has a one-hour limit;
individual requests and subprocesses also have timeouts. Access/rate-limit failures stop
the refresh without retries. Blizzard GET transport timeouts/disconnects have at most three
attempts under the same shared limiter. A failed fetch never starts the SQLite build.

Community sources resolve first, so a missing release stops before core collection starts.
Unavailable requested providers are reported as errors; selecting a narrower source list is
explicit and never deletes accepted translations. Wago and EG fetch in parallel with the Questie → Blizzard chain. Blizzard waits for
Questie's export so it can also request Questie IDs omitted by API discovery.
SQLite starts only after all three fetch branches finish successfully:

1. **Questie:** discover HEAD, fetch that exact SHA, export composed Forever data including
   authored corrections, and retain base/trace locale tables.
2. **Blizzard:** discover `static-forever-eu` through the response's self link and pin the
   resolved namespace for the collection. Walk the quest index, areas, categories and types;
   also request Questie IDs that discovery omitted. Omit `locale` to save all language slots
   in each unfiltered response. Record individual missing quests as 404s; authentication,
   rate-limit, namespace changes and other fetch failures prevent a complete collection.
   Quest downloads use 32 workers with shared pacing below 100 requests/second and a
   35,000-request collection budget per rolling hour. `Last-Modified` and `ETag` validators
   are retained per resource. With `--reuse`, selected Blizzard responses are revalidated
   using conditional requests to their exact URLs; a 304 reuses only hash-checked bytes.
   An unchanged index or namespace never skips checks of individual quests. Older snapshots
   without validators need one full fetch before conditional reuse becomes available.
3. **Wago:** discover the latest published `wowf` build and fetch all catalog client tables
   and their supported client locales on that one build. This includes item, spell,
   area/map, faction, class, creature-type and talent dependencies.
4. **EG Link:** discover HEAD and pin that SHA; fetch the newest available English NPC
   and valid-item cache datasets. Dedicated book runs fetch object-cache observations and book prose.
   **No EG quest data is fetched or imported.**
5. **VMaNGOS:** retain the published SQLite asset with its ID and verified digest, select Vanilla
   patch 10 identities, and project only owner titles/first pages and page links. No book bodies
   or translations are ingested. See [source scope](vmangos/SOURCE.md).
6. Write `sources.json` and `pins.json`, build `corpus.sqlite`, verify every indexed input's
   SHA-256, then write `complete.json`. Only a completed run is ready for catalog work.

The default refresh discovers current source versions. `pins.json` records the actual
Questie/EG revisions, Wago build and Blizzard namespace, whose versions are independent.
In particular, Blizzard's API namespace version is not the live client build number.

## Source rules

| Catalog text | Provider |
| --- | --- |
| Quest titles | Blizzard; Questie when a title is missing or unusable for that locale |
| Quest full descriptions | Blizzard |
| Quest summaries | Questie |
| NPC names | EG Link when covered, then Questie |
| Item names/flavor text | Wago and applicable EG server cache text |
| Spells, talents, areas, maps, factions, creature types, classes | Wago client tables |

Blizzard's quest web endpoint does not supply summaries. Italian is not an official
Forever language: Blizzard's Italian quest slots are excluded. Other English fallback
and cross-language collisions remain flagged for inspection, rather than accepted as
native translations. GitHub and CurseForge community evidence can be refreshed using the providers above.

Trusted Questie summaries may contain literal required amounts. Do not replace valid
translations with AI text solely to introduce objective placeholders. Live player progress
is separate. Existing runtime template support remains available.

## Reproduce and inspect a run

Use the paths printed by the refresh, substituting your actual run directory:

```sh
# Rebuild from the exact saved files without any network requests.
uv run --no-project --with lupa==2.8 python datasources/corpus/translation_corpus.py build \
  --config datasources/imports/RUN/sources.json --output datasources/imports/RUN/rebuilt.sqlite
python3 datasources/corpus/translation_corpus.py verify --database datasources/imports/RUN/rebuilt.sqlite

# Fetch the same selected upstream versions into a new run.
uv run --no-project --with lupa==2.8 python datasources/refresh.py \
  --pins datasources/imports/RUN/pins.json --output datasources/imports/replay
```

A network replay pins versions, but Blizzard can update responses within the same namespace.
The retained raw files plus hashes provide exact offline reproduction. Keep the run directory
for reproducibility; it is intentionally not versioned. The tracked
`datasources/corpus/sources.json` describes the layout; the orchestrator writes concrete
paths and revision pins into each run's `sources.json`. Use that generated file for builds.

`datasources/imports/` owns all source snapshots, generated work and SQLite files.
The legacy `references/` directory is removed and must not be recreated.

For catalog patch preparation and translation work, follow
[`datasources/corpus/README.md`](../datasources/corpus/README.md) and
[`catalogs/AGENTS.md`](../catalogs/AGENTS.md). Fetch and verify SQLite first, then prepare
reviewable catalog changes. A source refresh itself changes no catalog text.
