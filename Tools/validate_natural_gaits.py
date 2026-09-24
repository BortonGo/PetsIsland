#!/usr/bin/env python3
"""Check foreground animation completeness, distinct frames and safe margins."""
from pathlib import Path
from hashlib import sha256
from PIL import Image

root = Path(__file__).resolve().parents[1]
catalog = root / "PetIsland/Resources/NaturalGaits.xcassets"
tokens = ["dog_shepherd", "dog_corgi", "dog_doberman", "dog_bull_terrier",
          "cat", "cat_maine_coon", "cat_british", "cat_siamese",
          "fox", "fox_arctic", "penguin", "penguin_rockhopper"]
checked = 0
for token in tokens:
    for pose in ("walk", "run"):
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
print(f"Validated {checked} foreground frames in 24 distinct animation cycles.")
