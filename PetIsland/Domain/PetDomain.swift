import Foundation

enum PetSpecies: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case cat
    case dog
    case fox
    case parrot
    case bear
    case penguin
    case lizard
    case bunny

    var id: String { rawValue }

    /// Species with complete original Pet Island artwork. The remaining enum
    /// cases stay decodable so older saved profiles can migrate safely.
    static let selectableCases: [PetSpecies] = [
        .cat, .dog, .fox, .parrot, .penguin
    ]

    var isSelectable: Bool { Self.selectableCases.contains(self) }
}

/// A visual variant within a species. Dog values are breeds while other
/// values describe the character design. The stored property is still named
/// `breed` to keep profiles from earlier builds Codable-compatible.
enum PetBreed: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case shepherd
    case corgi
    case doberman
    case bullTerrier

    case classicCat
    case britishShorthair
    case maineCoon
    case siamese

    case redFox
    case arcticFox

    case classicParrot
    case cockatiel
    case budgie
    case macaw

    case classicPenguin
    case rockhopper

    var id: String { rawValue }

    static func available(for species: PetSpecies) -> [PetBreed] {
        switch species {
        case .dog: [.shepherd, .corgi, .doberman, .bullTerrier]
        case .cat: [.classicCat, .britishShorthair, .maineCoon, .siamese]
        case .fox: [.redFox, .arcticFox]
        case .parrot: [.classicParrot, .cockatiel, .budgie, .macaw]
        case .penguin: [.classicPenguin, .rockhopper]
        case .bear, .lizard, .bunny: []
        }
    }

    static func defaultVariant(for species: PetSpecies) -> PetBreed? {
        available(for: species).first
    }
}

enum PetCoat: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case sunrise
    case cloud
    case midnight

    var id: String { rawValue }
}

enum PetPersonality: String, Codable, Hashable, Sendable {
    case curious
    case playful
    case calm
}

enum PetPose: String, Codable, CaseIterable, Hashable, Sendable {
    case idle
    case walk
    case run
    case jump
    case fly
    case play
    case eat
    case sleep
}

enum DynamicIslandMotionMode: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case run
    case walk
    case sleep
    case runSleep
    case walkSleep
    case runWalkSleep

    var id: String { rawValue }

    var initialPose: PetPose {
        switch self {
        case .run, .runSleep, .runWalkSleep: .run
        case .walk, .walkSleep: .walk
        case .sleep: .sleep
        }
    }

    func initialPose(for species: PetSpecies) -> PetPose {
        species == .parrot && self != .sleep ? .fly : initialPose
    }

    var includesSleep: Bool {
        switch self {
        case .sleep, .runSleep, .walkSleep, .runWalkSleep: true
        case .run, .walk: false
        }
    }
}

enum PetDirection: String, Codable, Hashable, Sendable {
    case left
    case right
}

struct PetColorSelection: Codable, Equatable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }
}

struct PetProfile: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var species: PetSpecies
    var coat: PetCoat
    var createdAt: Date
    var customColor: PetColorSelection? = nil
    /// Optional so profiles saved before breeds existed continue to decode.
    var breed: PetBreed? = nil

    var resolvedBreed: PetBreed? {
        let variants = PetBreed.available(for: species)
        guard !variants.isEmpty else { return nil }
        if let breed, variants.contains(breed) { return breed }
        return variants.first
    }

    var personality: PetPersonality {
        switch species {
        case .cat: .curious
        case .dog: .playful
        case .fox: .calm
        case .parrot: .curious
        case .bear: .calm
        case .penguin: .playful
        case .lizard: .calm
        case .bunny: .curious
        }
    }

    static let starter = PetProfile(
        id: UUID(), name: "Pixel", species: .dog, coat: .sunrise,
        createdAt: .now, breed: .shepherd
    )

    mutating func normalizeName() {
        let words = name.split(whereSeparator: \Character.isWhitespace)
        let collapsed = words.joined(separator: " ")
        name = String((collapsed.isEmpty ? "Pixel" : collapsed).prefix(16))
    }
}

struct PetSnapshot: Codable, Equatable, Hashable, Sendable {
    var pose: PetPose
    var position: Double
    var direction: PetDirection
    var revision: Int
    var generatedAt: Date

    init(
        pose: PetPose,
        position: Double,
        direction: PetDirection,
        revision: Int,
        generatedAt: Date
    ) {
        self.pose = pose
        self.position = min(max(position, 0.08), 0.92)
        self.direction = direction
        self.revision = revision
        self.generatedAt = generatedAt
    }

    static func initial(at date: Date) -> PetSnapshot {
        PetSnapshot(pose: .idle, position: 0.18, direction: .right, revision: 0, generatedAt: date)
    }
}

struct PetSession: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var petID: UUID
    var startedAt: Date
    var endsAt: Date
    var snapshot: PetSnapshot

    var duration: TimeInterval { endsAt.timeIntervalSince(startedAt) }
    func isExpired(at date: Date) -> Bool { date >= endsAt }
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(max(date.timeIntervalSince(startedAt) / duration, 0), 1)
    }
}

enum SessionPreset: Int, CaseIterable, Identifiable, Sendable {
    case short = 20
    case medium = 40
    case hour = 60
    case long = 120
    case extended = 240

    var id: Int { rawValue }
    var duration: TimeInterval { TimeInterval(rawValue * 60) }
}

struct PetHistory: Codable, Equatable, Sendable {
    var totalSeconds: TimeInterval = 0
    var completedSessions: Int = 0
    var lastSessionEndedAt: Date?

    mutating func record(_ session: PetSession, endedAt: Date) {
        let elapsed = min(max(endedAt.timeIntervalSince(session.startedAt), 0), session.duration)
        totalSeconds += elapsed
        completedSessions += 1
        lastSessionEndedAt = endedAt
    }
}

struct AppSettings: Codable, Equatable, Sendable {
    var defaultSessionMinutes: Int = 20
    var hapticsEnabled = true
    var minimizeMotion = false
    var dynamicIslandMotionMode: DynamicIslandMotionMode = .runSleep

    private enum CodingKeys: String, CodingKey {
        case defaultSessionMinutes, hapticsEnabled, minimizeMotion, dynamicIslandMotionMode
    }

    init(
        defaultSessionMinutes: Int = 20,
        hapticsEnabled: Bool = true,
        minimizeMotion: Bool = false,
        dynamicIslandMotionMode: DynamicIslandMotionMode = .runSleep
    ) {
        self.defaultSessionMinutes = defaultSessionMinutes
        self.hapticsEnabled = hapticsEnabled
        self.minimizeMotion = minimizeMotion
        self.dynamicIslandMotionMode = dynamicIslandMotionMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        defaultSessionMinutes = try values.decodeIfPresent(Int.self, forKey: .defaultSessionMinutes) ?? 20
        hapticsEnabled = try values.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        minimizeMotion = try values.decodeIfPresent(Bool.self, forKey: .minimizeMotion) ?? false
        dynamicIslandMotionMode = try values.decodeIfPresent(
            DynamicIslandMotionMode.self,
            forKey: .dynamicIslandMotionMode
        ) ?? .runSleep
    }
}

struct PersistedAppState: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    static let maximumActivePets = 3

    var schemaVersion: Int
    var pets: [PetProfile]
    /// Ordered identifiers. The first pet is the lead pet shown in compact UI.
    var activePetIDs: [UUID]
    var activeSession: PetSession?
    var history: PetHistory
    var settings: AppSettings
    var completedOnboarding: Bool

    /// Compatibility bridge for the original single-pet UI. New code should use
    /// `pets`, `activePetIDs`, and `activeParty`.
    var profile: PetProfile {
        get { activeParty.first ?? pets.first ?? .starter }
        set {
            var normalized = newValue
            normalized.normalizeName()
            if let index = pets.firstIndex(where: { $0.id == normalized.id }) {
                pets[index] = normalized
            } else {
                pets.insert(normalized, at: 0)
            }
            activePetIDs.removeAll { $0 == normalized.id }
            activePetIDs.insert(normalized.id, at: 0)
            normalizePetCollection()
        }
    }

    var activeParty: [PetProfile] {
        activePetIDs.compactMap { id in pets.first(where: { $0.id == id }) }
    }

    init() {
        let starter = PetProfile.starter
        schemaVersion = Self.schemaVersion
        pets = [starter]
        activePetIDs = [starter.id]
        activeSession = nil
        history = PetHistory()
        settings = AppSettings()
        completedOnboarding = false
    }

    mutating func normalizePetCollection() {
        var seenPetIDs = Set<UUID>()
        pets = pets.filter {
            $0.species.isSelectable && seenPetIDs.insert($0.id).inserted
        }

        if pets.isEmpty {
            pets = [.starter]
        }

        let knownPetIDs = Set(pets.map(\.id))
        var seenActiveIDs = Set<UUID>()
        activePetIDs = activePetIDs.filter {
            knownPetIDs.contains($0) && seenActiveIDs.insert($0).inserted
        }
        if activePetIDs.isEmpty, let firstPetID = pets.first?.id {
            activePetIDs = [firstPetID]
        }
        activePetIDs = Array(activePetIDs.prefix(Self.maximumActivePets))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case profile // schema v1
        case pets
        case activePetIDs
        case activeSession
        case history
        case settings
        case completedOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1

        schemaVersion = decodedVersion <= 1 ? Self.schemaVersion : decodedVersion
        activeSession = try container.decodeIfPresent(PetSession.self, forKey: .activeSession)
        history = try container.decodeIfPresent(PetHistory.self, forKey: .history) ?? PetHistory()
        settings = try container.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        completedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .completedOnboarding) ?? false

        if decodedVersion <= 1 {
            let legacyProfile = try container.decodeIfPresent(PetProfile.self, forKey: .profile) ?? .starter
            pets = [legacyProfile]
            activePetIDs = [legacyProfile.id]
        } else {
            pets = try container.decodeIfPresent([PetProfile].self, forKey: .pets) ?? []
            activePetIDs = try container.decodeIfPresent([UUID].self, forKey: .activePetIDs) ?? []
            // Be lenient with early development builds that declared v2 before
            // writing the collection fields.
            if pets.isEmpty, let legacyProfile = try container.decodeIfPresent(PetProfile.self, forKey: .profile) {
                pets = [legacyProfile]
                activePetIDs = [legacyProfile.id]
            }
        }
        normalizePetCollection()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(pets, forKey: .pets)
        try container.encode(activePetIDs, forKey: .activePetIDs)
        try container.encodeIfPresent(activeSession, forKey: .activeSession)
        try container.encode(history, forKey: .history)
        try container.encode(settings, forKey: .settings)
        try container.encode(completedOnboarding, forKey: .completedOnboarding)
    }
}

enum PetInteraction: Sendable {
    case pet
    case play
    case snack
}

struct PetBehaviorMachine: Sendable {
    static func ambientCadence(for species: PetSpecies) -> TimeInterval {
        species == .parrot ? 0.65 : 0.8
    }

    func initialSnapshot(for species: PetSpecies, at date: Date) -> PetSnapshot {
        PetSnapshot(
            pose: species == .parrot ? .fly : .idle,
            position: 0.18,
            direction: .right,
            revision: 0,
            generatedAt: date
        )
    }

    func reacting(
        to interaction: PetInteraction,
        species: PetSpecies,
        from snapshot: PetSnapshot,
        at date: Date
    ) -> PetSnapshot {
        let pose: PetPose
        switch interaction {
        case .pet: pose = .jump
        case .play: pose = species == .parrot ? .fly : .play
        case .snack: pose = .eat
        }

        let direction: PetDirection = snapshot.direction == .right ? .left : .right
        let delta = direction == .right ? 0.17 : -0.17
        return PetSnapshot(
            pose: pose,
            position: snapshot.position + delta,
            direction: direction,
            revision: snapshot.revision + 1,
            generatedAt: date
        )
    }

    func ambientSnapshot(for session: PetSession, species: PetSpecies, at date: Date) -> PetSnapshot {
        guard !session.isExpired(at: date) else {
            return PetSnapshot(
                pose: .sleep,
                position: session.snapshot.position,
                direction: session.snapshot.direction,
                revision: session.snapshot.revision,
                generatedAt: date
            )
        }

        let cadence = Self.ambientCadence(for: species)
        let tick = max(Int(date.timeIntervalSince(session.startedAt) / cadence), 0)
        let travelSteps = 6
        let period = travelSteps * 2
        let phase = tick % period
        let progress = phase <= travelSteps
            ? Double(phase) / Double(travelSteps)
            : Double(period - phase) / Double(travelSteps)
        let atBoundary = phase == 0 || phase == travelSteps
        let direction: PetDirection = phase < travelSteps ? .right : .left
        let position = 0.12 + 0.76 * progress

        let pose: PetPose
        if atBoundary {
            pose = .jump
        } else if species == .parrot {
            pose = .fly
        } else if tick.isMultiple(of: 7) {
            pose = .play
        } else if tick.isMultiple(of: 4) {
            pose = .walk
        } else {
            pose = .run
        }

        return PetSnapshot(
            pose: pose,
            position: position,
            direction: direction,
            revision: session.snapshot.revision + tick,
            generatedAt: date
        )
    }
}
