#!/usr/bin/env python3
"""Convert one `/frsverify api` capture into a versioned Lua test fixture.

Reads the literal SavedVariables file without executing Lua. The fixture replays recorded
client API returns in tests; it is regression evidence, never a catalog source. Captured
GlobalStrings are not copied into the fixture (tests read the catalog); `--globals-report`
compares them with the owned catalog values instead.
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from datasources.lua_data import assignments
from tools.build.runtime_catalog import decode_client_escapes as decode_export_escapes
from tools.catalogs.catalog_storage import dump_json

ROOT_NAME = 'RosettaTooltipCheckData'
FIXTURE_NAME = 'RosettaClientApiFixture'
FINISHED = ('api complete', 'api timeout')
IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
RESERVED = frozenset('and break do else elseif end false for function if in local nil not or repeat '
                     'return then true until while'.split())


def sequence(value):
    """Return a captured Lua array as a list, or None when it is not one."""
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and value and set(value) == set(range(1, len(value) + 1)):
        return [value[index] for index in range(1, len(value) + 1)]
    return None


def lua_string(text):
    out = []
    for char in text:
        code = ord(char)
        if char == '\\':
            out.append('\\\\')
        elif char == '"':
            out.append('\\"')
        elif char == '\n':
            out.append('\\n')
        elif char == '\r':
            out.append('\\r')
        elif code < 32 or code == 127:
            out.append('\\%03d' % code)
        else:
            out.append(char)
    return '"' + ''.join(out) + '"'


def lua_key(key):
    if isinstance(key, str):
        return key if IDENTIFIER.match(key) and key not in RESERVED else '[' + lua_string(key) + ']'
    if isinstance(key, bool):
        return '[' + ('true' if key else 'false') + ']'
    return '[' + lua_scalar(key) + ']'


def lua_scalar(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value) if value != int(value) or abs(value) >= 2 ** 53 else str(int(value))
    if isinstance(value, str):
        return lua_string(value)
    if value is None:
        return 'nil'
    raise ValueError('Unsupported captured value: ' + type(value).__name__)


def sort_key(key):
    return (0, key, '') if isinstance(key, (int, float)) and not isinstance(key, bool) else (1, 0, str(key))


def to_lua(value, indent=0):
    """Write a deterministic, human-readable Lua literal."""
    if not isinstance(value, (dict, list)):
        return lua_scalar(value)
    if not value:
        return '{}'
    pad, inner = '    ' * indent, '    ' * (indent + 1)
    items = sequence(value)
    if items is not None:
        lines = [inner + to_lua(item, indent + 1) + ',' for item in items]
    else:
        lines = [inner + lua_key(key) + ' = ' + to_lua(value[key], indent + 1) + ','
                 for key in sorted(value, key=sort_key)]
    return '{\n' + '\n'.join(lines) + '\n' + pad + '}'


def first_value(result, label):
    if not isinstance(result, dict) or result.get('status') != 'ok':
        raise ValueError('Capture has no readable ' + label)
    values = sequence(result.get('values')) or []
    return values


def build_fixture(capture, run_index, capture_sha256):
    runs = sequence(capture.get('runs')) if isinstance(capture, dict) else None
    if capture.get('schemaVersion') != 1 or runs is None:
        raise ValueError('Expected a schema 1 RosettaTooltipCheckData capture')
    if not 1 <= run_index <= len(runs):
        raise ValueError(f'Run {run_index} does not exist; the capture has {len(runs)} run(s)')
    run = runs[run_index - 1]
    if run.get('profile') != 'api':
        raise ValueError(f'Run {run_index} is a {run.get("profile")!r} run, not an api run')
    if run.get('stoppedReason') not in FINISHED:
        raise ValueError(f'Run {run_index} did not finish its api capture ({run.get("stoppedReason")!r})')
    samples = [sample for sample in sequence(run.get('samples')) or [] if sample.get('kind') == 'api']
    if len(samples) != 1:
        raise ValueError(f'Run {run_index} must contain exactly one api sample')
    details = samples[0]['details']
    build = first_value(run.get('build'), 'build')
    locale = first_value(run.get('locale'), 'locale')
    if len(build) < 2 or not isinstance(locale[0] if locale else None, str):
        raise ValueError('Capture build or locale is incomplete')
    return {
        'schemaVersion': 1,
        'build': f'{build[0]}.{build[1]}',
        'locale': locale[0],
        'source': {'captureSha256': capture_sha256, 'run': run_index,
                   'startedAt': run.get('startedAt'), 'stoppedReason': run['stoppedReason']},
        'pendingAtCapture': sequence(details.get('pendingAtCapture')) or [],
        'calls': details.get('calls') or {},
    }, details.get('globals') or {}


def explicit_ids(cases_path):
    """IDs named in the probe's hand-written `api.ids` inventory; tests rely on them."""
    text = cases_path.read_text(encoding='utf-8')
    block = text[text.index('ids = {') + len('ids = {'):]
    block = block[:block.index('\n        },')]
    return {kind: [int(value) for value in re.findall(r'\d+', values)]
            for kind, values in re.findall(r'(\w+) = \{([^}]*)\}', block)}


def limit_calls(calls, limit, keep):
    """Keep `limit` responses per API (lowest argument keys first) plus every explicit test ID."""
    kept_keys = {str(value) for values in keep.values() for value in values}
    kept_keys |= {f'"{prefix}:{value}"' for values in keep.values() for value in values for prefix in ('item', 'quest')}
    def order(key):
        digits = re.search(r'\d+', key)
        return (int(digits[0]) if digits else -1, key)
    limited = {}
    for api, responses in calls.items():
        keys = sorted(responses, key=order)
        chosen = set(keys[:limit]) | (kept_keys & set(keys))
        limited[api] = {key: responses[key] for key in keys if key in chosen}
    return limited


def compare_globals(captured, locale, root=ROOT):
    """Classify each captured client GlobalString against the owned catalog value."""
    owned = {}
    for path in (root / 'catalogs/globalstrings').glob('*.json'):
        if path.name == 'metadata.json':
            continue
        record = json.loads(path.read_text(encoding='utf-8'))
        entry = record.get('locales', {}).get(locale, {})
        owned[record['key']] = {'id': int(path.stem), 'name': entry.get('name'),
                                'origin': entry.get('translationMetadata', {}).get('fields', {}).get('name', {}).get('origin')}
    rows, counts = [], {}
    for key in sorted(captured):
        client = None if captured[key] == '<nil>' else captured[key]
        record = owned.get(key)
        catalog = record and record['name']
        if record is None:
            status = 'not in catalog'
        elif client is None:
            status = 'absent in client'
        elif catalog is None:
            status = 'no catalog value'
        elif catalog == client:
            status = 'identical'
        elif decode_export_escapes(catalog) == client:
            status = 'export escapes'
        else:
            status = 'different'
        counts[status] = counts.get(status, 0) + 1
        if status != 'identical':
            rows.append({'key': key, 'status': status, 'client': client, 'catalog': catalog,
                         'id': record and record['id'], 'origin': record and record['origin']})
    return {'locale': locale, 'counts': counts, 'differences': rows}


def render(fixture):
    header = ('-- Generated by tools/source-scan/import_client_api_fixture.py from an in-game\n'
              '-- `/frsverify api` capture. Regression evidence only; never a catalog source.\n')
    return header + FIXTURE_NAME + ' = ' + to_lua(fixture) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--capture', required=True, type=Path,
                        help='Backed-up rosetta-tooltip-check.lua SavedVariables file')
    parser.add_argument('--run', required=True, type=int, help='1-based api run index')
    parser.add_argument('--output', type=Path,
                        help='Fixture path (default: tests/fixtures/client-api/<build>-<locale>.lua)')
    parser.add_argument('--replace', action='store_true', help='Allow replacing an existing fixture')
    parser.add_argument('--limit-per-api', type=int,
                        help='Keep at most N responses per API in the fixture, plus the explicit IDs of cases.lua')
    parser.add_argument('--globals-report', type=Path,
                        help='New JSON report under datasources/imports/ comparing captured GlobalStrings to the catalog')
    args = parser.parse_args()
    raw = args.capture.read_bytes()
    parsed = list(assignments(raw.decode('utf-8'), [(ROOT_NAME,)]))
    if len(parsed) != 1 or not isinstance(parsed[0][1], dict):
        raise SystemExit('Expected one literal ' + ROOT_NAME + ' assignment')
    fixture, globals_captured = build_fixture(parsed[0][1], args.run, hashlib.sha256(raw).hexdigest())
    if args.globals_report:
        report_path = args.globals_report.resolve()
        if not report_path.is_relative_to((ROOT / 'datasources/imports').resolve()) or report_path.exists():
            raise SystemExit('The GlobalStrings report must be a new file under datasources/imports/')
    if args.limit_per_api:
        fixture['calls'] = limit_calls(fixture['calls'], args.limit_per_api,
                                       explicit_ids(Path(__file__).resolve().parent / 'rosetta-tooltip-check/cases.lua'))
        fixture['source']['limitPerApi'] = args.limit_per_api
    output = args.output or ROOT / 'tests/fixtures/client-api' / f'{fixture["build"]}-{fixture["locale"]}.lua'
    if output.exists() and not args.replace:
        raise SystemExit(f'{output} already exists; pass --replace to update it')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(fixture), encoding='utf-8')
    if args.globals_report:
        report = compare_globals(globals_captured, fixture['locale'])
        report['source'] = fixture['source']
        report_path.write_text(dump_json(report), encoding='utf-8')
        print(f'Wrote {report_path}: ' + ', '.join(f'{n} {s}' for s, n in sorted(report['counts'].items())))
    pending = fixture['pendingAtCapture']
    print(f'Wrote {output} ({fixture["build"]}, {fixture["locale"]}, {len(fixture["calls"])} APIs)')
    if pending:
        print('Not loaded when captured: ' + ', '.join(pending))


if __name__ == '__main__':
    main()
