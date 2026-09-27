import XCTest
@testable import PetIsland

final class PetFurnitureTests: XCTestCase {
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
