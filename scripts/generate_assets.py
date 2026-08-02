#!/usr/bin/env python3
"""Generate Clipurr AppIcon + MenuBarIcon assets from a square logo source.

Keeps the source artwork faithful (soft top light, flat cat). Does not
recolor/wipe the background — that created the top-light artifact.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageFilter


APP_ICON_SIZES = {
    "appicon_16.png": 16,
    "appicon_16@2x.png": 32,
    "appicon_32.png": 32,
    "appicon_32@2x.png": 64,
    "appicon_128.png": 128,
    "appicon_128@2x.png": 256,
    "appicon_256.png": 256,
    "appicon_256@2x.png": 512,
    "appicon_512.png": 512,
    "appicon_512@2x.png": 1024,
}


def build_native_app_icon(source: Image.Image, size: int = 1024) -> Image.Image:
    return source.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)


def generate_app_icons(source: Path, destination: Path) -> None:
    master = build_native_app_icon(Image.open(source))
    destination.mkdir(parents=True, exist_ok=True)
    for filename, size in APP_ICON_SIZES.items():
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        if size <= 64:
            resized = resized.filter(
                ImageFilter.UnsharpMask(radius=0.5, percent=110, threshold=1)
            )
        resized.save(destination / filename, optimize=True)


def generate_menu_icon(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("L")
    body = image.point(lambda value: 255 if value >= 175 else 0)
    body = body.filter(ImageFilter.MedianFilter(3))
    bounds = body.getbbox()
    if bounds is None:
        raise RuntimeError("No menu bar artwork found in source image.")

    body = body.crop(bounds)
    destination.mkdir(parents=True, exist_ok=True)
    for filename, canvas_size in (
        ("menubar-template.png", 18),
        ("menubar-template@2x.png", 36),
    ):
        content_size = int(canvas_size * 0.90)
        icon = body.copy()
        icon.thumbnail((content_size, content_size), Image.Resampling.LANCZOS)
        canvas = Image.new("L", (canvas_size, canvas_size), 0)
        origin = (
            (canvas_size - icon.width) // 2,
            (canvas_size - icon.height) // 2,
        )
        canvas.paste(icon, origin)
        output = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        output.putalpha(canvas)
        output.save(destination / filename, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--asset-catalog", type=Path, required=True)
    parser.add_argument("--master-out", type=Path)
    arguments = parser.parse_args()

    if arguments.master_out:
        master = build_native_app_icon(Image.open(arguments.source))
        arguments.master_out.parent.mkdir(parents=True, exist_ok=True)
        master.save(arguments.master_out, optimize=True)

    generate_app_icons(
        arguments.source,
        arguments.asset_catalog / "AppIcon.appiconset",
    )
    generate_menu_icon(
        arguments.source,
        arguments.asset_catalog / "MenuBarIcon.imageset",
    )


if __name__ == "__main__":
    main()
