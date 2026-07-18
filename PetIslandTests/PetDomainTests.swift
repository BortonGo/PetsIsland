import XCTest
@testable import PetIsland

final class PetDomainTests: XCTestCase {
    func testTwoFrameAnimationClipLoopsAtItsOwnCadence() {
        let clip = PetAnimationClip(frames: ["walk-0", "walk-1"], frameDuration: 0.125)

        XCTAssertEqual(clip.frameIndex(at: 0), 0)
        XCTAssertEqual(clip.frameIndex(at: 0.124), 0)
        XCTAssertEqual(clip.frameIndex(at: 0.125), 1)
        XCTAssertEqual(clip.frameIndex(at: 0.249), 1)
        XCTAssertEqual(clip.frameIndex(at: 0.25), 0)
        XCTAssertEqual(clip.cycleDuration, 0.25, accuracy: 0.000_001)
    }

    func testAnimationClipSupportsPhaseOffsetsAndNegativeElapsedTime() {
        let clip = PetAnimationClip(frames: ["0", "1", "2"], frameDuration: 0.1)

        XCTAssertEqual(clip.frameIndex(at: 0, phaseOffset: 1), 1)
        XCTAssertEqual(clip.frameIndex(at: -0.1), 2)
        XCTAssertEqual(clip.frameIndex(at: 0, phaseOffset: .max), 1)
        XCTAssertEqual(clip.frameName(forStep: -1), "2")
    }

    func testSingleFrameAnimationClipRemainsStable() {
        let clip = PetAnimationClip(frames: ["sleep"], frameDuration: 0.68)

        XCTAssertEqual(clip.frameIndex(at: 10_000, phaseOffset: 99), 0)
        XCTAssertEqual(clip.frameName(at: 10_000), "sleep")
    }

    func testMovementClipCadenceAndExistingAssetNamesStayCompatible() {
        let walk = PetAnimationLibrary.clip(for: .dog, breed: .corgi, pose: .walk)
        let run = PetAnimationLibrary.clip(for: .dog, breed: .corgi, pose: .run)

        XCTAssertEqual(walk.frames, ["island_dog_corgi_walk_0", "island_dog_corgi_walk_1"])
        XCTAssertEqual(
            run.frames,
            [
                "island_dog_corgi_walk_0",
                "island_dog_corgi_idle",
                "island_dog_corgi_walk_1",
                "island_dog_corgi_idle"
            ]
        )
        XCTAssertLessThan(run.frameDuration, walk.frameDuration)
    }

    func testSpeciesVariantsResolveToTheirOwnSpriteAssets() {
        XCTAssertEqual(
            PetAnimationLibrary.clip(for: .cat, breed: .siamese, pose: .idle).frames,
            ["island_cat_siamese_idle"]
        )
        XCTAssertEqual(
            PetAnimationLibrary.clip(for: .fox, breed: .arcticFox, pose: .sleep).frames,
            ["island_fox_arctic_sleep"]
        )
        XCTAssertEqual(
            PetAnimationLibrary.clip(for: .parrot, breed: .macaw, pose: .fly).frames,
            [
                "island_parrot_macaw_fly_00",
                "island_parrot_macaw_fly_01",
                "island_parrot_macaw_fly_02",
                "island_parrot_macaw_fly_03",
                "island_parrot_macaw_fly_04",
                "island_parrot_macaw_fly_05",
                "island_parrot_macaw_fly_06",
                "island_parrot_macaw_fly_07"
            ]
        )
        XCTAssertEqual(
            PetAnimationLibrary.clip(for: .penguin, breed: .rockhopper, pose: .idle).frames,
            ["island_penguin_rockhopper_idle"]
        )
    }

    func testSnapshotClampsPositionToSafeTrack() {
        let low = PetSnapshot(pose: .walk, position: -10, direction: .right, revision: 0, generatedAt: .now)
        let high = PetSnapshot(pose: .walk, position: 10, direction: .left, revision: 0, generatedAt: .now)

        XCTAssertEqual(low.position, 0.08)
        XCTAssertEqual(high.position, 0.92)
    }

    func testBehaviorIsDeterministicForSameSessionAndDate() {
        let now = Date(timeIntervalSince1970: 1_000)
        let session = PetSession(
            id: UUID(), petID: UUID(), startedAt: now, endsAt: now.addingTimeInterval(3_600),
            snapshot: .initial(at: now)
        )
        let machine = PetBehaviorMachine()
        let date = now.addingTimeInterval(48)

        XCTAssertEqual(
            machine.ambientSnapshot(for: session, species: .cat, at: date),
            machine.ambientSnapshot(for: session, species: .cat, at: date)
        )
    }

    func testExpiredSessionAlwaysSleeps() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = PetSession(
            id: UUID(), petID: UUID(), startedAt: start, endsAt: start.addingTimeInterval(60),
            snapshot: .initial(at: start)
        )

        let result = PetBehaviorMachine().ambientSnapshot(
            for: session,
            species: .cat,
            at: start.addingTimeInterval(61)
        )
        XCTAssertEqual(result.pose, .sleep)
    }

    func testParrotStartsAndPlaysInFlight() {
        let now = Date(timeIntervalSince1970: 1_000)
        let machine = PetBehaviorMachine()
        let initial = machine.initialSnapshot(for: .parrot, at: now)
        let playing = machine.reacting(to: .play, species: .parrot, from: initial, at: now)

        XCTAssertEqual(initial.pose, .fly)
        XCTAssertEqual(playing.pose, .fly)
    }

    func testCatalogContainsEightOriginalSpecies() {
        XCTAssertEqual(PetSpecies.allCases.count, 8)
    }

    func testVisualVariantsAreScopedToTheirSpecies() {
        XCTAssertEqual(
            PetBreed.available(for: .dog),
            [.shepherd, .corgi, .doberman, .bullTerrier]
        )
        XCTAssertEqual(
            PetBreed.available(for: .cat),
            [.classicCat, .britishShorthair, .maineCoon, .siamese]
        )
        XCTAssertEqual(PetBreed.available(for: .fox), [.redFox, .arcticFox])
        XCTAssertEqual(
            PetBreed.available(for: .parrot),
            [.classicParrot, .cockatiel, .budgie, .macaw]
        )
        XCTAssertEqual(
            PetBreed.available(for: .penguin),
            [.classicPenguin, .rockhopper]
        )
        XCTAssertTrue(PetBreed.available(for: .bear).isEmpty)
    }

    func testLegacyDogWithoutBreedResolvesToShepherd() throws {
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Pixel",
          "species": "dog",
          "coat": "sunrise",
          "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PetProfile.self, from: legacyJSON)

        XCTAssertNil(decoded.breed)
        XCTAssertEqual(decoded.resolvedBreed, .shepherd)
    }

    func testInvalidVariantFallsBackToSpeciesDefault() {
        let profile = PetProfile(
            id: UUID(), name: "Milo", species: .cat, coat: .cloud,
            createdAt: .now, breed: .corgi
        )

        XCTAssertEqual(profile.resolvedBreed, .classicCat)
    }

    func testSelectedDogBreedSurvivesPersistenceRoundTrip() throws {
        let profile = PetProfile(
            id: UUID(), name: "Ein", species: .dog, coat: .sunrise,
            createdAt: Date(timeIntervalSince1970: 1_000), breed: .corgi
        )

        let decoded = try JSONDecoder().decode(
            PetProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.resolvedBreed, .corgi)
    }

    func testSessionProgressIsClamped() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = PetSession(
            id: UUID(), petID: UUID(), startedAt: start, endsAt: start.addingTimeInterval(100),
            snapshot: .initial(at: start)
        )

        XCTAssertEqual(session.progress(at: start.addingTimeInterval(-1)), 0)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(50)), 0.5)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(101)), 1)
    }

    func testPetNameIsTrimmedCollapsedAndLimited() {
        var profile = PetProfile(
            id: UUID(), name: "   Very    Long 🐈 Pet Name Beyond Limit   ",
            species: .cat, coat: .sunrise, createdAt: .now
        )
        profile.normalizeName()

        XCTAssertFalse(profile.name.hasPrefix(" "))
        XCTAssertFalse(profile.name.contains("  "))
        XCTAssertLessThanOrEqual(profile.name.count, 16)
    }

    func testHistoryNeverRecordsMoreThanSessionDuration() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = PetSession(
            id: UUID(), petID: UUID(), startedAt: start, endsAt: start.addingTimeInterval(100),
            snapshot: .initial(at: start)
        )
        var history = PetHistory()

        history.record(session, endedAt: start.addingTimeInterval(1_000))

        XCTAssertEqual(history.totalSeconds, 100)
        XCTAssertEqual(history.completedSessions, 1)
    }

    func testInMemoryStoreRoundTrip() async throws {
        let store = InMemoryPetStore()
        var state = PersistedAppState()
        state.profile.name = "Milo"
        state.history.completedSessions = 4

        try await store.save(state)
        let loaded = await store.load()

        XCTAssertEqual(loaded, state)
    }

    func testLegacySinglePetStateMigratesToV2WithoutLosingData() throws {
        let pet = PetProfile(
            id: UUID(),
            name: "Milo",
            species: .fox,
            coat: .midnight,
            createdAt: Date(timeIntervalSince1970: 1_000),
            customColor: .init(red: 0.2, green: 0.4, blue: 0.8)
        )
        let session = PetSession(
            id: UUID(),
            petID: pet.id,
            startedAt: Date(timeIntervalSince1970: 2_000),
            endsAt: Date(timeIntervalSince1970: 3_000),
            snapshot: .initial(at: Date(timeIntervalSince1970: 2_000))
        )
        let legacy = LegacyPersistedAppState(
            profile: pet,
            activeSession: session,
            history: PetHistory(totalSeconds: 120, completedSessions: 2),
            settings: AppSettings(defaultSessionMinutes: 60, hapticsEnabled: false, minimizeMotion: true),
            completedOnboarding: true
        )

        let migrated = try JSONDecoder().decode(
            PersistedAppState.self,
            from: JSONEncoder().encode(legacy)
        )

        XCTAssertEqual(migrated.schemaVersion, 2)
        XCTAssertEqual(migrated.pets, [pet])
        XCTAssertEqual(migrated.activePetIDs, [pet.id])
        XCTAssertEqual(migrated.activeSession, session)
        XCTAssertEqual(migrated.history, legacy.history)
        XCTAssertEqual(migrated.settings, legacy.settings)
        XCTAssertTrue(migrated.completedOnboarding)
    }

    func testPetCollectionNormalizationKeepsOneToThreeKnownUniqueActivePets() {
        let pets = (0..<4).map { index in
            PetProfile(
                id: UUID(), name: "Pet \(index)", species: .cat,
                coat: .sunrise, createdAt: .now
            )
        }
        var state = PersistedAppState()
        state.pets = pets
        state.activePetIDs = [pets[0].id, pets[0].id, UUID(), pets[1].id, pets[2].id, pets[3].id]

        state.normalizePetCollection()

        XCTAssertEqual(state.activePetIDs, [pets[0].id, pets[1].id, pets[2].id])
        XCTAssertEqual(state.activeParty.map(\.id), state.activePetIDs)

        state.activePetIDs = []
        state.normalizePetCollection()
        XCTAssertEqual(state.activePetIDs, [pets[0].id])
    }

    @MainActor
    func testControllerEnforcesPartyLimitAndLeadOrdering() async {
        let store = InMemoryPetStore()
        let controller = PetSessionController(store: store)
        await controller.bootstrap()
        let originalLeadID = controller.profile.id
        let additions = [PetSpecies.dog, .fox, .parrot].map { species in
            PetProfile(
                id: UUID(), name: species.rawValue, species: species,
                coat: .cloud, createdAt: .now
            )
        }

        for pet in additions {
            let added = await controller.addPet(pet)
            XCTAssertTrue(added)
        }

        XCTAssertEqual(controller.pets.count, 4)
        XCTAssertEqual(controller.activeParty.count, 3)
        XCTAssertEqual(controller.activeParty.first?.id, originalLeadID)
        let rejectedAtLimit = await controller.togglePetActive(id: additions[2].id)
        XCTAssertFalse(rejectedAtLimit)

        let removedCompanion = await controller.togglePetActive(id: additions[0].id)
        let addedCompanion = await controller.togglePetActive(id: additions[2].id)
        let promoted = await controller.makeLeadPet(id: additions[2].id)
        XCTAssertTrue(removedCompanion)
        XCTAssertTrue(addedCompanion)
        XCTAssertTrue(promoted)
        XCTAssertEqual(controller.profile.id, additions[2].id)
        XCTAssertEqual(controller.activeParty.map(\.id), controller.activePetIDs)
        XCTAssertLessThanOrEqual(controller.activeParty.count, PersistedAppState.maximumActivePets)
    }

    @MainActor
    func testControllerNeverRemovesLastPetOrDeactivatesLastPartyMember() async {
        let controller = PetSessionController(store: InMemoryPetStore())
        await controller.bootstrap()
        let onlyPetID = controller.profile.id

        let removed = await controller.removePet(id: onlyPetID)
        let deactivated = await controller.togglePetActive(id: onlyPetID)
        XCTAssertFalse(removed)
        XCTAssertFalse(deactivated)
        XCTAssertEqual(controller.pets.count, 1)
        XCTAssertEqual(controller.activePetIDs, [onlyPetID])
    }

    func testLiveActivityPayloadStaysWellBelowSystemLimit() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let state = PetActivityAttributes.ContentState(
            snapshot: .init(pose: .play, position: 0.5, direction: .right, revision: 42, generatedAt: now),
            lastInteraction: "play"
        )
        let identities = [PetSpecies.cat, .dog, .parrot].map { species in
            PetActivityIdentity(
                id: UUID(), name: species.rawValue, species: species,
                coat: .sunrise, customColor: nil
            )
        }
        let attributes = PetActivityAttributes(
            sessionID: UUID(),
            pet: identities[0],
            companions: Array(identities.dropFirst()),
            startedAt: now,
            endsAt: now.addingTimeInterval(3_600)
        )

        let encoded = try JSONEncoder().encode(state)
        let encodedAttributes = try JSONEncoder().encode(attributes)

        XCTAssertLessThan(encoded.count, 4_096)
        XCTAssertLessThan(encodedAttributes.count, 4_096)
        XCTAssertEqual(attributes.companions.count, 2)
    }

    func testLiveRunAlternatesTwoFramesInPlaceThenSleeps() {
        let start = PetSnapshot(
            pose: .idle,
            position: 0.18,
            direction: .right,
            revision: 10,
            generatedAt: .distantPast
        )

        let frames = PetLiveMotionSequence.snapshots(
            from: start,
            action: .run,
            at: .distantPast
        )

        XCTAssertEqual(frames.count, PetLiveMotionSequence.runningUpdateCount + 1)
        XCTAssertEqual(frames.dropLast().map(\.pose), [.run, .run, .run, .run])
        XCTAssertEqual(frames.last?.pose, .sleep)
        XCTAssertTrue(frames.allSatisfy { $0.direction == .right })
        XCTAssertTrue(frames.allSatisfy { abs($0.position - 0.18) < 0.0001 })
        XCTAssertEqual(frames.map(\.revision), [11, 12, 13, 14, 15])
        XCTAssertEqual(
            frames.dropLast().map { PetLiveMotionSequence.spriteStep(for: $0) },
            [1, 0, 1, 0]
        )
    }

    func testLiveParrotFlapsInPlaceThenSleeps() {
        let start = PetSnapshot(
            pose: .idle,
            position: 0.62,
            direction: .left,
            revision: 20,
            generatedAt: .distantPast
        )

        let frames = PetLiveMotionSequence.snapshots(
            from: start,
            action: .run,
            species: .parrot,
            at: .distantPast
        )

        XCTAssertTrue(frames.dropLast().allSatisfy { $0.pose == .fly })
        XCTAssertEqual(frames.last?.pose, .sleep)
        XCTAssertTrue(frames.allSatisfy { abs($0.position - start.position) < 0.0001 })
    }

    func testAmbientMotionBouncesAndJumpsAtTrackBoundary() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = PetSession(
            id: UUID(), petID: UUID(), startedAt: start,
            endsAt: start.addingTimeInterval(3_600), snapshot: .initial(at: start)
        )
        let cadence = PetBehaviorMachine.ambientCadence(for: .dog)
        let machine = PetBehaviorMachine()
        let approaching = machine.ambientSnapshot(
            for: session, species: .dog,
            at: start.addingTimeInterval(cadence * 5.01)
        )
        let boundary = machine.ambientSnapshot(
            for: session, species: .dog,
            at: start.addingTimeInterval(cadence * 6.01)
        )
        let rebounding = machine.ambientSnapshot(
            for: session, species: .dog,
            at: start.addingTimeInterval(cadence * 7.01)
        )

        XCTAssertEqual(approaching.direction, .right)
        XCTAssertEqual(boundary.pose, .jump)
        XCTAssertEqual(boundary.position, 0.88, accuracy: 0.0001)
        XCTAssertEqual(boundary.direction, .left)
        XCTAssertEqual(rebounding.direction, .left)
        XCTAssertLessThan(rebounding.position, boundary.position)
    }

    func testPetLifeStateRoundTripKeepsDogAndPlacement() throws {
        let date = Date(timeIntervalSince1970: 10_000)
        let cat = PetProfile(
            id: UUID(), name: "Pixel", species: .cat,
            coat: .midnight, createdAt: date
        )
        let state = PetLifeState(
            profile: cat,
            placement: .dynamicIsland,
            vitalsUpdatedAt: date,
            autonomyEpoch: date,
            behaviorSeed: 42
        )

        let decoded = try PropertyListDecoder().decode(
            PetLifeState.self,
            from: PropertyListEncoder().encode(state)
        )

        XCTAssertEqual(decoded.profile.species, .dog)
        XCTAssertEqual(decoded.placement, .dynamicIsland)
        XCTAssertEqual(decoded, state)
    }

    func testPetLifeEngineIsDeterministicAndStaysInsideEnclosure() {
        let start = Date(timeIntervalSince1970: 20_000)
        let state = PetLifeState(
            profile: .starter,
            placement: .enclosure,
            vitalsUpdatedAt: start,
            autonomyEpoch: start,
            behaviorSeed: 7
        )
        let date = start.addingTimeInterval(317)

        let first = PetLifeEngine.presentation(for: state, at: date)
        let second = PetLifeEngine.presentation(for: state, at: date)

        XCTAssertEqual(first, second)
        XCTAssertTrue((0...1).contains(first.position))
        XCTAssertTrue((0...1).contains(first.lane))
        XCTAssertTrue((0...1).contains(first.vitals.energy))
    }

    func testThrowingBallImprovesMoodAndStartsFetchReaction() {
        let start = Date(timeIntervalSince1970: 30_000)
        var state = PetLifeState(
            profile: .starter,
            placement: .enclosure,
            vitals: PetVitals(fullness: 0.7, happiness: 0.5, energy: 0.8),
            vitalsUpdatedAt: start,
            autonomyEpoch: start,
            behaviorSeed: 11
        )

        state.throwBall(at: start)
        let chasing = PetLifeEngine.presentation(
            for: state,
            at: start.addingTimeInterval(0.8)
        )
        let settled = PetLifeEngine.presentation(
            for: state,
            at: start.addingTimeInterval(PetLifeEngine.ballReactionDuration + 1)
        )

        XCTAssertEqual(state.placement, .enclosure)
        XCTAssertGreaterThan(state.vitals.happiness, 0.5)
        XCTAssertLessThan(state.vitals.energy, 0.8)
        XCTAssertEqual(chasing.activity, .playing)
        XCTAssertNotNil(chasing.ball)
        XCTAssertNil(settled.ball)
    }

    func testWidgetFetchStoryboardCoversTenSecondsInAnimationSafeSegments() {
        let offsets = PetLifeEngine.ballReactionTimelineOffsets

        XCTAssertEqual(offsets, offsets.sorted())
        XCTAssertGreaterThanOrEqual(offsets.last ?? 0, 10)
        XCTAssertEqual(PetLifeEngine.ballReactionDuration, offsets.last)
        XCTAssertTrue(zip([0] + offsets, offsets).allSatisfy { pair in
            pair.1 - pair.0 <= 2
        })
        XCTAssertGreaterThanOrEqual(PetLifeEngine.widgetSpriteFrameRate, 8)
    }

    func testPlayYardJumpRequiresAnAirborneNearbyBall() {
        XCTAssertTrue(
            PlayYardMotionRules.shouldJump(
                ballHeight: 74,
                horizontalDistance: 92,
                isAirborne: false,
                cooldown: 0,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            PlayYardMotionRules.shouldJump(
                ballHeight: 12,
                horizontalDistance: 92,
                isAirborne: false,
                cooldown: 0,
                reduceMotion: false
            )
        )
        XCTAssertFalse(
            PlayYardMotionRules.shouldJump(
                ballHeight: 74,
                horizontalDistance: 92,
                isAirborne: true,
                cooldown: 0,
                reduceMotion: false
            )
        )
    }

    func testPlayYardJumpLaunchVelocityScalesAndPointsUpward() {
        let lowThrow = PlayYardMotionRules.launchVelocity(for: 45)
        let highThrow = PlayYardMotionRules.launchVelocity(for: 105)

        XCTAssertLessThan(lowThrow, 0)
        XCTAssertLessThan(highThrow, lowThrow)
    }

    func testWidgetFetchContainsRunJumpAndLandingPhases() {
        let start = Date(timeIntervalSince1970: 40_000)
        var state = PetLifeState(
            profile: .starter,
            placement: .enclosure,
            vitalsUpdatedAt: start,
            autonomyEpoch: start,
            behaviorSeed: 19
        )
        state.throwBall(at: start)

        let run = PetLifeEngine.presentation(for: state, at: start.addingTimeInterval(1))
        let jump = PetLifeEngine.presentation(for: state, at: start.addingTimeInterval(4.5))
        let landing = PetLifeEngine.presentation(for: state, at: start.addingTimeInterval(8))

        XCTAssertEqual(run.pose, .run)
        XCTAssertEqual(jump.pose, .jump)
        XCTAssertLessThan(jump.lane, run.lane)
        XCTAssertEqual(landing.pose, .play)
    }

    func testWidgetFetchAdvancesEnoughSpriteFramesToShowARealGait() {
        let start = Date(timeIntervalSince1970: 50_000)
        var state = PetLifeState(
            profile: .starter,
            placement: .enclosure,
            vitalsUpdatedAt: start,
            autonomyEpoch: start,
            behaviorSeed: 23
        )
        state.throwBall(at: start)

        let first = PetLifeEngine.presentation(for: state, at: start)
        let second = PetLifeEngine.presentation(
            for: state,
            at: start.addingTimeInterval(PetLifeEngine.widgetMotionSegmentDuration)
        )

        XCTAssertGreaterThanOrEqual(second.spriteStep - first.spriteStep, 16)
        XCTAssertEqual(first.pose, .run)
        XCTAssertEqual(second.pose, .run)
        XCTAssertGreaterThan(second.position, 0.45)
    }
}

private struct LegacyPersistedAppState: Encodable {
    let schemaVersion = 1
    var profile: PetProfile
    var activeSession: PetSession?
    var history: PetHistory
    var settings: AppSettings
    var completedOnboarding: Bool
}
