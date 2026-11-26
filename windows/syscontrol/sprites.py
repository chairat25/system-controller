"""Mascot frames from the strips exported by the Mac app: walk 0-7, rest, held, fall. Recoloured and sized once
per look and cached."""
from __future__ import annotations

import sys
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageOps

FRAME_PIXELS = 128
WALK_FRAMES = 8
REST, HELD, FALL = 8, 9, 10
#: Windows draws a window's key colour as see-through; anything else on the mascot is solid.
KEY = (255, 0, 255)
#: Half-transparent edge pixels are laid on this instead of blending with the desktop, like a thin outline.
EDGE = (45, 40, 50)
MONOCHROME = {"panda"}


def sprite_folder() -> Path:
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).parent))
    return base / "sprites" if (base / "sprites").exists() else base / "syscontrol" / "sprites"


@lru_cache(maxsize=16)
def _strip(animal: str) -> Image.Image:
    path = sprite_folder() / f"{animal}.png"
    if not path.exists():
        path = sprite_folder() / "cat.png"
    return Image.open(path).convert("RGBA")


def _recolour(image: Image.Image, animal: str, hue: float) -> Image.Image:
    if not hue:
        return image
    alpha = image.getchannel("A")
    if animal in MONOCHROME:
        rgb = _multiply(image.convert("RGB"), _tint(hue))
    else:
        h, s, v = image.convert("RGB").convert("HSV").split()
        shift = int(round(hue / 360 * 255))
        h = h.point(lambda value: (value + shift) % 256)
        rgb = Image.merge("HSV", (h, s, v)).convert("RGB")
    rgb.putalpha(alpha)
    return rgb


def _tint(hue: float) -> tuple[float, float, float]:
    import colorsys
    red, green, blue = colorsys.hsv_to_rgb(hue / 360, 0.45, 1)
    return red * 255, green * 255, blue * 255


def _multiply(image: Image.Image, colour: tuple[float, float, float]) -> Image.Image:
    bands = [band.point(lambda value, scale=c / 255: int(value * scale)) for band, c in zip(image.split(), colour)]
    return Image.merge("RGB", bands)


@lru_cache(maxsize=64)
def frames(animal: str, hue: float, side: int, faces_right: bool, keyed: bool) -> tuple[Image.Image, ...]:
    """All frames of one look at `side` pixels. `keyed` lays them on the key colour (Windows); otherwise they
    keep their alpha."""
    strip = _recolour(_strip(animal), animal, hue)
    result = []
    for index in range(strip.width // FRAME_PIXELS):
        frame = strip.crop((index * FRAME_PIXELS, 0, (index + 1) * FRAME_PIXELS, FRAME_PIXELS))
        frame = frame.resize((side, side), Image.LANCZOS)
        if not faces_right:
            frame = ImageOps.mirror(frame)
        result.append(_keyed(frame) if keyed else frame)
    return tuple(result)


def _keyed(frame: Image.Image) -> Image.Image:
    alpha = frame.getchannel("A")
    solid = Image.new("RGB", frame.size, EDGE)
    solid.paste(frame.convert("RGB"), mask=alpha)
    keyed = Image.new("RGB", frame.size, KEY)
    keyed.paste(solid, mask=alpha.point(lambda value: 255 if value >= 128 else 0))
    return keyed
