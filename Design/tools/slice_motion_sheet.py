#!/usr/bin/env python3
"""Slice a horizontal motion sheet into normalized Xcode image sets."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image


CANVAS_SIZE = (220, 176)
SUBJECT_LIMIT = (196, 138)


def alpha_bbox(frame: Image.Image) -> tuple[int, int, int, int]:
    alpha = frame.getchannel("A")
    thresholded = alpha.point(lambda value: 255 if value > 8 else 0)
    bbox = thresholded.getbbox()
    if bbox is None:
        raise ValueError("frame contains no visible pixels")
    return bbox


def visible_column_runs(sheet: Image.Image, threshold: int = 64) -> list[tuple[int, int]]:
    alpha = sheet.getchannel("A")
    pixels = alpha.load()
    visible_columns = [
        x
        for x in range(sheet.width)
        if any(pixels[x, y] > threshold for y in range(sheet.height))
    ]
    if not visible_columns:
        return []

    runs: list[tuple[int, int]] = []
    start = previous = visible_columns[0]
    for x in visible_columns[1:]:
        if x > previous + 1:
            runs.append((start, previous + 1))
            start = x
        previous = x
    runs.append((start, previous + 1))
    return runs


def normalize_frames(
    sheet: Image.Image,
    frame_count: int,
    scale_multiplier: float,
    baseline: int,
) -> list[Image.Image]:
    runs = visible_column_runs(sheet)
    if len(runs) == frame_count:
        horizontal_bounds = runs
    else:
        # Fallback for sheets whose neighboring frames touch each other.
        horizontal_bounds = [
            (
                round(index * sheet.width / frame_count),
                round((index + 1) * sheet.width / frame_count),
            )
            for index in range(frame_count)
        ]

    trimmed: list[Image.Image] = []
    for left, right in horizontal_bounds:
        cell = sheet.crop((left, 0, right, sheet.height))
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
    parser.add_argument("--asset-prefix", required=True)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--frame-count", type=int, default=8)
    parser.add_argument("--scale", type=float, default=1.0)
    parser.add_argument("--baseline", type=int, default=158)
    args = parser.parse_args()

    if args.frame_count < 2:
        parser.error("--frame-count must be at least 2")
    if not 0 < args.scale <= 1.5:
        parser.error("--scale must be greater than 0 and no more than 1.5")
    if not 1 <= args.baseline < CANVAS_SIZE[1]:
        parser.error("--baseline must stay inside the normalized canvas")

    sheet = Image.open(args.input).convert("RGBA")
    frames = normalize_frames(
        sheet,
        frame_count=args.frame_count,
        scale_multiplier=args.scale,
        baseline=args.baseline,
    )
    for index, frame in enumerate(frames):
        write_image_set(args.catalog, f"{args.asset_prefix}_{index:02d}", frame)

    print(f"Wrote {len(frames)} motion frames for {args.asset_prefix}")


if __name__ == "__main__":
    main()
