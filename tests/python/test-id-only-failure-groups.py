import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).with_name("group-id-only-failures.py")
SPEC = importlib.util.spec_from_file_location("id_only_failure_groups", MODULE_PATH)
groups = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(groups)


class IdOnlyFailureGroupTests(unittest.TestCase):
    def write_reports(self, directory):
        stage_path = directory / "stage.json"
        failures = [
            {"id": 1, "field": "rank", "reason": "forbiddenDependency"},
            {"id": 1, "field": "rank", "reason": "forbiddenDependency"},
            {"id": 2, "field": "description", "reason": "mismatch"},
            {"id": 3, "field": "description", "reason": "future reason"},
        ]
        stage = {"kind": "spells", "runId": "run", "counts": {"failed": 4}, "failures": failures}
        stage_path.write_text(json.dumps(stage))
        report = {
            "runId": "run", "counts": {"failed": 4},
            "stages": [{
                "kind": "spells", "report": str(stage_path), "counts": {"failed": 4},
                "reportSha256": hashlib.sha256(stage_path.read_bytes()).hexdigest(),
            }],
        }
        report_path = directory / "report.json"
        report_path.write_text(json.dumps(report))
        return report_path, stage_path

    def test_partition_counts_each_failure_and_unique_entity(self):
        with tempfile.TemporaryDirectory() as tmp:
            report_path, _ = self.write_reports(Path(tmp))
            result = groups.group_reports(report_path)

        by_id = {group["id"]: group for group in result["groups"]}
        self.assertEqual(result["failed"], 4)
        self.assertEqual(sum(group["count"] for group in result["groups"]), 4)
        self.assertEqual(by_id["rank-row-matching"]["count"], 2)
        self.assertEqual(by_id["rank-row-matching"]["uniqueEntities"], 1)
        self.assertEqual(by_id["rank-row-matching"]["certainty"], "candidate")
        self.assertEqual(by_id["unclassified"]["count"], 1)
        self.assertEqual(by_id["renderer-mismatch"]["count"], 1)

    def test_rejects_changed_stage_report(self):
        with tempfile.TemporaryDirectory() as tmp:
            report_path, stage_path = self.write_reports(Path(tmp))
            stage_path.write_text(stage_path.read_text() + " ")
            with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
                groups.group_reports(report_path)

    def test_first_forbidden_call_is_only_a_candidate(self):
        failure = {"field": "effect", "reason": "forbiddenDependency", "forbiddenCalls": ["matcher:TranslateTargetLabel"]}
        group_id = groups.classify_failure("items", failure)
        self.assertEqual(group_id, "item-field-row-identity")
        self.assertEqual(groups.GROUPS[group_id][0], "candidate")


if __name__ == "__main__":
    unittest.main()
