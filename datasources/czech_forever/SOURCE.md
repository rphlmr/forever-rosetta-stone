# Czech Forever

- Upstream and contributor credit: https://www.curseforge.com/wow/addons/czechforever
- Language: `csCZ`.
- Scope: Main release archive (text only is extracted), quest fields, NPC names and exact-English item/spell name references. Text AI usage is unknown; declared AI narration does not establish text authorship.
- Retained license and attribution: [czechforever-license.txt](../../ForeverRosettaStone/notices/czechforever-license.txt).

This active CurseForge datasource discovers the latest approved public Forever release without
a Core API key. Fetches retain the file ID, release version, download URL, raw archive, source
notices and hashes under `datasources/imports/`. Explicit replay pins bypass discovery.
Refreshes build source evidence in SQLite; they never change catalogs automatically.
Keep field authorship and source attribution. A community source is not automatically
higher quality than our existing text. Hash keys are not entity IDs, and unrelated Classic
content must not replace changed Forever content just because an ID matches.

Underlying game content remains Blizzard Entertainment's property. Source code and
translation-data licenses can differ; keep the retained upstream notices when using text.
