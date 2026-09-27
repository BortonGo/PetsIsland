import XCTest
@testable import PetIsland

final class BubblePawsTests: XCTestCase {
    func testHexNeighboursAreSymmetricAndNeverWrapAtEdges() {
        let board = BubbleBoard(cells: [:])
        XCTAssertEqual(board.neighbours(of: cell(4, 3)).count, 6)
        XCTAssertEqual(board.neighbours(of: cell(0, 0)).count, 2)
        for row in 0..<BubbleBoard.maximumRows {
            for column in 0..<board.columns(in: row) {
                let origin = cell(row, column)
                for next in board.neighbours(of: origin) {
                    XCTAssertTrue(board.isValid(next))
                    XCTAssertTrue(board.neighbours(of: next).contains(origin))
                    let a = board.center(of: origin), b = board.center(of: next)
                    XCTAssertEqual(hypot(a.x - b.x, a.y - b.y), 40, accuracy: 0.001)
                }
            }
        }
    }

    func testTwoConnectedBubblesStickWithoutPopping() throws {
        var board = BubbleBoard(cells: [cell(0, 2): .rose])
        let result = try XCTUnwrap(board.attach(.rose, at: cell(1, 2)))
        XCTAssertEqual(board.cells.count, 2)
        XCTAssertEqual(result.points, 0)
    }

    func testMatchingSupportDropsHangingBubblesOfOtherColors() throws {
        var board = BubbleBoard(cells: [cell(0, 2): .rose, cell(0, 3): .rose,
                                      cell(1, 2): .mint, cell(2, 2): .honey])
        let result = try XCTUnwrap(board.attach(.rose, at: cell(0, 1)))
        XCTAssertEqual(result.popped.count, 3)
        XCTAssertEqual(result.dropped.count, 2)
        XCTAssertEqual(result.points, 140)
        XCTAssertTrue(board.cells.isEmpty)
    }

    func testDisconnectedSameColorAtCeilingIsNotPartOfMatch() throws {
        var board = BubbleBoard(cells: [cell(0, 0): .rose, cell(0, 1): .rose,
                                      cell(0, 6): .rose, cell(1, 6): .mint])
        let result = try XCTUnwrap(board.attach(.rose, at: cell(1, 0)))
        XCTAssertEqual(result.popped.count, 3)
        XCTAssertEqual(board.cells, [cell(0, 6): .rose, cell(1, 6): .mint])
    }

    func testIllegalAttachmentDoesNotOverwriteOrCreateFloatingBubble() {
        var board = BubbleBoard(cells: [cell(0, 0): .mint])
        let before = board.cells
        XCTAssertNil(board.attach(.rose, at: cell(0, 0)))
        XCTAssertNil(board.attach(.rose, at: cell(5, 3)))
        XCTAssertNil(board.attach(.rose, at: cell(1, 7)))
        XCTAssertNil(board.attach(.rose, at: cell(-1, 0)))
        XCTAssertEqual(board.cells, before)
    }

    func testRayStopsAtFirstBubbleAndSnapsInFront() throws {
        let board = BubbleBoard(cells: [cell(0, 3): .rose, cell(1, 3): .mint, cell(2, 3): .honey])
        let plan = board.planShot(angle: 0)
        let landing = try XCTUnwrap(plan.landing)
        XCTAssertEqual(landing, cell(3, 3))
        XCTAssertEqual(plan.points.count, 2)
        XCTAssertGreaterThan(try XCTUnwrap(plan.points.last).y, board.center(of: cell(2, 3)).y)
        XCTAssertNil(board.cells[landing])
    }

    func testBankShotReflectsInsideWallsAndReachesCeiling() throws {
        let board = BubbleBoard(cells: [:])
        for angle in [-1.2, 1.2] {
            let plan = board.planShot(angle: angle)
            XCTAssertGreaterThan(plan.points.count, 2)
            XCTAssertEqual(try XCTUnwrap(plan.landing).row, 0)
            for point in plan.points {
                XCTAssertGreaterThanOrEqual(point.x, 20 - 0.001)
                XCTAssertLessThanOrEqual(point.x, 300 + 0.001)
            }
            XCTAssertEqual(try XCTUnwrap(plan.points.last).y, 20, accuracy: 0.001)
            XCTAssertEqual(plan.point(at: plan.length + 100), plan.points.last)
        }
    }

    func testDangerBoundaryAndInvalidRayAreHandled() {
        var board = BubbleBoard(cells: [cell(11, 0): .rose])
        XCTAssertFalse(board.crossedDangerLine)
        board.ceiling = 20
        XCTAssertTrue(board.crossedDangerLine)
        XCTAssertNil(board.planShot(angle: .nan).landing)
        XCTAssertEqual(board.planShot(angle: .infinity).points, [BubbleBoard.launcher])
    }

    func testShotCannotBeOverlappedSwappedOrRedirectedInFlight() {
        var engine = BubblePawsEngine(seed: 7)
        XCTAssertFalse(engine.shoot())
        engine.start(); engine.setAim(0.2)
        let current = engine.currentColor, next = engine.nextColor
        XCTAssertTrue(engine.shoot())
        let flight = engine.flight?.plan
        XCTAssertFalse(engine.shoot())
        engine.swapColors(); engine.setAim(-0.8)
        XCTAssertEqual(engine.currentColor, current)
        XCTAssertEqual(engine.nextColor, next)
        XCTAssertEqual(engine.flight?.plan, flight)
        XCTAssertEqual(engine.aimAngle, 0.2)
        XCTAssertEqual(engine.shots, 1)
    }

    func testSameShotHasSameOutcomeAt30_60_120Hz() {
        var results: [BubblePawsEngine] = []
        for fps in [30, 60, 120] {
            var engine = BubblePawsEngine(seed: 104)
            engine.start(); engine.setAim(0.45); engine.shoot()
            for _ in 0..<(fps * 5) { engine.update(deltaTime: 1 / Double(fps)) }
            results.append(engine)
        }
        for engine in results.dropFirst() {
            XCTAssertEqual(engine.board.cells, results[0].board.cells)
            XCTAssertEqual(engine.board.ceiling, results[0].board.ceiling)
            XCTAssertEqual(engine.score, results[0].score)
            XCTAssertEqual(engine.phase, results[0].phase)
            XCTAssertFalse(engine.needsAnimation)
        }
    }

    func testFiveNonMatchingShotsLowerCeilingExactlyOnce() throws {
        var engine = BubblePawsEngine(seed: 37)
        engine.start()
        for _ in 0..<5 {
            let angle = try XCTUnwrap((-72...72).map { Double($0) * .pi / 180 }.first { angle in
                let plan = engine.board.planShot(angle: angle)
                guard let landing = plan.landing else { return false }
                var board = engine.board
                return board.attach(engine.currentColor, at: landing)?.popped.isEmpty == true
            })
            engine.setAim(angle); engine.shoot(); settle(&engine)
        }
        XCTAssertEqual(engine.board.ceiling, 20)
        XCTAssertEqual(engine.missesRemaining, 5)
        XCTAssertEqual(engine.score, 0)
    }

    func testInvalidTimeAndAimDoNotChangeFlight() {
        var engine = BubblePawsEngine(seed: 9)
        engine.start(); engine.setAim(.nan); engine.aim(at: CGPoint(x: 30, y: 550))
        XCTAssertEqual(engine.aimAngle, 0)
        engine.shoot()
        for dt in [Double.nan, .infinity, -10, 0] { engine.update(deltaTime: dt) }
        XCTAssertEqual(engine.flight?.travelled, 0)
        engine.update(deltaTime: 3600)
        XCTAssertEqual(engine.flight?.travelled, 36)
    }

    func testGeneratedLevelsAreSupportedVariedAndHaveSmallColorGroups() {
        var fingerprints = Set<String>()
        for seed in UInt64(1)...80 {
            var generator = BubbleLevelGenerator(seed: seed)
            for level in 1...5 {
                let board = generator.makeLevel(number: level).board
                XCTAssertFalse(board.crossedDangerLine)
                XCTAssertTrue(board.cells.keys.allSatisfy(board.isValid))
                XCTAssertGreaterThanOrEqual(board.cells.count, 25)
                XCTAssertLessThanOrEqual(board.cells.count, 68)
                XCTAssertEqual(board.colors.count, level == 1 ? 4 : 5)
                var supported = Set(board.cells.keys.filter { $0.row == 0 })
                var pending = Array(supported)
                while let cell = pending.popLast() {
                    for next in board.neighbours(of: cell) where board.cells[next] != nil {
                        if supported.insert(next).inserted { pending.append(next) }
                    }
                }
                XCTAssertEqual(supported.count, board.cells.count, "No initial floating bubbles")
                var unvisited = Set(board.cells.keys)
                while let first = unvisited.first {
                    unvisited.remove(first)
                    var cluster = [first], count = 0
                    while let cell = cluster.popLast() {
                        count += 1
                        for next in board.neighbours(of: cell) where board.cells[next] == board.cells[cell] {
                            if unvisited.remove(next) != nil { cluster.append(next) }
                        }
                    }
                    XCTAssertLessThanOrEqual(count, level <= 2 ? 4 : 3)
                }
                let fingerprint = board.cells.keys.sorted().map {
                    "\($0.row),\($0.column):\(board.cells[$0]!.rawValue)"
                }.joined(separator: ";")
                XCTAssertTrue(fingerprints.insert(fingerprint).inserted, "Duplicate generated board")
                XCTAssertTrue((-70...70).contains { board.planShot(angle: Double($0) * .pi / 180).landing != nil })
            }
        }
        XCTAssertEqual(fingerprints.count, 400)
    }

    func testLayoutShuffleDoesNotRepeatUntilAllSixShapesAreUsed() {
        var generator = BubbleLevelGenerator(seed: 91)
        var previous: BubbleLevelGenerator.Layout?
        for _ in 0..<10 {
            var layouts: [BubbleLevelGenerator.Layout] = []
            for _ in 0..<6 {
                let level = generator.makeLevel(number: 3)
                XCTAssertNotEqual(level.layout, previous)
                XCTAssertFalse(layouts.contains(level.layout))
                layouts.append(level.layout)
                previous = level.layout
            }
        }
    }

    func testSeedReproducesLevelsButRestartDealsAnotherBoard() {
        var first = BubblePawsEngine(seed: 8), second = BubblePawsEngine(seed: 8)
        first.start(); second.start()
        XCTAssertEqual(first.board.cells, second.board.cells)
        let initial = first.board.cells
        first.start(); second.start()
        XCTAssertNotEqual(first.board.cells, initial)
        XCTAssertEqual(first.board.cells, second.board.cells)
        XCTAssertEqual(first.currentColor, second.currentColor)
        XCTAssertEqual(first.nextColor, second.nextColor)
    }

    func testMatchingShotDoesNotEraseAccumulatedMisses() throws {
        var engine = BubblePawsEngine(seed: 37)
        engine.start()
        for wantsMatch in [false, true] {
            var choice: (Double, Bool)?
            for swap in [false, true] {
                let color = swap ? engine.nextColor : engine.currentColor
                for degrees in -72...72 {
                    let angle = Double(degrees) * .pi / 180
                    guard let landing = engine.board.planShot(angle: angle).landing else { continue }
                    var board = engine.board
                    guard let result = board.attach(color, at: landing), !result.popped.isEmpty == wantsMatch else { continue }
                    choice = (angle, swap); break
                }
                if choice != nil { break }
            }
            let shot = try XCTUnwrap(choice)
            if shot.1 { engine.swapColors() }
            engine.setAim(shot.0); engine.shoot(); settle(&engine)
            XCTAssertEqual(engine.misses, 1)
            XCTAssertEqual(engine.missesRemaining, 4)
        }
        XCTAssertGreaterThan(engine.score, 0)
    }

    func testFullRunsKeepLegalCellsAvailableColorsAndFinishWithoutTimers() {
        var wins = 0
        for seed in UInt64(1)...8 {
            var engine = BubblePawsEngine(seed: seed)
            engine.start()
            for _ in 0..<300 {
                if engine.phase == .roundCleared { engine.nextRound() }
                guard engine.phase == .playing else { break }
                var best: (points: Int, angle: Double, swap: Bool)?
                for swap in [false, true] {
                    let color = swap ? engine.nextColor : engine.currentColor
                    for degrees in stride(from: -72, through: 72, by: 3) {
                        let angle = Double(degrees) * .pi / 180
                        guard let landing = engine.board.planShot(angle: angle).landing else { continue }
                        var candidate = engine.board
                        guard let resolution = candidate.attach(color, at: landing) else { continue }
                        // Build a matching pair when no immediate pop is available.
                        let matchingNeighbours = engine.board.neighbours(of: landing)
                            .filter { engine.board.cells[$0] == color }.count
                        let points = resolution.points * 1000 + matchingNeighbours * 100 - landing.row
                        if best == nil || points > best!.points { best = (points, angle, swap) }
                    }
                }
                if let best {
                    if best.swap { engine.swapColors() }
                    engine.setAim(best.angle)
                }
                engine.shoot(); settle(&engine)
                XCTAssertTrue(engine.board.cells.keys.allSatisfy(engine.board.isValid))
                XCTAssertLessThanOrEqual(engine.board.cells.count, 90)
                if engine.phase == .playing {
                    XCTAssertTrue(engine.board.colors.contains(engine.currentColor))
                    XCTAssertTrue(engine.board.colors.contains(engine.nextColor))
                }
            }
            XCTAssertTrue(engine.phase == .won || engine.phase == .gameOver,
                          "Seed \(seed), level \(engine.level), \(engine.board.cells.count) bubbles after \(engine.shots) shots")
            if engine.phase == .won { wins += 1; XCTAssertEqual(engine.level, BubblePawsEngine.totalLevels) }
            XCTAssertFalse(engine.needsAnimation)
        }
        XCTAssertGreaterThan(wins, 0, "Generated boards must allow complete runs with reasonable aim.")
    }

    @MainActor
    func testNewGameRewardsPersistOnceAndDoNotReplaceOtherHighScores() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let petStore = InMemoryPetStore()
        let arcadeStore = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(highScores: [.petsDash: 700])))
        let controller = PetSessionController(store: petStore, arcadeStore: arcadeStore)
        await controller.bootstrap()
        let id = UUID(), petID = try XCTUnwrap(controller.pets.first?.id)
        let payout = await controller.completeMiniGame(.bubblePaws, score: 1600, petID: petID, runID: id)
        let coins = controller.arcadeProgress.coins
        let repeated = await controller.completeMiniGame(.bubblePaws, score: 1600, petID: petID, runID: id)
        XCTAssertNotNil(payout); XCTAssertEqual(payout, repeated)
        XCTAssertEqual(controller.arcadeProgress.coins, coins)
        let saved = await arcadeStore.load()
        let decoded = try JSONDecoder().decode(ArcadeState.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded.progress.highScore(for: .bubblePaws), 1600)
        XCTAssertEqual(decoded.progress.highScore(for: .petsDash), 700)
        XCTAssertEqual(decoded.progress.gamesPlayed, 1)
    }

    private func cell(_ row: Int, _ column: Int) -> BubbleCell { BubbleCell(row: row, column: column) }
    private func settle(_ engine: inout BubblePawsEngine) {
        for _ in 0..<600 {
            guard engine.needsAnimation else { return }
            engine.update(deltaTime: 1 / 120.0)
        }
        XCTFail("Shot or effect failed to settle")
    }
}
