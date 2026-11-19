# Forever quest dialogue

This local development addon borrows the FRS quest reader styling. It runs with a French
Forever client and an English FRS target while the FRS quest reader feature is enabled.
The native panels remain usable. The companion uses the reference dialogue only when the
displayed French matches a full source line for the live NPC, quest and panel type.
It follows the native window size, shows the quest titles available in the English FRS
catalog and joins the game's LT/RT panel navigation when gamepad UI is enabled.

Prepare the pilot from complete Spoken public search snapshots and a pinned QuestieDB
Forever export. Keep downloaded inputs, generated Lua and the audit under
`datasources/imports/`.

```sh
uv run --no-project --with lupa==2.8 python tools/quest-dialogue-pilot/prepare.py \
  --spoken datasources/imports/SPOKEN-RUN \
  --questie datasources/imports/QUESTIE-RUN/questie \
  --all-quests \
  --output datasources/imports/SPOKEN-RUN/pilot
```

The Spoken input directory contains `corpus.json.gz` and `revision.txt` from the pinned
GitHub export, plus `live.{enUS,frFR}.json` and `focus.{enUS,frFR}.json` from the public
quest search using `client=forever` and `client=focus`, respectively. The audit records
input hashes and the distinct line counts. Generated dialogue is a local evaluation
of public references with varying provenance. The base FRS release excludes it.
See [the Spoken source notes](../../datasources/spoken/SOURCE.md) for the two search
scopes, the identity checks and the boundary between the local pilot and catalog imports.

`--all-quests` removes the Northshire area restriction. It uses Forever-attributed pairs
and the Classic Era + Forever view, with Questie NPC and quest relationships checked for
combined-view quest phases. Greetings can match before or after turn-in. Progress and
turn-in use their dedicated screens, and offer text fills gaps in the core quest catalog.
Scripted chat follow-ups appear in the audit only. Omitting the option recreates the
Northshire scope.

Use `--observed` with a local JSON capture to add French variants to existing bilingual
lines. Each observation identifies the NPC, quest, stage, Spoken line and variant, and
provides the observed French template and source. An optional `playerSex` value scopes
the observation to the matching client character form.

Use `--vmangos` with a pinned local VMaNGOS SQLite snapshot to include vendor and trainer
options in the pilot. The audit preserves menu slots and BroadcastText IDs. The reader
matches the French option within the current NPC's visible menu.

Copy the generated `RosettaNorthshireDialogue` folder to the local Forever
`Interface/AddOns` directory. Reload in game, then talk to Deputy Willem and Marshal
McBride. View McBride's progression dialogue before completing the kobold objective
and his reward dialogue before completing the quest. Speak to him again after the
turn-in to check which dialogue the server sends next. Disable quest automation
during the test if it skips those panels.

`/frsdialogue` reports the current match status. `/frsdialogue off` hides and suspends
the pilot for the session. `/frsdialogue on` resumes it.
