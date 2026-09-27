import Foundation

enum PetWalkRoute: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case garden
    case shore
    case grove

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .garden: 20 * 60
        case .shore: 40 * 60
        case .grove: 60 * 60
        }
    }

    var discoveryIDs: [PetDiscoveryKind] {
        switch self {
        case .garden: [.stripedPebble, .clover, .tinyFlower, .ribbon]
        case .shore: [.shell, .seaGlass, .driftwood, .smoothStone]
        case .grove: [.feather, .pinecone, .acorn, .mapleLeaf]
        }
    }
}

enum PetDiscoveryKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case stripedPebble
    case clover
    case tinyFlower
    case ribbon
    case shell
    case seaGlass
    case driftwood
    case smoothStone
    case feather
    case pinecone
    case acorn
    case mapleLeaf

    var id: String { rawValue }
}

/// A walk is independent of the animation and Live Activity session. Keeping
/// the companion as a value also preserves memories after a rename or removal.
struct PetDiscoveryWalk: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let pet: PetProfile
    let route: PetWalkRoute
    let startedAt: Date
    let endsAt: Date
    let discovery: PetDiscoveryKind

    init?(
        id: UUID = UUID(),
        pet: PetProfile,
        route: PetWalkRoute,
        startedAt: Date,
        endsAt: Date,
        discovery: PetDiscoveryKind
    ) {
        guard startedAt.timeIntervalSinceReferenceDate.isFinite,
              endsAt.timeIntervalSinceReferenceDate.isFinite,
              endsAt > startedAt,
              endsAt.timeIntervalSince(startedAt).isFinite,
              route.discoveryIDs.contains(discovery) else { return nil }
        self.id = id
        self.pet = pet
        self.route = route
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.discovery = discovery
    }

    func isReady(at date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && date >= endsAt
    }

    func progress(at date: Date) -> Double {
        guard date.timeIntervalSinceReferenceDate.isFinite, date > startedAt else { return 0 }
        if date >= endsAt { return 1 }
        return date.timeIntervalSince(startedAt) / endsAt.timeIntervalSince(startedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, pet, route, startedAt, endsAt, discovery
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let id = try values.decode(UUID.self, forKey: .id)
        let pet = try values.decode(PetProfile.self, forKey: .pet)
        let route = try values.decode(PetWalkRoute.self, forKey: .route)
        let startedAt = try values.decode(Date.self, forKey: .startedAt)
        let endsAt = try values.decode(Date.self, forKey: .endsAt)
        let discovery = try values.decode(PetDiscoveryKind.self, forKey: .discovery)
        guard let walk = Self(id: id, pet: pet, route: route, startedAt: startedAt,
                              endsAt: endsAt, discovery: discovery) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid discovery walk"))
        }
        self = walk
    }
}

struct PetDiscoveryMemory: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let pet: PetProfile
    let route: PetWalkRoute
    let discovery: PetDiscoveryKind
    /// The planned return, so opening the app later never changes the memory.
    let foundAt: Date

    init(walk: PetDiscoveryWalk) {
        id = walk.id
        pet = walk.pet
        route = walk.route
        discovery = walk.discovery
        foundAt = walk.endsAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, pet, route, discovery, foundAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        pet = try values.decode(PetProfile.self, forKey: .pet)
        route = try values.decode(PetWalkRoute.self, forKey: .route)
        discovery = try values.decode(PetDiscoveryKind.self, forKey: .discovery)
        foundAt = try values.decode(Date.self, forKey: .foundAt)
        guard foundAt.timeIntervalSinceReferenceDate.isFinite,
              route.discoveryIDs.contains(discovery) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid discovery memory"))
        }
    }
}

struct PetDiscoveriesState: Codable, Equatable, Sendable {
    private(set) var activeWalk: PetDiscoveryWalk?
    private(set) var memories: [PetDiscoveryMemory]

    init(activeWalk: PetDiscoveryWalk? = nil, memories: [PetDiscoveryMemory] = []) {
        self.activeWalk = activeWalk
        self.memories = memories
    }

    var discoveredKinds: Set<PetDiscoveryKind> { Set(memories.map(\.discovery)) }

    @discardableResult
    mutating func startWalk(pet: PetProfile, route: PetWalkRoute, at date: Date) -> Bool {
        guard activeWalk == nil, date.timeIntervalSinceReferenceDate.isFinite else { return false }
        let options = route.discoveryIDs
        let completedOnRoute = memories.filter { $0.route == route }.count
        let discovered = discoveredKinds
        let discovery = options.first { !discovered.contains($0) }
            ?? options[completedOnRoute % options.count]
        guard let walk = PetDiscoveryWalk(pet: pet, route: route, startedAt: date,
                                          endsAt: date.addingTimeInterval(route.duration),
                                          discovery: discovery) else { return false }
        activeWalk = walk
        return true
    }

    /// A ready walk stays available indefinitely; backgrounding and missed days
    /// do not expire it. Clearing it here makes repeated collection taps harmless.
    @discardableResult
    mutating func collectWalk(at date: Date) -> PetDiscoveryMemory? {
        guard let walk = activeWalk, walk.isReady(at: date),
              !memories.contains(where: { $0.id == walk.id }) else { return nil }
        let memory = PetDiscoveryMemory(walk: walk)
        memories.append(memory)
        activeWalk = nil
        return memory
    }

    @discardableResult
    mutating func cancelWalk() -> Bool {
        guard activeWalk != nil else { return false }
        activeWalk = nil
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case activeWalk, memories
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        activeWalk = try values.decodeIfPresent(PetDiscoveryWalk.self, forKey: .activeWalk)
        memories = try values.decodeIfPresent([PetDiscoveryMemory].self, forKey: .memories) ?? []
        let memoryIDs = Set(memories.map(\.id))
        guard memoryIDs.count == memories.count,
              activeWalk.map({ !memoryIDs.contains($0.id) }) ?? true else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Duplicate discovery walk identifier"))
        }
    }
}
