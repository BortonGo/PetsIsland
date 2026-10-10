#!/usr/bin/env python3
"""Read-only check of accessory patterns, timer coverage and bitmap registration."""
from pathlib import Path
from io import BytesIO
import json
import math
from functools import lru_cache
from PIL import Image, ImageChops, ImageFilter
from fontTools.ttLib import TTCollection

ROOT = Path(__file__).resolve().parents[1]

def glyph_image(strike, glyph_name):
    """Resolve lossless sbix duplicate references, rejecting cycles/missing data."""
    seen = set()
    while True:
        assert glyph_name not in seen, ('cyclic glyph reference', glyph_name)
        seen.add(glyph_name)
        glyph = strike.glyphs[glyph_name]
        if glyph.graphicType != 'dupe':
            assert glyph.imageData, glyph_name
            return Image.open(BytesIO(glyph.imageData)).convert('RGBA')
        referenced = strike.glyphs[glyph.referenceGlyphName]
        assert (glyph.originOffsetX, glyph.originOffsetY) == (referenced.originOffsetX, referenced.originOffsetY)
        glyph_name = glyph.referenceGlyphName
@lru_cache(maxsize=None)
def outfit_bitmap(asset, ppem, dynamic_island, ink=False, item="knitHat"):
    from validate_timer_fonts import registered_canvas
    original = Image.open(ROOT / 'SharedResources/PetSprites.xcassets' / f'{asset}.imageset' / f'{asset}.png').convert('RGBA')
    bounds = original.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    scale = (180 / 259 if dynamic_island else 148 / 273) if asset.startswith('sprite_dog_lie_') else 1
    anchor = 161.5 if asset.startswith('sprite_dog_lie_') else original.width / 2
    frame = Image.open(ROOT / 'SharedResources/PetOutfits' / item / (asset + ('-ink' if ink else '') + '.png')).convert('RGBA')
    registered = Image.new('RGBA', (220, 176))
    registered.alpha_composite(frame.resize((round(frame.width * scale), round(frame.height * scale)), Image.Resampling.NEAREST),
                              (round(110 - anchor * scale), 0 if asset.startswith('companion_') else round(160 - bounds[3] * scale)))
    result = registered.resize((ppem, round(ppem * 176 / 220)), Image.Resampling.NEAREST)
    if not asset.startswith('companion_'):
        base = registered_canvas(asset, dynamic_island).resize(result.size, Image.Resampling.NEAREST)
        bottom = base.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()[3]
        shifted = Image.new('RGBA', result.size)
        shifted.alpha_composite(result, (0, round(160 * ppem / 220) - bottom))
        result = shifted
    return result


def validate():
    from validate_timer_fonts import asset_for_digit, registered_canvas, PREFIXES, MODES
    catalog = json.loads((ROOT / 'SharedResources/PetAccessories.json').read_text())
    assert catalog['version'] == 3
    assert catalog['poses'].keys() == catalog['anchors'].keys()
    for item, fits in catalog['fits'].items():
        assert item in catalog['art'], item
        for asset, fit in fits.items():
            assert asset in catalog['anchors'] and len(fit) == 3, (item, asset)
            assert all(math.isfinite(value) for value in fit) and fit[2] > 0, (item, asset)
    for item, art in catalog['art'].items():
        width = len(art['rows'][0])
        assert width > 0 and all(len(row) == width for row in art['rows']), item
        assert all(char == ' ' or char in art['palette'] for row in art['rows'] for char in row), item
        assert all(len(color) == 6 and int(color, 16) >= 0 for color in art['palette'].values()), item

    assets = {path.stem: path for folder in [ROOT / 'SharedResources/PetSprites.xcassets',
                                            ROOT / 'PetIsland/Resources/NaturalGaits.xcassets']
              for path in folder.rglob('*.png')}
    for item in catalog['art']:
        outfits = ROOT / 'SharedResources/PetOutfits' / item
        manifest = json.loads((outfits / 'manifest.json').read_text())
        assert manifest.keys() == catalog['anchors'].keys(), 'Incomplete authored outfit coverage'
        for asset, entry in manifest.items():
            original = Image.open(assets[asset]).convert('RGBA')
            full = Image.open(outfits / (asset + '.png')).convert('RGBA')
            ink = Image.open(outfits / (asset + '-ink.png')).convert('RGBA')
            assert full.size == ink.size == original.size == tuple(entry['size']), asset
            assert full.getbbox() and ink.getbbox() == tuple(entry['inkBounds']), asset
            assert set(full.getchannel('A').tobytes()) == {0, 255}, (asset, 'fringe alpha')
            assert set(ink.getchannel('A').tobytes()) == {0, 255}, asset
            # Ink is only a colour-preservation mask from the same completed frame.
            # It cannot introduce a new hat shape or resurrect original ears.
            pixels, colors = full.tobytes(), ink.tobytes()
            for offset in range(3, len(colors), 4):
                if colors[offset]:
                    assert colors[offset-3:offset+1] == pixels[offset-3:offset+1], (asset, 'ink differs from authored sprite')
            before = original.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
            assert abs(before[3] - full.getbbox()[3]) <= 2, (asset, 'ground registration')
            if item == 'tinyCrown' and '_dog_corgi_' in asset:
                # The ruby must remain visible and retain its colour after coat
                # tinting. Inspect the crown area, excluding the red tongue.
                ruby = []
                for y in range(full.getbbox()[1], min(full.height, full.getbbox()[1] + 40)):
                    for x in range(full.width):
                        r, g, b, a = full.getpixel((x, y))
                        if a and r > 120 and r > g * 1.7 and b > g * 1.2 and r > b * 1.4:
                            ruby.append((x, y))
                assert len(ruby) >= 12, (asset, 'missing red crown jewel')
                assert all(ink.getpixel(p) == full.getpixel(p) for p in ruby), (asset, 'jewel changes with coat colour')

    breeds, modes = list(PREFIXES), MODES
    directory = ROOT / 'SharedResources/PetOutfitFonts'
    index = json.loads((directory / 'index.json').read_text())
    expected_collections = {breed + '-' + item for breed in breeds for item in catalog['art']}
    assert {p.stem for p in directory.glob('*.ttc')} == expected_collections
    assert set(index.values()) == expected_collections
    all_faces = {}
    for path in sorted(directory.glob('*.ttc')):
        collection = TTCollection(path)
        assert len(collection.fonts) == 24, (path.name, 'must contain only one breed and accessory')
        for font in collection.fonts:
            name = font['name'].getDebugName(6)
            assert name not in all_faces and index[name] == path.stem, (path.name, name)
            all_faces[name] = font
    assert len(all_faces) == 1440 and all_faces.keys() == index.keys()
    faces = {name: font for name, font in all_faces.items() if name.startswith('PetAccessory')}
    assert len(faces) == 720

    def expected_bitmap(asset, item, ppem, dynamic_island):
        return outfit_bitmap(asset, ppem, dynamic_island, ink=True, item=item).tobytes()

    checked = 0
    for filename in ['PetIslandTimerPets', 'PetIslandLockTimerPets']:
        for base in TTCollection(ROOT / 'PetIslandLiveActivity/Resources' / (filename + '.ttc')).fonts:
            base_name = base['name'].getDebugName(6)
            if not any(base_name.endswith(breed + mode) for breed in breeds for mode in modes):
                continue  # Legacy fonts for species that are not selectable in this app.
            family = 'PetIslandLockTimer' if 'Lock' in base_name else 'PetIslandTimer'
            breed, mode = next((b, m) for b in breeds for m in modes if base_name == family + b + m)
            for item in catalog['art']:
                name = base_name.replace('PetIsland', 'PetAccessory') + item
                font = faces.pop(name)
                assert font.getBestCmap() == base.getBestCmap(), name
                assert font.getGlyphOrder() == base.getGlyphOrder(), name
                assert font['head'].unitsPerEm == base['head'].unitsPerEm, name
                for attr in ['ascent', 'descent', 'lineGap']:
                    assert getattr(font['hhea'], attr) == getattr(base['hhea'], attr), name
                assert font['hmtx'].metrics == base['hmtx'].metrics, name
                assert font['sbix'].strikes.keys() == base['sbix'].strikes.keys(), name
                for ppem, strike in font['sbix'].strikes.items():
                    for glyph_name in font.getGlyphOrder():
                        glyph = strike.glyphs[glyph_name]
                        original = base['sbix'].strikes[ppem].glyphs[glyph_name]
                        assert (glyph.originOffsetX, glyph.originOffsetY) == (original.originOffsetX, original.originOffsetY), name
                        if not original.imageData:
                            assert not glyph.imageData, name
                            continue
                        image = glyph_image(strike, glyph_name)
                        assert image.size == Image.open(BytesIO(original.imageData)).size, name
                        if not glyph_name.startswith('d'):
                            assert image.getbbox() is None, (name, glyph_name)
                            continue
                        asset = asset_for_digit(breed, mode, int(glyph_name[1:]))
                        assert image.tobytes() == expected_bitmap(asset, item, ppem, family == 'PetIslandTimer'), (name, glyph_name, 'stale or mismatched accessory pose')
                        bounds = image.getbbox()
                        assert bounds and bounds[1] >= 0 and bounds[3] < image.height, (name, glyph_name)
                        pet = Image.open(BytesIO(original.imageData)).convert('RGBA')
                        # Every frame must attach to the original silhouette, not float beside it.
                        a, b = image.getchannel('A'), pet.getchannel('A')
                        assert ImageChops.multiply(a, b.filter(ImageFilter.MaxFilter(3))).getbbox() is not None, (name, glyph_name, ppem, 'unattached')
                        checked += 1
    assert not faces, list(faces)
    dressed = [font for name, font in all_faces.items() if name.startswith('PetDressed')]
    assert len(dressed) == 720
    for font in dressed:
        name = font['name'].getDebugName(6)
        family = 'PetDressedLockTimer' if 'Lock' in name else 'PetDressedTimer'
        breed, mode, item = next((b, m, i) for b in breeds for m in modes for i in catalog['art'] if name == family + b + m + i)
        for ppem, strike in font['sbix'].strikes.items():
            for digit in range(10):
                asset = asset_for_digit(breed, mode, digit)
                actual = glyph_image(strike, f'd{digit}')
                assert actual.tobytes() == outfit_bitmap(asset, ppem, 'Lock' not in name, ink=False, item=item).tobytes(), (name, digit)
    print(f'Validated {len(manifest) * len(catalog["art"])} complete outfit frames, {checked} accessory glyphs and 720 dressed timer faces in 60 on-demand collections.')


if __name__ == "__main__":
    validate()
