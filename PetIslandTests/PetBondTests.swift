import CryptoKit
import XCTest
@testable import PetIsland

final class PetBondTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    func testEachKindCountsOncePerDayAndClockRollbackDoesNotGrantAgain() {
        var bond = PetBond()
        for _ in 0..<100 {
            bond.shareAttention(at: start, calendar: calendar)
            bond.recordCare(.toy, at: start, calendar: calendar)
            bond.recordGame(.bubblePaws, at: start, calendar: calendar)
        }
        XCTAssertEqual(bond.points, 3)
        XCTAssertEqual(bond.careDays, [.toy: 1])
        XCTAssertEqual(bond.gameDays, [.bubblePaws: 1])
        XCTAssertFalse(bond.shareAttention(at: start.addingTimeInterval(-86400), calendar: calendar))
        XCTAssertTrue(bond.shareAttention(at: start.addingTimeInterval(86400), calendar: calendar))
        XCTAssertEqual(bond.points, 4)
        XCTAssertFalse(bond.shareAttention(at: Date(timeIntervalSinceReferenceDate: .infinity)))
        XCTAssertFalse(bond.shareAttention(at: Date(timeIntervalSinceReferenceDate: .nan)))
    }

    func testLocalMidnightAndDaylightSavingUseCalendarDays() throws {
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let midnight = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        var bond = PetBond()
        XCTAssertTrue(bond.shareAttention(at: midnight.addingTimeInterval(-1), calendar: cal))
        XCTAssertTrue(bond.shareAttention(at: midnight, calendar: cal))
        XCTAssertFalse(bond.shareAttention(at: midnight.addingTimeInterval(22 * 3600), calendar: cal))
        XCTAssertTrue(bond.shareAttention(at: midnight.addingTimeInterval(23 * 3600), calendar: cal))
    }

    func testStagesCapWithoutDecayAndHabitsNeedThreeRepeatsAndClearWinner() throws {
        var bond = PetBond()
        for day in 0..<3 {
            let date = start.addingTimeInterval(Double(day) * 86400)
            bond.recordCare(.toy, at: date, calendar: calendar)
            bond.recordGame(.bubblePaws, at: date, calendar: calendar)
            if day < 2 { XCTAssertNil(bond.familiarCare) }
        }
        XCTAssertEqual(bond.stage, .familiar)
        XCTAssertEqual(bond.familiarCare, .toy)
        XCTAssertEqual(bond.familiarGame, .bubblePaws)
        for day in 3..<6 { bond.recordCare(.food, at: start.addingTimeInterval(Double(day) * 86400), calendar: calendar) }
        XCTAssertNil(bond.familiarCare)
        for day in 6..<60 { bond.shareAttention(at: start.addingTimeInterval(Double(day) * 86400), calendar: calendar) }
        XCTAssertEqual(bond.points, 30)
        XCTAssertEqual(bond.stage, .inseparable)
        XCTAssertEqual(bond.stageProgress, 1)
        let reopened = try JSONDecoder().decode(PetBond.self, from: JSONEncoder().encode(bond))
        XCTAssertEqual(reopened, bond)
        XCTAssertTrue(reopened.canShare(.attention, at: start.addingTimeInterval(86400 * 900), calendar: calendar))
        XCTAssertEqual(reopened.points, 30)
    }

    func testOldArcadeSaveLoadsAndReconciliationRemovesOnlyDeletedPets() throws {
        let pets = fixture().pets
        var state = ArcadeState()
        state.bondsByPetID[pets[0].id, default: PetBond()].shareAttention(at: start)
        state.bondsByPetID[pets[1].id, default: PetBond()].shareAttention(at: start)
        state.reconcile(with: [pets[1]])
        XCTAssertNil(state.bondsByPetID[pets[0].id])
        XCTAssertEqual(state.bondsByPetID[pets[1].id]?.points, 1)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        raw["bondsByPetID"] = nil
        let old = try JSONDecoder().decode(ArcadeState.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertTrue(old.bondsByPetID.isEmpty)
        XCTAssertEqual(old.progress, state.progress)
    }

    @MainActor
    func testAttentionIsPerPetFreePersistsAfterRenameAndRepeatedTapsAreHarmless() async throws {
        let state = fixture()
        let pet = state.pets[1]
        let store = InMemoryPetStore(state), arcade = BondTestStore(ArcadeState(progress: ArcadeProgress(coins: 42)))
        let controller = try await controller(state, store: store, arcade: arcade)
        let before = await arcade.load()
        let habitat = controller.habitat
        let tasks = (0..<8).map { _ in Task { await controller.sharePetMoment(with: pet.id) } }
        var successes = 0
        for task in tasks { if await task.value { successes += 1 } }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(controller.bond(for: pet.id).points, 1)
        XCTAssertEqual(controller.bond(for: state.profile.id).points, 0)
        let saved = await arcade.load()
        XCTAssertEqual(saved.progress, before.progress)
        XCTAssertEqual(saved.vitalsByPetID, before.vitalsByPetID)
        XCTAssertEqual(controller.habitat, habitat)
        XCTAssertEqual(controller.pets, state.pets, "Friendship never rewrites artwork, outfits or proportions")
        var renamed = pet; renamed.name = "Луна"
        let updated = await controller.updatePet(renamed)
        XCTAssertTrue(updated)
        let reopened = PetSessionController(store: store, arcadeStore: arcade)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.bond(for: pet.id), controller.bond(for: pet.id))
        XCTAssertFalse(reopened.canSharePetMoment(with: pet.id))
    }

    @MainActor
    func testFailedAttentionOrCareSaveGrantsNothingAndCanBeRetried() async throws {
        let state = fixture(), petID = state.pets[1].id
        var stock = ArcadeInventory(); stock.add(.food, count: 2)
        let arcade = BondTestStore(ArcadeState(progress: ArcadeProgress(inventory: stock),
            vitalsByPetID: [petID: PetVitals(fullness: 0.3)]))
        let controller = try await controller(state, arcade: arcade)
        await arcade.failNextWrite()
        let failed = await controller.sharePetMoment(with: petID)
        XCTAssertFalse(failed)
        XCTAssertEqual(controller.bond(for: petID), PetBond())
        let retried = await controller.sharePetMoment(with: petID)
        XCTAssertTrue(retried)
        await arcade.failNextWrite()
        let careFailed = await controller.useArcadeItem(.food, for: petID)
        XCTAssertFalse(careFailed)
        XCTAssertEqual(controller.bond(for: petID).points, 1)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 2)
        let care = await controller.useArcadeItem(.food, for: petID)
        XCTAssertTrue(care)
        XCTAssertEqual(controller.bond(for: petID).points, 2)
        XCTAssertEqual(controller.bond(for: petID).careDays, [.food: 1])
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 1)
    }

    @MainActor
    func testUnavailableCareAndEmptyGamesDoNotGrantAndCompletedRunDoesNotRepeat() async throws {
        let state = fixture(), petID = state.pets[1].id
        let arcade = BondTestStore(ArcadeState())
        let controller = try await controller(state, arcade: arcade)
        let unavailable = await controller.useArcadeItem(.food, for: petID)
        XCTAssertFalse(unavailable)
        _ = await controller.completeMiniGame(.skyHop, score: 0, petID: petID)
        XCTAssertEqual(controller.bond(for: petID).points, 0)
        let runID = UUID()
        await arcade.failNextWrite()
        let failed = await controller.completeMiniGame(.skyHop, score: 100, petID: petID, runID: runID)
        XCTAssertNil(failed)
        XCTAssertEqual(controller.bond(for: petID).points, 0)
        _ = await controller.completeMiniGame(.skyHop, score: 100, petID: petID, runID: runID)
        _ = await controller.completeMiniGame(.skyHop, score: 100, petID: petID, at: .now.addingTimeInterval(86400), runID: runID)
        XCTAssertEqual(controller.bond(for: petID).points, 1)
        XCTAssertEqual(controller.bond(for: petID).gameDays, [.skyHop: 1])
        XCTAssertEqual(controller.bond(for: state.profile.id).points, 0)
    }

    @MainActor
    func testAwayMissingAndUnloadedPetsCannotReceiveAttention() async throws {
        var state = fixture()
        let pet = state.pets[1]
        state.discoveries.startWalk(pet: pet, route: .garden, at: .now)
        let unbooted = PetSessionController(store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore())
        let early = await unbooted.sharePetMoment(with: pet.id)
        XCTAssertFalse(early)
        let controller = try await controller(state)
        XCTAssertFalse(controller.canSharePetMoment(with: pet.id))
        let away = await controller.sharePetMoment(with: pet.id)
        let missing = await controller.sharePetMoment(with: UUID())
        XCTAssertFalse(away); XCTAssertFalse(missing)
        let cancelled = await controller.cancelDiscoveryWalk()
        XCTAssertTrue(cancelled)
        XCTAssertTrue(controller.canSharePetMoment(with: pet.id))
    }

    @MainActor
    func testFamiliarPathsUseOnlyThisPetsCollectedMemories() async throws {
        var state = fixture()
        for index in 0..<5 {
            state.discoveries.startWalk(pet: state.pets[index < 3 ? 1 : 0], route: index < 3 ? .garden : .shore,
                at: start.addingTimeInterval(Double(index) * 86400))
            state.discoveries.collectWalk(at: start.addingTimeInterval(Double(index + 1) * 86400))
        }
        let controller = try await controller(state)
        let first = try XCTUnwrap(controller.profileOverview(for: state.pets[0].id))
        let second = try XCTUnwrap(controller.profileOverview(for: state.pets[1].id))
        XCTAssertNil(PetBond.familiarRoute(in: first.memories))
        XCTAssertEqual(PetBond.familiarRoute(in: second.memories), .garden)
    }

    @MainActor
    func testBackupRoundTripReturnCopyAndLegacyVersionPreserveExpectedBond() async throws {
        let state = fixture(), petID = state.pets[1].id
        let controller = try await controller(state)
        let shared = await controller.sharePetMoment(with: petID)
        XCTAssertTrue(shared)
        let data = try await controller.exportIslandBackup()
        let backup = try IslandBackupCodec.decode(data)
        XCTAssertEqual(backup.arcade.bondsByPetID[petID]?.points, 1)
        var legacyEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payloadData = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(legacyEnvelope["payload"] as? String)))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
        var arcade = payload["arcade"] as! [String: Any]
        arcade["bondsByPetID"] = nil; payload["arcade"] = arcade
        let oldPayload = try JSONSerialization.data(withJSONObject: payload)
        legacyEnvelope["payload"] = oldPayload.base64EncodedString()
        legacyEnvelope["checksum"] = SHA256.hash(data: oldPayload).map { String(format: "%02x", $0) }.joined()
        XCTAssertThrowsError(try IslandBackupCodec.decode(JSONSerialization.data(withJSONObject: legacyEnvelope)))
        legacyEnvelope["version"] = 1
        let legacy = try JSONSerialization.data(withJSONObject: legacyEnvelope)
        XCTAssertTrue(try IslandBackupCodec.decode(legacy).arcade.bondsByPetID.isEmpty)
        try await controller.restoreIslandBackup(legacy)
        XCTAssertEqual(controller.bond(for: petID).points, 0)
        let recovery = try await controller.islandRecoveryBackup()
        XCTAssertEqual(try IslandBackupCodec.decode(XCTUnwrap(recovery)).arcade.bondsByPetID[petID]?.points, 1)
        try await controller.restoreIslandBackup(data)
        XCTAssertEqual(controller.bond(for: petID).points, 1)
        try await controller.restoreIslandBackup(data)
        XCTAssertEqual(controller.bond(for: petID).points, 1)
    }

    func testCorruptBondIsRejectedInsteadOfImportingSilentProgressLoss() throws {
        var bond = PetBond(); bond.shareAttention(at: start)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bond)) as? [String: Any])
        raw["points"] = Int.max
        XCTAssertThrowsError(try JSONDecoder().decode(PetBond.self, from: JSONSerialization.data(withJSONObject: raw)))
        var backup = IslandBackup(app: fixture(), arcade: ArcadeState(), habitat: PetHabitatState())
        backup.arcade.bondsByPetID[UUID()] = bond
        XCTAssertThrowsError(try IslandBackupCodec.encode(backup))
    }

    private func fixture() -> PersistedAppState {
        var state = PersistedAppState()
        state.pets = [
            PetProfile(id: UUID(), name: "Корги", species: .dog, coat: .sunrise, createdAt: .now, breed: .corgi),
            PetProfile(id: UUID(), name: "Пиксель", species: .cat, coat: .sunrise, createdAt: .now, breed: .maineCoon)
        ]
        state.activePetIDs = [state.pets[0].id]
        state.completedOnboarding = true
        state.normalizePetCollection()
        return state
    }

    @MainActor
    private func controller(_ state: PersistedAppState, store: (any PetStore)? = nil,
                            arcade: any ArcadeStore = InMemoryArcadeStore()) async throws -> PetSessionController {
        let saved = try await arcade.load()
        let backup = IslandBackup(app: state, arcade: saved, habitat: PetHabitatState(residentPetIDs: state.pets.map(\.id)))
        try PetHabitatStore.save(backup.sharedHabitat)
        try PetLifeStore.save(backup.sharedLife)
        let controller = PetSessionController(store: store ?? InMemoryPetStore(state), arcadeStore: arcade)
        await controller.bootstrap()
        return controller
    }
}

private actor BondTestStore: ArcadeStore {
    private var value: ArcadeState
    private var shouldFail = false
    init(_ value: ArcadeState) { self.value = value }
    func failNextWrite() { shouldFail = true }
    func load() -> ArcadeState { value }
    func save(_ value: ArcadeState) throws {
        if shouldFail { shouldFail = false; throw CocoaError(.fileWriteUnknown) }
        self.value = value
    }
}
