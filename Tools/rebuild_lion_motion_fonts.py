#!/usr/bin/env python3
"""Repack adult-lion/lioness timer art from shipped assets; never redraw sprites.

Requires Pillow and fontTools, like the resource validators. Only these two
breeds are updated, including their three outfits. Other font faces are checked
byte-for-byte after saving. Generation drafts are not needed.
"""
from copy import deepcopy
from hashlib import sha256
from io import BytesIO
from pathlib import Path

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTCollection
from fontTools.ttLib.tables.sbixGlyph import Glyph

from validate_timer_fonts import asset_for_digit, registered_canvas, strike_bitmap, MODES
from validate_accessories import outfit_bitmap

ROOT = Path(__file__).resolve().parents[1]
BREEDS = ("LionAdult", "Lioness")


def digest(font):
    font.recalcTimestamp = False
    buffer = BytesIO()
    font.save(buffer)
    return sha256(buffer.getvalue()).hexdigest()


def silhouette(image, em):
    pen = TTGlyphPen(None)
    alpha = image.getchannel("A")
    for y in range(image.height):
        x = 0
        while x < image.width:
            if not alpha.getpixel((x, y)):
                x += 1
                continue
            start = x
            while x < image.width and alpha.getpixel((x, y)):
                x += 1
            left, right = round(start * em / image.width), round(x * em / image.width)
            bottom, top = round((image.height - y - 1) * em / image.width), round((image.height - y) * em / image.width)
            pen.moveTo((left, bottom))
            pen.lineTo((left, top))
            pen.lineTo((right, top))
            pen.lineTo((right, bottom))
            pen.closePath()
    return pen.glyph()


def bitmap_glyph(name, image, offset):
    data = BytesIO()
    image.save(data, "PNG", optimize=True)
    return Glyph(glyphName=name, originOffsetX=0, originOffsetY=offset,
                 graphicType="png ", imageData=data.getvalue())


def rebuild():
    bases = {}
    for filename, prefix in [("PetIslandTimerPets", "PetIslandTimer"), ("PetIslandLockTimerPets", "PetIslandLockTimer")]:
        path = ROOT / "PetIslandLiveActivity/Resources" / (filename + ".ttc")
        collection = TTCollection(path)
        selected = {prefix + breed + mode: (breed, mode) for breed in BREEDS for mode in MODES}
        protected = {f["name"].getDebugName(6): digest(f) for f in collection.fonts if f["name"].getDebugName(6) not in selected}
        for index, original in enumerate(collection.fonts):
            name = original["name"].getDebugName(6)
            if name not in selected:
                continue
            font = deepcopy(original)  # TTC tables can be shared with other faces.
            collection.fonts[index] = font
            font.recalcTimestamp = False
            breed, mode = selected[name]
            for digit in range(10):
                asset = asset_for_digit(breed, mode, digit)
                if "_sleep_" in asset:
                    continue
                glyph = f"d{digit}"
                em = font["head"].unitsPerEm
                font["glyf"][glyph] = silhouette(registered_canvas(asset), em)
                font["glyf"][glyph].recalcBounds(font["glyf"])
                for ppem, strike in font["sbix"].strikes.items():
                    offset = -round(font["glyf"][glyph].yMin * ppem / em)
                    strike.glyphs[glyph] = bitmap_glyph(glyph, strike_bitmap(asset, ppem, prefix == "PetIslandTimer"), offset)
            bases[name] = font
        collection.save(path, shareTables=True)
        actual = {f["name"].getDebugName(6): digest(f) for f in TTCollection(path).fonts if f["name"].getDebugName(6) not in selected}
        assert actual == protected, "Unrelated timer faces changed"
        print(f"{filename}: updated 12 lion faces; {len(protected)} other faces unchanged")

    for breed in BREEDS:
        for item in ("knitHat", "tinyCrown", "ribbonBow"):
            path = ROOT / "SharedResources/PetOutfitFonts" / f"{breed}-{item}.ttc"
            collection = TTCollection(path)
            for index, original in enumerate(collection.fonts):
                font = deepcopy(original)
                collection.fonts[index] = font
                font.recalcTimestamp = False
                name = font["name"].getDebugName(6)
                family = "PetAccessory" if name.startswith("PetAccessory") else "PetDressed"
                base_name = name.removesuffix(item).replace(family, "PetIsland", 1)
                base = bases[base_name]
                mode = next(m for m in MODES if base_name == ("PetIslandLockTimer" if "Lock" in name else "PetIslandTimer") + breed + m)
                for tag in ("glyf", "hmtx", "hhea"):
                    font[tag] = deepcopy(base[tag])
                for ppem, strike in font["sbix"].strikes.items():
                    for digit in range(10):
                        asset = asset_for_digit(breed, mode, digit)
                        glyph = f"d{digit}"
                        bitmap = outfit_bitmap(asset, ppem, "Lock" not in name, ink=family == "PetAccessory", item=item)
                        strike.glyphs[glyph] = bitmap_glyph(glyph, bitmap, base["sbix"].strikes[ppem].glyphs[glyph].originOffsetY)
                    seen = {}
                    for glyph in strike.glyphs.values():
                        if not glyph.imageData:
                            continue
                        identity = (glyph.originOffsetX, glyph.originOffsetY, glyph.imageData)
                        if identity in seen:
                            glyph.graphicType = "dupe"
                            glyph.referenceGlyphName = seen[identity]
                            glyph.imageData = None
                        else:
                            seen[identity] = glyph.glyphName
            collection.save(path, shareTables=True)
            print(f"{path.name}: updated 24 matching outfit faces")


if __name__ == "__main__":
    rebuild()
