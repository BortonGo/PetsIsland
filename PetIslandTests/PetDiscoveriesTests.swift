import XCTest
@testable import PetIsland

final class PetDiscoveriesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private var companion: PetProfile {
        PetProfile(id: UUID(), name: "Барсик", species: .cat, coat: .sunrise,
                   createdAt: start, breed: .classicCat)
    }

    func testFirstRunHasNoWalkOrMemories() {
        let state = PersistedAppState()
        XCTAssertNil(state.discoveries.activeWalk)
        XCTAssertTrue(state.discoveries.memories.isEmpty)
        XCTAssertTrue(state.discoveries.discoveredKinds.isEmpty)
    }

    func testLegacyCollectionSavePreservesPetsSettingsAndSession() throws {
        var original = PersistedAppState()
        original.profile = companion
        original.settings.defaultSessionMinutes = 45
        original.completedOnboarding = true
        original.activeSession = PetSession(id: UUID(), petID: original.profile.id, startedAt: start,
                                            endsAt: start.addingTimeInterval(2_700), snapshot: .initial(at: start))
        original.history.completedSessions = 12
        var payload = try jsonObject(original)
        payload.removeValue(forKey: "discoveries")
        let decoded = try decode(PersistedAppState.self, payload)
        XCTAssertEqual(decoded, original)
    }

    func testOriginalSinglePetSaveMigratesWithEmptyAlbum() throws {
        let pet = companion
        let payload: [String: Any] = ["profile": try jsonObject(pet), "completedOnboarding": true]
        let decoded = try decode(PersistedAppState.self, payload)
        XCTAssertEqual(decoded.pets, [pet])
        XCTAssertEqual(decoded.activePetIDs, [pet.id])
        XCTAssertTrue(decoded.completedOnboarding)
        XCTAssertEqual(decoded.discoveries, PetDiscoveriesState())
    }

    func testPendingWalkAndCompletedAlbumRoundTrip() throws {
        var state = PersistedAppState()
        XCTAssertTrue(state.discoveries.startWalk(pet: companion, route: .garden, at: start))
        XCTAssertEqual(try roundTrip(state), state)
        XCTAssertNotNil(state.discoveries.collectWalk(at: start.addingTimeInterval(1_200)))
        XCTAssertTrue(state.discoveries.startWalk(pet: companion, route: .shore, at: start))
        let restored = try roundTrip(state)
        XCTAssertEqual(restored, state)
        XCTAssertEqual(restored.discoveries.memories.count, 1)
        XCTAssertEqual(restored.discoveries.activeWalk?.route, .shore)
    }

    func testRoutesHaveDistinctCollectionsAndExpectedDuration() {
        XCTAssertEqual(PetWalkRoute.garden.duration, 1_200)
        XCTAssertEqual(PetWalkRoute.shore.duration, 2_400)
        XCTAssertEqual(PetWalkRoute.grove.duration, 3_600)
        XCTAssertTrue(PetWalkRoute.allCases.allSatisfy { $0.discoveryIDs.count == 4 })
        let allFinds = PetWalkRoute.allCases.flatMap(\.discoveryIDs)
        XCTAssertEqual(allFinds.count, Set(allFinds).count)
        XCTAssertEqual(Set(allFinds), Set(PetDiscoveryKind.allCases))
    }

    func testWalkBecomesReadyExactlyAtScheduledEnd() throws {
        var state = PetDiscoveriesState()
        XCTAssertTrue(state.startWalk(pet: companion, route: .garden, at: start))
        let walk = try XCTUnwrap(state.activeWalk)
        XCTAssertEqual(walk.endsAt, start.addingTimeInterval(1_200))
        XCTAssertEqual(walk.progress(at: start), 0)
        XCTAssertEqual(walk.progress(at: start.addingTimeInterval(600)), 0.5)
        XCTAssertFalse(walk.isReady(at: walk.endsAt.addingTimeInterval(-0.001)))
        XCTAssertNil(state.collectWalk(at: walk.endsAt.addingTimeInterval(-0.001)))
        XCTAssertEqual(state.activeWalk, walk)
        XCTAssertTrue(walk.isReady(at: walk.endsAt))
        XCTAssertEqual(walk.progress(at: walk.endsAt), 1)
        XCTAssertNotNil(state.collectWalk(at: walk.endsAt))
    }

    func testBackwardsClockNeverCompletesWalkOrProducesNegativeProgress() throws {
        var state = PetDiscoveriesState()
        state.startWalk(pet: companion, route: .shore, at: start)
        let walk = try XCTUnwrap(state.activeWalk)
        let earlier = start.addingTimeInterval(-86_400)
        XCTAssertFalse(walk.isReady(at: earlier))
        XCTAssertEqual(walk.progress(at: earlier), 0)
        XCTAssertNil(state.collectWalk(at: earlier))
        XCTAssertEqual(state.activeWalk, walk)
        XCTAssertTrue(state.memories.isEmpty)
    }

    func testReadyWalkSurvivesLongAbsenceAndKeepsScheduledFoundDate() throws {
        var state = PetDiscoveriesState()
        state.startWalk(pet: companion, route: .grove, at: start)
        let walk = try XCTUnwrap(state.activeWalk)
        let muchLater = start.addingTimeInterval(365 * 24 * 3_600)
        state = try roundTrip(state)
        XCTAssertEqual(state.activeWalk, walk)
        XCTAssertEqual(walk.progress(at: muchLater), 1)
        let memory = try XCTUnwrap(state.collectWalk(at: muchLater))
        XCTAssertEqual(memory.id, walk.id)
        XCTAssertEqual(memory.foundAt, walk.endsAt)
    }

    func testDuplicateStartAndCollectionTapsDoNotReplaceOrDuplicateRewards() throws {
        var state = PetDiscoveriesState()
        XCTAssertTrue(state.startWalk(pet: companion, route: .garden, at: start))
        let walk = try XCTUnwrap(state.activeWalk)
        XCTAssertFalse(state.startWalk(pet: companion, route: .shore, at: start))
        XCTAssertFalse(state.startWalk(pet: companion, route: .grove, at: walk.endsAt))
        XCTAssertEqual(state.activeWalk, walk)
        let collected = try XCTUnwrap(state.collectWalk(at: walk.endsAt))
        XCTAssertNil(state.collectWalk(at: walk.endsAt))
        XCTAssertNil(state.collectWalk(at: walk.endsAt.addingTimeInterval(1)))
        XCTAssertEqual(state.memories, [collected])
        XCTAssertNil(state.activeWalk)
    }

    func testEveryRouteRevealsAllFourFindsBeforeRepeating() throws {
        var state = PetDiscoveriesState()
        var now = start
        for route in PetWalkRoute.allCases {
            var finds: [PetDiscoveryKind] = []
            for _ in 0..<8 {
                XCTAssertTrue(state.startWalk(pet: companion, route: route, at: now))
                now = now.addingTimeInterval(route.duration)
                finds.append(try XCTUnwrap(state.collectWalk(at: now)).discovery)
            }
            XCTAssertEqual(Array(finds.prefix(4)), route.discoveryIDs)
            XCTAssertEqual(Array(finds.suffix(4)), route.discoveryIDs)
        }
        XCTAssertEqual(state.discoveredKinds, Set(PetDiscoveryKind.allCases))
        XCTAssertEqual(state.memories.count, 24)
    }

    func testWalkSnapshotAndAlbumSurviveCompanionRenameAndRemoval() throws {
        var state = PersistedAppState()
        let pet = companion
        state.profile = pet
        state.discoveries.startWalk(pet: pet, route: .garden, at: start)
        let walk = try XCTUnwrap(state.discoveries.activeWalk)
        state.pets[0].name = "Другое имя"
        XCTAssertEqual(state.discoveries.activeWalk?.pet, pet)
        state.pets.removeAll { $0.id == pet.id }
        state.normalizePetCollection()
        let memory = try XCTUnwrap(state.discoveries.collectWalk(at: walk.endsAt))
        XCTAssertEqual(memory.pet, pet)
        XCTAssertFalse(state.pets.contains { $0.id == pet.id })
        XCTAssertEqual(try roundTrip(state).discoveries.memories.first?.pet, pet)
    }

    func testCancellationDoesNotCreateMemoryOrUseUpDiscovery() throws {
        var state = PetDiscoveriesState()
        XCTAssertFalse(state.cancelWalk())
        state.startWalk(pet: companion, route: .garden, at: start)
        let canceled = try XCTUnwrap(state.activeWalk)
        XCTAssertTrue(state.cancelWalk())
        XCTAssertFalse(state.cancelWalk())
        XCTAssertNil(state.collectWalk(at: canceled.endsAt))
        XCTAssertTrue(state.memories.isEmpty)
        XCTAssertTrue(state.startWalk(pet: companion, route: .garden, at: canceled.endsAt))
        XCTAssertEqual(state.activeWalk?.discovery, canceled.discovery)
        XCTAssertNotEqual(state.activeWalk?.id, canceled.id)
    }

    func testCancelingReadyWalkLeavesExistingAlbumUntouched() throws {
        var state = PetDiscoveriesState()
        state.startWalk(pet: companion, route: .garden, at: start)
        let memory = try XCTUnwrap(state.collectWalk(at: start.addingTimeInterval(1_200)))
        state.startWalk(pet: companion, route: .shore, at: start)
        XCTAssertTrue(try XCTUnwrap(state.activeWalk).isReady(at: start.addingTimeInterval(2_400)))
        XCTAssertTrue(state.cancelWalk())
        XCTAssertEqual(state.memories, [memory])
    }

    func testInvalidDatesCannotStartOrCompleteWalk() throws {
        for interval in [Double.nan, Double.infinity, -Double.infinity, Double.greatestFiniteMagnitude] {
            var state = PetDiscoveriesState()
            XCTAssertFalse(state.startWalk(pet: companion, route: .garden,
                                           at: Date(timeIntervalSinceReferenceDate: interval)))
            XCTAssertNil(state.activeWalk)
        }
        var state = PetDiscoveriesState()
        state.startWalk(pet: companion, route: .garden, at: start)
        let walk = try XCTUnwrap(state.activeWalk)
        for interval in [Double.nan, Double.infinity, -Double.infinity] {
            let invalid = Date(timeIntervalSinceReferenceDate: interval)
            XCTAssertFalse(walk.isReady(at: invalid))
            XCTAssertEqual(walk.progress(at: invalid), 0)
            XCTAssertNil(state.collectWalk(at: invalid))
        }
        XCTAssertEqual(state.activeWalk, walk)
    }

    func testInvalidWalkCannotBeConstructed() {
        XCTAssertNil(PetDiscoveryWalk(pet: companion, route: .garden, startedAt: start,
                                     endsAt: start, discovery: .clover))
        XCTAssertNil(PetDiscoveryWalk(pet: companion, route: .garden, startedAt: start,
                                     endsAt: start.addingTimeInterval(-1), discovery: .clover))
        XCTAssertNil(PetDiscoveryWalk(pet: companion, route: .garden, startedAt: start,
                                     endsAt: start.addingTimeInterval(1_200), discovery: .shell))
    }

    func testCorruptDiscoveryDataFailsDecodingInsteadOfResettingSave() throws {
        var state = PersistedAppState()
        state.discoveries.startWalk(pet: companion, route: .garden, at: start)
        var payload = try jsonObject(state)
        payload["discoveries"] = "corrupt album"
        XCTAssertThrowsError(try decode(PersistedAppState.self, payload))
        var walk = try jsonObject(XCTUnwrap(state.discoveries.activeWalk))
        walk["endsAt"] = walk["startedAt"]
        payload["discoveries"] = ["activeWalk": walk, "memories": []]
        XCTAssertThrowsError(try decode(PersistedAppState.self, payload))
        walk = try jsonObject(XCTUnwrap(state.discoveries.activeWalk))
        walk["discovery"] = "unknownFutureFind"
        payload["discoveries"] = ["activeWalk": walk, "memories": []]
        XCTAssertThrowsError(try decode(PersistedAppState.self, payload))
    }

    func testDecodingRejectsDuplicateMemoryAndAlreadyClaimedActiveWalk() throws {
        var state = PetDiscoveriesState()
        state.startWalk(pet: companion, route: .garden, at: start)
        let walk = try XCTUnwrap(state.activeWalk)
        let memory = try XCTUnwrap(state.collectWalk(at: walk.endsAt))
        let duplicated = PetDiscoveriesState(memories: [memory, memory])
        XCTAssertThrowsError(try roundTrip(duplicated))
        var alreadyClaimed = PetDiscoveriesState(activeWalk: walk, memories: [memory])
        XCTAssertNil(alreadyClaimed.collectWalk(at: walk.endsAt))
        XCTAssertThrowsError(try roundTrip(alreadyClaimed))
    }

    func testWalkAbsencePreservesHabitatSlotsAndReturnsExactlyAtEndWithoutClaiming() throws {
        var habitat = try habitatWithWalkingResident()
        let walk = try XCTUnwrap(habitat.discoveryWalk)
        let configuredIDs = habitat.configuration.residentPetIDs
        let originalResidents = habitat.residents
        habitat.reconcile()

        XCTAssertEqual(habitat.configuration.residentPetIDs, configuredIDs)
        XCTAssertEqual(habitat.residents, originalResidents)
        XCTAssertFalse(habitat.visibleResidents(at: start).contains { $0.id == walk.pet.id })
        XCTAssertTrue(habitat.isPetAway(walk.pet.id, at: start.addingTimeInterval(-3_600)))
        XCTAssertTrue(habitat.isPetAway(walk.pet.id, at: walk.endsAt.addingTimeInterval(-0.001)))
        XCTAssertFalse(habitat.isPetAway(walk.pet.id, at: walk.endsAt))
        XCTAssertEqual(habitat.visibleResidents(at: walk.endsAt), originalResidents)
        XCTAssertEqual(habitat.discoveryWalk, walk, "Returning must not depend on claiming or changing the saved walk.")
    }

    func testWalkingResidentDoesNotChangeOtherWidgetProjections() throws {
        let habitat = try habitatWithWalkingResident()
        let walk = try XCTUnwrap(habitat.discoveryWalk)
        let allProjections = PetHabitatEngine.projections(for: habitat.configuration,
                                                         pets: habitat.residents.map(\.profile), at: start)
        let visible = habitat.visibleProjections(at: start)
        XCTAssertEqual(visible.count, allProjections.count - 1)
        XCTAssertFalse(visible.contains { $0.petID == walk.pet.id })
        for projection in visible {
            XCTAssertEqual(projection, allProjections.first { $0.petID == projection.petID })
        }
        let returned = habitat.visibleProjections(at: walk.endsAt)
        XCTAssertEqual(returned.map(\.petID), habitat.configuration.residentPetIDs)
    }

    func testSharedHabitatWalkSurvivesRoundTripAndOldSharedSavesLoadNormally() throws {
        let habitat = try habitatWithWalkingResident()
        let restored = try roundTrip(habitat)
        XCTAssertEqual(restored, habitat)
        XCTAssertEqual(restored.visibleResidents(at: start), habitat.visibleResidents(at: start))

        var oldPayload = try jsonObject(habitat)
        oldPayload.removeValue(forKey: "discoveryWalk")
        let legacy = try decode(SharedPetHabitat.self, oldPayload)
        XCTAssertNil(legacy.discoveryWalk)
        XCTAssertEqual(legacy.configuration, habitat.configuration)
        XCTAssertEqual(legacy.residents, habitat.residents)
        XCTAssertEqual(legacy.visibleResidents(at: start), habitat.residents)
    }

    func testWidgetBallDoesNotAffectAwayResidentButStillPlaysWithOthers() throws {
        var habitat = try habitatWithWalkingResident()
        let walk = try XCTUnwrap(habitat.discoveryWalk)
        let before = habitat.residents
        habitat.playWithResidents(at: start)
        XCTAssertEqual(habitat.residents.first { $0.id == walk.pet.id }, before.first { $0.id == walk.pet.id })
        for resident in habitat.residents where resident.id != walk.pet.id {
            let previous = try XCTUnwrap(before.first { $0.id == resident.id })
            XCTAssertGreaterThan(resident.vitals.happiness, previous.vitals.happiness)
            XCTAssertLessThan(resident.vitals.energy, previous.vitals.energy)
        }
        habitat.playWithResidents(at: walk.endsAt)
        XCTAssertGreaterThan(try XCTUnwrap(habitat.residents.first { $0.id == walk.pet.id }).vitals.happiness,
                             try XCTUnwrap(before.first { $0.id == walk.pet.id }).vitals.happiness)
    }

    func testWidgetAveragesOnlyPresentResidentsAtEntryDate() throws {
        var habitat = try habitatWithWalkingResident()
        let walk = try XCTUnwrap(habitat.discoveryWalk)
        habitat.residents[0].vitals = PetVitals(fullness: 0.1, happiness: 0.2, energy: 0.3)
        habitat.residents[1].vitals = PetVitals(fullness: 0.9, happiness: 0.8, energy: 0.7)
        XCTAssertEqual(habitat.averageVitals(at: start), habitat.residents[1].vitals)
        XCTAssertEqual(habitat.averageVitals(at: walk.endsAt).fullness, 0.5, accuracy: 0.000001)
        habitat.residents.removeLast()
        XCTAssertEqual(habitat.averageVitals(at: start), PetVitals(fullness: 0, happiness: 0, energy: 0))
    }

    func testClearingAbsenceReturnsResidentWithoutChangingComposition() throws {
        var habitat = try habitatWithWalkingResident()
        let before = habitat.configuration
        let residents = habitat.residents
        habitat.discoveryWalk = nil
        XCTAssertEqual(habitat.visibleResidents(at: start), residents)
        XCTAssertEqual(habitat.configuration, before)
    }

    private func habitatWithWalkingResident() throws -> SharedPetHabitat {
        let walkingPet = companion
        let stayingPet = companion
        let walk = try XCTUnwrap(PetDiscoveryWalk(pet: walkingPet, route: .garden, startedAt: start,
                                                 endsAt: start.addingTimeInterval(1_200), discovery: .clover))
        return SharedPetHabitat(
            configuration: PetHabitatState(residentPetIDs: [walkingPet.id, stayingPet.id], simulationEpoch: start),
            residents: [walkingPet, stayingPet].map {
                SharedHabitatResident(profile: $0, vitals: PetVitals(fullness: 0.6, happiness: 0.5, energy: 0.7),
                                      vitalsUpdatedAt: start)
            },
            discoveryWalk: walk
        )
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
}
