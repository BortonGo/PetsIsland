import CryptoKit
import XCTest
@testable import PetIsland

final class PetDiscoveryStoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var pet: PetProfile {
        PetProfile(id: UUID(), name: "Пиксель", species: .cat, coat: .sunrise, createdAt: start,
                   breed: .maineCoon, outfit: PetOutfit(headwear: .knitHat))
    }

    func testEachFindGetsAllThreeStoriesBeforeRepeatingAndNeverRepeatsConsecutively() throws {
        var state = PetDiscoveriesState()
        let companion = pet
        for route in PetWalkRoute.allCases {
            for index in 0..<16 {
                let time = start.addingTimeInterval(Double(index) * 86400)
                XCTAssertTrue(state.startWalk(pet: companion, route: route, at: time))
                let walk = try XCTUnwrap(state.activeWalk)
                XCTAssertEqual(walk.pet, companion)
                XCTAssertEqual(walk.endsAt.timeIntervalSince(walk.startedAt), route.duration)
                let earlier = state.memories.last { $0.discovery == walk.discovery }
                if let earlier { XCTAssertNotEqual(earlier.story, walk.story) }
                XCTAssertNotNil(state.collectWalk(at: walk.endsAt))
            }
        }
        XCTAssertEqual(Set(state.memories.map(\.storyID)).count, 36)
        for kind in PetDiscoveryKind.allCases {
            let stories = state.memories.filter { $0.discovery == kind }.prefix(3).compactMap(\.story)
            XCTAssertEqual(Set(stories), Set(PetWalkStory.allCases))
        }
    }

    func testJournalRevealsOnlyElapsedChaptersAndUsesNoWrites() throws {
        let walk = try makeWalk(story: .curious)
        XCTAssertTrue(walk.journalChapters(at: start.addingTimeInterval(-1)).isEmpty)
        XCTAssertTrue(walk.journalChapters(at: Date(timeIntervalSinceReferenceDate: .nan)).isEmpty)
        XCTAssertEqual(walk.journalChapters(at: start), [.settingOut])
        XCTAssertEqual(walk.journalChapters(at: start.addingTimeInterval(479)), [.settingOut])
        XCTAssertEqual(walk.journalChapters(at: start.addingTimeInterval(480)), [.settingOut, .exploring])
        XCTAssertEqual(walk.journalChapters(at: start.addingTimeInterval(960)), PetWalkChapter.allCases)
        XCTAssertEqual(walk.journalChapters(at: start.addingTimeInterval(86400)), PetWalkChapter.allCases)
        let before = try JSONEncoder().encode(walk)
        for index in 0..<300 { _ = walk.journalChapters(at: start.addingTimeInterval(Double(index) * 5)) }
        XCTAssertEqual(try JSONDecoder().decode(PetDiscoveryWalk.self, from: before), walk)
    }

    func testLegacyWalkAndMemoryKeepTheirOriginalTextAndNoInventedJournal() throws {
        let walk = try makeWalk(story: nil)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(walk)) as? [String: Any])
        raw["story"] = nil
        let decoded = try JSONDecoder().decode(PetDiscoveryWalk.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(decoded.story)
        XCTAssertTrue(decoded.journalChapters(at: decoded.endsAt).isEmpty)
        let original = PetDiscoveryMemory(walk: decoded)
        let memory = try JSONDecoder().decode(PetDiscoveryMemory.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(memory.storyText, memory.discovery.discoveryStory(petName: memory.pet.name))
        XCTAssertNil(memory.story)
        var state = PetDiscoveriesState(memories: [memory])
        for _ in 0..<4 {
            state.startWalk(pet: decoded.pet, route: .garden, at: start)
            let next = try XCTUnwrap(state.activeWalk)
            if next.discovery == .stripedPebble { XCTAssertEqual(next.story, .curious) }
            state.collectWalk(at: next.endsAt)
        }
    }

    func testStoriesSurviveReloadDelayedCollectionAndCancellation() throws {
        let companion = pet
        var state = PetDiscoveriesState()
        state.startWalk(pet: companion, route: .shore, at: start)
        let original = try XCTUnwrap(state.activeWalk)
        state = try JSONDecoder().decode(PetDiscoveriesState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(state.activeWalk, original)
        let memory = try XCTUnwrap(state.collectWalk(at: start.addingTimeInterval(86400)))
        XCTAssertEqual(memory.story, original.story)
        XCTAssertEqual(memory.foundAt, original.endsAt)
        XCTAssertEqual(memory.pet, companion)
        XCTAssertEqual(memory.shareText, "\(memory.discovery.discoveryTitle)\n\(memory.storyText)")
        state.startWalk(pet: companion, route: .shore, at: start)
        let cancelled = try XCTUnwrap(state.activeWalk)
        XCTAssertTrue(state.cancelWalk())
        XCTAssertEqual(state.memories, [memory])
        state.startWalk(pet: companion, route: .shore, at: start)
        XCTAssertEqual(state.activeWalk?.story, cancelled.story)
        XCTAssertEqual(state.activeWalk?.discovery, cancelled.discovery)
        XCTAssertNil(state.collectWalk(at: start))
    }

    func testAllStoriesAndJournalNotesAreDistinctAndShareTheDisplayedText() throws {
        for kind in PetDiscoveryKind.allCases {
            let companion = pet
            let stories = try PetWalkStory.allCases.map { story in
                let walk = try XCTUnwrap(PetDiscoveryWalk(pet: companion, route: kind.discoveryRoute, startedAt: start,
                    endsAt: start.addingTimeInterval(kind.discoveryRoute.duration), discovery: kind, story: story))
                let memory = PetDiscoveryMemory(walk: walk)
                XCTAssertTrue(memory.storyText.contains(companion.name))
                XCTAssertTrue(memory.shareText.contains(memory.storyText))
                return memory.storyText
            }
            XCTAssertEqual(Set(stories).count, 3, kind.rawValue)
        }
        let notes = PetWalkRoute.allCases.flatMap { route in
            PetWalkStory.allCases.flatMap { story in PetWalkChapter.allCases.map { story.note(on: route, chapter: $0) } }
        }
        XCTAssertEqual(Set(notes).count, 27)
        XCTAssertTrue(notes.allSatisfy { !$0.isEmpty && !$0.contains("%@") })
    }

    func testStoryMetadataCannotChangePositionsGaitTimingOrCompanionAppearance() throws {
        for species in PetSpecies.allCases {
            var companion = pet
            companion.species = species; companion.breed = PetBreed.available(for: species).first
            for route in PetWalkRoute.allCases {
                let id = UUID()
                let old = try XCTUnwrap(PetDiscoveryWalk(id: id, pet: companion, route: route, startedAt: start,
                    endsAt: start.addingTimeInterval(route.duration), discovery: route.discoveryIDs[0]))
                for story in PetWalkStory.allCases {
                    let new = try XCTUnwrap(PetDiscoveryWalk(id: id, pet: companion, route: route, startedAt: start,
                        endsAt: old.endsAt, discovery: old.discovery, story: story))
                    XCTAssertEqual(new.pet, old.pet)
                    for fraction in [0.0, 0.01, 0.4, 0.7, 0.99, 1, 2] {
                        let date = start.addingTimeInterval(route.duration * fraction)
                        XCTAssertEqual(PetDiscoveryScenePlan(walk: new).frame(at: date), PetDiscoveryScenePlan(walk: old).frame(at: date))
                    }
                }
            }
        }
    }

    func testUnknownStoryIsRejectedAndOldBackupVersionsStillOpen() throws {
        let walk = try makeWalk(story: .quiet)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(walk)) as? [String: Any])
        raw["story"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(PetDiscoveryWalk.self, from: JSONSerialization.data(withJSONObject: raw)))
        var app = PersistedAppState()
        app.pets = [walk.pet]; app.activePetIDs = [walk.pet.id]; app.completedOnboarding = true
        app.discoveries = PetDiscoveriesState(activeWalk: walk)
        var arcade = ArcadeState(progress: ArcadeProgress(ownedAccessories: [.knitHat]))
        arcade.bondsByPetID[walk.pet.id, default: PetBond()].shareAttention(at: start)
        let backup = IslandBackup(app: app, arcade: arcade, habitat: PetHabitatState(residentPetIDs: [walk.pet.id]))
        let data = try IslandBackupCodec.encode(backup)
        XCTAssertEqual(try IslandBackupCodec.decode(data).app.discoveries.activeWalk, walk)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["version"] as? Int, 3)
        let originalPayload = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(envelope["payload"] as? String)))
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: originalPayload) as? [String: Any])
        var oldApp = payload["app"] as! [String: Any]
        var discoveries = oldApp["discoveries"] as! [String: Any]
        var oldWalk = discoveries["activeWalk"] as! [String: Any]
        oldWalk["story"] = nil; discoveries["activeWalk"] = oldWalk; oldApp["discoveries"] = discoveries; payload["app"] = oldApp
        for version in [1, 2] {
            let bytes = try JSONSerialization.data(withJSONObject: payload)
            envelope["version"] = version; envelope["payload"] = bytes.base64EncodedString()
            envelope["checksum"] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            let decoded = try IslandBackupCodec.decode(JSONSerialization.data(withJSONObject: envelope))
            XCTAssertNil(decoded.app.discoveries.activeWalk?.story)
            XCTAssertEqual(decoded.app.pets, backup.app.pets)
            XCTAssertEqual(decoded.arcade, arcade)
        }
    }

    @MainActor
    func testFailedCollectionAndRepeatedTapKeepOnePersistedStoryAndOriginalPets() async throws {
        let walk = try makeWalk(story: .curious)
        var app = PersistedAppState()
        app.pets = [walk.pet]; app.activePetIDs = [walk.pet.id]; app.completedOnboarding = true
        app.discoveries = PetDiscoveriesState(activeWalk: walk)
        let store = StoryFailingStore(app)
        let arcadeState = ArcadeState(progress: ArcadeProgress(coins: 50, ownedAccessories: [.knitHat]))
        let arcade = InMemoryArcadeStore(arcadeState)
        let island = IslandBackup(app: app, arcade: arcadeState, habitat: PetHabitatState(residentPetIDs: [walk.pet.id]))
        try PetHabitatStore.save(island.sharedHabitat)
        try PetLifeStore.save(island.sharedLife)
        let controller = PetSessionController(store: store, arcadeStore: arcade)
        await controller.bootstrap()
        await store.failNextWrite()
        let failed = await controller.collectDiscoveryWalk(at: walk.endsAt)
        XCTAssertNil(failed)
        XCTAssertEqual(controller.discoveries.activeWalk, walk)
        XCTAssertTrue(controller.discoveries.memories.isEmpty)
        let memory = await controller.collectDiscoveryWalk(at: walk.endsAt)
        let repeated = await controller.collectDiscoveryWalk(at: walk.endsAt)
        XCTAssertEqual(memory?.story, .curious)
        XCTAssertNil(repeated)
        let reopened = PetSessionController(store: store, arcadeStore: arcade)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.discoveries.memories, [try XCTUnwrap(memory)])
        XCTAssertEqual(reopened.pets, app.pets)
        XCTAssertEqual(reopened.arcadeProgress.coins, 50)
        let backup: Data
        do { backup = try await reopened.exportIslandBackup() }
        catch { XCTFail("Story export failed: \(error)"); return }
        do { try await reopened.restoreIslandBackup(backup) }
        catch { XCTFail("Story restore failed: \(error)"); return }
        XCTAssertEqual(reopened.discoveries.memories, [try XCTUnwrap(memory)])
    }

    func testFileSaveRetainsStorySelectionAndPetSnapshot() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "state.json")
        var state = PersistedAppState()
        let walk = try makeWalk(story: .quiet)
        state.discoveries = PetDiscoveriesState(activeWalk: walk)
        try await FilePetStore(fileURL: file).save(state)
        let loaded = try await FilePetStore(fileURL: file).load()
        XCTAssertEqual(loaded.discoveries.activeWalk, walk)
        var collected = loaded
        let memory = try XCTUnwrap(collected.discoveries.collectWalk(at: walk.endsAt))
        try await FilePetStore(fileURL: file).save(collected)
        let reloaded = try await FilePetStore(fileURL: file).load()
        XCTAssertEqual(reloaded.discoveries.memories, [memory])
    }

    private func makeWalk(story: PetWalkStory?) throws -> PetDiscoveryWalk {
        try XCTUnwrap(PetDiscoveryWalk(pet: pet, route: .garden, startedAt: start,
            endsAt: start.addingTimeInterval(1200), discovery: .stripedPebble, story: story))
    }
}

private actor StoryFailingStore: PetStore {
    private var state: PersistedAppState
    private var fails = false
    init(_ state: PersistedAppState) { self.state = state }
    func failNextWrite() { fails = true }
    func load() -> PersistedAppState { state }
    func save(_ state: PersistedAppState) throws {
        if fails { fails = false; throw CocoaError(.fileWriteUnknown) }
        self.state = state
    }
}
