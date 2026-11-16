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

GitHub **CI** runs on pushes to `main` and pull requests. It builds the production database, runs the
addon harness and packaging tests, and provides an `addon-preview` artifact containing a ZIP and
Markdown notes. Preview ZIPs use **Unreleased** notes and are not published to CurseForge.
The ZIP includes the main addon, its declared data packs, artwork, and license notices.
Developer tracing files, local collectors, catalogs, and reference captures are excluded.

CI and Release gate unit/integration regressions, database contracts and packaging.
The manual **Translation coverage** workflow runs the full strict matrices and retains reports
even on failure. Missing translations and unavailable source evidence fail that audit; they do
not require the product to claim complete coverage of every language before shipping.
The default local `tests/run-tests.py` still includes those matrices.

## Prepare and test before merging

The version has one maintained owner: `tools/build/addon-manifest.toc`.
The database builder propagates it to the main addon TOC; data-pack TOCs share the
generated catalog fingerprint. Do not edit generated identifiers individually. Data updates do not require a version bump
until they are included in a new player release.

1. On the release branch, set `## Version: MAJOR.MINOR.PATCH` in the manifest template.
2. Move the Unreleased notes into `## [VERSION] - YYYY-MM-DD`, leaving an empty
   `## [Unreleased]` section above it. The notes become both the GitHub release body and
   the changelog to paste into CurseForge.
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
6. Tag the merged commit `vVERSION` and push that tag. The Release workflow requires the tagged
   commit to belong to `main`, repeats the checks, and publishes the GitHub Release with the
   ZIP and `release-notes.md` attached.

The tag, main addon TOC, template version and changelog section must agree. For example,
`v1.0.0` requires version `1.0.0` and a `[1.0.0]` changelog section. All language packs stay
in the same ZIP. Preview artifacts use Unreleased notes; use `--tag vVERSION` locally to
inspect the final version-specific notes before tagging.

## Submit to CurseForge manually

Download `ForeverRosettaStone-VERSION.zip` from the GitHub Release and upload that ZIP to
CurseForge. Paste the release body or the attached `release-notes.md` into its Markdown
changelog editor. GitHub's automatic source archives are not installable addon bundles.

There is no CurseForge API integration or token configuration. Publishing a GitHub Release
does not submit a file to CurseForge; its processing and approval remain separate.

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
