import fs from "node:fs/promises";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const sharp = require("sharp");

const root = path.resolve(import.meta.dirname, "..");
const source = path.join(root, "Design", "PetPortraitsSource.png");
const outputRoot = path.join(root, "PetIsland", "Assets.xcassets", "PetPortraits");
const species = ["cat", "dog", "fox", "parrot", "bear", "penguin", "lizard", "bunny"];

const metadata = await sharp(source).metadata();
if (!metadata.width || !metadata.height) throw new Error("Portrait source has no dimensions");

await fs.mkdir(outputRoot, { recursive: true });
await fs.writeFile(
  path.join(outputRoot, "Contents.json"),
  JSON.stringify({ info: { author: "xcode", version: 1 } }, null, 2) + "\n"
);

for (let index = 0; index < species.length; index += 1) {
  const column = index % 4;
  const row = Math.floor(index / 4);
  const left = Math.floor((column * metadata.width) / 4);
  const right = Math.floor(((column + 1) * metadata.width) / 4);
  const top = Math.floor((row * metadata.height) / 2);
  const bottom = Math.floor(((row + 1) * metadata.height) / 2);

  const { data, info } = await sharp(source)
    .extract({ left, top, width: right - left, height: bottom - top })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  removeConnectedLightBackground(data, info.width, info.height, info.channels);
  removeSmallDetachedArtifacts(data, info.width, info.height, info.channels);
  const bounds = alphaBounds(data, info.width, info.height, info.channels, 12);
  const assetName = `pet_${species[index]}.png`;
  const imageset = path.join(outputRoot, `pet_${species[index]}.imageset`);
  await fs.mkdir(imageset, { recursive: true });

  await sharp(data, { raw: info })
    .extract(bounds)
    .resize(192, 192, {
      fit: "contain",
      background: { r: 0, g: 0, b: 0, alpha: 0 },
      kernel: "nearest",
    })
    .png({ compressionLevel: 9, palette: true })
    .toFile(path.join(imageset, assetName));

  await fs.writeFile(
    path.join(imageset, "Contents.json"),
    JSON.stringify(
      {
        images: [{ filename: assetName, idiom: "universal", scale: "1x" }],
        info: { author: "xcode", version: 1 },
        properties: { "preserves-vector-representation": false },
      },
      null,
      2
    ) + "\n"
  );
}

function isLightBackground(data, offset) {
  const red = data[offset];
  const green = data[offset + 1];
  const blue = data[offset + 2];
  const maximum = Math.max(red, green, blue);
  const minimum = Math.min(red, green, blue);
  return minimum >= 225 && maximum - minimum <= 16;
}

function removeConnectedLightBackground(data, width, height, channels) {
  const visited = new Uint8Array(width * height);
  const queue = new Int32Array(width * height);
  let head = 0;
  let tail = 0;

  const enqueue = (x, y) => {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    const index = y * width + x;
    if (visited[index]) return;
    const offset = index * channels;
    if (!isLightBackground(data, offset)) return;
    visited[index] = 1;
    queue[tail++] = index;
  };

  for (let x = 0; x < width; x += 1) {
    enqueue(x, 0);
    enqueue(x, height - 1);
  }
  for (let y = 0; y < height; y += 1) {
    enqueue(0, y);
    enqueue(width - 1, y);
  }

  while (head < tail) {
    const index = queue[head++];
    const x = index % width;
    const y = Math.floor(index / width);
    data[index * channels + 3] = 0;
    enqueue(x - 1, y);
    enqueue(x + 1, y);
    enqueue(x, y - 1);
    enqueue(x, y + 1);
  }
}

function removeSmallDetachedArtifacts(data, width, height, channels) {
  const visited = new Uint8Array(width * height);
  const queue = new Int32Array(width * height);
  const components = [];

  for (let start = 0; start < width * height; start += 1) {
    if (visited[start] || data[start * channels + 3] === 0) continue;

    let head = 0;
    let tail = 0;
    const pixels = [];
    queue[tail++] = start;
    visited[start] = 1;

    while (head < tail) {
      const index = queue[head++];
      pixels.push(index);
      const x = index % width;
      const y = Math.floor(index / width);

      for (const [nextX, nextY] of [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]]) {
        if (nextX < 0 || nextY < 0 || nextX >= width || nextY >= height) continue;
        const next = nextY * width + nextX;
        if (visited[next] || data[next * channels + 3] === 0) continue;
        visited[next] = 1;
        queue[tail++] = next;
      }
    }
    components.push(pixels);
  }

  const largest = Math.max(...components.map((component) => component.length), 0);
  const minimumSize = Math.max(24, Math.floor(largest * 0.018));
  for (const component of components) {
    if (component.length >= minimumSize) continue;
    for (const index of component) data[index * channels + 3] = 0;
  }
}

function alphaBounds(data, width, height, channels, padding) {
  let minX = width;
  let minY = height;
  let maxX = 0;
  let maxY = 0;

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      if (data[(y * width + x) * channels + 3] === 0) continue;
      minX = Math.min(minX, x);
      minY = Math.min(minY, y);
      maxX = Math.max(maxX, x);
      maxY = Math.max(maxY, y);
    }
  }

  if (minX > maxX || minY > maxY) throw new Error("No visible pixels found");
  minX = Math.max(0, minX - padding);
  minY = Math.max(0, minY - padding);
  maxX = Math.min(width - 1, maxX + padding);
  maxY = Math.min(height - 1, maxY + padding);
  return { left: minX, top: minY, width: maxX - minX + 1, height: maxY - minY + 1 };
}

console.log(`Built ${species.length} original portrait assets in ${outputRoot}`);
