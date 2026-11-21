# NPC dialogue options

Each record is keyed by the live `C_GossipInfo.GetOptions().gossipOptionID`,
never the array position or `orderIndex`. The French names of the initial
16 guard directions were captured with `/frs gossip` on Forever 1.60.1.70938
on 2026-11-15. Their exact text remains in each record with native provenance.

For these 16 options, the user explicitly authorized translations in all 18
configured languages, including missing English and official-language text.
Authored names retain `ai` provenance. This scoped authorization does not
change the general import/resync policy for other entities or future options.

Existing destination/service names were reused with their field provenance:

| Option | Owned name reused |
| --- | --- |
| 96916 | globalstrings/20327 |
| 96914 | areas/2257 |
| 96910 | globalstrings/18587 |
| 96909 | globalstrings/17564 |
| 96906 | globalstrings/17565 |
| 96905 | globalstrings/17566 |
| 140186 | areas/17203 |
| 141988 | globalstrings/18788 |
| 141989 | globalstrings/35642 |

These reused names identify the same service/destination; they are not a claim
to have captured the original gossip wording in every client language. Missing
names were translated from the captured French. The guild service is distinct
from the player guild-leader label, so that GlobalString was not reused.

Runtime lookups use the captured option ID or an explicitly verified universal
service icon (such as the flight option icon). Unrecognized IDs keep their
native labels.

NPC dialogue routes live on the owning NPC's `dialogueContexts` entry.
`gossipRoute.visible` lists verified option IDs visible alongside a passage.
`gossipRoute.selected` lists the options that open a terminal passage. The
runtime uses a selected ID only on the next gossip screen for the same
creature, when the client reports no options. Another NPC can reuse a
route when its client data supplies the same option ID. Ambiguity leaves
the native dialogue available. Client text is retained for reports and
translation provenance.

The Ironforge guard menu was captured on Forever 1.60.1.70959 (NPC 274781).
Twelve options reuse the equivalent destination or service names already in this
catalog and retain their exact captured French labels. The bank (95418) uses the
[VMaNGOS Classic reference](https://github.com/vmangos/core/releases/download/db_latest/db-sqlite-70e38cd.zip) for
BroadcastText 5078, the [Blizzard Ironforge guide](https://news.blizzard.com/pt-br/article/23149294/tour-urbano-em-wow-classic-altaforja)
for Brazilian Portuguese, and translations from English for additional locales.

Gryth Thurden's flight option (97329) was captured in French on Forever
1.60.1.70959. [Zephras](https://zephras.com/forever/enUS/npc/1573/) confirms the
English label, VMaNGOS BroadcastText 3409 supplies matching reference locales,
and Brazilian Portuguese uses the English fallback.

The Stormwind Guard (NPC 1423) menu was captured in French on Forever 1.60.1.71037.
Options 95310–95315 reuse the service names from 95408, 95409, 95412, 95414,
95415 and 95416 respectively. The bank (95316) uses GlobalString 24710 and the
transmogrifier (141422) uses 141989. Each option retains the exact captured French
label. Icon 132053 is shared by all eight options.

Laurena's talent reset option (97309) and Brother Joshua's equivalent (97311)
were captured in French on Forever 1.60.1.71037 with the same label and icon.
The shared option uses that exact French wording and reuses the other locales
from Brandur Ironhammer's existing talent reset dialogue.

Argus (NPC 514) offered trainer option 95665 on Forever 1.60.1.71037. Its
translations reuse his existing training dialogue (BroadcastText 3266), with
the French option verified in the capture. His separate blacksmith greeting
is captured French with provisional translations from French in the other
17 locales. The eight additional bank labels for 95316 use English as source.

Allison's innkeeper menu (NPC 6740, build 1.60.1.71037) supplies the French
labels and icons for options 96504–96506. The other locales reuse Allison's
vendor and bind options and Boorand Plainswind's dungeon option. Allison's
menu and the equivalent Boorand options have their own observed IDs.
The dungeon submenu reuses activity names 799, 1982 and 1984. The follow-up
question uses the captured French wording and the English label from
[Allison's Forever dialogue](https://db.icy-veins.com/wow-forever/npcs/6740).

The three observed dungeon choices and the three follow-up options each use
their captured IDs. The Lordaeron and Hall of Thanes follow-up IDs also bind
the corresponding terminal passages on Allison's NPC record.

Olivia Burnside's deposit box option (95532) uses the French label and icon
captured on Forever 1.60.1.71037 and reuses the other locales from the
equivalent option on NPC 2456.
