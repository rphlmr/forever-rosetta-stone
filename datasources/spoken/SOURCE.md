# Spoken quest dialogue reference

Use Spoken to locate candidate quest and NPC dialogue for Forever. Prepared records retain its
provenance. For quest dialogue and NPC introductions, the addon uses the quest ID when
available, NPC, stage and player sex when all eligible lines agree in the target locale.
It checks the full live client text when the context leaves multiple possible translations.
NPC options use their live ID or a verified shared icon when possible.

- [Pinned quest corpus](https://github.com/rusty-key/spoken-wow/blob/9dd73894a1a736c3cc69e17c1bb4e8111d06f928/pipelines/quests/corpus/corpus.json.gz)
- [Public quest catalogue](https://spoken.quest/)
- [Upstream code and third-party terms](https://github.com/rusty-key/spoken-wow/blob/master/THIRD_PARTY.md)
- [Local pilot and reproducible audit](../../tools/quest-dialogue-pilot/README.md)

The English static corpus and the public search views have different scopes. Save the source
revision and full search snapshots for each locale and client filter under ignored
`datasources/imports/`. The pilot audit records their hashes and counts distinct lines by
stage, separating localized text from English fallbacks.

Join observations by speaker type and ID, quest ID where present, stage, line ID and variant.
For a quest started or completed through a game object, use `objectID` in the
reviewed audit. The catalog stores `objectId` and the addon matches a GameObject GUID.
Verify the live text and player-dependent variant on the same screen. A localized row in the
combined Classic Era and Forever view does not establish Forever provenance, and scripted
follow-up lines are chat dialogue. A gossip match alone does not indicate whether it appears
before offering or after completing a quest.

Spoken's MIT grant covers its code. Upstream identifies the game prose and contributions as
third-party text outside that grant. Raw snapshots and prepared results stay under ignored imports.
This workflow does not establish distribution rights. Follow the project's
[import and translation rules](../../docs/import-resync.md) for official targets, English
fallback and the independent localized evidence required for additional-language jobs.

Retain complete per-locale client=focus snapshots from the quest search endpoint in the
snapshot directory. English and French come from the paired audit. Other locales must match its
line identity and English wording. English fallbacks, narration and ambiguous translations are
excluded from those locale slots.

Run resync.py prepare-quest-dialogue with --audit, --snapshots and --output, then run
the normal apply and verify commands against that output directory.

Quest offer, progress and reward text live on the existing quest records. Greetings and
options live on the existing NPC records. Each owner records conditions in dialogueContexts,
localized text in locales[locale].dialogue and provenance under the matching
translationMetadata.fields entry. The normal database build packs each language.
Missing or ambiguous output leaves the live text in the native window.

After applying source updates, run `resync.py queue --directory UPDATE --output QUEUE`.
It proposes reusable translations in `QUEUE/dialogue-reuse` and lists the distinct remaining
jobs in `QUEUE/dialogue-translation-queue.json`. Use the normal `apply` and `verify` commands
for the reuse proposal, if present. Follow the
[catalog translation workflow](../../catalogs/AGENTS.md) to assign up to 125 entities to
each of six fresh workers. Use `catalog-batch.py prepare --batch-size 1` to keep a snapshot
and result per entity, then validate each compact locale-to-dialogue-key result with
`catalog-batch.py patch-dialogue`. The exception permits any target locale for a dialogue
with owned English. A later applicable sourced translation replaces the AI wording.
