"""Fetch and export one pinned QuestieDB Forever revision."""

import re
import subprocess
import sys

from datasources.common import ROOT, latest_revision, write_json


REPOSITORY = 'https://github.com/Questie/QuestieDB.git'


def fetch(output, revision=None):
    revision = revision or latest_revision(REPOSITORY)
    output.mkdir(parents=True)
    subprocess.run(['git', 'init', '-q', str(output)], check=True, timeout=30)
    subprocess.run(['git', '-C', str(output), 'fetch', '--depth=1', REPOSITORY, revision],
                   check=True, timeout=180)
    subprocess.run(['git', '-C', str(output), 'checkout', '--detach', 'FETCH_HEAD'], check=True, timeout=30)
    actual = subprocess.check_output(['git', '-C', str(output), 'rev-parse', 'HEAD'], text=True, timeout=30).strip()

    if actual != revision:
        raise ValueError('Questie checkout differs from selected revision')

    # The upstream exporter uses paths relative to its working directory.
    subprocess.run([sys.executable, '-c',
                    'from lupa.lua51 import LuaRuntime; lua=LuaRuntime(); '
                    'lua.globals().arg=lua.table_from(["--include-authored"]); '
                    'lua.execute(\'dofile("tools/export-forever.lua")\')'],
                   cwd=output, check=True, timeout=180)
    write_json(output / 'source.json', {'repository': REPOSITORY, 'revision': revision})

    return {'path': str(output.relative_to(ROOT)), 'revision': revision}


def quest_ids(output):
    paths = [output / 'src/corrections/Forever/combined/foreverQuestDB.lua']
    paths.extend((output / 'l10n/Forever/lookupQuests').glob('*.lua'))
    paths.extend((output / 'l10n/Forever/traces/lookupQuests').glob('*.lua'))
    ids = set()

    for path in paths:
        ids.update(map(int, re.findall(r'^\s*(?:quest)?\[(\d+)\]\s*=', path.read_text(), re.M)))

    if not ids:
        raise ValueError('Questie export contains no quest IDs')

    return ids
