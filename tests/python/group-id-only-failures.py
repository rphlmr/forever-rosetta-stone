#!/usr/bin/env python3
"""Partition strict ID-only matrix failures without changing their outcomes."""

import argparse
import collections
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REPORT = ROOT / "datasources/imports/id-only-matrix/report.json"

GROUPS = {
    "missing-target-translation": ("reported", "Supply or verify the missing target translation."),
    "missing-objective-identity": ("reported", "Find verified client objective indices before rendering amounts or lines."),
    "offer-structured-amounts": ("candidate", "Trace offered quest amounts using structured objective data."),
    "quest-objective-native-dependency": ("candidate", "Trace objective identity and rendering after removing the first native source lookup."),
    "quest-oracle-fixture": ("reported", "Investigate unresolved quest placeholder expectations and fixture context."),
    "rank-row-matching": ("candidate", "Trace rank row identity and rendering without target-label matching."),
    "item-field-row-identity": ("candidate", "Trace item field and row identity after removing the first target-label lookup."),
    "unavailable-id-render": ("candidate", "Inspect missing row identity or rendering prerequisites without inferring them from native text."),
    "renderer-mismatch": ("reported", "Compare actual output with the independent expectation and resolve the mismatch."),
    "numeric-reference-prerequisites": ("reported", "Investigate missing numeric or referenced data and oracle prerequisites."),
    "live-context": ("reported", "Investigate scaling context and whether the independent oracle can model it."),
    "unsupported-grammar-oracle": ("reported", "Investigate unsupported grammar or independent oracle limitations."),
    "unclassified": ("unknown", "Inspect this failure and add an evidence-based classification."),
}


def classify_failure(kind, failure):
    reason = failure["reason"]
    field = failure.get("field")
    normalized = reason.removeprefix("oracle limitation: ")

    if reason in {"missing target translation", "missing linked spell translation"}:
        return "missing-target-translation"
    if reason == "missing verified client objective index" or reason.startswith("objective amount has no verified client index"):
        return "missing-objective-identity"
    if reason == "unknown or unresolved placeholder expectation":
        return "quest-oracle-fixture"
    if reason == "forbiddenDependency":
        if kind == "quests" and field == "summary":
            return "offer-structured-amounts"
        if kind == "quests" and field == "objectiveLines":
            return "quest-objective-native-dependency"
        if kind == "spells" and field == "rank":
            return "rank-row-matching"
        if kind == "items":
            return "item-field-row-identity"
    if kind == "spells" and field == "rank" and reason == "no ID-based renderer for this field":
        return "rank-row-matching"
    if reason in {"untranslated", "nativeFallback"}:
        return "unavailable-id-render"
    if reason == "mismatch":
        return "renderer-mismatch"
    if normalized in {"spell power scaling", "unsupported effect scaling", "unsupported periodic scaling"}:
        return "live-context"
    if normalized.startswith("missing ") or normalized == "unknown or malformed linked spell identity or trigger":
        return "numeric-reference-prerequisites"
    if normalized in {
        "unsupported expression", "unsupported template grammar", "plural without amount",
        "malformed known-spell condition", "indexed spell value", "unsupported spell variable",
    }:
        return "unsupported-grammar-oracle"

    return "unclassified"


def hash_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as report_file:
        for chunk in iter(lambda: report_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def group_reports(report_path):
    report_path = Path(report_path)
    report = json.loads(report_path.read_text())
    groups = {}
    kind_totals = {}
    stage_hashes = {}

    for stage in report["stages"]:
        kind = stage["kind"]
        path = report_path.parent / Path(stage["report"]).name
        digest = hash_file(path)
        if digest != stage["reportSha256"]:
            raise ValueError(f"Stage report SHA-256 mismatch for {path}: {digest}")
        stage_report = json.loads(path.read_text())
        if stage_report["runId"] != report["runId"] or stage_report["kind"] != kind:
            raise ValueError(f"Stage report identity mismatch for {path}")
        failures = stage_report["failures"]
        if len(failures) != stage["counts"]["failed"] or len(failures) != stage_report["counts"]["failed"]:
            raise ValueError(f"Stage failure count mismatch for {path}")
        kind_totals[kind] = len(failures)
        stage_hashes[kind] = digest

        for failure in failures:
            group_id = classify_failure(kind, failure)
            if group_id not in groups:
                certainty, action = GROUPS[group_id]
                groups[group_id] = {
                    "id": group_id, "certainty": certainty, "action": action, "count": 0,
                    "perKind": collections.Counter(), "entities": set(), "samples": [],
                    "reasons": collections.Counter(),
                }
            group = groups[group_id]
            group["count"] += 1
            group["perKind"][kind] += 1
            group["entities"].add((kind, failure["id"]))
            group["reasons"][failure["reason"]] += 1
            if len(group["samples"]) < 5:
                group["samples"].append({"kind": kind, **failure})
        del failures, stage_report

    total = sum(kind_totals.values())
    if total != report["counts"]["failed"]:
        raise ValueError(f"Combined failure count mismatch: {total} vs {report['counts']['failed']}")
    result_groups = []
    for group_id in sorted(groups):
        group = groups[group_id]
        group["uniqueEntities"] = len(group.pop("entities"))
        group["perKind"] = dict(sorted(group["perKind"].items()))
        group["reasons"] = dict(sorted(group["reasons"].items()))
        result_groups.append(group)

    return {
        "runId": report["runId"], "reportSha256": hash_file(report_path), "stageSha256": stage_hashes,
        "failed": total, "perKind": kind_totals, "groups": result_groups,
        "note": "Every recorded failure is counted once. Candidate groups describe a first investigation, not a proven root cause.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = group_reports(args.report)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(f"Grouped {result['failed']} failures from run {result['runId']} into {args.output}")


if __name__ == "__main__":
    main()
