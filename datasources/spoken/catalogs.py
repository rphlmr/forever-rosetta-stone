"""Prepare reviewed reference dialogue alongside the owning quest or NPC record."""

from collections import Counter, defaultdict
import hashlib
from pathlib import Path
import re

from tools.build.runtime_catalog import EXCLUDED_QUEST_STATUSES, NPC_DIALOGUE_STAGES, QUEST_DIALOGUE_STAGES
from tools.catalogs.catalog_storage import dump_json, get_entity_path, load_catalog, read_json
from tools.catalogs.english_scope import has_english_text, identity_field
from tools.catalogs.official_text import OFFICIAL_LOCALES


VOICE_DIRECTION = re.compile(r"^\[(?:curious|serious|warmly)\][ \t]+")
PLAYER_SEX = {"m": 2, "f": 3}


def sha256(raw):
    return hashlib.sha256(raw).hexdigest()


def normalized(text):
    return " ".join(text.replace("\\n", "\n").replace("’", "'").split())


def source_key(row, audit=False):
    if audit:
        return ("creature", row["npcID"], row["questID"] or 0, row["stage"], row["lineID"], row["variant"])
    return (row["npcType"], row["npcId"], row["questId"] or 0, row["source"], row["lineId"], row["variant"])


def candidates(path, locale, wanted):
    view = read_json(path)
    if view["offset"] != 0 or len(view["lines"]) != view["total"]:
        raise ValueError("Incomplete source view: " + str(path))
    result = defaultdict(set)
    for row in view["lines"]:
        if (row.get("lang") != locale or row.get("narration") or row.get("override") or row.get("ignored")
                or row.get("missing", {}).get("text") or not row.get("text") or not row.get("originalText")):
            continue
        key = (*source_key(row), normalized(row["originalText"]))
        if key not in wanted:
            continue
        text = VOICE_DIRECTION.sub("", row["text"])
        if text.strip() and normalized(text) != key[-1]:
            result[key, PLAYER_SEX.get(row.get("playerGender"))].add(text)
    return result


def dialogue_rows(audit):
    seen = set()
    for row in audit["pairs"] + audit.get("observedVariants", []):
        if row["stage"] not in QUEST_DIALOGUE_STAGES | NPC_DIALOGUE_STAGES:
            continue
        identity = (source_key(row, audit=True), row.get("playerSex"), row["enUS"], row["frFR"])
        if identity in seen:
            continue
        seen.add(identity)
        yield row
    for row in audit.get("gossipOptions", []):
        key = ("option", row["npcID"], row["broadcastTextID"], row["frFR"], row["enUS"])
        if key not in seen:
            seen.add(key)
            yield {**row, "questID": None, "stage": "option", "lineID": str(row["broadcastTextID"]), "variant": 0}


def prepare(root, audit_path, snapshots, output, locales=None):
    root, audit_path, output = (Path(path).resolve() for path in (root, audit_path, output))
    snapshots = Path(snapshots).resolve()
    inputs = {str(audit_path.relative_to(root)): sha256(audit_path.read_bytes())}
    audit = read_json(audit_path)
    configured = load_catalog(root, "quests", ids={})["locales"]
    if locales is not None:
        configured = [locale for locale in configured if locale in locales]
    rows = list(dialogue_rows(audit))
    wanted = {(*source_key(row, audit=True), normalized(row["enUS"])) for row in rows if row["stage"] != "option"}
    per_locale = {}
    for locale in configured:
        path = snapshots / (locale + ".json")
        if locale in ("enUS", "frFR") or not path.is_file():
            continue
        inputs[str(path.relative_to(root))] = sha256(path.read_bytes())
        per_locale[locale] = candidates(path, locale, wanted)

    by_owner = defaultdict(list)
    for row in rows:
        owner = ("quests", row["questID"]) if row["stage"] in QUEST_DIALOGUE_STAGES else ("npcs", row["npcID"])
        by_owner[owner].append(row)

    output.mkdir(parents=True)
    files, scope, captured, held = [], [], Counter(), Counter()
    for (kind, entity_id), entries in sorted(by_owner.items()):
        path = get_entity_path(root, kind, entity_id)
        if not path.is_file():
            held["ownerNotInCatalog"] += len(entries)
            continue
        before = path.read_bytes()
        entity = read_json(path)
        if not has_english_text(entity, identity_field(kind)) or entity.get("usageStatus") in EXCLUDED_QUEST_STATUSES:
            held["ownerNotShipped"] += len(entries)
            continue
        relative = str(path.relative_to(root))
        scope.append(relative)
        contexts = entity.setdefault("dialogueContexts", {})
        for row in entries:
            raw_key = (*source_key(row, audit=True), row.get("playerSex"), row["enUS"], row["frFR"])
            key = sha256(dump_json(raw_key).encode())[:20]
            npc_id, sex = row["npcID"], row.get("playerSex")
            context = {"stage": row["stage"], "lineId": row["lineID"], "variant": row["variant"],
                       "scope": row.get("scope", "vanilla-reference")}
            if kind == "quests":
                context["npcId"] = npc_id
            if sex is not None:
                context["playerSex"] = sex
            if row.get("contributionID") is not None:
                context["contributionId"] = row["contributionID"]
            if row.get("observation"):
                context["observation"] = row["observation"]
            if row["stage"] == "option":
                context["broadcastTextId"] = row["broadcastTextID"]
            contexts.setdefault(key, context)
            texts = {locale: row[locale] for locale in ("enUS", "frFR")}
            lookup = (*source_key(row, audit=True), normalized(row["enUS"]))
            if row["stage"] != "option":
                for locale, index in per_locale.items():
                    matches = index.get((lookup, sex)) or index.get((lookup, None))
                    if matches and len(matches) == 1:
                        texts[locale], = matches
                    elif matches:
                        held["ambiguousLocaleText"] += 1
            for locale, text in texts.items():
                record = entity["locales"].setdefault(locale, {})
                dialogue = record.setdefault("dialogue", {})
                fields = record.setdefault("translationMetadata", {}).setdefault("fields", {})
                if key in dialogue and fields.get("dialogue." + key, {}).get("origin") != "ai":
                    continue
                dialogue[key] = text
                source = "VMaNGOS" if row["stage"] == "option" else "Spoken"
                if locale == "frFR" and row.get("observation"):
                    source = "ForeverClientObservation"
                fields["dialogue." + key] = {
                    "origin": "original" if source == "ForeverClientObservation" else "community",
                    "source": source, "sourceLocale": locale,
                }
                if source == "Spoken":
                    snapshot = audit_path if locale in ("enUS", "frFR") else snapshots / (locale + ".json")
                    fields["dialogue." + key]["sourceSha256"] = inputs[str(snapshot.relative_to(root))]
                captured[locale] += 1
        after = dump_json(entity).encode()
        if before != after:
            result = "results/" + relative
            target = output / result
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(after)
            files.append({"path": relative, "result": result, "beforeSha256": sha256(before),
                          "afterSha256": sha256(after)})

    manifest = {"policyInputs": inputs, "files": files, "sourceType": "questDialogue", "dialogueScope": scope,
                "localizedLines": dict(captured), "held": dict(held),
                "officialTargetsWithoutSnapshot": sorted(OFFICIAL_LOCALES.intersection(configured)
                                                        - {"enUS", "frFR"} - per_locale.keys())}
    (output / "manifest.json").write_text(dump_json(manifest))
    return {key: val for key, val in manifest.items()
            if key not in ("files", "policyInputs", "dialogueScope")} | {"changedFiles": len(files)}
