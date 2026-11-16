# CurseForge gallery

`slides.html` contains the eight slide layouts and their text. `img/` contains the
source game screenshots and project logo. Keep both in version control.
Game screenshots retain the game content's original ownership and terms.

Open `slides.html?s=1` through `slides.html?s=8` in a browser to preview each slide.

## Generate images

Use Python 3, macOS's built-in `sips`, and a locally installed Chromium or Chrome executable.
From the repository root:

```sh
python3 docs/media/curseforge/render.py --browser "/path/to/chromium"
```

For example, with Google Chrome on macOS:

```sh
python3 docs/media/curseforge/render.py --browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

The renderer keeps `out/01.png` through `out/08.png` as **3840 × 2160** masters,
and exports `out/01.jpg` through `out/08.jpg` for upload. JPEG quality is adjusted
automatically so each file is below **1,900,000 bytes**, leaving headroom under
CurseForge's 2 MB limit without reducing resolution.

To re-export existing PNGs without running the browser:

```sh
python3 docs/media/curseforge/render.py --compress-only
```

`out/` is ignored by Git; regenerate the images after editing the source.
The export improves layout and text resolution, but screenshot detail remains limited
by the source images. Native fonts may render differently on other operating systems.

Upload the generated **JPGs** to CurseForge. These gallery sources and exports are separate
from the shipping addon folders.

## README images

The root README embeds three versioned JPEG exports under `../readme/`, using absolute
raw GitHub URLs so the same Markdown works on GitHub and CurseForge. After regenerating
the gallery, refresh those copies from the repository root:

```sh
cp docs/media/curseforge/out/01.jpg docs/media/readme/overview.jpg
cp docs/media/curseforge/out/02.jpg docs/media/readme/quest-companion.jpg
cp docs/media/curseforge/out/04.jpg docs/media/readme/item-comparisons.jpg
```

Keep the README image copies in version control; `out/` remains ignored.
