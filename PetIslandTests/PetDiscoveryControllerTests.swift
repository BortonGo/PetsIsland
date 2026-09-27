import XCTest
@testable import PetIsland

final class PetDiscoveryControllerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    @MainActor
    func testDiscoveryMutationsBeforeBootstrapDoNotReplaceSavedWalk() async {
        var initial = makeState()
        initial.discoveries.startWalk(pet: initial.profile, route: .garden, at: start)
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())

        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .shore, at: start)
        let collected = await controller.collectDiscoveryWalk(at: start.addingTimeInterval(3_600))
        let cancelled = await controller.cancelDiscoveryWalk()

        XCTAssertFalse(started)
        XCTAssertNil(collected)
        XCTAssertFalse(cancelled)
        let unchanged = await store.load()
        XCTAssertEqual(unchanged, initial)

        await controller.bootstrap()
        XCTAssertEqual(controller.discoveries, initial.discoveries)
    }

    @MainActor
    func testFailedBootstrapBlocksDiscoveryMutationsUntilSuccessfulRetry() async {
        let initial = makeState()
        let store = DiscoveryTestStore(initial)
        await store.setLoadFailure(true)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()

        XCTAssertEqual(controller.operation, .loadFailed)
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)
        let collected = await controller.collectDiscoveryWalk(at: start.addingTimeInterval(3_600))
        let cancelled = await controller.cancelDiscoveryWalk()
        XCTAssertFalse(started)
        XCTAssertNil(collected)
        XCTAssertFalse(cancelled)
        let unchanged = await store.snapshot()
        XCTAssertEqual(unchanged, initial)

        await store.setLoadFailure(false)
        await controller.bootstrap()
        let retried = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)
        XCTAssertTrue(retried)
    }

    @MainActor
    func testStartingWalkRejectsUnknownAndRemovedPets() async {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()

        let unknown = await controller.startDiscoveryWalk(petID: UUID(), route: .garden, at: start)
        XCTAssertFalse(unknown)
        XCTAssertNil(controller.discoveries.activeWalk)

        let removedPetID = initial.pets[1].id
        let removed = await controller.removePet(id: removedPetID)
        XCTAssertTrue(removed)
        let before = await store.load()
        let rejected = await controller.startDiscoveryWalk(petID: removedPetID, route: .garden, at: start)
        XCTAssertFalse(rejected)
        let after = await store.load()
        XCTAssertEqual(after, before)
        XCTAssertNil(controller.discoveries.activeWalk)
    }

    @MainActor
    func testPendingWalkRejectsSecondWalkAndPrematureCollection() async throws {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()

        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)
        let before = await store.load()

        let second = await controller.startDiscoveryWalk(petID: initial.pets[1].id, route: .shore, at: start)
        let early = await controller.collectDiscoveryWalk(at: walk.endsAt.addingTimeInterval(-1))
        XCTAssertFalse(second)
        XCTAssertNil(early)
        XCTAssertEqual(controller.discoveries.activeWalk, walk)
        XCTAssertTrue(controller.discoveries.memories.isEmpty)
        let after = await store.load()
        XCTAssertEqual(after, before)
    }

    @MainActor
    func testFailedStartSaveKeepsOldStateAndAllowsRetry() async {
        let initial = makeState()
        let store = DiscoveryTestStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let before = await store.snapshot()
        await store.setSaveFailure(true)

        let failed = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)

        XCTAssertFalse(failed)
        XCTAssertEqual(controller.discoveries, before.discoveries)
        XCTAssertNotNil(controller.alertMessage)
        XCTAssertFalse(controller.isSavingChanges)
        let savedAfterFailure = await store.snapshot()
        XCTAssertEqual(savedAfterFailure, before)

        await store.setSaveFailure(false)
        let retried = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)
        XCTAssertTrue(retried)
        let saved = await store.snapshot()
        XCTAssertEqual(controller.discoveries, saved.discoveries)
        XCTAssertEqual(saved.discoveries.activeWalk?.pet, initial.profile)
    }

    @MainActor
    func testFailedCollectionSaveKeepsRewardAvailableForExactlyOneRetry() async throws {
        let initial = makeState()
        let store = DiscoveryTestStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)
        let before = await store.snapshot()
        await store.setSaveFailure(true)

        let failed = await controller.collectDiscoveryWalk(at: walk.endsAt)

        XCTAssertNil(failed)
        XCTAssertEqual(controller.discoveries, before.discoveries)
        XCTAssertFalse(controller.isSavingChanges)
        let savedAfterFailure = await store.snapshot()
        XCTAssertEqual(savedAfterFailure, before)

        await store.setSaveFailure(false)
        let retried = await controller.collectDiscoveryWalk(at: walk.endsAt.addingTimeInterval(60))
        XCTAssertEqual(retried?.id, walk.id)
        XCTAssertEqual(retried?.discovery, walk.discovery)
        XCTAssertNil(controller.discoveries.activeWalk)
        XCTAssertEqual(controller.discoveries.memories.count, 1)
        let duplicate = await controller.collectDiscoveryWalk(at: walk.endsAt.addingTimeInterval(120))
        XCTAssertNil(duplicate)
        let saved = await store.snapshot()
        XCTAssertEqual(saved.discoveries, controller.discoveries)
        XCTAssertEqual(saved.discoveries.memories.count, 1)
    }

    @MainActor
    func testFailedCancellationSavePreservesWalkAndRetryKeepsAlbum() async throws {
        var initial = makeState()
        initial.discoveries.startWalk(pet: initial.profile, route: .garden, at: start)
        initial.discoveries.collectWalk(at: start.addingTimeInterval(3_600))
        let store = DiscoveryTestStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .shore, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)
        let before = await store.snapshot()
        await store.setSaveFailure(true)

        let failed = await controller.cancelDiscoveryWalk()

        XCTAssertFalse(failed)
        XCTAssertEqual(controller.discoveries.activeWalk, walk)
        let savedAfterFailure = await store.snapshot()
        XCTAssertEqual(savedAfterFailure, before)

        await store.setSaveFailure(false)
        let retried = await controller.cancelDiscoveryWalk()
        XCTAssertTrue(retried)
        XCTAssertNil(controller.discoveries.activeWalk)
        XCTAssertEqual(controller.discoveries.memories, initial.discoveries.memories)
        let saved = await store.snapshot()
        XCTAssertEqual(saved.discoveries, controller.discoveries)
        let alreadyCancelled = await controller.cancelDiscoveryWalk()
        XCTAssertFalse(alreadyCancelled)
    }

    @MainActor
    func testReopeningRestoresPendingWalkAndThenCollectedAlbum() async throws {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let arcadeStore = InMemoryArcadeStore()
        let first = PetSessionController(store: store, arcadeStore: arcadeStore)
        await first.bootstrap()
        let started = await first.startDiscoveryWalk(petID: initial.profile.id, route: .shore, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(first.discoveries.activeWalk)

        let reopened = PetSessionController(store: store, arcadeStore: arcadeStore)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.discoveries.activeWalk, walk)
        let memory = await reopened.collectDiscoveryWalk(at: walk.endsAt.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(memory?.id, walk.id)
        XCTAssertEqual(memory?.foundAt, walk.endsAt)

        let reopenedAgain = PetSessionController(store: store, arcadeStore: arcadeStore)
        await reopenedAgain.bootstrap()
        XCTAssertNil(reopenedAgain.discoveries.activeWalk)
        XCTAssertEqual(reopenedAgain.discoveries.memories, [try XCTUnwrap(memory)])
    }

    @MainActor
    func testWalkRetainsOriginalPetSnapshotAfterRenameAndRemoval() async throws {
        let initial = makeState()
        let originalPet = initial.pets[1]
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let started = await controller.startDiscoveryWalk(petID: originalPet.id, route: .grove, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)

        var renamed = originalPet
        renamed.name = "New name"
        renamed.coat = .midnight
        let updated = await controller.updatePet(renamed)
        XCTAssertTrue(updated)
        XCTAssertEqual(controller.discoveries.activeWalk?.pet, originalPet)
        let removed = await controller.removePet(id: originalPet.id)
        XCTAssertTrue(removed)

        let memory = await controller.collectDiscoveryWalk(at: walk.endsAt)

        XCTAssertEqual(memory?.pet, originalPet)
        XCTAssertEqual(memory?.id, walk.id)
        XCTAssertFalse(controller.pets.contains(where: { $0.id == originalPet.id }))
        let saved = await store.load()
        XCTAssertEqual(saved.discoveries.memories.first?.pet, originalPet)
        XCTAssertFalse(saved.pets.contains(where: { $0.id == originalPet.id }))
    }

    @MainActor
    func testConcurrentCollectionPublishesOnlyAfterSavingAndCreatesOneMemory() async throws {
        let initial = makeState()
        let store = DiscoveryTestStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)
        let before = controller.discoveries
        await store.pauseNextSave()

        let first = Task { await controller.collectDiscoveryWalk(at: walk.endsAt) }
        await store.waitForPausedSave()
        XCTAssertTrue(controller.isSavingChanges)
        XCTAssertEqual(controller.discoveries, before, "The reward must not appear before its save succeeds.")
        let duringSave = await store.snapshot()
        XCTAssertEqual(duringSave.discoveries, before)
        let second = Task { await controller.collectDiscoveryWalk(at: walk.endsAt) }
        await store.resumeSave()
        let results = await [first.value, second.value]

        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        XCTAssertEqual(controller.discoveries.memories.map(\.id), [walk.id])
        XCTAssertNil(controller.discoveries.activeWalk)
        XCTAssertFalse(controller.isSavingChanges)
        let saved = await store.snapshot()
        XCTAssertEqual(saved.discoveries, controller.discoveries)
    }

    @MainActor
    func testDiscoveryLifecyclePreservesPetsHabitatArcadeAndLiveActivitySettings() async throws {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let arcadeStore = InMemoryArcadeStore(ArcadeState(
            progress: ArcadeProgress(coins: 137, totalScore: 420, gamesPlayed: 3),
            vitalsByPetID: Dictionary(uniqueKeysWithValues: initial.pets.map {
                ($0.id, PetVitals(fullness: 0.45, happiness: 0.67, energy: 0.81))
            })
        ))
        let controller = PetSessionController(store: store, arcadeStore: arcadeStore)
        await controller.bootstrap()
        let before = await store.load()
        let arcadeBefore = await arcadeStore.load()
        let profileBefore = controller.profile
        let petsBefore = controller.pets
        let partyBefore = controller.activeParty
        let activeIDsBefore = controller.activePetIDs
        let sessionBefore = controller.session
        let connectionBefore = controller.liveActivityConnection
        let placementBefore = controller.placement
        let lifeBefore = controller.lifeState
        let habitatBefore = controller.habitat
        let vitalsBefore = controller.vitals(for: profileBefore.id, at: start)

        let started = await controller.startDiscoveryWalk(petID: initial.pets[1].id, route: .garden, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)
        let collected = await controller.collectDiscoveryWalk(at: walk.endsAt)
        XCTAssertNotNil(collected)
        let nextStarted = await controller.startDiscoveryWalk(petID: profileBefore.id, route: .grove, at: walk.endsAt)
        XCTAssertTrue(nextStarted)
        let cancelled = await controller.cancelDiscoveryWalk()
        XCTAssertTrue(cancelled)

        var after = await store.load()
        after.discoveries = before.discoveries
        XCTAssertEqual(after, before, "Only discovery data should change in the collection save.")
        let arcadeAfter = await arcadeStore.load()
        XCTAssertEqual(arcadeAfter, arcadeBefore)
        XCTAssertEqual(controller.arcadeProgress, arcadeBefore.progress)
        XCTAssertEqual(controller.profile, profileBefore)
        XCTAssertEqual(controller.pets, petsBefore)
        XCTAssertEqual(controller.activeParty, partyBefore)
        XCTAssertEqual(controller.activePetIDs, activeIDsBefore)
        XCTAssertEqual(controller.settings, before.settings)
        XCTAssertEqual(controller.session, sessionBefore)
        XCTAssertEqual(controller.liveActivityConnection, connectionBefore)
        XCTAssertEqual(controller.placement, placementBefore)
        XCTAssertEqual(controller.lifeState, lifeBefore)
        XCTAssertEqual(controller.habitat, habitatBefore)
        XCTAssertEqual(controller.vitals(for: profileBefore.id, at: start), vitalsBefore)
    }

    @MainActor
    func testDiscoveryWalkTemporarilyHidesOnlyTheSelectedResident() async throws {
        let initial = makeState()
        let controller = PetSessionController(store: InMemoryPetStore(initial), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))
        let configuration = controller.habitat.configuration
        let residentIDs = controller.habitatResidents.map(\.id)
        let now = Date.now
        let walkerID = initial.pets[1].id

        let started = await controller.startDiscoveryWalk(petID: walkerID, route: .garden, at: now)

        XCTAssertTrue(started)
        XCTAssertTrue(controller.isPetOnDiscoveryWalk(walkerID, at: now))
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        XCTAssertEqual(controller.habitatResidents.map(\.id), residentIDs.filter { $0 != walkerID })
        XCTAssertEqual(controller.habitat.visibleResidents(at: now).map(\.id), residentIDs.filter { $0 != walkerID })
        XCTAssertTrue(controller.habitat.isPetAway(walkerID, at: now))
        XCTAssertEqual(controller.habitat.configuration, configuration,
                       "A temporary absence must not remove the pet from the owner's enclosure selection.")
        XCTAssertEqual(controller.pets, initial.pets)
        XCTAssertEqual(controller.activePetIDs, initial.activePetIDs)
        XCTAssertEqual(controller.habitat.residents.map(\.profile), initial.pets)
    }

    @MainActor
    func testFailedWalkSaveDoesNotHideResident() async {
        let initial = makeState()
        let store = DiscoveryTestStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))
        let habitatBefore = controller.habitat
        let residentsBefore = controller.habitatResidents
        let now = Date.now
        await store.setSaveFailure(true)

        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: now)

        XCTAssertFalse(started)
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        XCTAssertFalse(controller.habitat.isPetAway(initial.profile.id, at: now))
        XCTAssertEqual(controller.habitatResidents, residentsBefore)
        XCTAssertEqual(controller.habitat, habitatBefore)
        XCTAssertNil(controller.discoveries.activeWalk)
    }

    @MainActor
    func testCancellingWalkReturnsResidentOnlyAfterSuccessfulSave() async {
        let initial = makeState()
        let store = DiscoveryTestStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))
        let configuration = controller.habitat.configuration
        let residentsBefore = controller.habitatResidents
        let now = Date.now
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: now)
        XCTAssertTrue(started)
        await store.setSaveFailure(true)

        let failed = await controller.cancelDiscoveryWalk()

        XCTAssertFalse(failed)
        XCTAssertTrue(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        XCTAssertFalse(controller.habitatResidents.contains { $0.id == initial.profile.id })

        await store.setSaveFailure(false)
        let cancelled = await controller.cancelDiscoveryWalk()

        XCTAssertTrue(cancelled)
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        XCTAssertEqual(controller.habitatResidents, residentsBefore)
        XCTAssertEqual(controller.habitat.visibleResidents(at: now).map(\.id), residentsBefore.map(\.id))
        XCTAssertEqual(controller.habitat.configuration, configuration)
        XCTAssertTrue(controller.discoveries.memories.isEmpty)
    }

    @MainActor
    func testReopeningPendingWalkKeepsResidentAwayAndCancellationReturnsIt() async throws {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let arcadeStore = InMemoryArcadeStore()
        let first = PetSessionController(store: store, arcadeStore: arcadeStore)
        await first.bootstrap()
        XCTAssertTrue(first.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))
        let configuration = first.habitat.configuration
        let now = Date.now
        let started = await first.startDiscoveryWalk(petID: initial.profile.id, route: .shore, at: now)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(first.discoveries.activeWalk)

        let reopened = PetSessionController(store: store, arcadeStore: arcadeStore)
        await reopened.bootstrap()

        XCTAssertEqual(reopened.discoveries.activeWalk, walk)
        XCTAssertTrue(reopened.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        XCTAssertFalse(reopened.habitatResidents.contains { $0.id == initial.profile.id })
        XCTAssertFalse(reopened.habitat.visibleResidents(at: now).contains { $0.id == initial.profile.id })
        XCTAssertTrue(reopened.habitatResidents.contains { $0.id == initial.pets[1].id })
        XCTAssertEqual(reopened.habitat.configuration, configuration)

        let cancelled = await reopened.cancelDiscoveryWalk()
        XCTAssertTrue(cancelled)
        XCTAssertEqual(reopened.habitatResidents.map(\.id), initial.pets.map(\.id))
        XCTAssertEqual(reopened.habitat.configuration, configuration)
    }

    @MainActor
    func testCompletedWalkReturnsResidentWithoutCollectingTheMemory() async throws {
        let now = Date.now
        var initial = makeState()
        initial.discoveries.startWalk(pet: initial.profile, route: .garden,
                                      at: now.addingTimeInterval(-PetWalkRoute.garden.duration - 60))
        let walk = try XCTUnwrap(initial.discoveries.activeWalk)
        let controller = PetSessionController(store: InMemoryPetStore(initial), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))

        XCTAssertTrue(controller.isPetOnDiscoveryWalk(initial.profile.id, at: walk.endsAt.addingTimeInterval(-1)))
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: walk.endsAt))
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        XCTAssertFalse(controller.habitatResidents(at: walk.endsAt.addingTimeInterval(-1)).contains {
            $0.id == initial.profile.id
        })
        XCTAssertTrue(controller.habitatResidents(at: walk.endsAt).contains { $0.id == initial.profile.id })
        XCTAssertFalse(controller.habitat.visibleResidents(at: walk.endsAt.addingTimeInterval(-1)).contains {
            $0.id == initial.profile.id
        })
        XCTAssertTrue(controller.habitat.visibleResidents(at: walk.endsAt).contains { $0.id == initial.profile.id })
        XCTAssertTrue(controller.habitatResidents.contains { $0.id == initial.profile.id })
        XCTAssertEqual(controller.discoveries.activeWalk, walk)
        XCTAssertTrue(controller.discoveries.memories.isEmpty,
                      "Returning to the enclosure and collecting the keepsake are separate actions.")
    }

    @MainActor
    func testWalkingPetCannotEnterDynamicIslandThroughEitherEntryPoint() async {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))
        let now = Date.now
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: now)
        XCTAssertTrue(started)
        let before = await store.load()
        let habitatBefore = controller.habitat
        let placementBefore = controller.placement
        let connectionBefore = controller.liveActivityConnection

        await controller.placePet(in: .dynamicIsland)
        await controller.startSession(duration: 1_200)

        XCTAssertNil(controller.session)
        XCTAssertEqual(controller.operation, .idle)
        XCTAssertEqual(controller.placement, placementBefore)
        XCTAssertEqual(controller.liveActivityConnection, connectionBefore)
        XCTAssertEqual(controller.habitat, habitatBefore)
        let after = await store.load()
        XCTAssertEqual(after, before)
        XCTAssertTrue(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
    }

    @MainActor
    func testEditingHabitatDuringWalkRetainsTheWalkersReservedSlot() async {
        let initial = makeState()
        let controller = PetSessionController(store: InMemoryPetStore(initial), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .starryNight, residentPetIDs: initial.pets.map(\.id)))
        let started = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: .now)
        XCTAssertTrue(started)

        XCTAssertTrue(controller.saveHabitat(theme: .sunnyMeadow, residentPetIDs: [initial.pets[1].id]))

        XCTAssertEqual(Set(controller.habitat.configuration.residentPetIDs), Set(initial.pets.map(\.id)))
        XCTAssertEqual(controller.habitat.configuration.theme, .sunnyMeadow)
        XCTAssertEqual(controller.habitatResidents.map(\.id), [initial.pets[1].id])
        let cancelled = await controller.cancelDiscoveryWalk()
        XCTAssertTrue(cancelled)
        XCTAssertEqual(Set(controller.habitatResidents.map(\.id)), Set(initial.pets.map(\.id)))
        XCTAssertEqual(controller.habitatResidents.count, initial.pets.count)
    }

    @MainActor
    func testPetCannotBeRemovedUntilItsWalkHasReturnedOrBeenCancelled() async {
        let initial = makeState()
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let walker = initial.pets[1]
        let started = await controller.startDiscoveryWalk(petID: walker.id, route: .garden, at: .now)
        XCTAssertTrue(started)
        let before = await store.load()

        let rejected = await controller.removePet(id: walker.id)

        XCTAssertFalse(rejected)
        XCTAssertTrue(controller.pets.contains { $0.id == walker.id })
        let rejectedState = await store.load()
        XCTAssertEqual(rejectedState, before)
        let cancelled = await controller.cancelDiscoveryWalk()
        XCTAssertTrue(cancelled)
        let removed = await controller.removePet(id: walker.id)
        XCTAssertTrue(removed)
    }

    @MainActor
    func testDynamicIslandPetCannotWalkWhileAnotherPetStillCan() async throws {
        let now = Date.now
        var initial = makeState()
        let savedSession = PetSession(
            id: UUID(), petID: initial.profile.id, startedAt: now,
            endsAt: now.addingTimeInterval(3_600), snapshot: .initial(at: now)
        )
        initial.activeSession = savedSession
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        // Bootstrap restores the saved session without requesting a new system activity.
        await controller.bootstrap()
        XCTAssertEqual(controller.session, savedSession)
        XCTAssertEqual(controller.placement, .dynamicIsland)
        XCTAssertEqual(controller.availableDiscoveryPets.map(\.id), [initial.pets[1].id])
        let before = await store.load()

        let rejected = await controller.startDiscoveryWalk(petID: initial.profile.id, route: .garden, at: now)

        XCTAssertFalse(rejected)
        XCTAssertNil(controller.discoveries.activeWalk)
        let rejectedState = await store.load()
        XCTAssertEqual(rejectedState, before)

        let otherStarted = await controller.startDiscoveryWalk(petID: initial.pets[1].id, route: .garden, at: now)
        XCTAssertTrue(otherStarted)
        XCTAssertEqual(controller.session, savedSession)
        XCTAssertEqual(controller.placement, .dynamicIsland)
        XCTAssertEqual(controller.settings, before.settings)
        XCTAssertTrue(controller.isPetOnDiscoveryWalk(initial.pets[1].id, at: now))
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))

        await controller.endSession(showSummary: false, removeImmediately: true, recordsHistory: false)
    }

    @MainActor
    func testBootstrapResolvesLegacyWalkAndDynamicIslandConflictWithoutLosingFind() async throws {
        let now = Date.now
        var initial = makeState()
        initial.discoveries.startWalk(pet: initial.profile, route: .garden, at: now)
        let walk = try XCTUnwrap(initial.discoveries.activeWalk)
        initial.activeSession = PetSession(
            id: UUID(), petID: initial.profile.id, startedAt: now,
            endsAt: now.addingTimeInterval(3_600), snapshot: .initial(at: now)
        )
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())

        await controller.bootstrap()

        XCTAssertNil(controller.session)
        XCTAssertEqual(controller.operation, .idle)
        XCTAssertEqual(controller.placement, .enclosure)
        XCTAssertNil(controller.habitat.configuration.leadDynamicIslandPetID)
        XCTAssertTrue(controller.habitat.configuration.residentPetIDs.contains(walk.pet.id))
        XCTAssertFalse(controller.habitatResidents.contains { $0.id == walk.pet.id })
        XCTAssertEqual(controller.discoveries.activeWalk, walk)
        XCTAssertEqual(controller.discoveries.memories, initial.discoveries.memories)
        XCTAssertEqual(controller.pets, initial.pets)
        XCTAssertEqual(controller.history, initial.history)
        XCTAssertEqual(controller.settings, initial.settings)
        let saved = await store.load()
        XCTAssertNil(saved.activeSession)
        XCTAssertEqual(saved.discoveries, initial.discoveries)
        XCTAssertEqual(saved.history, initial.history)
        let memory = await controller.collectDiscoveryWalk(at: walk.endsAt)
        XCTAssertEqual(memory?.id, walk.id)
        XCTAssertEqual(memory?.discovery, walk.discovery)
    }

    @MainActor
    func testBootstrapPreservesNonconflictingDynamicIslandSessionAndWalk() async throws {
        let now = Date.now
        var initial = makeState()
        initial.discoveries.startWalk(pet: initial.pets[1], route: .shore, at: now)
        let walk = try XCTUnwrap(initial.discoveries.activeWalk)
        let savedSession = PetSession(
            id: UUID(), petID: initial.profile.id, startedAt: now,
            endsAt: now.addingTimeInterval(3_600), snapshot: .initial(at: now)
        )
        initial.activeSession = savedSession
        let store = InMemoryPetStore(initial)
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())

        await controller.bootstrap()

        XCTAssertEqual(controller.session, savedSession)
        XCTAssertEqual(controller.operation, .active)
        XCTAssertEqual(controller.placement, .dynamicIsland)
        XCTAssertEqual(controller.habitat.configuration.leadDynamicIslandPetID, initial.profile.id)
        XCTAssertEqual(controller.discoveries.activeWalk, walk)
        XCTAssertTrue(controller.isPetOnDiscoveryWalk(walk.pet.id, at: now))
        XCTAssertFalse(controller.isPetOnDiscoveryWalk(initial.profile.id, at: now))
        let saved = await store.load()
        XCTAssertEqual(saved.activeSession, savedSession)
        XCTAssertEqual(saved.discoveries, initial.discoveries)
        XCTAssertEqual(saved.history, initial.history)

        await controller.endSession(showSummary: false, removeImmediately: true, recordsHistory: false)
    }

    @MainActor
    func testTakingOutsidePetToDynamicIslandDoesNotEvictWalkingResidentAtCapacity() async throws {
        let now = Date.now
        var initial = makeState()
        initial.pets = (0...PetHabitatState.maximumResidents).map { index in
            PetProfile(id: UUID(), name: "Resident \(index)", species: .cat, coat: .sunrise,
                       createdAt: start, breed: .classicCat)
        }
        initial.activePetIDs = [initial.pets[0].id]
        let residentIDs = Array(initial.pets.prefix(PetHabitatState.maximumResidents)).map(\.id)
        let walkerID = try XCTUnwrap(residentIDs.last)
        let outsidePet = try XCTUnwrap(initial.pets.last)
        let store = InMemoryPetStore(initial)
        let arcadeStore = InMemoryArcadeStore()
        let first = PetSessionController(store: store, arcadeStore: arcadeStore)
        await first.bootstrap()
        XCTAssertTrue(first.saveHabitat(theme: .starryNight, residentPetIDs: residentIDs))
        let started = await first.startDiscoveryWalk(petID: walkerID, route: .garden, at: now)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(first.discoveries.activeWalk)

        // Restore another pet's saved DI session against the existing full habitat.
        // This exercises the same slot reservation without requesting an activity.
        var saved = await store.load()
        saved.activePetIDs = [outsidePet.id]
        saved.activeSession = PetSession(
            id: UUID(), petID: outsidePet.id, startedAt: now,
            endsAt: now.addingTimeInterval(3_600), snapshot: .initial(at: now)
        )
        try await store.save(saved)
        let reopened = PetSessionController(store: store, arcadeStore: arcadeStore)

        await reopened.bootstrap()

        XCTAssertEqual(reopened.session?.petID, outsidePet.id)
        XCTAssertEqual(reopened.habitat.configuration.leadDynamicIslandPetID, outsidePet.id)
        XCTAssertEqual(reopened.habitat.configuration.residentPetIDs.count, PetHabitatState.maximumResidents - 1)
        XCTAssertTrue(reopened.habitat.configuration.residentPetIDs.contains(walkerID))
        XCTAssertTrue(reopened.habitat.residents.contains { $0.id == walkerID })
        XCTAssertFalse(reopened.habitatResidents.contains { $0.id == walkerID })
        XCTAssertTrue(reopened.habitatResidents(at: walk.endsAt).contains { $0.id == walkerID })
        XCTAssertEqual(reopened.discoveries.activeWalk, walk)
        XCTAssertEqual(reopened.pets, initial.pets)

        await reopened.endSession(showSummary: false, removeImmediately: true, recordsHistory: false)
        XCTAssertTrue(reopened.habitat.configuration.residentPetIDs.contains(walkerID))
        XCTAssertTrue(reopened.habitat.configuration.residentPetIDs.contains(outsidePet.id))
        let cancelled = await reopened.cancelDiscoveryWalk()
        XCTAssertTrue(cancelled)
        XCTAssertTrue(reopened.habitatResidents.contains { $0.id == walkerID })
    }

    private func makeState() -> PersistedAppState {
        let pets = [
            PetProfile(id: UUID(), name: "Mochi", species: .cat, coat: .sunrise,
                       createdAt: start, breed: .classicCat),
            PetProfile(id: UUID(), name: "Nori", species: .dog, coat: .cloud,
                       createdAt: start, breed: .cardigan)
        ]
        var state = PersistedAppState()
        state.pets = pets
        state.activePetIDs = pets.map(\.id)
        state.completedOnboarding = true
        state.settings.defaultSessionMinutes = 120
        state.settings.hapticsEnabled = false
        state.settings.minimizeMotion = true
        state.settings.liveActivityBackgroundColor = .init(red: 0.21, green: 0.26, blue: 0.35)
        state.history = PetHistory(totalSeconds: 720, completedSessions: 2)
        return state
    }
}

private actor DiscoveryTestStore: PetStore {
    private var value: PersistedAppState
    private var loadFails = false
    private var saveFails = false
    private var pausesNextSave = false
    private var savePaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveContinuation: CheckedContinuation<Void, Never>?

    init(_ value: PersistedAppState) { self.value = value }

    func setLoadFailure(_ value: Bool) { loadFails = value }
    func setSaveFailure(_ value: Bool) { saveFails = value }
    func snapshot() -> PersistedAppState { value }
    func pauseNextSave() { pausesNextSave = true }

    func waitForPausedSave() async {
        if savePaused { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func load() async throws -> PersistedAppState {
        if loadFails { throw CocoaError(.fileReadCorruptFile) }
        return value
    }

    func save(_ state: PersistedAppState) async throws {
        if pausesNextSave {
            pausesNextSave = false
            savePaused = true
            let waiters = pauseWaiters
            pauseWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { saveContinuation = $0 }
            savePaused = false
        }
        if saveFails { throw CocoaError(.fileWriteOutOfSpace) }
        value = state
    }
}
