# Local quest collection tool

This versioned development tool is a separate WoW addon. It is excluded from Forever Rosetta Stone's
shipping directories and TOCs. A fresh checkout has everything needed to prepare it;
generated queues, saved observations, and caches stay under ignored `datasources/imports/quest-scan/`.

Use existing captures first. Installing or starting a scan requires an explicit user request.
Preparing files offline does not install the tool, start WoW, or send quest requests.

## Prepare an explicit queue

From the repository root:

```sh
python3 tools/quest-scan/prepare.py --ids 170 943 --output datasources/imports/quest-scan/new-run/rosetta-quest-probe
```

The command copies `probe.lua` and the development TOC, and generates `queue.lua` with
the selected IDs and source fingerprints. It reads only those catalog IDs; IDs absent
from the catalog may also be requested. Use `--eg-revision FULL_SHA` if the queue was
selected against a pinned EG Link snapshot. It rejects duplicate/invalid IDs, existing
output directories, and destinations outside `datasources/imports/quest-scan/`.

Choose a new run directory rather than overwriting a previous queue or saved results.
Use `--session-name Matrix20261113` to prepare a separate SavedVariables name when a previous
scan is already loaded. Back up its addon and SavedVariables files before installing the new
session. This avoids mixing queues or requiring the old results to be cleared in game.
The TOC's Interface number must match the intended client family before installation;
the scanner records the actual client build and locale when it first loads.

## Install and run only when requested

Copy the prepared `rosetta-quest-probe/` directory as its own addon under the local
client's `Interface/AddOns/`. Do not copy it into `ForeverRosettaStone/`. Preserve any
existing probe SavedVariables before replacing a queue or changing client build/locale.

- `/frsscan status`: inspect progress; loading the tool does not start requests.
- `/frsscan start`: explicitly start or resume the prepared queue.
- `/frsscan pause`: stop new requests after the current request finishes or times out.
- `/frsscan report`: open the copyable status report.
- `/frsscan quest 170`: inspect one saved quest's status, raw objective rows, and request error.

Bare `/frsscan` opens the same local report window. Its command field accepts `status`,
`start`, `pause`, `report`, `quest ID`, and `compare ID`. Choose **Select output**, then Ctrl+C / Cmd+C
to copy text without using chat. Opening a report never starts or resumes the scan.

The explicit transition table in `probe.lua` owns loading, idle, cooldown, waiting,
pausing, paused, and complete states. One request may be in flight; requests are spaced
at least 0.2 seconds apart, each times out after 10 seconds, combat delays new requests,
and a session ends after two hours. Reloading preserves progress but does not auto-resume.
Changed queue/build/locale is refused rather than mixed into existing saved results.
After a successful quest load, blank or counter-only objective text is reread every 0.2 seconds
until it resolves or the original 10-second request deadline expires. In enUS this also covers
monster rows containing only a counter and `slain`. Usable rows incur no retry delay. Unresolved
rows retain the observed text and `labelRetry = "incomplete"`; resolved retries record `"resolved"`.
Each unresolved quest can use the remaining request deadline, so a large queue can take much longer.

Fully quit WoW after collection to flush both `RosettaQuestProbeData` SavedVariables
and the client's `Cache/WDB/<locale>/questcache.wdb`. Preserve copies with the run's queue,
build, and locale under `datasources/imports/quest-scan/`. Disable the local probe after collection.
Failed loads, successful empty objectives, and missing API rows are distinct outcomes.
Use the [source guide](../../datasources/SOURCES.md#existing-local-in-game-quest-scan)
for cache/mapping limits and the historical scan evidence.

## Compare item-cache observations

An optional JSON file maps selected quest IDs to candidate item IDs, for example
`{"6": [182], "272": [15885]}`. Pass it to `prepare.py` with
`--item-dependencies PATH`. Each list must contain 1–100 unique positive item IDs.
The sorted candidates are included in the queue fingerprint. They are candidates for
an experiment only: their order does not identify or map client objective indices.

An isolated two-quest session has already been prepared at
`datasources/imports/quest-scan/item-cache-comparison-20261113/rosetta-quest-probe/`,
using `datasources/imports/quest-scan/item-cache-comparison-20261113/item-dependencies.json`
and the SavedVariables name `RosettaQuestProbeData_ItemCacheCompare20261113`. In the
saved capture, quest 6 had one item objective with a blank label; quest 272 had one
item objective with a label. Items 182 and 15885 respectively are quest-linked candidates.
To prepare an equivalent fresh session, choose a **new** output and session name:

```sh
python3 tools/quest-scan/prepare.py --ids 6 272 \
  --item-dependencies datasources/imports/quest-scan/item-cache-comparison-20261113/item-dependencies.json \
  --output datasources/imports/quest-scan/NEW-RUN/rosetta-quest-probe \
  --session-name NewItemCacheComparison
```

Only when a run is explicitly requested, install the prepared probe as described above.
Start the queue with `/frsscan start` and wait until the quests have loaded; comparisons
require a successful saved quest result and run only while the scan is idle, paused, or
complete. Run `/frsscan compare 6` and, once it finishes, `/frsscan compare 272`.
`/frsscan pause` stops a comparison after its current item request finishes or times out.

Each comparison saves separate before/after objective observations, build, locale,
queue fingerprint, and each candidate's cache state and request outcome in the session's
SavedVariables. Already-cached items are skipped; unavailable or failed cache checks are
recorded. Requests use the same spacing, timeout, combat delay, and session limit described
above. Existing quest results and the scan cursor are not replaced. Preserve the queue and
SavedVariables after fully quitting WoW. The post-request labels are observations, not proof
that item loading caused a change; delayed quest data or an already-warm cache can confound
the comparison. Monster and other missing labels need separate investigation.

## Integrate a saved capture

`import_capture.py` prepares a catalog patch and a compact matrix fixture without editing
catalogs. Supply the saved Lua file, its original `queue.lua`, the session's SavedVariables
name, and a new output directory under `datasources/imports/`:

```sh
python3 tools/quest-scan/import_capture.py --capture datasources/imports/quest-scan/RUN/saved-variables.lua \
  --queue datasources/imports/quest-scan/RUN/rosetta-quest-probe/queue.lua \
  --variable RosettaQuestProbeData --output datasources/imports/quest-scan/RUN/integration
```

It verifies queue/catalog fingerprints, completion, locale, quest titles and contiguous
captured indices. Each fully labeled item row or explicit `NAME slain` / `NAME destroyed`
monster row is checked independently against exactly one existing quest-linked identity
with translations in every configured language. Reputation rows must use captured standard
English standing labels and exactly one quest-linked faction's English name; the observed
client index is stored explicitly with the faction ID and `reputation` type. Captured standings
are never stored as live values. Verified subsets retain their captured indices
in explicit `index` fields when the mapping is partial. The report identifies verified indices
and unresolved rows with reasons. Blank labels, ambiguous identities, failed loads, mismatched
existing mappings and conflicting objective types remain unresolved. Existing mappings and
their provenance are preserved unless every existing mapped index can be reverified against
the current capture. Relationship order never supplies client indices. Captured counters are
validation context and are not stored as live values.
Completed comparison after-observations may supply rows from the same capture when queue,
build, locale, quest, candidate dependencies, title and catalog fingerprints match. The importer
rejects conflicting row types, counters, or nonblank labels across observations and rejects
conflicting completed comparisons; it ignores incomplete comparisons. The original capture is
left unchanged. A later label is evidence of the returned text, not proof of what caused it.

Review `updates.patch`, apply accepted catalog changes, and retain the generated
`client-objectives.json` as a versioned test fixture. The matrix can use observed types and
indices to verify count variables while still failing missing objective translations or
unknown types. Failed/empty responses do not establish that a quest has no objectives.
Build once after catalog edits, then run the matrix and normal checks.

## Validate and exclude from releases

```sh
python3 tests/python/test-quest-scan-preparation.py
uv run --no-project --with lupa==2.8 python tests/python/test-quest-scan.py
python3 tests/python/test-local-scan-boundary.py
```

These checks also run through `tests/run-tests.py`. They need neither a WoW installation
nor previous captures. Mocked lifecycle checks do not establish behavior on a new client build.

Package only `ForeverRosettaStone/` and the generated `ForeverRosettaStone_Data_*`,
`ForeverRosettaStone_Source_*`, and `ForeverRosettaStone_Rules/` directories. Exclude
`tools/`, `datasources/imports/`, tests, and the separately installed probe from every release.
