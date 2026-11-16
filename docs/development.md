# Development and validation

Source-driven catalog changes follow [the import/resync policy](import-resync.md).

[Back to the project](../README.md)

Run commands from the repository root. See also [the database guide](database.md) and [the release guide](releases.md).

## Runtime layout

`ForeverRosettaStone/core.lua` is the entry point. Runtime files are grouped by responsibility:

- `core/`: safety guards and shared controller.
- `database/`: database API and item/NPC data adapters.
- `quests/`: quest state, readers, reports, panels, and reward tooltips.
- `tooltips/`: rendering, formatting, lifecycle, `components/`, and placement `policies/`.
- `settings/`: settings UI and minimap button.
- `diagnostics/`: errors, debug display, benchmarks, and optional developer tracing.
- `locales/`: diagnostic labels, character-stat translations, and `tooltips/` locale formats.
- `media/` and `notices/`: artwork and attribution.

The folder layout does not determine load order. `tools/build/addon-manifest.toc` declares the
ordered runtime files; the database builder embeds it in the generated addon TOC. Keep both
manifests aligned when moving files, and update explicit paths in generators and test harnesses.
`Bindings.xml` stays at the addon root for the client's implicit binding discovery.

## Strict ID-only coverage

For catalog update cycles, run scoped checks while preparing and reviewing changes, then build
once after all catalog edits and run the full required checks in
[catalog maintenance](../catalogs/AGENTS.md#build-and-validate). A focused matrix run with
`--kind`, `--locale`, `--profile`, or `--ids` is useful for diagnosis; it is not a substitute
for the full strict matrix. The default test runner includes matrix stages; `--unit-only`
deliberately excludes them. Save the final report and distinguish unresolved coverage failures
from missing source evidence. If validation requires another catalog correction, rebuild and
rerun the affected checks and full required validation.

Saved quest captures use the original queue and catalog fingerprints. Follow
[capture integration](../tools/quest-scan/README.md#integrate-a-saved-capture): review the
generated patch and fixture, keep unresolved or ambiguous observations separate, and include
accepted changes in the same final build. Capture import prepares a patch; it does not apply one
or automatically create translation jobs.

Run unit and integration checks separately from translation coverage:

```sh
uv run --no-project --with lupa==2.8 python tests/run-tests.py --unit-only
```

This mode includes addon behavior, syntax, XML, and manifest checks. It does not run translation
matrices or establish translation coverage. The default runner still includes all matrix stages.

```sh
uv run --no-project --with lupa==2.8 python tests/python/test-id-only-matrix.py
```

This matrix checks every maintained item and spell, and every quest exported by the product,
in all supported target locales. Product-excluded quest IDs and their reasons are recorded.
The two deterministic profiles exercise different character levels, spell power, known-spell
conditions, player sex, and objective counts. Player level is available as branch-selection
context; character-stat and spell-power recalculation APIs remain blocked. Independent spell
fixtures preserve owned paragraphs and decode literal percent escapes. They do not cover every possible live state.

Before rendering, the isolated Lua runtime removes matching fields from returned records and
blocks source getters, reverse-name lookup, native-description APIs, and private matching
functions. Native row text is replaced with an opaque sentinel. Valid target translations and
numeric catalog data remain available. The maintained catalogs and installed addon are unchanged.

Every missing translation, native fallback, forbidden dependency, unsupported expectation,
rendering error, or output mismatch fails coverage. Unsupported cases are recorded individually;
they are not skipped. An optional field absent from all maintained languages is reported as
not applicable rather than counted as translated. Mandatory names and quest titles are checked
for every entity, locale, and profile; omitted or duplicate cases invalidate the result.

The summary is `datasources/imports/id-only-matrix/report.json`. The adjacent `report-quests.json`,
`report-spells.json`, and `report-items.json` contain each failed case and its reason. Independent
spell expectations use owned numeric data and retained locale-format dictionaries; an oracle
limitation is a coverage failure, not proof of a production renderer defect.

Group a completed report without changing its results:

```sh
python3 tests/python/group-id-only-failures.py --output datasources/imports/id-only-matrix/root-causes.json
```

The grouping verifies stage hashes and accounts for every failed case once. Candidate groups
identify the next investigation; they do not establish a production defect from a failed lookup alone.

`--kind`, `--locale`, `--profile`, and `--ids` narrow debugging runs. Narrowed reports are marked
scoped, and the command still exits nonzero for any failed case. There is no allow-gaps mode.

Entity tooltip rows use verified row types, entity IDs, and owned formulas. Native entity names,
descriptions, quest titles, objective text, and faction labels do not identify translations.
Unmapped rows retain native text. Required quest amounts come from indexed client objectives;
an unavailable value suppresses that translated field instead of parsing the displayed summary.
Localized templates and field provenance live under `locales`. Source getters derive eligible
non-AI fields for explicit reference and diagnostic lookups; rendering uses target templates and IDs.

Effect formulas accept uppercase `A`, `O`, `T`, and `X` aliases and the `$/N;` and `$*N;`
coefficient prefixes on `s`, `S`, `m`, and `M` values. These use the same owned effect and
scaling prerequisites as the unmodified token. Missing values remain coverage failures.
Numeric `$<name>` references resolve only from the current spell's owned variable definitions,
including known-spell branches and dependencies. Missing, conflicting, or cyclic definitions fail closed.
The full translation suite always includes this strict stage, independently of its older
`--strict-coverage` option. Focused matrix fixture tests also run in the standard test runner.

## Local development trace

The debug console command field accepts `dump <Lua expression>` or a pasted `/dump` expression.
For example, run `dump C_TooltipInfo.GetHyperlink("spell:430")` to inspect the live structured
spell tooltip without drinking or sending its output to chat. Input is not limited to the
chat command length. Results appear in the existing scrollable, copyable report with a count
and type for every return value, including `nil` and `false`. Syntax and API errors appear in
that report. Probe snapshots include all readable returned fields without depth or field-count
truncation. Cycles, restricted values, and opaque objects are marked; hidden engine data is not
enumerable. Expressions execute as addon Lua only when Run or Enter is pressed, including function
calls and immediately invoked function expressions. The probe is available only in local builds made with `--dev-debug`, alongside the profiler
and optional trace module below. Normal builds retain the support console without Lua execution or profiling.

Build or refresh an installation manifest with `--dev-debug` to load `diagnostics/dev-debug.lua`,
`diagnostics/dev-api-probe.lua`, and `diagnostics/dev-benchmark.lua`, and add
`ForeverRosettaStoneDevTrace` to its SavedVariables. Normal manifests omit these modules and the trace SavedVariable. For an existing
installation, use `python3 tools/build/build-lua-database.py --manifest-only --dev-debug --output <installed-addon-toc>`.

The debug window has native **Overview**, **Captures**, and **UI components** tabs.
**UI components** (`/frs display`) offers native item, spell, quest, and crafting-recipe tooltips.
Choose a type to populate an example, or enter an optional ID or matching link. An empty field
uses the selected type's default sample. **Show tooltip** and **Pin tooltip** close the console so the native tooltip and translation
can render normally. `/frs pin quest 783` pins a native quest-link tooltip.

Choose **Back to debug tools**, press **Escape**, or use gamepad **Back** to close the preview and restore the
UI components tab with the same type and ID/link. Gamepad **Select** can activate the return button.

Recipe previews use crafting spell IDs (`/frs display recipe 7418`); recipe scrolls and crafted results use Item.
**Compare equipped** uses WoW's native item-comparison renderer with a default item sample.
It shows the comparisons appropriate to the character's current equipment, including both
native shopping tooltips when applicable. **Side by side** and **Stacked** choose the preview's
translation layout without changing saved settings. The layout also applies to equipped comparisons.
The client must have data for the requested entity. These previews do not simulate profession
windows, reagent inventory, loot rolls, or mouse/gamepad interaction on the original surface.

Reload to load the debug build, hover the affected items and spells, then reload again to flush the trace.
WoW writes it into the account's `SavedVariables/ForeverRosettaStone.lua`; it does not stream arbitrary files live.
Character-stat hovers, including resistances and specialized damage tooltips, are captured as
`character.stat.hover` events. These include the current row label/value, raw tooltip fields,
client locale, and rendered tooltip lines with colors. Pooled rows may have no frame name;
the captured label identifies their current content. The trace does not infer translation keys.

Character-stat translations use the normal Stacked/Separate display setting and have their own
**Character → Character stat tooltips** switch. Stat rows and resistance icons are identified from
their native setup callbacks, including pooled and unnamed ScrollBox rows. Complete rendered rows
are translated against keyed GlobalStrings templates; numbers, buffs, both columns and colors come
from the live tooltip. No character-stat formulas are recalculated. Unknown rows remain native and
the translation is marked incomplete. Stat explanations always use full text.

`tooltips/character-stat-formats.lua` is generated from build-matched official exports. The additional Forever Rosetta Stone
languages have no character-stat explanation maps yet, and the retained Italian export contains
English fallback text. These are language-coverage limits. Rebuild the formats using
`python3 tools/build/build-character-stat-formats.py --source-dir <pinned-ui-source-directory> --strings-dir datasources/imports/RUN/wago` with
`rosetta-paper-doll.lua` and `rosetta-paper-doll-stats.lua` from the pinned Camelot UI source.
`tests/fixtures/character-stat-tooltips-70862.json` retains 23 captured French tooltips, including
all five magic resistances, without account or player fields. This fixture verifies the captured
character's rows; class-specific templates outside those hovers are not in-game verified.
`/frs status` confirms the debug revision and captured event count. The trace retains the first
12,000 events per session and the latest three sessions, including native IDs and payloads, rendered
text, getter arguments, owners, lookup results, layout bounds, settings, and caught errors. It warns
when full and counts omitted events instead of overwriting earlier hovers. Restricted values are
marked; native payload snapshots stop at five nesting levels. Rebuilding the manifest without
`--dev-debug` disables capture.

## Benchmark in game

Requires a local `--dev-debug` build. Release builds omit the profiler and its commands.

Keep the French client. The capture temporarily selects English for Forever Rosetta Stone and restores the
previous translation language when stopped. Profiling is manual and disabled during normal use.

1. Close the map and tooltips, then `/reload` to start with fresh Forever Rosetta Stone caches.
2. Run `/frs bench start`.
3. Hover several bag/equipment items, including native comparisons. Repeat some hovers to exercise
   cached reads. Hover several spellbook/action-bar spells and repeat them too. Chat links,
   talents, NPCs, collections and minimap companions also record their own categories.
4. Open quest details to exercise Forever Rosetta Stone's panel. Change quests and reopen one you already read.
5. Run `/frs bench stop`. The copyable report opens after chat finishes. Click its text and
   press Ctrl+C / Cmd+C to save the report for analysis.

Capture stops automatically after 90 seconds. Use `/frs bench report` to reopen the latest
report. A new capture replaces it, and `/reload` discards it. Reset, logout/reload, addon errors,
or selecting a language other than English also stop capture.

The report includes client/build/catalog identity; count, mean, maximum and first-observed timings
for DB lookups, item/spell companion updates and layouts, and quest-panel refreshes; page-cache
hits/misses; native base64, inflate and CBOR decode totals; addon-attributed Lua memory and global
   Lua-heap snapshots; and the first 128 individual samples. Each tooltip sample identifies its
   entity ID and native frame/getter where available. Aggregates continue beyond that cap.
The quest panel's normal periodic refreshes are included, so its average mixes content changes and
unchanged refreshes. The first and maximum samples help identify more expensive work.

First observed does not guarantee a cold cache: starting capture refreshes any currently visible
Forever Rosetta Stone UI. Page misses and decode totals show actual decode work. Timings measure synchronous Lua
updates, not GPU rendering or total frame time, and nested categories must not be summed.
Memory snapshots include capture overhead, and global Lua memory also includes other addons.
These are before/after snapshots rather than peak or retained-after-GC measurements; capture does
not force garbage collection. Native client memory holding the TOC metadata is outside addon Lua
attribution. Native stopwatch measurements do not require enabling `scriptProfile`.

## Tooltip components

The native `GameTooltipTemplate` supplies each companion. `tooltips/tooltip-layout.lua` owns creation,
spacing, and placement primitives. `tooltips/tooltip-companions.lua` owns native tooltip hooks and lifecycle effects.
Each component selects its placement strategy from `tooltips/policies/`. Item, item-comparison, spell,
talent, and NPC strategies own their rules independently. `toolkit.lua` supplies the policy factory and
small composable anchor rules; it contains no type dispatch. Add new type behavior to its component
and strategy, rather than branching in the shared renderer. Individual resolvers live under `tooltips/components/`:

| Component ID | File | Native source and DB lookup |
| --- | --- | --- |
| `item` | `item-tooltip.lua` | Item/toy tooltip item ID → item name; also equipment, appearances and chat links using item tooltips |
| `spell` | `spell-tooltip.lua` | Spell tooltip spell ID → spell name; including action bars and spellbook |
| `characterStat` | `character-stat-tooltip.lua` | Character stat rows and resistance icons → keyed client templates with displayed live values |
| `talent` | `talent-tooltip.lua` | Native talent spell data or talent button's `GetSpellID()` → spell name; live talent IDs are never treated as DB2 IDs |
| `npc` | `npc-tooltip.lua` | Creature/vehicle GUID → NPC name; players and custom pet names remain native |
| `mount` | `mount-tooltip.lua` | `GetMountBySpellID` argument → spell name |
| `pet` | `pet-tooltip.lua` | Native battle-pet species → client creature ID → NPC name, when available |
| `minimapQuest` | `minimap-quest-tooltip.lua` | Minimap line's quest ID, or a unique catalog title → quest title |
| `minimapLocation` | `minimap-location-tooltip.lua` | Native zone-heading owner and current zone/subzone → area names |
| `quest` | `quest-link-tooltip.lua` | Quest link in `ItemRefTooltip` → quest title, summary and requirements |
| `questTracker` | `quest-tracker-tooltip.lua` | Hovered or controller-focused tracker block or POI → quest title/summary with live progress |
| `questOffer` | `quest-offer-tooltip.lua` | Hovered or controller-focused NPC Gossip ScrollBox quest row → quest title |

Every module registers through `RegisterNameTooltipComponent`, which constructs and validates the
common interface in `tooltips/tooltip-component.lua`. All components expose `GetName`, `ResolveData`,
`ResolveOwner`, `GetPlacementContext`, `SelectPlacementPolicy`, `FillTooltip`, `AfterFill`, `Install`,
`Update`, and `Hide`. Inapplicable operations use explicit no-op defaults supplied by the factory.
Each component has independent placement profiles for its declared screen contexts and both input modes.
Invalid method types, capability types, shared input-mode profiles, and duplicate IDs are refused
before they enter the registry. Full-text and embedded-display support are component
capabilities; the shared renderer does not select behavior by component ID.

Native callbacks drive data-based components. The same registry drives focus-based components through
`Update` and `Hide`, including tracker and quest-offer components. Component IDs identify implementations;
screen locations and mouse/gamepad input modes identify their presentation contexts. Screenshot codes
can map to those contexts without inventing a different component for every screen. The contract tests
verify registration and interface coverage, not visual coverage of those contexts.

Placement is selected by `component / context / mouse|gamepad`. Items distinguish bags, equipment,
action bars and chat links; comparisons have their own strategies for those same contexts. Spells
distinguish spellbook and action-bar tooltips. Mode configurations are separate objects even when
their initial rules match. Type-specific policy files compose shared rules from `toolkit.lua` and may
override one context and mode without mutating another. The trace records the selected context and mode.

Unknown IDs, ambiguous minimap titles, and missing species/locale records show no companion.
The NPC greeting prose is outside the quest-title component. Named component switches apply
immediately and translation-language changes refresh displayed names. Tracker and quest-offer
hover checks reuse the addon's existing refresh loop.

Tooltip groups use the lifecycle in `tooltips/tooltip-state.lua`: `hidden`, `building`, `scheduled`,
`rendering`, `visible`, and `cleaning`. Native clears enter `building` and preserve the displayed
companion until replacement data and native geometry are ready. Show, anchor, and resize events
share a scheduled layout; stale callback tickets are refused. Rendering and cleanup refuse
reentrant native callbacks. Existing placements are updated in place and restored only on exit
or a display-mode change, rather than restored and reapplied during each native refresh.

## Translation boundary

`quests/quest-data.lua` consumes `ForeverRosettaStoneDB`; it contains no translated quest corpus.
Missing titles use the missing-quest page; other missing prose fields render empty. Unknown
tooltip quests show no companion. Duplicate titles never select an arbitrary quest ID.
The native quest list and objectives remain in the client's language.

Captured objective templates retain their verified client index and type, and receive live
counts at render time. Verified item-to-client-index mappings are compiled from owned
catalog records. Questie target positions are not assumed to be client indices:
unmapped objectives retain the client's own text. Progress and rewards are never baked
from a character's saved values. Returned quest records expose an aggregate AI flag;
field origins remain inline in the catalogs.

The English panel is a separate instance built with Blizzard's `PortraitFrameTemplateNoCloseButton` shell,
using the bags' native `HeldBagLayout` and 36×36 portrait size for the Forever Rosetta Stone logo,
`QuestLogBorderFrameTemplate`, `QuestDetailsBackgrounds` atlas, `ScrollFrameTemplate`, quest fonts,
and reward widgets. It follows
the native quest panel's dimensions, header, content gaps, and clipped rewards layout. The addon
supplies translated text and coordinates the panel; scrolling uses Blizzard's scrollbar and wheel
handling. No copied textures or custom scrolling renderer are loaded.

The translated text copies effective fonts, colors, shadows, and spacing from the French quest
text, including per-element font overrides. Its full-height viewport and rewards spacer follow
the native layout. Blizzard's rewards adjustment uses the English scroll offset to reveal reward
rows. French scrolling cannot change the English scroll offset or reward area height. Reward
cards mirror native values and usability tints; localized item names are keyed by item ID. Items without a selected-language name retain their native name.
Rewards are a display, without reward selection or quest-changing actions. No native frames are
reparented, and rendering English does not change the selected quest. The shared `QuestInfo_Display`
renderer is not called for the English panel because it would move the French text frames.
The bundled provider supplies the wider translation source without a runtime external database dependency.

## Validation

Quest navigation uses the explicit transition table in `quests/quest-state.lua`: `unavailable`, `open`,
`reading`, `collapsed`, and `bookmarkFocused`. Native selection events enter or leave
`bookmarkFocused`; activating the selected bookmark emits a `panel.focus` effect. The native
focus callback confirms `reading`. Returning to the quest list enters `unavailable`, and ignored
events produce no effects. Frame visibility and secure focus registration run outside the machine.
Input-mode changes emit `controller.reset`, clearing native-focus state before registration is
reconciled on the next permitted refresh.

Run from this repository's root with Python and `lupa==2.8`:

```sh
uv run --no-project --with lupa==2.8 python tests/run-tests.py
```

The runner includes the full translation matrix. To run that matrix on its own:

```sh
uv run --no-project --with lupa==2.8 python tests/python/test-translation-matrix.py
uv run --no-project --with lupa==2.8 python tests/python/test-translation-matrix.py --strict-coverage
```

The ID-selected stage checks maintained quests, spells, and items across configured target
locales, currently 18. Spell and item effects use synthetic displayed values from original source
templates, with independently prepared target expectations and no formula evaluation. Quests
retain their structured-progress checks. Additional stages check shared labels and renderer surfaces using their
declared client-locale inventories. Reports under
`datasources/imports/translation-matrix/`, `datasources/imports/tooltip-matrix/`, and `datasources/imports/quest-matrix/`
separate verified cases from missing source evidence, missing targets, ambiguous matches, and
unsupported synthetic fixtures. `classification.json` separates confirmed addon failures,
missing/invalid owned data, independent-checker or fixture limitations, and unclassified reasons.
All unverified cases still fail strict catalog completeness. Per-kind reports retain individual
cases, dependency evidence, reason groups and examples; aggregate counts exclude the repeated
spell-shard stage. `suite.json` lists each stage and its report. Strict coverage also
fails on classified missing target text, unsupported renderer grammar, and ambiguous stat rendering.
Grouped gaps can overlap. Synthetic native rows exercise parsing; they do not establish how every
tooltip appears in game. An entity absent from the catalog still needs a capture and catalog update.

The harness uses **Lua 5.1**, the real addon renderer, and mocked WoW APIs and native templates. It checks transitions, selection changes,
tooltip ownership and recycled rows, progress, reopening, map visibility and scaling, and controller
input consumption. Failure injection covers quest API errors, partial initialization, scrollbar
errors, controller errors, repeated events after failure, and recovery without a reload. No Spoken
addon is loaded in the harness. Native-component checks cover preservation of the French text,
native window focus, gamepad reopening, independent scrolling, progressive rewards, wheel scrolling, reaching the final
paragraph, and resizing. Cleanup checks cover map closure, menus, failures, reset, and deferred
cleanup after combat. The runner also checks Lua syntax, binding XML, TOC file references, and
the standalone manifest. Controller overrides and raw gamepad capture are forbidden by the harness.

Native API references were checked against Gethe's `forever` UI source at
`9dc84f0d3bbae1768ac3405b3716000bd93eda06` (client `1.60.1.70862`).

**In-game visual, controller, and taint validation is required for runtime releases.**
Mocks cannot establish native focus routing, visual alignment, or freedom from taint.

The live acceptance check is: focus each supported quest with a controller, compare both tooltips,
open its details, use RT to select English, scroll to the last paragraph with the right stick,
then use LT to return to French. Confirm that scrolling either panel leaves the other unchanged
and that all English rewards become visible at the bottom. Close English with B and confirm that
Forever Rosetta Stone leaves no LT/RT window target. Use the D-pad to select the right-side book bookmark and
press A to reopen it. Confirm that English regains scroll focus,
then return to the map with LT and close it with B. Repeat with Spoken's story open, switch to an unsupported quest,
and confirm that the original map controls still work and no blocked-action dialog appears.
