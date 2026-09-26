#!/usr/bin/env python3
"""Validate packaged timer fonts: registration, metrics and every gait bitmap."""
from io import BytesIO
from PIL import Image
from fontTools.ttLib import TTCollection
from functools import lru_cache
from pathlib import Path

# Read-only geometry expectations, using only the shipped asset catalogs.
ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'SharedResources/PetSprites.xcassets'
CANVAS = (220, 176)
BASELINE = 160
PREFIXES = {
    'DogShepherd': 'dog_shepherd', 'DogCorgi': 'dog_corgi',
    'DogDoberman': 'dog_doberman', 'DogBullTerrier': 'dog_bull_terrier',
    'CatClassic': 'cat', 'CatBritish': 'cat_british',
    'CatMaineCoon': 'cat_maine_coon', 'CatSiamese': 'cat_siamese',
    'FoxRed': 'fox', 'FoxArctic': 'fox_arctic',
    'ParrotClassic': 'parrot', 'ParrotCockatiel': 'parrot_cockatiel',
    'ParrotBudgie': 'parrot_budgie', 'ParrotMacaw': 'parrot_macaw',
    'PenguinClassic': 'penguin', 'PenguinRockhopper': 'penguin_rockhopper',
    'DogCardigan': 'dog_cardigan', 'LionAdult': 'lion_adult',
    'Lioness': 'lioness', 'LionCub': 'lion_cub',
}
COMPANIONS = {'DogCardigan', 'LionAdult', 'Lioness', 'LionCub'}
MODES = ('Run', 'Walk', 'Sleep', 'RunSleep', 'WalkSleep', 'RunWalkSleep')


def pose_for_digit(mode, digit):
    if mode == 'Sleep' or ('Sleep' in mode and digit >= 7):
        return 'sleep'
    if mode in ('Walk', 'WalkSleep') or (mode == 'RunWalkSleep' and digit >= 4):
        return 'walk'
    return 'run'


def asset_for_digit(breed, mode, digit):
    pose = pose_for_digit(mode, digit)
    if breed in COMPANIONS:
        index = 0 if pose == 'sleep' else (0, 4)[digit % 2]
        return f'companion_{PREFIXES[breed]}_{pose}_{index:02}'
    if breed == 'DogShepherd' and pose == 'sleep':
        return 'sprite_dog_lie_0'
    if breed.startswith('Parrot') and pose != 'sleep':
        token = {'ParrotClassic': 'classic', 'ParrotCockatiel': 'cockatiel',
                 'ParrotBudgie': 'budgie', 'ParrotMacaw': 'macaw'}[breed]
        return f'island_parrot_{token}_fly_{digit % 8:02}'
    suffix = pose if pose == 'sleep' else f'{pose}_{digit % 2}'
    return f'island_{PREFIXES[breed]}_{suffix}'


@lru_cache(maxsize=None)
def registered_canvas(asset, dynamic_island=False):
    image = Image.open(CATALOG / f'{asset}.imageset' / f'{asset}.png').convert('RGBA')
    bounds = image.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    assert bounds, asset
    if asset.startswith('companion_'):
        assert image.size == CANVAS
        return image
    # Keep this registration consistent with PetSpriteGeometry.
    scale = (180 / 259 if dynamic_island else 148 / 273) if asset.startswith('sprite_dog_lie_') else 1
    anchor = 161.5 if asset.startswith('sprite_dog_lie_') else image.width / 2
    result = Image.new('RGBA', CANVAS)
    size = (round(image.width * scale), round(image.height * scale))
    result.alpha_composite(image.resize(size, Image.Resampling.NEAREST),
                           (round(110 - anchor * scale), round(BASELINE - bounds[3] * scale)))
    return result


@lru_cache(maxsize=None)
def strike_bitmap(asset, ppem, dynamic_island=False):
    image = registered_canvas(asset, dynamic_island).resize((ppem, round(ppem * CANVAS[1] / CANVAS[0])),
                                             Image.Resampling.NEAREST)
    image.putalpha(image.getchannel('A').point(lambda a: 255 if a > 8 else 0))
    if asset.startswith('companion_'):
        return image
    bounds = image.getbbox()
    grounded = Image.new('RGBA', image.size)
    grounded.alpha_composite(image, (0, round(BASELINE * ppem / CANVAS[0]) - bounds[3]))
    return grounded


checked = 0
for filename, prefix in [('PetIslandTimerPets', 'PetIslandTimer'),
                         ('PetIslandLockTimerPets', 'PetIslandLockTimer')]:
    faces = {prefix + breed + mode for breed in PREFIXES for mode in MODES}
    found = set()
    path = ROOT / 'PetIslandLiveActivity/Resources' / f'{filename}.ttc'
    for font in TTCollection(path).fonts:
        name = font['name'].getDebugName(6)
        if name not in faces:
            continue
        found.add(name)
        em = font['head'].unitsPerEm
        assert font['hhea'].ascent == round(em * CANVAS[1] / CANVAS[0]), name
        assert font['hhea'].descent == 0 and font['hhea'].lineGap == 0, name
        for ppem, strike in font['sbix'].strikes.items():
            for digit in range(10):
                glyph_name = f'd{digit}'
                glyph = strike.glyphs[glyph_name]
                image = Image.open(BytesIO(glyph.imageData)).convert('RGBA')
                assert image.size == (ppem, round(ppem * CANVAS[1] / CANVAS[0])), name
                breed, mode = next((b, m) for b in PREFIXES for m in MODES if name == prefix + b + m)
                asset = asset_for_digit(breed, mode, digit)
                expected = strike_bitmap(asset, ppem, dynamic_island=prefix == 'PetIslandTimer')
                assert image.tobytes() == expected.tobytes(), (name, digit, 'bitmap differs from app registration')
                if not asset.startswith('companion_'):
                    assert image.getbbox()[3] == round(BASELINE * ppem / CANVAS[0]), (name, digit)
                assert glyph.originOffsetX == 0, name
                assert glyph.originOffsetY == -round(font['glyf'][glyph_name].yMin * ppem / em), name
                assert font['hmtx'][glyph_name] == (em, 0), name
                checked += 1
    assert found == faces, faces - found
print(f'Validated {checked} bitmaps, {len(PREFIXES) * len(MODES) * 2} faces, shared registration and CoreText bearings.')
