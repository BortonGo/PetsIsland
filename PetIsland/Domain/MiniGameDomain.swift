import Foundation

enum MiniGameKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case skyHop
    case skyPaws
    case petsDash

    var id: String { rawValue }
}

enum ArcadeItemKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case food
    case treat
    case toy
    case vitamins

    var id: String { rawValue }
}

struct ArcadeInventory: Codable, Equatable, Sendable {
    private(set) var quantities: [ArcadeItemKind: Int] = [:]

    subscript(item: ArcadeItemKind) -> Int {
        quantities[item, default: 0]
    }

    mutating func add(_ item: ArcadeItemKind, count: Int = 1) {
        guard count > 0 else { return }
        quantities[item, default: 0] += count
    }

    @discardableResult
    mutating func remove(_ item: ArcadeItemKind, count: Int = 1) -> Bool {
        guard count > 0, quantities[item, default: 0] >= count else { return false }
        quantities[item, default: 0] -= count
        if quantities[item] == 0 { quantities[item] = nil }
        return true
    }
}

struct ArcadePayout: Codable, Equatable, Sendable {
    let score: Int
    let coinsEarned: Int
    let isNewHighScore: Bool
    let receivedDailyBonus: Bool
    let wasTired: Bool
}

struct ArcadeProgress: Codable, Equatable, Sendable {
    private(set) var coins: Int
    private(set) var totalScore: Int
    private(set) var gamesPlayed: Int
    private(set) var highScores: [MiniGameKind: Int]
    private(set) var inventory: ArcadeInventory
    private(set) var lastPlayedAt: Date?

    init(
        coins: Int = 0,
        totalScore: Int = 0,
        gamesPlayed: Int = 0,
        highScores: [MiniGameKind: Int] = [:],
        inventory: ArcadeInventory = ArcadeInventory(),
        lastPlayedAt: Date? = nil
    ) {
        self.coins = max(coins, 0)
        self.totalScore = max(totalScore, 0)
        self.gamesPlayed = max(gamesPlayed, 0)
        self.highScores = highScores.mapValues { max($0, 0) }
        self.inventory = inventory
        self.lastPlayedAt = lastPlayedAt
    }

    func highScore(for game: MiniGameKind) -> Int {
        highScores[game, default: 0]
    }

    mutating func record(
        game: MiniGameKind,
        score rawScore: Int,
        wasTired: Bool,
        at date: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ArcadePayout {
        let score = max(rawScore, 0)
        let previousHighScore = highScore(for: game)
        let isNewHighScore = score > previousHighScore
        let receivedDailyBonus = lastPlayedAt.map {
            !calendar.isDate($0, inSameDayAs: date)
        } ?? true

        let performanceCoins: Int
        if score == 0 {
            performanceCoins = 0
        } else {
            let base = max(score / ArcadeEconomy.pointsPerCoin, 1)
            performanceCoins = wasTired
                ? max(Int((Double(base) * ArcadeEconomy.tiredCoinMultiplier).rounded(.down)), 1)
                : base
        }
        let earned = min(
            performanceCoins
                + (isNewHighScore ? ArcadeEconomy.newRecordBonus : 0)
                + (receivedDailyBonus ? ArcadeEconomy.firstGameDailyBonus : 0),
            ArcadeEconomy.maximumCoinsPerRun
        )

        coins += earned
        totalScore += score
        gamesPlayed += 1
        if isNewHighScore { highScores[game] = score }
        lastPlayedAt = date

        return ArcadePayout(
            score: score,
            coinsEarned: earned,
            isNewHighScore: isNewHighScore,
            receivedDailyBonus: receivedDailyBonus,
            wasTired: wasTired
        )
    }

    @discardableResult
    mutating func purchase(_ item: ArcadeItemKind) -> Bool {
        let price = ArcadeEconomy.price(of: item)
        guard coins >= price else { return false }
        coins -= price
        inventory.add(item)
        return true
    }

    @discardableResult
    mutating func consume(_ item: ArcadeItemKind) -> Bool {
        inventory.remove(item)
    }

    private enum CodingKeys: String, CodingKey {
        case coins, totalScore, gamesPlayed, highScores, inventory, lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            coins: try values.decodeIfPresent(Int.self, forKey: .coins) ?? 0,
            totalScore: try values.decodeIfPresent(Int.self, forKey: .totalScore) ?? 0,
            gamesPlayed: try values.decodeIfPresent(Int.self, forKey: .gamesPlayed) ?? 0,
            highScores: try values.decodeIfPresent([MiniGameKind: Int].self, forKey: .highScores) ?? [:],
            inventory: try values.decodeIfPresent(ArcadeInventory.self, forKey: .inventory) ?? ArcadeInventory(),
            lastPlayedAt: try values.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        )
    }
}

struct ArcadeState: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    var schemaVersion: Int
    var progress: ArcadeProgress
    var vitalsByPetID: [UUID: PetVitals]
    var vitalsUpdatedAtByPetID: [UUID: Date] = [:]
    var pendingCareEvents: [PetCareEvent] = []
    var completedRuns: [CompletedArcadeRun] = []

    init(
        progress: ArcadeProgress = ArcadeProgress(),
        vitalsByPetID: [UUID: PetVitals] = [:]
    ) {
        schemaVersion = Self.schemaVersion
        self.progress = progress
        self.vitalsByPetID = vitalsByPetID
    }

    mutating func reconcile(with pets: [PetProfile]) {
        let petIDs = Set(pets.map(\.id))
        vitalsByPetID = vitalsByPetID.filter { petIDs.contains($0.key) }
        vitalsUpdatedAtByPetID = vitalsUpdatedAtByPetID.filter { petIDs.contains($0.key) }
        for petID in petIDs where vitalsByPetID[petID] == nil {
            vitalsByPetID[petID] = PetVitals()
        }
    }

    /// Widget actions run in another process. Merge only newer care changes,
    /// preserving inventory/coins and any more recent action inside the app.
    mutating func mergeVitals(from habitat: SharedPetHabitat) {
        for resident in habitat.residents where vitalsByPetID[resident.id] != nil {
            if resident.vitalsUpdatedAt > (vitalsUpdatedAtByPetID[resident.id] ?? .distantPast) {
                vitalsByPetID[resident.id] = resident.vitals
                vitalsUpdatedAtByPetID[resident.id] = resident.vitalsUpdatedAt
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, progress, vitalsByPetID, vitalsUpdatedAtByPetID, pendingCareEvents, completedRuns
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pendingCareEvents = try values.decodeIfPresent([PetCareEvent].self, forKey: .pendingCareEvents) ?? []
        completedRuns = try values.decodeIfPresent([CompletedArcadeRun].self, forKey: .completedRuns) ?? []
        schemaVersion = Self.schemaVersion
        progress = try values.decodeIfPresent(ArcadeProgress.self, forKey: .progress) ?? ArcadeProgress()
        vitalsByPetID = try values.decodeIfPresent([UUID: PetVitals].self, forKey: .vitalsByPetID) ?? [:]
        vitalsUpdatedAtByPetID = try values.decodeIfPresent([UUID: Date].self, forKey: .vitalsUpdatedAtByPetID) ?? [:]
    }
}

struct CompletedArcadeRun: Codable, Equatable, Sendable {
    let id: UUID
    let payout: ArcadePayout
}

protocol ArcadeStore: Sendable {
    func load() async throws -> ArcadeState
    func save(_ state: ArcadeState) async throws
}

actor FileArcadeStore: ArcadeStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base.appending(path: "PetIsland/arcade.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() async throws -> ArcadeState {
        try DurableJSON.load(ArcadeState.self, from: fileURL, decoder: decoder) ?? ArcadeState()
    }

    func save(_ state: ArcadeState) async throws {
        try DurableJSON.save(state, to: fileURL, encoder: encoder, decoder: decoder)
    }
}

actor InMemoryArcadeStore: ArcadeStore {
    private var value: ArcadeState

    init(_ value: ArcadeState = ArcadeState()) {
        self.value = value
    }

    func load() async -> ArcadeState { value }
    func save(_ state: ArcadeState) async throws { value = state }
}

enum ArcadeEconomy {
    static let pointsPerCoin = 100
    static let newRecordBonus = 5
    static let firstGameDailyBonus = 10
    static let maximumCoinsPerRun = 50
    static let tiredEnergyThreshold = 0.18
    static let tiredCoinMultiplier = 0.75

    static func price(of item: ArcadeItemKind) -> Int {
        switch item {
        case .food: 12
        case .treat: 18
        case .vitamins: 20
        case .toy: 24
        }
    }

    static func vitalsAfterPlaying(_ vitals: PetVitals) -> PetVitals {
        PetVitals(
            fullness: vitals.fullness - 0.02,
            happiness: vitals.happiness + 0.08,
            energy: vitals.energy - 0.055
        )
    }

    static func vitals(_ vitals: PetVitals, afterUsing item: ArcadeItemKind) -> PetVitals {
        switch item {
        case .food:
            PetVitals(
                fullness: vitals.fullness + 0.24,
                happiness: vitals.happiness,
                energy: vitals.energy
            )
        case .treat:
            PetVitals(
                fullness: vitals.fullness + 0.10,
                happiness: vitals.happiness + 0.14,
                energy: vitals.energy
            )
        case .toy:
            PetVitals(
                fullness: vitals.fullness,
                happiness: vitals.happiness + 0.22,
                energy: vitals.energy - 0.02
            )
        case .vitamins:
            PetVitals(
                fullness: vitals.fullness,
                happiness: vitals.happiness + 0.03,
                energy: vitals.energy + 0.25
            )
        }
    }
}
