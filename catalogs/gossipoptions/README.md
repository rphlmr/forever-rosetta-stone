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

Runtime lookups use only these owned option records. Unknown options keep their
native text without a translation tooltip. New options require their own
captured IDs and catalog records, not runtime exceptions.
