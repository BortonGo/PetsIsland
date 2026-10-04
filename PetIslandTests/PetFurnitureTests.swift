import XCTest
@testable import PetIsland

final class PetFurnitureTests: XCTestCase {
    func testEveryItemChargesOnceAndPersistsOwnership() throws {
        for item in HabitatItemKind.allCases {
            var progress = ArcadeProgress(coins: item.price + 7)
            XCTAssertTrue(progress.purchaseHabitatItem(item))
            XCTAssertEqual(progress.coins, 7)
            XCTAssertFalse(progress.purchaseHabitatItem(item))
            XCTAssertEqual(progress.coins, 7)
            XCTAssertEqual(try JSONDecoder().decode(ArcadeProgress.self, from: JSONEncoder().encode(progress)), progress)
            var poor = ArcadeProgress(coins: item.price - 1)
            XCTAssertFalse(poor.purchaseHabitatItem(item))
            XCTAssertTrue(poor.ownedHabitatItems.isEmpty)
        }
    }

    func testPlacementLimitsAndExplicitReplacementPreserveResidents() throws {
        let id = UUID()
        var state = PetHabitatState(residentPetIDs: [id], hasCozyBox: true)
        XCTAssertTrue(state.placeItem(.softBed, in: .left))
        XCTAssertTrue(state.placeItem(.birdPerch, in: .perch))
        let full = state
        XCTAssertFalse(state.placeItem(.leafNest, in: .left))
        XCTAssertFalse(state.placeItem(.playBall, in: .perch))
        XCTAssertFalse(state.placeItem(.birdPerch, in: .right))
        XCTAssertEqual(state, full)
        XCTAssertEqual(Set(state.furnitureConflicts(for: .leafNest, in: .left).map(\.item)), [.cozyBox, .softBed])
        XCTAssertTrue(state.placeItem(.leafNest, in: .left, replacing: true))
        XCTAssertEqual(Set(state.furniture.map(\.item)), [.leafNest, .birdPerch])
        XCTAssertFalse(state.hasCozyBox)
        XCTAssertEqual(state.residentPetIDs, [id])
        XCTAssertTrue(state.placeItem(.warmStone, in: .right))
        XCTAssertEqual(state.furniture.count, 3)
        XCTAssertEqual(try JSONDecoder().decode(PetHabitatState.self, from: JSONEncoder().encode(state)), state)
        XCTAssertTrue(state.removeItem(.leafNest))
        XCTAssertTrue(state.placeItem(.warmStone, in: .left))
        XCTAssertEqual(state.furniture.filter { $0.item == .warmStone }.count, 1)
    }

    func testOldBoxMigratesAndFutureOrInvalidPlacementsAreIgnored() throws {
        let old = try JSONDecoder().decode(PetHabitatState.self, from: Data("{\"hasCozyBox\":true}".utf8))
        XCTAssertEqual(old.furniture, [.init(item: .cozyBox, slot: .right)])
        let corrupt = Data("{\"hasCozyBox\":true,\"furniture\":{\"left\":\"cozyBox\",\"right\":\"leafNest\",\"perch\":\"softBed\",\"future\":\"warmStone\"}}".utf8)
        let decoded = try JSONDecoder().decode(PetHabitatState.self, from: corrupt)
        XCTAssertEqual(decoded.furniture, [.init(item: .cozyBox, slot: .left)])
        let removed = try JSONDecoder().decode(PetHabitatState.self, from: Data("{\"hasCozyBox\":true,\"furniture\":{}}".utf8))
        XCTAssertFalse(removed.hasCozyBox, "An explicit empty layout must not resurrect the legacy box")
        let future = try JSONDecoder().decode(PetHabitatState.self, from: Data("{\"furniture\":{\"left\":\"futureItem\",\"right\":\"softBed\"}}".utf8))
        XCTAssertEqual(future.furniture, [.init(item: .softBed, slot: .right)])
    }

    func testFurnitureFramesFitSmallAndLargeCanvasesAndLeaveCentralPassage() {
        for size in [CGSize(width: 280, height: 210), CGSize(width: 360, height: 236), CGSize(width: 600, height: 300)] {
            for item in HabitatItemKind.allCases {
                for slot in item.slots {
                    let rect = HabitatFurnitureLayout.frame(for: .init(item: item, slot: slot), in: size, petWidth: 93.6)
                    XCTAssertGreaterThanOrEqual(rect.minX, 0)
                    XCTAssertGreaterThanOrEqual(rect.minY, 0)
                    XCTAssertLessThanOrEqual(rect.maxX, size.width)
                    XCTAssertLessThanOrEqual(rect.maxY, size.height)
                    if slot == .left { XCTAssertLessThan(rect.maxX, size.width * 0.32) }
                    if slot == .right { XCTAssertGreaterThan(rect.minX, size.width * 0.68) }
                }
            }
        }
    }

    @MainActor
    func testReplacementPersistsWithoutChargingAgainOrLosingInventory() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        try PetHabitatStore.save(SharedPetHabitat(configuration: PetHabitatState(), residents: []))
        let store = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 23, ownedHabitatItems: Set(HabitatItemKind.allCases))))
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await controller.bootstrap()
        XCTAssertTrue(controller.placeHabitatItem(.cozyBox, in: .left))
        XCTAssertFalse(controller.placeHabitatItem(.leafNest, in: .right))
        XCTAssertTrue(controller.placeHabitatItem(.leafNest, in: .right, replacing: true))
        XCTAssertFalse(controller.habitat.configuration.hasCozyBox)
        XCTAssertEqual(controller.arcadeProgress.coins, 23)
        XCTAssertEqual(controller.arcadeProgress.ownedHabitatItems, Set(HabitatItemKind.allCases))
        let reopened = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.habitat.configuration.furniture, [.init(item: .leafNest, slot: .right)])
        XCTAssertTrue(reopened.setHabitatItem(.leafNest, placed: false))
        XCTAssertTrue(reopened.arcadeProgress.ownedHabitatItems.contains(.leafNest))
    }

    func testPermanentPurchaseDebitsOnceAndSurvivesRoundTrip() throws {
        var progress = ArcadeProgress(coins: 120)
        XCTAssertTrue(progress.purchaseHabitatItem(.cozyBox))
        XCTAssertEqual(progress.coins, 40)
        XCTAssertEqual(progress.ownedHabitatItems, [.cozyBox])
        let purchased = progress
        XCTAssertFalse(progress.purchaseHabitatItem(.cozyBox))
        XCTAssertEqual(progress, purchased)
        XCTAssertEqual(try JSONDecoder().decode(ArcadeProgress.self, from: JSONEncoder().encode(progress)), purchased)
        XCTAssertEqual(progress.inventory[.toy], 0)
        XCTAssertEqual(progress.gamesPlayed, 0)
    }

    func testInsufficientCoinsLeaveEntireProgressUnchanged() {
        var progress = ArcadeProgress(coins: HabitatItemKind.cozyBox.price - 1)
        let original = progress
        XCTAssertFalse(progress.purchaseHabitatItem(.cozyBox))
        XCTAssertEqual(progress, original)
    }

    func testLegacyMigrationKeepsInstalledBoxWithoutSpendingCoinsAndRunsOnce() throws {
        let original = ArcadeProgress(coins: 37, gamesPlayed: 4)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "ownedHabitatItems")
        json.removeValue(forKey: "hasImportedLegacyFurniture")
        var legacy = try JSONDecoder().decode(ArcadeProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(legacy.hasImportedLegacyFurniture)
        legacy.importLegacyFurniture(hasCozyBox: true)
        XCTAssertEqual(legacy.ownedHabitatItems, [.cozyBox])
        XCTAssertEqual(legacy.coins, 37)
        XCTAssertEqual(legacy.gamesPlayed, 4)
        let imported = legacy
        legacy.importLegacyFurniture(hasCozyBox: false)
        XCTAssertEqual(legacy, imported)
    }

    func testEmptyLegacyEnclosureStaysLockedAndUnknownItemsDoNotEraseWallet() throws {
        var legacy = ArcadeProgress(coins: 52, hasImportedLegacyFurniture: false)
        legacy.importLegacyFurniture(hasCozyBox: false)
        legacy.importLegacyFurniture(hasCozyBox: true)
        XCTAssertTrue(legacy.ownedHabitatItems.isEmpty)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        json["ownedHabitatItems"] = ["cozyBox", "futureItem"]
        let decoded = try JSONDecoder().decode(ArcadeProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.coins, 52)
        XCTAssertEqual(decoded.ownedHabitatItems, [.cozyBox])
    }

    @MainActor
    func testControllerPurchasePersistsAndDuplicateRequestsChargeOnlyOnce() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let store = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 200)))
        let petStore = InMemoryPetStore()
        let controller = PetSessionController(store: petStore, arcadeStore: store)
        await controller.bootstrap()
        async let first = controller.purchaseHabitatItem(.cozyBox)
        async let second = controller.purchaseHabitatItem(.cozyBox)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(controller.arcadeProgress.coins, 120)
        let saved = await store.load()
        XCTAssertEqual(saved.progress, controller.arcadeProgress)
        let reopened = PetSessionController(store: petStore, arcadeStore: store)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.arcadeProgress.ownedHabitatItems, [.cozyBox])
        XCTAssertEqual(reopened.arcadeProgress.coins, 120)
    }

    @MainActor
    func testFailedPurchaseChangesNeitherWalletNorOwnershipAndCanBeRetried() async {
        let store = FurnitureTestArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 100)))
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await controller.bootstrap()
        let before = await store.load()
        await store.setFailure(true)
        let failed = await controller.purchaseHabitatItem(.cozyBox)
        XCTAssertFalse(failed)
        XCTAssertEqual(controller.arcadeProgress, before.progress)
        let unchanged = await store.load()
        XCTAssertEqual(unchanged, before)
        await store.setFailure(false)
        let retried = await controller.purchaseHabitatItem(.cozyBox)
        XCTAssertTrue(retried)
        XCTAssertEqual(controller.arcadeProgress.coins, 20)
    }

    @MainActor
    func testCannotPlaceUnownedItemAndRemovingPurchasedItemKeepsOwnership() async {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let controller = PetSessionController(store: InMemoryPetStore(),
            arcadeStore: InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 100))))
        await controller.bootstrap()
        let ids = controller.pets.map(\.id)
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: ids, hasCozyBox: false))
        let before = PetHabitatStore.load()
        XCTAssertFalse(controller.saveHabitat(theme: .warmRoom, residentPetIDs: ids, hasCozyBox: true))
        XCTAssertEqual(PetHabitatStore.load(), before)
        let bought = await controller.purchaseHabitatItem(.cozyBox)
        XCTAssertTrue(bought)
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: ids, hasCozyBox: true))
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: ids, hasCozyBox: false))
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: ids, hasCozyBox: true))
        XCTAssertEqual(controller.arcadeProgress.coins, 20)
        XCTAssertEqual(controller.arcadeProgress.ownedHabitatItems, [.cozyBox])
    }

    @MainActor
    func testPlacementSavesImmediatelyAndEnclosureDraftCannotUndoIt() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let petStore = InMemoryPetStore()
        let arcadeStore = InMemoryArcadeStore(ArcadeState(progress:
            ArcadeProgress(coins: 20, ownedHabitatItems: [.cozyBox])))
        let controller = PetSessionController(store: petStore, arcadeStore: arcadeStore)
        await controller.bootstrap()
        let ids = controller.pets.map(\.id)
        XCTAssertTrue(controller.saveHabitat(theme: .warmRoom, residentPetIDs: ids, hasCozyBox: false))
        var expected = PetHabitatStore.load()
        expected.configuration.setCozyBox(true)

        XCTAssertTrue(controller.setHabitatItem(.cozyBox, placed: true))
        XCTAssertEqual(PetHabitatStore.load(), expected)
        XCTAssertEqual(controller.habitat, expected)
        // Dismissing either sheet without Save must not discard the placement.
        let reopened = PetSessionController(store: petStore, arcadeStore: arcadeStore)
        await reopened.bootstrap()
        XCTAssertTrue(reopened.habitat.configuration.hasCozyBox)
        XCTAssertEqual(reopened.habitat.configuration.theme, .warmRoom)
        XCTAssertEqual(reopened.habitat.configuration.residentPetIDs, ids)

        // Saving an independently edited theme must preserve the latest item choice.
        XCTAssertTrue(reopened.saveHabitat(theme: .sunnyMeadow, residentPetIDs: ids))
        XCTAssertTrue(PetHabitatStore.load().configuration.hasCozyBox)
        XCTAssertTrue(reopened.setHabitatItem(.cozyBox, placed: false))
        XCTAssertFalse(PetHabitatStore.load().configuration.hasCozyBox)
        XCTAssertTrue(reopened.saveHabitat(theme: .warmRoom, residentPetIDs: ids))
        XCTAssertFalse(PetHabitatStore.load().configuration.hasCozyBox)
        XCTAssertEqual(reopened.arcadeProgress.coins, 20)
        XCTAssertEqual(reopened.arcadeProgress.ownedHabitatItems, [.cozyBox])
    }

    @MainActor
    func testImmediatePlacementRejectsUnloadedAndUnownedItemsWithoutChangingHabitat() async {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: InMemoryArcadeStore())
        XCTAssertFalse(controller.setHabitatItem(.cozyBox, placed: true))
        XCTAssertFalse(controller.setHabitatItem(.cozyBox, placed: false))
        XCTAssertEqual(PetHabitatStore.load(), original)
        await controller.bootstrap()
        let before = PetHabitatStore.load()
        XCTAssertFalse(controller.setHabitatItem(.cozyBox, placed: true))
        XCTAssertEqual(PetHabitatStore.load(), before)
        XCTAssertEqual(controller.habitat, before)
    }

    @MainActor
    func testPurchaseBeforeBootstrapDoesNotReplaceSavedWallet() async {
        let state = ArcadeState(progress: ArcadeProgress(coins: 200))
        let store = InMemoryArcadeStore(state)
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        let result = await controller.purchaseHabitatItem(.cozyBox)
        XCTAssertFalse(result)
        let saved = await store.load()
        XCTAssertEqual(saved, state)
    }

    @MainActor
    func testBootstrapImportsExistingBoxPermanently() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        _ = try PetHabitatStore.update { $0.configuration.setCozyBox(true) }
        let store = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 17, hasImportedLegacyFurniture: false)))
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await controller.bootstrap()
        XCTAssertEqual(controller.arcadeProgress.ownedHabitatItems, [.cozyBox])
        XCTAssertEqual(controller.arcadeProgress.coins, 17)
        let saved = await store.load()
        XCTAssertTrue(saved.progress.hasImportedLegacyFurniture)
        XCTAssertEqual(saved.progress.ownedHabitatItems, [.cozyBox])
    }

    @MainActor
    func testFailedMigrationPreservesLegacySaveAndRetriesBeforeUnlocking() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        _ = try PetHabitatStore.update { $0.configuration.setCozyBox(true) }
        let initial = ArcadeState(progress: ArcadeProgress(coins: 17, hasImportedLegacyFurniture: false))
        let store = FurnitureTestArcadeStore(initial)
        await store.setFailure(true)
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await controller.bootstrap()
        XCTAssertEqual(controller.operation, .loadFailed)
        XCTAssertTrue(controller.arcadeProgress.ownedHabitatItems.isEmpty)
        let saved = await store.load()
        XCTAssertEqual(saved, initial)
        await store.setFailure(false)
        await controller.bootstrap()
        XCTAssertEqual(controller.operation, .idle)
        XCTAssertEqual(controller.arcadeProgress.ownedHabitatItems, [.cozyBox])
        XCTAssertEqual(controller.arcadeProgress.coins, 17)
    }
}

private actor FurnitureTestArcadeStore: ArcadeStore {
    private var state: ArcadeState
    private var fails = false
    init(_ state: ArcadeState) { self.state = state }
    func setFailure(_ value: Bool) { fails = value }
    func load() -> ArcadeState { state }
    func save(_ value: ArcadeState) throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        state = value
    }
}

extension PetFurnitureTests {
    private var furnitureCanvas: CGSize { CGSize(width: 360, height: 236) }

    private func furniturePet(_ species: PetSpecies, breed: PetBreed? = nil) -> PetProfile {
        PetProfile(id: UUID(), name: species.rawValue, species: species, coat: .sunrise,
                   createdAt: Date(timeIntervalSince1970: 1_000), breed: breed)
    }

    @MainActor
    private func advance(_ simulation: HabitatMotionSimulation, slot: HabitatFurnitureSlot,
                         until phase: HabitatMotionSimulation.FurniturePhase?) -> Bool {
        for _ in 0..<3_600 {
            if simulation.furnitureVisits[slot]?.phase == phase { return true }
            simulation.advance(by: 1.0 / 60)
        }
        return simulation.furnitureVisits[slot]?.phase == phase
    }

    @MainActor
    func testEveryNewItemSupportsAllItsBreedsAndCompletesContinuousVisit() throws {
        for item in HabitatItemKind.allCases where item != .cozyBox {
            for species in PetSpecies.allCases where item.supports(species) {
                for breed in PetBreed.available(for: species) {
                    let pet = furniturePet(species, breed: breed)
                    let placement = HabitatFurniturePlacement(item: item, slot: item.slots[0])
                    let simulation = HabitatMotionSimulation()
                    simulation.configure(pets: [pet], size: furnitureCanvas, furniture: [placement])
                    XCTAssertTrue(simulation.requestFurniture(placement.slot, petID: pet.id))
                    var previous = try XCTUnwrap(simulation.actors.first)
                    var phases = Set<String>()
                    for _ in 0..<3_600 {
                        if let visit = simulation.furnitureVisits[placement.slot] { phases.insert(visit.phase.rawValue) }
                        simulation.advance(by: 1.0 / 60)
                        let actor = try XCTUnwrap(simulation.actors.first)
                        XCTAssertEqual(actor.profile, pet)
                        let distance = hypot(actor.position.x - previous.position.x,
                            actor.position.y + actor.visualOffsetY - previous.position.y - previous.visualOffsetY)
                        XCTAssertLessThan(distance, 3, "\(item) / \(breed): discontinuous entry or exit")
                        XCTAssertTrue(actor.position.x.isFinite && actor.position.y.isFinite && actor.visualOffsetY.isFinite)
                        XCTAssertEqual(abs(actor.facing), 1)
                        let clip = PetAnimationLibrary.naturalClip(for: species, breed: breed, pose: actor.pose)
                        XCTAssertTrue(clip.frames.indices.contains(actor.step), "\(item): invalid \(actor.pose) frame")
                        previous = actor
                        if simulation.furnitureVisits[placement.slot] == nil { break }
                    }
                    XCTAssertNil(simulation.furnitureVisits[placement.slot], "\(item): visit must finish")
                    XCTAssertEqual(phases, ["approaching", "settling", "using", "leaving"])
                    XCTAssertEqual(previous.visualOffsetY, 0, accuracy: 0.001)
                }
            }
        }
    }

    @MainActor
    func testReservationsAreExclusiveAcrossPetsItemsAndTheOriginalCatBox() {
        let cats = [furniturePet(.cat), furniturePet(.cat)]
        let dog = furniturePet(.dog)
        let simulation = HabitatMotionSimulation()
        let layout: [HabitatFurniturePlacement] = [.init(item: .cozyBox, slot: .left), .init(item: .playBall, slot: .right)]
        simulation.configure(pets: cats + [dog], size: furnitureCanvas, furniture: layout)
        XCTAssertFalse(simulation.requestFurniture(.left, petID: dog.id))
        XCTAssertFalse(simulation.requestFurniture(.perch))
        XCTAssertTrue(simulation.requestFurniture(.right, petID: cats[0].id))
        XCTAssertFalse(simulation.requestCatToBox(cats[0].id))
        XCTAssertTrue(simulation.requestCatToBox(cats[1].id))
        for phase: HabitatMotionSimulation.FurniturePhase in [.approaching, .settling, .using, .leaving] {
            XCTAssertTrue(advance(simulation, slot: .right, until: phase))
            for challenger in cats + [dog] {
                XCTAssertFalse(simulation.requestFurniture(.right, petID: challenger.id))
                XCTAssertEqual(simulation.furnitureVisits[.right]?.petID, cats[0].id)
            }
        }
        XCTAssertTrue(advance(simulation, slot: .right, until: nil))
        XCTAssertTrue(simulation.requestFurniture(.right, petID: dog.id))
    }

    @MainActor
    func testChangingFurnitureAndDepartingResidentsReleaseOnlyTheirReservations() throws {
        let dog = furniturePet(.dog), bird = furniturePet(.parrot)
        let simulation = HabitatMotionSimulation()
        let bed = HabitatFurniturePlacement(item: .softBed, slot: .left)
        let swing = HabitatFurniturePlacement(item: .birdPerch, slot: .perch)
        simulation.configure(pets: [dog, bird], size: furnitureCanvas, furniture: [bed, swing])
        XCTAssertTrue(simulation.requestFurniture(.left, petID: dog.id))
        XCTAssertTrue(simulation.requestFurniture(.perch, petID: bird.id))
        XCTAssertTrue(advance(simulation, slot: .perch, until: .using))
        let before = try XCTUnwrap(simulation.actors.first { $0.id == bird.id })
        simulation.configure(pets: [dog, bird], size: furnitureCanvas, furniture: [bed])
        let after = try XCTUnwrap(simulation.actors.first { $0.id == bird.id })
        XCTAssertEqual(after.position, before.position)
        XCTAssertEqual(after.visualOffsetY, before.visualOffsetY)
        XCTAssertNil(simulation.furnitureVisits[.perch])
        XCTAssertEqual(simulation.furnitureVisits[.left]?.petID, dog.id)
        for _ in 0..<120 { simulation.advance(by: 1.0 / 60) }
        XCTAssertEqual(simulation.actors.first { $0.id == bird.id }?.visualOffsetY, 0)
        simulation.configure(pets: [bird], size: furnitureCanvas, furniture: [bed, swing])
        XCTAssertNil(simulation.furnitureVisits[.left])
        XCTAssertTrue(simulation.requestFurniture(.perch, petID: bird.id))
        simulation.configure(pets: [], size: furnitureCanvas, furniture: [bed, swing])
        XCTAssertTrue(simulation.furnitureVisits.isEmpty)
        XCTAssertFalse(simulation.isRunning)
    }

    @MainActor
    func testResizeAndPettingDuringEveryPhaseKeepVisitsContinuous() throws {
        for phase: HabitatMotionSimulation.FurniturePhase in [.approaching, .settling, .using, .leaving] {
            let bird = furniturePet(.parrot)
            let simulation = HabitatMotionSimulation()
            let layout: [HabitatFurniturePlacement] = [.init(item: .birdPerch, slot: .perch)]
            simulation.configure(pets: [bird], size: furnitureCanvas, furniture: layout)
            XCTAssertTrue(simulation.requestFurniture(.perch))
            XCTAssertTrue(advance(simulation, slot: .perch, until: phase))
            simulation.configure(pets: [bird], size: CGSize(width: 430, height: 280), petScale: 1.2, furniture: layout)
            XCTAssertEqual(simulation.furnitureVisits[.perch]?.petID, bird.id)
            var before = try XCTUnwrap(simulation.actors.first)
            simulation.pet(bird.id)
            XCTAssertEqual(simulation.actors.first?.position, before.position)
            for _ in 0..<180 {
                simulation.advance(by: 1.0 / 60)
                let after = try XCTUnwrap(simulation.actors.first)
                XCTAssertLessThan(hypot(after.position.x - before.position.x,
                    after.position.y + after.visualOffsetY - before.position.y - before.visualOffsetY), 4)
                before = after
                if simulation.furnitureVisits.isEmpty { break }
            }
            XCTAssertTrue(simulation.furnitureVisits.isEmpty)
            XCTAssertEqual(before.visualOffsetY, 0, accuracy: 0.001)
        }
    }

    @MainActor
    func testReducedMotionAndInactiveCanvasDoNotRunFurnitureTimers() throws {
        let bird = furniturePet(.parrot)
        let simulation = HabitatMotionSimulation()
        let layout: [HabitatFurniturePlacement] = [.init(item: .birdPerch, slot: .perch)]
        simulation.configure(pets: [bird], size: furnitureCanvas, furniture: layout)
        simulation.start(reduceMotion: false, active: false)
        XCTAssertFalse(simulation.isRunning)
        simulation.start(reduceMotion: true, active: true)
        XCTAssertFalse(simulation.isRunning)
        XCTAssertTrue(simulation.requestFurniture(.perch))
        let before = simulation.actors
        let visits = simulation.furnitureVisits
        for _ in 0..<300 { simulation.advance(by: 1.0 / 60) }
        XCTAssertEqual(simulation.actors, before)
        XCTAssertEqual(simulation.furnitureVisits, visits)
        simulation.pet(bird.id)
        XCTAssertTrue(simulation.furnitureVisits.isEmpty)
        XCTAssertEqual(simulation.actors.first?.visualOffsetY, 0)
        simulation.start(reduceMotion: false, active: true)
        XCTAssertTrue(simulation.isRunning)
        simulation.stop()
        XCTAssertFalse(simulation.isRunning)
    }

    @MainActor
    func testFullEnclosureRemainsBoundedAndAutomaticallyUsesFurniture() {
        let pets = [furniturePet(.dog), furniturePet(.cat), furniturePet(.fox),
                    furniturePet(.parrot), furniturePet(.penguin), furniturePet(.lion)]
        let simulation = HabitatMotionSimulation()
        let layout: [HabitatFurniturePlacement] = [.init(item: .softBed, slot: .left),
            .init(item: .playBall, slot: .right), .init(item: .birdPerch, slot: .perch)]
        simulation.configure(pets: pets, size: furnitureCanvas, furniture: layout)
        var visited = Set<HabitatFurnitureSlot>()
        for _ in 0..<180 * 60 {
            simulation.advance(by: 1.0 / 60)
            visited.formUnion(simulation.furnitureVisits.keys)
            let owners = simulation.furnitureVisits.values.map(\.petID)
            XCTAssertEqual(Set(owners).count, owners.count)
            for actor in simulation.actors {
                XCTAssertGreaterThanOrEqual(actor.position.x, 0)
                XCTAssertLessThanOrEqual(actor.position.x, furnitureCanvas.width)
                XCTAssertGreaterThan(actor.position.y + actor.visualOffsetY, 0)
                XCTAssertLessThan(actor.position.y + actor.visualOffsetY, furnitureCanvas.height)
            }
        }
        XCTAssertEqual(visited, [.left, .right, .perch])
        let before = simulation.actors
        for delta in [Double.nan, .infinity, -1, 0] { simulation.advance(by: delta) }
        XCTAssertEqual(simulation.actors, before)
    }
}

extension PetFurnitureTests {
    @MainActor
    func testLegacyBoxEditCannotSilentlyReplaceFullLayoutOrPartiallySaveTheme() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let layout: [HabitatFurniturePlacement] = [.init(item: .softBed, slot: .left), .init(item: .warmStone, slot: .right)]
        try PetHabitatStore.save(SharedPetHabitat(configuration: PetHabitatState(furniture: layout), residents: []))
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: InMemoryArcadeStore(
            ArcadeState(progress: ArcadeProgress(coins: 18, ownedHabitatItems: [.cozyBox, .softBed, .warmStone]))))
        await controller.bootstrap()
        let before = controller.habitat
        XCTAssertFalse(controller.saveHabitat(theme: .sunsetDunes, residentPetIDs: controller.pets.map(\.id), hasCozyBox: true))
        XCTAssertEqual(controller.habitat, before)
        XCTAssertEqual(PetHabitatStore.load(), before)
        XCTAssertTrue(controller.saveHabitat(theme: .sunsetDunes, residentPetIDs: controller.pets.map(\.id)))
        XCTAssertEqual(controller.habitat.configuration.furniture, layout)
        XCTAssertEqual(controller.arcadeProgress.coins, 18)
    }

    @MainActor
    func testMovingOccupiedFurnitureCancelsVisitWithoutTeleportingResident() throws {
        let pet = furniturePet(.dog)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [pet], size: furnitureCanvas, furniture: [.init(item: .softBed, slot: .left)])
        XCTAssertTrue(simulation.requestFurniture(.left))
        XCTAssertTrue(advance(simulation, slot: .left, until: .using))
        let before = try XCTUnwrap(simulation.actors.first)
        simulation.configure(pets: [pet], size: furnitureCanvas, furniture: [.init(item: .softBed, slot: .right)])
        XCTAssertTrue(simulation.furnitureVisits.isEmpty)
        XCTAssertEqual(simulation.actors.first?.position, before.position)
        XCTAssertEqual(simulation.actors.first?.visualOffsetY, before.visualOffsetY)
        XCTAssertFalse(simulation.requestFurniture(.left))
        XCTAssertTrue(simulation.requestFurniture(.right))
        XCTAssertEqual(simulation.furnitureVisits[.right]?.petID, pet.id)
    }
}
