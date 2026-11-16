# Blizzard source

- Provider and credit: Blizzard Entertainment.
- Upstream: https://develop.battle.net/
- Terms: Blizzard Developer API Terms of Use; Blizzard retains game-content rights.
- Scope: Quest titles and full descriptions from the Forever API.

`loader.py` owns collection. Refreshes retain the actual revision/build/namespace in
`pins.json`, with raw evidence under ignored `datasources/imports/`. Fetching never
changes catalogs or transfers third-party content into the project MIT license.

## Project attribution and non-affiliation notice

Use this project-authored wording in the public README and release descriptions:

> Forever Rosetta Stone is a free, noncommercial community addon. Game data is provided
> by Blizzard Entertainment through the Battle.net API and client-data sources.
> World of Warcraft and related trademarks and game content belong to Blizzard
> Entertainment, Inc. and their respective owners. This project is independently
> developed and is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment.

This is our project notice, not a quotation of mandatory API wording or a claim that
noncommercial use grants permission. The project's MIT license covers its own code;
it does not relicense Blizzard text, artwork, or trademarks. Preserve upstream notices.

Applicable reference: [Blizzard Developer API Terms of Use](https://www.blizzard.com/en-us/legal/a2989b50-5f16-43b1-abec-2ae17cc09dd6/blizzard-developer-api-terms-of-use).
The full terms page could not be retrieved during this change (HTTP 403); this wording
has not been verified as satisfying every API requirement. Recheck the terms before
claiming compliance or copying mandatory wording.
