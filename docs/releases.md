# Changelog and releases

[Back to the project](../README.md)

## Project description

Use the root [README](../README.md) as the CurseForge project description, choosing the
**Markdown** editor. Its links use full GitHub URLs so they also resolve outside the repository.
Publish the README and linked guides on the repository's public `main` branch before sharing
the description. Preview it in CurseForge before saving. See
[CurseForge's description editor guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips).

The release workflow publishes the ZIP and version-specific changelog in a GitHub Release. It does not update the
project description. Copy README changes into the description when the presentation changes.

## Release notes

Keep player-facing changes in [CHANGELOG.md](../CHANGELOG.md), under **Unreleased** until release.
Use **Added**, **Changed**, **Fixed**, **Translations**, and **Known limitations** only when relevant.
Describe the visible result and affected surface. For example, write
"Fixed translated item tooltips overlapping equipment comparisons" rather than an internal refactor name.
For translation updates, name the affected languages and content. Do not claim complete coverage
from a catalog count or an automated check. Include an upgrade instruction only when players need to act.

The first entry describes the initial release. Later entries contain only changes since the previous
release, plus limitations that affect that update. Keep technical maintenance details in commits.

GitHub **CI** runs on pull requests. On `main`, it runs automatically when a push changes the
version template (`tools/build/addon-manifest.toc`). It can also be run manually. CI builds the
production database, runs the addon harness and packaging tests, and provides an `addon-preview`
artifact containing a ZIP and Markdown notes. Preview ZIPs use **Unreleased** notes and are not published to CurseForge.
The ZIP includes the main addon, its declared data packs, artwork, and license notices.
Developer tracing files, local collectors, catalogs, and reference captures are excluded.

CI gates unit/integration regressions, database contracts and packaging. Release requires a
successful CI run triggered by a push to `main` or a manual run on `main` for the exact tagged commit,
then reuses that run's ZIP bytes.
It waits if CI is still running; it does not rebuild the database or rerun the tests.
The manual **Translation coverage** workflow runs the full strict matrices and retains reports
even on failure. Missing translations and unavailable source evidence fail that audit; they do
not require the product to claim complete coverage of every language before shipping.
The default local `tests/run-tests.py` still includes those matrices.

## Prepare and test before merging

The version has one maintained owner: `tools/build/addon-manifest.toc`.
The database builder propagates it to the main addon TOC; data-pack TOCs share the
generated catalog fingerprint. Do not edit generated identifiers individually. Data updates do not require a version bump
until they are included in a new player release.

For catalog releases, choose the version bump based on what players get:

- **Minor** when the release adds quests or translations, including translations for existing quests.
- **Patch** when the catalog changes are limited to metadata updates or corrections to existing translations.

1. On the release branch, set `## Version: MAJOR.MINOR.PATCH` in the manifest template.
2. Move the Unreleased notes into `## [VERSION] - YYYY-MM-DD`, leaving an empty
   `## [Unreleased]` section above it. The notes become both the GitHub release body and
   the CurseForge file changelog.
3. Build and check the exact candidate locally:

   ```sh
   uv run --no-project --with lupa==2.8 python tools/build/build-lua-database.py
   uv run --no-project --with lupa==2.8 python tests/run-tests.py --unit-only
   uv run --no-project --with lupa==2.8 python tests/python/test-lua-database.py
   python3 tests/python/test-release.py
   python3 tools/release/build-release.py --tag vVERSION
   ```

4. When ready for in-game testing, manually extract `dist/ForeverRosettaStone-VERSION.zip`
   into the local AddOns directory and test it before merging. Building and packaging never
   installs the addon. Branch CI also provides an `addon-preview` artifact for local testing.
5. Commit the template, changelog and generated shipping files. Merge the tested candidate
   into `main`. If review changes runtime code or data, rebuild and retest before merging.
6. Tag the version bump commit `vVERSION` and push that tag. The Release workflow requires the tagged
   commit to belong to `main` and have a successful main CI run. It downloads that run's
   `addon-preview` artifact, validates its version and archive inventory, renames the ZIP
   without changing its bytes, and publishes the GitHub Release with version-specific notes
   and `release-notes.md` attached. You can push the tag while main CI is running; Release waits.

The tag, main addon TOC, template version and changelog section must agree. For example,
`v1.0.0` requires version `1.0.0` and a `[1.0.0]` changelog section. All language packs stay
in the same ZIP. Preview artifacts use Unreleased notes; use `--tag vVERSION` locally to
inspect the final version-specific notes before tagging.

Failed, cancelled or missing main CI runs block publication. Rerun CI for the tagged commit
if needed, then retry Release. If there is no CI run yet, use **Run workflow** in **CI** while
`main` points to the tagged commit. Expired or missing artifacts require another CI run; Release
never silently substitutes an artifact from a different commit or rebuilds it itself.
For local promotion of an already downloaded, validated preview, use:

```sh
python3 tools/release/build-release.py --tag vVERSION \
  --from-preview /path/to/ForeverRosettaStone-VERSION-preview.zip
```

The workflow establishes CI provenance by repository, workflow, event, branch and exact commit.
The local command validates the ZIP and version; only pass a preview whose provenance you trust.

## Publish to CurseForge

Create a CurseForge author upload token using the [CurseForge Upload API guide](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api).
In the GitHub repository, go to **Settings → Secrets and variables → Actions → New repository secret**.
Name the secret `CF_API_TOKEN` and paste the CurseForge token as its value.

After GitHub publication, the `publish-curseforge` job downloads the same validated ZIP and
notes from the current run. It submits them to project `1807672` as a WoW Forever `1.60.1`
release and reports the CurseForge file ID. CurseForge processes and approves the file separately.

If upload fails, check the CurseForge project files first in case CurseForge received the ZIP
before GitHub lost the response. If the ZIP is absent, rerun the failed job in the original run.
For a manual upload, use the versioned ZIP and `release-notes.md` attached to the GitHub Release.

The Release workflow can also be run manually against an existing version tag, for example
if a build failed before publication. It uses that tag's workflow and code. An existing
GitHub Release is not overwritten: inspect its assets before retrying a completed publication.

## Clean local build outputs

After validation, remove ignored build outputs, reports and source downloads:

```sh
python3 tools/clean.py
```

This preserves tracked shipping files, local `.env` credentials and editor configuration.
It removes `dist/`, gallery exports, `datasources/imports/`, Python bytecode and local tool
caches. Source downloads and prepared update results are disposable, including nested upstream
Git checkouts. After this deliberate fresh-checkout cleanup, the next refresh starts without
`--previous`; see [cache lifecycle](import-resync.md#cache-lifecycle).
