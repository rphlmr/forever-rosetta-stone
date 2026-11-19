"""Audit Spoken snapshots and prepare an opt-in local FRS dialogue pilot."""

import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
from shutil import copyfile
import sqlite3

from lupa.lua51 import LuaRuntime


SOURCES = ("gossip", "progress", "complete", "followup")
# These narration cues are absent from Spoken's client-locale lookup for the same dialogues.
VOICE_DIRECTION = re.compile(r"^\[(?:curious|serious|warmly)\][ \t]+")
NORTHSHIRE_AREAS = {9, 24, 59, 16514, 16520, 16523, 16537}
NORTHSHIRE_BOUNDS = (44, 58, 24, 53)  # Candidate spawns on Questie's Elwynn map


def load_view(directory, scope, locale):
    data = json.loads((directory / f"{scope}.{locale}.json").read_text())
    rows = data["lines"]
    if data["offset"] != 0 or data["total"] != len(rows):
        raise ValueError(f"Incomplete Spoken view: {scope}.{locale}")
    return rows


def coverage(rows):
    localized = [row for row in rows if row["text"].strip() and not row.get("missing", {}).get("text")]
    fallback = [row for row in rows if row.get("missing", {}).get("text")]
    return {
        "rows": len(rows),
        "text": dict(Counter(source for source, _ in {(row["source"], row["lineId"]) for row in localized})),
        "fallback": dict(Counter(source for source, _ in {(row["source"], row["lineId"]) for row in fallback})),
    }


def list_npcs(questie_directory):
    db = questie_directory / "src/corrections/Forever/combined/foreverNpcDB.lua"
    npcs = LuaRuntime().execute(db.read_text())
    left, right, top, bottom = NORTHSHIRE_BOUNDS
    for npc_id, npc in sorted(npcs.items()):
        if not npc[7] or not npc[1]:
            continue
        positions = []
        for area, spawns in npc[7].items():
            for point in spawns.values():
                x, y = point[1], point[2]
                if area in NORTHSHIRE_AREAS or (area == 12 and left <= x <= right and top <= y <= bottom):
                    positions.append([area, x, y])
        if positions:
            yield npc_id, {
                "name": npc[1], "positions": positions, "flags": npc[15],
                "friendly": "A" in (npc[13] or ""),
                "starts": sorted(npc[10].values()) if npc[10] else [],
                "ends": sorted(npc[11].values()) if npc[11] else [],
            }


def identity(row):
    return tuple(row[key] for key in ("npcType", "npcId", "questId", "source", "lineId", "variant"))


def lua_string(text):
    escaped = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\r": "\\r", "\t": "\\t"}
    return '"' + "".join(escaped.get(ch, f"\\{ord(ch):03d}" if ord(ch) < 32 else ch) for ch in text) + '"'


def prepare(scope, en, fr):
    english = defaultdict(set)
    for row in en:
        if row["originalText"].strip():
            english[identity(row)].add(row["originalText"])

    pairs = {}
    for row in fr:
        npc = scope.get(row["npcId"])
        stage = row["source"]
        quest_id = row["questId"]
        if not npc or row["npcType"] != "creature" or stage not in SOURCES:
            continue
        if stage in ("progress", "complete") and quest_id not in npc["ends"]:
            continue
        if row.get("missing", {}).get("text") or row.get("narration") or row.get("override"):
            continue
        candidates = english[identity(row)]
        french = VOICE_DIRECTION.sub("", row["text"])
        if len(candidates) != 1 or not french.strip():
            continue
        target, = candidates
        if french.strip() == target.strip():
            continue
        pairs[identity(row)] = {
            "npcID": row["npcId"], "questID": quest_id, "stage": stage, "lineID": row["lineId"],
            "variant": row["variant"], "contributionID": row.get("contributionId"),
            "enUS": target, "frFR": french,
        }
        if french != row["text"]:
            pairs[identity(row)]["spokenFrFR"] = row["text"]
    return sorted(pairs.values(), key=lambda row: (row["npcID"], row["stage"], row["questID"] or 0, row["lineID"]))


def write_dialogues(output, pairs):
    by_npc = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    for row in pairs:
        # Spoken's follow-up is a chat event rather than a dialogue window.
        if row["stage"] != "followup":
            by_npc[row["npcID"]][row["stage"]][row["questID"] or 0].append(row)
    lines = ['-- Generated local pilot data. The audit JSON records source identity and provenance.',
             'local _, pilot = ...', 'pilot.dialogues = {']
    for npc, stages in sorted(by_npc.items()):
        lines.append(f"    [{npc}] = {{")
        for stage, quests in sorted(stages.items()):
            lines.append(f"        {stage} = {{")
            for quest, rows in sorted(quests.items()):
                lines.append(f"            [{quest}] = {{")
                for row in rows:
                    sex = f'playerSex = {row["playerSex"]}, ' if "playerSex" in row else ""
                    lines.append(f'                {{ {sex}frFR = {lua_string(row["frFR"])}, enUS = {lua_string(row["enUS"])} }},')
                lines.append("            },")
            lines.append("        },")
        lines.append("    },")
    lines.append("}")
    (output / "dialogues.lua").write_text("\n".join(lines) + "\n")


def observed_variants(path, pairs):
    fields = ("npcID", "questID", "stage", "lineID", "variant")
    known = {tuple(row[field] for field in fields): row for row in pairs}
    variants = []
    for observation in json.loads(path.read_text()):
        key = tuple(observation[field] for field in fields)
        if key not in known or not observation["frFR"].strip():
            raise ValueError(f"Observation without an existing bilingual line: {key}")
        sex = observation.get("playerSex")
        if sex is not None and (type(sex) is not int or sex not in (2, 3)):
            raise ValueError(f"Unknown observed player sex: {key}")
        variant = {**known[key], "frFR": observation["frFR"], "observation": observation["source"]}
        if sex is not None:
            variant["playerSex"] = sex
        variants.append(variant)
    return variants


def vendor_and_training_options(database, npcs):
    placeholders = ",".join("?" for _ in npcs)
    # The menu slot and BroadcastText ID are reference identifiers, not live GossipOption IDs.
    query = f"""
        SELECT DISTINCT c.entry, g.menu_id, g.id, g.option_broadcast_text,
               b.male_text, b.female_text, l.male_text_loc2, l.female_text_loc2
        FROM creature_template c
        JOIN gossip_menu_option g ON g.menu_id = c.gossip_menu_id
        JOIN broadcast_text b ON b.entry = g.option_broadcast_text
        JOIN locales_broadcast_text l ON l.entry = b.entry
        WHERE c.entry IN ({placeholders}) AND g.option_id IN (3, 5)
        ORDER BY c.entry, g.menu_id, g.id, g.option_broadcast_text
    """
    options = []
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
        for npc, menu, slot, broadcast, en_male, en_female, fr_male, fr_female in connection.execute(query, tuple(npcs)):
            for english, french in sorted({(en_male, fr_male), (en_female or en_male, fr_female or fr_male)},
                                          key=lambda pair: (pair[0] or "", pair[1] or "")):
                if english and french:
                    options.append({"npcID": npc, "menu": menu, "slot": slot, "broadcastTextID": broadcast,
                                    "enUS": english, "frFR": french})
    return options


def write_options(bundle, options):
    by_npc = defaultdict(set)
    for row in options:
        by_npc[row["npcID"]].add((row["frFR"], row["enUS"]))
    lines = ["local _, pilot = ...", "pilot.options = {"]
    for npc, pairs in sorted(by_npc.items()):
        lines.append(f"    [{npc}] = {{")
        for french, english in sorted(pairs):
            lines.append(f"        {{ frFR = {lua_string(french)}, enUS = {lua_string(english)} }},")
        lines.append("    },")
    lines.append("}")
    with (bundle / "dialogues.lua").open("a") as output:
        output.write("\n".join(lines) + "\n")


def write_report(output, coverage_by_view, paired_forever, selected, pairs):
    lines = [
        "# Spoken et Northshire", "",
        "L’export GitHub est une base de référence anglaise. Les vues publiques sont des instantanés du site.", "",
        "Les chiffres comptent les identifiants de réplique distincts avec du texte dans la langue demandée. "
        "La vue Forever de Spoken classe les contributions selon leur provenance. Elle laisse de côté "
        "les dialogues de l’extraction Vanilla repris dans Forever.", "",
        "| Vue | Langue | Dialogue de PNJ | Progression | Rendu | Après quête (scripté) |",
        "| --- | --- | ---: | ---: | ---: | ---: |",
    ]
    for (scope, locale), counts in coverage_by_view.items():
        cells = " | ".join(str(counts["text"].get(stage, 0)) for stage in SOURCES)
        lines.append(f"| {scope} | {locale} | {cells} |")
    cells = " | ".join(str(paired_forever.get(stage, 0)) for stage in SOURCES)
    lines.append(f"| Forever | enUS et frFR appariés | {cells} |")
    counts = coverage_by_view["Forever", "frFR"]["fallback"]
    lines.extend([
        "", "Dans la vue Forever en français, Spoken renvoie aussi des fallbacks anglais pour "
        f"{counts.get('gossip', 0)} dialogues, {counts.get('progress', 0)} répliques de progression et "
        f"{counts.get('complete', 0)} textes de rendu. Ils sont exclus des chiffres français.", "",
        "« Dialogue de PNJ » regroupe tous les gossips de Spoken, y compris les réponses aux options. "
        "Le corpus ne précise pas lequel s’affiche avant ou après une quête. Les lignes « après quête (scripté) » "
        "désignent des répliques du chat et sont distinctes d’une nouvelle ouverture du dialogue.", "",
        "## PNJ interactifs et locuteurs repérés dans la zone", "",
        "Le périmètre combine les zones Northshire et une fenêtre de coordonnées QuestieDB autour de l’abbaye, "
        "de la mine et des vignes. Les coordonnées ne prouvent pas la présence de chaque PNJ dans une phase précise.", "",
        "| PNJ | ID | Dialogue | Progression | Rendu | Après quête scripté |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ])
    by_npc = Counter((row["npcID"], row["stage"]) for row in pairs)
    for npc_id, npc in sorted(selected.items(), key=lambda entry: entry[1]["name"]):
        cells = " | ".join(str(by_npc[npc_id, stage]) for stage in SOURCES)
        lines.append(f'| {npc["name"]} | {npc_id} | {cells} |')
    lines.extend(["", "Les chiffres de cette table comptent les paires FR → EN par PNJ. "
                  "Les marchands ou autres PNJ sans réplique appariée restent en texte natif."])
    output.write_text("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spoken", required=True, type=Path)
    parser.add_argument("--questie", required=True, type=Path)
    parser.add_argument("--observed", type=Path, help="Optional French client observations of existing lines")
    parser.add_argument("--vmangos", type=Path, help="Optional local VMaNGOS SQLite reference for gossip menu options")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if "datasources/imports" not in str(args.output.resolve()) + "/":
        parser.error("All generated output belongs under datasources/imports.")
    args.output.mkdir(parents=True)
    bundle = args.output / "RosettaNorthshireDialogue"
    bundle.mkdir()

    inputs = [args.spoken / "corpus.json.gz"]
    snapshot = json.loads(gzip.decompress(inputs[0].read_bytes()))
    if snapshot["lineCount"] != len(snapshot["lines"]):
        raise ValueError("Truncated Spoken export")
    views = {("GitHub", "enUS"): coverage(snapshot["lines"])}
    for scope, label in (("live", "Forever"), ("focus", "Classic Era + Forever")):
        for locale in ("enUS", "frFR"):
            inputs.append(args.spoken / f"{scope}.{locale}.json")
            views[label, locale] = coverage(load_view(args.spoken, scope, locale))

    en, fr = (load_view(args.spoken, "focus", locale) for locale in ("enUS", "frFR"))
    speakers = {row["npcId"] for row in en + fr if row["npcType"] == "creature"}
    located = dict(list_npcs(args.questie))
    selected = {
        npc_id: npc for npc_id, npc in located.items()
        if npc_id in speakers or ((npc["flags"] or npc["starts"] or npc["ends"]) and npc["friendly"])
    }
    pairs = prepare(selected, en, fr)
    observations = observed_variants(args.observed, pairs) if args.observed else []
    if args.observed:
        inputs.append(args.observed)
    write_dialogues(bundle, pairs + observations)
    options = vendor_and_training_options(args.vmangos, selected) if args.vmangos else []
    write_options(bundle, options)
    live_en, live_fr = (load_view(args.spoken, "live", locale) for locale in ("enUS", "frFR"))
    live_en_ids = {identity(row) for row in live_en if row["text"].strip()}
    paired_forever = Counter(stage for stage, _ in {
        (row["source"], row["lineId"]) for row in live_fr
        if not row.get("missing", {}).get("text") and row["text"].strip() and identity(row) in live_en_ids
    })
    write_report(args.output / "coverage.md", views, paired_forever, selected, pairs)
    audit = {
        "spokenRevision": (args.spoken / "revision.txt").read_text().split()[0],
        "staticGeneratedAt": snapshot["generatedAt"],
        "questieRevision": json.loads((args.questie / "source.json").read_text())["revision"],
        "inputs": {file.name: hashlib.sha256(file.read_bytes()).hexdigest() for file in inputs},
        "views": {f"{view}.{locale}": counts for (view, locale), counts in views.items()},
        "pairedForever": dict(paired_forever),
        "locatedCreatures": located, "candidates": selected, "pairs": pairs, "observedVariants": observations,
        "gossipOptions": options,
    }
    (args.output / "audit.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    for filename in ("pilot.lua", "RosettaNorthshireDialogue.toc"):
        copyfile(Path(__file__).with_name(filename), bundle / filename)


if __name__ == "__main__":
    main()
