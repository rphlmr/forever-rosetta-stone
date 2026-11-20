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

Runtime lookups first use the captured option ID. Records with a unique
`sharedIcon` also supply a standard label for options with that native icon.
This applies to the flight option. Unrecognized options keep their native text.

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
