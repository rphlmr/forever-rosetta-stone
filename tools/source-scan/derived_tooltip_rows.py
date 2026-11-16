"""Adapt renderer output using observed row ownership, not guessed row positions."""
import copy


def derive(data, translated, bindings, suppressions, *, visible_surface=False):
    """Retain captured metadata, with an explicitly derived visible representation.

    Bindings and suppressions come from the shipping renderer during this render.
    A visible talent surface can contain rows absent from its structured API payload;
    those rows remain visible-only rather than acquiring fabricated line types.
    """
    if len(bindings) != len(translated):
        return None, {'reason': 'missing_renderer_row_provenance'}
    if isinstance(suppressions, list):
        suppressions = {index: reason for index, reason in enumerate(suppressions, 1)}
    by_original = {}
    for index, binding in enumerate(bindings):
        if binding.get('ambiguous'):
            return None, {'reason': 'ambiguous_captured_row_identity', 'outputRow': index + 1}
        original = binding.get('originalIndex')
        if original is not None:
            by_original.setdefault(original, []).append(index)
        elif not visible_surface and binding.get('role') != 'title':
            return None, {'reason': 'unowned_rendered_row', 'outputRow': index + 1}
    result, retained = copy.deepcopy(data), []
    for original, line in enumerate(result['lines'], 1):
        emitted = by_original.get(original, [])
        # A partial API payload can start at the cost row while its title comes
        # from the visible frame. Its emitted body owns the raw row, not the title.
        body = [index for index in emitted if bindings[index].get('role') != 'title']
        emitted = body or emitted
        if len(emitted) > 1 and all(translated[index] == translated[emitted[0]] for index in emitted):
            emitted = emitted[:1]
        if not emitted:
            if original in suppressions:
                continue
            if line.get('leftText') or line.get('rightText'):
                return None, {'reason': 'unmapped_captured_text_row', 'sourceRow': original}
        elif len(emitted) == 1:
            row = translated[emitted[0]]
            for field, side in [('leftText', 'left'), ('rightText', 'right')]:
                if row[side] is None:
                    line.pop(field, None)
                else:
                    line[field] = row[side]
        elif not (isinstance(line.get('price'), (int, float)) and line.get('maxPrice', 0) > 0):
            return None, {'reason': 'unsupported_structured_expansion', 'sourceRow': original,
                          'outputRows': [index + 1 for index in emitted]}
        # Expanded price rows keep their captured numeric fields. Replaying the
        # same structured expansion uses those values instead of parsing its label.
        retained.append(line)
    result['lines'] = retained
    return result, None
