#!/usr/bin/env python3
"""Generate Clipurr AppIcon, MenuBarIcon, and docs logo from a square source."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

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

MAC_ICON_CORNER_FRACTION = 0.2237
CONTINUOUS_CORNER_FACTOR = 0.611335116483066
MENU_BAR_FILL = 0.98
MENU_BAR_LUMINANCE_THRESHOLD = 90
MENU_BAR_LUMINANCE_SOFT = 70
MENU_BAR_FLAT_LUMINANCE_THRESHOLD = 248


def _sample_background_color(image: Image.Image) -> tuple[int, int, int]:
    pixels = image.convert("RGBA").load()
    width, height = image.size
    corners = (
        pixels[0, 0],
        pixels[width - 1, 0],
        pixels[0, height - 1],
        pixels[width - 1, height - 1],
    )
    red = sum(color[0] for color in corners) // 4
    green = sum(color[1] for color in corners) // 4
    blue = sum(color[2] for color in corners) // 4
    return red, green, blue


def _bezier_points(
    start: tuple[float, float],
    control_1: tuple[float, float],
    control_2: tuple[float, float],
    end: tuple[float, float],
    segments: int = 32,
) -> list[tuple[float, float]]:
    points = [start]
    for index in range(1, segments + 1):
        t = index / segments
        inverse = 1 - t
        x = (
            inverse**3 * start[0]
            + 3 * inverse**2 * t * control_1[0]
            + 3 * inverse * t**2 * control_2[0]
            + t**3 * end[0]
        )
        y = (
            inverse**3 * start[1]
            + 3 * inverse**2 * t * control_1[1]
            + 3 * inverse * t**2 * control_2[1]
            + t**3 * end[1]
        )
        points.append((x, y))
    return points


def continuous_corner_mask(size: int, scale: int = 8) -> Image.Image:
    """macOS-style continuous corner mask (not circular-arc rounded rect)."""
    supersampled = size * scale
    radius = supersampled * MAC_ICON_CORNER_FRACTION
    control = radius * CONTINUOUS_CORNER_FACTOR
    width = height = supersampled

    points: list[tuple[float, float]] = []
    points.append((radius, 0))
    points.append((width - radius, 0))
    points.extend(
        _bezier_points(
            (width - radius, 0),
            (width - radius + control, 0),
            (width, radius - control),
            (width, radius),
        )[1:]
    )
    points.append((width, height - radius))
    points.extend(
        _bezier_points(
            (width, height - radius),
            (width, height - radius + control),
            (width - radius + control, height),
            (width - radius, height),
        )[1:]
    )
    points.append((radius, height))
    points.extend(
        _bezier_points(
            (radius, height),
            (radius - control, height),
            (0, height - radius + control),
            (0, height - radius),
        )[1:]
    )
    points.append((0, radius))
    points.extend(
        _bezier_points(
            (0, radius),
            (0, radius - control),
            (radius - control, 0),
            (radius, 0),
        )[1:]
    )

    mask = Image.new("L", (supersampled, supersampled), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.resize((size, size), Image.Resampling.LANCZOS)


def build_native_app_icon(source: Image.Image, size: int = 1024) -> Image.Image:
    return source.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)


def build_docs_logo(source: Image.Image, size: int = 1024) -> Image.Image:
    artwork = build_native_app_icon(source, size=size).convert("RGBA")
    mask = continuous_corner_mask(size)
    output = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    output.paste(artwork, mask=mask)
    return output


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


def _luminance(red: int, green: int, blue: int) -> float:
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def _finalize_menu_bar_mask(
    mask: Image.Image, *, close_gaps: bool = True
) -> Image.Image:
    if close_gaps:
        mask = mask.filter(ImageFilter.MaxFilter(3))
        mask = mask.filter(ImageFilter.MinFilter(3))
    bounds = mask.getbbox()
    if bounds is None:
        raise RuntimeError("No menu bar artwork found in source image.")
    return mask.crop(bounds)


def extract_menu_bar_silhouette_from_photo(source: Image.Image) -> Image.Image:
    rgba = source.convert("RGBA")
    background = _sample_background_color(rgba)
    pixels = rgba.load()
    width, height = rgba.size
    mask = Image.new("L", (width, height), 0)
    mask_pixels = mask.load()

    for y in range(height):
        for x in range(width):
            red, green, blue, _alpha = pixels[x, y]
            distance = (
                (red - background[0]) ** 2
                + (green - background[1]) ** 2
                + (blue - background[2]) ** 2
            ) ** 0.5
            luminance = _luminance(red, green, blue)
            # Keep solid cat + glass document; drop soft shadow glow.
            if luminance >= MENU_BAR_LUMINANCE_THRESHOLD or (
                luminance >= MENU_BAR_LUMINANCE_SOFT and distance >= 40
            ):
                mask_pixels[x, y] = 255
            elif luminance >= MENU_BAR_LUMINANCE_SOFT:
                blend = (luminance - MENU_BAR_LUMINANCE_SOFT) / (
                    MENU_BAR_LUMINANCE_THRESHOLD - MENU_BAR_LUMINANCE_SOFT
                )
                mask_pixels[x, y] = int(max(0.0, min(1.0, blend)) * 255)

    return _finalize_menu_bar_mask(mask)


def extract_menu_bar_silhouette_from_flat_asset(source: Image.Image) -> Image.Image:
    """Keep only light pixels as the template.

    Black regions (document fill, eyes, mouth, background) stay transparent so
    the menu-bar icon is an outline + face cutouts, not a solid blob.
    """
    rgba = source.convert("RGBA")
    alpha = rgba.getchannel("A")
    transparent_pixels = sum(1 for value in alpha.getdata() if value < 240)
    if transparent_pixels > rgba.width * rgba.height * 0.01:
        # Already a white-on-transparent template: trust alpha as-is so document
        # holes and face cutouts survive (do not flatten/threshold them shut).
        return _finalize_menu_bar_mask(alpha, close_gaps=False)

    pixels = rgba.load()
    width, height = rgba.size
    # Soft white extraction from black-background flat art.
    hard = max(180, MENU_BAR_FLAT_LUMINANCE_THRESHOLD - 60)
    soft = hard - 40
    mask = Image.new("L", (width, height), 0)
    mask_pixels = mask.load()

    for y in range(height):
        for x in range(width):
            red, green, blue, _alpha = pixels[x, y]
            luminance = _luminance(red, green, blue)
            if luminance >= hard:
                mask_pixels[x, y] = 255
            elif luminance >= soft:
                mask_pixels[x, y] = int((luminance - soft) / (hard - soft) * 255)

    return _finalize_menu_bar_mask(mask)


def generate_menu_icon(source: Path, destination: Path, *, flat_asset: bool) -> None:
    image = Image.open(source)
    if flat_asset:
        silhouette = extract_menu_bar_silhouette_from_flat_asset(image)
    else:
        silhouette = extract_menu_bar_silhouette_from_photo(image)
    destination.mkdir(parents=True, exist_ok=True)

    for filename, canvas_size in (
        ("menubar-template.png", 18),
        ("menubar-template@2x.png", 36),
    ):
        content_size = int(canvas_size * MENU_BAR_FILL)
        icon = silhouette.copy()
        icon.thumbnail((content_size, content_size), Image.Resampling.LANCZOS)
        # Keep thin document strokes and face holes crisp at menu-bar sizes.
        icon = icon.filter(ImageFilter.UnsharpMask(radius=0.6, percent=160, threshold=1))
        icon = icon.point(lambda value: 0 if value < 90 else (255 if value > 160 else value))

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
    parser.add_argument("--menu-bar-source", type=Path)
    parser.add_argument("--asset-catalog", type=Path, required=True)
    parser.add_argument("--docs-out", type=Path)
    arguments = parser.parse_args()

    source_image = Image.open(arguments.source)
    menu_bar_source = arguments.menu_bar_source or arguments.source

    generate_app_icons(arguments.source, arguments.asset_catalog / "AppIcon.appiconset")
    generate_menu_icon(
        menu_bar_source,
        arguments.asset_catalog / "MenuBarIcon.imageset",
        flat_asset=arguments.menu_bar_source is not None,
    )

    if arguments.docs_out:
        docs_logo = build_docs_logo(source_image)
        arguments.docs_out.parent.mkdir(parents=True, exist_ok=True)
        docs_logo.save(arguments.docs_out, optimize=True)


if __name__ == "__main__":
    main()
