# Dog breed preview prompts

Mode: built-in `image_gen`; intent: `generate`; the approved shepherd sheet was
used only as a style, pose and scale reference. Each prompt requested exactly
six poses in one row on a flat `#00ff00` chroma-key background.

## Shared specification

```text
Use case: stylized-concept
Asset type: preview-only horizontal pixel-art sprite sheet for an iOS Dynamic Island virtual pet
Input image: the supplied approved shepherd sprite sheet is STYLE/POSE/SCALE REFERENCE ONLY. Do not copy, trace, recolor, or preserve any pixels, silhouette details, facial design, markings, or anatomy from it. Create an original character.
Primary request: Create one original, very cute <BREED> puppy sprite sheet with exactly six distinct poses in one horizontal row, ordered left to right: 1 idle standing, 2 walk/run contact pose, 3 walk/run passing pose clearly different from pose 2, 4 joyful forward jump/stretch, 5 playful bow with front legs down and rump up, 6 curled sleeping.
Style/medium: crisp low-detail hand-pixel-art look, chunky square pixels, limited palette, dark near-black pixel outline, cute expressive proportions, no smoothing, no antialiasing, no gradients.
Composition/framing: wide landscape canvas; exactly six ample equal-width cells implied only by spacing, no visible grid; one dog centered in every cell; consistent baseline, scale and character proportions; generous empty padding; no overlap and no cropped pixels.
Scene/backdrop: perfectly flat solid #00ff00 background across the entire canvas.
Constraints: six poses only; all dogs face right except sleeping may curl right; each pose isolated; sprite silhouette and leg positions must communicate motion; uniform background with no floor line, shadow, texture, lighting variation, dividers, labels, text, logo, or watermark.
Avoid: photorealism, vector smoothness, high detail, 3D, fuzzy fur, accessories, extra animals, duplicate poses, mixed scales, green anywhere in the dog.
```

## Breed-specific subject lines

### Corgi

```text
Subject: recognizable Pembroke Welsh corgi traits—short legs, compact long body, oversized upright ears, warm orange-and-cream coat, cream muzzle/chest, tiny dark nose, happy expressive eyes. Keep the design readable at Dynamic Island scale and genuinely original.
```

### Doberman

```text
Subject: recognizable friendly Doberman traits—slim athletic puppy body, naturally floppy ears, long muzzle softened into cute proportions, black-and-rust coat with small rust eyebrows, muzzle, chest and legs, tiny dark nose, bright gentle eyes. No cropped ears and no aggressive expression. Keep the design readable at Dynamic Island scale and genuinely original.
```

### Bull terrier

```text
Subject: recognizable but friendly English Bull Terrier traits—small triangular upright ears, gently egg-shaped head with curved profile, tiny triangular dark eyes made sweet rather than aggressive, sturdy compact body, white coat with one warm caramel ear patch and a small caramel body spot, tiny dark nose. Keep the design readable at Dynamic Island scale and genuinely original.
```
