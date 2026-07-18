#!/usr/bin/env python3
"""Build single-texture sprite atlases for WidgetKit motion rendering."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "SharedResources" / "PetSprites.xcassets"


ATLASES: dict[str, list[str]] = {
    "widget_atlas_dog_shepherd_run": [f"sprite_dog_run_{index}" for index in range(6)],
    "widget_atlas_dog_corgi_run": [
        "island_dog_corgi_walk_0", "island_dog_corgi_idle",
        "island_dog_corgi_walk_1", "island_dog_corgi_idle",
    ],
    "widget_atlas_dog_doberman_run": [
        "island_dog_doberman_walk_0", "island_dog_doberman_idle",
        "island_dog_doberman_walk_1", "island_dog_doberman_idle",
    ],
    "widget_atlas_dog_bull_terrier_run": [
        "island_dog_bull_terrier_walk_0", "island_dog_bull_terrier_idle",
        "island_dog_bull_terrier_walk_1", "island_dog_bull_terrier_idle",
    ],
    "widget_atlas_cat_classic_run": [
        "island_cat_walk_0", "island_cat_idle", "island_cat_walk_1", "island_cat_idle",
    ],
    "widget_atlas_cat_british_run": [
        "island_cat_british_walk_0", "island_cat_british_idle",
        "island_cat_british_walk_1", "island_cat_british_idle",
    ],
    "widget_atlas_cat_maine_coon_run": [
        "island_cat_maine_coon_walk_0", "island_cat_maine_coon_idle",
        "island_cat_maine_coon_walk_1", "island_cat_maine_coon_idle",
    ],
    "widget_atlas_cat_siamese_run": [
        "island_cat_siamese_walk_0", "island_cat_siamese_idle",
        "island_cat_siamese_walk_1", "island_cat_siamese_idle",
    ],
    "widget_atlas_fox_red_run": [
        "island_fox_walk_0", "island_fox_idle", "island_fox_walk_1", "island_fox_idle",
    ],
    "widget_atlas_fox_arctic_run": [
        "island_fox_arctic_walk_0", "island_fox_arctic_idle",
        "island_fox_arctic_walk_1", "island_fox_arctic_idle",
    ],
    "widget_atlas_parrot_classic_fly": [
        "island_parrot_walk_1", "island_parrot_jump",
        "island_parrot_walk_0", "island_parrot_jump",
    ],
    "widget_atlas_parrot_cockatiel_fly": [
        "island_parrot_cockatiel_walk_1", "island_parrot_cockatiel_jump",
        "island_parrot_cockatiel_walk_0", "island_parrot_cockatiel_jump",
    ],
    "widget_atlas_parrot_budgie_fly": [
        "island_parrot_budgie_walk_1", "island_parrot_budgie_jump",
        "island_parrot_budgie_walk_0", "island_parrot_budgie_jump",
    ],
    "widget_atlas_parrot_macaw_fly": [
        f"island_parrot_macaw_fly_{index:02d}" for index in range(8)
    ],
    "widget_atlas_penguin_classic_run": [
        "island_penguin_walk_0", "island_penguin_idle",
        "island_penguin_walk_1", "island_penguin_idle",
    ],
    "widget_atlas_penguin_rockhopper_run": [
        "island_penguin_rockhopper_walk_0", "island_penguin_rockhopper_idle",
        "island_penguin_rockhopper_walk_1", "island_penguin_rockhopper_idle",
    ],
    "widget_atlas_bear_run": [f"sprite_bear_run_{index}" for index in range(16)],
    "widget_atlas_lizard_run": [f"sprite_lizard_run_{index}" for index in range(4)],
    "widget_atlas_bunny_run": ["sprite_bunny_idle_0"],
}


def image_for_asset(asset_name: str) -> Image.Image:
    path = CATALOG / f"{asset_name}.imageset" / f"{asset_name}.png"
    if not path.exists():
        raise FileNotFoundError(path)
    return Image.open(path).convert("RGBA")


def write_atlas(asset_name: str, frame_names: list[str]) -> None:
    frames = [image_for_asset(frame_name) for frame_name in frame_names]
    size = frames[0].size
    if any(frame.size != size for frame in frames):
        raise ValueError(f"frames for {asset_name} do not share one size")

    atlas = Image.new("RGBA", (size[0] * len(frames), size[1]), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, (index * size[0], 0))

    image_set = CATALOG / f"{asset_name}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    filename = f"{asset_name}.png"
    atlas.save(image_set / filename, optimize=True)
    contents = {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (image_set / "Contents.json").write_text(
        json.dumps(contents, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    for name, frames in ATLASES.items():
        write_atlas(name, frames)
    print(f"Wrote {len(ATLASES)} WidgetKit sprite atlases")


if __name__ == "__main__":
    main()
