"""Define supported source locales and translatable catalog fields."""

import json
import re

SOURCE_PROVIDERS = frozenset(('wago', 'blizzard', 'questie', 'egLink'))


def source_build(provenance):
    """Compare declared game builds, never Git revisions or collection dates."""
    value = provenance.get('sourceBuild') or provenance.get('sourceNamespace') or ''
    match = re.fullmatch(r'(?:static-)?(\d+)\.(\d+)\.(\d+)[._](\d+)(?:-forever-[a-z]+)?', value)
    return tuple(map(int, match.groups())) if match else None


def preferred_source_rows(rows):
    """Prefer the newest comparable core-source build before origin-based tie breaks."""
    rows = list(rows)
    builds = [(row, source_build(json.loads(row['provenance']))) for row in rows]
    known = [(row, build) for row, build in builds
             if build and json.loads(row['provenance']).get('source') in SOURCE_PROVIDERS]
    if known:
        latest = max(build for row, build in known)
        rows = [row for row, build in builds if build is None or build == latest]
    return rows


def newer_core_source(candidate, current):
    """Require explicit comparable builds from both trusted providers."""
    candidate_build, current_build = source_build(candidate), source_build(current)
    if (candidate.get('source') not in SOURCE_PROVIDERS or current.get('source') not in SOURCE_PROVIDERS
            or not candidate_build or not current_build):
        return False
    return (candidate_build, candidate.get('source') == 'egLink') > (current_build, current.get('source') == 'egLink')


OFFICIAL_LOCALES = frozenset(('enUS', 'deDE', 'esES', 'esMX', 'frFR',
                             'koKR', 'ptBR', 'ruRU', 'zhCN', 'zhTW'))
# Forever's Italian client exports are English fallback; FRS maintains authored Italian targets.
ADDITIONAL_LOCALES = ('csCZ', 'daDK', 'hrHR', 'itIT', 'ltLT', 'plPL', 'svSE', 'trTR', 'ukUA')
TEXT_FIELDS = ('name', 'nameFemale', 'nameHorde', 'title', 'summary', 'description', 'auraDescription', 'rank',
               'nameDescription', 'setName', 'eventObjectiveLabel', 'subName', 'equipmentRequirement')
