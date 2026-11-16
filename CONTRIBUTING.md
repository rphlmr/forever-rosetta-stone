# Contributing translations

One corrected word or one translated quest is a useful contribution. You can submit a
[translation issue](https://github.com/rphlmr/forever-rosetta-stone/issues/new) without building
the addon, or open a pull request editing the catalogs directly.

## Report a translation

Include the target language, entity type and ID when available, the original text, your
suggested translation, and where it appears in WoW Forever. A screenshot or an FRS diagnostic
report helps identify the exact field; see [reporting problems](docs/troubleshooting.md).
Explain whether you wrote the text yourself, copied an existing translation, or used AI.

## Find the catalog record

Each entity has one JSON file under `catalogs/<kind>/<decimalID>.json`. The filename owns the
ID. All languages share that file, under `locales`.

| Content | Catalog and text fields |
| --- | --- |
| Quests | `quests/<questID>.json`: `title`, `summary`, `description`, `eventObjectiveLabel`, `objectiveLines` |
| Items | `items/<itemID>.json`: `name`, `description`, `nameDescription`, `setName` |
| Spells and talents | `spells/<spellID>.json`, `talents/<talentID>.json`: `name`, `description`, `auraDescription`, `rank` where present |
| NPCs | `npcs/<creatureID>.json`: `name`, `subName` |
| Zones and maps | `areas/<areaID>.json`, `maps/<uiMapID>.json`: `name` |
| UI labels | `globalstrings/<GlobalStrings.ID>.json`: `name`; the record also identifies its symbolic `key` |
| Books | `books/<firstPageID>.json`: `name`; `bookpages/<pageID>.json`: `description` |

Other name catalogs include `activities`, `classes`, `races`, `factions`, `creaturetypes`,
`professioncategories`, `taxinodes`, and `totemcategories`. Race records can also have
`nameFemale`. Use the correct ID namespace: an item ID is not a totem-category ID, and a
spell ID is not necessarily a talent ID.

For example, [quest 783](catalogs/quests/783.json) owns the title and prose for **A Threat
Within**. Read the maintained `enUS` field and surrounding context before changing a target
translation. Do not translate a quest summary as though it were the full quest description.
If you cannot find the record or verify its identity, open an issue rather than inventing an ID.

Supported locale codes are listed in
[`catalogs/quests/metadata.json`](catalogs/quests/metadata.json), under `document.locales`.
English is `enUS`, Portuguese is `ptBR`, and Italian is `itIT`. Adding an entirely new language
needs maintainer coordination; do not add a locale only to an individual record.

## Edit the text and its provenance

Change only the requested fields in the target locale. A partial contribution is welcome;
you do not need to translate every language or fill every field. Preserve the English source,
other translations, and all shared relationships.

For a translation you wrote yourself from English, use `origin: "community"`, identify your
contributor handle in `source`, and set `sourceLocale: "enUS"`. For example, this locale object
belongs under `locales.itIT` in a race record whose English name is `Human`:

```json
{
  "name": "Umano",
  "translationMetadata": {
    "fields": {
      "name": {
        "origin": "community",
        "source": "github:YOUR_HANDLE",
        "sourceLocale": "enUS"
      }
    }
  }
}
```

This is a fragment, not a replacement for the whole entity file. Replace `YOUR_HANDLE` with
your handle. Each changed text field needs its own metadata entry: a quest `title` uses
`translationMetadata.fields.title`, for example. The source locale is the language you
actually translated from, not automatically the target language.

When correcting existing text, update its provenance to reflect the new wording. Do not keep
the previous provider, build, revision or source hash if it no longer describes your work.
Reusing unchanged text from another source retains its real provenance. Identify that source,
its attribution and applicable terms in the PR; new third-party credits belong in
[`catalog-credits.md`](ForeverRosettaStone/notices/catalog-credits.md), with license notices
where required. See the [project license](LICENSE.md).

AI-generated or AI-adapted wording must retain `origin: "ai"`, even after human review.
Never relabel it as a human community translation. AI authoring is allowed only for eligible
additional languages under the [import policy](docs/import-resync.md#eligibility-for-new-additional-language-ai-translations);
it is prohibited for official target languages. A human-authored community translation does
not use that new-AI eligibility gate. Prefer verified native game wording when it exists.
Bulk upstream imports follow the [resync workflow](docs/import-resync.md), rather than manual
catalog replacement.

## Preserve templates and live data

- Keep placeholders such as `{name}`, `{class}`, `{race}`, `{current}` and `{required}`.
- Keep numeric arguments (`%s`, `%d`, `%1$s`, `%%`), client formulas (`$s1`, `$d`, `$@...`),
  colors, icons, links and line-break formatting. Translate the surrounding words, not live values.
- Preserve gender/plural selector syntax and branch order while translating their visible
  alternatives. Ask for review when the target grammar needs a different plural structure.
- For quest `objectiveLines`, preserve each entry's verified `index` and `type`. Change only
  its `text` and matching `objectiveLines.<index>` metadata. Never invent objective bindings.
- Keep spell cast `description` separate from `auraDescription`. Do not replace missing facts
  with a plausible guess; leave unavailable text absent.

Do not edit `ForeverRosettaStone_Data/`, generated TOCs or runtime Lua to add translations.
The build compiles the catalogs into the shipping data packs.

## Validate and open a pull request

Fork the repository and work on a branch. For a small edit, GitHub's file editor also works;
describe the translation and its provenance so a maintainer can help with validation.

With Python 3 and `uv` installed, run these commands from the repository root. Replace the
example path with your changed files:

```sh
python3 tools/catalogs/format-catalogs.py --write catalogs/races/1.json
python3 tools/catalogs/format-catalogs.py --check catalogs/races/1.json
git diff --check
uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
uv run --no-project --with lupa==2.8 python tests/run-tests.py --unit-only
uv run --no-project --with lupa==2.8 python tests/python/test-lua-database.py
```

Build once after finishing the catalog edits. No source download or game installation is
needed for a small translation contribution. Review the catalog diff and include the generated
shipping changes from the build, without changing the addon version. Do not commit source
downloads, captures, reports or release ZIPs. If you cannot run the build, submit the catalog
edit and say so; a maintainer can regenerate the shipping files before merging.

In the PR, name the affected IDs, fields and locales, explain corrections, and disclose the
source and any AI assistance. `main` requires a PR and the `checks` CI check; a maintainer
reviews the wording. Passing CI verifies structure and runtime behavior, not linguistic quality
or complete translation coverage.

For advanced field contracts, see [catalog maintenance](catalogs/AGENTS.md). For local ZIPs
and release testing, see [the release guide](docs/releases.md).
