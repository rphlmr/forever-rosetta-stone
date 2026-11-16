# Datasource status

The maintained `catalogs/` JSON files own accepted translations and relationships.
A SQLite corpus indexes collected source evidence for lookup and reviewed catalog changes;
building it does not replace catalogs or prove translation coverage.

## Current inputs

- **Blizzard:** Forever quest titles and full descriptions, with the actual API namespace retained.
- **QuestieDB:** composed Forever quest summaries, missing titles, names and relationships.
- **Wago:** build-pinned client tables for item/spell text and structured dependencies, areas,
  maps, factions, classes and creature types.
- **EG Link:** NPC and item text only. Quest data is excluded.
- **GitHub community sources:** Ukrainian, Polish, Italian and Turkish datasets remain
  active; see the datasource registry for raw snapshots, origins and licence restrictions.
- **CurseForge community sources:** Czech Forever, Forever Translated Polish, Världen av
  Krigskraft and ForeverTR discover and fetch their latest approved public Forever releases.
- **VMaNGOS:** Vanilla book identities, page chains and explicitly requested source text;
  reference scope is retained separately from verified Forever evidence.

Use [`datasources/README.md`](../datasources/README.md) for selective refreshes and reuse.
Use the selected run's `sources.json` to build SQLite from already collected inputs.
Raw inputs, corpus files, generated patches, reports and optional collector output belong
under ignored `datasources/imports/`. The legacy workspace must not be recreated.

## Catalog synchronization

Verify source hashes before preparing updates. Preserve manual fixes, valid translations,
field meanings, locale identity and client-index mappings. Review conflicting or flagged
source candidates. Missing source text stays missing; English fallback is not a translation.
Apply only verified source-backed changes, then build the addon database and validate it.

The live client owns quest progress, rewards and current tooltip numbers. Static relationship
positions do not establish objective client indices. Optional local collectors are separate
manual development tools; a catalog sync does not start an in-game scan.
