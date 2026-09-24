#!/usr/bin/env python3
"""Check shipped lion/Cardigan assets without generation sources or local drafts."""
import json
from hashlib import sha256
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / "SharedResources/PetSprites.xcassets"
ARCADE = ROOT / "PetIsland/Assets.xcassets"
TOKENS = ("lion_adult", "lioness", "lion_cub", "dog_cardigan")
SIDE_POSES = {"idle": 2, "jump": 2, "play": 2, "run": 8, "sleep": 2, "walk": 8}


def validate_asset(catalog, name, size):
    folder = catalog / f"{name}.imageset"
    contents = json.loads((folder / "Contents.json").read_text())
    assert any(item.get("filename") == f"{name}.png" for item in contents["images"]), name
    with Image.open(folder / f"{name}.png") as image:
        assert image.mode == "RGBA" and image.size == size, (name, image.mode, image.size)
        alpha = image.getchannel("A")
        bounds = alpha.getbbox()
        assert bounds is not None, f"Empty artwork: {name}"
        assert bounds[0] >= 3 and bounds[1] >= 3, (name, bounds)
        assert bounds[2] <= size[0] - 3 and bounds[3] <= size[1] - 3, (name, bounds)
        assert sum(alpha.histogram()[1:9]) == 0, f"Invisible edge residue: {name}"
        return sha256(image.tobytes()).digest()


def main():
    checked = 0
    for token in TOKENS:
        for pose, count in SIDE_POSES.items():
            hashes = set()
            for index in range(count):
                name = f"companion_{token}_{pose}_{index:02}"
                hashes.add(validate_asset(SHARED, name, (220, 176)))
                checked += 1
            if pose in ("walk", "run"):
                assert len(hashes) == count, f"Duplicate gait frames: {token} {pose}"
        for index in range(4):
            validate_asset(ARCADE, f"pets_dash_{token}_{index:02}", (160, 160))
            checked += 1
        validate_asset(ARCADE, f"sky_paws_{token}", (256, 176))
        checked += 1
    assert checked == 116, checked
    print(f"Validated {checked} companion assets: complete states, fixed canvases, distinct gaits and safe margins.")


if __name__ == "__main__":
    main()
