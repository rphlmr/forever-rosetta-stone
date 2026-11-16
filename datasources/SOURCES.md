# Finding fresh catalog sources

Run commands from the Forever Rosetta Stone repository root unless stated otherwise. Git and Python 3
handle source downloads; the orchestrator uses bounded requests and subprocesses.
The addon builds/tests use `uv run --no-project --with lupa==2.8 python ...` as documented
in `catalogs/AGENTS.md`. No original imports, ignored snapshots, WoW installation, API
credentials, or previous chat are required to edit and validate existing catalogs.

## Choose the source before fetching

Start with the requested entity files and existing translations. For new evidence, use the
row matching the field. Prefer an exact matching build/locale over an unrelated newer snapshot.
Preserve manual fixes and check applicability before accepting any upstream difference.

For source priority, official/additional-language decisions and preservation of accepted
translations, follow [the import/resync policy](../docs/import-resync.md). The table below
owns provider/field coverage; a provider does not supply every field.

| Need | First source and useful fields | Limits / next source |
| --- | --- | --- |
| Book identities and page chains | VMaNGOS Vanilla patch-10 item/object owners and page links; reconcile with Wago `ItemSparse.PageID` and EG `object_details.enUS` | Identity-only codex; VMaNGOS is a reference, not proof of Forever text or reachability. Conflicts, missing/cyclic/shared links remain visible. Explicit `--book-texts` also reads VMaNGOS page/locales and wording-matched EG book captures, with provenance and unresolved cases. See [workflow](books/README.md). |
| Item names and flavor text | Wago `ItemSparse`; `Item` for shared identity/class facts | Server-only names may appear in EG Link `item_hotfixes.<locale>`. QuestieDB supplies additional community item names. |
| Spell names and text | Wago `SpellName` and `Spell`: name, cast description, aura description, rank | Fetch effect/range/duration dependencies only when relevant. Rendered live values are not replacement templates. |
| Spell rendered description evidence | Blizzard Forever `/data/wow/spell/{id}` with its actual resolved namespace and locale | Keep API prose and values as source evidence. A missing leading percentage token may be reconstructed offline only when native template locales unanimously agree on token identities/order and API quantities, and the target's existing token tail independently matches. Record `tokenDerivation` and witness locales; never claim a raw cache template or ship API values as live constants. |
| Malformed spell conditional syntax | Owned native templates in other official locales, plus scoped Blizzard response evidence when available | A unique missing delimiter or displaced predicate-adjacent literal may be normalized only when native witnesses agree on the exact predicate and branches. Preserve all prose and token identities, and record the original template hash and derivation. A normalized translation template is not proof that broken native client output is decodable. |
| Alternate spell description wording | Exact same-field canonical English in verified native Spell records | Reuse only concordant native target wording with explicit donor provenance. Store it in the owner's `descriptionVariants` / `auraDescriptionVariants`, with indexed field metadata and a canonical-English SHA-256 guard. Keep the primary native text. Runtime selection still requires complete matching, exact slot binding and one unambiguous result; variants cannot supply hidden values or discard unmatched quantities. |
| Spell equipment requirement labels | Wago `ItemSubClassMask`, joined to the exact `SpellEquippedItems` class/subclass-mask signature, with owned `GlobalStrings` equipment formats | Verify against complete native requirements before composing missing localized labels. A nonzero inventory mask needs its own evidence. Keep names and format provenance in the owned spell field; never infer equipment identity from text. |
| Recipe tool categories | Wago `SpellTotems.RequiredTotemCategoryID_*` → `TotemCategory.ID` / `Name_lang` | Keep category IDs separate from item IDs; name-to-item cache lookups cannot identify tools the player has never carried. |
| Recipe tool items | Wago `SpellTotems.Totem_*` → owned `items/<ItemID>.json` names | Direct item tools are a separate relationship from categories; unowned items stay native. |
| Item effects and set text | Wago `ItemXItemEffect` → `ItemEffect` → spell; `ItemSet` and `ItemSetSpell` | Follow IDs rather than guessing links from similar names. See the Wago table guide. |
| Item restrictions | Wago `ItemSparse.LimitCategory` → `ItemLimitCategory`; holiday fields → `Holidays.HolidayNameID` → `HolidayNames`; `LockID` → `Lock` skill entries → `LockType` | Localized labels have separate catalog owners. Counts and ranks remain live. `ZoneBound_*` are AreaTable IDs; `InstanceBound` is a Map ID resolved through `Map.AreaTableID`, not UiMap. |
| Spell equipment requirements | Wago `SpellEquippedItems` class and subclass mask → `ItemSubClass.ID` / `VerboseName_lang` | Keep record IDs separate from class/subclass numbers. A source mask does not establish an otherwise unsourced composite label such as “Ranged Weapon”. |
| NPC names | EG Link `creature_details.<locale>` for exact server text, when covered; otherwise QuestieDB Forever locale lookups | Window/observation datasets may mix client languages. A translated NPC name does not establish quest text. |
| NPC faction identity | QuestieDB composed Forever `Npc.factionID` → Wago `FactionTemplate.ID` → `FactionTemplate.Faction` | Questie's field is a template ID, not a Faction ID. Its faction-template support dictionary contains enemy groups, not faction-name IDs. EG Link `creature_details` does not supply this relationship. Preserve native text for missing or stale mappings. |
| Faction names | Wago `Faction.Name_lang`, keyed by Faction ID; owned `catalogs/factions/` records retain translations | Catalog records do not use `sourceNames`. Missing translations stay absent. Existing faction targets retain their original/community/AI field provenance. |
| Creature type and class labels | Wago `CreatureType.ID` / `Name_lang` and `ChrClasses.ID` / `Name_lang` | Use IDs returned by `UnitCreatureType` and `UnitClass`. IDs are not contiguous. Existing NPC type labels and quest class labels supply additional-language translations. Translate only semantically identified rows; untyped rows remain native. |
| Player race names | Wago `ChrRaces.ID` / `Name_lang` / `Name_female_lang`, owned in `catalogs/races/` | Use `UnitRace` IDs and `UnitSex`; preserve the native row when a required translation or variant is missing. Player names remain verbatim. |
| Quest titles and descriptions | Blizzard Forever quest web API, with its resolved namespace and actual language slots | Questie supplies missing titles. The web endpoint supplies no summaries; Italian is not an official Forever language. |
| Quest summaries | QuestieDB composed Forever data and locale base/trace tables | Use actual summary prose, never invent a summary from relationships or join ambiguous objective rows. |
| Quest starters, finishers, targets, item relationships | QuestieDB composed Forever static data, checked against exact-build server observations | Raw base files omit later corrections. Relationships do not establish client objective indices or wording. |
| Indexed quest objective text | Existing local in-game scan captures or an exact client report | Source relationship positions do not establish client objective indices. Verify indices and placeholders separately. |
| Flight destination names | Wago `TaxiNodes.Name_lang` | `TaxiNodes.ID`, resolved from the live taxi slot via `C_TaxiMap.GetAllTaxiNodes`. Never treat a slot as a node ID. |
| Area/map names | Wago `AreaTable` for areas/parents; `UiMap` for UI map names | Separate ID namespaces. Use `--tables AreaTable UiMap`; do not infer one ID from the other. |
| Profession section names | Wago `TradeSkillCategory.ID` / `Name_lang`, owned in `catalogs/professioncategories/` | Use the live category ID, never infer it from translated names or recipe IDs. |
| Group finder activity names | Wago `GroupFinderActivity.ID` / `FullName_lang`, owned in `catalogs/activities/` | Use the row's live activity ID; do not treat its instance MapID as a UI map ID. |
| Talent identity and name | Wago `Talent` for rank spell links, then `SpellName` | DB2 Talent ID and live talent spell ID differ. Do not index `talents/` with a live spell ID. |
| Community target languages | Maintained catalog translations, active GitHub community projects, and retained one-time seed text | GitHub projects and four CurseForge sources are refreshable; see the active registry. Preserve text, authorship, provenance and notices. |

For verified native text use `original` origin; QuestieDB/community translations use
`community` unless the source declares AI authorship. AI adaptations use `ai`. EG Link's
compilation credit still belongs in notices when retaining native game text. Never identify
English fallback as a native translation. Absent fields stay absent.

## Fetch current sources

Use the [datasource refresh guide](README.md) for Blizzard credential setup,
the single refresh command, saved version pins and exact offline rebuilds. Run
`uv run --no-project --with lupa==2.8 python datasources/refresh.py` from the repository root.
The orchestrator fetches Questie, Blizzard, Wago and EG NPC/item data into a new ignored
`datasources/imports/` run, then builds and verifies SQLite. It writes new runs without overwriting existing inputs.

Blizzard's resolved Forever API namespace is independent of the latest Wago client build.
Keep each provider's actual version; never relabel one as the other. Questie is exported
with authored Forever corrections and base/trace localization. EG Link quest inputs are
not fetched or accepted. Its NPC/item inputs retain Efficient Games' CC BY 4.0 credit.

A refresh does not edit catalogs. Use its generated `sources.json` for an offline rebuild;
use `pins.json` to request the same upstream versions in a new run. Historical scan paths
below are retained evidence, not inputs to the refresh. New scans and analysis belong under
`datasources/imports/` when separately requested.

## Local development tools

Optional in-game collectors live under `tools/quest-scan/` and `tools/source-scan/`.
They are separate development tools and are not part of a source refresh or catalog sync.
Their generated inputs and captures belong under `datasources/imports/`. Never ship them
with the addon or start an in-game collection without an explicit request.

## Blizzard API and remaining gaps

Blizzard OAuth setup and collection are documented in [datasources/README.md](README.md).
Responses are retained unfiltered and hash-checked before SQLite ingestion. Missing quests,
empty description fields and language fallbacks remain gaps; do not substitute summaries for
full descriptions. Verified Forever pages or explicit client captures can support separately
requested investigations. Never start an unattended in-game collection to fill gaps.

## Apply only the requested change

Reference downloads do not edit catalogs, establish translation coverage, or advance an
applied baseline. Use `catalogs/AGENTS.md` for edits, inline origins, notices, placeholder
checks, and the final build/tests. Keep snapshots and resumable results under ignored
`datasources/imports/`. Print selected IDs/fields, not complete exports, and stop once the requested
evidence and validation are sufficient. Report unavailable sources and missing languages.

Before comparing catalog text or preparing updates, rebuild and verify the SQLite reference
corpus from these freshly selected sources as described in `datasources/corpus/README.md`.

## Additional-language community sources

The active community registry is documented in [README.md](README.md). It includes ClassicUA,
Czech Forever, PolishForever, three Italian projects, WoWLang's supported Polish/Turkish/Ukrainian
quest tables, a Turkish Vanilla/OctoWOW quest dataset, and the CurseForge projects
Forever Translated Polish, Världen av Krigskraft and ForeverTR. Each retains raw text and full
upstream notices. No additional target locales are introduced by selecting a multi-language project.

Classic community text can supply terminology and context for additional languages. A matching
entity ID alone does not establish that Forever uses the same meaning. Keep explicit English
source guards, version/server identity, fingerprints, authorship and attribution with candidates.
Unsupported placeholders and unclear reuse rights remain visible flags; do not guess them away.

No usable Croatian content dataset was found. The Danish lead currently supplies addon UI labels,
not our quest/item/spell fields. Czech Forever, Forever Translated Polish, Världen av Krigskraft and ForeverTR discover
the latest approved public Forever release on CurseForge without a Core API key.
