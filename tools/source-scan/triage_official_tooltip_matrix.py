#!/usr/bin/env python3
"""Separate proven missing evidence from decoder candidates in a capture matrix."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

import official_tooltip_matrix as matrix
import report_tooltip_gaps as gaps
from roundtrip_tooltip_campaign import quantities


def normalized(value):
    return re.sub(r'\s+', ' ', re.sub(r'\|[cC][0-9a-fA-F]{8}|\|[rR]', '', value or '')).replace('’', "'").strip()


def numeric_context(replay, locale):
    addon = replay.lua.globals().ReplayAddon
    def label(key, source=locale):
        value = addon.GetClientLabel(addon, key.encode(), source.encode())
        return value.decode() if value is not None else None
    magnitudes = {}
    # The decoder's threshold evidence is currently bounded to these clients.
    if locale in ('enUS', 'frFR'):
        for key, english, exponent in [('FIRST_NUMBER', 'thousand', 3), ('SECOND_NUMBER', 'million', 6),
                                       ('THIRD_NUMBER', 'billion', 9), ('FOURTH_NUMBER', 'trillion', 12)]:
            source = label(key)
            if label(key, 'enUS') == english and source:
                forms = re.fullmatch(r'\|7([^;]+);', source)
                for form in forms[1].split(':') if forms else [source]:
                    magnitudes[form] = exponent
    return label('DECIMAL_SEPERATOR') or '.', label('LARGE_NUMBER_SEPERATOR') or '', magnitudes


def numeric_template_equivalence(replay, event):
    """Prove word/digit equivalence through a whole owned spell description."""
    if event['kind'] not in ('spell', 'aura'):
        return []
    evidence = event.get('evidence') or {}
    expected, returned = evidence.get('expected', []), evidence.get('returned', [])
    if len(expected) != len(returned):
        return []
    locale = event['target']
    decimal, grouping, magnitudes = numeric_context(replay, locale)
    pivot = 'enUS' if locale != 'enUS' else 'frFR'
    addon = replay.lua.globals().ReplayAddon
    proof = []
    for index, (before, after) in enumerate(zip(expected, returned)):
        for side in ('left', 'right'):
            left, right = before.get(side), after.get(side)
            values = lambda text: quantities([{'left': text}], decimal, grouping, magnitudes)
            if values(left) == values(right):
                continue
            if not isinstance(left, str) or not isinstance(right, str):
                return []
            field = b'auraDescription' if event['kind'] == 'aura' else b'description'
            first = addon.TranslateLiveSpellDescription(addon, event['id'], pivot.encode(), left.encode(), field)
            second = addon.TranslateLiveSpellDescription(addon, event['id'], pivot.encode(), right.encode(), field)
            if first is None or first != second:
                return []
            proof.append({'row': index, 'side': side, 'owner': f"spells/{event['id']}",
                          'field': field.decode(), 'pivotLocale': pivot, 'canonicalText': first.decode(),
                          'expectedText': left, 'returnedText': right})
    return proof


def owned_missing_fields(replay, observation, target, row):
    """Return evidence only for absent fields tied to the captured owner's IDs."""
    db = replay.database
    kind, entity = observation['kind'], observation['id']
    if kind not in ('item', 'spell', 'aura'):
        return []
    getter = db.GetItemDetails if kind == 'item' else db.GetSpellDetails
    source = matrix.copied_rows(getter(db, entity, observation['locale'].encode())) or {}
    destination = matrix.copied_rows(getter(db, entity, target.encode())) or {}
    text = normalized(row.get('text'))
    if kind == 'item' and source.get('set', {}).get('name'):
        name = source['set']['name']
        if text.startswith(normalized(name)) and not destination.get('set', {}).get('name'):
            return [{'owner': f'items/{entity}', 'field': 'setName', 'locale': target,
                     'sourceText': name, 'reason': 'Missing owned target set name'}]
    if kind not in ('spell', 'aura') or row.get('lineType') != 'UsageRequirement':
        return []
    rules = matrix.copied_rows(db.GetSpellRules(db, entity)) or {}
    lines = gaps.clean(observation.get('data', {})).get('lines', [])
    native = next((line for line in lines if normalized(line.get('leftText')) == text), {})
    if not native:
        # A derived row retains captured metadata, but its wording has changed.
        # Use a sole typed requirement owner only; multiple owners stay unresolved.
        candidates = [line for line in lines if line.get('type') == gaps.LINE_TYPES.index('UsageRequirement')]
        if len(candidates) == 1:
            native = candidates[0]
    requirement = native.get('requirementType')
    references = rules.get('equipmentRequirementSources', {}).get(requirement, {})
    own = requirement is not None and requirement == rules.get('equipmentRequirementType')
    source_id = entity if own else references.get(observation['locale'])
    target_id = entity if own else references.get(target)
    source_record = matrix.copied_rows(db.GetSpellDetails(db, source_id, observation['locale'].encode())) if source_id else None
    target_record = matrix.copied_rows(db.GetSpellDetails(db, target_id, target.encode())) if target_id else None
    if source_record and normalized(source_record.get('equipmentRequirement')) == text \
            and not (target_record or {}).get('equipmentRequirement'):
        return [{'owner': f'spells/{source_id}', 'field': 'equipmentRequirement', 'locale': target,
                 'reason': 'No owned target label for this verified equipment signature',
                 'equipment': rules.get('requiredEquipment'), 'sourceText': source_record['equipmentRequirement']}]
    missing = []
    for field, getter, namespace in (
        ('requiredForms', db.GetShapeshiftFormName, 'shapeshiftforms'),
        ('requiredItemSubclasses', db.GetItemSubclassName, 'itemsubclasses'),
    ):
        for owner in rules.get(field, []):
            name = getter(db, owner, observation['locale'].encode())
            translated = getter(db, owner, target.encode())
            if name and normalized(name.decode()) in text and not translated:
                missing.append({'owner': f'{namespace}/{owner}', 'field': 'name', 'locale': target,
                                'sourceText': name.decode(), 'reason': 'Missing owned requirement name'})
    return missing


def generation_loss(replay, event, observation):
    """Explain a failed true return from observed generation, without feeding it hints."""
    if event['source'] == observation['locale'] or event['target'] != observation['locale']:
        return None
    generation = event.get('generationProvenance') or {}
    texts = {normalized(row.get('text')) for row in event.get('rows', [])}
    unresolved = []
    for proof in generation.get('decoderProofs', []):
        rendered = normalized(proof.get('renderedText'))
        if rendered and any(rendered in text for text in texts):
            for slot in proof.get('slots', []):
                if slot.get('unresolved'):
                    unresolved.append({'owner': proof['owner'], 'field': proof['field'],
                                       'nativeText': proof['nativeText'], 'slot': slot})
    if unresolved:
        return 'inherited_unresolved_client_value', unresolved
    db = replay.database
    for origin in generation.get('rowProvenance', []):
        for side, field in [('left', 'leftText'), ('right', 'rightText')]:
            text = normalized(origin['generatedRow'].get(side))
            native = normalized(origin['nativeRow'].get(field))
            if not text or text not in texts or not native:
                continue
            keys = matrix.copied_rows(db.GetGlobalStringKeysByText(db, text.encode(), event['source'].encode())) or []
            targets, original = {}, []
            for key in keys:
                value = db.GetGlobalStringByKey(db, key.encode(), event['target'].encode())
                if value:
                    targets[key] = value.decode()
                source = db.GetGlobalStringByKey(db, key.encode(), observation['locale'].encode())
                if source and normalized(source.decode()) == native:
                    original.append(key)
            if original and len(set(targets.values())) > 1:
                return 'derived_semantic_context_loss', [{'nativeText': native, 'generatedText': text,
                    'matchingGeneratedKeys': keys, 'matchingOriginalKeys': original, 'targetLabels': targets}]
    return None


def triage(report, directory):
    observations = {}
    wanted = {case['key'] for case in report['cases']}
    for observation in matrix.observations(directory):
        key = matrix.fingerprint(observation)
        if key in wanted:
            observations.setdefault(key, observation)
    replay = gaps.Replay('enUS', {})
    matrix.cache_catalog(replay)
    events, counts, case_sets, numeric_replays = [], Counter(), {}, {}
    for failure in report['failures']:
        event = dict(failure)
        status = event['status']
        evidence = event.get('evidence') or {}
        if status == 'missing_captured_player_context':
            category = 'missing_client_context'
        elif status == 'blocked_source_generation':
            category = ('replay_alignment_gap' if evidence.get('reason') in (
                'unsupported_row_alignment', 'unsupported_unit_row_alignment', 'missing_renderer_row_provenance',
                'ambiguous_captured_row_identity', 'unowned_rendered_row', 'unmapped_captured_text_row',
                'unsupported_structured_expansion')
                        else 'blocked_by_forward_failure')
        elif status == 'numeric_difference':
            decimal, grouping, magnitudes = numeric_context(replay, event['target'])
            before = quantities(evidence['expected'], decimal, grouping, magnitudes)
            after = quantities(evidence['returned'], decimal, grouping, magnitudes)
            event['reviewedQuantities'] = {'before': before, 'after': after}
            category = 'numeric_formatting_only' if before == after else 'numeric_review_required'
            if category == 'numeric_review_required':
                locale = event['target']
                if locale not in numeric_replays:
                    numeric_replays[locale] = gaps.Replay(locale, {})
                numeric_replay = numeric_replays[locale]
                observation = observations[event['case']]
                numeric_replay.install_calls(observation['calls'], observation.get('unit'))
                proof = numeric_template_equivalence(numeric_replay, event)
                if proof:
                    category = 'numeric_template_equivalent'
                    event['templateEquivalence'] = proof
        elif status in ('native_incomplete', 'derived_incomplete'):
            origin = observations[event['case']]
            observation = dict(origin, locale=event['source'])
            findings = [owned_missing_fields(replay, observation, event['target'], row) for row in event.get('rows', [])]
            event['missingOwnedFields'] = [finding for row in findings for finding in row]
            category = ('missing_owned_translation' if findings and all(findings)
                        else 'decoder_or_source_mismatch' if status == 'native_incomplete'
                        else 'derived_decoder_or_adapter_failure')
            loss = generation_loss(replay, event, origin) if status == 'derived_incomplete' else None
            if loss:
                category, event['contextLossEvidence'] = loss
        else:
            category = 'runtime_or_catalog_error'
        event['category'] = category
        counts[category] += 1
        case_sets.setdefault(category, set()).add(event['case'])
        events.append(event)
    unavailable = []
    for case in report['cases']:
        if case['nativeStatus'] == 'replayed':
            continue
        category = {'loading': 'loading_capture', 'missing_native_context': 'missing_client_context',
                    'not_applicable': 'unsupported_owner'}.get(case['nativeStatus'], 'unsupported_capture')
        event = dict(case, category=category)
        observation = observations.get(case['key'], {})
        if category == 'missing_client_context' and case['kind'] == 'aura':
            event['requiredEvidence'] = 'Matching captured aura instance, tooltip getter arguments and C_UnitAuras response'
        unavailable.append(event)
    return {'schemaVersion': 1, 'directionEventCounts': dict(counts),
            'uniqueNativeCasesByCategory': {key: len(values) for key, values in case_sets.items()},
            'unavailableNativeCaseCounts': dict(Counter(event['category'] for event in unavailable)),
            'unavailableNativeCases': unavailable, 'events': events,
            'limitations': ['Categories can overlap for one native case across different directions.',
                           'Derived decoder failures require separating runtime bugs from derived metadata adapters.',
                           'Decoder/source mismatches are candidates, not a claim that source text is correct.',
                           'Missing owned translations are catalog coverage gaps, not missing gameplay context.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--fixtures', type=Path, default=gaps.ROOT / 'tests/fixtures/tooltip-campaign')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not args.output.resolve().is_relative_to((gaps.ROOT / 'datasources/imports').resolve()):
        parser.error('Reports belong under datasources/imports/')
    result = triage(json.loads(args.report.read_text()), args.fixtures)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({key: result[key] for key in ('directionEventCounts', 'uniqueNativeCasesByCategory', 'unavailableNativeCaseCounts')}))


if __name__ == '__main__':
    main()
