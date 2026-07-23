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

    func testMovementClipUsesDistinctWalkAndGallopArtwork() {
        let walk = PetAnimationLibrary.clip(for: .dog, breed: .corgi, pose: .walk)
        let run = PetAnimationLibrary.clip(for: .dog, breed: .corgi, pose: .run)

        XCTAssertEqual(walk.frames, ["island_dog_corgi_walk_0", "island_dog_corgi_walk_1"])
        XCTAssertEqual(run.frames, ["island_dog_corgi_run_0", "island_dog_corgi_run_1"])
        XCTAssertLessThan(run.frameDuration, walk.frameDuration)
    }

    func testShepherdJumpUsesItsAirborneGallopFrame() {
        let jump = PetAnimationLibrary.clip(for: .dog, breed: .shepherd, pose: .jump)

        XCTAssertEqual(jump.frames, ["island_dog_shepherd_run_0"])
    }

    func testMaineCoonJumpUsesTheCompleteAirborneFrame() {
        let jump = PetAnimationLibrary.clip(for: .cat, breed: .maineCoon, pose: .jump)

        XCTAssertEqual(jump.frames, ["island_cat_maine_coon_run_0"])
    }

    func testSkyPawsUsesOneDedicatedPlaneForEveryNonParrotVariant() {
        let variants: [(PetSpecies, PetBreed, String)] = [
            (.cat, .classicCat, "sky_paws_cat_classic"),
            (.cat, .britishShorthair, "sky_paws_cat_british"),
            (.cat, .maineCoon, "sky_paws_cat_maine_coon"),
            (.cat, .siamese, "sky_paws_cat_siamese"),
            (.dog, .shepherd, "sky_paws_dog_shepherd"),
            (.dog, .corgi, "sky_paws_dog_corgi"),
            (.dog, .doberman, "sky_paws_dog_doberman"),
            (.dog, .bullTerrier, "sky_paws_dog_bull_terrier"),
            (.fox, .redFox, "sky_paws_fox_red"),
            (.fox, .arcticFox, "sky_paws_fox_arctic"),
            (.penguin, .classicPenguin, "sky_paws_penguin_classic"),
            (.penguin, .rockhopper, "sky_paws_penguin_rockhopper")
        ]

        for (species, breed, assetName) in variants {
            XCTAssertEqual(
                SkyPawsArtworkLibrary.assetNames(for: species, breed: breed),
                [assetName]
            )
        }
    }

    func testSkyPawsParrotsUseExactlyTwoNativeWingFrames() {
        let variants: [(PetBreed, String)] = [
            (.classicParrot, "classic"),
            (.cockatiel, "cockatiel"),
            (.budgie, "budgie"),
            (.macaw, "macaw")
        ]

        for (breed, token) in variants {
            XCTAssertEqual(
                SkyPawsArtworkLibrary.assetNames(for: .parrot, breed: breed),
                ["island_parrot_\(token)_fly_00", "island_parrot_\(token)_fly_04"]
            )
        }
    }

    func testSkyPawsEngineStartsAndFlaps() {
        var engine = SkyPawsEngine()
        let size = CGSize(width: 393, height: 852)

        engine.start(in: size)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.gates.count, 4)
        XCTAssertEqual(engine.score, 0)

        engine.flap()
        XCTAssertEqual(engine.velocityY, -325)
        engine.update(deltaTime: 1.0 / 60.0, in: size)
        XCTAssertLessThan(engine.playerY, size.height * 0.48)
    }

    func testSkyPawsSeedChangesTheGateLayout() {
        let size = CGSize(width: 393, height: 852)
        var first = SkyPawsEngine()
        var second = SkyPawsEngine()

        first.start(in: size, seed: 1)
        second.start(in: size, seed: 2)

        XCTAssertNotEqual(first.gates.map(\.gapCenter), second.gates.map(\.gapCenter))
    }

    func testSkyPawsGateSequenceKeepsEveryNextGapReachable() {
        let size = CGSize(width: 393, height: 852)
        var engine = SkyPawsEngine()

        engine.start(in: size, seed: 0xCAFE_BABE)

        for (previous, next) in zip(engine.gates, engine.gates.dropFirst()) {
            XCTAssertLessThanOrEqual(
                abs(next.gapCenter - previous.gapCenter),
                SkyPawsEngine.maximumGateCenterShift + 0.001
            )
        }
    }

    func testPetsDashProvidesFourRearViewFramesForEverySelectableVariant() {
        let variants: [(PetSpecies, PetBreed, String)] = [
            (.cat, .classicCat, "cat_classic"),
            (.cat, .britishShorthair, "cat_british"),
            (.cat, .maineCoon, "cat_maine_coon"),
            (.cat, .siamese, "cat_siamese"),
            (.dog, .shepherd, "dog_shepherd"),
            (.dog, .corgi, "dog_corgi"),
            (.dog, .doberman, "dog_doberman"),
            (.dog, .bullTerrier, "dog_bull_terrier"),
            (.fox, .redFox, "fox_red"),
            (.fox, .arcticFox, "fox_arctic"),
            (.parrot, .classicParrot, "parrot_classic"),
            (.parrot, .cockatiel, "parrot_cockatiel"),
            (.parrot, .budgie, "parrot_budgie"),
            (.parrot, .macaw, "parrot_macaw"),
            (.penguin, .classicPenguin, "penguin_classic"),
            (.penguin, .rockhopper, "penguin_rockhopper")
        ]

        for (species, breed, token) in variants {
            XCTAssertEqual(
                PetsDashArtworkLibrary.assetNames(for: species, breed: breed),
                (0..<4).map { "pets_dash_\(token)_\(String(format: "%02d", $0))" }
            )
        }
    }

    func testPetsDashEngineSupportsThreeLanesAndJumping() {
        var engine = PetsDashEngine()
        let size = CGSize(width: 393, height: 852)

        engine.start(in: size)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.lane, 1)

        engine.moveLane(-1)
        engine.moveLane(-1)
        XCTAssertEqual(engine.lane, 0)
        engine.moveLane(1)
        XCTAssertEqual(engine.lane, 1)

        engine.jump()
        engine.update(deltaTime: 1.0 / 60.0, in: size)
        XCTAssertTrue(engine.isJumping)
        XCTAssertGreaterThan(engine.jumpHeight, 0)
    }

    func testPetsDashObstacleEndsRunWithoutAJump() {
        var engine = PetsDashEngine()
        let size = CGSize(width: 393, height: 852)
        engine.start(in: size)
        engine.objects = [
            PetsDashObject(id: 99, kind: .barrier, lane: 1, progress: 0.82)
        ]

        engine.update(deltaTime: 1.0 / 60.0, in: size)

        XCTAssertEqual(engine.phase, .gameOver)
    }

    func testPetsDashCollectedCoinDisappearsImmediately() {
        var engine = PetsDashEngine()
        let size = CGSize(width: 393, height: 852)
        engine.start(in: size, seed: 1)
        engine.objects = [
            PetsDashObject(id: 7, kind: .coin, lane: 1, progress: 0.78)
        ]

        engine.update(deltaTime: 1.0 / 60.0, in: size)

        XCTAssertEqual(engine.coinsCollected, 1)
        XCTAssertTrue(engine.objects.isEmpty)
    }

    func testPetsDashSeedChangesTheFirstWave() {
        let size = CGSize(width: 393, height: 852)
        var first = PetsDashEngine()
        var second = PetsDashEngine()
        first.start(in: size, seed: 1)
        second.start(in: size, seed: 2)

        for _ in 0..<18 {
            first.update(deltaTime: 1.0 / 24.0, in: size)
            second.update(deltaTime: 1.0 / 24.0, in: size)
        }

        XCTAssertNotEqual(first.objects, second.objects)
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

    func testCatalogContainsSupportedSpecies() {
        XCTAssertEqual(PetSpecies.allCases.count, 5)
        XCTAssertEqual(PetSpecies.selectableCases, [.cat, .dog, .fox, .parrot, .penguin])
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

    func testDynamicIslandPresetsMatchSettingsChoices() {
        XCTAssertEqual(SessionPreset.allCases.map(\.rawValue), [20, 40, 60, 120, 240])
    }

    func testDynamicIslandMotionModesResolveTheirStartingPose() {
        XCTAssertEqual(DynamicIslandMotionMode.run.initialPose, .run)
        XCTAssertEqual(DynamicIslandMotionMode.walk.initialPose, .walk)
        XCTAssertEqual(DynamicIslandMotionMode.sleep.initialPose, .sleep)
        XCTAssertEqual(DynamicIslandMotionMode.run.initialPose(for: .parrot), .fly)
        XCTAssertEqual(DynamicIslandMotionMode.walk.initialPose(for: .parrot), .fly)
        XCTAssertTrue(DynamicIslandMotionMode.runWalkSleep.includesSleep)
        XCTAssertFalse(DynamicIslandMotionMode.run.includesSleep)
    }

    func testArcadeAwardsPerformanceRecordAndDailyCoins() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDate = Date(timeIntervalSince1970: 1_750_000_000)
        var progress = ArcadeProgress()

        let first = progress.record(
            game: .skyHop,
            score: 550,
            wasTired: false,
            at: firstDate,
            calendar: calendar
        )
        let second = progress.record(
            game: .skyHop,
            score: 700,
            wasTired: true,
            at: firstDate.addingTimeInterval(60),
            calendar: calendar
        )

        XCTAssertEqual(first.coinsEarned, 20)
        XCTAssertTrue(first.isNewHighScore)
        XCTAssertTrue(first.receivedDailyBonus)
        XCTAssertEqual(second.coinsEarned, 10)
        XCTAssertTrue(second.isNewHighScore)
        XCTAssertFalse(second.receivedDailyBonus)
        XCTAssertTrue(second.wasTired)
        XCTAssertEqual(progress.coins, 30)
        XCTAssertEqual(progress.highScore(for: .skyHop), 700)
    }

    func testSkyHopCreatesDifferentMapsForDifferentRuns() {
        let size = CGSize(width: 390, height: 844)
        var firstRun = SkyHopEngine()
        var secondRun = SkyHopEngine()

        firstRun.start(in: size, seed: 101)
        secondRun.start(in: size, seed: 202)

        XCTAssertNotEqual(firstRun.platforms, secondRun.platforms)
    }

    func testSkyHopSeedKeepsGeneratedMapReproducibleForTests() {
        let size = CGSize(width: 390, height: 844)
        var firstRun = SkyHopEngine()
        var repeatedRun = SkyHopEngine()

        firstRun.start(in: size, seed: 7_777)
        repeatedRun.start(in: size, seed: 7_777)

        XCTAssertEqual(firstRun.platforms, repeatedRun.platforms)
    }

    func testSkyHopGeneratedPlatformsStayInsidePlayableBounds() {
        let size = CGSize(width: 390, height: 844)
        var engine = SkyHopEngine()

        engine.start(in: size, seed: 42)

        XCTAssertGreaterThan(engine.platforms.count, 5)
        XCTAssertEqual(engine.platforms.first?.x, size.width / 2)
        XCTAssertTrue(engine.platforms.dropFirst().allSatisfy { platform in
            platform.x >= 52
                && platform.x <= size.width - 52
                && platform.width >= 72
                && platform.width <= 112
        })

        let verticalGaps = zip(engine.platforms, engine.platforms.dropFirst()).map { lower, upper in
            lower.y - upper.y
        }
        XCTAssertTrue(verticalGaps.allSatisfy { $0 >= 76 && $0 <= 108 })
    }

    func testArcadeShopMovesCoinsIntoInventory() {
        var progress = ArcadeProgress(coins: 24)

        XCTAssertTrue(progress.purchase(.toy))
        XCTAssertEqual(progress.coins, 0)
        XCTAssertEqual(progress.inventory[.toy], 1)
        XCTAssertTrue(progress.consume(.toy))
        XCTAssertEqual(progress.inventory[.toy], 0)
        XCTAssertFalse(progress.consume(.toy))
    }

    func testArcadeVitalsCreateAClosedCareLoop() {
        let starting = PetVitals(fullness: 0.5, happiness: 0.5, energy: 0.5)
        let afterGame = ArcadeEconomy.vitalsAfterPlaying(starting)
        let afterFood = ArcadeEconomy.vitals(afterGame, afterUsing: .food)
        let afterVitamins = ArcadeEconomy.vitals(afterFood, afterUsing: .vitamins)

        XCTAssertEqual(afterGame.fullness, 0.48, accuracy: 0.0001)
        XCTAssertEqual(afterGame.happiness, 0.58, accuracy: 0.0001)
        XCTAssertEqual(afterGame.energy, 0.445, accuracy: 0.0001)
        XCTAssertGreaterThan(afterFood.fullness, starting.fullness)
        XCTAssertGreaterThan(afterVitamins.energy, starting.energy)
    }

    func testArcadeStateRoundTripsWithPetVitals() throws {
        let petID = UUID()
        var state = ArcadeState()
        state.vitalsByPetID[petID] = PetVitals(fullness: 0.4, happiness: 0.6, energy: 0.8)
        _ = state.progress.record(game: .skyHop, score: 900, wasTired: false)
        XCTAssertTrue(state.progress.purchase(.food))

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ArcadeState.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, ArcadeState.schemaVersion)
        XCTAssertEqual(decoded.vitalsByPetID[petID]?.energy, 0.8)
        XCTAssertEqual(decoded.progress.highScore(for: .skyHop), 900)
        XCTAssertEqual(decoded.progress.inventory[.food], 1)
    }

    func testLegacySettingsDecodeWithDynamicIslandDefaults() throws {
        let data = Data(#"{"defaultSessionMinutes":40,"hapticsEnabled":false,"minimizeMotion":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.defaultSessionMinutes, 40)
        XCTAssertEqual(settings.dynamicIslandMotionMode, .runSleep)
        XCTAssertFalse(settings.hapticsEnabled)
        XCTAssertTrue(settings.minimizeMotion)
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
