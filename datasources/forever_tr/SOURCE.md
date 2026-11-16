# ForeverTR

- Upstream: https://www.curseforge.com/wow/addons/forevertr
- Language: `trTR`.
- Credit and terms: Red Lion Labs; MIT code and CC BY-SA 4.0 Turkish data. Upstream declares AI-assisted translations.
- Scope: Numeric quest/item/NPC IDs only. Hash-keyed spell descriptions, names and untyped UI/dialogue are excluded. Unsupported markup remains flagged for review.

The refresh discovers the latest approved public Forever release from the CurseForge website
file listing, without a Core API key. Explicit replay pins bypass discovery. Every snapshot
retains the archive, exact file ID, version, date, download URL, SHA-256 and upstream notices.
Downloaded Lua is parsed as literal data and never executed. A refresh builds source evidence
in SQLite and does not edit maintained catalogs. Normal import policy and review still apply.
