# Catalog credits

Forever Rosetta Stone retains Blizzard game text, community translations, and unofficial AI-authored
translations and adaptations. Credits also apply when community text was adapted or reused
as a translation reference. Field origins and minimal source identifiers live in the catalogs;
license texts remain in this directory. See also [THIRD-PARTY.md](../THIRD-PARTY.md).

## Blizzard and reference databases

- Game text and names belong to Blizzard Entertainment. Client table references came through
  [Wago.tools](https://wago.tools/db2), including builds `1.60.1.70862`, `1.60.1.70888` and `1.60.1.70938`.
- [EG Link](https://github.com/JIVESCORP/eg-link-output-wowf) compiles native NPC and item cache text used by our import.
  Data from Efficient Games (https://efficient.games), licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Retained source snapshots identify
  the client build and revision; source wording remains attributed to its original language.
- [QuestieDB](https://github.com/Questie/QuestieDB) supplied Forever names and relationships,
  including revisions `3a621efafce6aef99b0f106d22aa71ca980ee552`,
  `e19dfdf8528334ea63da0ecc4e291c134c0fc266` and
  `4dbb82440a27856f8dccf57094a5d792cdc7cc9b` and
  `e1652ce62113c152da682baf2d6fb85f1396bcfb`. See `questiedb-license.md` and `gpl-3.0.md`.
  NPC faction-template relationships also use the composed Forever static data from revision
  `48514e5119804c8b88cde800a1d99a8de1f28aef`, joined to Wago's build `1.60.1.70888` FactionTemplate table.
- [Wowhead Forever](https://www.wowhead.com/forever) and
  [Icy Veins](https://db.icy-veins.com/wow-forever/) supplied accepted supplemental text
  and terminology references. They are references, not automatic synchronization sources.
- Additional terminology/context references included [JudgeHype](https://wowclassic.judgehype.com/),
  [Realm First](https://realmfirst.net/), and [ConquestCapped](https://conquestcapped.com/).

## Community translations

- [ClassicUA](https://github.com/greenya/ClassicUA/tree/1770d208ad853d23d61105cf510d53804770d916),
  revisions `d9bf29572a85957fd69085be0cec28262cba0c87` and
  `1770d208ad853d23d61105cf510d53804770d916`: Ukrainian text and translation references.
  Retained upstream markings distinguish declared AI text from community text; the upstream
  model was unspecified. See `classicua-copying.txt`.
- [Czech Forever](https://www.curseforge.com/wow/addons/czechforever/files/9648816),
  Marek Lušovský, release `0.8.2`, alongside retained text from `0.7.3` and `v0.7.1`: CC BY-NC 3.0.
  Text AI usage is unspecified; the AI narration declaration does not establish text authorship.
  See `czechforever-license.txt`.
- [Forever Translated Polish](https://www.curseforge.com/wow/addons/forever-translated/files/9434472),
  Copyright (c) 2026 Ceridian, release `1.1.1`: CC BY-NC-SA 4.0.
  Upstream AI usage was unknown. See `polish-license.txt`.
- [Världen av Krigskraft](https://www.curseforge.com/wow/addons/varlden-av-krigskraft/files/9125768),
  Ninsew, archive author Pontus, release `0.10.1`: observed MIT declaration.
  Upstream declares Claude-generated Swedish translations. See `swedish-declaration.json`
  for the retained declaration and its verification limits.
- [ForeverTR](https://edge.forgecdn.net/files/9147/688/ForeverTR-0.1.0-beta.1.zip),
  Red Lion Labs, release `0.1.0-beta.1`: CC BY-SA 4.0 translation data, declared AI-generated.
  See `forevertr-data-license.txt` and `forevertr-notice.txt`.
- [PolishForever](https://github.com/JSlomian/PolishForever/tree/9b7f35499cdc8c52ebf4de88f315c18092c16ac8),
  Copyright (c) 2026 Jan Słomian, revision `9b7f35499cdc8c52ebf4de88f315c18092c16ac8`:
  CC BY 4.0 translation data, declared AI-generated. Includes text accepted through reviewed
  hash and pattern matching. See `polishforever-data-license.txt`.
- [WoWForeverIT](https://github.com/polletto/WoWForeverIT/tree/81023460dfdccb80a33cf6be805eae4539eb99ca),
  Copyright (c) 2026 polletto and WoWForeverIT contributors, revision
  `81023460dfdccb80a33cf6be805eae4539eb99ca`: Italian names, text and translation references.
  See `wowforeverit-license.txt` and the unchanged `wowforeverit-upstream-notices.md`.
  WoWForeverIT includes translations from **QuestIT by Drakanast**, maintained with the
  **QuestIT Discord community** and **#italyforazeroth** (https://italy-for-azeroth.vercel.app/).
  QuestIT translations are community work, not independently AI-authored work by Forever
  Rosetta Stone. Their separate terms are retained verbatim in `questit-translations-license.txt`;
  `questit-license.txt` retains the upstream code notice and Blizzard ownership distinction.
- [WOW Forver - Italiano](https://github.com/z4mbo/WOW-Forver-Italiano/tree/f5d5970e57745ae6d59e72983b494195a6167822),
  Copyright (c) 2026 WOW Forver - Italiano contributors, revision
  `f5d5970e57745ae6d59e72983b494195a6167822`: Italian spell descriptions and translation references.
  Upstream declares GPT Luna translation work; retained fields keep AI origin.
  See `wowforveritaliano-license.txt` for the complete MIT notice. Blizzard and other
  third-party game content retain their original ownership.

## Additional collected context

These projects supply labelled reference context. Their unresolved reuse terms prevent
unreviewed copying into shipping catalogs; downloaded context does not imply bundled text.

- [WoWita-quests](https://github.com/deemonder/WoWita-quests): Icedany, WoWita maintainers
  and the original wowpopolsku.pl contributors. No translation-data licence was located.
- [WoWLang](https://github.com/DiNaSoR/WoWLang): Platine, Dragonarab, Hakan YILMAZ and
  the WoWpoPolsku, WoWTR and WoWAR community contributors. Upstream README and LICENSE
  declarations conflict; this source remains context-only.
- [QuestTranslator Vanilla Turkish](https://github.com/devteabct78/questtranslator-vanilla-turkish):
  devteabct78 and the credited QuestTranslator/WoWpoPolsku contributors. The dataset targets
  OctoWOW Vanilla; no translation-data licence was located.

Forever Rosetta Stone adaptations may normalize player tokens, repair placeholders, or translate wording
from retained source text. AI-authored or AI-adapted wording retains AI origin in the catalogs.
AI-assisted placement of unchanged community text retains its community origin.
