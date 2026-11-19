# Spoken quest dialogue reference

Use Spoken to locate candidate quest and NPC dialogue during a local Forever investigation.
It is a comparison source for the quest panel and NPC dialogue pilot. It supplies no text to
the shipped catalogs or their translation queues.

- [Pinned quest corpus](https://github.com/rusty-key/spoken-wow/blob/9dd73894a1a736c3cc69e17c1bb4e8111d06f928/pipelines/quests/corpus/corpus.json.gz)
- [Public quest catalogue](https://spoken.quest/)
- [Upstream code and third-party terms](https://github.com/rusty-key/spoken-wow/blob/master/THIRD_PARTY.md)
- [Local pilot and reproducible audit](../../tools/quest-dialogue-pilot/README.md)

The English static corpus and the public search views have different scopes. Save the source
revision and full search snapshots for each locale and client filter under ignored
`datasources/imports/`. The pilot audit records their hashes and counts distinct lines by
stage, separating localized text from English fallbacks.

Join observations by NPC type and ID, quest ID where present, stage, line ID and variant.
Verify the live text and player-dependent variant on the same screen. A localized row in the
combined Classic Era and Forever view does not establish Forever provenance, and scripted
follow-up lines are chat dialogue. A gossip match alone does not indicate whether it appears
before offering or after completing a quest.

Spoken's MIT grant covers its code. Upstream identifies the game prose and contributions as
third-party text outside that grant. Keep the Spoken data, pilot output and derived wording local.
Before catalog admission, obtain reusable source evidence with verified Forever identity, stage,
locale, placeholders and provenance. Follow the project's
[import and translation rules](../../docs/import-resync.md) for official targets, English
fallback and the independent localized evidence required for additional-language jobs.
