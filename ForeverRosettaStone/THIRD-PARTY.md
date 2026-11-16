# Third-party references

## Spoken

Forever Rosetta Stone retains adaptations of Spoken 3.8.3's page and map-panel coordination.
It uses Blizzard's native components for the quest panel, scrolling, fonts, textures, and reward
widgets. It does not load Spoken or write to its global namespaces. Adapted modules are:

- `quests/quest-page.lua`: page coordination adapted from Spoken `UI/Compendium.lua` and
  Spoken Places `UI/LorePage.lua`. Native scrolling, content order, spacing, header and rewards follow
  Forever's `QUEST_TEMPLATE_MAP_DETAILS` and `QuestMapFrame.xml`. Text styles and reward displays
  are copied from the live native quest frame without changing it.
- `quests/quest-ui.lua`: Spoken Places `UI/MapPanel.lua`, panel shell and map-relative layout adapted for
  a separate quest companion.

- [Spoken repository](https://github.com/rusty-key/spoken-wow)
- [Map panel](https://github.com/rusty-key/spoken-wow/blob/master/addons/Spoken_Places/UI/MapPanel.lua)
- [Page renderer](https://github.com/rusty-key/spoken-wow/blob/master/addons/Spoken_Places/UI/LorePage.lua)
- [License](https://github.com/rusty-key/spoken-wow/blob/master/LICENSE)

MIT License

Copyright (c) 2026 Rusty Key

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Spoken's license excludes third-party assets. The game's UI artwork and quest content belong
to Blizzard Entertainment and are **not covered by the MIT code license**. Artwork is referenced
through the client's native atlases; no copied textures or audio are bundled. Book text sources are credited separately below.
Forever Rosetta Stone's localized apology page is addon UI, not official quest text.

## MultiLanguage

[MultiLanguage](https://github.com/rubenzantingh/MultiLanguage) was inspected as a reference for
quest-ID and locale keyed data and the source quest's identity. Its license is **all rights
reserved**. No MultiLanguage code or database is bundled.

## Native UI reference

The [Forever UI source mirror](https://github.com/Gethe/wow-ui-source/tree/forever) was used to
verify quest tooltip ownership, gamepad input propagation, and input constants.

## Client tooltip labels

`database/item-data.lua` contains English binding/equipment labels and item subclass names from Forever
build 1.60.1.70862's [GlobalStrings](https://wago.tools/db2/GlobalStrings/csv?build=1.60.1.70862&locale=enUS)
and [ItemSubClass](https://wago.tools/db2/ItemSubClass/csv?build=1.60.1.70862&locale=enUS) tables.
These game strings belong to Blizzard Entertainment. Item names come from the bundled database.

## Database provider and build inputs

The metadata chunk reader in `database/database-api.lua` is adapted from QuestieDB's
`src/read/baked.lua`. The offline builder reuses its `generator/lib.lua` metadata writer and
`generator/vendor/BlizzardCBOR.lua` deterministic codec at commit
`3a621efafce6aef99b0f106d22aa71ca980ee552`. The build helpers retain source credits in
`tools/build/encoding/blizzard-cbor.lua` and `tools/build/encoding/toc-metadata.lua`, with the original
comments and license notices in `tools/build/encoding/`. They are not
loaded or distributed as addon runtime code. The provider uses the client's encoding APIs.
The pinned source's licensing notice and GPLv3 text are included in `notices/`.

Tooltip titles use Forever Rosetta Stone's existing icon as an inline texture in the native tooltip text.

The generated data retains text from Blizzard Entertainment (including client-table exports
through Wago.tools), the pinned QuestieDB Forever snapshots, accepted Wowhead and Icy Veins
supplements, and the community sources recorded below. The maintained root `catalogs/` files
retain the accepted text and its provenance; the builder exports selected runtime fields.
Translations generated for Forever Rosetta Stone are not official game text. Per-field AI/community provenance
is retained in the source catalogs. The runtime API exposes only an aggregate AI flag.

- QuestieDB: https://github.com/Questie/QuestieDB, pinned to the commit above.
- ClassicUA: https://github.com/greenya/ClassicUA, whose original COPYING notice is retained.
- Czech Forever: Marek Lušovský, release `0.7.3`;
  https://www.curseforge.com/wow/addons/czechforever/files/9595441; CC BY-NC 3.0.
  Retained adaptations from `v0.7.1` keep their original catalog provenance.
- Forever Translated Polish: Copyright (c) 2026 Ceridian;
  https://www.curseforge.com/wow/addons/forever-translated/files/9434472; CC BY-NC-SA 4.0.
  Attribution and the supplied license notice are retained in `notices/polish-license.txt`.
- Världen av Krigskraft Swedish: Ninsew (archive author Pontus);
  https://www.curseforge.com/wow/addons/varlden-av-krigskraft/files/9125768.
  The observed MIT declaration and its retrieval limits are retained in `notices/swedish-declaration.json`.
- ForeverTR Turkish: Red Lion Labs, release `0.1.0-beta.1`;
  https://edge.forgecdn.net/files/9147/688/ForeverTR-0.1.0-beta.1.zip; CC BY-SA 4.0 data.
  The supplied data license and Blizzard notice are retained in `notices/forevertr-data-license.txt`
  and `notices/forevertr-notice.txt`.
- PolishForever: Copyright (c) 2026 Jan Słomian;
  https://github.com/JSlomian/PolishForever/tree/9b7f35499cdc8c52ebf4de88f315c18092c16ac8;
  CC BY 4.0 translation data. The supplied notice, including its AI translation declaration,
  is retained in `notices/polishforever-data-license.txt`.
- EG Link: Efficient Games (https://efficient.games), https://github.com/JIVESCORP/eg-link-output-wowf;
  CC BY 4.0 compilation credit for the native NPC/item cache text used by our import.
  Underlying game text remains Blizzard Entertainment's content.
- WoWForeverIT: Copyright (c) 2026 polletto and WoWForeverIT contributors;
  https://github.com/polletto/WoWForeverIT. The complete MIT notice and upstream third-party
  notices are retained in `notices/wowforeverit-license.txt` and
  `notices/wowforeverit-upstream-notices.md`.
  WoWForeverIT includes translations from **QuestIT by Drakanast**, maintained with the
  **QuestIT Discord community** and **#italyforazeroth** (https://italy-for-azeroth.vercel.app/).
  QuestIT translations are not independently AI-authored work by Forever Rosetta Stone;
  their separate terms are retained in `notices/questit-translations-license.txt`.
  `notices/questit-license.txt` retains the code notice and Blizzard ownership distinction.
- WOW Forver - Italiano: Copyright (c) 2026 WOW Forver - Italiano contributors;
  https://github.com/z4mbo/WOW-Forver-Italiano. Italian spell descriptions retain the declared
  AI origin. The complete MIT notice is retained in `notices/wowforveritaliano-license.txt`.

Community notices are included in `notices/`. [Catalog credits](notices/catalog-credits.md)
collect attribution, release references, and upstream AI declarations. Catalog fields retain
minimal inline origins and source identifiers, languages, revisions/builds, or text fingerprints.
The game's quest text and names remain Blizzard's content and are not covered by the MIT
notice for Spoken code.


## Book text source

Book/page catalogs also retain English and localized text from the VMaNGOS world database,
published at https://github.com/vmangos/core/releases/tag/db_latest. Credit: VMaNGOS
contributors; underlying World of Warcraft text belongs to Blizzard Entertainment. The upstream
repository's GPL-2.0 notice is retained verbatim in `notices/vmangos-license.txt`; this content
is not relicensed as Forever Rosetta Stone's MIT code. Catalog field metadata retains the exact
asset ID/name, source locale, scope and hashes. VMaNGOS-derived wording remains a Vanilla
reference; it is not represented as a verified Forever client capture. Existing ClassicUA,
Czech Forever, PolishForever, ForeverTR and Efficient Games credits also apply to reused book
text with their retained origin and notices.
