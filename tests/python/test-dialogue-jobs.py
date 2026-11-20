"""Regression coverage for the English-only quest dialogue translation exception."""

import tempfile
import unittest
from pathlib import Path

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from datasources.spoken.catalogs import prepare
from tools.catalogs.dialogue_jobs import group_key, merge_translations
from tools.catalogs.catalog_storage import dump_json, read_json


class DialogueJobsTests(unittest.TestCase):
    def test_identical_quest_lines_share_a_job_only_for_the_same_speaker_and_phase(self):
        progress = {"stage": "progress", "npcId": 197}
        line = "Thank you, $N."
        first = group_key("catalogs/quests/7.json", progress, line)
        self.assertEqual(first, group_key("catalogs/quests/15.json", progress, line))
        for context in ({**progress, "stage": "complete"}, {**progress, "npcId": 240},
                        {**progress, "playerSex": 3}):
            self.assertNotEqual(first, group_key("catalogs/quests/15.json", context, line))
        self.assertNotEqual(first, group_key("catalogs/quests/15.json", progress, "Thank you."))

    def test_official_target_uses_owned_english_and_cannot_overwrite_existing_text(self):
        entry = {
            "dialogueContexts": {"first": {"stage": "progress"}},
            "locales": {"enUS": {"dialogue": {"first": "Thank you, $N."},
                "translationMetadata": {"fields": {"dialogue.first": {"origin": "community"}}}}},
        }
        batch = {"records": {"quests": {"7": entry}}, "localeConfig": {"locales": ["enUS", "deDE"]}}
        tokens = lambda text: text.count("$N")
        submitted = {"deDE": {"first": "Danke, $N."}}
        updated = merge_translations(batch, submitted, tokens)["quests"]["7"]
        self.assertEqual(updated["locales"]["deDE"]["translationMetadata"]["fields"]["dialogue.first"],
                         {"origin": "ai", "source": "ForeverRosettaStoneAI", "sourceLocale": "enUS"})
        self.assertNotIn("deDE", entry["locales"])
        with self.assertRaisesRegex(ValueError, "placeholder mismatch"):
            merge_translations(batch, {"deDE": {"first": "Danke."}}, tokens)
        batch["records"]["quests"]["7"] = updated
        with self.assertRaisesRegex(ValueError, "unavailable"):
            merge_translations(batch, submitted, tokens)

    def test_later_compatible_source_replaces_provisional_ai(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            quest_dir = root / "catalogs/quests"
            quest_dir.mkdir(parents=True)
            (quest_dir / "metadata.json").write_text(dump_json({
                "storageVersion": 2, "kinds": ["quests"],
                "document": {"schemaVersion": 1, "locales": ["enUS", "frFR", "deDE"]},
            }))
            quest = quest_dir / "7.json"
            quest.write_text(dump_json({"locales": {"enUS": {"title": "Test Quest"}}}))
            audit = root / "audit.json"
            audit.write_text(dump_json({"pairs": [{
                "npcID": 197, "questID": 7, "stage": "progress", "lineID": "q:7:progress", "variant": 0,
                "enUS": "Thank you, $N.", "frFR": "Merci, $N.",
            }]}))
            snapshots = root / "snapshots"
            snapshots.mkdir()
            prepare(root, audit, snapshots, root / "initial")
            generated = root / "initial/results/catalogs/quests/7.json"
            entry = read_json(generated)
            key, = entry["dialogueContexts"]
            batch = {"records": {"quests": {"7": entry}},
                     "localeConfig": {"locales": ["enUS", "frFR", "deDE"]}}
            provisional = merge_translations(batch, {"deDE": {key: "Danke, $N."}}, lambda text: text.count("$N"))
            quest.write_text(dump_json(provisional["quests"]["7"]))
            (snapshots / "deDE.json").write_text(dump_json({"offset": 0, "total": 1, "lines": [{
                "npcType": "creature", "npcId": 197, "questId": 7, "source": "progress",
                "lineId": "q:7:progress", "variant": 0, "lang": "deDE",
                "originalText": "Thank you, $N.", "text": "Habt Dank, $N.",
            }]}))
            prepare(root, audit, snapshots, root / "updated")
            imported = read_json(root / "updated/results/catalogs/quests/7.json")
            self.assertEqual(imported["locales"]["deDE"]["dialogue"][key], "Habt Dank, $N.")
            self.assertEqual(imported["locales"]["deDE"]["translationMetadata"]["fields"]["dialogue." + key]["source"],
                             "Spoken")
            self.assertEqual(imported["locales"]["frFR"], entry["locales"]["frFR"])


if __name__ == "__main__":
    unittest.main()
