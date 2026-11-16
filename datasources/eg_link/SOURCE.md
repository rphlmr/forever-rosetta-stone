# Eg Link source

- Provider and credit: Efficient Games; JIVESCORP/EG Link.
- Upstream: https://github.com/JIVESCORP/eg-link-output-wowf
- Terms: CC BY 4.0 compilation credit; underlying game text remains Blizzard content.
- Scope: Native NPC/item text and book-object identities. Quest fields are excluded. Explicit book-text collection indexes only `texts.<locale>.books`;
  other sections of the raw aggregated text snapshots are retained but never imported.
- Book codex: `object_details.enUS` across published `wowf` builds, retaining the newest observation
  per object at one pinned revision. Text-type and readable goober objects supply first-page links.
  This identity evidence is stored separately from NPC/item translation records.

`loader.py` owns collection. Refreshes retain the actual revision/build/namespace in
`pins.json`, with raw evidence under ignored `datasources/imports/`. Fetching never
changes catalogs or transfers third-party content into the project MIT license.
