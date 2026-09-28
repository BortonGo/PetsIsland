#!/usr/bin/env python3
"""Check foreground animation completeness, distinct frames and safe margins."""
from pathlib import Path
from hashlib import sha256
from collections import deque
from PIL import Image

root = Path(__file__).resolve().parents[1]
catalog = root / "PetIsland/Resources/NaturalGaits.xcassets"
tokens = ["dog_shepherd", "dog_corgi", "dog_doberman", "dog_bull_terrier",
          "cat", "cat_maine_coon", "cat_british", "cat_siamese",
          "fox", "fox_arctic", "penguin", "penguin_rockhopper"]
checked = 0
for token in tokens:
    for pose in ("walk", "run"):
        # Pembroke uses four approved frames from the shared catalog.
        if token == "dog_corgi" and pose == "walk":
            continue
        hashes = set()
        for index in range(8):
            name = f"fluid_{token}_{pose}_{index}"
            image = Image.open(catalog / f"{name}.imageset" / f"{name}.png")
            assert image.mode == "RGBA" and image.size == (244, 176), name
            bounds = image.getchannel("A").getbbox()
            assert bounds and 0 < bounds[0] < bounds[2] < 244, (name, bounds)
            assert 0 < bounds[1] < bounds[3] < 176, (name, bounds)
            hashes.add(sha256(image.tobytes()).digest())
            checked += 1
        assert len(hashes) == 8, f"Duplicated poses in {token} {pose}"
print(f"Validated {checked} foreground frames in 23 distinct animation cycles.")

shared = root / "SharedResources/PetSprites.xcassets"
corgi_steps = []
for index in range(4):
    name = f"island_dog_corgi_walk_{index}"
    image = Image.open(shared / f"{name}.imageset" / f"{name}.png")
    assert image.mode == "RGBA" and image.size == (220, 176), name
    alpha = image.getchannel("A")
    bounds = alpha.getbbox()
    assert bounds and bounds[1] in (42, 43) and bounds[2:] == (178, 160), (name, bounds)
    assert set(image.getchannel("A").tobytes()) == {0, 255}, name
    # All four paws, including the lifted one, remain separated below the belly.
    for y in (150, 151, 152):
        spans = 0
        was_visible = False
        for x in range(image.width):
            visible = alpha.getpixel((x, y)) > 0
            spans += visible and not was_visible
            was_visible = visible
        assert spans == 4, (name, y, "Missing or merged paws", spans)
    corgi_steps.append(image)
assert len({sha256(image.tobytes()).digest() for image in corgi_steps}) == 4, "Repeated corgi phase"
for region in [(35, 134, 112, 164), (112, 134, 180, 164)]:
    assert len({image.crop(region).tobytes() for image in corgi_steps}) == 4, "Static corgi legs"
# Frame 0 is also a long-held DI pose: its near hind paw must reach the
# contact plane rather than remain visibly tucked above the other feet.
near_hind_region = (56, 140, 76, 166)
near_hind_bounds = corgi_steps[0].getchannel("A").crop(near_hind_region).getbbox()
assert near_hind_bounds and 159 <= near_hind_region[1] + near_hind_bounds[3] <= 160, \
    ("Corgi walk 0 near hind paw floats above the ground", near_hind_bounds)
print("Validated 4 shared corgi walking phases: four distinct paws, stable head, common ground and crisp alpha.")

# Fixed-cell slicing previously left a neighbouring jumping paw in the British
# and Siamese play poses. Allow tiny detached whiskers, but never a second piece
# of character art. These poses are shared by the app and Live Activity.
for token in ("cat", "cat_british", "cat_maine_coon", "cat_siamese"):
    for pose in ("jump", "play"):
        name = f"island_{token}_{pose}"
        image = Image.open(shared / f"{name}.imageset" / f"{name}.png")
        width, height = image.size
        mask = bytearray(value > 96 for value in image.getchannel("A").tobytes())
        pieces = []
        for start in range(len(mask)):
            if not mask[start]:
                continue
            mask[start] = 0
            queue = deque([start])
            count = 0
            while queue:
                index = queue.popleft()
                x, y = index % width, index // width
                count += 1
                neighbours = ([index - 1] if x else []) + ([index + 1] if x + 1 < width else [])
                neighbours += ([index - width] if y else []) + ([index + width] if y + 1 < height else [])
                for neighbour in neighbours:
                    if mask[neighbour]:
                        mask[neighbour] = 0
                        queue.append(neighbour)
            pieces.append(count)
        pieces.sort(reverse=True)
        assert pieces and pieces[0] > 1000, f"Missing cat in {name}"
        assert all(size <= 16 for size in pieces[1:]), f"Stray sprite fragment in {name}: {pieces[1:]}"
print("Validated 8 complete cat jump/play sprites without neighbouring fragments.")
