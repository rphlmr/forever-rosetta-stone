# Changelog

## [Unreleased]

## [1.0.1] - 2026-11-17

### Fixed

- Fixed stacked tooltip translations pausing the addon when a tooltip contains restricted client text.

### Changed

- The minimap icon turns red while translations are paused; click it to open the error report.

## [1.0.0] - 2026-11-16

### Added

- Initial release of **Forever Rosetta Stone**, exclusively for **WoW Forever**.
- Quest translations in a companion panel beside the original quest windows, including available titles, descriptions, objectives and rewards.
- Translated quest tooltips for the quest list, tracker, chat links, map markers and NPC quest offers, with supported live objective progress.
- Item, spell and talent tooltip translations, including supported effects, live values and equipment comparisons. Choose translations below the original tooltip or in a separate companion.
- Translations for supported profession recipes, reagents and tracked recipes; NPC and player details; mounts, companions, appearances, books, group finder activities and character stats.
- Zone and subzone translations on the map and minimap, with supported map navigation and tracking labels.
- Per-feature settings, mouse and native gamepad navigation, and an in-game console for collecting bug reports.
- A public translation database API for other addons. The normal UI and API can run together; optional API-only startup skips the FRS interface and its hooks.

### Translations

- Bundled translation data for 18 languages, available offline while playing.
- Game data, community translations and AI-generated or adapted translations, with source credits and AI indicators where applicable.

### Known limitations

- Coverage varies by language and content. Missing translations or unavailable decoding context can leave native text, an incomplete-translation notice, or no translated companion.
- Buff tooltips on native unit frames remain in the game's language, even when a translation exists.
- Designed for WoW Forever's native Blizzard UI. Compatibility with custom UI addons and tooltip replacements is unverified.
