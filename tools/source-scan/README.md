# Local native source collection

For a small spell/item/active-aura calibration campaign, see
[`rosetta-tooltip-check/README.md`](rosetta-tooltip-check/README.md). That separate local
collector uses `/frsverify`, records full hover payloads and appends labelled gear profiles.
It is not part of the source queue below and is never shipped in FRS.

This development addon collects observations from the game client into local SavedVariables.
It is separate from the shipping addon. Preparing a queue does not install the probe, start WoW,
or start collection. Do not install or run it until the user explicitly requests that action.
Offline lifecycle, queue preparation, and release-boundary checks pass. Loading and collection
in the actual game client remain unverified.

## Scope and evidence

The full queue targets quests, items, and spells from the union of known IDs in the maintained
catalogs and supplied reference inputs. It is not an API enumeration of every game entity:
unknown IDs can remain outside the queue. Record the reference inputs with each run, and report
failed or unavailable requests separately from missing IDs. Talent jobs use backing spell IDs;
area and UI map IDs remain separate namespaces. Known keyed client globals are also collected.

Prepare a new queue from the repository root with the available
client snapshot and quest ID inventory:

```sh
python3 tools/source-scan/prepare.py --all \
  --client-snapshot datasources/imports/wago/1.60.1.70888 \
  --quest-ids datasources/imports/datasource-consolidation-20261111/id-universe.json \
  --output datasources/imports/source-scan/new-run
```

The quest inventory supplies `sources.questieForever`, `sources.egQuests70862`, and
`sources.egHistoricalQuestsAndObjectives`, each with a
revision and IDs. The preparer verifies the Wago manifest checksums. It writes `queue.json` with
inventory provenance and counts, `queue.lua`, and a separate addon copy. It refuses to overwrite
an existing output directory. The example inputs are local reference artifacts, not a guarantee
that they are present in a fresh checkout or exhaustive.

The queue has eleven game-locale profiles: `deDE`, `enUS`, `esES`, `esMX`, `frFR`,
`itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, and `zhTW`. Run each profile in its corresponding
client locale. Forever Rosetta Stone's community-only target languages are not game profiles and
cannot be collected by switching to them. An English fallback observed in a client locale remains
an observation of that fallback, not evidence of a native translation.

API descriptions and tooltip lines are rendered observations and can depend on character or
other context. Keep them separate from raw Wago templates, including their tokens and source
build. A rendered observation does not replace a raw template. NPC names require an actual unit
observation; this probe does not collect NPCs or auras. Quest API observations include titles and
objective rows, not quest summaries or descriptions. The preserved quest cache is raw evidence;
the repository does not currently provide a portable prose decoder.

Explicit `--factions 92 93` jobs synchronously observe both
`C_Reputation.GetFactionDataByID` and `GetFactionInfoByID` when available; they issue no
faction server request and do not imply the client has populated either record. The probe
preserves returned field and positional value availability, restrictions, and API errors;
it does not infer standings. Player level, client build and locale accompany the observations.
`--global-keys` accepts only explicitly named `FACTION_STANDING_LABEL1` through
`FACTION_STANDING_LABEL8`. These keys and faction IDs contribute to the queue hash.
`--unowned-spells` accepts explicit positive spell IDs without catalog records, such as
known talent backing IDs; it does not establish that an ID exists or is displayable.
These options are excluded from `--all` and do not install or start a probe.

## Run and preserve results

For a small explicit spell calibration queue, optionally include items in the same run:

```sh
python3 tools/source-scan/prepare.py \
  --items 191267 1002 221348 258734 264501 10010 212160 10011 \
  --spells 10 1014 10250 13033 1454 6574 7799 7800 7801 --spell-context \
  --output datasources/imports/source-scan/combined-calibration-conflicts-20261113
```

Choose a new output path if that directory already exists. `--spell-context` is restricted
to explicit spell and optional item selections; it cannot be combined with `--all` or globals.
Only spell jobs receive snapshots. The probe records per-return availability, player level,
spirit, melee and ranged attack power returns, damage bonuses by school, healing bonus, and
known-spell conditions found in each selected record's English templates and variables. It
does not follow conditions in linked records or record aura conditions. Player snapshots do not
establish an aura's caster identity or its stats, and aura points are not effect-index mappings.
These observations are calibration evidence, not proof of client scaling formulas.

If explicitly instructed to install the prepared probe, first preserve any existing probe addon
and its SavedVariables. From the repository root, this guarded command installs the example
queue only if no probe directory already exists:

```sh
test ! -e '/Applications/World of Warcraft/_forever_/Interface/AddOns/rosetta-source-probe' && \
  cp -R datasources/imports/source-scan/combined-calibration-conflicts-20261113 \
    '/Applications/World of Warcraft/_forever_/Interface/AddOns/rosetta-source-probe'
```

After loading the addon in the appropriate client locale, use these in-game commands:

```text
/frssource status
/frssource start
/frssource pause
/frssource report
```

`status` and `report` are read-only. `start` explicitly begins or resumes the matching session;
`pause` stops new requests after any in-flight request settles. To resume after a reload, issue
`/frssource start` again. Different queue hashes, builds, or locales use separate sessions.
Quit the client fully before copying the account's `WTF/Account/<account>/SavedVariables/rosetta-source-probe.lua`
and, when relevant, the locale's quest cache to a new backup directory. Preserve the previous
SavedVariables and prepared queue before replacing an installed probe or changing runs; do not
overwrite earlier captures. The SavedVariables filename uses the addon's folder name.

Install the prepared `rosetta-source-probe` as a separate local addon only when requested. Loading
it does not start a scan. `/frssource status` reports progress, `/frssource start` starts or resumes,
and `/frssource pause` stops new requests after the current request settles. `/frssource report`
shows the status report. Collection pauses after two hours; explicitly start again to resume.
Reloading does not start it automatically. A saved session is associated with its queue hash,
client build, and locale; preserve those identities rather than combining observations across them.
The probe attempts one request at a time, waits at least 0.2 seconds between requests, times out
after 10 seconds, and delays requests during combat. Completion means all jobs were attempted,
not that every request returned usable text. Confirm the addon's Interface version for the client.

Fully quit WoW after each collection session to flush SavedVariables and the client quest cache.
Back up the `RosettaSourceProbeData` SavedVariables file and `Cache/WDB/<locale>/questcache.wdb`
alongside the prepared queue, reference inputs, locale, and exact client build under the ignored
`datasources/imports/source-scan/` workspace. Preserve previous backups before changing locale, build, or
queue. A quest cache is separate evidence and its order does not establish objective indices.

Collection does not change catalogs or prove that a failed load means the entity does not exist.
Exclude this tool, prepared queues, captures, and caches from addon releases.

## Propose item description row bindings

For explicitly selected items, `import_description_rows.py` can propose a binding between an
owned item description and a captured `ItemSpellTriggerLearn` row. It reads the original literal
SavedVariables file; it does not execute Lua or edit catalogs. Use a completed English session,
its original queue, and the English GlobalStrings export and manifest from the captured client build:

```sh
python3 tools/source-scan/import_description_rows.py \
  --queue datasources/imports/source-scan/RUN/queue.json \
  --capture datasources/imports/CAPTURE/rosetta-source-probe.lua \
  --session SESSION_NUMBER --ids ITEM_ID \
  --global-strings datasources/imports/WAGO/GlobalStrings.BUILD.enUS.csv \
  --manifest datasources/imports/WAGO/manifest.json \
  --patch datasources/imports/REVIEW/description-rows.patch \
  --report datasources/imports/REVIEW/description-rows.json
```

Replace the uppercase placeholders with retained paths and IDs; pass additional item IDs after
the first when needed. Both output files must be new
and under `datasources/imports/`; create the review directory first. The patch uses the
`apply_patch` format. Review the report and patch, verify each recorded owned hash against the
current catalog, and apply only after review. Then follow the catalog build and validation workflow.

The importer verifies the queue hash, current queued catalog snapshot, complete ordered session
and job identities, English locale, capture build, and the GlobalStrings file's manifest hash. For
each item it requires exactly one captured learn row, one matching owned trigger-6 spell link,
and an exact match between the observed English row and the verified use prefix plus owned English
description. The comparison is offline evidence; runtime uses the owned row type and spell ID,
never native text. The binding records capture and source-description hashes. A later English
description change invalidates the binding at build time and requires fresh review or evidence.

This does not infer a binding for every trigger-6 effect. Other row types, ambiguous links, incomplete
captures, missing target descriptions or missing formats remain unresolved and preserve native text.
The captured row is a rendered observation, not a replacement for the raw source template.
