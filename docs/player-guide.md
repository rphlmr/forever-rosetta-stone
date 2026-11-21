# Player guide

[Back to the project](../README.md)

Examples below use a French client with English translations. Choose your own translation language in Settings.

## Feature settings

Open **Settings > AddOns > Forever Rosetta Stone**, or use **`/frs settings`**.
Scroll to a feature group and choose an option directly on its row. Hover a choice
to preview its effect before applying it. Changes take effect immediately.

Tooltip categories offer **Off**, **Name only**, or **All details** wherever detailed
translations are available. Choose the tooltip layout separately. **Separate tooltip**
enables the position selector for NPC translations.

Use **Live settings** to change options alongside the spellbook, talents or another game
window.

Choose the **Translation language** list, or run **`/frs language frFR`**, replacing `frFR`
with a catalog locale. English is the default. The choice is account-wide and does not change
the game client or another addon's language. Some added languages still have large coverage gaps.
The list excludes the game client's language, including its regional variants.

Left-click the minimap icon to open Settings. There is no minimap menu. Dragging the icon moves it
around the minimap and saves its position. Language changes refresh open translations immediately.

Controller users can enter the page from the native category list, navigate features with the
D-pad, and toggle the focused feature with **A / Cross**. **B / Circle** returns to categories;
press it again to close Settings. WoW handles navigation, dropdown choices, scrolling, and the yellow focus marker.

Features start enabled. The native scrollable list keeps every switch accessible by mouse or controller:

- Quest panel, including its bookmark and controller window registration.
- Quest-list and chat-link translation tooltips.
- World Map quest-marker translation tooltips.
- Reward comparison tooltips, when the quest panel is enabled.
- Translated item tooltips, including comparison tooltips.
- Translated spell and talent tooltips.
- Translated NPC tooltips.
- Quest tracker companions and NPC quest-offer titles.
- Minimap quest titles and minimap zone/subzone names.
- Mount and companion summon names and available descriptions; pet species names with a catalog match.
- Appearance names and shared tooltip instructions using the displayed source item. **Appearance categories** separately controls category hovers such as Chest and Shoulders under **Collections**.
- Dungeon, battleground and questing activity names on hover or controller focus in group finder.
- Quest-list location-header tooltips.
- Map hover-name translations.
- Map navigation dropdown translations.
- Minimap tracking-option translations.
- Viewed-map location path above the map's native place name, matching its color.
- White character-location translation beside coordinates.

On any Forever Rosetta Stone page, the header's **Defaults** button opens an addon-only confirmation.
Choose **Reset addon only** to restore English, every feature, Stacked, Full text, and NPC position Top.
Captures, error logs, minimap position, and other addons' settings are kept. Cancel with **B / Circle** or Escape.
Changes apply immediately without a reload.
It preserves the minimap icon's position. **`/frs reset`** restarts the addon while preserving
your choices. Disabling a focused panel or comparison clears its obsolete controller target.
Protected window-registration changes wait until combat ends; the disabled UI hides immediately.

## Item, spell, NPC, and talent names

Hover an item in your bags, equipment, or a chat link, or hover a spell in the spellbook or action bar.
Stacked mode adds translated content below the original tooltip content. In Separate tooltip mode,
item, spell, and talent translations appear beside the original tooltip.
Translations include available target-language details and supported live values. Missing target
text remains native and is marked incomplete. In Separate tooltip mode, NPC translations use the selected position around the
original: top, left, right, or bottom. The default is top. No tooltip title uses
the Forever Rosetta Stone logo. Original titles, rarity colors, details, owners, and anchors remain native.
Language and feature changes refresh open translations. Missing catalog names hide the translation.

Name companions copy their source tooltip's effective title font, shadow, line spacing, background
and border colors, and opacity. Title colors use the
native tooltip data when supplied, otherwise the rendered source title.

The following placement rules describe Separate tooltip mode. Single item, spell, talent and stat
tooltips retain their native position. When an automatic companion cannot fit on its preferred side,
it tries the opposite side without moving the original. NPC translations match the native tooltip's
width, keep their selected top/left/right/bottom position, and follow it when it moves.
The tracker uses the same placement beside its native tooltip when present, or beside the quest block otherwise.
Completed tracker quests show the same turn-in status as quest-list tooltips. Completed map pins
show only the translated title, without level brackets or completed objectives.
Minimap zone and subzone translations follow the selected tooltip display mode.
Each translated line matches its own source font size and text scale. The World Map hint
and territory information remain native. Chat quest links use the quest ID to translate their
summary and item requirements, preserving the game's displayed quantities.
Companions use a two-unit gap. Comparison rows retain the native order and spacing, with translations
on the outside: `FRS | Native | Native | FRS`. The complete row inherits the native outer anchor edge
and grows away from the hovered item, sliding inside the screen only when necessary.
Translated comparisons retain the equipped header and the client's completed stat-change summary,
including signed values and colors. Headers and common stat labels cover all supported languages;
other English stat labels use the client GlobalStrings mapping. Unmapped labels retain their native text.
Native placement settings are restored when the translations close or the group changes.

## Use the quest companion

1. Open the windowed map and quest log.
2. Hover or focus **Débuts modestes** in the quest list. The original French tooltip stays visible,
   and an English companion appears on its right, including the live compass count.
3. Open that quest's details. The English panel opens automatically with the native quest content
   order: decorated title, objective, progress, Description, and description text.
4. Close the translation with its title-bar X or the controller. Reopen it with the book bookmark
   on the map's right edge, using the mouse or the map's D-pad navigation and A / Cross.

The English hover companion appears for the visible quest list and native World Map quest markers,
using mouse hover or controller focus. Quest-list companions contain the summary and live progress.
Map-marker companions show only the title and live objectives, with the title following the native
quest difficulty color setting. Controller and click commands remain in the original tooltip.
The bookmark shows only its reopen tooltip.
Hover or focus the **Hurlevent** location header to see **Stormwind**. Mouse hover also works
while the gamepad interface is active. Known locations also get an English line beneath the
native map hover label, including **Comté-de-l'Or → Goldshire**. Unrecognized names show no English label.
Map navigation dropdowns show a translation to the right of the hovered or controller-focused
row, vertically centered beside the list border. Minimap tracking options use the same companion
on hover or controller focus, excluding “Uncheck All”. Service labels support English; tracking
spells use the catalog's selected language. The area catalog covers
the Eastern Kingdoms destinations shown in the dropdown, including **Bois de la Pénombre → Duskwood**
and **Rives Claires → Riverglades**.
The latter uses Blizzard's [French](https://worldofwarcraft.blizzard.com/fr-fr/news/24304071/world-of-warcraft-forever-found-photos-panel-recap)
and [English](https://worldofwarcraft.blizzard.com/en-gb/news/24304071/world-of-warcraft-forever-found-photos-panel-recap) place names.
The plain label above the map's place name identifies the viewed map, for example
**Eastern Kingdoms - Hillsbrad Foothills**, matching the native name's color. Known names are translated; other names remain in
the client language. When the native character coordinate line names a different player location,
its English name follows in white, such as **(Les Paluns) - Wetlands**.

Hover or focus Forever Rosetta Stone's item rewards to compare the reward with the items chosen by the native
comparison engine. Compact tooltips contain the item name, binding, and equipment slot/type,
with quality and restriction colors. Stats, effects, and prices are omitted. The equipped and
paired-item headers stay in the client language. Item-name translations come from the shared
database; missing translations retain the client name.
The binding and equipment labels cover the client's **48 GlobalStrings labels** and **100 item
subclasses** from build **1.60.1.70862**. Missing translations retain the original label.

If Spoken's place story is open, the translation stands to its right. Collapse the place story
with its own X to put the translation directly beside the quest log, as in the screenshots.
Both panels and tooltips are clamped to the screen; limited horizontal room can bring them
over other UI. The translation panel is hidden on a maximized map.
The English quest page follows the native details panel's top, height, scale, and clipping geometry.
Its outer shell aligns with the map's top and bottom borders. A standalone
opaque native window shell surrounds it, with the title **Forever Rosetta Stone: English**, an X button,
and a separate scrollbar gutter. Gaps follow the visible border artwork, including the space beside
Spoken when multiple panels are open. The side bookmark stays behind
adjacent windows. The quest header has no written controller hints. Native focus and scrollbar
prompts remain visible when using a gamepad.

## Controller first

With Forever's gamepad UI enabled, while a supported quest's details are open:

| Input | Action |
| --- | --- |
| LT / RT | Switch between visible windows using Blizzard's focus manager |
| Right stick up / down | Scroll the focused window with Blizzard's native scrolling |
| B / Circle | Close the English panel when it has focus |
| A / Cross on the title-bar X | Close the English panel |
| D-pad, then A / Cross | Select the right-side Forever Rosetta Stone bookmark and reopen a collapsed panel |

The English panel joins native window paging without taking focus automatically. Its LT/RT
prompts and focus glow use Blizzard's focus template. When selected, its native right-stick
prompt appears on its scrollbar. English and French text scroll independently. As you scroll down,
the English rewards area expands to reveal its remaining rows, following the native quest log.
Short quests and single-row rewards show the full rewards area immediately.
Returning from English to the same French quest restores the French reading position.
Entering English selects its title-bar X. Right-stick scrolling keeps that button selected,
so A / Cross can close the panel after scrolling.

There are no addon controller overrides or raw gamepad receivers. Right-stick click is left to
the game. Blizzard owns window switching, button navigation, scrolling, and the Back action.
Closing the map, leaving quest details, opening the game menu,
or opening Forever Rosetta Stone's error report withdraws the English panel from native window paging.
When collapsed, Forever Rosetta Stone has no window-paging registration or LT/RT focus prompts. Its Forever Rosetta Stone
bookmark belongs to quest-details navigation and disappears when returning to the quest list.
It is selected only through manual navigation. Back remains owned by the map.
Input-mode changes invalidate Forever Rosetta Stone's old focus registration. New native registrations wait
until combat ends if Blizzard's combat restriction prevents them.

`/frs quest` opens or closes the selected quest's English panel. The **Forever Rosetta Stone** entry
in Key Bindings does the same. Saved bindings are not rewritten. A collapsed panel can also be
reopened with the right-side bookmark. Selecting it with the D-pad and activating it returns
gamepad focus to the English panel. Reopening is unavailable during combat.

The English window is parented to `UIParent` and registers with Blizzard's focus manager while
open. The bookmark is a child of the native quest-details frame so Blizzard discovers it during button
navigation. Both follow the native quest panel's scale, alpha, and visibility.
No native targeting functions are replaced, and the panel is not registered in
`UISpecialFrames`.
