#!/usr/bin/env python3
"""Slice a six-pose Pet Island sheet into normalized Xcode image sets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


POSES = ("idle", "walk_0", "walk_1", "jump", "play", "sleep")
CANVAS_SIZE = (220, 176)
SUBJECT_LIMIT = (196, 138)
BASELINE = 160


def alpha_bbox(frame: Image.Image) -> tuple[int, int, int, int]:
    alpha = frame.getchannel("A")
    thresholded = alpha.point(lambda value: 255 if value > 8 else 0)
    bbox = thresholded.getbbox()
    if bbox is None:
        raise ValueError("frame contains no visible pixels")
    return bbox


def normalize_frames(
    sheet: Image.Image,
    scale_multiplier: float = 1.0,
    baseline: int = BASELINE,
) -> list[Image.Image]:
    if sheet.width % len(POSES) != 0:
        raise ValueError(f"sheet width {sheet.width} is not divisible by {len(POSES)}")

    cell_width = sheet.width // len(POSES)
    trimmed: list[Image.Image] = []
    for index in range(len(POSES)):
        cell = sheet.crop((index * cell_width, 0, (index + 1) * cell_width, sheet.height))
        trimmed.append(cell.crop(alpha_bbox(cell)))

    base_scale = min(
        SUBJECT_LIMIT[0] / max(frame.width for frame in trimmed),
        SUBJECT_LIMIT[1] / max(frame.height for frame in trimmed),
        1.0,
    )
    scale = base_scale * scale_multiplier

    normalized: list[Image.Image] = []
    for frame in trimmed:
        resized = frame.resize(
            (max(round(frame.width * scale), 1), max(round(frame.height * scale), 1)),
            Image.Resampling.NEAREST,
        )
        canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
        x = (CANVAS_SIZE[0] - resized.width) // 2
        y = baseline - resized.height
        canvas.alpha_composite(resized, (x, y))
        normalized.append(canvas)
    return normalized


def write_image_set(catalog: Path, asset_name: str, image: Image.Image) -> None:
    image_set = catalog / f"{asset_name}.imageset"
    image_set.mkdir(parents=True, exist_ok=True)
    filename = f"{asset_name}.png"
    image.save(image_set / filename, optimize=True)
    contents = {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (image_set / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--species", required=True)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument(
        "--scale",
        type=float,
        default=1.0,
        help="Per-character visual scale multiplier after standard normalization",
    )
    parser.add_argument(
        "--baseline",
        type=int,
        default=BASELINE,
        help="Vertical pixel coordinate used as the character ground line",
    )
    args = parser.parse_args()

    if not 0 < args.scale <= 1.5:
        parser.error("--scale must be greater than 0 and no more than 1.5")
    if not 1 <= args.baseline < CANVAS_SIZE[1]:
        parser.error("--baseline must stay inside the normalized canvas")

    sheet = Image.open(args.input).convert("RGBA")
    frames = normalize_frames(
        sheet,
        scale_multiplier=args.scale,
        baseline=args.baseline,
    )
    for pose, frame in zip(POSES, frames, strict=True):
        write_image_set(args.catalog, f"island_{args.species}_{pose}", frame)

    print(f"Wrote {len(frames)} frames for {args.species}")


if __name__ == "__main__":
    main()
