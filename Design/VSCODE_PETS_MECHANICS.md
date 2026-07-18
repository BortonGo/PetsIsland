# vscode-pets mechanics audit for Pet Island

## Scope and pinned upstream

This audit is based on the real `main` branch of
[`tonybaloney/vscode-pets`](https://github.com/tonybaloney/vscode-pets), cloned
at commit
[`d661785e890c422999bdec739dcc0a6b65d6f1cd`](https://github.com/tonybaloney/vscode-pets/tree/d661785e890c422999bdec739dcc0a6b65d6f1cd).
It covers the runtime mechanics that are relevant to Pet Island: states,
movement, boundaries, multiple pets, interactions, themes, persistence and
asset licensing. It is not an inference from screenshots.

The most important architectural fact is that vscode-pets is not driven by a
single animation loop:

- the extension sends a pet-logic `tick` every 100 ms (10 Hz);
- the browser plays state-specific GIF files named `*_8fps.gif`;
- the thrown ball uses `requestAnimationFrame`, throttled to 24 fps.

This separation is worth preserving in the foreground Pet Island playground.
It cannot be copied literally into WidgetKit, whose Live Activity UI is a
system-hosted, update-driven presentation rather than a continuously running
game loop.

## Upstream source map

| Concern | Upstream implementation | What it actually owns |
| --- | --- | --- |
| State vocabulary and state classes | [`src/panel/states.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/states.ts) | `States`, `IState`, `FrameResult`, static/moving/chase/climb implementations and sprite labels |
| Shared pet runtime | [`src/panel/basepettype.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/basepettype.ts) | position, direction, speed, current state, random transitions, temporary interactions, friendships and sprite selection |
| Per-species behavior graph | [`src/panel/pets/*.ts`](https://github.com/tonybaloney/vscode-pets/tree/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets) | allowed colors, starting state, transition graph, personality text and occasional species overrides |
| Transition structure | [`src/panel/sequences.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/sequences.ts) | `ISequenceTree` and `ISequenceNode` (`state -> possibleNextStates`) |
| Species factory and collection | [`src/panel/pets.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets.ts) | pet construction, species speed tiers, colors, add/remove/reset, friend discovery |
| Webview orchestration and persistence | [`src/panel/main.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/main.ts) | DOM elements, spawn/recover/save, commands, theme setup and per-tick iteration |
| Tick source | [`src/extension/extension.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/extension/extension.ts#L792-L822) | `PetWebviewContainer` creates the 100 ms interval; panel ticks only while visible |
| Ball physics and gesture | [`src/panel/ball.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/ball.ts) | drag/flick velocity, gravity, damping, traction, wall/floor collisions and chase trigger |
| Themes and floor height | [`src/panel/themes.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/themes.ts) | background/foreground asset names, light/dark variants, effects and size-dependent floor |
| Public pet/color/size/theme catalog | [`src/common/types.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/common/types.ts) | 25 pet identifiers, colors, speed levels, four sizes and six theme choices |

## State machine

### State vocabulary

`States` contains 18 values:

- ground idle/motion: `sitIdle`, `lie`, `standRight`, `standLeft`,
  `walkRight`, `walkLeft`, `runRight`, `runLeft`;
- wall/air: `climbWallLeft`, `wallHangLeft`, `wallDigLeft`, `wallNap`,
  `jumpDownLeft`, `land`;
- interactions: `swipe`, `chase`, `idleWithBall`, `chaseFriend`.

The semantic state and visual animation are deliberately separate. Every
`IState` exposes `label`, `spriteLabel`, `horizontalDirection` and
`nextFrame()`. For example:

- `runRight` and `runLeft` both render the `walk_fast` GIF;
- `chase` and `chaseFriend` render `run`;
- `sitIdle` renders `idle`, `lie` renders `lie`;
- `idleWithBall` renders `with_ball`;
- wall states map to `wallclimb`, `wallgrab`, `walldig`, `wallnap`,
  `fall_from_grab` and `land`.

`FrameResult` is a small protocol between state and controller:
`stateContinue`, `stateComplete`, or `stateCancel`. `BasePetType.nextFrame()`
applies facing, selects the sprite, advances the current state and then either
chooses the next graph node or restores a temporarily interrupted state.

### Timing

The extension creates a 100 ms interval in `PetWebviewContainer`. Static
states count logic ticks, not GIF frames. Because completion is tested with
`counter > holdTime`, approximate visible durations are:

| State class | `holdTime` | Approximate duration at 10 Hz |
| --- | ---: | ---: |
| `SitIdleState`, `LieState`, `WallHangLeftState`, `WallNapState` | 50 | 5.1 s |
| `WallDigLeftState`, `StandRightState`, `StandLeftState` | 60 | 6.1 s |
| `SwipeState` | 15 | 1.6 s |
| `IdleWithBallState` | 30 | 3.1 s |
| `LandState` | 10 | 1.1 s |

Walking and running normally finish on a boundary instead of a timer. Their
hold time only prevents a zero-speed pet from staying in a moving state
forever.

### Species transition graphs

Each species subclasses `BasePetType` and supplies a transition table.
`chooseNextState()` selects uniformly from `possibleNextStates`; repeated
entries are intentional weights rather than mistakes.

Concrete examples:

- [`Cat`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/cat.ts)
  can idle, walk, run, climb the left wall, hang, fall and land.
- [`Dog`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/dog.ts)
  adds `lie` to the common idle/walk/run graph.
- [`Cockatiel`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/cockatiel.ts)
  currently uses the ordinary horizontal graph; upstream does not implement
  free two-dimensional bird flight.
- [`Totoro`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/totoro.ts)
  combines lying and the simpler cat wall sequence.
- [`Squirrel`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/squirrel.ts)
  has the richest graph: stand/run/walk, climb, dig, wall-nap, hang, fall and
  land. It varies climb speed and derives a random climb height from viewport
  height.
- [`Bunny`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/bunny.ts)
  uses duplicated transition entries to favor hops/runs in the same direction.
- [`Rocky`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets/rocky.ts)
  is constructed with speed `still` and explicitly refuses ball chasing.

This is the strongest mechanic to adapt: species should share a small set of
state implementations but own different weighted transition graphs. Avoid one
large switch that hardcodes every species.

## Movement and boundaries

### Horizontal movement

`WalkRightState` captures a right boundary equal to `floor(window.innerWidth *
0.95)`. Each tick it adds `pet.speed`, then clamps to `boundary - pet.width`.
`WalkLeftState` subtracts speed and clamps to zero. Run states inherit these
classes and use a `1.6` multiplier.

Species speed is selected by `createPet()` from the numeric `PetSpeed` levels
`still = 0` through `veryFast = 5`. `BasePetType` then randomizes the result to
70–130% so two pets of the same species do not move identically. Initial x is
randomized only within 70% of the viewport.

For Swift, use normalized logical coordinates for persistence and convert to
pixels at render time:

```text
availableWidth = containerWidth - spriteWidth
xPixels = clamp(position01, 0...1) * availableWidth
```

Keep direction separate from velocity so that idle/lying frames retain the
last facing. A fixed-step reducer should own motion; the SwiftUI view should
only render the resulting position.

### Vertical movement

Only the left-wall sequence changes `bottom`:

- `ClimbWallLeftState` adds `climbSpeed` until `climbHeight`;
- static wall states wait;
- `JumpDownLeftState` subtracts `fallSpeed` and clamps to `floor`;
- `LandState` pauses before returning to a ground state.

`isStateAboveGround()` prevents swipe and chase while climbing/falling. On
state recovery, ground states are snapped to the current theme floor because
the theme may have changed.

For Pet Island, model this as a capability (`canClimb`) and a vertical phase,
not as a special-case view offset. Dynamic Island should not receive this full
model; at most it should receive a short semantic `jump`/`fly` snapshot.

## Multiple pets and social behavior

[`PetCollection`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/pets.ts#L62-L165)
stores an arbitrary array and supports push, locate, remove and reset.
`seekNewFriends()` runs every 100 ms. It looks at friendless pets and considers
them touching when another pet's left edge lies inside the first pet's
horizontal span. On friendship it stores a friend reference and shows `❤️`
speech bubbles for two seconds.

`BasePetType.isPlaying` is true only during `runLeft` or `runRight`. A pet with
a running friend temporarily switches into `ChaseFriendState`, follows the
friend's x coordinate and cancels when the friend stops running. The temporary
`swipe` interaction uses a similar interruption mechanism: save the old state,
play swipe, then resume it.

What to adapt:

- one independent `PetAgent` per pet;
- a world-level collection that advances all agents in one deterministic tick;
- stable UUID relationships (`friendID`), never names as identity;
- a short heart event when compatible pets overlap;
- chase/follow as an interruptible goal above the ordinary species graph.

What not to copy literally:

- the upstream overlap check is one-dimensional and asymmetric;
- all pets scan all other pets every tick (`O(n²)`), acceptable for a handful
  but unnecessary for larger groups;
- friendship persistence uses names and can be ambiguous;
- state is saved on every 100 ms tick.

For the Pet Island playground, use rectangle/distance collision and cap the
active group to a deliberately small number. In compact Dynamic Island, show
only the lead pet; multiple fully independent agents need more space and more
updates than the system surface can guarantee.

## Interactions

### Petting/swipe

`main.ts` creates a transparent collision `div` beside each sprite. Mouse-over
calls `pet.swipe()` when `canSwipe` is true. The pet stores its current state,
plays the `swipe` animation, shows `👋`, and resumes the interrupted state.
Some species override only the speech content; for example Squirrel asks for a
random food emoji and Horse says “Neigh!”.

iOS adaptation: tap or short drag directly on a pet, emit a temporary
`petReaction` goal, and display a small SwiftUI speech bubble/haptic response.

### Ball throwing and fetch

[`ball.ts`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/src/panel/ball.ts)
implements two input modes:

- a command creates a ball at `(100, 100)` with velocity `(4, 5)`;
- dynamic throw tracks mouse movement and uses the final pointer delta as
  release velocity.

The simulation runs at 24 fps with gravity `0.6`, damping `0.9`, traction
`0.8`, and boundary collisions against canvas edges plus the theme floor.
Every eligible pet receives the same `BallState` and enters `ChaseState`.
Chase moves horizontally toward `ball.cx`; a simple x/height test marks the
ball caught, hides it and changes the pet to `idleWithBall`.

This mechanic belongs in the foreground playground. Use `DragGesture` plus a
fixed-step physics body (SpriteKit is the lowest-risk option; a tested Swift
reducer is also viable). One world object should own the ball; pets should
receive a target, not mutate separate ball copies. Dynamic Island can expose a
“play” intent and show a short response, but it cannot run this 24 fps physics
loop in the background.

### Commands and persistence

`main.ts` handles `spawn-pet`, `delete-pet`, `reset-pet`, `list-pets`,
`roll-call`, `throw-ball`, dynamic throwing and effect toggling. Persisted data
includes name, type, color, current state, friend name and pixel `left`/`bottom`.

Pet Island should persist species, color, normalized position, direction,
semantic state and friend UUID. Animation frame and transient chase/swipe
objects should be reconstructed rather than treated as durable state.

## Statuses, sprites, colors and themes

### Statuses and sprite frames

Upstream has no separate localized “status” layer. Its visible status is the
current state-specific GIF plus occasional speech bubble; roll-call combines
species emoji, name, color/type and species `hello` text.

`BasePetType.setAnimation()` builds an asset URL as
`{petRoot}_{spriteLabel}_8fps.gif` and avoids replacing the image when the same
animation is already active. The browser therefore owns frame playback; the
state machine only swaps whole GIFs.

For Pet Island:

- retain semantic state separately from sprite frame index;
- use losslessly decoded nearest-neighbor frames/atlases in the foreground;
- map semantic status text locally (`exploring`, `running`, `playing`,
  `resting`) rather than copying species dialogue;
- in Live Activity, send a small number of explicit state snapshots and end in
  a stable pose; do not attempt the upstream 8 fps GIF loop.

### Species, colors, size and speed

`common/types.ts` declares 25 pet identifiers, four sizes and five effective
speed levels. Each species exposes `possibleColors`, and `availableColors()` /
`normalizeColor()` enforce valid combinations. Examples include six cat
colors, five dog variants, two cockatiel colors, two panda colors and eleven
horse variants.

This is better represented in Swift as immutable species metadata:

```text
PetDefinition {
    species, allowedCoats, baseSpeed, capabilities,
    transitionGraph, spriteManifest
}
```

Free tinting should be an explicit Pet Island feature layered on top of an
asset that permits modification; it is not equivalent to upstream's discrete
pre-rendered color files.

### Themes

`Theme` contains `none`, `forest`, `castle`, `beach`, `winter` and `autumn`.
Every theme provides background/foreground images selected by light/dark mode
and pet size, plus an absolute floor height. Forest/beach use a star effect,
winter uses snow, and autumn uses falling leaves.

Adapt the concept, not the upstream image layout:

- define `PetHabitatTheme` with original Pet Island backgrounds;
- express floor as a normalized ratio or geometry-derived inset;
- render background, pet world and foreground as separate layers;
- make effects optional and respect Reduce Motion;
- do not place detailed themes/effects in Dynamic Island, where contrast,
  energy and size are system constrained.

## Recommended Swift architecture

| Upstream concept | Foreground Pet Island playground | Live Activity adapter |
| --- | --- | --- |
| `States` + `IState.nextFrame()` | Pure `PetBrain.advance(dt:world:)` reducer | Coarse `PetSnapshot` pose/direction/position |
| `ISequenceTree` | Per-species weighted transition table | Prebuilt finite interaction sequence |
| `BasePetType` | `PetAgent` model/actor, independent of SwiftUI | No independent loop |
| 100 ms extension tick | Fixed-step world update; render independently at display cadence | User/background-triggered update only |
| 8 fps GIF | Decoded frame atlas with nearest-neighbor rendering | 2–3 meaningful frames per short update |
| `PetCollection` | `PetWorld` with UUID-indexed agents | Lead pet only in compact UI |
| Canvas ball | SpriteKit or tested fixed-step physics model | Play icon + short reaction |
| DOM collision div | Sprite bounds/hit testing | Interactive button in expanded activity |
| Theme floor in pixels | Geometry-derived floor ratio | No themed floor beyond a simple track |
| Save every tick | Debounced persistence on semantic changes/background | Persist only last delivered snapshot |

Suggested implementation order for the next stage:

1. Introduce a pure, deterministic `PetBrain` with weighted transition graphs
   and tests for boundaries and forbidden transitions.
2. Build a foreground `PetWorld` that owns several `PetAgent`s and advances
   them with a fixed timestep.
3. Connect the current frame assets through a sprite manifest; never let views
   choose behavior.
4. Add tap/swipe interruption, speech bubbles and haptics.
5. Add one shared ball and drag/flick physics, then friend discovery/chase.
6. Convert semantic world events to short Live Activity snapshots. Keep the
   Live Activity adapter separate from the continuous foreground simulation.

## License and attribution audit

### Repository code

The root [`LICENSE`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/LICENSE)
is MIT, copyright © 2022 Anthony Shaw. It permits use, modification,
distribution and sublicensing, provided the copyright and permission notice
are included in copies or substantial portions.

For adapted mechanics/code, Pet Island should keep:

- the full MIT text and Anthony Shaw copyright in
  `THIRD_PARTY_NOTICES.md`;
- the upstream URL and pinned commit;
- an in-app/Open Source acknowledgements entry for binary distribution.

The existing Pet Island `THIRD_PARTY_NOTICES.md` already contains the full MIT
notice and the same pinned commit, so the repository-level attribution is in
good shape.

### Media is not “MIT by assumption”

The root MIT license does not remove restrictions stated for particular
third-party media:

- [`media/README.md`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/media/README.md)
  says the cat author asked that cat assets not be freely distributed on
  GitHub and directs users to purchase the catset. The upstream Git checkout
  contains no `media/cat/*_8fps.gif` files. Do not copy cat frames from a
  packaged extension or another installation.
- [`media/dog/license.txt`](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/media/dog/license.txt)
  applies Creative Commons Attribution-NoDerivatives 4.0 to the dog work.
  Recoloring, pixel edits or distributing modified dog frames is not compatible
  with NoDerivatives. Pet Island should continue using its original shepherd.
- [`README.md` credits](https://github.com/tonybaloney/vscode-pets/blob/d661785e890c422999bdec739dcc0a6b65d6f1cd/README.md#credits)
  name individual creators for many other assets: Marc Duiker (including the
  cockatiel), Elthen (fox), Jessie Ferris (panda), and others. Preserve those
  creator credits for every imported animal and verify any linked source terms
  before adding new media to an App Store build.

Therefore MIT is sufficient to adapt the TypeScript mechanics with notice, but
it is not a blanket permission to modify every pixel asset. New animals should
be original Pet Island art or imported only after a per-asset provenance check.

## Bottom line

The valuable reusable idea in vscode-pets is a small state protocol plus a
per-species weighted transition graph, not its DOM or GIF implementation. Port
that model into a deterministic Swift foreground world, preserve normalized
positions and UUID relationships, and expose only short semantic events to
WidgetKit. This keeps the application lively where iOS permits a real loop and
reliable where Dynamic Island does not.
