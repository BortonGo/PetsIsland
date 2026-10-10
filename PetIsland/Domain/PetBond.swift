import Foundation

/// Small, durable memories of successful actions. This never drives sprites,
/// vitals or movement, and never decreases when the app is closed.
struct PetBond: Codable, Equatable, Sendable {
    enum Moment: String, Codable, CaseIterable, Sendable { case attention, care, play }
    enum Stage: Int, CaseIterable { case meeting, familiar, trusting, inseparable }

    static let maximumPoints = 30
    private(set) var points = 0
    private(set) var lastMoments: [Moment: Date] = [:]
    private(set) var careDays: [ArcadeItemKind: Int] = [:]
    private(set) var gameDays: [MiniGameKind: Int] = [:]

    var stage: Stage {
        switch points {
        case 0..<5: .meeting
        case 5..<15: .familiar
        case 15..<30: .trusting
        default: .inseparable
        }
    }

    var stageProgress: Double {
        switch stage {
        case .meeting: Double(points) / 5
        case .familiar: Double(points - 5) / 10
        case .trusting: Double(points - 15) / 15
        case .inseparable: 1
        }
    }

    func canShare(_ moment: Moment, at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard Self.valid(date) else { return false }
        guard let previous = lastMoments[moment] else { return true }
        // A clock rollback cannot make the same moment available again.
        return date > previous && !calendar.isDate(previous, inSameDayAs: date)
    }

    @discardableResult
    mutating func shareAttention(at date: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        credit(.attention, at: date, calendar: calendar)
    }

    mutating func recordCare(_ item: ArcadeItemKind, at date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard credit(.care, at: date, calendar: calendar) else { return }
        careDays[item] = min(careDays[item, default: 0] + 1, 1_000_000)
    }

    mutating func recordGame(_ game: MiniGameKind, at date: Date, calendar: Calendar = .autoupdatingCurrent) {
        guard credit(.play, at: date, calendar: calendar) else { return }
        gameDays[game] = min(gameDays[game, default: 0] + 1, 1_000_000)
    }

    private mutating func credit(_ moment: Moment, at date: Date, calendar: Calendar) -> Bool {
        guard canShare(moment, at: date, calendar: calendar) else { return false }
        lastMoments[moment] = date
        points = min(points + 1, Self.maximumPoints)
        return true
    }

    var familiarCare: ArcadeItemKind? { Self.favorite(in: careDays) }
    var familiarGame: MiniGameKind? { Self.favorite(in: gameDays) }

    static func familiarRoute(in memories: [PetDiscoveryMemory]) -> PetWalkRoute? {
        favorite(in: Dictionary(grouping: memories, by: \.route).mapValues(\.count))
    }

    /// A preference needs repeated time together; ties remain undecided.
    private static func favorite<Key: Hashable>(in counts: [Key: Int]) -> Key? {
        guard let largest = counts.values.max(), largest >= 3 else { return nil }
        let leaders = counts.filter { $0.value == largest }
        return leaders.count == 1 ? leaders.first?.key : nil
    }

    var isValid: Bool {
        (0...Self.maximumPoints).contains(points)
            && lastMoments.values.allSatisfy(Self.valid)
            && careDays.values.allSatisfy { (1...1_000_000).contains($0) }
            && gameDays.values.allSatisfy { (1...1_000_000).contains($0) }
    }

    private static func valid(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && abs(date.timeIntervalSinceReferenceDate) < 100_000_000_000
    }

    init() {}
    private enum CodingKeys: String, CodingKey { case points, lastMoments, careDays, gameDays }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        points = try values.decode(Int.self, forKey: .points)
        lastMoments = try values.decode([Moment: Date].self, forKey: .lastMoments)
        careDays = try values.decode([ArcadeItemKind: Int].self, forKey: .careDays)
        gameDays = try values.decode([MiniGameKind: Int].self, forKey: .gameDays)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid pet bond"))
        }
    }
}
