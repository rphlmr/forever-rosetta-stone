# VMaNGOS book identities

- Upstream: https://github.com/vmangos/core/releases/tag/db_latest
- Provider: VMaNGOS contributors; repository https://github.com/vmangos/core.
- Scope: Vanilla 1.12 identities and page relationships; explicit `--book-texts` reads existing
  page prose/locales from the retained SQLite. Text retains community origin and Vanilla-reference
  scope. No new translations are generated. Upstream GPL notice is retained in addon notices.
- Snapshot: the official SQLite distribution, pinned by asset ID, name, SHA-256 and content patch 10.
- Attribution: retain VMaNGOS credit. Core declares GPL-2.0; underlying game content belongs to
  Blizzard. This stage retains reference evidence under ignored imports and does not ship database
  text or change its licensing. A future text import must review the distribution's data terms.

Select the latest item/object template row with patch <= 10 before filtering readable entries.
Item `page_text`, object type 9 `data0`, and object type 10 `data7` identify the first page.
`page_text.entry` and `next_page` define the page chain. Item, object and page IDs are separate
namespaces. Missing links, cycles and shared pages remain explicit diagnostics.

VMaNGOS is a Vanilla reference, not evidence that an owner or page is available or unchanged in
Forever. Wago's Forever item identity and EG Link's observed object identity override their
VMaNGOS counterparts; disagreements retain both observations. VMaNGOS-only owners remain
unconfirmed candidates. A first-page match does not verify the rest of a Forever page chain.

A refresh never edits catalogs, translates text, installs addons or adds runtime exceptions.
Replay uses the saved GitHub asset ID and rejects changed bytes. If upstream deletes an asset,
network replay fails; the retained verified inputs support an exact offline rebuild.
