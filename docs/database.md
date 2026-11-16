# Database and catalogs

[Back to the project](../README.md)

Run commands from the repository root. For other addons, see [the public API](api.md).

The bundled database excludes test/development quests and exports accepted quest text,
plus available item, NPC, area, spell and DB2 talent names.
Translation coverage varies by language; missing fields remain explicit gaps.
The quest panel, name tooltips, quest companions, locations, and reward names read the same public database API.
Components include talents, NPCs, tracker quests, NPC quest offers, minimap quests/locations, and collections.

## Component data sources

Fresh source collection lives in [`datasources/`](../datasources/README.md). Its orchestrator fetches
into ignored `datasources/imports/`, then builds and verifies SQLite. Quest titles/descriptions come from
Blizzard; Questie supplies summaries and missing titles. EG remains an NPC/item source only.
Raw source snapshots and SQLite files live under `datasources/imports/`; catalogs own accepted text.

Forever Rosetta Stone maintains **its own Forever-only translation database** in `catalogs/<kind>/<id>.json`,
with all languages for each entity together. Catalog metadata files store only
configuration. Tools read them through `tools/catalogs/catalog_storage.py`. Upstream references supplied the initial
text and relationships; later corrections are made in the catalogs, with their field provenance.

The database ships as compressed pages in load-on-demand data addons. Questie and QuestieDB are not
runtime dependencies. Translation coverage varies by language and field.

Import/update/resync follows [one documented policy and pipeline](import-resync.md).
Actual source builds/revisions live in field provenance and verified run manifests; a
single historical snapshot listed in this guide is not an applied baseline. Quest relationships
do not establish indexed client objective text. Existing captured objective translations remain
accepted even when upstream localization evidence is missing.

Every component below has the prefix **Forever Rosetta Stone -**. These eight components
define the product scope; individual settings are separate from this list.

| Component | Maintained catalog | Component scope |
| --- | --- | --- |
| **Quest panel** | `quests/`; reward names from `items/` | Title, summary, live objective progress, Description, and client rewards, with native styling, scrolling, and gamepad behavior. |
| **Quest tooltip** | `quests/` | Companion to the **right** of quest-log and chat-link tooltips. Commands remain in the original tooltip. |
| **Quest tracker tooltip** | `quests/` | Hover or gamepad focus, showing the translation to the **right**, using the tracked quest ID and live progress. |
| **Location tooltip** | `areas/` and `maps/` | Names keyed by AreaTable ID or UI map ID. Companion to the right of the location header when space permits, omitting its **World Map** hint. |
| **Item tooltip** | `items/`; owned recipe/output links in `spells/` | Translated companions outside the native comparison block when the complete row fits, including equipped headers, live stat changes, recipe outputs and reagents with verified ID relationships. |
| **Spell tooltip** | `spells/` | Translated companion beyond the native tooltip on the same side of the hovered button. |
| **Talent tooltip** | `spells/`; `talents/` remains exposed through its DB2-ID API | Translated companion using the native talent's spell ID for runtime name lookup. |
| **NPC tooltip** | `npcs/` and shared tooltip labels | Creature names and supported tooltip details, using the hovered creature/vehicle GUID. Player and custom pet names remain native. |
| **NPC dialogue options** | `gossipoptions/` | Companion tooltip for hovered or controller-focused menu entries, keyed by the live gossip option ID. Unknown options keep their native text. |

### Share one catalog per entity type

Forever Rosetta Stone's database contains **one catalog per entity type, keyed by entity ID and locale**.
All components read the same catalogs. A component does not own a separate copy of its translations.

DB2 Talent IDs, live talent API IDs, spell IDs, AreaTable IDs, and UI map IDs are separate
namespaces. The catalog's retained source build and relationships do not guarantee live ID
correspondence. Rank spell IDs and live override names require reconciliation before runtime use.

| Catalog | Identity and shared relationships | Consumers |
| --- | --- | --- |
| `quests` | Quest ID; localized title, summary, Description, and ordered objective labels, with target IDs | Quest panel, quest tooltip, and quest tracker tooltip |
| `items` | Item ID; localized name, including recipe items | Item tooltip and quest reward names |
| `areas` | Area ID; localized zone/subzone name | Location tooltip and location displays |
| `spells` | Spell ID; localized name | Spell tooltip and linked talent spell names |
| `shapeshiftforms` | SpellShapeshiftForm ID; localized name | Owned spell form/stance requirements |
| `itemsubclasses` | ItemSubClass record ID; localized verbose name | Owned spell equipment requirements; distinct from the class/subclass pair |
| `itemlimitcategories` | ItemLimitCategory ID; localized name | Unique and unique-equipped category rows |
| `holidaynames` | HolidayNames ID; localized name | Item holiday and appearance restrictions |
| `locktypes` | LockType ID; localized name | Item lock requirements with live skill ranks |
| `sharedstrings` | SharedString ID; localized client text with an optional semantic usage | Recognized talent purchase-gate messages are omitted from translated talent blocks |
| `talents` | Talent ID; localized name and linked spell ID | Talent tooltip |
| `npcs` | NPC ID; localized name | NPC tooltip and quest target names |
| `races` | `ChrRaces.ID`; localized `name` and optional `nameFemale` | Player tooltip race rows, matched with live `UnitRace` IDs and `UnitSex` |
| `gossipoptions` | `C_GossipInfo.GetOptions().gossipOptionID`; localized name | NPC dialogue option tooltip; separate from the button's `orderIndex` |

Entity files use `locales[locale]` for translated fields and keep minimal field metadata inline.
The common reader exposes `catalogs.<entityType>[id].locales[locale]` for tools and builds.
Store locale-independent relationships once on the entity record, outside `locales`.
For example, a talent keeps its linked spell ID once.
Spell `tooltipData.requiredForms`, `requiredReagentItems` and `createdItemIDs` bind visible
requirements and nested output blocks to owned records. Item `recipeSpellIDs` bind crafted
items to verified recipe spells. These positive ID lists retain source metadata and do not
store live quantities. The renderer validates the native text against those owners before
using their target names; missing or ambiguous relationships preserve the native row.
Item restrictions use `limitCategoryID`, `boundAreaIDs`, `requiredHolidayNames`,
`requiredTransmogHolidayNames` and `requiredLockTypes`. Instance map IDs first resolve through
`Map.AreaTableID`; they never enter the UI-map namespace. Spell `requiredItemSubclasses`
contains ItemSubClass record IDs selected by the verified equipped-item class/subclass mask.
Names stay in their corresponding catalogs, and displayed counts/ranks remain client values.
Talent purchase-gate formats are selected by verified `TraitCond.SpendMoreSharedStringID`
relationships and tagged `usage: "talentPurchaseRequirement"`. Their complete localized
formats identify only the contextual purchase message. The translated talent block omits
these messages; the native tooltip, rank, descriptions and next-rank preview remain intact.
Unknown lines still preserve native text and can trigger the incomplete-translation notice.
The same omission policy covers the owned GlobalStrings for preceding talents, named-talent
prerequisites and tier/row point gates, in the native client language rather than the target language.
JSON uses decimal string keys for IDs; generated pages use numeric IDs. One generated TOC
contains compressed column pages by entity type and locale, including English.
UI map names live in `maps/`, with shared configuration in `areas/metadata.json`; UI map IDs are never treated
as AreaTable IDs in `catalogs.areas`.

Resolve shared item, NPC, and spell names through their catalogs instead of copying them into
each component's data. Keep authored quest summaries and literal objective labels as quest text,
including scripted objectives that cannot be derived from an entity name. Retain supporting
game-object relationships and text needed by quests in their catalog records.
UI headings and gamepad instructions belong to separate locale strings, keyed by message name.

### Language coverage

The quest catalog's `metadata.json` declares available locale IDs in `document.locales` and additional
language names in `document.rosettaLocales`. Locale presence does not establish complete translations. Names and prose
can have different coverage, and missing fields remain absent.

Preserve supported regional variants such as `esMX` and `zhTW`. English targets use only `enUS`;
`enGB` is not a supported target locale. Historical source provenance may retain `enGB`.
Portuguese uses `ptBR`. Do not silently substitute another locale or count an upstream
English fallback as a translation. A proper name can legitimately match English, so equality
alone is not grounds for rejection. Blank values and placeholders must not fill translation gaps.

### Keep translated text separate from live values

An **objective summary** is the instruction paragraph, such as bringing the Stone of Relu to
Flagongut. **Objective lines** are the individual targets and their progress, such as
`Stone of Relu: 0/1`. The **Description** is the long narrative below its heading.

The three quest components share one translation catalog keyed by quest ID and target locale.
The game client supplies progress, completion state, actual reward choices, quantities, XP,
money, icons, and usability. Forever Rosetta Stone's locale strings supply translated headings and instructions.
Static reward data must not replace the rewards the client actually offers.

QuestieDB's relationships identify quest targets and required/source items; reward item IDs
come from the live client. Preserve objective order and literal objective text where available.
Some scripted objectives are free text and cannot be reconstructed from an item or NPC name.
Missing summaries, descriptions, or labels remain absent in the catalogs.

### Build and runtime boundaries

The flow is **root catalogs → load-on-demand data addons → Lua API**.

| Artifact | Contents | Shipped with the addon? |
| --- | --- | --- |
| `catalogs/**/*.json` | Maintained text, relationships, locale definitions, field origins, and source provenance | **No** |
| `tools/build/runtime_catalog.py` | Runtime field selection, AI-flag derivation, and quest exclusion rules | **No** |
| `tools/build/database_storage.py` | Column layout, page limits, packed AI flags, and reverse-name indexes | **No** |
| `tools/build/database_packs.py` | Small TOCs and Lua payload files for load-on-demand data addons | **No** |
| `tools/build/build-lua-database.py` | Catalog loading, version hashing, encoding, and TOC generation | **No** |
| `tools/build/addon-manifest.toc` | Maintained addon header and load order | **No** |
| `tools/build/encoding/` | Offline CBOR codec and metadata writer, with QuestieDB credits and retained license notices | **No** |
| Main addon TOC | Catalog version, locale names, pack inventory, and UI load order | **Yes** |
| `ForeverRosettaStone_Data_*` | Compressed translation pages for one language | **Yes** |
| `ForeverRosettaStone_Rules` | Shared item and spell facts, including effects, durations, and set relationships | **Yes** |

The main addon reads its small manifest through `C_AddOns.GetAddOnMetadata`. Preferences load
only the selected translation pack through `C_AddOns.LoadAddOn`. Compressed page strings live
in each data addon's `data.lua`, not in TOC metadata, so unused packs do not retain their payloads.
Switching languages loads the new pack immediately; earlier packs remain loaded until `/reload`.
Keep all generated data-addon folders beside `ForeverRosettaStone` in `Interface/AddOns` and enabled.
Adding these folders to an already running client requires a full game restart for discovery.

Tooltip rendering loads the selected translation pack, the client-language pack needed for original
source templates, and shared item/label rules. It does not load unrelated language packs. Diagnostics use these same localized records rather
than shipping a duplicate non-AI subset. Each pack must
match the main addon's catalog version; missing, disabled, or mismatched packs report an error.

Only the small locale manifest decodes at API load. A lookup uses native `C_EncodingUtil` to decode
a small page directory and its matching page. Pages contain at most 128 records
and 64 KiB of uncompressed CBOR, unless a single record itself exceeds that byte budget.
Names and quest fields use flat columns rather than a table per stored record. AI flags use
one bit per record. This storage layout preserves the public record model.
`enUS` is the sole English dataset and language choice. Catalog locale inputs reject `enGB`;
English source provenance can still retain its actual historical language identifier.

The runtime retains compressed strings for packs used during the session and at most eight decoded
pages across all kinds, locales, shared rules, and reverse indexes,
evicting the least recently used page. Quest records are materialized only when requested and
weakly cached; callers holding a record retain its identity across page eviction. Callers can
retain additional records, so the page-cache bound is not a bound on all consumer memory.
Quest-title and area-name indexes are generated offline and paged separately; resolving one name
does not scan or decode the full quest/area dataset. Small page directories remain cached.

There is no runtime compiler or SavedVariables database. Manifest generation reuses the pinned
upstream CBOR and chunk-writing helpers under `tools/build/encoding/`; those build helpers are not
loaded by the addon.

Catalog changes are explicit edits followed by a database rebuild. No source aggregation,
automatic import, or upstream sync participates in the build. External references can establish
a correction, but they must not overwrite unrelated records or manual fixes.

Each component selects Forever Rosetta Stone's target locale through the public API. If no accepted translation
exists, it applies its documented missing-text behavior. For an NPC name companion, that means
retaining the native tooltip without a translation companion.

### Build the bundled database

Root `catalogs/` contains one maintained JSON source file per entity:

- `catalogs/quests/<questID>.json`: edit `locales[locale]` for quest text.
- `catalogs/<kind>/<id>.json`: edit localized names and text under `locales`.
  Geographic map names live in `catalogs/maps/`, separate from `catalogs/areas/`.
- `catalogs/<catalog>/metadata.json`: catalog configuration only.

Fix text and add missing records in these JSON files. For batch updates, follow the
[agent assignment workflow](../catalogs/AGENTS.md#assign-bounded-batches-to-agents), then rebuild once:

```sh
uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
uv run --no-project --with lupa==2.8 python tests/python/test-lua-database.py
uv run --no-project --with lupa==2.8 python tests/run-tests.py --unit-only
git diff --check
```

The DB builder reads entity files and catalog configuration. It writes `ForeverRosettaStone/ForeverRosettaStone.toc`
and the language folders (`enUS/`, `frFR/`, etc.) plus shared `Rules/` under `ForeverRosettaStone_Data/`.
Release packaging maps each language folder to `ForeverRosettaStone_Data_<locale>/` and `Rules/`
to `ForeverRosettaStone_Rules/` beside the main addon at the ZIP root. Installed
addons must also remain directly under WoW's `Interface/AddOns/`, without the repository's `ForeverRosettaStone_Data/` wrapper.
It does not collect external data or rewrite the JSON. Original snapshots, supplements, reports,
and import scripts are not part of the maintained repository.
The maintained addon header and load order are in `tools/build/addon-manifest.toc`; edit that template
rather than the generated TOC. `catalogVersion` hashes the normalized quest and name inputs;
`apiVersion` is 3 and the storage format is 8. The version hash includes the storage format.
Rebuilding does not collect data or translate text.
The workflow after the initial import is **edit JSON → rebuild DB**.
For load-order changes only, `python3 tools/build/build-lua-database.py --manifest-only`
refreshes the manifest while preserving existing database metadata. Use `--output` to target an installed TOC.
Catalog maintenance instructions and external source references are in `catalogs/AGENTS.md`.
The catalogs retain field origins, source identifiers/languages, and useful source revisions,
builds, or text fingerprints. Credits, licenses, and upstream references live in
[`ForeverRosettaStone/notices/catalog-credits.md`](../ForeverRosettaStone/notices/catalog-credits.md).

Numeric source constraints:

- Spell 3110's scaling evidence is client hotfix push `113766`, record `681913`, build
  `1.60.1.70888`, French client; its level data references `SpellLevels` record `98498`.
  Firebolt base values for spells 3110, 7799, 7800, and 7801 also have Wowhead Forever evidence.
- Spell 1316697 has catalog base value 25 and coefficient 0.2002, while the level-60 tooltip
  observation shows 60. Per-level scaling is unverified and must remain absent until captured.
- Effect values for spells 5785, 1283034, 1283073, 1283086, 1312870, and 1315878 originate
  from the English `SpellEffect` table in client build `1.60.1.70888`.

Every catalog text field retains `translationMetadata.fields[field].origin`, with value `original`,
`community`, or `ai`, plus minimal source metadata. No duplicate boolean is stored in the catalogs.

The runtime model is owned by `tools/build/runtime_catalog.py`:

| Runtime record | Exported fields |
| --- | --- |
| Quest, keyed by ID and locale | `title`, `summary`, `description`, `eventObjectiveLabel`, `objectiveLines`, `hasAITranslation` |
| Item or spell, keyed by ID and locale | `name`, available target-language `details`, `hasAITranslation` |
| NPC, area, map, or talent, keyed by ID and locale | `name`, `hasAITranslation` |

The builder validates field origins and computes `hasAITranslation` from the text actually exported.
English detail API records combine localized templates with structural dependencies;
shared facts are stored once in the rules pack and combined with text when requested.
Other locales contain only available translated detail fields, without duplicating those dependencies.
Diagnostics read the client-locale catalog through the ordinary ID-based getters and label it
as catalog text, which may contain AI translations. Source-only getters and reverse-name APIs
are not exported in API version 3.
The tooltip renderer does not use these getters to match native text or select a translation.
Detailed metadata and quest relationship records are not shipped. The API does not export
`GetTranslationMetadata`, `IsFieldAITranslated`, or `GetQuestRelations`.
Verified client item-objective mappings are compiled into `objectiveLines` using the same-locale
item catalog names, preserving authored templates and live client counts without shipping relationships.
Ordinary objective-target positions are never treated as verified client indices.
Other objectives require an authored client-index template or a supported event label.
Unmapped indices, mismatched objective types, missing translations, and unavailable required live
values retain native text. Item names and displayed counts are not reverse-matched to choose templates.

Quests marked `test`, `notImplemented`, `placeholder`, or `unused` are omitted from runtime rows,
locale blocks, and ID indexes. `temporarilyDisabled` quests remain available. Maintained entity
JSON files remain unchanged by generation.

`ForeverRosettaStone/database/database-api.lua` owns lazy lookup and caching; `quests/quest-data.lua` combines
DB text with live client progress. `tests/python/test-lua-database.py` covers export and lookup contracts;
`tests/lua/test-database-integration.lua` exercises rendering with real generated quest records.

Item/spell details retain localized description templates and normalized owned dependencies with
their catalog provenance. `GetItemDetails` and `GetSpellDetails` return shared read-only records.
`GetItemRules(id)` and `GetSpellRules(id)` read locale-independent facts from the shared rules pack
without loading translations or native source text. Formula rendering combines those facts with
the selected locale's description; missing required values retain native text.
Settings offer Stacked translations (the default) and separate tooltips for items, spells, talents,
quests, NPC names and minimap locations. Available item/spell details translate supported
text in both columns. Sell-price rows use the live price and available target label.
Live quest objectives use the same translated progress rows as the quest panel.
Name only suppresses translated details in both layouts. Surfaces
without a native tooltip, including quest offers and tracker rows, keep a separate translation.
Mount and companion summon tooltips use their spell records and the selected layout. Battle-pet
species tooltips without standard tooltip rows retain their separate display. Appearance tooltips
resolve the displayed transmog source to its item ID and translate available shared labels.
Group finder hover/focus translations use `activities/<GroupFinderActivity.ID>.json` and the row's
activity ID; instance map IDs never index the UI map catalog. Captured client fixtures come from a French
client; coverage stages declare their target locales and any client-format inventories explicitly.

Item, spell, and talent translations appear beyond the native tooltip on its side of the hovered target.
In Separate mode, NPC translations use their selected position around the native tooltip. Edge exceptions and comparison rows temporarily adjust native
screen-clamping settings to preserve the pair order; closing or rebuilding restores those settings.
During combat, when protected native tooltips cannot accommodate outer translations, those translations appear in a
separate row above or below them when space permits. Translations that collide or cannot fit on screen
are hidden without changing the original frames.

`tooltips/tooltip-descriptions.lua` selects entity records using the client-provided ID and supported
row types. `tooltips/spell-live-values.lua` is the single description engine for spells, talents,
auras and linked item effects. It reads the maintained source-language template and selected target
text from the catalogs, captures the values actually displayed by the client, localizes those
values, and inserts them into the target template. Expressions are opaque displayed results;
character stats, spell coefficients, trait ranks and aura points are never used to recalculate them.

Tokens retain their complete identity, including case and referenced spell ownership. Reordered
or repeated tokens keep their values; compatible effect-index changes are aligned by sorted index.
Durations, ranges, decimal precision and plural forms are localized. Description and aura references
resolve their own catalog fields. Aura timers use the displayed remaining time, not expiration math.

Description variables have typed inputs rather than an unrestricted text wildcard:

| Family | Input and behavior |
| --- | --- |
| `$z` | Requires the readable name returned by `GetBindLocation()`, and verifies it against the displayed description. The name stays in the client's language; this API does not provide an area ID. |
| `$@spellicon<ID>` | Retains the displayed texture/atlas markup, bound to the catalog reference. If the native description contains no icons, none are generated. Arbitrary text cannot fill an icon slot. |
| Numeric slots, including `$H`, `$N`, `$R`, `$R1`, `$c`, `$rad#` / `$rad`, and bare numeric markers | Require a displayed number or numeric range. No meaning, quantity or character formula is inferred from the token's name. |
| Modified slots such as `$m~1` | Preserve the modifier in the token identity; capture the displayed result without evaluating the modifier. |
| Indexed slots followed by text, such as `$t2seconds` | The numeric index ends the slot; the suffix remains owned catalog prose. Bare unknown identifiers are still rejected. |
| Plural and gender forms containing slots | Recursively compile the selected form. Plurals must have a visible controlling quantity before or inside the form, and are checked against each locale's rules. An omitted quantity is not invented. |
| `$@expandkey[…]` | Match the expanded block, the collapsed client hint, or an empty block against the native description. The hint and modifier labels come from owned GlobalStrings. Do not infer the captured state from current keyboard state. |

Conditions accept whitespace between branches. Recursive references, branches and forms retain
the depth and search limits. Literal-prefix checks prune branches that cannot match the native
description before trying further conditions. Target paragraphs and inline icon line breaks are
preserved. Debug hyperlink previews rebuild on modifier changes so the client can refresh its
expanded description. Unsupported or malformed references (`$@auracaster`, `$@auradesc`, `$@spelltooltip`,
`$@null`, `$@spellaura` without an ID), doubled dollars, incomplete grammar, and unbound text
variables still keep the native description. Recognizing a token alone does not prove that the
referenced fields, source/target slot bindings, client grammar or translations are available.
The French `|2` grammar directive is not implemented by this description parser; descriptions
whose native output expands it differently still fail closed.

Item effects require typed rows, readable spell IDs, and verified links from the owned item record.
Auras require a readable matching aura spell ID; their templates remain separate from cast descriptions.
An absent source template or translation, unsupported syntax, conflicting values, or ambiguous match
preserves native text and marks the translation incomplete. There is no static/calculated fallback.
Quest prose, objective progress and live rewards retain their separate quest pipeline.

Typed item usage requirements combine the shared GlobalString format with the selected item's
owned class IDs or required-skill category binding. Names come from the class/category catalogs;
the required rank comes from the displayed row. Source names must match those owned records.
Missing, conflicting or unbound names remain native, without a global reverse-name scan.

Recognized client-label formats can retain their readable displayed mana cost, armor, block,
durability, and cooldown values. Sell price uses the native tooltip's `price` for the actual item
context. Those label formats do not identify entity descriptions or infer item-effect links.
Full translated tooltips retain unrecognized rows and flag unresolved visible text; numeric-only
and decorative rows do not trigger that warning.

`tests/python/test-id-only-matrix.py` retains ID-based entity selection. Spell and item-effect cases
now supply synthetic client text from maintained catalog templates with controlled displayed values
unrelated to static spell rules. The independent `tests/python/live_spell_fixture.py` prepares source
text and target expectations without evaluating formulas or calling the production capture engine.
The runtime is checked against those expectations, including incomplete/native fallbacks. Missing
source evidence, target text, unsupported fixture grammar and unverified row identities stay failed
coverage cases. Source/reverse identity lookups and character-stat recalculation are blocked.
Quest checks retain their structured-data contract. Recorded client examples are tested separately
from synthetic inputs. These checks do not establish universal tooltip parity, complete translations,
linguistic accuracy, or in-game appearance.

Tooltip coverage checks run as part of `tests/run-tests.py`:

- `tests/python/test-tooltip-client-labels.py` checks an explicit client-label inventory against checked-in
  build-matched GlobalStrings fixtures and exercises isolated rows across official source/target pairs.
  Generated values and individual format cases do not establish complete live tooltip coverage.
- `tests/python/test-item-subclasses.py` checks target class/subclass labels against build-matched fixtures.
  The Italian source export is identical to English and is excluded.
- `tests/python/test-rosetta-tooltip-locales.py` checks the shared-label inventory, format arguments and
  subclass IDs for configured target locales. Custom target maps and Italian replacements are AI-authored;
  these checks do not establish linguistic accuracy or entity-description completeness.
- `tests/lua/test-whole-tooltip-rendering.lua` checks exact complete row sequences for supported item,
  spell, talent and quest examples, including unknown rows and missing target text. These are controlled
  fixtures, not captured in-game tooltips. Presentation-mode checks remain in the addon harness.

The seven additional Forever Rosetta Stone languages have AI-authored shared tooltip-label and subclass maps.
Italian shared labels also have AI-authored replacements for the incomplete client export.
Item/spell detail availability depends on each entity's localized fields. Some official source exports
contain English fallback text; the presence of a configured language or a passing renderer test does
not establish complete or linguistically verified translation.
The label inventory also reports client stat formats whose use by this client is unverified.

Generate a field-presence report for all configured targets, with explicit per-field denominators, using:

```sh
python3 tools/catalogs/catalog-coverage.py --require-complete --output dist/catalog-coverage.json
```

This command exits nonzero while inventoried target text is missing. It checks retained catalog records,
not every entity in the game, linguistic accuracy, or in-game appearance. Catalog completeness and
renderer correctness are separate checks.
WoW API mocks and small unit-test fixtures stay in tests. The localized missing-quest apology,
including its fictional beer reward, is deliberate UI content rather than a replacement quest record.

Focused footprint checks run with:

```sh
uv run --no-project --with lupa==2.8 python tests/python/test-lua-database.py \
  DatabaseTests.test_first_lookups_decode_small_pages \
  DatabaseTests.test_name_page_cache_has_bounded_retained_memory
```

These check decoded byte volume and retained Lua 5.1 heap in the offline harness. They do not
measure native Forever decode latency, frame time, or the client's memory used to hold TOC metadata.

### Maintain catalog text

Use [the import/resync reference](import-resync.md) for source priority, language rules and
the prepare/apply/verify process. Source-driven updates must use that pipeline.

For a source update, first establish changed provider/ID/locale/field tuples against the
last successful pinned run. The [bounded update handoff](../datasources/corpus/README.md#bounded-update-handoff)
describes the offline planner and mandatory review steps. Keep local fixes out of an unchanged
source scope, and resolve actual conflicts explicitly. Queue only affected entities, check
changed meanings in each configured target language, and reuse verified matching text before
authoring. Preserve field origins, source locale, placeholders and unrelated records. Save
source and target fingerprints and accepted results so interrupted work can be revalidated.

For numeric-only spell updates, review the build-matched Wago snapshot and run
`python3 tools/catalogs/refresh-spell-values.py --snapshot datasources/imports/wago/BUILD --output datasources/imports/RUN/numeric --ids ID`.
Review `report.json`, including skipped entries, and `updates.patch` before applying. Use
`--replace-existing` only for reviewed replacements. This command produces no text translations;
its ID filter still loads and indexes required snapshot tables and enumerates spell filenames.
After all accepted text, numeric and capture changes, build once and run the required checks.

Edit only the requested entity IDs, locales, and fields. Keep locale-independent relationships
outside `locales`, preserve explicit gaps, and retain the actual origin of every text field.
AI-authored or AI-adapted wording has `origin: "ai"`; reusing community or native text keeps its
established origin. Objective templates must preserve their interpolation tokens and verified
client indices. Ordinary objective-target positions are not client objective indices.

Additional language IDs and native names live in `catalogs/quests/metadata.json` under
`document.locales` and `document.rosettaLocales`. There is no separate language-import manifest.

Consult [catalog maintenance instructions](../catalogs/AGENTS.md) for field contracts and external
references. Check the exact entity, quest stage, locale, field, and Forever build before accepting
a correction. Keep attribution and license notices in `ForeverRosettaStone/notices/`.
Do not add another import layer or regenerate a catalog from an upstream dataset.

For manual item/spell build checks, reference downloads and field diffs, use the
[Wago reference workflow](../datasources/wago/README.md). It keeps raw exports untracked
and never changes the maintained catalogs automatically.

The catalogs are a maintained snapshot. They do not establish complete translations for every
Forever entity or supply live quest progress, reward values, or completion dialogue. Live talent
tooltips use native spell IDs; the DB2 talent-ID API remains separate. Standalone provider packaging
and publishing remain separate work.
