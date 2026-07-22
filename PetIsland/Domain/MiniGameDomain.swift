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

struct ArcadePayout: Equatable, Sendable {
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
        for petID in petIDs where vitalsByPetID[petID] == nil {
            vitalsByPetID[petID] = PetVitals()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, progress, vitalsByPetID
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = Self.schemaVersion
        progress = try values.decodeIfPresent(ArcadeProgress.self, forKey: .progress) ?? ArcadeProgress()
        vitalsByPetID = try values.decodeIfPresent([UUID: PetVitals].self, forKey: .vitalsByPetID) ?? [:]
    }
}

protocol ArcadeStore: Sendable {
    func load() async -> ArcadeState
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

    func load() async -> ArcadeState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? decoder.decode(ArcadeState.self, from: data) else {
            return ArcadeState()
        }
        return state
    }

    func save(_ state: ArcadeState) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
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
