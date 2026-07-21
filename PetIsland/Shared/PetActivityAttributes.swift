import ActivityKit
import AppIntents
import Foundation

struct PetActivityIdentity: Codable, Hashable {
    var id: UUID
    var name: String
    var species: PetSpecies
    var coat: PetCoat
    var customColor: PetColorSelection?
    var breed: PetBreed? = nil
}

struct PetActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var snapshot: PetSnapshot
        var lastInteraction: String?
    }

    var sessionID: UUID
    /// Lead pet used by compact Dynamic Island presentations.
    var pet: PetActivityIdentity
    /// Up to two additional pets used by expanded and Lock Screen layouts.
    var companions: [PetActivityIdentity] = []
    var startedAt: Date
    var endsAt: Date
    var motionMode: DynamicIslandMotionMode = .runSleep
}

enum PetLiveAction: String, AppEnum {
    case run
    case play

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Pet action")
    static var caseDisplayRepresentations: [PetLiveAction: DisplayRepresentation] = [
        .run: "Run",
        .play: "Play"
    ]

    var pose: PetPose {
        switch self {
        case .run: .run
        case .play: .play
        }
    }
}

/// Produces a short, finite ActivityKit reaction instead of relying on a timer
/// inside the widget extension. The pet stays at one horizontal position while
/// two gait frames alternate, then settles into its sleeping pose.
enum PetLiveMotionSequence {
    static let gaitFrameCount = 2
    static let runningUpdateCount = 4
    static let frameDelayNanoseconds: UInt64 = 340_000_000
    static let frameDuration: TimeInterval = 0.34
    static let backgroundRevealDelayNanoseconds: UInt64 = 150_000_000

    static func snapshots(
        from previous: PetSnapshot,
        action: PetLiveAction,
        species: PetSpecies = .dog,
        at date: Date = .now
    ) -> [PetSnapshot] {
        switch action {
        case .run:
            let movingPose: PetPose = species == .parrot ? .fly : .run
            let runningFrames = (0..<runningUpdateCount).map { index in
                PetSnapshot(
                    pose: movingPose,
                    position: previous.position,
                    direction: previous.direction,
                    revision: previous.revision + index + 1,
                    generatedAt: date.addingTimeInterval(Double(index) * frameDuration)
                )
            }
            return runningFrames + [
                PetSnapshot(
                    pose: .sleep,
                    position: previous.position,
                    direction: previous.direction,
                    revision: previous.revision + runningUpdateCount + 1,
                    generatedAt: date.addingTimeInterval(
                        Double(runningUpdateCount) * frameDuration
                    )
                )
            ]
        case .play:
            let sign = previous.direction == .right ? 1.0 : -1.0
            let offsets = [0.1, -0.04, 0]
            return interpolatedSnapshots(
                from: previous,
                positions: offsets.map { previous.position + $0 * sign },
                pose: .play,
                direction: previous.direction,
                at: date
            )
        }
    }

    /// Live Activity locomotion deliberately uses only two readable frames.
    /// The full multi-frame clips remain available to the foreground app.
    static func spriteStep(for snapshot: PetSnapshot, phaseOffset: Int = 0) -> Int {
        switch snapshot.pose {
        case .run, .fly:
            let step = (snapshot.revision + phaseOffset) % gaitFrameCount
            return step >= 0 ? step : step + gaitFrameCount
        case .idle, .walk, .jump, .play, .eat, .sleep:
            return snapshot.revision + phaseOffset
        }
    }

    private static func interpolatedSnapshots(
        from previous: PetSnapshot,
        positions: [Double],
        pose: PetPose,
        direction: PetDirection,
        at date: Date
    ) -> [PetSnapshot] {
        positions.enumerated().map { index, position in
            PetSnapshot(
                pose: pose,
                position: position,
                direction: direction,
                revision: previous.revision + index + 1,
                generatedAt: date.addingTimeInterval(Double(index) * frameDuration)
            )
        }
    }
}

/// Runs in the app process when a person presses an expanded Live Activity
/// button, so a pet can react without opening the app.
struct PetLiveActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Play with pets"
    static var description = IntentDescription("Makes the active pets run or play in Pet Island.")

    @Parameter(title: "Session")
    var sessionID: String

    @Parameter(title: "Action")
    var action: PetLiveAction

    init() {}

    init(sessionID: UUID, action: PetLiveAction) {
        self.sessionID = sessionID.uuidString
        self.action = action
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID),
              let activity = Activity<PetActivityAttributes>.activities.first(where: {
                  $0.attributes.sessionID == id
              }) else {
            return .result()
        }

        let snapshots = PetLiveMotionSequence.snapshots(
            from: activity.content.state.snapshot,
            action: action,
            species: activity.attributes.pet.species
        )
        for (index, snapshot) in snapshots.enumerated() {
            await activity.update(
                ActivityContent(
                    state: .init(
                        snapshot: snapshot,
                        lastInteraction: "\(action.rawValue)-\(index)"
                    ),
                    staleDate: activity.attributes.endsAt
                )
            )
            if index < snapshots.count - 1 {
                try? await Task.sleep(
                    nanoseconds: PetLiveMotionSequence.frameDelayNanoseconds
                )
            }
        }
        return .result()
    }
}

#if DEBUG
/// Minimal ActivityKit payload used only by automated simulator diagnostics.
/// Keeping it independent from the pet model lets us distinguish extension
/// registration failures from rendering or payload failures.
struct LiveActivitySmokeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var message: String
    }

    var endsAt: Date
}
#endif
