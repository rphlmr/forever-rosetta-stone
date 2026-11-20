"""Prepare and validate missing translations under the quest-dialogue exception."""

from collections import Counter, defaultdict
import copy
from pathlib import Path

from tools.catalogs.catalog_storage import dump_json, get_digest, read_json
from datasources.spoken.catalogs import normalized, sha256


def source_dialogue(entity):
    en = entity.get("locales", {}).get("enUS", {})
    fields = en.get("translationMetadata", {}).get("fields", {})
    return {key: text for key, text in en.get("dialogue", {}).items()
            if text.strip() and key in entity.get("dialogueContexts", {})
            and fields.get("dialogue." + key, {}).get("origin") in ("community", "original")}


def set_translation(entity, locale, key, text, origin):
    localized = entity["locales"].setdefault(locale, {})
    localized.setdefault("dialogue", {})[key] = text
    fields = localized.setdefault("translationMetadata", {}).setdefault("fields", {})
    fields["dialogue." + key] = dict(origin)


def description_donor(entity, locale, key, source):
    english = entity["locales"]["enUS"]
    if (entity["dialogueContexts"][key]["stage"] != "accept"
            or normalized(english.get("description", "")) != normalized(source)):
        return
    localized = entity["locales"].get(locale, {})
    text = localized.get("description")
    origin = localized.get("translationMetadata", {}).get("fields", {}).get("description", {})
    if text and origin.get("origin") in ("original", "community", "ai") \
            and normalized(text) != normalized(source):
        return text, origin


def merge_translations(batch, translations, tokens):
    """Accept only absent dialogue fields with owned English and preserved tokens."""
    records = copy.deepcopy(batch["records"])
    if len(records) != 1:
        raise ValueError("One NPC or quest per dialogue translation assignment")
    kind, = records
    if kind not in ("quests", "npcs") or len(records[kind]) != 1:
        raise ValueError("Dialogue assignments must contain exactly one quest or NPC")
    entity = next(iter(records[kind].values()))
    sources = source_dialogue(entity)
    supported = set(batch["localeConfig"]["locales"]) - {"enUS"}
    for locale, lines in translations.items():
        if locale not in supported or not isinstance(lines, dict):
            raise ValueError("Invalid dialogue target: " + locale)
        current = entity["locales"].get(locale, {}).get("dialogue", {})
        for key, text in lines.items():
            if key in current or key not in sources or not isinstance(text, str) or not text.strip():
                raise ValueError(f"Dialogue slot is unavailable for authoring: {locale}/{key}")
            source = sources[key]
            if tokens(source) != tokens(text) or source.count("\\n") != text.count("\\n"):
                raise ValueError(f"Dialogue placeholder mismatch: {locale}/{key}")
            origin = {"origin": "ai", "source": "ForeverRosettaStoneAI", "sourceLocale": "enUS"}
            donor = description_donor(entity, locale, key, source)
            if donor and donor[0] == text:
                origin = donor[1]
            set_translation(entity, locale, key, text, origin)
    return records


def group_key(relative, context, text):
    stage = context["stage"]
    if stage == "option" and type(context.get("broadcastTextId")) is int:
        identity = ("broadcastText", context["broadcastTextId"])
    elif stage in ("accept", "progress", "complete") and type(context.get("npcId")) is int:
        identity = ("questSpeaker", context["npcId"])
    else:
        identity = (relative,)
    return (stage, identity, context.get("playerSex"), text)


def queue(root, directory, manifest):
    root, directory = Path(root).resolve(), Path(directory).resolve()
    locales = [locale for locale in read_json(root / "catalogs/quests/metadata.json")["document"]["locales"]
               if locale != "enUS"]
    scope = manifest.get("dialogueScope", sorted({entry["path"] for entry in manifest["files"]}))
    owners, donors = {}, defaultdict(list)
    for relative in scope:
        path = (root / relative).resolve()
        if (path.parent not in (root / "catalogs/quests", root / "catalogs/npcs")
                or path.suffix != ".json" or not path.stem.isdecimal()):
            raise ValueError("Invalid dialogue owner: " + relative)
        raw = path.read_bytes()
        entity = read_json(path)
        families = {key: group_key(relative, entity["dialogueContexts"][key], text)
                    for key, text in source_dialogue(entity).items()}
        owners[relative] = (sha256(raw), entity, families)
        for locale in locales:
            localized = entity["locales"].get(locale, {})
            meta = localized.get("translationMetadata", {}).get("fields", {})
            for key, family in families.items():
                text = localized.get("dialogue", {}).get(key)
                origin = meta.get("dialogue." + key, {})
                if text and origin.get("origin") in ("original", "community", "ai"):
                    donors[locale, family].append((text, origin))
                donor = description_donor(entity, locale, key, family[-1])
                if donor:
                    donors[locale, family].append(donor)

    reused, pending, rank = Counter(), {}, {"original": 0, "community": 1, "ai": 2}
    directory.mkdir(parents=True, exist_ok=True)
    reuse_dir = directory / "dialogue-reuse"
    files = []
    for relative, (before, entity, families) in owners.items():
        changed = False
        for locale in locales:
            current = entity["locales"].get(locale, {}).get("dialogue", {})
            for key, family in families.items():
                if key in current:
                    continue
                candidates = sorted(donors.get((locale, family), []), key=lambda item: rank[item[1]["origin"]])
                if candidates:
                    text, origin = candidates[0]
                    best = rank[origin["origin"]]
                    if len({value for value, meta in candidates if rank[meta["origin"]] == best}) == 1:
                        set_translation(entity, locale, key, text, origin)
                        reused[locale] += 1
                        changed = True
                        continue
                job_id = get_digest((locale, family))
                job = pending.setdefault(job_id, {"targetLocale": locale, "sourceLocale": "enUS",
                    "text": family[-1], "stage": family[0], "pointers": []})
                job["pointers"].append({"path": relative, "key": key})
        if changed:
            result = "results/" + relative
            target = reuse_dir / result
            target.parent.mkdir(parents=True, exist_ok=True)
            raw = dump_json(entity).encode()
            target.write_bytes(raw)
            files.append({"path": relative, "result": result, "beforeSha256": before, "afterSha256": sha256(raw)})

    if files:
        reuse_dir.mkdir(parents=True, exist_ok=True)
        (reuse_dir / "manifest.json").write_text(dump_json({
            "sourceType": "questDialogue", "policyInputs": manifest["policyInputs"],
            "dialogueScope": scope, "files": files,
        }))
    summary = {"eligibleJobs": len(pending), "remainingSlots": sum(len(job["pointers"]) for job in pending.values()),
               "reusedSlots": sum(reused.values()), "reusedByLocale": dict(reused)}
    (directory / "dialogue-translation-queue.json").write_text(dump_json({
        **summary, "jobs": pending,
    }))
    return summary
