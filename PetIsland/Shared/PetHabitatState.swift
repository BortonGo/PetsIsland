import Foundation

/// Visual environment selected for the multi-pet Home Screen habitat.
/// Unknown values decode as `.meadow`, allowing older app versions to open a
/// state written by a newer version without discarding its residents.
enum HabitatTheme: String, CaseIterable, Hashable, Sendable, Codable {
    case meadow
    case cozyRoom
    case moonlitGarden
    case arcticCove
    case desertCamp

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try? container.decode(String.self)
        self = value.flatMap(Self.init(rawValue:)) ?? .meadow
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Versioned selection state. The Dynamic Island lead is deliberately not a
/// resident: one pet cannot be rendered in both places at the same time.
struct PetHabitatState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumResidents = 6

    var schemaVersion: Int
    var theme: HabitatTheme
    private(set) var residentPetIDs: [UUID]
    private(set) var leadDynamicIslandPetID: UUID?
    var simulationEpoch: Date
    var behaviorSeed: UInt64
    private(set) var revision: Int

    init(
        theme: HabitatTheme = .meadow,
        residentPetIDs: [UUID] = [],
        leadDynamicIslandPetID: UUID? = nil,
        simulationEpoch: Date = .now,
        behaviorSeed: UInt64 = 0x4841_4249_5441_5421,
        revision: Int = 0
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.theme = theme
        self.residentPetIDs = residentPetIDs
        self.leadDynamicIslandPetID = leadDynamicIslandPetID
        self.simulationEpoch = simulationEpoch
        self.behaviorSeed = behaviorSeed
        self.revision = max(revision, 0)
        normalize()
    }

    @discardableResult
    mutating func setTheme(_ newTheme: HabitatTheme) -> Bool {
        guard theme != newTheme else { return false }
        theme = newTheme
        revision += 1
        return true
    }

    @discardableResult
    mutating func setResidents(_ ids: [UUID]) -> Bool {
        let previous = residentPetIDs
        residentPetIDs = ids
        normalize()
        guard residentPetIDs != previous else { return false }
        revision += 1
        return true
    }

    @discardableResult
    mutating func addResident(_ id: UUID) -> Bool {
        guard id != leadDynamicIslandPetID,
              !residentPetIDs.contains(id),
              residentPetIDs.count < Self.maximumResidents else { return false }
        residentPetIDs.append(id)
        revision += 1
        return true
    }

    @discardableResult
    mutating func removeResident(_ id: UUID) -> Bool {
        guard let index = residentPetIDs.firstIndex(of: id) else { return false }
        residentPetIDs.remove(at: index)
        revision += 1
        return true
    }

    /// Promotes a pet to Dynamic Island and removes it from the enclosure.
    @discardableResult
    mutating func setDynamicIslandLead(_ id: UUID?) -> Bool {
        let previousLead = leadDynamicIslandPetID
        let previousResidents = residentPetIDs
        leadDynamicIslandPetID = id
        if let id {
            residentPetIDs.removeAll { $0 == id }
        }
        guard previousLead != leadDynamicIslandPetID || previousResidents != residentPetIDs else {
            return false
        }
        revision += 1
        return true
    }

    /// Returns the current Dynamic Island pet to the habitat when a slot is
    /// available. The lead remains assigned if the habitat is full.
    @discardableResult
    mutating func returnDynamicIslandLeadToHabitat() -> Bool {
        guard let leadDynamicIslandPetID,
              residentPetIDs.count < Self.maximumResidents else { return false }
        self.leadDynamicIslandPetID = nil
        residentPetIDs.append(leadDynamicIslandPetID)
        revision += 1
        return true
    }

    /// Removes references to deleted profiles while preserving resident order.
    mutating func reconcile(availablePetIDs: Set<UUID>) {
        let previousResidents = residentPetIDs
        let previousLead = leadDynamicIslandPetID
        residentPetIDs.removeAll { !availablePetIDs.contains($0) }
        if let leadDynamicIslandPetID, !availablePetIDs.contains(leadDynamicIslandPetID) {
            self.leadDynamicIslandPetID = nil
        }
        normalize()
        if residentPetIDs != previousResidents || leadDynamicIslandPetID != previousLead {
            revision += 1
        }
    }

    private mutating func normalize() {
        var seen = Set<UUID>()
        residentPetIDs = residentPetIDs.filter { id in
            id != leadDynamicIslandPetID && seen.insert(id).inserted
        }
        residentPetIDs = Array(residentPetIDs.prefix(Self.maximumResidents))
        revision = max(revision, 0)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case theme
        case residentPetIDs
        case leadDynamicIslandPetID
        case simulationEpoch
        case behaviorSeed
        case revision
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Self.currentSchemaVersion
        theme = try container.decodeIfPresent(HabitatTheme.self, forKey: .theme) ?? .meadow
        residentPetIDs = try container.decodeIfPresent([UUID].self, forKey: .residentPetIDs) ?? []
        leadDynamicIslandPetID = try container.decodeIfPresent(UUID.self, forKey: .leadDynamicIslandPetID)
        simulationEpoch = try container.decodeIfPresent(Date.self, forKey: .simulationEpoch) ?? .now
        behaviorSeed = try container.decodeIfPresent(UInt64.self, forKey: .behaviorSeed)
            ?? 0x4841_4249_5441_5421
        revision = try container.decodeIfPresent(Int.self, forKey: .revision) ?? 0
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(theme, forKey: .theme)
        try container.encode(residentPetIDs, forKey: .residentPetIDs)
        try container.encodeIfPresent(leadDynamicIslandPetID, forKey: .leadDynamicIslandPetID)
        try container.encode(simulationEpoch, forKey: .simulationEpoch)
        try container.encode(behaviorSeed, forKey: .behaviorSeed)
        try container.encode(revision, forKey: .revision)
    }
}

enum HabitatPetStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case watching
    case wandering
    case running
    case flying
    case playing
    case resting
    case sleeping
}

/// Render-ready projection expressed entirely in normalized habitat coordinates.
struct HabitatPetProjection: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID { petID }
    let petID: UUID
    let position: Double
    let verticalPosition: Double
    let lane: Int
    let direction: PetDirection
    let pose: PetPose
    let status: HabitatPetStatus
    let spriteStep: Int
    let depth: Int
}

/// Native deterministic state machine for the enclosure. It follows the same
/// broad rhythm as desktop-pet engines (pause, travel, play, return, sleep),
/// while keeping all scheduling and collision rules explicit in Swift.
enum PetHabitatEngine {
    static let cycleLength = 32
    static let minimumHorizontalSeparation = 0.22
    static let minimumVerticalSeparation = 0.14

    static func projections(
        for state: PetHabitatState,
        pets: [PetProfile],
        at date: Date
    ) -> [HabitatPetProjection] {
        let profilesByID = pets.reduce(into: [UUID: PetProfile]()) { result, profile in
            if result[profile.id] == nil {
                result[profile.id] = profile
            }
        }
        let residents = state.residentPetIDs.compactMap { profilesByID[$0] }
        guard !residents.isEmpty else { return [] }

        let laneCount = min(3, residents.count)
        var laneOccupancies = Array(repeating: 0, count: laneCount)
        for index in residents.indices {
            laneOccupancies[index % laneCount] += 1
        }

        return residents.enumerated().map { index, profile in
            let lane = index % laneCount
            let slot = index / laneCount
            let track = horizontalTrack(slot: slot, occupancy: laneOccupancies[lane])
            let frame = stateFrame(
                for: profile,
                state: state,
                date: date,
                residentIndex: index,
                track: track
            )
            return HabitatPetProjection(
                petID: profile.id,
                position: frame.position,
                verticalPosition: verticalPosition(lane: lane, laneCount: laneCount),
                lane: lane,
                direction: frame.direction,
                pose: frame.pose,
                status: frame.status,
                spriteStep: frame.spriteStep,
                depth: lane
            )
        }
    }

    private struct StateFrame {
        let position: Double
        let direction: PetDirection
        let pose: PetPose
        let status: HabitatPetStatus
        let spriteStep: Int
    }

    private static func stateFrame(
        for profile: PetProfile,
        state: PetHabitatState,
        date: Date,
        residentIndex: Int,
        track: ClosedRange<Double>
    ) -> StateFrame {
        let cadence = cadence(for: profile.species)
        let elapsedSteps = max(date.timeIntervalSince(state.simulationEpoch), 0) / cadence
        let tick = Int64(floor(elapsedSteps))
        let fraction = elapsedSteps - floor(elapsedSteps)
        let petSeed = mixed(
            state.behaviorSeed
                ^ seed(for: profile.id)
                ^ UInt64(residentIndex) &* 0x9e37_79b9_7f4a_7c15
        )
        let offset = Int64(petSeed % UInt64(cycleLength))
        let rawPhase = (tick + offset) % Int64(cycleLength)
        let phase = Int(rawPhase >= 0 ? rawPhase : rawPhase + Int64(cycleLength))
        let mirrored = ((petSeed >> 8) & 1) == 1

        var direction: PetDirection
        var normalizedPosition: Double
        let status: HabitatPetStatus

        switch phase {
        case 0...2:
            normalizedPosition = 0
            direction = .right
            status = .watching
        case 3...7:
            normalizedPosition = (Double(phase - 3) + fraction) / 8
            direction = .right
            status = profile.species == .parrot ? .flying : .wandering
        case 8...10:
            normalizedPosition = (Double(phase - 3) + fraction) / 8
            direction = .right
            status = profile.species == .parrot ? .flying : .running
        case 11...13:
            normalizedPosition = 1
            direction = .left
            status = .playing
        case 14...16:
            normalizedPosition = 1
            direction = .left
            status = .watching
        case 17...19:
            normalizedPosition = 1 - (Double(phase - 17) + fraction) / 8
            direction = .left
            status = profile.species == .parrot ? .flying : .running
        case 20...24:
            normalizedPosition = 1 - (Double(phase - 17) + fraction) / 8
            direction = .left
            status = profile.species == .parrot ? .flying : .wandering
        case 25...27:
            normalizedPosition = 0
            direction = .right
            status = .resting
        default:
            normalizedPosition = 0
            direction = .right
            status = .sleeping
        }

        normalizedPosition = min(max(normalizedPosition, 0), 1)
        if mirrored {
            normalizedPosition = 1 - normalizedPosition
            direction = opposite(direction)
        }
        let position = track.lowerBound + normalizedPosition * (track.upperBound - track.lowerBound)

        return StateFrame(
            position: position,
            direction: direction,
            pose: pose(for: status, species: profile.species),
            status: status,
            spriteStep: state.revision + Int(tick % 100_000)
        )
    }

    private static func horizontalTrack(slot: Int, occupancy: Int) -> ClosedRange<Double> {
        guard occupancy > 1 else { return 0.08...0.92 }
        return slot == 0 ? 0.08...0.38 : 0.62...0.92
    }

    private static func verticalPosition(lane: Int, laneCount: Int) -> Double {
        switch laneCount {
        case 1: 0.76
        case 2: lane == 0 ? 0.64 : 0.82
        default: [0.56, 0.72, 0.86][min(max(lane, 0), 2)]
        }
    }

    private static func pose(for status: HabitatPetStatus, species: PetSpecies) -> PetPose {
        switch status {
        case .watching: .idle
        case .wandering: .walk
        case .running: .run
        case .flying: .fly
        case .playing: .play
        case .resting: .idle
        case .sleeping: .sleep
        }
    }

    private static func cadence(for species: PetSpecies) -> TimeInterval {
        switch species {
        case .parrot: 1.8
        case .dog, .fox: 2.5
        case .cat, .penguin: 2.8
        }
    }

    private static func opposite(_ direction: PetDirection) -> PetDirection {
        direction == .right ? .left : .right
    }

    private static func seed(for id: UUID) -> UInt64 {
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { value, byte in
                (value ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
            }
        }
    }

    private static func mixed(_ input: UInt64) -> UInt64 {
        var value = input &+ 0x9e37_79b9_7f4a_7c15
        value = (value ^ (value >> 30)) &* 0xbf58_476d_1ce4_e5b9
        value = (value ^ (value >> 27)) &* 0x94d0_49bb_1331_11eb
        return value ^ (value >> 31)
    }
}

/// A resident snapshot copied into the App Group so WidgetKit never needs to
/// read the main application's private document store.
struct SharedHabitatResident: Codable, Equatable, Sendable, Identifiable {
    var id: UUID { profile.id }
    var profile: PetProfile
    var vitals: PetVitals
}

/// Complete cross-process payload used by the app and the enclosure widget.
/// The selection model keeps stable IDs while this payload carries the small
/// amount of render data the extension needs for an offline timeline.
struct SharedPetHabitat: Codable, Equatable, Sendable {
    var configuration: PetHabitatState
    var residents: [SharedHabitatResident]

    static func initial(at date: Date = .now) -> SharedPetHabitat {
        let dog = PetLifeState.initial(at: date).profile
        return SharedPetHabitat(
            configuration: PetHabitatState(
                theme: .meadow,
                residentPetIDs: [dog.id],
                simulationEpoch: dog.createdAt
            ),
            residents: [SharedHabitatResident(profile: dog, vitals: PetVitals())]
        )
    }

    mutating func reconcile() {
        var seen = Set<UUID>()
        residents = residents.filter { seen.insert($0.id).inserted }
        configuration.reconcile(availablePetIDs: Set(residents.map(\.id)))
        let selected = Set(configuration.residentPetIDs)
        residents = residents.filter { selected.contains($0.id) }
    }
}

enum PetHabitatStoreError: Error, LocalizedError {
    case appGroupUnavailable
    case encodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "The Pet Island App Group is unavailable."
        case .encodingFailed(let error):
            "The enclosure could not be encoded: \(error.localizedDescription)"
        }
    }
}

/// App Group repository shared by the main app, WidgetKit and AppIntents.
enum PetHabitatStore {
    static let stateKey = "petHabitatState.v1"
    private static let backupKey = "petHabitatState.v1.backup"
    private static let lock = NSLock()

    static func load() -> SharedPetHabitat {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    static func save(_ habitat: SharedPetHabitat) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnlocked(habitat)
    }

    @discardableResult
    static func update(_ mutation: (inout SharedPetHabitat) -> Void) throws -> SharedPetHabitat {
        lock.lock()
        defer { lock.unlock() }
        var habitat = loadUnlocked()
        mutation(&habitat)
        habitat.reconcile()
        try saveUnlocked(habitat)
        return habitat
    }

    private static func loadUnlocked() -> SharedPetHabitat {
        guard let defaults = UserDefaults(suiteName: PetLifeStore.appGroupIdentifier) else {
            return .initial()
        }
        let decoder = PropertyListDecoder()
        for key in [stateKey, backupKey] {
            guard let data = defaults.data(forKey: key),
                  var habitat = try? decoder.decode(SharedPetHabitat.self, from: data) else { continue }
            habitat.reconcile()
            return habitat
        }
        return .initial()
    }

    private static func saveUnlocked(_ habitat: SharedPetHabitat) throws {
        guard let defaults = UserDefaults(suiteName: PetLifeStore.appGroupIdentifier) else {
            throw PetHabitatStoreError.appGroupUnavailable
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data: Data
        do {
            data = try encoder.encode(habitat)
        } catch {
            throw PetHabitatStoreError.encodingFailed(error)
        }
        if let current = defaults.data(forKey: stateKey) {
            defaults.set(current, forKey: backupKey)
        }
        defaults.set(data, forKey: stateKey)
    }
}
