#!/usr/bin/env python3
"""Remove tiny disconnected artifacts far from the main sprite body."""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image


def components(alpha: Image.Image, threshold: int = 8) -> list[list[tuple[int, int]]]:
    width, height = alpha.size
    pixels = alpha.load()
    visited: set[tuple[int, int]] = set()
    result: list[list[tuple[int, int]]] = []

    for y in range(height):
        for x in range(width):
            origin = (x, y)
            if origin in visited or pixels[x, y] <= threshold:
                continue
            visited.add(origin)
            queue = deque([origin])
            component: list[tuple[int, int]] = []
            while queue:
                current_x, current_y = queue.popleft()
                component.append((current_x, current_y))
                for offset_y in (-1, 0, 1):
                    for offset_x in (-1, 0, 1):
                        if offset_x == 0 and offset_y == 0:
                            continue
                        neighbor = (current_x + offset_x, current_y + offset_y)
                        if not (0 <= neighbor[0] < width and 0 <= neighbor[1] < height):
                            continue
                        if neighbor in visited or pixels[neighbor[0], neighbor[1]] <= threshold:
                            continue
                        visited.add(neighbor)
                        queue.append(neighbor)
            result.append(component)
    return result


def bounds(component: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [point[0] for point in component]
    ys = [point[1] for point in component]
    return min(xs), min(ys), max(xs), max(ys)


def box_distance(
    first: tuple[int, int, int, int],
    second: tuple[int, int, int, int],
) -> int:
    horizontal = max(first[0] - second[2] - 1, second[0] - first[2] - 1, 0)
    vertical = max(first[1] - second[3] - 1, second[1] - first[3] - 1, 0)
    return max(horizontal, vertical)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--min-area", type=int, default=32)
    parser.add_argument("--proximity", type=int, default=12)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    if args.out.exists() and not args.force:
        parser.error(f"output already exists: {args.out}")

    image = Image.open(args.input).convert("RGBA")
    found = components(image.getchannel("A"))
    if not found:
        parser.error("input contains no visible sprite pixels")

    main_component = max(found, key=len)
    main_bounds = bounds(main_component)
    removed: list[tuple[int, tuple[int, int, int, int]]] = []
    output = image.copy()
    output_pixels = output.load()

    for component in found:
        if component is main_component:
            continue
        component_bounds = bounds(component)
        if len(component) >= args.min_area or box_distance(component_bounds, main_bounds) <= args.proximity:
            continue
        removed.append((len(component), component_bounds))
        for x, y in component:
            output_pixels[x, y] = (0, 0, 0, 0)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.out, optimize=True)
    print(f"Removed {len(removed)} component(s): {removed}")


if __name__ == "__main__":
    main()
