# Local tooltip verification campaign

This opt-in development addon is separate from the shipping FRS addon. Loading it never
starts collection. It reads data and saves local observations; it never casts spells,
uses items or modifies equipment. Installation requires the explicit user authorization
described in the parent [source-scan guide](../README.md).

## Cases

`/frsverify auras` records all readable helpful and harmful auras on the player and target
immediately, then on aura changes and target changes. Each sample retains the actual aura API
returns, instance ID, tooltip getter arguments and response, unit sex and caster level.
No item/spell inventory scan or manual hover is required. Aura hovers also retain their native
visible rows and renderer dependencies. Start outside combat, reproduce the desired active
effects, then use `/frsverify stop` and `/reload`. Expired instances cannot be reconstructed;
these samples validate the new instances without replacing context in historical captures.

`tools/source-scan/replay_aura_campaign.py` replays frozen JSON aura runs, including direct
samples and native hovers. It requires matching captured instance IDs and spell IDs, exercises
the shipping aura owner resolver, and reports missing context separately from untranslated rows.
The real-data regression is `tests/python/test-captured-auras.py`.

| Code | Case | What to compare |
| --- | --- | --- |
| D01 | Smite rank 3 (598) | Native damage range versus FRS |
| D02 | Mind Blast rank 2 (8102) | Shadow school damage range versus FRS |
| S01 | Heal rank 1 (2054) | Healing range versus FRS |
| P01 | Shadow Word: Pain rank 3 (970) | Cast total/duration and active debuff when accessible |
| P02 | Renew rank 2 (6074) | Cast total versus active aura tick amount |
| O01 | Melon Juice (1205) | Complete translated drink effect |
| O02 | Crab Cake (2683) | Food, well-fed bonus and experience bonus |
| O03 | Minor Wizard Oil (20744) | Effect, cooldown, charges and creator line |

IDs here are an explicit test inventory. The collector logic is generic and the list is
not a runtime translation allowlist. Hover capture also accepts other item/spell/aura IDs.

## Two required passes

1. Equip normal gear and use `/frsverify equip` outside combat.
2. Hover the three available items and the five spellbook entries.
3. Reapply Renew to yourself, then hover its active buff. The aura event also records it.
4. If practical, apply Shadow Word: Pain to a suitable target and hover its active debuff.
   A restricted or unavailable API result is evidence to investigate, not a passing case.
5. Use `/frsverify stop`.
6. Remove gear that contributes spell/healing power, then repeat with `/frsverify zero`.
   Reapply the auras after the equipment change; do not compare an old instance to new stats.
7. Use `/frsverify stop`, then `/reload` to flush SavedVariables.

Hovering is sufficient for the item cases; no item needs to be consumed or oil applied.
`/frsverify partial` is an optional intermediate gear profile for rounding checks.
`/frsverify autre` is a separate optional pass receiving Renew from another priest.
Until that observation exists, foreign-caster behavior remains unverified in game.

## Unit pass

`/frsverify unites` starts a run that makes no direct calls. Each hovered unit tooltip records
the raw tooltip data, visible lines, the live `CORPSE` GlobalString and every return slot of
the unit APIs read by the FRS NPC renderer (`UnitCreatureType`, `UnitIsDead`, `UnitGUID`...).
Hover living and dead mobs, NPCs with subnames, elites and players, then `/frsverify stop`
and `/reload`.

## API fixture pass

`/frsverify api` snapshots the data APIs listed in `cases.lua` (`api.calls`) for each listed ID
(`api.ids`) plus the listed GlobalStrings (`api.globals`). It requests only uncached spells and
items, waits for their load events (`api.loadTimeout` seconds at most), captures once and stops
by itself. It records no hovers or auras. IDs still loading at the timeout are listed in
`pendingAtCapture`. Before capturing, it rebuilds the listed tooltips and waits
(`api.settleDelay` seconds, `api.settleRounds` times at most) while a row still shows the client's
`RETRIEVING_ITEM_INFO` placeholder for a linked reagent or set piece; `settleRounds` records how
many waits were needed. Run it once per client locale, then `/reload`.

For a sample of the whole catalog, prepare a separate probe copy:

```sh
python3 tools/source-scan/prepare_api_sample.py --output datasources/imports/source-scan/NEW_RUN
```

It adds a generated `api-sample.lua` with a stable pseudo-random sample of owned IDs per kind
(`--per-kind`, default 300; `--seed` changes the sample) and every owned GlobalStrings key, and
writes `sample.json` beside it. Installing that copy follows the guarded install rules above.

## Targeted recapture campaign

Prepare a smaller probe from an existing gap report:

```sh
python3 tools/source-scan/prepare_tooltip_campaign.py \
  --report datasources/imports/CAPTURE/tooltip-gaps/report.json \
  --output datasources/imports/source-scan/NEW_CAMPAIGN
```

The API inventory replaces the default IDs with up to two selected examples per gap group,
reusing IDs across groups, plus every previously unloaded ID. This covers report examples,
not every entity represented by a group. `sample.json` records the input report hash and IDs.
It does not fetch sources, change catalogs, install anything or start collection.

To replay the whole retained capture inventory instead of group examples, pass
`--fixture tests/fixtures/tooltip-campaign/1.60.1.70938-frFR.json` in place of `--report`.
This preserves the recorded item/spell IDs and exact stable getter arguments, including
talent nodes and recipe outputs. Use the same prepared probe for paired client-language
passes; keep each flushed capture separately.

The API pass now also captures `C_TradeSkillUI.GetRecipeSchematic(spellID, false)` and
`C_Spell.GetSpellPowerCost(spellID)`. False arguments, nil returns, missing APIs, call errors,
load-event success flags and timeouts remain distinct evidence. A finished pass need not mean
that every requested entity was available. Unavailable tooltips are listed separately by replay.

After authorized installation, keep the client language unchanged and use this order:

1. Outside combat, with normal gear, `/frsverify api`. Wait for the completion message.
   Do not reload or start another pass while it is loading; the default campaign wait is up to
   60 seconds for primary records, then up to 30 seconds for linked items.
2. Open a learned crafting profession, select a recipe showing reagents, then
   `/frsverify cible craft`. Hover the recipe and its reagents. `/frsverify stop`.
3. `/frsverify cible normal`. Hover two learned spells (damage, healing or periodic effects),
   the Hearthstone if owned, and the active tooltip of a self-applied aura if available.
   `/frsverify stop`.
4. For a class with forms, stances or stealth, `/frsverify cible forme` and hover the same
   affected spell outside and inside that state. `/frsverify stop`. State changes are manual.
5. Optionally, `/frsverify cible sans-bonus`: remove gear contributing to spell/healing power,
   reapply the same aura and repeat the same hovers. `/frsverify stop`, then restore gear.
   This is useful only when the character has such gear. No talent reset is needed.
6. `/reload`, then preserve the SavedVariables file under a new ignored capture directory.
   Never replace an earlier backup. If transferring files while the client runs, reload first
   and do not start another capture before copying the flushed file.

`cible` starts no direct inventory sweep. Each item/spell/aura hover retains its own native
rows, processing getter, renderer dependencies and character context (class, race,
faction, sex, level, form, stealth, power, gear-derived bonuses and configured trait nodes).
GlobalStrings are captured once per run rather than duplicated for every hover. Renderer
dependencies include the actual `GetBindLocation`, `UnitFactionGroup` and `UnitSex` returns.
Aura spell IDs
come from the structured aura getter, never from the tooltip's instance ID. Active-aura events
are also preserved for inspection; automatic replay currently uses hover samples only.
Visible frame text is auxiliary evidence because other addons may add rows after the hook.
Trait-entry hovers also receive a `nextFrame` observation when the same tooltip data instance
is still present. This retains purchase-gate rows appended after the data post-call. When
FRS exposes its stacked translation range, `nativeVisible` excludes only that recorded range
and retains native rows on either side. Replay prefers this explicit native snapshot.

Replay one explicitly selected, stopped targeted run with the ordinary command:

```sh
uv run --no-project --with lupa==2.8 python tools/source-scan/report_tooltip_gaps.py \
  --capture datasources/imports/CAPTURE/rosetta-tooltip-check.lua --run RUN_NUMBER \
  --output datasources/imports/CAPTURE/replay-RUN_NUMBER
```

API and targeted runs are separate reports. Repeated hovers of the same ID are separate
observations and must not be compared as a count of distinct broken entities. The report
records sample indices/contexts, capture and renderer/pack hashes, recipe API availability,
missing names, skipped loading rows and render errors. Legacy captures remain supported;
an uncaptured schematic is explicitly classified as `not captured`, not as a verified in-game
absence. Captured APIs replay their original arguments, errors and return counts.
Only renderer dependencies are installed; power-cost captures remain inspection evidence.
This checks renderer behavior in captured contexts, not linguistic or numeric correctness.
API replay also retains recorded trait, recipe-result, recipe-reagent and item-link tooltip
surfaces. Repeated IDs remain distinct observations because their rows can differ by getter.

The versioned campaign fixture retains real native rows and recorded API responses. Its
strict regression test (`tests/python/test-captured-tooltip-campaign.py`) fails while any
render keeps an untranslated row. `FRS_CAPTURE_REPORT` saves the failing observations;
`FRS_CAPTURE_TARGETS` and `FRS_CAPTURE_RUNS` select a replay scope. Loading placeholders are
reported separately as unavailable evidence. Talent replay removes only the identifiable
FRS insertion and retains the native current-rank and next-rank blocks.

Another source-client language needs a separate capture on that client. In particular, frFR
to zhCN/zhTW target replay does not establish behavior on a Chinese source client. Do not
change language for the first campaign; a second source-language pass can follow separately.

## Tooltip gap pass

To find rows that would show the incomplete-translation notice before a player reports them,
select IDs by tooltip feature instead of at random:

```sh
python3 tools/source-scan/prepare_tooltip_coverage.py \
  --wago datasources/imports/WAGO_RUN/wago --output datasources/imports/source-scan/NEW_RUN
```

The Wago snapshot must be the client build. Each feature that drives a distinct native row or
value extrapolation gets `--per-feature` owned IDs present in that build (default 3), rarest
first: spell description and aura token shapes (`$s1`, `${$m1/-1000}`, `$lpoint:points;`,
`$?s123[...]`, `$@spellname`), subtext, cast time, range, duration, school, passive and owned
tooltip facts; item class/subclass, slot, binding, quality, stat types, requirements, sets,
flags, weapon damage, durations and each effect trigger with its spell's token shapes.
`features.json` lists the selected IDs per feature; `sample.json` lists the features that have
fewer candidates than requested. Install the copy, run `/frsverify api`, `/reload`, back up the
SavedVariables file under `datasources/imports/`, then replay it offline:

```sh
uv run --no-project --with lupa==2.8 python tools/source-scan/report_tooltip_gaps.py \
  --capture datasources/imports/CAPTURE/rosetta-tooltip-check.lua \
  --output datasources/imports/CAPTURE/tooltip-gaps
```

Every captured `C_TooltipInfo` spell and item tooltip is rendered with the shipping renderer and
built packs into each target language. `report.md` groups the rows behind the notice by kind,
line type, reason (`left kept`, `right kept`, `unmatched`, `requirement`, `subtext`) and
number-normalized native text, with counts and example IDs. Tooltips still showing
`RETRIEVING_ITEM_INFO` are skipped and listed for recapture. After a fix, rebuild and rerun the
report; no new capture is needed. NPC and context-dependent tooltips still need the hover passes.

## API fixtures

Back up the SavedVariables file under `datasources/imports/`, then convert the run:

```sh
python3 tools/source-scan/import_client_api_fixture.py \
  --capture datasources/imports/CAPTURE/rosetta-tooltip-check.lua --run RUN_NUMBER \
  --globals-report datasources/imports/CAPTURE/globals-report.json
```

The fixture `tests/fixtures/client-api/<build>-<locale>.lua` holds the API returns only; it is
not overwritten without `--replace`. A full catalog sample is several megabytes, so pass
`--limit-per-api N` to version N responses per API plus the explicit IDs of `cases.lua`; the
retained capture keeps everything. Captured GlobalStrings are not copied into it: the report
classifies each one against the owned catalog value (`identical`, `export escapes`,
`different`, `not in catalog`, `absent in client`, `no catalog value`).

Lua tests replay the fixture with `tests/lua/support/client-api-fixture.lua`: each installed API
returns fresh copies with the captured return count and nil slots, replays captured errors,
leaves APIs missing from the client undefined and raises for uncaptured arguments unless
`strict = false`. Tests take GlobalStrings from the catalog with
`ClientApi.InstallGlobals("frFR", {...})`, which decodes the export's Lua escapes (`\32`, `\"`, `\\`)
as the client does, and fails for keys without an owned value. Frames, fonts, mouse focus and combat state are
behaviour, not data, and stay as hand-written mocks. Units, active auras and quest frames still
need the hover passes above.

## Preserved evidence

Each profile appends a run in `RosettaTooltipCheckData.runs`. It keeps the build, locale,
the explicit case inventory, and per-sample player level, per-school damage, healing
bonus, spirit, attack power, combat state and relevant live trait node data. Full API
returns preserve nil slots, errors and unavailable APIs. Raw tooltip structures, actual
hover getter info and visible frame lines are captured separately. Aura snapshots retain
the source unit, instance data, returned points and native instance tooltip. There is no
depth or field-count truncation; cycles, nonfinite values and restricted/opaque data are marked.

Hover callbacks can run before another addon's final additions. Visible lines are auxiliary
evidence; they do not by themselves prove that every FRS row was captured after rendering.

Collection stops at 600 samples with a message. Reloading never resumes collection.
Previous runs are preserved. Invalid SavedVariables are not overwritten.

### Clear captures after exporting

After copying any evidence you want to keep, run `/frsverify clear`, then `/reload`.
This explicitly discards **all tooltip-probe runs**, stops active collection and prevents
pending callbacks from appending to the cleared data. The next capture starts a fresh run.
Only this command deliberately replaces incompatible SavedVariables with an empty schema.
It does not reset FRS settings, delete quest/source collector data, or remove exported files.

Normal FRS picks are separate: `/frs clear` clears the in-memory picks and saved debug report.
Error history can be cleared from the error report window and is already bounded.
The tooltip probe is a developer tool and is not included in player release packages.

The game writes the empty probe data on reload/logout; addons cannot delete files from disk.
An older large `.bak` may remain until another save rotates it. If the client cannot load
the existing dump, quit WoW completely before archiving/removing the probe's `.lua` and
`.lua.bak` files outside the game. Keep exported evidence under ignored `datasources/imports/`.

The saved file is under:

`WTF/Account/<account>/SavedVariables/rosetta-tooltip-check.lua`

Keep an original backup under ignored `datasources/imports/` before analysis. Real captures
are regression evidence, not replacement catalog templates. A successful synthetic test
does not establish the availability of those fields in the game client.

## Acceptance

For every observed case, match the ID, build, locale and actual aura instance; compare
native and target numeric values and confirm that no untranslated warning remains. First
classify failures as owned-data omissions, unsupported rendering or unavailable client
values. Only the last category is a candidate for a guarded native-text extraction path.
Then replay retained captures offline and extend catalog matrices across all target locales.
These passes calibrate representative behaviors; they do not manually verify every spell
or item in every class, level and talent configuration.
