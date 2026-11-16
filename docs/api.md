# Translation database API

[Back to the project](../README.md)

## Use ForeverRosettaStoneDB

Expose the catalogs through a single public global, **`ForeverRosettaStoneDB`**, so Forever Rosetta Stone's
components and other addons can use the same small, synchronous lookup API. Keep generated
tables private and publish no per-entity shorthand globals. Every lookup takes an entity ID
and an explicit target locale:

| Lookup | Result |
| --- | --- |
| `ForeverRosettaStoneDB:GetQuest(questID, locale)` | Selected quest text, objective templates, and `hasAITranslation` |
| `ForeverRosettaStoneDB:GetItemName(itemID, locale)` | Translated item name |
| `ForeverRosettaStoneDB:GetAreaName(areaID, locale)` | Translated zone or subzone name |
| `ForeverRosettaStoneDB:GetPlayerLocation(locale)` | Fresh zone/subzone snapshot resolved from live client names and candidate IDs |
| `ForeverRosettaStoneDB:GetMapName(mapID, locale)` | Available UI map name, using its separate UI map ID |
| `ForeverRosettaStoneDB:GetSpellName(spellID, locale)` | Translated spell name |
| `ForeverRosettaStoneDB:GetTalentName(talentID, locale)` | Translated talent name, using its linked spell where resolved during generation |
| `ForeverRosettaStoneDB:GetNpcName(npcID, locale)` | Translated NPC name |

`GetLocales()` returns the shared locale-name map. `IsQuestAITranslated(questID, locale)` and
`IsAITranslated(kind, id, locale)` return the generated AI flag. Unknown records return `nil`,
while existing records without AI text return `false`.
`GetTalentName` accepts **client DB2 Talent IDs**; live
talent API identifiers are not mapped or guessed. Rank-zero spell names are resolved during
generation. Location controls use `GetPlayerLocation(locale)` to resolve live client candidate IDs.
Quest objectives use verified client-index templates and live objective counts. Unmapped objectives
retain native text. Lookups are ID-based; the runtime does not ship reverse-name indexes.

Returned quest records are shared and treated as read-only. Unknown IDs or unavailable locales
return `nil`; missing quest fields remain absent. Lookups return only accepted translations for
the requested locale and do not silently substitute English or the client language. Each
component applies its documented missing-text behavior when rendering.

English targets use `enUS`; `enGB` is not a supported catalog or runtime language choice.
Historical field provenance may still identify an `enGB` source.

`GetItemDetails(id, locale)` and `GetSpellDetails(id, locale)` return available localized details.
`GetItemRules(id)` and `GetSpellRules(id)` expose shared numeric facts without loading translations.
Tooltip rendering selects original source and target templates by owned IDs, then captures the
client's displayed values. It never recalculates descriptions from character stats or aura points.
Missing prerequisites preserve native text. Shared numeric facts remain public catalog data;
they are not an alternate description renderer.

API version 3 uses one localized data pack per language plus shared rules. Duplicate source packs,
source-only getters and reverse-name lookups are removed. Diagnostics read the same localized
catalog records as the UI; these records can contain AI translations and are labeled accordingly.

Each caller supplies its own target locale; Forever Rosetta Stone's components use Forever Rosetta Stone's selected locale.
The API owns catalog access, the client owns live progress and rewards, and components own
rendering. The full catalogs retain relationships and field origins; the runtime export contains
only the selected text fields and AI flags. Runtime lookups perform
no network requests or writes and do not change QuestieDB's locale. Publish `apiVersion` and
`catalogVersion` on the same global so consumers can distinguish API compatibility from data updates.

Keep the catalog provider independent of Forever Rosetta Stone's UI, controller code, and saved preferences.
Forever Rosetta Stone initially bundles it and consumes the public API itself. The same provider and API can
later ship as a standalone addon for other addons to depend on. A distribution must load one
provider for the global; the standalone release must define dependency and load ownership before
shipping. Standalone packaging and publishing remain future work.

## Normal UI or API-only startup

The database is available in both modes. Players normally get the complete Forever Rosetta
Stone UI, and another addon can use the API at the same time. Declaring a dependency alone
does not disable the UI. There is no API-only checkbox in Settings.

For database-only use, run `/frs api on`, then `/reload`. To keep the normal UI, run
`/frs api off`, then `/reload`. `/frs api status` reports the active mode and the currently
requested startup mode. `/frs api auto`, then `/reload`, removes the explicit override:
the normal UI starts unless a dependent addon requests API-only startup again.
The explicit override is account-wide, like the existing addon preferences.

API-only startup skips UI preference initialization, panels, minimap button, settings
registration, controller setup, tooltip/map hooks, diagnostic monitoring hooks, and UI
update/event handlers. Only the startup listener, slash commands and catalog provider are
initialized. Catalog getters load the requested language packs on demand; the shared rules
pack is initialized at startup. The existing Lua modules and virtual XML templates still
load from the same addon TOC; this is not a separate database-only distribution.

Mode changes require a reload because already-installed hooks cannot be safely removed.
UI commands in API-only mode print instructions instead of opening windows. Existing UI
preferences are kept for the next normal session.

In normal mode, protected-action diagnostic listeners and the blocked-action reporting
hook are installed only when a console, error report or debug display is first opened.
They remain active until reload; normal startup does not install them. Ordinary error
containment for the addon's own callbacks remains active from startup.

### Example consumer addon

Keep Forever Rosetta Stone and its bundled data folders installed and enabled. In your
addon's TOC, declare a dependency so the provider loads before your Lua file:

```toc
## Interface: 16001
## Title: My Translation Addon
## Dependencies: ForeverRosettaStone
MyTranslationAddon.lua
```

`MyTranslationAddon.lua` can use the database with or without the FRS UI:

```lua
local db = ForeverRosettaStoneDB
assert(db and db.apiVersion == 3, "Forever Rosetta Stone API v3 is required")

-- Each caller selects its own locale; this does not change the FRS UI language.
local translatedName = db:GetItemName(6948, "frFR")
local quest = db:GetQuest(783, "deDE")
local spell = db:GetSpellDetails(133, "enUS")

-- Missing text stays absent. Preserve your native text when using these values.
local function ItemLabel(itemID, nativeName, locale)
    return db:GetItemName(itemID, locale) or nativeName
end
```

If your integration should request database-only startup, add this at file scope in your
Lua file, **before `PLAYER_LOGIN`**, rather than inside its login handler:

```lua
local frs = ForeverRosettaStone
local accepted, reason = frs:RequestAPIOnly()
-- A rejected request does not prevent database lookups. Continue using the API normally.
-- The player's explicit /frs api off choice always keeps the normal UI.
```

`RequestAPIOnly()` is a session-only request and does not write saved preferences. It
returns `true` when accepted, or `false, reason` if the player explicitly selected normal
mode or startup has already begun. A late request does not remove installed UI hooks;
request it earlier on the next reload. `ForeverRosettaStone:IsAPIOnly()` reports the active
mode after startup. This is one shared FRS instance: an accepted request suppresses its UI
for the whole session, not only for the caller. Offer that integration behavior deliberately.

`ForeverRosettaStone:SetAPIOnly(boolean)` sets the same persistent override as
`/frs api on` or `/frs api off`, for the next reload. Use it only for an explicit player action; do
not call it unconditionally during another addon's startup or overwrite the player's choice.

## Live zone and subzone resolution

`GetPlayerLocation(locale)` returns `{ uiMapID, zone, subzone }`. Each area record contains
`nativeName`, `status`, and, when resolved, a translated `name` and either `areaID` or `uiMapID`.
AreaTable IDs and UI map IDs are separate namespaces. Unsupported target locales return `nil`.

The resolver matches `GetZoneText()` and `GetSubZoneText()` against candidate names supplied by
`C_Map.GetAreaInfo()`, using the player's current map position. A unique area match selects
`GetAreaName(areaID, locale)`. If no candidate matches, an exact match against the current
map's live name can select `GetMapName(uiMapID, locale)`. This allows a broad zone to resolve
even when the exploration candidates contain only smaller areas. It never selects candidates
by array order or by translated wording, and does not load stored source-language name pages.

Statuses are `resolved`, `empty`, `unavailable`, `unresolved`, `ambiguous`, and
`missingTranslation`. Duplicate copies of one candidate ID are harmless; distinct IDs matching
the same name remain ambiguous. Unresolved records have no translated `name`; consumers should
retain their native line. Each call reads current client state without retaining a location
cache or changing another caller's target locale. Unlike ordinary catalog getters, this method
also reads the live location APIs; it makes no network requests or persistent writes.

Preferences use `ForeverRosettaStoneSettings`; the settings frame is separately named
`ForeverRosettaStoneSettingsPanel`. The public
database global is not a SavedVariable and neither catalogs nor API functions are serialized.
