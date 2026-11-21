# Rosetta catalog maintenance

## Source of truth

Each entity has one maintained, human-editable JSON source at `catalogs/<kind>/<decimalID>.json`.
All catalog JSON, including metadata, uses `catalog_storage.dump_json`: UTF-8, two-space
indentation, recursively sorted keys and one final LF. Preserve array order and all string
contents. Run `python3 tools/catalogs/format-catalogs.py --write [paths...]` after edits;
`--check` validates the whole catalog tree in CI. VS Code's built-in JSON formatter is
configured to preserve this layout on save; use the format task after inserting unsorted keys.
Kinds are `quests`, `items`, `npcs`, `areas`, `maps`, `spells`, `talents`, `factions`,
`creaturetypes`, `classes`, `races`, `globalstrings`, `professioncategories`, and `activities`.
Race records use `ChrRaces.ID` from `UnitRace`; `name` and optional `nameFemale` retain
the exact `Name_lang` and `Name_female_lang` client text with separate field provenance.
The runtime selects `nameFemale` when `UnitSex` is 3. Missing variants stay native.
Profession category names use `TradeSkillCategory.ID` from the client API; keep them
separate from recipe spell IDs. Their localized `name` and field provenance live in
`professioncategories/<categoryID>.json`. Missing languages remain absent.
GlobalStrings use the client's numeric `GlobalStrings.ID`, with the symbolic `key` beside
`locales[locale].name` (the exact UI text, including format arguments). Keep per-field
`translationMetadata.fields.name` like other catalogs. Untranslated locales have no name
or invented provenance. Empty original strings remain in the source catalog. Builds export
the key index in shared rules and translations in the normal FRS language packs, using the
same bounded pages and lazy loading as other records. Do not edit generated Lua or recreate
parallel `locales/client-labels` files. Authorized translation snapshots use `catalog-batch.py`
`prepare-labels`, `check-labels` and `patch-labels`; agents edit only result JSON, and the
coordinator applies validated catalog patches. Preserve existing translations and raw source
formatting during source updates.
Item modifiers use `itemenchantments/<SpellItemEnchantment.ID>.json`. Keep the
official name, optional Horde variant and per-field provenance next to the source
duration in seconds. Follow the [enchantment refresh and translation workflow](../docs/import-resync.md#equipment-enchantments-and-temporary-modifiers).
Tool category names live in `totemcategories/<TotemCategory.ID>.json`, with localized `name`
and inline field provenance. These IDs are not item IDs. Spell `tooltipData.requiredToolCategories`
contains verified `SpellTotems.RequiredTotemCategoryID_*` relationships, with
`requiredToolCategoriesSourceMetadata` beside them. Direct `SpellTotems.Totem_*` item tools use
`tooltipData.requiredToolItems` and `requiredToolItemsSourceMetadata`; their names come from owned
`items/<ItemID>.json`. Never resolve missing tools by reverse-looking up their names in the client's
inventory cache or by scanning item names.
All languages and relationships for that entity stay together. The catalog `metadata.json`
files retain only catalog configuration. The `areas` metadata owns
both `areas` and `maps`; their ID namespaces remain separate.
The original datasets seeded them once. Normal targeted corrections edit owned JSON, then rebuild.
Import/update/resync work uses the explicit prepare/apply/verify pipeline below; do not repair
its translations by hand. Source downloads never write catalogs, and no background source
refresh may overwrite maintained files.
The derived language reference library described below supports lookup and proposed patches;
it does not own catalog text or replace direct maintenance of these files.

Keep fields used by the addon, its database builder, translation tooling, and numeric-update safeguards.
Do not retain edit-history arrays, unused starter/finisher or classification fields, area parent IDs,
objective source positions, or duplicate locale identifiers and English labels.

- Quest text: `quests/<decimalQuestID>.json` → `locales[locale]`.
  Fields include `title`, `summary`, `description`, `eventObjectiveLabel`, and indexed `objectiveLines`.
- Quest interaction dialogue carries its source identity in `dialogueContexts` and locale text in
  `locales[locale].dialogue`. The owner is the quest for offers, progress and turn-in, and the
  NPC for greetings and options. Keep `translationMetadata.fields["dialogue.<key>"]` with each
  localized line. The [Spoken source workflow](../datasources/spoken/SOURCE.md) prepares updates
  through resync. A reference candidate must match its full client text at runtime.
  Canonical offer translations may use `dialogue.description` to supplement a missing or
  English fallback description. The `description` dialogue context uses stage `accept`,
  `sourceField: "description"`, and `sourceDescriptionSha256` of the verified English description.
  Keep the English description in its existing field. The build uses the offer as the locale's
  description while the English fingerprint matches and no localized description is available.
- Names: `<kind>/<decimalID>.json` → `locales[locale].name`.
  Kinds are `items`, `npcs`, `areas`, `spells`, `talents`, `factions`, `creaturetypes`, and `classes`.
  Group finder activity names live in `activities/<GroupFinderActivity.ID>.json`, keyed by the
  live activity ID. These IDs are separate from AreaTable, UI map and instance map IDs.
  CreatureType and ChrClasses IDs come from their client table rows, not label-list positions.
  Geographic map names also live in
  `maps/`, separate from `areas/` because their IDs differ.
- Keep locale-independent relationships outside `locales`. AreaTable IDs, UI map IDs,
  spell IDs, DB2 Talent IDs, and live talent API IDs are separate namespaces.
  NPC `factionTemplateId` comes from Questie's composed Forever NPC records; resolve it through
  build-matched `FactionTemplate.Faction` to obtain `factionId`. FactionTemplate IDs and Faction IDs
  are different namespaces. Keep relationship provenance in `factionMetadata` and faction names
  in `factions/<FactionID>.json`. Do not infer NPC faction identity from names, allegiance, or location.
  Catalog records do not use `sourceNames`. Do not recreate those fields.
  The runtime exports `GetNpcFactionID` and `GetFactionName`.
  NPC subnames (the tooltip title line, such as "Warlock Trainer") live in `locales[locale].subName`
  with their own field metadata. Questie supplies them: English from the composed Forever NPC
  records, localized text from `lookupNpcs` merged per field with traces. A subName is kept only
  where English has one. The runtime exports `GetNpcSubName` and matches the visible line only
  against that NPC's own client-language subName.
  Talent `spellId` is the first rank's spell ID; `spellRankIds` retains the ordered
  nonzero `Talent.SpellRank` IDs from client build 1.60.1.70862.
  `clientObjectiveTargets` contains only verified client-index mappings. Entries may specify a positive,
  unique `index`; entries without it use their one-based list position for legacy contiguous mappings.
  Sparse mappings must specify each entry's captured `index`. Ordinary `objectiveTargets`
  positions must not be promoted to client indices.
  Captured NPC kill mappings also retain `type: "monster"`; an NPC relationship alone does not
  establish its live objective type. Verified item/monster targets reuse owned localized names
  when compiling progress labels. Existing explicit objective text takes precedence.
  Captured reputation mappings use `kind: "faction"`, `type: "reputation"`, and an explicit
  client `index`. Only these verified bindings add `factionID` to matching compiled reputation
  lines; current standing is read from structured client data, never stored in the catalog.
  Do not recreate the retired Questie fields `questieExtraObjectives` or `triggerEnd` in catalog records.
- Missing source text remains absent. Official target languages may use the maintained English
  source as an explicit fallback, with its real source-language provenance. Do not guess labels.
- Follow [the import/resync policy](../docs/import-resync.md) for source priority,
  target-language decisions and the reviewed prepare/apply/verify pipeline. Never author AI
  for official target languages outside the book/letter and quest/NPC dialogue exceptions.
  Preserve accepted translations, including captured quest objectives; missing new-job evidence must not remove them.
- Preserve exact sourced wording and provenance, including legitimate names equal to English.
  For cities and continents, prefer official AreaTable/UiMap names. Never rewrite one
  language's source to make it agree with another language.
- Keep localized names in `locales[locale].name` with their field provenance.
  Do not invent a foreign translation from an inherited English default.
- Item usage restrictions live in `tooltipData.requirements`, with inline
  `requirementsSourceMetadata`. Derive `classIDs` from `ItemSparse.AllowableClass`, and bind
  `ItemSparse.RequiredSkill` to `TradeSkillCategory.SkillLineID` only when the category mapping
  is unique in that same verified build. SkillLine IDs and category IDs are distinct. The
  runtime may compare a typed requirement's text only with those owned IDs' source names;
  never scan all class/skill names. Required numeric ranks stay live, not catalog constants.
  A generic client error row can carry an item-owned reputation requirement captured in
  `locales[locale].reputationRequirement`. Preserve its complete native wording and provenance.
  Bind only the verified faction ID and minimum standing in `tooltipData.requirements.reputation`.
  The tooltip uses the owned faction name, standing label and client format when the full row matches.
- Existing item/spell English `description` fields retain the raw client templates and field provenance.
  Spell `auraDescription` is a separate localized field with its own metadata. `$@spellaura` references use this
  field; a cast description must not substitute for an aura description.
  Text without an official English source is outside catalog/addon scope. Remove the unsupported
  field in every language; remove an entity when its English name (quest title) is unavailable.
  Check retained official source evidence first so an import omission can be repaired rather than
  mistaken for an absent source. Do not author English from another language to keep a field in scope.
  Entity `tooltipData` retains normalized effect dependencies and English item labels. Localized
  templates live only in `locales[locale]` with their field provenance. It is maintained catalog content,
  not an automatic upstream sync. Preserve its build/locale provenance and missing spell links.
  English uses the canonical `enUS` locale.
  The runtime exports these as read-only `GetItemDetails` / `GetSpellDetails` records for available locales.
  English records retain structural dependencies and their localized templates. Other locales
  export only available translated text fields. Known Italian target fields copied from English are
  excluded by comparison with their English counterparts; genuinely Italian text remains available.
  Render from owned IDs, target templates and structured client data. Never infer entity identity
  by matching live game text against source templates or translated names. NPC faction rows may
  verify a visible label against the source-language name of that NPC's owned faction ID before
  rendering its target name; never reverse-search all faction names or assume a fixed row position.
  Missing required data or translations preserve native text.
  Spell `schoolMask` selects structured school-specific damage power. `durationModifiers`
  links flat duration adjustments to owned spell effects through `spellID` and zero-based
  `effectIndex`, with `operation: "add"`. Derive these links from build-matched
  SpellClassOptions families and SpellEffect class masks, never from names or entity exceptions.
  Do not recreate `sourceTitles`, `sourceSummaries`, `sourceDescriptions`, `sourceAuraDescriptions`,
  `sourceRanks`, `sourceNameDescriptions`, or their companion metadata maps. Current localized fields
  are authoritative. Native SQLite references exclude Rosetta-authored AI text. Shipping Data packs
  include accepted translations and their aggregate AI flag; do not recreate duplicate Source packs.
  Store canonical English source under `enUS`; explicit official-language fallbacks may copy
  that source text and its actual provenance. Do not accept `enGB` as a target locale or create
  compatibility aliases, duplicate translation jobs, or SQLite languages. Preserve historical sourceLocale
  provenance even when it identifies an original `enGB` source.
  Portuguese uses `ptBR`; do not reintroduce the retired European Portuguese locale.
- Preserve unrelated records and existing manual fixes. Apply small edits with `apply_patch`;
  do not reformat the complete catalogs or refresh unrelated text.

## Book catalogs

`books/<firstPageID>.json` owns localized `name`, typed item/object owners, their native source
observations, and page order. `bookpages/<pageID>.json` owns localized `description`, `nextPageId`
and book memberships. These are separate ID namespaces. Every name/body uses the same inline
`translationMetadata.fields` contract. Missing English bodies, placeholders and ambiguous links
remain gaps. VMaNGOS prose is a community Vanilla reference, not verified Forever wording.

Use the [book source workflow](../datasources/books/README.md) and `resync.py prepare-books`,
then the ordinary immutable apply/verify boundary. Preserve accepted non-AI and manual wording.
Use the dedicated book queue for AI in either target group when verified English exists and a
matching translation is unavailable. Applicable sourced wording supersedes AI. Review source
terms before distributing the compiled records.

## Everyday editing: add, fix, or translate

Source-driven import/update/resync work follows [the canonical process](../docs/import-resync.md).
`resync.py` owns prepared catalog writes; do not repair source-driven translations manually.
`fill-official-text.py` is the source-selection helper and read-only audit tool, not an
alternative everyday update pipeline. Retain English authorship honestly when copying fallback.

Use direct edits for a small number of records. A queue or agent batch is useful for larger
translation work, but is not required to fix one field. Do not load the whole corpus or add
maintenance machinery for a small edit.

### 1. Read only the relevant records

Confirm the kind, positive decimal ID, requested fields, and target languages. Open
`catalogs/<kind>/<id>.json` and inspect its source text, existing translations, metadata,
and relevant relationships. Read a nearby entry of the same kind when adding a new record.
Do not copy that entry's IDs, text, metadata, or tooltip dependencies into the new record.

Get supported languages from configuration, without reading quest records:

```sh
PYTHONPATH=. python3 -c 'from tools.catalogs.catalog_storage import load_catalog; print(load_catalog(".", "quests", ids={})["locales"])'
```

| Request | Scope of the edit |
| --- | --- |
| Fix or add a target translation | Change only the requested locale and fields, plus their metadata. Other languages do not need rewriting when the source meaning is unchanged. |
| Correct source wording or add a source field | Check each supported language against the new meaning. Reuse valid wording; translate only missing or affected targets. Store English once under `enUS`. |
| Add an entity | Create `catalogs/<kind>/<id>.json` with a top-level `locales` object. Add verified shared relationships outside it. Cover every supported language for the supplied text unless the user requests a narrower scope. |

No entry registration or metadata manifest edit is needed for a new entity: the full build
discovers entity files. The filename owns the ID; do not wrap the record in another ID or
`catalogs` object. Use the kind's actual ID namespace, especially for maps and talents.
If no real source exists for a field, leave it absent and report the gap. Do not invent
quest prose, objectives, tooltip facts, or relationships to make a record look complete.

### 2. Choose the wording and origin

Prefer verified native text, then existing translations with the same source meaning and
context. Follow the [source evidence rules](../docs/import-resync.md#eligibility-for-new-additional-language-ai-translations)
and the specific [book and letter exception](../docs/import-resync.md#book-identities-and-existing-source-text).
Check relevant entity names and Warcraft terminology before
authoring. For targeted reuse, search the relevant catalog kind; do not print the full corpus.
Verify that an upstream locale contains an actual translation rather than English fallback.

Edit the text and its `translationMetadata.fields` entry together with `apply_patch`.
For example, this is a locale object under `locales.itIT` for an eligible AI-authored item name:

```json
{
  "name": "Vecchia spada corta",
  "translationMetadata": {
    "fields": {
      "name": {
        "origin": "ai",
        "source": "ForeverRosettaStoneAI",
        "sourceLocale": "enUS"
      }
    }
  }
}
```

`sourceLocale` identifies the text actually used as the source, not automatically the target
language. Unchanged native/community text keeps its real origin and source when reused.
AI-authored corrections to community or native wording have `ai` origin. Retain community
attribution in notices when adapting its text. Do not label text `original` because an AI
checked it, or keep an old source-text fingerprint after changing its source.

Use metadata keys matching the text fields: `name`, `title`, `summary`, `description`,
`auraDescription`, or `objectiveLines.<clientIndex>`, as applicable. Keep metadata inline
and minimal, following the field origin contract below. Add notices only for new source
credits, license requirements, or changed attribution; routine translations do not need
an entry in a generation log.

### 3. Preserve the runtime contract

- Preserve placeholders and formatting tokens, including `{name}`, `{class}`, `{race}`,
  `{current}`, `{required}`, client `$...` formulas, format specifiers, and markup.
  Translate surrounding wording; do not replace live values with fixed numbers.
  For `$g<masculine>:<feminine>;`, preserve the selector syntax and branch order while
  translating the visible alternatives. The branch words are text, not immutable formula tokens.
  Trusted Questie summaries may use literal required amounts. Preserve those translations;
  do not introduce placeholders solely because another source uses them. Live progress is
  separate from required totals. Preserve tokens when authoring a translation of a template.
- Quest `objectiveLines` entries retain their verified `index`, `type`, and `text` shape.
  Do not infer client indices from Questie relationship positions.
  Do not store `objectiveType` or `numRequired`; live objective facts come from the client.
  Literal gender selectors may vary with a language's grammar. Value-bearing selectors,
  formulas, named placeholders, printf arguments, and markup remain protected by validation.
- Keep cast descriptions and aura descriptions separate in localized fields.
  Update field provenance when correcting native quest text; do not retain duplicate source maps.
- Preserve unrelated languages, fields, relationships, and manual fixes. Do not edit
  generated addon files directly or reformat unrelated entity files.

### 4. Validate and finish

Inspect each changed field against its source and confirm its origin, language, placeholders,
and required language coverage. Parse edited JSON before building. For queued translations,
use the existing validate/patch/verify commands; apply generated patches with `apply_patch`.
Run the build and checks in [Build and validate](#build-and-validate) once after the catalog
edits are complete. Report the changed IDs, fields, locales, checks, and any missing source
or translation gaps. A passing build does not establish linguistic quality.

## Checking an upstream update

Read [the import/resync reference](../docs/import-resync.md), then use
[datasources/README.md](../datasources/README.md) for refresh/reuse commands and
[datasources/SOURCES.md](../datasources/SOURCES.md) for provider ownership and attribution.
A check-only request remains read-only. A refresh never edits catalogs.

Keep updates bounded to requested IDs, fields and languages. Freeze one verified corpus
for preparation and authoring; do not rebuild it per entity or batch. Review conflicts and
changed meanings, preserve explicit manual corrections, and report gaps rather than inventing
text. Historical pins belong to field provenance and ignored run manifests, not this guide.
Do not broaden an update into unrelated backfills or historical resets.

For numeric-only spell updates, use `tools/catalogs/refresh-spell-values.py` with build-matched
Wago evidence as documented in `datasources/wago/README.md`. Review its numeric patch and
skipped mappings; this operation does not authorize text changes. Build once after accepted
catalog changes, then run the required checks below.

Keep third-party attribution under `ForeverRosettaStone/notices/`, credentials outside Git,
and raw inputs, reports, queues and SQLite under ignored `datasources/imports/`.

## Language reference library and entity translation workflow

Use [`datasources/corpus/README.md`](../datasources/corpus/README.md) for the offline corpus
builder, source selection, read-only lookup commands, evidence tiers, and current limitations.

Prepare the corpus and tooling before starting a large translation run. Updating these instructions
does not authorize corpus construction, agent execution, or catalog translations. Treat corpus/tooling
preparation, a translation pilot, and the full translation run as separate scopes. Do not resume old
translation work merely because saved drafts exist.

### 1. Build reusable language references

- Derive supported languages from catalog configuration and follow the canonical import policy.
  Pair credited localized sources with verified English. New AI authoring uses English only
  and only eligible additional targets; absent English is a source gap, not permission to
  author from another language. English fallback retains its real source-language provenance.
- Pin source builds/revisions and record coverage by language, entity kind, and field. Follow
  `datasources/SOURCES.md`; a locale file or provider's supported-locale list does not prove
  translated content exists. Reject demonstrated wrong-language text and inherited fallback.
  Equality alone does not invalidate a proper name or source wording. It also does not prove
  a translated official-language field for new-job eligibility.
- Keep original, community, and AI text distinguishable. Preserve upstream AI declarations,
  provenance, and attribution. Do not promote existing catalog metadata into fresh verification
  or feed newly generated wording back into the library as authoritative native evidence.
- Build searchable indexes for exact entity/field matches, English/target pairs, recurring
  phrases, and related entity terminology. Keep source context, field meaning, placeholders,
  and provenance with each match. Similarity retrieves candidates; it does not authorize reuse.
  Resolve conflicting terminology or reuse candidates explicitly before distributing them.
- Keep new source snapshots, derived indexes, and run artifacts under ignored `datasources/imports/`;
  source/corpus tooling belongs under `datasources/`, and catalog/build/release tools under `tools/`. The library must be rebuildable
  from pinned evidence, with catalog inputs identified when used. Read/index the relevant
  source collection once during preparation, not once per entity or worker. Do not duplicate
  full source prose into catalog field metadata or ship development references in the addon.

### 2. Plan work once and give workers bounded context

- Establish the exact IDs, fields, languages, and inclusion of excluded quest statuses before
  assigning work. Calculate gaps from actual text and applicable source evidence.
  Do not recreate `incomplete` or `missingTextByLocale` bookkeeping in catalog records.
  Keep missing source evidence separate from missing translations, conflicts, and demonstrated errors.
- Resolve verified source matches and valid existing translations before authoring. Deduplicate
  remaining jobs by target locale, source text, field meaning, and relevant entity context.
  Use `tools/catalogs/translation-work.py` where applicable. Assign each shared job to one owner;
  distribute accepted results to matching entities without having several workers translate it.
- Supply each worker the complete assigned entity across supported languages, pinned exact
  source matches, related names, applicable terminology, relevant bilingual examples, and the
  unresolved jobs it owns. Keep the full library searchable; do not paste every language's
  entire corpus into each context. Bound retrieved examples and avoid dumping raw tables.
- Freeze the library version for a run. Share accepted translation results with their real
  provenance, without changing the run's native evidence. Save source/target fingerprints,
  assignments, completed results, validation outcomes, and unresolved work so resuming does
  not repeat accepted jobs or redo searches whose inputs have not changed.

### 3. One snapshot per entity, coordinator-owned integration

When delegation is explicitly authorized, assign up to 125 entities to each of six fresh
GPT-6.1-Tera workers at medium effort for a wave of up to 750 entities. Keep one snapshot
per entity with `tools/catalogs/catalog-batch.py` and `--batch-size 1`. Balance disjoint
assignments by the source text volume across missing target languages. Give workers compact
inputs and relevant terminology with a fresh context for each wave. Each worker completes
every missing target language per entity and saves a result file before moving on.
Workers edit their assigned result files and report unresolved cases. Validate results
before applying them.

For each field, applicable trusted source updates win over existing text, especially AI drafts.
Prefer verified official text for official languages, or applicable community text for community
languages. Preserve explicit manual fixes and review conflicts with fresh evidence. Preserve
unaffected valid translations; when source meaning changes, check every supported language.
Reuse accepted matching wording,
then author only eligible additional-language gaps from English with AI origin. Preserve declared AI origin
when using community sources that contain AI text. Leave fields without source evidence absent.

Cleanup covers demonstrated text/language errors and corresponding provenance within scope.
Preserve relationships, objective indices, formatting tokens, and raw valid source templates.
Do not rewrite valid prose for style, invent missing content, or remove text to satisfy a count.
Workers report proposed removals separately: existing batch checks reject removed text, so the
coordinator must handle authorized evidence-backed removals explicitly rather than bypass checks.

The coordinator checks submissions against current records, validates language, meaning,
placeholders, origins, and required coverage, and applies accepted patches with `apply_patch`.
Existing automated checks validate structure and provenance contracts, not linguistic accuracy.
Validate scoped submissions in batches, avoid repeated full-catalog reads or builds per entity,
and run the final build and required checks once after accepted catalog edits are complete.

### 4. Measure before scaling

Before a large translation run, run a separately authorized bounded pilot on representative
records: short names, quest prose, tooltip templates, official/community languages, and known
fallback or provenance problems. Reuse saved work only after checking it against current inputs.
Compare approaches on the same scope and acceptance criteria when claiming a speed improvement.

Measure preparation separately from repeated-run costs: source lookup, retrieval/context size,
unique translation jobs, worker time, coordinator integration, validation/build time, and rework.
Report accepted fields/entities per wall-clock hour, correction/rejection rate, unresolved gaps,
and token usage where available. Count accepted output, not generated drafts. Estimate total
completion time including preparation and integration, and state when no comparable baseline exists.

Do not promise a speed multiplier or accuracy percentage without measurements. Present pilot
throughput, quality limits, the estimated full-run duration, and the concrete remaining bottleneck
before expanding to the full run. Resolve demonstrated language/provenance defects before scaling;
do not trade text correctness for a throughput target or add repeated general review cycles.

## Field origin contract

Every field's metadata is an inline object in its entity file. No shared profiles or references.
Read catalogs through `tools/catalogs/catalog_storage.py`: `load_catalog(root, kind, ids={kind: ids})`
reads only selected entities. Use `load_catalog(root, 'quests', ids={})`
for language configuration without reading quest records. Full builds use `load_catalogs(root)`.
The document shape stays `catalogs.<kind>[id].locales[locale]`.
Field metadata keeps `origin`, `source`, and `sourceLocale`, plus `sourceBuild`, `sourceRevision`,
and `sourceTextSha256` when available and useful for updates. Credits, licenses, upstream links,
and adaptation attribution belong in `ForeverRosettaStone/notices/catalog-credits.md` and its
accompanying license files. Credit community sources even when adapting their text with AI.
Localized field metadata does not retain `sourceFile`, `sourceColumn`, or `sourceFileSha256`;
the reference snapshots own file identity and integrity checks.
Do not add generation dates, tool names, method logs, review bookkeeping, import checksums,
duplicate source prose, reuse histories, or nested metadata. Entity original source templates
and their native origins remain separate from target translation metadata.

Every localized text field in every catalog has metadata. Store its origin once; do not store
a duplicate `hasAITranslation` boolean. For example:

```json
"translationMetadata": {
  "fields": {
    "summary": {
      "origin": "ai",
      "source": "ForeverRosettaStoneAI",
      "sourceLocale": "enUS"
    }
  }
}
```

Allowed origins are `original` for direct API/client text, `community` for third-party supplied
text, and `ai` for known AI-generated or AI-adapted text. Keep the actual source language and
revision/build when known. Record upstream AI declarations in notices.
Unknown upstream AI usage remains community origin; do not invent certainty.
`nativeContextReuse` keeps the referenced native field's origin. `reviewedCommunityReuse` keeps
community origin unless the upstream source explicitly declares AI generation. AI-authored or
AI-adapted wording has AI origin. The fact that an import or review used AI does not change the
origin of text it reused. Locale aliases inherit the referenced field's origin.
Names use `fields.name`; quest prose uses its field name, and objective templates use
`fields["objectiveLines.<clientIndex>"]`. Missing text has no invented field metadata.

The builder validates these origins and exports a `hasAITranslation` boolean per runtime record.
Quest records contain only `title`, `summary`, `description`, `eventObjectiveLabel`, `objectiveLines`,
and that boolean. Quest and NPC dialogue are indexed separately in the same language packs.
Item/spell records also export available target-language `details`; their normalized
tooltip dependencies and retained source templates remain in English detail records. ID-only rendering
loads numeric rules through `GetItemRules` and `GetSpellRules`. Book-page records
expose `description` and that boolean; other named entity records expose `name` and
that boolean.
Detailed origins and quest relationships stay in these full catalogs. Runtime capture may use
a maintained template of any origin when it matches visible client text unambiguously; origin
must not block a usable source template or establish entity identity through text matching.
`tools/build/runtime_catalog.py`
owns this projection and compiles verified item objectives without changing catalog text.
`IsQuestAITranslated` and `IsAITranslated(kind, id, locale)` expose the aggregate flag. API version 3
has no per-field metadata or quest-relation API. Unknown records return `nil`. The UI owns icon placement.

Runtime export excludes quests marked `test`, `notImplemented`, `placeholder`, or `unused`, including
their ID-index entries. Keep their full catalog records. `temporarilyDisabled` quests remain exported.

## Build and validate

### Assign bounded batches to agents

When delegation is authorized, scope the catalog work before assigning records. Save a JSON
scope such as `{"items": ["25", "35"], "quests": ["170"]}` in the ignored reference workspace.
Include new IDs explicitly. Prepare disjoint assignments:

```sh
python3 tools/catalogs/catalog-batch.py prepare --scope datasources/imports/update/scope.json --output-dir datasources/imports/update/batches --batch-size 1
```

Assign each agent a disjoint group of `NNNNN.results.json` files, the supported languages, and
the pinned upstream evidence. Each file contains all languages with inline field metadata. The
coordinator retains the matching `NNNNN.batch.json`, which contains complete original records,
locale configuration, and fingerprints. Agents edit only their assigned results files with
the dedicated `apply_patch` tool. Preserve unchanged
metadata. Changed metadata records the correct origin, source, and source language inline.
New records start as `null` and must be supplied in the results.
Do not run builders or modify maintained catalogs or shared metadata from individual agents.
Assign related source and target corrections to the same agent, and supply the pinned upstream
records or paths in its brief. The batch snapshot alone is not evidence of upstream changes.

The coordinator checks each submission and generates a patch:

```sh
python3 tools/catalogs/catalog-batch.py check --batch datasources/imports/update/batches/00000.batch.json --results datasources/imports/update/batches/00000.results.json
python3 tools/catalogs/catalog-batch.py patch --batch datasources/imports/update/batches/00000.batch.json --results datasources/imports/update/batches/00000.results.json --output datasources/imports/update/batches/00000.patch
```

Apply the generated patch with the dedicated `apply_patch` tool. Checks reject stale records,
altered assignments, records outside the assigned scope, removed text, missing origins, and invalid
placeholders in changed AI text. Keep English frozen in authoring assignments; apply source
changes through resync before preparing batches. Missing new-job evidence blocks authoring,
not accepted additional-language text.
These checks do not establish translation quality or upstream applicability. The coordinator must
inspect those and confirm unchanged target wording remains valid when source text changes.
Recheck immediately before patch generation. The patch includes the previous entity contents so
a conflicting edit between validation and application fails instead of silently overwriting it.
Keep saved submissions to resume work, and use a fresh output directory for a new assignment.

For translation jobs, `translation-work.py queue --scope datasources/imports/update/scope.json --output ...`
reads only the selected records. Reuse candidates in a scoped queue come from those records;
use a full queue when corpus-wide reuse is needed. Result validation, verification and patching
load only the records referenced by the saved queue. Build once after all accepted patches.

When catalog metadata changes, regenerate saved queues and batch assignments against the current
catalogs rather than bypassing stale-source checks.

From the repository root:

```sh
uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
uv run --no-project --with lupa==2.8 python tests/python/test-lua-database.py
uv run --no-project --with lupa==2.8 python tests/run-tests.py
git diff --check
```

The builder reads the owned entity files, their metadata and the maintained addon manifest. It writes the
encoded TOC database and must not modify its JSON inputs. Original snapshots are unnecessary.
Inspect the edited IDs and locales in the diff, ensure origins match the retained field evidence,
and report the exact checks run. Do not restart a general review once the scoped checks pass.
If the user excludes the matrix, run focused checks or `tests/run-tests.py --unit-only`;
do not invoke the full test runner or matrix stages indirectly.
