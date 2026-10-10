import CryptoKit
import XCTest
@testable import PetIsland

final class IslandBackupTests: XCTestCase {
    private func sample() -> IslandBackup {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let cat = PetProfile(id: UUID(), name: "Пиксель", species: .cat, coat: .sunrise, createdAt: date,
                             customColor: PetColorSelection(red: 0.3, green: 0.5, blue: 0.7), breed: .maineCoon,
                             outfit: PetOutfit(headwear: .knitHat))
        let dog = PetProfile(id: UUID(), name: "Корги", species: .dog, coat: .cloud, createdAt: date, breed: .cardigan)
        var app = PersistedAppState()
        app.pets = [cat, dog]; app.activePetIDs = [cat.id]; app.completedOnboarding = true
        app.settings.appearance = .dark
        app.settings.dynamicIslandMotionMode = .walkSleep
        app.discoveries.startWalk(pet: cat, route: .garden, at: date)
        app.discoveries.collectWalk(at: date.addingTimeInterval(3600))
        app.discoveries.startWalk(pet: dog, route: .shore, at: .now)
        var inventory = ArcadeInventory()
        inventory.add(.food, count: 7); inventory.add(.vitamins, count: 2)
        var arcade = ArcadeState(progress: ArcadeProgress(coins: 300, totalScore: 1200, gamesPlayed: 5,
            highScores: [.petsDash: 400], inventory: inventory,
            ownedHabitatItems: [.cozyBox, .softBed], ownedAccessories: [.knitHat, .tinyCrown]),
            vitalsByPetID: [cat.id: PetVitals(fullness: 0.5), dog.id: PetVitals(energy: 0.3)])
        arcade.vitalsUpdatedAtByPetID = [cat.id: date, dog.id: date]
        var engine = BubblePawsEngine(seed: 15)
        engine.start()
        arcade.bubblePawsRuns = [BubblePawsCheckpoint(engine: engine, petID: cat.id, runID: UUID())!]
        return IslandBackup(createdAt: date, app: app, arcade: arcade,
            habitat: PetHabitatState(theme: .starryNight, residentPetIDs: [cat.id, dog.id], simulationEpoch: date,
                                     furniture: [.init(item: .cozyBox, slot: .left), .init(item: .softBed, slot: .right)]))
    }

    func testRoundTripKeepsEveryPortableFeatureAndOriginalArtworkChoices() throws {
        let original = sample()
        let decoded = try IslandBackupCodec.decode(IslandBackupCodec.encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.sharedHabitat.residents.map(\.profile), original.app.pets)
        XCTAssertEqual(decoded.sharedHabitat.discoveryWalk, original.app.discoveries.activeWalk)
        XCTAssertEqual(decoded.sharedLife.placement, .enclosure)
    }

    func testInvalidDataChecksumVersionAndOversizedFileAreRejected() throws {
        let data = try IslandBackupCodec.encode(sample())
        XCTAssertThrowsError(try IslandBackupCodec.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try IslandBackupCodec.decode(data.dropLast(20)))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        envelope["checksum"] = "broken"
        XCTAssertThrowsError(try IslandBackupCodec.decode(JSONSerialization.data(withJSONObject: envelope)))
        envelope["version"] = 99
        XCTAssertThrowsError(try IslandBackupCodec.decode(JSONSerialization.data(withJSONObject: envelope))) { error in
            XCTAssertEqual(error as? IslandBackupError, .newerVersion)
        }
        XCTAssertThrowsError(try IslandBackupCodec.decode(Data(repeating: 0, count: IslandBackupCodec.maximumBytes + 1)))
    }

    func testIncompleteOrSilentlyRepairedPayloadCannotReplacePets() throws {
        let original = try IslandBackupCodec.encode(sample())
        for mutate in [
            { (raw: inout [String: Any]) in raw["arcade"] = nil },
            { raw in var app = raw["app"] as! [String: Any]; app["pets"] = []; raw["app"] = app },
            { raw in var app = raw["app"] as! [String: Any]; var pets = app["pets"] as! [Any]; pets.append(pets[0]); app["pets"] = pets; raw["app"] = app },
            { raw in var arcade = raw["arcade"] as! [String: Any]; arcade["bubblePawsRuns"] = [[:]]; raw["arcade"] = arcade },
            { raw in var arcade = raw["arcade"] as! [String: Any]; arcade["schemaVersion"] = 90; raw["arcade"] = arcade }
        ] {
            XCTAssertThrowsError(try IslandBackupCodec.decode(modified(original, mutate)))
        }
    }

    func testInvalidRelationshipsAndUnsafeAmountsAreRejected() throws {
        var value = sample()
        value.habitat.setResidents([UUID()])
        XCTAssertThrowsError(try IslandBackupCodec.encode(value))
        value = sample()
        value.arcade.progress = ArcadeProgress(coins: Int.max)
        XCTAssertThrowsError(try IslandBackupCodec.encode(value))
        value = sample()
        value.arcade.vitalsByPetID[value.app.profile.id] = PetVitals()
        value.arcade.vitalsByPetID[value.app.profile.id]?.fullness = .infinity
        XCTAssertThrowsError(try IslandBackupCodec.encode(value))
    }

    @MainActor
    func testExportDoesNotSpendCoinsChangePetsOrConsumeFinds() async throws {
        let original = sample()
        let store = InMemoryPetStore(original.app)
        let arcade = InMemoryArcadeStore(original.arcade)
        try PetHabitatStore.save(original.sharedHabitat)
        try PetLifeStore.save(original.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade)
        await controller.bootstrap()
        let beforeApp = await store.load(), beforeArcade = await arcade.load()
        let data = try await controller.exportIslandBackup()
        let decoded = try IslandBackupCodec.decode(data)
        XCTAssertEqual(decoded.app, beforeApp)
        XCTAssertEqual(decoded.arcade, beforeArcade)
        let afterApp = await store.load(), afterArcade = await arcade.load()
        XCTAssertEqual(afterApp, beforeApp); XCTAssertEqual(afterArcade, beforeArcade)
    }

    @MainActor
    func testRestorePersistsWholeIslandAndRecoveryCopyAcrossRelaunch() async throws {
        let old = sample(), imported = sample()
        let store = InMemoryPetStore(old.app), arcade = InMemoryArcadeStore(old.arcade)
        let recovery = InMemoryIslandBackupStore()
        try PetHabitatStore.save(old.sharedHabitat); try PetLifeStore.save(old.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade, backupStore: recovery)
        await controller.bootstrap()
        try await controller.restoreIslandBackup(IslandBackupCodec.encode(imported))
        XCTAssertEqual(controller.pets, imported.app.pets)
        XCTAssertEqual(controller.arcadeProgress, imported.arcade.progress)
        XCTAssertEqual(controller.discoveries, imported.app.discoveries)
        XCTAssertEqual(controller.habitat.configuration, imported.habitat)
        let storedArcade = await arcade.load()
        XCTAssertEqual(storedArcade, imported.arcade)
        let storedRecovery = await recovery.recoveryBackup()
        let recoveryData = try XCTUnwrap(storedRecovery)
        XCTAssertEqual(try IslandBackupCodec.decode(recoveryData).app.pets, old.app.pets)
        let storedResult1 = await recovery.pendingRestore()
        XCTAssertNil(storedResult1)
        let reopened = PetSessionController(store: store, arcadeStore: arcade, backupStore: recovery)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.pets, imported.app.pets)
        XCTAssertEqual(reopened.arcadeProgress, imported.arcade.progress)
        try await reopened.restoreIslandBackup(recoveryData)
        XCTAssertEqual(reopened.pets, old.app.pets)
        XCTAssertEqual(reopened.arcadeProgress, old.arcade.progress)
    }

    @MainActor
    func testSecondStoreFailureRollsBackCollectionAndSharedIsland() async throws {
        let old = sample()
        let store = InMemoryPetStore(old.app), arcade = BackupFailingArcadeStore(old.arcade)
        let recovery = InMemoryIslandBackupStore()
        try PetHabitatStore.save(old.sharedHabitat); try PetLifeStore.save(old.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade, backupStore: recovery)
        await controller.bootstrap()
        let before = await store.load()
        await arcade.failNextWrites(1)
        do { try await controller.restoreIslandBackup(IslandBackupCodec.encode(sample())); XCTFail("Expected write failure") }
        catch { XCTAssertEqual(error as? IslandBackupError, .saveFailed) }
        let after = await store.load()
        XCTAssertEqual(after, before)
        XCTAssertEqual(controller.pets, old.app.pets)
        XCTAssertEqual(PetHabitatStore.load().configuration, old.habitat)
        let storedResult1 = await recovery.pendingRestore()
        XCTAssertNil(storedResult1)
    }

    @MainActor
    func testRollbackFailureKeepsJournalAndRecoversBeforeNextBootstrap() async throws {
        let old = sample()
        let store = InMemoryPetStore(old.app), arcade = BackupFailingArcadeStore(old.arcade)
        let recovery = InMemoryIslandBackupStore()
        try PetHabitatStore.save(old.sharedHabitat); try PetLifeStore.save(old.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade, backupStore: recovery)
        await controller.bootstrap()
        await arcade.failNextWrites(2)
        do { try await controller.restoreIslandBackup(IslandBackupCodec.encode(sample())); XCTFail("Expected rollback failure") }
        catch { XCTAssertEqual(error as? IslandBackupError, .recoveryRequired) }
        XCTAssertEqual(controller.operation, .loadFailed)
        let settingsSaved = await controller.updateSettings(AppSettings(appearance: .light))
        XCTAssertFalse(settingsSaved)
        let storedResult3 = await recovery.pendingRestore()
        XCTAssertNotNil(storedResult3)
        await controller.bootstrap()
        XCTAssertEqual(controller.pets, old.app.pets)
        XCTAssertEqual(controller.arcadeProgress, old.arcade.progress)
        XCTAssertEqual(controller.operation, .idle)
        let storedResult1 = await recovery.pendingRestore()
        XCTAssertNil(storedResult1)
    }

    @MainActor
    func testInterruptedRestoreRollsBackEvenAfterEveryStoreWasWritten() async throws {
        let old = sample(), imported = sample()
        let recovery = InMemoryIslandBackupStore()
        try await recovery.beginRestore(previous: IslandBackupCodec.encode(old))
        let store = InMemoryPetStore(imported.app), arcade = InMemoryArcadeStore(imported.arcade)
        try PetHabitatStore.save(imported.sharedHabitat); try PetLifeStore.save(imported.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade, backupStore: recovery)
        await controller.bootstrap()
        XCTAssertEqual(controller.pets, old.app.pets)
        XCTAssertEqual(controller.arcadeProgress, old.arcade.progress)
        XCTAssertEqual(controller.habitat.configuration, old.habitat)
        let storedResult1 = await recovery.pendingRestore()
        XCTAssertNil(storedResult1)
    }

    func testFileJournalSurvivesNewStoreAndKeepsReturnCopyAfterCommit() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try IslandBackupCodec.encode(sample())
        let store = FileIslandBackupStore(directory: directory)
        try await store.beginRestore(previous: data)
        let reopened = FileIslandBackupStore(directory: directory)
        let storedResult6 = try await reopened.pendingRestore()
        XCTAssertEqual(storedResult6, data)
        try await reopened.finishRestore()
        let storedResult7 = try await store.pendingRestore()
        XCTAssertNil(storedResult7)
        let storedResult8 = try await reopened.recoveryBackup()
        XCTAssertEqual(storedResult8, data)
        let path = directory.appending(path: "user-backup.json")
        try data.write(to: path)
        XCTAssertEqual(try IslandBackupCodec.read(from: path), data)
    }

    @MainActor
    func testActiveLiveActivityCanBeExportedButNotReplaced() async throws {
        let original = sample()
        var app = original.app
        let session = PetSession(id: UUID(), petID: app.profile.id, startedAt: .now,
                                 endsAt: .now.addingTimeInterval(3600), snapshot: .initial(at: .now))
        app.activeSession = session
        let store = InMemoryPetStore(app)
        try PetHabitatStore.save(original.sharedHabitat); try PetLifeStore.save(original.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore(original.arcade))
        await controller.bootstrap()
        XCTAssertEqual(controller.placement, .dynamicIsland)
        XCTAssertFalse(controller.canRestoreIsland)
        let data = try await controller.exportIslandBackup()
        let exported = try IslandBackupCodec.decode(data)
        XCTAssertNil(exported.app.activeSession)
        XCTAssertNil(exported.habitat.leadDynamicIslandPetID)
        XCTAssertEqual(controller.session, session)
        do { try await controller.restoreIslandBackup(data); XCTFail("Must keep the active session") }
        catch { XCTAssertEqual(error as? IslandBackupError, .travelling) }
        XCTAssertEqual(controller.session, session)
        await controller.endSession(showSummary: false, removeImmediately: true, recordsHistory: false)
    }

    @MainActor
    func testUnreadableJournalBlocksLoadingInsteadOfPublishingMixedStores() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: directory.appending(path: "pending-restore.json"))
        let original = sample(), store = InMemoryPetStore(sample().app)
        let before = await store.load()
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore(original.arcade),
                                             backupStore: FileIslandBackupStore(directory: directory))
        await controller.bootstrap()
        XCTAssertEqual(controller.operation, .loadFailed)
        let after = await store.load()
        XCTAssertEqual(after, before)
    }

    @MainActor
    func testCannotRestoreBeforeBootstrapOrWithoutWritingReturnCopy() async throws {
        let original = sample(), current = sample()
        let store = InMemoryPetStore(current.app)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try IslandBackupCodec.encode(original)
        try PetHabitatStore.save(current.sharedHabitat); try PetLifeStore.save(current.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore(current.arcade),
                                             backupStore: FileIslandBackupStore(directory: directory))
        do { try await controller.restoreIslandBackup(data); XCTFail("Cannot replace an unloaded island") }
        catch { XCTAssertEqual(error as? IslandBackupError, .busy) }
        // A regular file where the backup folder should be simulates an unwritable destination.
        await controller.bootstrap()
        try Data().write(to: directory)
        let before = await store.load()
        do { try await controller.restoreIslandBackup(data); XCTFail("Cannot skip the return copy") }
        catch { XCTAssertFalse(error is IslandBackupError) }
        let after = await store.load()
        XCTAssertEqual(after, before)
    }

    @MainActor
    func testRealFilesRestoreAndRepeatedImportDoNotAddCoinsOrDuplicatePets() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = sample(), imported = sample()
        let store = FilePetStore(fileURL: directory.appending(path: "state.json"))
        let arcade = FileArcadeStore(fileURL: directory.appending(path: "arcade.json"))
        let recovery = FileIslandBackupStore(directory: directory.appending(path: "Backups"))
        try await store.save(original.app); try await arcade.save(original.arcade)
        try PetHabitatStore.save(original.sharedHabitat); try PetLifeStore.save(original.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade, backupStore: recovery)
        await controller.bootstrap()
        let data = try IslandBackupCodec.encode(imported)
        try await controller.restoreIslandBackup(data)
        try await controller.restoreIslandBackup(data)
        let reopened = PetSessionController(store: FilePetStore(fileURL: directory.appending(path: "state.json")),
            arcadeStore: FileArcadeStore(fileURL: directory.appending(path: "arcade.json")), backupStore: recovery)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.pets, imported.app.pets)
        XCTAssertEqual(reopened.arcadeProgress, imported.arcade.progress)
        XCTAssertEqual(reopened.settings, imported.app.settings)
        XCTAssertEqual(reopened.habitat.configuration.furniture, imported.habitat.furniture)
        XCTAssertEqual(reopened.discoveries.memories, imported.app.discoveries.memories)
        let game = try XCTUnwrap(reopened.bubblePawsCheckpoint(for: imported.app.profile.id))
        XCTAssertEqual(game, imported.arcade.bubblePawsRuns.first)
        let saved = try await recovery.pendingRestore()
        XCTAssertNil(saved)
    }

    @MainActor
    func testUncertainJournalWriteStopsFurtherChangesUntilRecovery() async throws {
        let original = sample(), store = InMemoryPetStore(sample().app)
        let recovery = UncertainBackupStore()
        // Use matching snapshots for a valid return copy.
        try await store.save(original.app)
        try PetHabitatStore.save(original.sharedHabitat); try PetLifeStore.save(original.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore(original.arcade), backupStore: recovery)
        await controller.bootstrap()
        do { try await controller.restoreIslandBackup(IslandBackupCodec.encode(sample())); XCTFail("Expected an uncertain journal write") }
        catch { XCTAssertEqual(error as? IslandBackupError, .recoveryRequired) }
        XCTAssertEqual(controller.operation, .loadFailed)
        let after = await store.load()
        XCTAssertEqual(after.pets, original.app.pets)
        await controller.bootstrap()
        XCTAssertEqual(controller.operation, .idle)
        XCTAssertEqual(controller.pets, original.app.pets)
    }

    private func modified(_ data: Data, _ mutation: (inout [String: Any]) -> Void) throws -> Data {
        var envelope = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var raw = try JSONSerialization.jsonObject(with: Data(base64Encoded: envelope["payload"] as! String)!) as! [String: Any]
        mutation(&raw)
        let payload = try JSONSerialization.data(withJSONObject: raw)
        envelope["payload"] = payload.base64EncodedString()
        envelope["checksum"] = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return try JSONSerialization.data(withJSONObject: envelope)
    }
}

private actor BackupFailingArcadeStore: ArcadeStore {
    private var state: ArcadeState
    private var failures = 0
    init(_ state: ArcadeState) { self.state = state }
    func failNextWrites(_ count: Int) { failures = count }
    func load() -> ArcadeState { state }
    func save(_ value: ArcadeState) throws {
        if failures > 0 { failures -= 1; throw CocoaError(.fileWriteUnknown) }
        state = value
    }
}

private actor UncertainBackupStore: IslandBackupStore {
    private var pending: Data?
    func pendingRestore() -> Data? { pending }
    func recoveryBackup() -> Data? { pending }
    func beginRestore(previous: Data) throws {
        pending = previous
        throw CocoaError(.fileWriteUnknown)
    }
    func finishRestore() { pending = nil }
}
