# App Store release checklist

## Product positioning

Pet Island is a small virtual companion with one pixel dog. A person chooses
where to keep the dog: in a medium Home Screen enclosure widget or in a Live
Activity on Dynamic Island. The ball button triggers a brief reaction.

The app has no user-configurable timer and does not claim continuous background
animation. WidgetKit and ActivityKit decide when system presentations render
updates.

Suggested subtitle: `A tiny dog for your Home Screen`

Suggested category: `Lifestyle`

## App Review Notes

Pet Island is a serverless virtual companion built with SwiftUI, WidgetKit,
App Intents and ActivityKit.

To review the enclosure flow:

1. Open the app and choose **Enclosure**.
2. Return to the Home Screen, touch and hold an empty area, choose **Edit** →
   **Add Widget**, find **Pet Island**, select the medium size, and add it.
3. Tap the ball button. The dog performs a short state change; the presentation
   then returns to a resting state.

To review the Dynamic Island flow:

1. Return to the app and choose **Dynamic Island**.
2. Background the app on a compatible iPhone. The compact Live Activity shows
   the dog; touch and hold it to open the expanded presentation.
3. Tap the ball button to request one short reaction.
4. On an iPhone without Dynamic Island, inspect the Lock Screen presentation.
5. On a device with Always-On Display, reduced luminance intentionally uses a
   static sleeping pose.

The medium widget uses a WidgetKit timeline and shared App Group storage. The
Live Activity receives meaningful state updates through ActivityKit/App
Intents. Neither surface runs an endless animation loop. The system may delay
widget refreshes, shorten animations, or require device authentication for an
interaction.

The app uses no hidden background modes, accounts, analytics, advertising,
remote notifications or server in this MVP.

## Signing and shared data

- The app and widget extension must use the same Apple Developer Team.
- Each target needs its own unique Bundle Identifier.
- Both targets must include the same App Groups entitlement.
- The shared suite identifier in code must match the entitlement exactly.
- Distribution provisioning profiles must include that App Group.
- A Personal Team setup used for local experiments is not proof that the
  TestFlight/App Store configuration is valid.

## Before upload

- [ ] Join the Apple Developer Program.
- [ ] Confirm final app and extension Bundle Identifiers.
- [ ] Confirm the same Team and App Group on both targets.
- [ ] Verify distribution provisioning profiles contain the App Group.
- [ ] Replace privacy-policy and support contact placeholders.
- [ ] Add a public support URL and source repository URL.
- [ ] Confirm only the intended dog assets ship and document their license.
- [ ] Run unit tests and record the exact count/result.
- [ ] Produce clean Debug and Release integration builds.
- [ ] Test a clean install and first launch.
- [ ] Add the medium widget from the system gallery on a real iPhone.
- [ ] Verify App Group synchronization after app and widget interactions.
- [ ] Test the ball App Intent with the app foregrounded and suspended.
- [ ] Test Live Activity start, restore, switch-away and end paths.
- [ ] Test compact, minimal and expanded Dynamic Island presentations.
- [ ] Test Lock Screen and Always-On on a supported Pro model.
- [ ] Test on an iPhone without Dynamic Island.
- [ ] Verify English and Russian localizations.
- [ ] Verify VoiceOver, large Dynamic Type and Reduce Motion.
- [ ] Create screenshots without promising continuous background movement.
- [ ] Archive a Release build and validate it in Xcode Organizer.
- [ ] Upload to TestFlight and complete at least one external test cycle.

## Integration result

| Check | Result | Evidence |
| --- | --- | --- |
| Debug build | Passed | iOS Simulator 26.5, app + extension |
| Release build | Passed | iOS Simulator 26.5, unsigned |
| Unit tests | Passed | 19/19, `PetIslandConceptTests5.xcresult` |
| Medium widget | Not run | Simulator and real iPhone |
| App Group | Not run | Both targets + real-device signing |
| Dynamic Island | Not run | Compact/minimal/expanded |
| Lock Screen / AOD | Not run | Real compatible device |

## Claims to avoid in metadata

- “The pet runs continuously on your Home Screen/Dynamic Island.”
- “Real-time animation while the app is closed.”
- “Always-On animation.”
- “The app automatically installs a Home Screen widget.”

Accurate wording: the dog remains visible in a system widget or Live Activity
and performs brief reactions when the person interacts or the saved state
meaningfully changes.
