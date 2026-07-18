#!/usr/bin/env node

/**
 * Imports the permitted vscode-pets animations as lossless PNG frames.
 *
 * Requirements:
 *   - Node.js 18+
 *   - sharp (`npm install sharp`, or provide it through NODE_PATH)
 *
 * Usage:
 *   node Scripts/import_vscode_pets_assets.mjs
 *   node Scripts/import_vscode_pets_assets.mjs --source /path/to/vscode-pets
 *
 * The source is pinned to a specific commit for reproducible downloads. When
 * --source is used, the script reads the same paths from an existing checkout.
 * It does not resize, recolor, crop, retouch, or interpolate any source frame.
 */

import { createRequire } from 'node:module';
import { access, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
let sharp;
try {
  sharp = require('sharp');
} catch {
  throw new Error(
    'The "sharp" package is required. Install it with `npm install sharp` or make it available through NODE_PATH.',
  );
}

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectRoot = path.resolve(scriptDirectory, '..');
const defaultAssetCatalog = path.join(
  projectRoot,
  'SharedResources',
  'PetSprites.xcassets',
);
const defaultManifestPath = path.join(
  projectRoot,
  'SharedResources',
  'PetSpritesManifest.json',
);

const sourceRepository = 'https://github.com/tonybaloney/vscode-pets';
const sourceCommit = 'd661785e890c422999bdec739dcc0a6b65d6f1cd';
const rawBaseURL = `https://raw.githubusercontent.com/tonybaloney/vscode-pets/${sourceCommit}`;

const imports = [
  {
    species: 'dog',
    sourcePet: 'dog',
    sourceColor: 'brown',
    license: 'CC-BY-ND-4.0',
    states: ['idle', 'walk', 'run', 'swipe', 'with_ball', 'lie'],
  },
  {
    species: 'fox',
    sourcePet: 'fox',
    sourceColor: 'red',
    license: 'MIT',
    states: ['idle', 'walk', 'run', 'swipe', 'with_ball'],
  },
  {
    species: 'parrot',
    sourcePet: 'cockatiel',
    sourceColor: 'gray',
    license: 'MIT',
    states: ['idle', 'walk', 'run', 'swipe', 'with_ball'],
  },
  {
    species: 'bear',
    sourcePet: 'panda',
    sourceColor: 'black',
    license: 'MIT',
    states: ['idle', 'walk', 'run', 'swipe', 'with_ball', 'lie'],
  },
  {
    species: 'lizard',
    sourcePet: 'deno',
    sourceColor: 'green',
    license: 'MIT',
    states: ['idle', 'walk', 'run', 'swipe', 'with_ball'],
  },
];

function argumentValue(flag) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? undefined : process.argv[index + 1];
}

const sourceRootArgument = argumentValue('--source');
const assetCatalog = path.resolve(
  argumentValue('--output') ?? defaultAssetCatalog,
);
const manifestPath = path.resolve(
  argumentValue('--manifest') ?? defaultManifestPath,
);

async function exists(filePath) {
  try {
    await access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function loadSource(relativePath) {
  if (sourceRootArgument) {
    const localPath = path.join(path.resolve(sourceRootArgument), relativePath);
    if (!(await exists(localPath))) {
      throw new Error(`Missing source file: ${localPath}`);
    }
    return readFile(localPath);
  }

  const url = `${rawBaseURL}/${relativePath}`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Could not download ${url}: HTTP ${response.status}`);
  }
  return Buffer.from(await response.arrayBuffer());
}

function assetContents(filename) {
  return {
    images: [
      {
        filename,
        idiom: 'universal',
        scale: '1x',
      },
    ],
    info: {
      author: 'xcode',
      version: 1,
    },
  };
}

async function extractFrames(buffer, species, state) {
  const metadata = await sharp(buffer, { animated: true }).metadata();
  const decoded = await sharp(buffer, { animated: true })
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });

  const frameCount = decoded.info.pages ?? metadata.pages ?? 1;
  const width = decoded.info.width;
  const height = decoded.info.pageHeight ?? metadata.pageHeight;
  const channels = decoded.info.channels;
  if (!height || decoded.info.height !== height * frameCount) {
    throw new Error(`Unexpected animated image geometry for ${species}/${state}`);
  }

  const bytesPerFrame = width * height * channels;
  const frames = [];
  for (let index = 0; index < frameCount; index += 1) {
    const assetName = `sprite_${species}_${state}_${index}`;
    const fileName = `${assetName}.png`;
    const imageSet = path.join(assetCatalog, `${assetName}.imageset`);
    await mkdir(imageSet, { recursive: true });

    const frameStart = index * bytesPerFrame;
    const rawFrame = decoded.data.subarray(
      frameStart,
      frameStart + bytesPerFrame,
    );
    await sharp(rawFrame, {
      raw: { width, height, channels },
    })
      .png({ compressionLevel: 9, palette: false })
      .toFile(path.join(imageSet, fileName));

    await writeFile(
      path.join(imageSet, 'Contents.json'),
      `${JSON.stringify(assetContents(fileName), null, 2)}\n`,
    );
    frames.push(assetName);
  }

  const sourceDelays = metadata.delay ?? [];
  const frameDurationsMilliseconds = Array.from(
    { length: frameCount },
    (_, index) => sourceDelays[index] ?? 125,
  );

  return {
    frameCount,
    frameDurationsMilliseconds,
    width,
    height,
    frames,
  };
}

async function main() {
  await rm(assetCatalog, { recursive: true, force: true });
  await mkdir(assetCatalog, { recursive: true });
  await mkdir(path.dirname(manifestPath), { recursive: true });
  await writeFile(
    path.join(assetCatalog, 'Contents.json'),
    `${JSON.stringify(
      { info: { author: 'xcode', version: 1 } },
      null,
      2,
    )}\n`,
  );

  const manifest = {
    schemaVersion: 1,
    source: {
      repository: sourceRepository,
      commit: sourceCommit,
      rawBaseURL,
    },
    generatedAssetCatalog: path.basename(assetCatalog),
    frameNaming: 'sprite_<species>_<state>_<zero-based-index>',
    species: {},
  };

  for (const entry of imports) {
    const speciesManifest = {
      sourcePet: entry.sourcePet,
      sourceColor: entry.sourceColor,
      license: entry.license,
      states: {},
    };

    for (const state of entry.states) {
      const relativePath = `media/${entry.sourcePet}/${entry.sourceColor}_${state}_8fps.gif`;
      const sourceBuffer = await loadSource(relativePath);
      speciesManifest.states[state] = await extractFrames(
        sourceBuffer,
        entry.species,
        state,
      );
      speciesManifest.states[state].sourcePath = relativePath;
    }

    manifest.species[entry.species] = speciesManifest;
  }

  await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);

  const stateCount = Object.values(manifest.species).reduce(
    (sum, species) => sum + Object.keys(species.states).length,
    0,
  );
  const frameCount = Object.values(manifest.species).reduce(
    (speciesSum, species) =>
      speciesSum +
      Object.values(species.states).reduce(
        (stateSum, state) => stateSum + state.frameCount,
        0,
      ),
    0,
  );
  console.log(
    `Imported ${frameCount} lossless frames across ${stateCount} animation states into ${assetCatalog}`,
  );
  console.log(`Wrote manifest to ${manifestPath}`);
}

await main();
