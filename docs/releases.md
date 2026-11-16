# Changelog and releases

[Back to the project](../README.md)

## Project description

Use the root [README](../README.md) as the CurseForge project description, choosing the
**Markdown** editor. Its links use full GitHub URLs so they also resolve outside the repository.
Publish the README and linked guides on the repository's public `main` branch before sharing
the description. Preview it in CurseForge before saving. See
[CurseForge's description editor guide](https://support.curseforge.com/support/solutions/articles/9000199552-project-submission-guide-and-tips).

The release workflow uploads ZIPs and version-specific changelogs. It does not update the
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

GitHub **CI** runs on branch pushes and pull requests. It builds the production database, runs the
addon harness and packaging tests, and provides an `addon-preview` artifact containing a ZIP and
Markdown notes. Preview ZIPs use **Unreleased** notes and are not published to CurseForge.
The ZIP includes the main addon, its declared data packs, artwork, and license notices.
Developer tracing files, local collectors, catalogs, and reference captures are excluded.

To prepare a release:

1. Set the version in `tools/build/addon-manifest.toc`, using `MAJOR.MINOR.PATCH`.
2. Move the Unreleased notes into `## [VERSION] - YYYY-MM-DD`, leaving an empty
   `## [Unreleased]` section above it. Review the notes as the text players will see on CurseForge.
3. Build the database and run validation using [the database guide](database.md#build-the-bundled-database). Also run
   `python3 tests/python/test-release.py` and `python3 tools/release/build-release.py --tag vVERSION`.
4. Commit the release files, create the matching `vVERSION` tag, and push it to GitHub.
   The **Release** workflow repeats the build and checks before preparing the ZIP and notes.

The tag, TOC version, and changelog section must agree. For example, `v1.0.0` requires TOC version
`1.0.0` and a `[1.0.0]` changelog section. Only that version's notes are included in the release artifact
and CurseForge upload. All data packs remain in the same release bundle.

### Enable CurseForge uploads after the initial submission

Submit the first addon release manually using the prepared ZIP and `release-notes.md` from the
release artifact. Keep automated uploads disabled until CurseForge accepts the project.

Then configure these under GitHub **Settings > Secrets and variables > Actions**:

| Kind | Name | Value |
| --- | --- | --- |
| Secret | `CURSEFORGE_API_TOKEN` | Author upload token from [CurseForge API Tokens](https://authors.curseforge.com/account/api-tokens) |
| Variable | `CURSEFORGE_PROJECT_ID` | Your approved project's numeric ID |
| Variable | `CURSEFORGE_GAME_VERSION_IDS` | Comma-separated CurseForge version IDs for the supported WoW Forever client |
| Variable | `CURSEFORGE_ENABLED` | `true`, only after the other values are configured |

CurseForge game-version IDs are not the TOC Interface number. Retrieve them from the authenticated
WoW `/api/game/versions` endpoint described in the
[Upload API documentation](https://support.curseforge.com/support/solutions/articles/9000197321).
Choose the supported Forever version explicitly, and update the IDs when client support changes.

Once enabled, pushing a version tag uploads the tested ZIP and that release's Markdown notes
to CurseForge as a **release**. CurseForge's own processing and approval still apply.
Before enabling it, tags produce downloadable artifacts only.
Setting `CURSEFORGE_ENABLED` to `false` disables uploads without disabling builds.

The Release workflow can also be run manually against an existing version tag. Its upload checkbox
defaults to off and still requires `CURSEFORGE_ENABLED=true`. Do not upload the initial version again
after submitting it manually. Before repeating an upload after an interrupted run, check CurseForge
for an existing file: the upload step does not deduplicate releases or retry requests.
These workflows produce Actions artifacts; they do not create GitHub Releases.
