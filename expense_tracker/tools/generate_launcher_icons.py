#!/usr/bin/env python3
"""Generate the legacy (API < 26) launcher PNGs.

The adaptive icon in mipmap-anydpi-v26 covers Android 8+, but older devices
read the raster mipmaps directly, so both must show the same mark. This script
draws the wallet mark defined in res/drawable/ic_launcher_foreground.xml.

Usage:  python tools/generate_launcher_icons.py
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw

RES = pathlib.Path(__file__).resolve().parents[1] / "android" / "app" / "src" / "main" / "res"

# Must match res/values/colors.xml
BACKGROUND = (0x4F, 0x46, 0xE5, 255)
FOREGROUND = (0xFF, 0xFF, 0xFF, 0xFF)

# density -> icon edge length in px
SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

SUPERSAMPLE = 4
VIEWPORT = 108.0


def wallet_layer(size: int) -> Image.Image:
    """The wallet mark, transparent where it is not drawn."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    s = size / VIEWPORT

    def box(x0, y0, x1, y1):
        return [x0 * s, y0 * s, x1 * s, y1 * s]

    # Wallet body (the "hole" for the pocket is punched afterwards).
    draw.rounded_rectangle(box(28, 36, 80, 72), radius=10 * s, fill=FOREGROUND)
    # Pocket hole.
    draw.rounded_rectangle(box(54, 48, 76, 60), radius=6 * s, fill=(0, 0, 0, 0))
    # Snap button floating in the pocket.
    cx, cy, r = 65 * s, 54 * s, 3.5 * s
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=FOREGROUND)
    return layer


def build(size: int, round_icon: bool) -> Image.Image:
    big = size * SUPERSAMPLE

    background = Image.new("RGBA", (big, big), BACKGROUND)
    mask = Image.new("L", (big, big), 0)
    mask_draw = ImageDraw.Draw(mask)

    if round_icon:
        mask_draw.ellipse([0, 0, big - 1, big - 1], fill=255)
    else:
        # Squircle-ish legacy background; the launcher applies its own mask on
        # top for adaptive-capable devices, so this is only ever shown whole on
        # pre-Android-8 devices.
        mask_draw.rounded_rectangle(
            [0, 0, big - 1, big - 1], radius=int(big * 0.18), fill=255
        )

    icon = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    icon.paste(background, (0, 0), mask)
    icon.alpha_composite(wallet_layer(big))

    return icon.resize((size, size), Image.LANCZOS)


def main() -> None:
    for folder, size in SIZES.items():
        target = RES / folder
        target.mkdir(parents=True, exist_ok=True)
        build(size, round_icon=False).save(target / "ic_launcher.png")
        build(size, round_icon=True).save(target / "ic_launcher_round.png")
        print(f"wrote {target}/ic_launcher.png + ic_launcher_round.png ({size}px)")


if __name__ == "__main__":
    main()
