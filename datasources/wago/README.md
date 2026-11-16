# Manual item and spell reference updates

Python 3 and its standard library are sufficient. Run commands from the repository root.
Nothing runs on a schedule. These tools never import, merge, or rewrite maintained catalogs.

## Check for a new Forever build

```sh
python3 -m datasources.wago check
```

This queries Wago's `wowf` product, excludes background-download builds, and compares
numeric versions against the applied baseline `1.60.1.70888`. It downloads no tables. Network errors and
unexpected responses fail rather than reporting “no updates”. After reviewing another
build, pass `--baseline FULL_VERSION` explicitly. Downloading does not promote a baseline.

## Download a reference snapshot

```sh
python3 -m datasources.wago download
```

Without `--build`, the downloader discovers the latest published Forever (`wowf`) build,
excluding background-download builds. It resolves the version once, prints it, and pins
every table request to that version. Discovery errors stop the command; there is no fallback
to the applied baseline. Use `--build FULL_VERSION` only to reproduce a known snapshot or
fetch the old side of a comparison.

The default destination is `<project>/datasources/imports/wago/<build>/`. Use `--output` to change it.
Raw snapshots are stored in the project but stay outside Git: `/datasources/imports/wago/` and
versioned client-locale CSVs are ignored. Keep reports and manifests under that ignored folder too.

The 31 tables below form the default item/spell profile. `AreaTable`, `UiMap`, and `TradeSkillCategory` are also
supported when explicitly selected; they are not downloaded by default.
`--tables Spell SpellName` selects a subset for a
targeted check. There is no download-everything option. English is always fetched first;
tables with `_lang` columns are then fetched in the requested client locales, except
`Talent`, which is retained in English only for talent-to-spell links. Localized
`GlobalStrings` are the official same-field evidence for client-label AI jobs. Shared
tables are downloaded once.

Default locales: `enUS deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW`.
Use `--locales enUS frFR` to narrow them. English is represented by `enUS`; community languages
are not Wago client locales and need separate authored translations.

Downloads use sequential requests, a 30-second request timeout, validated CSVs, atomic
file writes, and a generic Chrome User-Agent (no user or project identity).
A manifest contains row counts and SHA-256 hashes. Valid existing
files are reused. Invalid existing files are preserved and reported; move them aside
before retrying. HTTP 401/403/429 stops immediately, without retry or access bypass.
Exit status 1 means the snapshot is incomplete or the check failed.

## Why each table is retained

This profile supports translated item/spell text and the data behind description templates.
It is not an attempt to reproduce the entire client database or live tooltip calculation.

| Tables | Required content/dependency |
| --- | --- |
| `GlobalStrings` | Client formats and labels for native tooltip lines, and official evidence for label jobs. |
| `Talent` | Talent row IDs and their linked spell IDs. |
| `TradeSkillCategory` (opt-in) | Localized profession section names keyed by the live category ID. |
| `SpellTotems`, `TotemCategory` (opt-in) | Spell-to-tool-category relationships and localized category names; category IDs are distinct from item IDs. |
| `GroupFinderActivity` (opt-in) | Localized dungeon, battleground and questing activity names keyed by the live group finder activity ID. |
| `TaxiNodes` (opt-in) | Localized flight destination names keyed by the live taxi node ID, distinct from session slots. |
| `AreaTable`, `UiMap` (opt-in) | Localized area names/parents and UI map names, in separate ID namespaces. |
| `Item`, `ItemSparse` | Item identity, class/subclass keys, localized names/flavor text, and content links. |
| `ItemClass`, `ItemSubClass` | Translated class/subclass labels, joined by class and subclass keys. |
| `ItemXItemEffect`, `ItemEffect` | Item → equip/use effect → spell description. |
| `ItemSet`, `ItemSetSpell` | Set names and threshold → bonus-spell links. |
| `ItemNameDescription`, `ItemLimitCategory` | Extra item labels referenced by `ItemSparse`. |
| `Spell`, `SpellName` | Description/aura templates, rank text and names, including references to other spells. |
| `SpellEffect` | Effect amounts, intervals, variance, coefficients and effect references used by templates. |
| `SpellMisc`, `SpellDuration` | Spell → duration, including duration used inside description prose. |
| `SpellClassOptions` (opt-in) | Spell family and class masks used to bind duration-changing talent effects to their targets. |
| `SpellRadius`, `SpellRange` | Effect → radius and spell → range, including description placeholders. |
| `SpellLevels` | Level bounds associated with effect scaling; not the player's current level. |
| `TraitDefinition`, `TraitDefinitionEffectPoints`, `CurvePoint` | Spell effect overrides and their numeric rank-to-value curves. |
| `TraitNodeEntry`, `TraitNodeXTraitNodeEntry`, `TraitNode` | Trait definition → entry → node links used to read live ranks. |
| `SpellAuraOptions` | Stack, charge and proc values referenced by description placeholders. |
| `SpellTargetRestrictions` | Target-count limits referenced by description placeholders. |
| `SpellDescriptionVariables`, `SpellXDescriptionVariables` | Spell → named expression definitions used by templates. |
| `SpellItemEnchantment` | Localized enchantment text and effect arguments for item enchantments. |

Excluded: visuals, sound, animation, duplicate search-name exports, bag-family metadata,
cast-time, mana-cost, cooldown, reagent and equipment-requirement tables. Live values
should come from the game where available. A future renderer must demonstrate a missing
dependency before expanding this list; schema links alone are not a reason to download a table.

`SpellMisc` necessarily includes unrelated columns because Wago exports whole tables.
Keeping a table does not mean every column is used or every referenced table is needed.

## Audit content dependencies and languages

```sh
python3 -m datasources.wago audit datasources/imports/wago/BUILD --output datasources/imports/wago/reports/audit-BUILD
```

Replace `BUILD` with the full version printed by the downloader.

Read `report.md` for counts and `report.json` for IDs and fields. The audit verifies
manifest completeness, file hashes, unique IDs and record counts before reporting:

- Missing tables in the selected content profile and missing target IDs in known content joins.
- Missing localized IDs/text relative to English.
- Exact English matches as **possible fallback**, including legitimate unchanged proper names.
- Differences in recognized numeric/reference placeholders as **review candidates**.

The placeholder comparison is deliberately partial: grammar, plurals, conditions and
the full expression language are not parsed. A clean report does not prove renderability.
All templates containing `$` remain identified as requiring a renderer. Audit findings
are review data and do not cause a nonzero exit; corrupt/incomplete snapshots do.

English defines the reference records and meaning. Use the requested language's client
text where present and correct. Missing or stale translations require manual review and,
when authored with AI, `origin: "ai"` metadata. Never silently substitute English and
label it translated. A successful download does not establish language parity.

## Refresh spell numeric data

After fetching or comparing a new build, prepare numeric updates for the existing spell catalog:

```sh
python3 tools/catalogs/refresh-spell-values.py --snapshot datasources/imports/wago/BUILD --output datasources/imports/spell-numeric-refresh
```

The script checks snapshot hashes and build consistency, then generates `report.json` and
`updates.patch`. It never edits catalogs. Review and apply the patch with the dedicated patch
tool, then rebuild once using `catalogs/AGENTS.md`. Use `--ids 1454 18182` for a focused update.
Multiple `--snapshot` directories may supply the required tables only when their builds agree.
The refresh updates represented effect amounts, coefficients, periods, chain counts, level fields,
and trait curves. Other numeric fields, translation text, and provenance outside these fields
are preserved. Ambiguous trait mappings and unavailable source rows are reported and left unchanged.
This is one step of each Wago update, not a scheduled or background job.
Existing numeric values that disagree with Wago are also skipped to preserve manual fixes.
After reviewing those records, use `--ids` with `--replace-existing` to prepare replacements.

For missing scalar formula dependencies, use `--missing-spell-fields --ids ID...` with the
same snapshot/output arguments. This only fills absent stack counts, proc chances/charges,
target limits and ranges. Each value requires one default-difficulty source row; a range
also requires both target variants to agree. Absent source rows never imply zero. Existing
values and translations are preserved, and added fields retain build and input-hash provenance.
Review the generated patch before applying it, then build once after catalog edits.

## Compare builds

Download the latest candidate without `--build`, and pin the previous applied build with
`--build FULL_VERSION` if its snapshot is not already available. Use the downloader's
printed version for `NEW_BUILD`, then run:

```sh
python3 -m datasources.wago diff datasources/imports/wago/OLD_BUILD datasources/imports/wago/NEW_BUILD --output datasources/imports/wago/reports/diff
```

The snapshots must contain identical table/locale profiles. To compare an older broad
snapshot, rerun its downloader with the same narrowed profile; its manifest will select
that profile while extra historical CSVs remain untouched. No automatic cleanup occurs.

The report lists added/removed IDs, added/removed columns, and old/new values of changed
cells, independent of row order. It flags unchanged localized text after an English edit
for review. JSON carries full field changes; new/removed record contents remain in their
respective CSVs. Review differences before making narrowly scoped catalog edits under
`catalogs/AGENTS.md`. Nothing is applied automatically.

When asked “any update to spells/items?”, run `check` against the last reviewed build;
download the candidate, audit it and compare only when an update is present. Report the
changes and gaps. Catalog edits and translation work remain separate requested work.

## Dependency evidence for 1.60.1.70862

The original 23-table profile validates as 123 exports across 11 client locales. Known content joins
resolve all referenced set labels, extra item labels, limit categories, duration IDs,
range IDs, radius IDs and description-variable definitions. The source has gaps:
one referenced item-effect ID, 165 distinct item-effect spell IDs and nine set-bonus spell
IDs are absent from their target exports. These are reported, not filled with guesses.

Verified examples: item 2102 → item effect 97412 → spell 14824 → effect base value 10;
Raptor Strike 2973 → effect index 0 → base value 5. Fireball 133 also needs duration,
period, variance and level scaling, so a base amount alone is not a rendered description.
The English templates contain duration, radius, range, stack, charge and target-limit
token candidates. These checks justify retaining their content dependencies, but do not
prove all formulas or character modifiers are resolved. Full tooltip rendering is separate.

## Tool validation

```sh
python3 tests/python/test-wago-download.py
python3 tests/python/test-wago-updates.py
git diff --check
```
