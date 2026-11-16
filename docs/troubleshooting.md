# Troubleshooting and reports

[Back to the project](../README.md)

## Known limitations

### Unit-frame buff tooltips remain untranslated

Hovering a buff icon on a native unit frame can show only the original tooltip, with no
translated companion. This is a known limitation, reproduced with Demon Skin on the target
frame in WoW Forever **1.60.1 / 70888**, even though its French name and aura description
are present in the database. Changing between Stacked and Separate tooltip does not add
support for this surface.

This client uses a separate, hidden `AuraButtonTooltip` marked forbidden by Blizzard.
In the live check, a successfully registered `TooltipDataProcessor` post-callback for
`UnitAura` captured no event when hovering the affected buff. The existing companion
renderer therefore has no verified connection to this tooltip's aura identity, position,
or show/hide lifecycle. This does not establish that every possible integration is blocked.

The build-matched [aura button handler](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_AuraContainer/Blizzard_AuraButton.lua)
and [tooltip definition](https://github.com/Gethe/wow-ui-source/blob/4cd0ab752a77164f654ccbca9d0c1fe8dafceebe/Interface/AddOns/Blizzard_AuraContainer/Classic/Blizzard_AuraButtonTooltip.xml)
describe this native path. Support remains unresolved. No duplicate buff icons or
replacement aura row are added as a workaround. This limitation is specific to the native
unit-frame buff tooltip path, not a claim that all aura translations are unavailable.

## Addon error log

Open `/frs error`, or choose **Captures → Error log** in the console. The addon
automatically keeps its last ten callback errors and blocked native actions, including
timestamps, client builds, and stack traces. This history survives `/reload` and relogging.
Each entry is limited to 12,000 characters. It only records Forever Rosetta Stone's errors.

History stays saved until replaced by newer entries or removed with **Clear error log**.
That button clears all saved errors, current-session errors, and blocked-action entries.
It does not restart a paused addon or change settings and captures.

Use **Select output** to copy the report, or **Save report** with a controller.
After logging out, copy `WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua`
as `FRS-debug.txt` and attach the copy to your issue. Keep the original file.
WoW writes the saved history to disk when reloading or logging out.

## Capturing an NPC dialogue menu

Keep the NPC dialogue open and run `/frs gossip`. The console captures the NPC name and GUID,
client build and language, greeting text, and every option returned by the client, including its
IDs and other readable fields. Choose **Select output**, then press **Ctrl+C / Cmd+C** to copy
the report. **Save report** is also available when using a controller.

The report is a snapshot of that menu. Run the command again after opening a submenu to capture
its options. Capturing does not select an option. If no dialogue is open, the report says so
instead of collecting stale options.

Known options show a translated companion tooltip on mouse hover or controller focus.
The **NPC dialogue options** setting controls this feature. The initial catalog covers the
16 Stormwind guard directions in all 18 target languages; other menus and submenus need
their own captured option IDs. Missing translations never replace the native menu text.
See [dialogue catalog provenance](../catalogs/gossipoptions/README.md) for reused and authored names.

## Quest bug reports

Translated quest panels have a native **Options** button in their header. Choose
**This quest is bugged** to open the report modal for that quest. With a controller, focus
the Forever Rosetta Stone quest panel, select **Options** with **A / Cross**, then select the same action.
There is no direct Y / Triangle shortcut: custom footer bindings taint Blizzard's shared
gamepad binding stack in this client. The footer only displays native Select and Back prompts;
SmartNavigation handles those actions without an addon-created binding group.

When a quest has no translation, Forever Rosetta Stone uses the same quest page and framed Rewards area as a
translated quest. Its **Sorry we missed it** text follows the client language, independently of
Forever Rosetta Stone's translation language. A French client shows **Désolés pour cet oubli**, with **Bière × 100**
in a native reward row. Select **Prepare quest report** (localized to the client language), centered
in the quest header, to request the quest's data by ID. With a controller, focus Forever Rosetta Stone and press Down
from the title-bar X to reach the report button, then A / Cross. When loading finishes,
**Copy report** selects the text for **Ctrl+C / Cmd+C** on a keyboard. Paste it into a GitHub
issue and describe the problem. Use the [GitHub issue tracker](https://github.com/rphlmr/forever-rosetta-stone/issues/new). The sorry page only has its
**Prepare quest report** action; it does not show the extra header button.

The report includes the quest ID, client locale/build/date, addon and catalog versions, selected
translation language, title, completion/failure state, raw objective progress, raw tooltip
lines, and request errors. Quest-log information, summary and description are included only for a verified quest-log
entry. Text stays exactly as returned, without language detection or English comparisons.
The request has a five-second timeout and no retries; missing text is left absent.

This helper is part of Forever Rosetta Stone. It has no separate addon, catalog dependency,
bulk queue, or language restriction. Reports remain in memory and are not imported into the
catalog or saved automatically. Native controller navigation supports the report buttons,
right-stick scrolling, and B / Circle to close. Escape also closes it. There is no bug bookmark;
the existing reopen bookmark uses the Forever Rosetta Stone icon and can reopen the missing-quest page too.

## Debug console and reporting

Run `/frs`, or open **Settings → AddOns → Forever Rosetta Stone → Debug & reports**.
The console uses your current game language, independently of Forever Rosetta Stone's translation language.
The start screen offers **Inspect something**, **Addon report**, and **How to report**.
Captured entries appear in the left column; detailed, copyable output appears when selected.
Choose **Addon report** (or run `/frs status`)
to get version, language, settings, and captured errors for a bug report. Choose
**Clear captures** (or run `/frs clear`) to stop picking, remove the hover list, clear the
command field, delete the saved report, and return to the instructions. This preserves settings and addon errors.
Use `/frs help`, type `help` in the
command field, or choose the native **Help** button to reopen the same guide. It covers
settings and language selection, quest controls, entity inspection, picking, reports,
recovery, and performance capture. Switch to the **UI components** tab or run `/frs display`
to open native item, spell, quest, or crafting-recipe tooltips. Each type provides a default
sample; entering an ID or matching link is optional. Choose
**Pin tooltip** to keep the native link tooltip open, including quests. Recipe previews use
crafting spell IDs; recipe scrolls and crafted items use Item. Showing a tooltip closes the
console so it cannot obscure the tooltip or its translation. **Back to debug tools**, **Escape**,
or gamepad **Back** closes the preview and returns to the same component type and ID/link.
Gamepad **Select** can also activate the return button.
Choose **Compare equipped** for WoW's native equipment comparisons. Choose **Side by side**
for separate original and translated tooltips, or **Stacked** to combine them. These preview
choices do not change your saved settings. Equipment comparisons depend on the character's equipped items.

To report a translated surface without knowing its ID:

1. Open the relevant native panel, such as bags, talents, quests, or the map, and choose **Inspect something**.
2. The console stays visible at 15% opacity in the highest addon UI layer. All of its controls
   and scroll areas become click-through; hover or select native game elements through the window.
3. Choose the separate **Stop picking** control. The console returns to full opacity.
4. Select an entry from the hovered list, then choose **Select output** and press **Ctrl+C / Cmd+C**.
5. Open a [new GitHub issue](https://github.com/rphlmr/forever-rosetta-stone/issues/new)
   and paste the entire output into its description. Fill in the included steps to reproduce,
   expected behavior, and actual behavior fields. Add a screenshot if useful.

For a general addon problem, reproduce it and choose **Addon report**, then follow the same
copy-and-paste steps. The report contains addon/client versions, language, settings, and
captured errors. Each addon or entity report includes the GitHub destination and instructions.

In native gamepad mode, use the D-pad to move between actions and captured entries, Select
to activate, and Back to close. The report scroll area uses native controller scrolling.
Pick releases console focus so you can navigate the game panels normally; switch to the
**Stop picking** panel or reopen the console from Settings when finished.
For Steam Deck users without a keyboard, choose the desired report and **Save report**.
Log out to write `WTF/Account/<account>/SavedVariables/ForeverRosettaStone.lua`, then copy
that file as `FRS-debug.txt` and attach the copy to the GitHub issue from desktop mode.
Keep the original `.lua` file unchanged. The file contains the latest saved report
and addon settings. Saving again replaces that report; **Clear captures** deletes it.

The picker covers items and comparisons, spells and auras, talents, mounts, pets, NPCs,
quest links, quest lists and map pins, quest offers and tracking, quest interaction panels,
map context and player location, area labels, map and tracking menus, minimap quests and
locations, and character stats. Native gamepad focus uses the same component capture paths.
Visible translated labels are recorded while you explore; a surface does not need a tooltip.

Pick records at most 30 distinct entries. Repeated inspections update that entry's snapshot
and preserve its surface contexts. A new Pick session clears the previous list, and records
already visible tooltip and quest panel content. Capturing is off outside Pick mode. Reports
include client/addon/catalog versions, languages, settings, captured native tooltip data,
and available source/target catalog details. Missing captures and restricted values are
identified explicitly. Reports stay in memory and are not uploaded or imported automatically.
They provide bug-report and source-text evidence; translation quality and objective mappings
still require review before catalog changes.

The optional command field accepts `status`, `item ID`, `spell ID`, `npc ID`, `questid ID`,
`map ID`, `report`, `pick`, `stop`, `list`, `clear`, `gossip`, `error`,
`settings`, `language LOCALE`, `reset`, and `quest`. Local `--dev-debug` builds also expose
`bench start`, `bench stop`, and `bench report`.
Examples can be pasted with or without the `/frs` prefix. Direct queries such as
`/frs item 25` and `/frs spell 133` open the same report.

The command field also accepts `dump <Lua expression>` and pasted `/dump` expressions, including
function calls and immediately invoked function expressions. These execute as addon Lua when
Run or Enter is pressed; they are not restricted to read-only API queries. This requires a local development
build made with `--dev-debug`; normal releases do not include this command. Results include every return value, including `nil` and `false`, or
the syntax/runtime error. Probe snapshots have no depth or field-count truncation and mark cycles,
restricted values, and opaque objects; hidden engine data is not enumerable.

The separate developer-only quest collector uses `/frsscan`; see
[`tools/quest-scan/README.md`](../tools/quest-scan/README.md). It is never part of the shipped addon.

## Error handling

Addon callbacks, including the native scroll handlers it wraps, use protected execution. The
first caught failure **pauses the addon**, hides its frames, withdraws its native focus registration,
and prints one short chat message. If combat prevents registration cleanup, a guarded cleanup
handler completes it when combat ends, even while the addon is paused. It does not retry the failed callback every
frame or open an error dialog. Up to five diagnostic records remain in memory for the session.

- `/frs status`: open the copyable debug status report, including lifecycle, settings, and captured errors.
- `/frs error`: open a scrollable, copyable error report, including stack traces. Click the
  text and press Ctrl+C / Cmd+C. It works while Forever Rosetta Stone is paused; X or Escape closes it.
- `/frs reset`: rebuild the addon's UI and resume without reloading WoW. Reset is refused in combat.

The report window belongs to this addon, outside Blizzard's static-popup system and the quest
map's gamepad navigation tree. Select output explicitly gives its text field keyboard focus for copying.
Reports remain in memory for the session; a UI reload clears them.

Reset invalidates old callbacks and hides old frames. It does not reset other addons or game bindings.
No code replaces the game's error handler or suppresses another addon's errors. A permanent API
incompatibility will pause again and needs a code fix.

This cannot guarantee zero Lua errors or eliminate client bugs, protected-action failures, broken
addon files, or errors from other addons. Protected execution contains errors raised within our
callbacks; it does not turn an unsafe protected operation into a permitted one.
