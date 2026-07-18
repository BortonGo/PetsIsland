import Foundation

/// The single authoritative location of the pet. Keeping this in the shared
/// state prevents the dog from appearing in two surfaces at the same time.
enum PetPlacement: String, Codable, CaseIterable, Hashable, Sendable {
    case home
    case dynamicIsland
    case enclosure
}

/// Normalized values persisted at `PetLifeState.vitalsUpdatedAt`.
/// Consumers should use `PetLifeEngine.presentation(for:at:)` to obtain the
/// time-adjusted values instead of displaying these anchors directly.
struct PetVitals: Codable, Equatable, Hashable, Sendable {
    var fullness: Double
    var happiness: Double
    var energy: Double

    init(fullness: Double = 0.78, happiness: Double = 0.84, energy: Double = 0.88) {
        self.fullness = Self.clamp(fullness)
        self.happiness = Self.clamp(happiness)
        self.energy = Self.clamp(energy)
    }

    func projected(from anchor: Date, to date: Date) -> PetVitals {
        let elapsedHours = max(date.timeIntervalSince(anchor), 0) / 3_600
        return PetVitals(
            fullness: fullness - elapsedHours * 0.004,
            happiness: happiness - elapsedHours * 0.002,
            energy: energy - elapsedHours * 0.003
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// Durable cross-process model shared by the main app and the widget extension.
/// Versioned decoding supplies defaults for fields added by future releases.
struct PetLifeState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var profile: PetProfile
    var placement: PetPlacement
    var vitals: PetVitals
    var vitalsUpdatedAt: Date
    var autonomyEpoch: Date
    var behaviorSeed: UInt64
    var lastBallThrownAt: Date?
    var revision: Int

    init(
        profile: PetProfile,
        placement: PetPlacement = .enclosure,
        vitals: PetVitals = PetVitals(),
        vitalsUpdatedAt: Date = .now,
        autonomyEpoch: Date? = nil,
        behaviorSeed: UInt64? = nil,
        lastBallThrownAt: Date? = nil,
        revision: Int = 0
    ) {
        var dog = profile
        dog.species = .dog

        self.schemaVersion = Self.currentSchemaVersion
        self.profile = dog
        self.placement = placement
        self.vitals = vitals
        self.vitalsUpdatedAt = vitalsUpdatedAt
        self.autonomyEpoch = autonomyEpoch ?? dog.createdAt
        self.behaviorSeed = behaviorSeed ?? Self.seed(for: dog.id)
        self.lastBallThrownAt = lastBallThrownAt
        self.revision = max(revision, 0)
    }

    static func initial(at date: Date = .now) -> PetLifeState {
        let profile = PetProfile(
            id: UUID(uuidString: "7C88CA21-8244-4B46-9A14-6B59A99CE731")!,
            name: "Buddy",
            species: .dog,
            coat: .sunrise,
            createdAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        return PetLifeState(
            profile: profile,
            placement: .enclosure,
            vitalsUpdatedAt: date,
            autonomyEpoch: profile.createdAt,
            behaviorSeed: 0x5045_5449_534C_414E
        )
    }

    /// Materializes natural vital decay before applying an explicit mutation.
    /// The controller should call this before feeding or moving the pet.
    mutating func materializeVitals(at date: Date) {
        vitals = vitals.projected(from: vitalsUpdatedAt, to: date)
        vitalsUpdatedAt = date
    }

    mutating func move(to newPlacement: PetPlacement, at date: Date = .now) {
        materializeVitals(at: date)
        placement = newPlacement
        revision += 1
    }

    mutating func throwBall(at date: Date = .now) {
        materializeVitals(at: date)
        vitals = PetVitals(
            fullness: vitals.fullness,
            happiness: vitals.happiness + 0.12,
            energy: vitals.energy - 0.035
        )
        lastBallThrownAt = date
        revision += 1
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profile
        case placement
        case vitals
        case vitalsUpdatedAt
        case autonomyEpoch
        case behaviorSeed
        case lastBallThrownAt
        case revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.initial()
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        profile = try container.decodeIfPresent(PetProfile.self, forKey: .profile) ?? fallback.profile
        profile.species = .dog
        placement = try container.decodeIfPresent(PetPlacement.self, forKey: .placement) ?? .enclosure
        vitals = try container.decodeIfPresent(PetVitals.self, forKey: .vitals) ?? PetVitals()
        vitalsUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .vitalsUpdatedAt) ?? .now
        autonomyEpoch = try container.decodeIfPresent(Date.self, forKey: .autonomyEpoch) ?? profile.createdAt
        behaviorSeed = try container.decodeIfPresent(UInt64.self, forKey: .behaviorSeed)
            ?? Self.seed(for: profile.id)
        lastBallThrownAt = try container.decodeIfPresent(Date.self, forKey: .lastBallThrownAt)
        revision = max(try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0, 0)
    }

    private static func seed(for id: UUID) -> UInt64 {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return bytes.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { value, byte in
            (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }
}

enum PetLifeActivity: String, Codable, Equatable, Hashable, Sendable {
    case away
    case watching
    case patrolling
    case playing
    case resting
    case sleeping
}

struct PetLifePoint: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
}

/// Render-ready, non-persisted projection of the durable state at one instant.
struct PetLifePresentation: Equatable, Sendable {
    var pose: PetPose
    var position: Double
    var lane: Double
    var direction: PetDirection
    var spriteStep: Int
    var activity: PetLifeActivity
    var ball: PetLifePoint?
    var vitals: PetVitals
}

/// Pure deterministic behavior engine. Identical state and date always produce
/// the same result, which makes it safe for independently scheduled widgets.
enum PetLifeEngine {
    /// WidgetKit caps one data-update animation at two seconds. The enclosure
    /// therefore expresses a longer fetch scene as several precomputed 1.8 s
    /// segments. Delivery remains best-effort because WidgetKit owns timing.
    static let widgetMotionSegmentDuration: TimeInterval = 1.8
    static let widgetSpriteFrameRate: TimeInterval = 14
    static let ballReactionTimelineOffsets: [TimeInterval] = [1.8, 3.6, 5.4, 7.2, 9.0, 10.2]
    static let ballReactionDuration: TimeInterval = 10.2
    static let autonomousStepDuration: TimeInterval = 45

    static func presentation(for state: PetLifeState, at date: Date) -> PetLifePresentation {
        let vitals = state.vitals.projected(from: state.vitalsUpdatedAt, to: date)

        guard state.placement == .enclosure else {
            return PetLifePresentation(
                pose: .idle,
                position: 0.5,
                lane: 0.72,
                direction: .right,
                spriteStep: state.revision,
                activity: .away,
                ball: nil,
                vitals: vitals
            )
        }

        if let thrownAt = state.lastBallThrownAt {
            let elapsed = date.timeIntervalSince(thrownAt)
            if elapsed >= 0, elapsed < ballReactionDuration {
                return ballPresentation(
                    for: state,
                    elapsed: elapsed,
                    vitals: vitals
                )
            }
        }

        let rawTick = floor(date.timeIntervalSince(state.autonomyEpoch) / autonomousStepDuration)
        let tick = Int64(max(rawTick, 0))
        let random = mixed(state.behaviorSeed &+ UInt64(bitPattern: tick))
        let phase = Double(random & 0xffff) / Double(UInt16.max)
        let lane = 0.66 + Double((random >> 16) & 0xff) / 255 * 0.15
        let direction: PetDirection = (random & 1) == 0 ? .right : .left
        let position = direction == .right ? 0.12 + phase * 0.7 : 0.88 - phase * 0.7
        let selector = Int((random >> 32) % 12)

        let activity: PetLifeActivity
        let pose: PetPose
        if vitals.energy < 0.16 || selector == 0 {
            activity = vitals.energy < 0.16 ? .sleeping : .resting
            pose = .sleep
        } else if selector <= 2 {
            activity = .watching
            pose = .idle
        } else if selector == 3 {
            activity = .playing
            pose = .play
        } else {
            activity = .patrolling
            pose = selector.isMultiple(of: 3) ? .walk : .run
        }

        return PetLifePresentation(
            pose: pose,
            position: position,
            lane: lane,
            direction: direction,
            spriteStep: state.revision + Int(tick % 10_000),
            activity: activity,
            ball: nil,
            vitals: vitals
        )
    }

    private static func ballPresentation(
        for state: PetLifeState,
        elapsed: TimeInterval,
        vitals: PetVitals
    ) -> PetLifePresentation {
        let progress = min(max(elapsed / ballReactionDuration, 0), 1)
        // Fetch is deliberately front-loaded: the pet crosses the enclosure
        // quickly, then jumps and settles instead of gliding for seven seconds.
        let chaseEnd = 0.36
        let jumpStart = 0.30
        let jumpEnd = 0.48
        let outward = progress < jumpEnd
        let chaseProgress = min(progress / chaseEnd, 1)
        let dogX = 0.16 + 0.66 * chaseProgress
        let ballFlightEnd = 0.42
        let ballX = 0.2 + 0.68 * min(progress / ballFlightEnd, 1)
        let arc = sin(min(progress / ballFlightEnd, 1) * .pi)
        let jumpProgress = min(max((progress - jumpStart) / (jumpEnd - jumpStart), 0), 1)
        let jumpArc = progress >= jumpStart && progress <= jumpEnd
            ? sin(jumpProgress * .pi)
            : 0

        let pose: PetPose
        if progress >= jumpStart, progress <= jumpEnd {
            pose = .jump
        } else if progress < jumpStart {
            pose = .run
        } else {
            pose = .play
        }

        return PetLifePresentation(
            pose: pose,
            position: outward ? dogX : 0.82,
            lane: 0.75 - jumpArc * 0.27,
            direction: outward ? .right : .left,
            spriteStep: state.revision + Int(elapsed * widgetSpriteFrameRate),
            activity: .playing,
            ball: progress < 0.62
                ? PetLifePoint(x: ballX, y: 0.7 - arc * 0.36)
                : nil,
            vitals: vitals
        )
    }

    private static func mixed(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9e37_79b9_7f4a_7c15
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
}

enum PetLifeStoreError: Error, LocalizedError {
    case appGroupUnavailable
    case encodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The Pet Island App Group is unavailable."
        case .encodingFailed(let error):
            "The pet state could not be encoded: \(error.localizedDescription)"
        }
    }
}

/// App Group repository used by the app, WidgetKit provider, and AppIntent.
/// A last-known-good backup is kept so a partial or incompatible write never
/// resets the user's pet.
enum PetLifeStore {
    static let appGroupIdentifier = "group.org.bortongo.PetIsland"
    static let stateKey = "petLifeState.v1"

    private static let backupKey = "petLifeState.v1.backup"
    private static let lock = NSLock()

    static func load() -> PetLifeState {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    static func save(_ state: PetLifeState) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnlocked(state)
    }

    @discardableResult
    static func update(_ mutation: (inout PetLifeState) -> Void) throws -> PetLifeState {
        lock.lock()
        defer { lock.unlock() }
        var state = loadUnlocked()
        mutation(&state)
        try saveUnlocked(state)
        return state
    }

    private static func loadUnlocked() -> PetLifeState {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return .initial()
        }

        let decoder = PropertyListDecoder()
        for key in [stateKey, backupKey] {
            guard let data = defaults.data(forKey: key),
                  let state = try? decoder.decode(PetLifeState.self, from: data) else { continue }
            return state
        }
        return .initial()
    }

    private static func saveUnlocked(_ state: PetLifeState) throws {
        guard let defaults = UserDefaults(suiteName: appGroupIdentifier) else {
            throw PetLifeStoreError.appGroupUnavailable
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data: Data
        do {
            data = try encoder.encode(state)
        } catch {
            throw PetLifeStoreError.encodingFailed(error)
        }

        if let current = defaults.data(forKey: stateKey) {
            defaults.set(current, forKey: backupKey)
        }
        defaults.set(data, forKey: stateKey)
    }
}
