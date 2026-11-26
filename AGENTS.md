# Forever Rosetta Stone

The authoritative import/update/resync policy and workflow is
[`docs/import-resync.md`](docs/import-resync.md). Read it before source-driven changes.
Use the newest verified applicable game build for each field. One verified source
in an official client language, including English, can support provisional AI
translations for missing targets. Prefer applicable sourced wording and preserve
captured quest objectives and accepted translations when new-job evidence is absent.

See [`tools/README.md`](tools/README.md) for the retained Python tools and their actual
callers. Generated database addons live in `ForeverRosettaStone_Data/<locale>/` and shared
`ForeverRosettaStone_Data/Rules/` in the repository; release ZIPs and installed addons use
`ForeverRosettaStone_Data_<locale>/` and `ForeverRosettaStone_Rules/` beside `ForeverRosettaStone/`. Tests are grouped under
`tests/python/`, `tests/lua/` and `tests/fixtures/`; run `tests/run-tests.py --unit-only` when
translation matrices must not run.

Never hardcode runtime behavior to specific entity IDs or add per-entity exceptions.
Use generic, data-driven paths based on owned catalog records and structured client data.
Do not add spell-ID allowlists, spell-specific point counts, or special-case fixes.
When required data or translations are unavailable, preserve native text instead of guessing.

All source text that the addon may translate must have a readable, versioned owner in the
catalogs. Download caches and encoded/generated runtime data are never the only copy of
translatable text. GlobalStrings live in `catalogs/globalstrings/<GlobalStrings.ID>.json`:
the source `key`, localized `name` text and inline field provenance stay together. Missing
translations remain absent. The normal build compiles them into FRS language database packs;
never maintain parallel Lua translation files or overwrite manual text during a refresh.

Before adding catalog entries, fixing translations, or checking upstream updates, read
[`catalogs/AGENTS.md`](catalogs/AGENTS.md). Start with its everyday editing workflow; use the
upstream update workflow when checking Wago or QuestieDB. Scope work to the requested IDs and
fields, reuse translations before authoring new ones, and build once after catalog edits are complete.
Catalogs use one file per entity with minimal inline field metadata; credits live in notices.
For fresh source evidence, follow [`datasources/README.md`](datasources/README.md) and
[`datasources/SOURCES.md`](datasources/SOURCES.md) for source priorities and refresh commands.
Run `datasources/refresh.py` to fetch into ignored `datasources/imports/`, then build and verify SQLite before
source-driven catalog edits. Never create or use the legacy `references/` workspace. All downloaded inputs, captures, queues,
reports and SQLite files belong under ignored `datasources/imports/`.
Quest titles/descriptions come from Blizzard; Questie supplies summaries and missing titles.
EG Link is used for NPC/item text only. A fresh checkout needs
no reference cache: Python 3 handles reference tools, and `uv` supplies the pinned Lua test
dependency when building. Fetch sources only when the requested work needs them. Do not
recreate ignored snapshots, scan the full catalogs, or install the addon just to get started.
The manual quest collector source is versioned under `tools/quest-scan/`; generated queues
and captures stay ignored under `datasources/imports/quest-scan/`. See the source guide before using it.
Never include developer tools in shipping addon folders, TOCs, or release archives;
`tests/python/test-local-scan-boundary.py` checks the collector boundary.
For authorized parallel updates, use
`tools/catalogs/catalog-batch.py` to assign disjoint snapshots and validate agent submissions before
applying patches. Agents edit their assigned results, and the coordinator owns catalog writes
and the final build.
