#!/usr/bin/env python3
"""Render the CurseForge gallery into an unversioned output directory."""

import argparse
from pathlib import Path
import subprocess


def export_jpeg(source):
    """Keep the 4K resolution while leaving headroom below CurseForge's 2 MB limit."""
    target = source.with_suffix(".jpg")
    for quality in range(90, 39, -5):
        subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(quality),
             str(source), "--out", str(target)],
            check=True,
            capture_output=True,
        )
        if target.stat().st_size < 1_900_000:
            print(f"{target}: {target.stat().st_size:,} bytes (quality {quality})", flush=True)
            return
    target.unlink()
    raise RuntimeError(f"Could not export {source.name} below the upload size limit")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--browser", help="Path to a Chromium or Chrome executable")
    parser.add_argument("--compress-only", action="store_true", help="Export JPEGs from existing PNGs")
    args = parser.parse_args()
    if not args.compress_only and not args.browser:
        parser.error("--browser is required unless --compress-only is used")
    base = Path(__file__).resolve().parent
    output = base / "out"
    output.mkdir(exist_ok=True)
    for number in range(1, 9):
        target = output / f"{number:02}.png"
        if args.compress_only:
            export_jpeg(target)
            continue
        subprocess.run(
            [
                args.browser,
                "--headless",
                "--hide-scrollbars",
                "--window-size=1920,1080",
                "--force-device-scale-factor=2",
                "--run-all-compositor-stages-before-draw",
                "--virtual-time-budget=3000",
                f"--screenshot={target}",
                (base / "slides.html").as_uri() + f"?s={number}",
            ],
            check=True,
        )
        export_jpeg(target)


if __name__ == "__main__":
    main()
