import ActivityKit
import AppIntents
import CoreText
import SwiftUI
import WidgetKit

struct PetLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PetActivityAttributes.self) { context in
            LockScreenPetView(context: context)
                .activityBackgroundTint(Color(red: 0.07, green: 0.08, blue: 0.14))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLink(for: context.attributes.sessionID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.pet.name, systemImage: "pawprint.fill")
                        .font(.caption.bold())
                        .lineLimit(1)
                        .foregroundStyle(accent(for: context.attributes.pet))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: symbol(for: resolvedPose(context)))
                        .font(.caption.bold())
                        .foregroundStyle(accent(for: context.attributes.pet))
                        .accessibilityLabel(status(for: resolvedPose(context)))
                }
                DynamicIslandExpandedRegion(.center) {
                    ActivityPetTrack(
                        identity: context.attributes.pet,
                        snapshot: resolvedSnapshot(context),
                        isStale: context.isStale,
                        spriteSize: CGSize(width: 50, height: 44)
                    )
                    .frame(height: 72)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Label(status(for: resolvedPose(context)), systemImage: symbol(for: resolvedPose(context)))
                        Spacer()
                        Button(intent: PetLiveActionIntent(
                            sessionID: context.attributes.sessionID,
                            action: .run
                        )) {
                            Image(systemName: "figure.run")
                        }
                        .buttonStyle(.plain)
                        .tint(accent(for: context.attributes.pet))
                        .accessibilityLabel("Run")

                        Button(intent: PetLiveActionIntent(
                            sessionID: context.attributes.sessionID,
                            action: .play
                        )) {
                            Image(systemName: "tennisball.fill")
                        }
                        .buttonStyle(.plain)
                        .tint(accent(for: context.attributes.pet))
                        .accessibilityLabel("Play")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                CompactTimerPet(
                    context: context,
                    viewport: CGSize(width: 32, height: 26)
                )
            } compactTrailing: {
                EmptyView()
            } minimal: {
                CompactTimerPet(
                    context: context,
                    viewport: CGSize(width: 25, height: 22)
                )
            }
            .keylineTint(accent(for: context.attributes.pet))
            .widgetURL(deepLink(for: context.attributes.sessionID))
        }
    }

    private func resolvedSnapshot(_ context: ActivityViewContext<PetActivityAttributes>) -> PetSnapshot {
        context.state.snapshot
    }

    private func resolvedPose(_ context: ActivityViewContext<PetActivityAttributes>) -> PetPose {
        context.isStale ? .sleep : context.state.snapshot.pose
    }

    private func status(for pose: PetPose) -> LocalizedStringKey {
        switch pose {
        case .idle: "Looking around"
        case .walk: "Exploring the island"
        case .run: "Running"
        case .jump: "Happy to see you"
        case .fly: "Flying over the island"
        case .play: "Playing"
        case .eat: "Having a snack"
        case .sleep: "Resting"
        }
    }

    private func symbol(for pose: PetPose) -> String {
        switch pose {
        case .idle: "pawprint.fill"
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .jump: "arrow.up"
        case .fly: "bird.fill"
        case .play: "sparkles"
        case .eat: "carrot.fill"
        case .sleep: "moon.zzz.fill"
        }
    }

    private func deepLink(for sessionID: UUID) -> URL? {
        URL(string: "petisland://session/\(sessionID.uuidString)")
    }
}

/// The compact island has no long-running SwiftUI render loop. Its visible
/// sprite is therefore a custom timer font: the system changes the timer's
/// final digit once per second and the font maps that digit to gait A, gait B,
/// or sleep. The pet stays anchored exactly like the reference implementation.
private struct CompactTimerPet: View {
    let context: ActivityViewContext<PetActivityAttributes>
    let viewport: CGSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let snapshot = context.state.snapshot

        Group {
            if isLuminanceReduced || context.isStale {
                compactArtwork(pose: .sleep, step: 0)
            } else if context.attributes.motionMode == .sleep {
                compactArtwork(pose: .sleep, step: 0)
            } else if let fontName = LiveTimerPetFontRegistry.fontName(
                for: context.attributes.pet,
                mode: context.attributes.motionMode
            ) {
                LiveTimerGlyphPet(
                    timerStart: context.attributes.startedAt,
                    fontName: fontName,
                    viewport: viewport
                )
            } else {
                compactArtwork(pose: snapshot.pose, step: 0)
            }
        }
        .frame(width: viewport.width, height: viewport.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(verbatim: context.attributes.pet.name) + Text(", pet session")
        )
    }

    private func compactArtwork(pose: PetPose, step: Int) -> some View {
        PetArtwork(
            species: context.attributes.pet.species,
            coat: context.attributes.pet.coat,
            customColor: context.attributes.pet.customColor,
            breed: context.attributes.pet.breed,
            pose: pose,
            direction: context.state.snapshot.direction,
            step: step,
            animatesMotion: false
        )
    }
}

/// The timer text may contain hours and separators, but only its final glyph
/// is placed inside the compact viewport. All preceding glyphs remain clipped.
private struct LiveTimerGlyphPet: View {
    let timerStart: Date
    let fontName: String
    let viewport: CGSize

    var body: some View {
        // The generated sbix font contains a native 96 px bitmap strike.
        // Rendering it at 32 pt on a @3x Dynamic Island screen selects that
        // strike without vectorizing or independently moving sprite pixels.
        let glyphSize: CGFloat = 32

        Text(timerStart, style: .timer)
            .font(.custom(fontName, fixedSize: glyphSize))
            .lineLimit(1)
            .frame(width: glyphSize * 9, height: glyphSize)
            .multilineTextAlignment(.trailing)
            .offset(x: -glyphSize * 4)
            .offset(y: -1)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
    }
}

private struct LockScreenPetView: View {
    let context: ActivityViewContext<PetActivityAttributes>
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var resolvedSnapshot: PetSnapshot {
        guard isLuminanceReduced || context.isStale else { return context.state.snapshot }
        return PetSnapshot(
            pose: .sleep,
            position: context.state.snapshot.position,
            direction: context.state.snapshot.direction,
            revision: context.state.snapshot.revision,
            generatedAt: context.state.snapshot.generatedAt
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(context.attributes.pet.name, systemImage: "pawprint.fill")
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(accent(for: context.attributes.pet))
                Spacer()
                Label(
                    isLuminanceReduced || context.isStale ? "Resting" : status(for: resolvedSnapshot.pose),
                    systemImage: symbol(for: resolvedSnapshot.pose)
                )
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            }
            ActivityPetTrack(
                identity: context.attributes.pet,
                snapshot: resolvedSnapshot,
                isStale: context.isStale,
                forceSleep: isLuminanceReduced,
                spriteSize: CGSize(width: 62, height: 54)
            )
            .frame(height: 78)
        }
        .padding(14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: context.attributes.pet.name) + Text(", pet session"))
    }

    private func status(for pose: PetPose) -> LocalizedStringKey {
        switch pose {
        case .idle: "Looking around"
        case .walk: "Exploring the island"
        case .run: "Running"
        case .jump: "Happy to see you"
        case .fly: "Flying over the island"
        case .play: "Playing"
        case .eat: "Having a snack"
        case .sleep: "Resting"
        }
    }

    private func symbol(for pose: PetPose) -> String {
        switch pose {
        case .idle: "pawprint.fill"
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .jump: "arrow.up"
        case .fly: "bird.fill"
        case .play: "sparkles"
        case .eat: "carrot.fill"
        case .sleep: "moon.zzz.fill"
        }
    }
}

private enum LiveTimerPetFontRegistry {
    private static let registration: Void = {
        guard let url = Bundle.main.url(
            forResource: "PetIslandTimerPets",
            withExtension: "ttc"
        ) else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }()

    static func fontName(for pet: PetActivityIdentity, mode: DynamicIslandMotionMode) -> String? {
        _ = registration
        let name = postScriptName(for: pet) + mode.fontNameSuffix
        return isAvailable(name) ? name : nil
    }

    private static func isAvailable(_ postScriptName: String) -> Bool {
        _ = registration
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == postScriptName
    }

    private static func postScriptName(for pet: PetActivityIdentity) -> String {
        switch pet.species {
        case .dog:
            switch pet.breed ?? .shepherd {
            case .corgi: "PetIslandTimerDogCorgi"
            case .doberman: "PetIslandTimerDogDoberman"
            case .bullTerrier: "PetIslandTimerDogBullTerrier"
            default: "PetIslandTimerDogShepherd"
            }
        case .cat:
            switch pet.breed ?? .classicCat {
            case .britishShorthair: "PetIslandTimerCatBritish"
            case .maineCoon: "PetIslandTimerCatMaineCoon"
            case .siamese: "PetIslandTimerCatSiamese"
            default: "PetIslandTimerCatClassic"
            }
        case .fox:
            pet.breed == .arcticFox
                ? "PetIslandTimerFoxArctic"
                : "PetIslandTimerFoxRed"
        case .parrot:
            switch pet.breed ?? .classicParrot {
            case .cockatiel: "PetIslandTimerParrotCockatiel"
            case .budgie: "PetIslandTimerParrotBudgie"
            case .macaw: "PetIslandTimerParrotMacaw"
            default: "PetIslandTimerParrotClassic"
            }
        case .penguin:
            pet.breed == .rockhopper
                ? "PetIslandTimerPenguinRockhopper"
                : "PetIslandTimerPenguinClassic"
        case .bear:
            "PetIslandTimerBear"
        case .lizard:
            "PetIslandTimerLizard"
        case .bunny:
            "PetIslandTimerBunny"
        }
    }
}

private extension DynamicIslandMotionMode {
    var fontNameSuffix: String {
        switch self {
        case .run: "Run"
        case .walk: "Walk"
        case .sleep: "Sleep"
        case .runSleep: "RunSleep"
        case .walkSleep: "WalkSleep"
        case .runWalkSleep: "RunWalkSleep"
        }
    }
}

private struct ActivityPetTrack: View {
    let identity: PetActivityIdentity
    let snapshot: PetSnapshot
    var isStale = false
    var forceSleep = false
    let spriteSize: CGSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isSleeping: Bool {
        isLuminanceReduced || isStale || forceSleep
    }

    var body: some View {
        GeometryReader { proxy in
            let groupWidth = spriteSize.width
            let travelWidth = max(proxy.size.width - groupWidth, 0)
            let centerX = groupWidth / 2 + travelWidth * snapshot.position

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(isSleeping ? 0.07 : 0.12))
                    .frame(height: 4)
                    .offset(y: -7)

                ActivityAnimatedPet(
                    identity: identity,
                    snapshot: snapshot,
                    direction: snapshot.direction,
                    index: 0,
                    isSleeping: isSleeping
                )
                .frame(width: groupWidth, height: spriteSize.height, alignment: .bottom)
                .accessibilityHidden(true)
                .position(x: centerX, y: proxy.size.height / 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: identity.name) + Text(", pet session"))
    }
}

/// Each ActivityKit update selects one of two crisp gait frames. The Dynamic
/// Island pet intentionally runs in place; real locomotion belongs to the app.
private struct ActivityAnimatedPet: View {
    let identity: PetActivityIdentity
    let snapshot: PetSnapshot
    let direction: PetDirection
    let index: Int
    let isSleeping: Bool

    var body: some View {
        PetArtwork(
            species: identity.species,
            coat: identity.coat,
            customColor: identity.customColor,
            breed: identity.breed,
            pose: isSleeping ? .sleep : snapshot.pose,
            direction: direction,
            step: PetLiveMotionSequence.spriteStep(for: snapshot, phaseOffset: index),
            animatesMotion: false
        )
        .contentTransition(.identity)
    }
}

private func accent(for pet: PetActivityIdentity) -> Color {
    PetColors.resolve(species: pet.species, coat: pet.coat, customColor: pet.customColor).secondary
}
