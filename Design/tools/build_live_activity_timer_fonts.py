#!/usr/bin/env python3
"""Build the color bitmap font used by the compact Dynamic Island pet.

WidgetKit keeps `Text(date, style: .timer)` ticking after the extension has
been suspended. Each font face replaces the timer's final digit with a color
PNG sprite:

    x0...x6  movement frame A/B
    x7...x9  sleeping frame

The faces are packaged in one TTC. This is a public timer-font technique; it
does not call Apple's private clock-hand APIs.

Requires fontTools and Pillow.
"""

from __future__ import annotations

import argparse
import io
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection, newTable
from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
from fontTools.ttLib.tables.sbixStrike import Strike as SbixStrike


# Dynamic Island iPhones render at @3x. At a 32 pt glyph size, a 48-column
# source grid maps each artwork pixel to exactly two physical screen pixels.
# Keeping the em divisible by 48 also prevents CoreText from rounding alternate
# columns to different widths. This preserves the original dog instead of
# reducing its face and paws to the former ~27x25 visible-pixel silhouette.
UNITS_PER_EM = 1_536
CANVAS_SIZE = (64, 52)
PIXEL_CANVAS_SIZE = (48, 39)
DIGIT_GLYPHS = [f"d{value}" for value in range(10)]
MASK_SPECS = {
    "PetIslandTimerRunA": {0, 2, 4, 6},
    "PetIslandTimerRunB": {1, 3, 5},
    "PetIslandTimerSleep": {7, 8, 9},
}


@dataclass(frozen=True)
class PetFontSpec:
    postscript_name: str
    moving_a: str
    moving_b: str
    sleeping: str


SPECS = [
    PetFontSpec("PetIslandTimerDogShepherd", "sprite_dog_run_0.png", "sprite_dog_run_1.png", "sprite_dog_lie_0.png"),
    PetFontSpec("PetIslandTimerDogCorgi", "island_dog_corgi_walk_0.png", "island_dog_corgi_walk_1.png", "island_dog_corgi_sleep.png"),
    PetFontSpec("PetIslandTimerDogDoberman", "island_dog_doberman_walk_0.png", "island_dog_doberman_walk_1.png", "island_dog_doberman_sleep.png"),
    PetFontSpec("PetIslandTimerDogBullTerrier", "island_dog_bull_terrier_walk_0.png", "island_dog_bull_terrier_walk_1.png", "island_dog_bull_terrier_sleep.png"),
    PetFontSpec("PetIslandTimerCatClassic", "island_cat_walk_0.png", "island_cat_walk_1.png", "island_cat_sleep.png"),
    PetFontSpec("PetIslandTimerCatBritish", "island_cat_british_walk_0.png", "island_cat_british_walk_1.png", "island_cat_british_sleep.png"),
    PetFontSpec("PetIslandTimerCatMaineCoon", "island_cat_maine_coon_walk_0.png", "island_cat_maine_coon_walk_1.png", "island_cat_maine_coon_sleep.png"),
    PetFontSpec("PetIslandTimerCatSiamese", "island_cat_siamese_walk_0.png", "island_cat_siamese_walk_1.png", "island_cat_siamese_sleep.png"),
    PetFontSpec("PetIslandTimerFoxRed", "island_fox_walk_0.png", "island_fox_walk_1.png", "island_fox_sleep.png"),
    PetFontSpec("PetIslandTimerFoxArctic", "island_fox_arctic_walk_0.png", "island_fox_arctic_walk_1.png", "island_fox_arctic_sleep.png"),
    PetFontSpec("PetIslandTimerParrotClassic", "island_parrot_walk_1.png", "island_parrot_jump.png", "island_parrot_sleep.png"),
    PetFontSpec("PetIslandTimerParrotCockatiel", "island_parrot_cockatiel_walk_1.png", "island_parrot_cockatiel_jump.png", "island_parrot_cockatiel_sleep.png"),
    PetFontSpec("PetIslandTimerParrotBudgie", "island_parrot_budgie_walk_1.png", "island_parrot_budgie_jump.png", "island_parrot_budgie_sleep.png"),
    PetFontSpec("PetIslandTimerParrotMacaw", "island_parrot_macaw_fly_00.png", "island_parrot_macaw_fly_04.png", "island_parrot_macaw_sleep.png"),
    PetFontSpec("PetIslandTimerPenguinClassic", "island_penguin_walk_0.png", "island_penguin_walk_1.png", "island_penguin_sleep.png"),
    PetFontSpec("PetIslandTimerPenguinRockhopper", "island_penguin_rockhopper_walk_0.png", "island_penguin_rockhopper_walk_1.png", "island_penguin_rockhopper_sleep.png"),
    PetFontSpec("PetIslandTimerBear", "sprite_bear_run_0.png", "sprite_bear_run_1.png", "sprite_bear_lie_0.png"),
    PetFontSpec("PetIslandTimerLizard", "sprite_lizard_run_0.png", "sprite_lizard_run_1.png", "sprite_lizard_idle_0.png"),
    PetFontSpec("PetIslandTimerBunny", "sprite_bunny_idle_0.png", "sprite_bunny_idle_0.png", "sprite_bunny_idle_0.png"),
]


def empty_glyph():
    return TTGlyphPen(None).glyph()


def rectangle_glyph(x0: int, y0: int, x1: int, y1: int):
    pen = TTGlyphPen(None)
    pen.moveTo((x0, y0))
    pen.lineTo((x0, y1))
    pen.lineTo((x1, y1))
    pen.lineTo((x1, y0))
    pen.closePath()
    return pen.glyph()


def build_mask_face(postscript_name: str, active_digits: set[int]):
    """Build a timer mask without truly empty glyphs.

    WidgetKit can redact an empty advancing glyph as a gray placeholder in a
    Live Activity. Inactive digits therefore keep a real outline two ems to
    the right of their advance box. It satisfies the text renderer but remains
    outside the small clipped mask proposed by the compact island.
    """
    glyph_order = [".notdef", *DIGIT_GLYPHS, "colon"]
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap(
        {
            **{ord(str(value)): f"d{value}" for value in range(10)},
            ord(":"): "colon",
        }
    )
    inactive = rectangle_glyph(2_000, 0, 3_000, UNITS_PER_EM)
    active = rectangle_glyph(0, 0, UNITS_PER_EM, UNITS_PER_EM)
    glyphs = {".notdef": inactive, "colon": inactive}
    glyphs.update(
        {
            glyph_name: active if digit in active_digits else inactive
            for digit, glyph_name in enumerate(DIGIT_GLYPHS)
        }
    )
    builder.setupGlyf(glyphs)
    metrics = {".notdef": (UNITS_PER_EM, 2_000), "colon": (UNITS_PER_EM, 2_000)}
    metrics.update(
        {
            glyph_name: (UNITS_PER_EM, 0 if digit in active_digits else 2_000)
            for digit, glyph_name in enumerate(DIGIT_GLYPHS)
        }
    )
    builder.setupHorizontalMetrics(metrics)
    builder.setupHorizontalHeader(ascent=UNITS_PER_EM, descent=0)
    builder.setupOS2(
        sTypoAscender=UNITS_PER_EM,
        sTypoDescender=0,
        usWinAscent=UNITS_PER_EM,
        usWinDescent=0,
        sxHeight=UNITS_PER_EM,
        sCapHeight=UNITS_PER_EM,
    )
    family_name = postscript_name.replace("PetIslandTimer", "Pet Island Timer ")
    builder.setupNameTable(
        {
            "familyName": family_name,
            "styleName": "Regular",
            "uniqueFontIdentifier": f"PetIsland:{postscript_name}:2.0",
            "fullName": family_name,
            "psName": postscript_name,
            "version": "Version 2.0",
        }
    )
    builder.setupPost()
    builder.setupMaxp()
    return builder.font


def locate_asset(root: Path, filename: str) -> Path:
    matches = list(root.rglob(filename))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {filename}, found {len(matches)}")
    return matches[0]


@lru_cache(maxsize=None)
def normalized_png(path_string: str) -> bytes:
    source = Image.open(path_string).convert("RGBA")
    alpha_box = source.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError(f"Sprite has no visible pixels: {path_string}")
    source = source.crop(alpha_box)

    max_width, max_height = CANVAS_SIZE[0] - 4, CANVAS_SIZE[1] - 2
    scale = min(max_width / source.width, max_height / source.height)
    size = (
        max(1, round(source.width * scale)),
        max(1, round(source.height * scale)),
    )
    source = source.resize(size, Image.Resampling.NEAREST)
    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(
        source,
        ((CANVAS_SIZE[0] - size[0]) // 2, CANVAS_SIZE[1] - size[1]),
    )
    output = io.BytesIO()
    canvas.save(output, format="PNG", optimize=True)
    return output.getvalue()


def pixel_image(assets_root: Path, filename: str) -> Image.Image:
    png = normalized_png(str(locate_asset(assets_root, filename)))
    resized = Image.open(io.BytesIO(png)).convert("RGBA").resize(
        PIXEL_CANVAS_SIZE,
        Image.Resampling.NEAREST,
    )
    # Preserve the source artwork's colors and proportions. Alpha alone is
    # snapped to the pixel grid so CoreText cannot create stray half-pixels at
    # the compact Dynamic Island size.
    quantized = resized.quantize(
        colors=64,
        method=Image.Quantize.FASTOCTREE,
        dither=Image.Dither.NONE,
    ).convert("RGBA")
    quantized.putalpha(
        quantized.getchannel("A").point(lambda alpha: 255 if alpha >= 96 else 0)
    )

    # Preserve every source pixel and add contrast only in previously
    # transparent neighbours. This is an external display outline, not a
    # repaint of the character artwork.
    alpha = quantized.getchannel("A")
    outline_alpha = ImageChops.subtract(
        alpha.filter(ImageFilter.MaxFilter(3)),
        alpha,
    )
    outlined = Image.new("RGBA", quantized.size, (46, 43, 52, 0))
    outlined.putalpha(outline_alpha)
    outlined.alpha_composite(quantized)
    return outlined


def silhouette_glyph(image: Image.Image):
    """Build a monochrome fallback for renderers that ignore sbix strikes.

    Dynamic `Text` is rendered by a WidgetKit host rather than the app process.
    Some host paths resolve the base TrueType outline without applying color
    paints. Keeping the base digit visible prevents an otherwise blank glyph;
    sbix-capable renderers replace it with the intact color bitmap.
    """
    pen = TTGlyphPen(None)
    width, height = image.size
    pixels = image.load()
    for y in range(height):
        x = 0
        while x < width:
            if pixels[x, y][3] == 0:
                x += 1
                continue
            run_start = x
            while x < width and pixels[x, y][3] > 0:
                x += 1
            x0 = round(run_start * UNITS_PER_EM / width)
            x1 = round(x * UNITS_PER_EM / width)
            y0 = round((height - y - 1) * UNITS_PER_EM / width)
            y1 = round((height - y) * UNITS_PER_EM / width)
            pen.moveTo((x0, y0))
            pen.lineTo((x0, y1))
            pen.lineTo((x1, y1))
            pen.lineTo((x1, y0))
            pen.closePath()
    return pen.glyph()


def sbix_png(image: Image.Image, ppem: int) -> bytes:
    """Encode one complete sprite strike without splitting it into contours."""
    target_size = (
        ppem,
        round(image.height * ppem / image.width),
    )
    bitmap = image.resize(target_size, Image.Resampling.NEAREST)
    output = io.BytesIO()
    bitmap.save(output, format="PNG", optimize=True)
    return output.getvalue()


def build_face(spec: PetFontSpec, assets_root: Path):
    frame_images = {
        "moveA": pixel_image(assets_root, spec.moving_a),
        "moveB": pixel_image(assets_root, spec.moving_b),
        "sleep": pixel_image(assets_root, spec.sleeping),
    }
    glyph_order = [".notdef", *DIGIT_GLYPHS, "colon"]
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    builder.setupCharacterMap(
        {
            **{ord(str(value)): f"d{value}" for value in range(10)},
            ord(":"): "colon",
        }
    )
    glyphs = {name: empty_glyph() for name in glyph_order}
    digit_frames = {
        glyph_name: "sleep" if digit >= 7 else ("moveA" if digit % 2 == 0 else "moveB")
        for digit, glyph_name in enumerate(DIGIT_GLYPHS)
    }
    glyphs.update(
        {
            glyph_name: silhouette_glyph(frame_images[frame_name])
            for glyph_name, frame_name in digit_frames.items()
        }
    )
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name: (UNITS_PER_EM, 0) for name in glyph_order})
    builder.setupHorizontalHeader(ascent=UNITS_PER_EM, descent=0)
    builder.setupOS2(
        sTypoAscender=UNITS_PER_EM,
        sTypoDescender=0,
        usWinAscent=UNITS_PER_EM,
        usWinDescent=0,
        sxHeight=UNITS_PER_EM,
        sCapHeight=UNITS_PER_EM,
    )
    family_name = spec.postscript_name.replace("PetIslandTimer", "Pet Island Timer ")
    builder.setupNameTable(
        {
            "familyName": family_name,
            "styleName": "Regular",
            "uniqueFontIdentifier": f"PetIsland:{spec.postscript_name}:2.0",
            "fullName": family_name,
            "psName": spec.postscript_name,
            "version": "Version 2.0",
        }
    )
    builder.setupPost()
    builder.setupMaxp()

    # COLRv0 required hundreds of tiny contours per sprite. CoreText dropped
    # some of those contours at compact Dynamic Island sizes, producing real
    # transparent holes in the dog. Apple's sbix format stores one intact PNG
    # for each digit, so the system receives the exact pixel grid instead.
    sbix = newTable("sbix")
    strike = SbixStrike(ppem=96, resolution=72)
    for glyph_name, frame_name in digit_frames.items():
        strike.glyphs[glyph_name] = SbixGlyph(
            glyphName=glyph_name,
            originOffsetX=0,
            originOffsetY=0,
            graphicType="png ",
            imageData=sbix_png(frame_images[frame_name], ppem=96),
        )
    sbix.strikes = {strike.ppem: strike}
    builder.font["sbix"] = sbix
    return builder.font


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--assets",
        type=Path,
        default=Path("SharedResources/PetSprites.xcassets"),
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("PetIslandLiveActivity/Resources/PetIslandTimerPets.ttc"),
    )
    args = parser.parse_args()

    collection = TTCollection()
    collection.fonts = []
    faces_directory = args.output.parent / "PetTimerFaces"
    faces_directory.mkdir(parents=True, exist_ok=True)
    for spec in SPECS:
        face = build_face(spec, args.assets)
        face.save(faces_directory / f"{spec.postscript_name}.ttf")
        collection.fonts.append(face)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    collection.save(args.output)
    for postscript_name, active_digits in MASK_SPECS.items():
        build_mask_face(postscript_name, active_digits).save(
            args.output.parent / f"{postscript_name}.ttf"
        )
    print(args.output)
    print(f"faces: {len(collection.fonts)}")


if __name__ == "__main__":
    main()
