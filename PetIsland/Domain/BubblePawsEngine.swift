import Foundation
import CoreGraphics

/// Logical coordinates keep collision, aiming and snapping identical on every screen.
enum BubbleColor: Int, CaseIterable, Sendable {
    case rose, honey, mint, sky, lilac
}

struct BubbleCell: Hashable, Comparable, Sendable {
    let row: Int
    let column: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.row, lhs.column) < (rhs.row, rhs.column)
    }
}

struct BubbleShotPlan: Equatable {
    let points: [CGPoint]
    let landing: BubbleCell?
    var length: CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }
    func point(at distance: CGFloat) -> CGPoint {
        var remaining = max(0, distance)
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = hypot(b.x - a.x, b.y - a.y)
            if remaining <= segment, segment > 0 {
                let t = remaining / segment
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            remaining -= segment
        }
        return points.last ?? BubbleBoard.launcher
    }
}

struct BubbleResolution {
    var popped: [BubbleCell: BubbleColor] = [:]
    var dropped: [BubbleCell: BubbleColor] = [:]
    var points: Int { popped.count * 20 + dropped.count * 40 }
}

struct BubbleBoard {
    static let width: CGFloat = 320
    static let height: CGFloat = 560
    static let radius: CGFloat = 20
    static let rowHeight = radius * sqrt(3)
    static let launcher = CGPoint(x: width / 2, y: 494)
    static let dangerY: CGFloat = 439
    static let maximumRows = 12
    var cells: [BubbleCell: BubbleColor]
    var ceiling: CGFloat = 0

    func columns(in row: Int) -> Int { row.isMultiple(of: 2) ? 8 : 7 }
    func isValid(_ cell: BubbleCell) -> Bool {
        cell.row >= 0 && cell.row < Self.maximumRows && cell.column >= 0 && cell.column < columns(in: cell.row)
    }
    func center(of cell: BubbleCell) -> CGPoint {
        CGPoint(x: Self.radius + CGFloat(cell.column) * Self.radius * 2
                + (cell.row.isMultiple(of: 2) ? 0 : Self.radius),
                y: ceiling + Self.radius + CGFloat(cell.row) * Self.rowHeight)
    }
    func neighbours(of cell: BubbleCell) -> [BubbleCell] {
        let diagonal = cell.row.isMultiple(of: 2) ? [-1, 0] : [0, 1]
        var result = [BubbleCell(row: cell.row, column: cell.column - 1),
                      BubbleCell(row: cell.row, column: cell.column + 1)]
        for row in [cell.row - 1, cell.row + 1] {
            result += diagonal.map { BubbleCell(row: row, column: cell.column + $0) }
        }
        return result.filter(isValid)
    }
    var colors: [BubbleColor] { Array(Set(cells.values)).sorted { $0.rawValue < $1.rawValue } }
    var crossedDangerLine: Bool { cells.keys.contains { center(of: $0).y + Self.radius >= Self.dangerY } }

    /// Exact ray/circle intersections, including wall bounces. Preview and flight use this same plan.
    func planShot(angle rawAngle: Double) -> BubbleShotPlan {
        guard rawAngle.isFinite else { return BubbleShotPlan(points: [Self.launcher], landing: nil) }
        let angle = min(max(rawAngle, -Double.pi * 0.41), Double.pi * 0.41)
        var direction = CGVector(dx: sin(angle), dy: -cos(angle))
        var origin = Self.launcher
        var points = [origin]
        for _ in 0..<16 {
            let wallX = direction.dx > 0 ? Self.width - Self.radius : Self.radius
            let wallDistance = abs(direction.dx) > 1e-8 ? (wallX - origin.x) / direction.dx : CGFloat.infinity
            let ceilingDistance = (ceiling + Self.radius - origin.y) / direction.dy
            var distance = min(wallDistance, ceilingDistance)
            var hit: BubbleCell?
            for cell in cells.keys.sorted() {
                let c = center(of: cell)
                let ox = origin.x - c.x, oy = origin.y - c.y
                let projection = ox * direction.dx + oy * direction.dy
                let discriminant = projection * projection - (ox * ox + oy * oy - pow(Self.radius * 2, 2))
                guard discriminant >= 0 else { continue }
                let entry = -projection - sqrt(discriminant)
                if entry >= -0.001 && entry < distance {
                    distance = max(entry, 0)
                    hit = cell
                }
            }
            guard distance.isFinite, distance >= 0 else { break }
            let end = CGPoint(x: origin.x + direction.dx * distance, y: origin.y + direction.dy * distance)
            points.append(end)
            if let hit {
                let candidates = neighbours(of: hit).filter {
                    cells[$0] == nil && hypot(center(of: $0).x - end.x, center(of: $0).y - end.y) <= Self.radius * 2 + 0.01
                }
                return BubbleShotPlan(points: points, landing: closest(candidates, to: end))
            }
            if ceilingDistance <= wallDistance {
                let candidates = (0..<columns(in: 0)).map { BubbleCell(row: 0, column: $0) }.filter { cells[$0] == nil }
                return BubbleShotPlan(points: points, landing: closest(candidates, to: end))
            }
            direction.dx = -direction.dx
            origin = end
        }
        return BubbleShotPlan(points: points, landing: nil)
    }

    private func closest(_ candidates: [BubbleCell], to point: CGPoint) -> BubbleCell? {
        candidates.sorted().min {
            let a = center(of: $0), b = center(of: $1)
            return hypot(a.x - point.x, a.y - point.y) < hypot(b.x - point.x, b.y - point.y)
        }
    }

    @discardableResult
    mutating func attach(_ color: BubbleColor, at cell: BubbleCell) -> BubbleResolution? {
        guard isValid(cell), cells[cell] == nil,
              cell.row == 0 || neighbours(of: cell).contains(where: { cells[$0] != nil }) else { return nil }
        cells[cell] = color
        var matching: Set<BubbleCell> = [cell]
        var pending = [cell]
        while let current = pending.popLast() {
            for neighbour in neighbours(of: current) where cells[neighbour] == color {
                if matching.insert(neighbour).inserted { pending.append(neighbour) }
            }
        }
        guard matching.count >= 3 else { return BubbleResolution() }
        var result = BubbleResolution()
        for cell in matching { result.popped[cell] = cells.removeValue(forKey: cell) }
        // Only cells connected to the ceiling survive, irrespective of their color.
        var supported = Set(cells.keys.filter { $0.row == 0 })
        pending = Array(supported)
        while let current = pending.popLast() {
            for neighbour in neighbours(of: current) where cells[neighbour] != nil {
                if supported.insert(neighbour).inserted { pending.append(neighbour) }
            }
        }
        for cell in Array(cells.keys) where !supported.contains(cell) {
            result.dropped[cell] = cells.removeValue(forKey: cell)
        }
        return result
    }
}

/// A shuffled set of silhouettes, with fresh gaps and bounded color clusters on every deal.
/// The seed makes a reported level reproducible without keeping a catalogue of fixed puzzles.
struct BubbleLevelGenerator {
    enum Layout: CaseIterable { case arch, steps, twinPeaks, valley, wave, terraces }
    struct Level {
        let board: BubbleBoard
        let layout: Layout
    }
    private var seed: UInt64
    private var layouts: [Layout] = []
    private var previousLayout: Layout?

    init(seed: UInt64) { self.seed = seed }

    mutating func random(_ upperBound: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 32) % UInt64(max(upperBound, 1)))
    }

    mutating func makeLevel(number: Int) -> Level {
        if layouts.isEmpty {
            layouts = Layout.allCases
            for i in stride(from: layouts.count - 1, through: 1, by: -1) {
                layouts.swapAt(i, random(i + 1))
            }
            if layouts.last == previousLayout { layouts.swapAt(0, layouts.count - 1) }
        }
        let layout = layouts.removeLast()
        previousLayout = layout
        let depth = 7 + min(max(number - 1, 0) / 2, 2)
        let mirrored = random(2) == 0
        let palette = Array(BubbleColor.allCases.prefix(number == 1 ? 4 : 5))
        let maximumCluster = number <= 2 ? 4 : 3
        let phase = random(3)
        var shape = Set<BubbleCell>()
        let grid = BubbleBoard(cells: [:])
        for row in 0..<depth {
            for column in 0..<grid.columns(in: row) {
                let cell = BubbleCell(row: row, column: column)
                let x = Int((grid.center(of: cell).x - 20) / 40)
                let c = mirrored ? 7 - x : x
                let inset: Int
                switch layout {
                case .arch: inset = [0, 0, 1, 3, 3, 1, 0, 0][c]
                case .steps: inset = c / 2
                case .twinPeaks: inset = [2, 0, 0, 2, 2, 0, 0, 2][c]
                case .valley: inset = [3, 2, 1, 0, 0, 1, 2, 3][c]
                case .wave: inset = [0, 1, 2, 3, 2, 1, 0, 1][(c + phase) % 8]
                case .terraces: inset = [0, 0, 2, 2, 1, 1, 3, 3][c]
                }
                guard row < depth - inset else { continue }
                // Every bubble has support above it; gaps never create floating islands.
                guard row == 0 || grid.neighbours(of: cell).contains(where: { $0.row < row && shape.contains($0) }) else { continue }
                if row > 1, row < depth - inset - 1, random(100) < 12 { continue }
                shape.insert(cell)
            }
        }

        var board = BubbleBoard(cells: [:])
        for cell in shape.sorted() {
            let neighbourColors = grid.neighbours(of: cell).compactMap { board.cells[$0] }
            var candidates = palette
            for i in stride(from: candidates.count - 1, through: 1, by: -1) {
                candidates.swapAt(i, random(i + 1))
            }
            // Small pairs reward aiming, but large pre-connected patches cannot clear the level for free.
            if !neighbourColors.isEmpty, random(100) < 65 {
                let preferred = neighbourColors[random(neighbourColors.count)]
                candidates.removeAll { $0 == preferred }
                candidates.insert(preferred, at: 0)
            }
            let color = candidates.first { color in
                var connected: Set<BubbleCell> = [cell]
                var pending = [cell]
                while let current = pending.popLast() {
                    for adjacent in grid.neighbours(of: current) where board.cells[adjacent] == color {
                        if connected.insert(adjacent).inserted { pending.append(adjacent) }
                    }
                }
                return connected.count <= maximumCluster
            }!
            board.cells[cell] = color
        }
        return Level(board: board, layout: layout)
    }
}

struct BubblePawsEngine {
    enum Phase: Equatable { case ready, playing, roundCleared, won, gameOver }
    struct Flight {
        let plan: BubbleShotPlan
        let color: BubbleColor
        var travelled: CGFloat = 0
        var position: CGPoint { plan.point(at: travelled) }
    }
    struct Effect: Identifiable {
        let id: Int
        let origin: CGPoint
        let color: BubbleColor
        let falling: Bool
        var age: TimeInterval = 0
    }
    private(set) var phase: Phase = .ready
    private(set) var board = BubbleBoard(cells: [:])
    private(set) var level = 1
    private(set) var score = 0
    private(set) var misses = 0
    private(set) var shots = 0
    private(set) var currentColor: BubbleColor = .rose
    private(set) var nextColor: BubbleColor = .honey
    private(set) var flight: Flight?
    private(set) var effects: [Effect] = []
    private(set) var aimAngle = 0.0
    private var generator: BubbleLevelGenerator
    private var effectID = 0
    static let totalLevels = 5
    var missesBeforeDescent: Int { level <= 2 ? 5 : 4 }
    var needsAnimation: Bool { flight != nil || !effects.isEmpty }
    var canShoot: Bool { phase == .playing && !needsAnimation }
    var preview: BubbleShotPlan { board.planShot(angle: aimAngle) }
    var missesRemaining: Int { missesBeforeDescent - misses }

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) { generator = BubbleLevelGenerator(seed: seed) }

    mutating func start() {
        level = 1; score = 0; shots = 0; effectID = 0
        prepareRound()
    }
    mutating func nextRound() {
        guard phase == .roundCleared else { return }
        level += 1
        prepareRound()
    }
    private mutating func prepareRound() {
        board = generator.makeLevel(number: level).board
        misses = 0; flight = nil; effects = []; aimAngle = 0
        currentColor = availableColor(); nextColor = availableColor(); phase = .playing
    }
    mutating func aim(at point: CGPoint) {
        guard canShoot, point.x.isFinite, point.y.isFinite, point.y < BubbleBoard.launcher.y - 20 else { return }
        setAim(atan2(point.x - BubbleBoard.launcher.x, BubbleBoard.launcher.y - point.y))
    }
    mutating func setAim(_ angle: Double) {
        guard canShoot, angle.isFinite else { return }
        aimAngle = min(max(angle, -Double.pi * 0.41), Double.pi * 0.41)
    }
    mutating func swapColors() {
        guard canShoot else { return }
        swap(&currentColor, &nextColor)
    }
    @discardableResult
    mutating func shoot() -> Bool {
        guard canShoot else { return false }
        flight = Flight(plan: preview, color: currentColor)
        shots += 1
        return true
    }
    mutating func update(deltaTime: TimeInterval) {
        guard phase == .playing, deltaTime.isFinite, deltaTime > 0 else { return }
        let dt = min(deltaTime, 0.05)
        for i in effects.indices { effects[i].age += dt }
        effects.removeAll { $0.age >= 0.6 }
        if var moving = flight {
            moving.travelled += CGFloat(dt) * 720
            if moving.travelled >= moving.plan.length {
                flight = nil
                resolve(moving)
            } else { flight = moving }
        }
        guard flight == nil, effects.isEmpty else { return }
        if board.cells.isEmpty { phase = level == Self.totalLevels ? .won : .roundCleared }
        else if board.crossedDangerLine { phase = .gameOver }
    }
    private mutating func resolve(_ shot: Flight) {
        guard let cell = shot.plan.landing, let result = board.attach(shot.color, at: cell) else {
            phase = .gameOver
            effects = []
            return
        }
        score += result.points
        for (cells, falling) in [(result.popped, false), (result.dropped, true)] {
            for cell in cells.keys.sorted() {
                effectID += 1
                effects.append(Effect(id: effectID, origin: board.center(of: cell), color: cells[cell]!, falling: falling))
            }
        }
        if result.popped.isEmpty {
            misses += 1
            if misses == missesBeforeDescent { board.ceiling += BubbleBoard.radius; misses = 0 }
        }
        if board.cells.isEmpty { score += 200 * level }
        // Never keep an extinct color in either slot, including after a swap.
        currentColor = board.colors.contains(nextColor) ? nextColor : availableColor()
        nextColor = availableColor()
    }
    private mutating func availableColor() -> BubbleColor {
        let colors = board.colors
        return colors.isEmpty ? .rose : colors[generator.random(colors.count)]
    }
}
