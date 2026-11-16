# Wago source

- Provider and credit: Wago.tools; game content by Blizzard Entertainment.
- Upstream: https://wago.tools/
- Terms: Client text remains Blizzard content; access through Wago does not relicense it.
- Scope: Client tables for spells, items, talents, locations, factions, classes and creature types.

`loader.py` owns collection. Refreshes retain the actual revision/build/namespace in
`pins.json`, with raw evidence under ignored `datasources/imports/`. Fetching never
changes catalogs or transfers third-party content into the project MIT license.
