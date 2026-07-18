# Pet variant preview sheets

These files are design previews only. They establish each variant's appearance before transparent production sprites and motion cycles are generated.

## Shared generation specification

- Tool/mode: built-in `image_gen`, intent `generate`.
- References: existing Pet Island sheets are used only for style, pose order, and approximate scale. Do not trace, recolor, or retain their pixels or exact silhouettes.
- Layout: one wide 3:1 PNG, exactly six isolated poses in one horizontal row: idle, locomotion A, locomotion B, jump/fly/play, playful crouch/landing, sleep.
- Style: original cute chunky low-detail pixel art, limited palette, dark square-pixel outline, readable at Dynamic Island size, no smoothing, antialiasing, gradients, text, labels, shadows, or watermark.
- Scale: one complete character per implied equal-width cell, consistent body proportions and baseline, no overlaps or cropping.
- Chroma: cats, fox, and penguin use green; parrots use magenta to avoid destroying green plumage.

## Subject prompts

- `cat-british-v1.png`: plush round blue-grey British Shorthair, small ears, full cheeks, copper-gold eyes.
- `cat-maine-coon-v1.png`: compact fluffy warm-brown tabby Maine Coon, tufted ears, bushy tail, green eyes.
- `cat-siamese-v1.png`: slim cream Siamese, chocolate mask/ears/paws/tail, bright blue eyes.
- `fox-arctic-v1.png`: compact white Arctic fox, pale cool-grey form accents, black nose and eyes, very fluffy tail.
- `parrot-cockatiel-v1.png`: grey cockatiel, yellow face and crest, orange cheek patches; walking poses are replaced by hopping/wing poses.
- `parrot-budgie-v1.png`: green-yellow budgerigar, dark green wing markings and blue cheek spots; walking poses are replaced by hopping/wing poses.
- `parrot-macaw-v1.png`: scarlet macaw, cream face patch, red body, yellow-and-blue wings, long red-blue tail; walking poses are replaced by hopping/wing poses.
- `penguin-rockhopper-v1.png`: southern rockhopper penguin chick, black-and-white body, orange beak and feet, two obvious symmetric yellow eyebrow crests in all poses.

## Production motion format

After visual approval, locomotion is generated as separate motion sheets instead of trying to interpolate the six semantic preview poses:

- `walk`: 8 frames, 110 ms per frame.
- `run`: 8 frames, 80 ms per frame.
- `fly`: 8 frames, 90 ms per frame.
- Output frame: transparent RGBA 220x176, shared baseline 160, nearest-neighbour pixel scaling.
- Asset name: `island_<species>_<variant>_<state>_<00...07>`.
