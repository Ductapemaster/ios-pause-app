#!/usr/bin/env python3
"""Render Pause's app icon.

The icon is generated rather than drawn by hand so it stays tied to the app's
own visual constants: the indigo of `Color.pauseTint` and the concentric ring
proportions of `PulsingCircles`. Change a number here, re-run, and the asset
catalog is updated in place.

    python3 Tools/make_app_icon.py

Requires Pillow. Everything is drawn at SUPERSAMPLE x the final size and
downsampled, which is where the edge quality comes from — Pillow's shape
drawing is not itself antialiased.
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

SIZE = 1024
SUPERSAMPLE = 4

OUTPUT = (
    pathlib.Path(__file__).resolve().parent.parent
    / "Sources/Pause/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)

# `Color.pauseTint` is (0.36, 0.36, 0.84) — rgb(92, 92, 214). The field runs a
# little brighter than the tint at the top and deeper at the bottom so the icon
# has some depth under the system's own treatment; the tint itself sits about
# two thirds of the way down.
GRADIENT_TOP = (112, 112, 234)
GRADIENT_BOTTOM = (58, 58, 156)

# Ring radii as fractions of the icon's width, holding the 273:210:147 ratio of
# `PulsingCircles`. The outer ring crosses the icon's edges, which is what makes
# the rings read as a ripple continuing past the frame rather than as a target.
RING_OUTER = 0.547
RING_RATIOS = (1.0, 210 / 273, 147 / 273)
RING_ALPHAS = (0.07, 0.10, 0.16)

# The pause symbol. Bars are stadiums (corner radius = half their width) to
# match the rounded design of the countdown numeral. Their 538pt diagonal fits
# inside the innermost ring's 604pt diameter, the same containment rule
# `PulsingCircles` applies to the countdown it holds.
BAR_WIDTH = 0.115
BAR_HEIGHT = 0.420
BAR_GAP = 0.085
BAR_COLOR = (255, 255, 255)


def draw_gradient(size: int) -> Image.Image:
    """A vertical linear gradient, built one row at a time."""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        t = y / (size - 1)
        row = tuple(
            round(top + (bottom - top) * t)
            for top, bottom in zip(GRADIENT_TOP, GRADIENT_BOTTOM)
        )
        draw.line([(0, y), (size, y)], fill=row + (255,))
    return image


def draw_rings(image: Image.Image, size: int) -> None:
    """Overlay the concentric rings, largest first.

    Each is a translucent white disc rather than a stroke, so the overlaps
    accumulate toward the centre exactly as the stacked circles do on the pause
    screen.
    """
    centre = size / 2
    for ratio, alpha in zip(RING_RATIOS, RING_ALPHAS):
        radius = RING_OUTER * size * ratio
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse(
            [centre - radius, centre - radius, centre + radius, centre + radius],
            fill=BAR_COLOR + (round(alpha * 255),),
        )
        image.alpha_composite(layer)


def draw_bars(image: Image.Image, size: int) -> None:
    """The two pause bars, centred as a pair."""
    draw = ImageDraw.Draw(image)
    width = BAR_WIDTH * size
    height = BAR_HEIGHT * size
    gap = BAR_GAP * size
    centre = size / 2

    top = centre - height / 2
    left_bar_left = centre - gap / 2 - width
    for left in (left_bar_left, centre + gap / 2):
        draw.rounded_rectangle(
            [left, top, left + width, top + height],
            radius=width / 2,
            fill=BAR_COLOR,
        )


def render() -> Image.Image:
    size = SIZE * SUPERSAMPLE
    image = draw_gradient(size)
    draw_rings(image, size)
    draw_bars(image, size)
    return image.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    icon = render()
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # No alpha channel: an app icon with one is rejected at submission and can
    # render with a black fringe on device.
    icon.convert("RGB").save(OUTPUT, "PNG")
    print(f"Wrote {OUTPUT.relative_to(pathlib.Path.cwd())} ({icon.width}x{icon.height})")


if __name__ == "__main__":
    main()
