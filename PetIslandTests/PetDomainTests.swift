import XCTest
import CoreText
import SwiftUI
@testable import PetIsland

final class PetDomainTests: XCTestCase {

    func testAllSelectableAppIconsAreBundledWithPreviews() throws {
        let bundleIcons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(bundleIcons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        let alternates = try XCTUnwrap(bundleIcons["CFBundleAlternateIcons"] as? [String: Any])
        let expected = Set(AppIconChoice.allCases.compactMap(\.alternateName))
        XCTAssertEqual(expected.count, 5)
        XCTAssertEqual(Set(alternates.keys), expected)
        XCTAssertNil(AppIconChoice.classic.alternateName)
        for choice in AppIconChoice.allCases {
            XCTAssertNotNil(UIImage(named: choice.previewName), "Missing preview for \(choice)")
            guard let name = choice.alternateName else { continue }
            let icon = try XCTUnwrap(alternates[name] as? [String: Any])
            XCTAssertEqual(icon["CFBundleIconName"] as? String, name)
        }
    }

    @MainActor
    func testUnreadableSaveBlocksBootstrapWithoutReplacingFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("state.json")
        let broken = Data("unreadable save".utf8)
        try broken.write(to: file)
        try broken.write(to: file.appendingPathExtension("backup"))
        let controller = PetSessionController(store: FilePetStore(fileURL: file), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertEqual(controller.operation, .loadFailed)
        XCTAssertTrue(controller.isBusy)
        XCTAssertEqual(try Data(contentsOf: file), broken)
        XCTAssertEqual(try Data(contentsOf: file.appendingPathExtension("backup")), broken)
        var recovered = PersistedAppState()
        recovered.profile.name = "Recovered companion"
        try await FilePetStore(fileURL: file).save(recovered)
        await controller.bootstrap()
        XCTAssertEqual(controller.operation, .idle)
        XCTAssertEqual(controller.profile.name, recovered.profile.name)
    }

    func testUnreadableArcadeSaveThrowsInsteadOfResettingWallet() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let broken = Data("broken wallet".utf8)
        try broken.write(to: file)
        do {
            _ = try await FileArcadeStore(fileURL: file).load()
            XCTFail("Corruption must not look like a fresh installation")
        } catch {
            XCTAssertEqual(try Data(contentsOf: file), broken)
        }
    }

    func testRestRestoresEnergyWithoutPenalizingAbsenceOrClockChanges() {
        let date = Date(timeIntervalSince1970: 10_000)
        let tired = PetVitals(fullness: 0.4, happiness: 0.5, energy: 0.2)
        let rested = tired.projected(from: date, to: date.addingTimeInterval(5 * 3600))
        XCTAssertEqual(rested.energy, 0.4, accuracy: 0.000001)
        XCTAssertEqual(rested.fullness, tired.fullness)
        XCTAssertEqual(rested.happiness, tired.happiness)
        XCTAssertEqual(tired.projected(from: date, to: date.addingTimeInterval(-3600)), tired)
        XCTAssertEqual(tired.projected(from: .distantPast, to: date), tired)
        XCTAssertEqual(tired.projected(from: date, to: date.addingTimeInterval(7 * 24 * 3600)).energy, 1)
    }

    func testRestAndWidgetCareAreMaterializedExactlyOnce() {
        let date = Date(timeIntervalSince1970: 20_000)
        let pet = PetProfile.starter
        var shared = SharedPetHabitat(configuration: PetHabitatState(residentPetIDs: [pet.id]),
            residents: [SharedHabitatResident(profile: pet, vitals: PetVitals(energy: 0.2), vitalsUpdatedAt: date)])
        let event = PetCareEvent(petID: pet.id, fullness: 0, happiness: 0, energy: -0.05,
                                 date: date.addingTimeInterval(5 * 3600))
        shared.apply(event)
        shared.apply(event)
        XCTAssertEqual(shared.residents[0].vitals.energy, 0.35, accuracy: 0.000001)
        shared.playWithResidents(at: event.date.addingTimeInterval(3600))
        XCTAssertEqual(shared.residents[0].vitals.energy, 0.355, accuracy: 0.000001)
    }

    func testDismissedActivityChoiceSurvivesSaveAndLegacyStateStillLoads() throws {
        var state = PersistedAppState()
        state.dismissedActivitySessionID = UUID()
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistedAppState.self, from: encoded)
        XCTAssertEqual(decoded.dismissedActivitySessionID, state.dismissedActivitySessionID)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "dismissedActivitySessionID")
        let legacy = try JSONDecoder().decode(PersistedAppState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.dismissedActivitySessionID)
        XCTAssertEqual(legacy.pets, state.pets)
    }

    @MainActor
    func testCoatDoesNotChangeTimerGlyphGeometry() throws {
        try registerTimerFonts()
        let viewport = CGSize(width: 84, height: 72)
        for coat in PetCoat.allCases {
            for customColor in [nil, PetColorSelection(red: 0.6, green: 0.2, blue: 0.9)] {
                let glyph = PetTimerGlyphViewport(text: Text("12:00:00"), fontName: "PetIslandLockTimerDogShepherdRun", viewport: viewport)
                let colored = glyph.petCoat(species: .dog, coat: coat, customColor: customColor)
                XCTAssertEqual(try renderedBounds(glyph), try renderedBounds(colored))
            }
        }
    }

    @MainActor
    func testEnclosureKeepsExistingPositionsWhenResidentsChange() {
        let simulation = HabitatMotionSimulation()
        let pets = (0..<6).map { PetProfile(id: UUID(), name: "Pet \($0)", species: .cat, coat: .sunrise, createdAt: .now) }
        let size = CGSize(width: 345, height: 240)
        simulation.configure(pets: Array(pets.prefix(3)), size: size)
        for _ in 0..<300 { simulation.advance(by: 1.0 / 60) }
        let before = simulation.actors
        simulation.configure(pets: pets, size: size)
        for actor in before {
            let after = simulation.actors.first { $0.id == actor.id }!
            XCTAssertEqual(actor.position, after.position)
            XCTAssertEqual(actor.gaitPhase, after.gaitPhase)
        }
        simulation.configure(pets: Array(pets.dropFirst()), size: size)
        for actor in before.dropFirst() {
            XCTAssertEqual(simulation.actors.first { $0.id == actor.id }?.position, actor.position)
        }
    }

    @MainActor
    func testEnclosureMovesContinuouslyAndFreezesForReduceMotion() {
        let simulation = HabitatMotionSimulation()
        let pets = (0..<6).map { PetProfile(id: UUID(), name: "Pet \($0)", species: .dog, coat: .sunrise, createdAt: .now) }
        simulation.configure(pets: pets, size: CGSize(width: 320, height: 240), petScale: 1.2)
        var travelled = 0.0
        for _ in 0..<3600 {
            let before = simulation.actors
            simulation.advance(by: 1.0 / 60)
            for (old, new) in zip(before, simulation.actors) {
                let distance = hypot(new.position.x - old.position.x, new.position.y - old.position.y)
                XCTAssertLessThan(distance, 1.5)
                XCTAssertTrue(new.position.x.isFinite && new.position.y.isFinite)
                XCTAssertTrue((30...290).contains(new.position.x))
                travelled += distance
            }
        }
        XCTAssertGreaterThan(travelled, 1000)
        simulation.start(reduceMotion: true, active: true)
        let positions = simulation.actors.map(\.position)
        simulation.advance(by: 1)
        XCTAssertEqual(positions, simulation.actors.map(\.position))
    }

    func testNaturalGaitFramesAreCompleteWithoutChangingSystemClips() {
        for species in PetSpecies.allCases where species != .parrot {
            for breed in PetBreed.available(for: species) {
                for pose in [PetPose.walk, .run] {
                    let clip = PetAnimationLibrary.naturalClip(for: species, breed: breed, pose: pose)
                    XCTAssertEqual(clip.frames.count, 8)
                    XCTAssertEqual(Set(clip.frames).count, 8)
                    for name in clip.frames {
                        XCTAssertNotNil(UIImage(named: name), name)
                        let geometry = PetSpriteGeometry.load(assetName: name)
                        let origin = breed.companionArtworkToken == nil ? CGPoint(x: -12, y: 0) : .zero
                        XCTAssertEqual(geometry?.rect(in: PetSpriteGeometry.canvas).origin, origin, name)
                        XCTAssertEqual(geometry?.scale, 1, name)
                    }
                    XCTAssertEqual(PetAnimationLibrary.clip(for: species, breed: breed, pose: pose).frames.count,
                                   breed.companionArtworkToken == nil ? 2 : 8)
                }
            }
        }
    }

    @MainActor
    func testFailedPetSaveKeepsCollectionAndAllowsRetry() async {
        let store = FailablePetStore()
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let original = controller.pets
        let pet = PetProfile(id: UUID(), name: "Retry", species: .cat, coat: .cloud, createdAt: .now)
        await store.setFailure(true)
        let failed = await controller.addPet(pet)
        XCTAssertFalse(failed)
        XCTAssertEqual(controller.pets, original)
        XCTAssertNotNil(controller.alertMessage)
        await store.setFailure(false)
        let saved = await controller.addPet(pet)
        XCTAssertTrue(saved)
        XCTAssertEqual(controller.pets.filter { $0.id == pet.id }.count, 1)
    }

    @MainActor
    func testFailedRewardDoesNotChangeWalletAndRetryIsIdempotent() async {
        let store = FailableArcadeStore()
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await controller.bootstrap()
        let run = UUID()
        let original = controller.arcadeProgress
        await store.setFailure(true)
        let failed = await controller.completeMiniGame(.skyPaws, score: 400, petID: controller.profile.id, runID: run)
        XCTAssertNil(failed)
        XCTAssertEqual(controller.arcadeProgress, original)
        await store.setFailure(false)
        let reward = await controller.completeMiniGame(.skyPaws, score: 400, petID: controller.profile.id, runID: run)
        let coins = controller.arcadeProgress.coins
        let repeated = await controller.completeMiniGame(.skyPaws, score: 400, petID: controller.profile.id, runID: run)
        XCTAssertNotNil(reward)
        XCTAssertEqual(reward, repeated)
        XCTAssertEqual(controller.arcadeProgress.coins, coins)
        XCTAssertEqual(controller.arcadeProgress.gamesPlayed, 1)
    }

    @MainActor
    func testFailedPurchaseDoesNotSpendCoinsOrAddInventory() async {
        let store = FailableArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 100)))
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: store)
        await controller.bootstrap()
        await store.setFailure(true)
        let result = await controller.purchaseArcadeItem(.food)
        XCTAssertFalse(result)
        XCTAssertEqual(controller.arcadeProgress.coins, 100)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 0)
    }

    func testSharedSnapshotRecoversAgainAfterReplacingCorruptPrimary() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = SharedSnapshotFile<[Int]>(url: root.appending(path: "snapshot.plist"))
        try file.update(fallback: { [0] }) { $0 = [10] }
        try file.update(fallback: { [0] }) { $0 = [20] }
        try Data("broken".utf8).write(to: file.url)
        XCTAssertEqual(try file.load(fallback: { [0] }), [10])
        try Data("broken again".utf8).write(to: file.url)
        XCTAssertEqual(try file.load(fallback: { [0] }), [10])
    }

    func testSharedSnapshotRejectsUnreadableStateInsteadOfResettingIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = SharedSnapshotFile<[Int]>(url: root.appending(path: "snapshot.plist"))
        let broken = Data("unrecoverable".utf8)
        try broken.write(to: file.url)
        XCTAssertThrowsError(try file.update(fallback: { [0] }) { $0[0] += 1 })
        XCTAssertEqual(try Data(contentsOf: file.url), broken)
    }

    func testCareOutboxCombinesWidgetAndAppChangesExactlyOnce() {
        let pet = PetProfile.starter
        var habitat = SharedPetHabitat(configuration: PetHabitatState(residentPetIDs: [pet.id]),
            residents: [SharedHabitatResident(profile: pet, vitals: PetVitals(fullness: 0.5, happiness: 0.5, energy: 0.5))])
        let event = PetCareEvent(petID: pet.id, fullness: -0.02, happiness: 0.08, energy: -0.055, date: .now)
        habitat.playWithResidents(at: .now)
        habitat.apply(event)
        habitat.apply(event)
        XCTAssertEqual(habitat.residents[0].vitals.happiness, 0.7, accuracy: 0.00001)
        XCTAssertEqual(habitat.residents[0].vitals.energy, 0.41, accuracy: 0.00001)
        XCTAssertEqual(habitat.appliedCareEventIDs, [event.id])
    }

    func testTravellingPetHasAReservedBerthAndAlwaysReturns() {
        let pets = (0..<8).map { _ in UUID() }
        var habitat = PetHabitatState(residentPetIDs: Array(pets.prefix(6)))
        habitat.setDynamicIslandLead(pets[6])
        habitat.setResidents(Array(pets.prefix(6)))
        XCTAssertEqual(habitat.residentPetIDs.count, 5)
        XCTAssertTrue(habitat.returnDynamicIslandLeadToHabitat())
        XCTAssertEqual(habitat.residentPetIDs.count, 6)
        XCTAssertTrue(habitat.residentPetIDs.contains(pets[6]))
        XCTAssertNil(habitat.leadDynamicIslandPetID)
    }

    func testHabitatPawsTakeSeveralStepsPerBodyLengthWithoutMovingWhenStopped() {
        for pose in [PetPose.walk, .run] {
            let clip = PetAnimationLibrary.clip(for: .dog, breed: .shepherd, pose: pose)
            let width = 90.0
            let frames = (0...90).map { distance in
                clip.travelFrameIndex(distance: Double(distance), canvasWidth: width, pose: pose)
            }
            let changes = zip(frames, frames.dropFirst()).filter { $0 != $1 }.count
            XCTAssertGreaterThanOrEqual(changes, 7, "Paws should not slide over a whole body length")
            XCTAssertLessThanOrEqual(changes, 12, "Avoid flickering through steps")
            for _ in 0..<30 {
                XCTAssertEqual(clip.travelFrameIndex(distance: 37, canvasWidth: width, pose: pose), frames[37])
            }
        }
    }

    @MainActor
    func testTimerGlyphMatchesPNGSizeGroundAndDirectionIncludingSleepFallback() throws {
        try registerTimerFonts()
        let samples: [(PetSpecies, PetBreed, String)] = [
            (.dog, .shepherd, "DogShepherd"), (.dog, .corgi, "DogCorgi"),
            (.dog, .doberman, "DogDoberman"), (.dog, .bullTerrier, "DogBullTerrier"),
            (.cat, .classicCat, "CatClassic"), (.cat, .britishShorthair, "CatBritish"),
            (.cat, .maineCoon, "CatMaineCoon"), (.cat, .siamese, "CatSiamese"),
            (.fox, .redFox, "FoxRed"), (.fox, .arcticFox, "FoxArctic"),
            (.parrot, .classicParrot, "ParrotClassic"), (.parrot, .cockatiel, "ParrotCockatiel"),
            (.parrot, .budgie, "ParrotBudgie"), (.parrot, .macaw, "ParrotMacaw"),
            (.penguin, .classicPenguin, "PenguinClassic"), (.penguin, .rockhopper, "PenguinRockhopper"),
            (.dog, .cardigan, "DogCardigan"), (.lion, .adultLion, "LionAdult"),
            (.lion, .lioness, "Lioness"), (.lion, .lionCub, "LionCub")
        ]
        for (species, breed, token) in samples {
            for viewport in [CGSize(width: 36, height: 30), CGSize(width: 28, height: 25), CGSize(width: 84, height: 72)] {
                let family = viewport.width == 84 ? "PetIslandLockTimer" : "PetIslandTimer"
                for pose in [PetPose.run, .walk, .sleep] {
                    let suffix = pose == .run ? "Run" : pose == .walk ? "Walk" : "Sleep"
                    for direction in [PetDirection.left, .right] {
                        let glyph = PetTimerGlyphViewport(text: Text("0"),
                            fontName: family + token + suffix, viewport: viewport, direction: direction)
                        let artwork = PetArtwork(species: species, breed: breed, pose: pose,
                                                 direction: direction, step: 0, animatesMotion: false)
                            .frame(width: viewport.width, height: viewport.height)
                        let fontBounds = try renderedBounds(glyph)
                        let pngBounds = try renderedBounds(artwork)
                        let sample = "\(breed), \(pose), \(viewport)"
                        XCTAssertEqual(fontBounds.minX, pngBounds.minX, accuracy: 1.5, sample)
                        XCTAssertEqual(fontBounds.maxX, pngBounds.maxX, accuracy: 1.5, sample)
                        XCTAssertEqual(fontBounds.minY, pngBounds.minY, accuracy: 1.5, sample)
                        XCTAssertEqual(fontBounds.maxY, pngBounds.maxY, accuracy: 1.5, sample)
                    }
                }
            }
        }
    }

    @MainActor
    func testTimerDoesNotShiftAcrossGaitStatesOrMinuteAndHourRollovers() throws {
        try registerTimerFonts()
        let viewport = CGSize(width: 84, height: 72)
        let name = "PetIslandLockTimerDogShepherdRunWalkSleep"
        var bottoms: [CGFloat] = []
        for digit in 0...9 {
            let bounds = try renderedBounds(PetTimerGlyphViewport(text: Text("\(digit)"), fontName: name, viewport: viewport))
            bottoms.append(bounds.maxY)
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(bottoms.max()) - XCTUnwrap(bottoms.min()), 1)
        let reference = try renderedBounds(PetTimerGlyphViewport(text: Text("0"), fontName: name, viewport: viewport))
        for timer in ["0:00", "1:00", "10:00", "1:00:00", "24:00:00", "100:00:00"] {
            let bounds = try renderedBounds(PetTimerGlyphViewport(text: Text(timer), fontName: name, viewport: viewport))
            XCTAssertEqual(bounds, reference, timer)
        }
    }

    private func registerTimerFonts() throws {
        for family in ["PetIslandTimer", "PetIslandLockTimer"] {
            let name = family + "DogShepherdRun"
            if CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 84, nil)) as String != name {
                let url = Bundle.main.bundleURL
                    .appendingPathComponent("PlugIns/PetIslandLiveActivity.appex/\(family)Pets.ttc")
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
            let font = CTFontCreateWithName(name as CFString, 84, nil)
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
        }
    }

    @MainActor
    private func renderedBounds<V: View>(_ view: V) throws -> CGRect {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var left = image.width, top = image.height, right = 0, bottom = 0
        for y in 0..<image.height {
            for x in 0..<image.width where pixels[(y * image.width + x) * 4 + 3] > 32 {
                left = min(left, x); top = min(top, y)
                right = max(right, x + 1); bottom = max(bottom, y + 1)
            }
        }
        XCTAssertGreaterThan(right, left, "The timer sprite must stay visible")
        return CGRect(x: CGFloat(left) / 3, y: CGFloat(top) / 3,
                      width: CGFloat(right - left) / 3, height: CGFloat(bottom - top) / 3)
    }

    func testSkyHopKeepsEveryPlatformReachableOnWideScreens() {
        for seed in 0..<30 {
            var engine = SkyHopEngine()
            engine.start(in: CGSize(width: 1024, height: 1366), seed: UInt64(seed))
            for (a, b) in zip(engine.platforms, engine.platforms.dropFirst()) {
                XCTAssertLessThanOrEqual(abs(a.x - b.x), SkyHopEngine.maximumPlatformShift)
            }
        }
    }

    func testAllArcadeEnginesIgnoreNonFiniteTimeSteps() {
        let size = CGSize(width: 393, height: 852)
        var hop = SkyHopEngine(), paws = SkyPawsEngine(), dash = PetsDashEngine()
        hop.start(in: size, seed: 1)
        paws.start(in: size, seed: 1)
        dash.start(in: size, seed: 1)
        let hopPosition = hop.playerPosition, pawsPosition = paws.playerY
        for dt in [Double.nan, .infinity, -.infinity, -1, 0] {
            hop.update(deltaTime: dt, in: size)
            paws.update(deltaTime: dt, in: size)
            dash.update(deltaTime: dt, in: size)
        }
        XCTAssertEqual(hop.playerPosition, hopPosition)
        XCTAssertEqual(paws.playerY, pawsPosition)
        XCTAssertEqual(dash.score, 0)
        XCTAssertEqual(dash.trackProgress, 0)
    }

    func testSavedSessionCannotReferenceDeletedPet() {
        var state = PersistedAppState()
        state.activeSession = PetSession(id: UUID(), petID: UUID(), startedAt: .now,
                                        endsAt: .distantFuture, snapshot: .initial(at: .now))
        state.normalizePetCollection()
        XCTAssertNil(state.activeSession)
    }

    func testPersistedDurationIsClampedBeforeConvertingToSeconds() throws {
        let data = Data("{\"defaultSessionMinutes\":9223372036854775807}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.defaultSessionMinutes, 480)
        XCTAssertEqual(AppSettings(defaultSessionMinutes: -1).defaultSessionMinutes, 10)
    }

    func testStrideFramesAreDrivenByDistanceAndHoldWhenStopped() {
        let clip = PetAnimationClip(frames: ["contact-left", "contact-right"], frameDuration: 0.13)
        XCTAssertEqual(clip.frameIndex(distance: 0, strideLength: 60), 0)
        XCTAssertEqual(clip.frameIndex(distance: 29, strideLength: 60), 0)
        XCTAssertEqual(clip.frameIndex(distance: 30, strideLength: 60), 1)
        XCTAssertEqual(clip.frameIndex(distance: 60, strideLength: 60), 0)
        for _ in 0..<100 { XCTAssertEqual(clip.frameIndex(distance: 45, strideLength: 60), 1) }
        XCTAssertEqual(clip.frameIndex(distance: .infinity, strideLength: 60), 0)
    }

    func testDogWalkAndRunUseOneGroundPlaneWithoutRescaling() {
        let size = CGSize(width: 88, height: 70.4)
        let walk = PetSpriteGeometry(sourceSize: .init(width: 220, height: 176),
                                     visibleBounds: .init(x: 42, y: 54, width: 136, height: 117),
                                     assetName: "island_dog_corgi_walk_0")
        let run = PetSpriteGeometry(sourceSize: .init(width: 220, height: 176),
                                    visibleBounds: .init(x: 23, y: 45, width: 173, height: 115),
                                    assetName: "island_dog_corgi_run_0")
        let walkRect = walk.rect(in: size), runRect = run.rect(in: size)
        XCTAssertEqual(walkRect.width, runRect.width)
        XCTAssertEqual(walkRect.minY + walk.visibleBounds.maxY * 0.4, 64, accuracy: 0.001)
        XCTAssertEqual(runRect.minY + run.visibleBounds.maxY * 0.4, 64, accuracy: 0.001)
    }

    func testShepherdLegacyPosesHaveAConstantScale() {
        let idle = PetSpriteGeometry(sourceSize: .init(width: 362, height: 362),
                                     visibleBounds: .init(x: 70, y: 78, width: 267, height: 273),
                                     assetName: "sprite_dog_idle_0")
        let play = PetSpriteGeometry(sourceSize: .init(width: 362, height: 362),
                                     visibleBounds: .init(x: 62, y: 136, width: 268, height: 215),
                                     assetName: "sprite_dog_swipe_0")
        XCTAssertEqual(idle.scale, play.scale)
        XCTAssertEqual(idle.scale * 273, 148, accuracy: 0.001)
        XCTAssertEqual(idle.rect(in: PetSpriteGeometry.canvas), play.rect(in: PetSpriteGeometry.canvas))
    }

    func testEverySelectablePetPoseHasVisibleBundledArtwork() throws {
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for pose in PetPose.allCases {
                    for name in PetAnimationLibrary.clip(for: species, breed: breed, pose: pose).frames {
                        let geometry = try XCTUnwrap(PetSpriteGeometry.load(assetName: name), name)
                        XCTAssertGreaterThan(geometry.visibleBounds.width, 0)
                        XCTAssertGreaterThan(geometry.visibleBounds.height, 0)
                        let rect = geometry.rect(in: PetSpriteGeometry.canvas)
                        let foot = rect.minY + geometry.visibleBounds.maxY * geometry.scale
                        if breed.companionArtworkToken != nil {
                            XCTAssertEqual(rect.origin, .zero, name)
                            XCTAssertLessThanOrEqual(foot, PetSpriteGeometry.baseline + 1, name)
                            if [.walk, .idle, .play, .sleep, .eat].contains(pose) {
                                XCTAssertEqual(foot, PetSpriteGeometry.baseline, accuracy: 1, name)
                            }
                        } else {
                            XCTAssertEqual(foot, PetSpriteGeometry.baseline, accuracy: 0.001, name)
                        }
                    }
                }
            }
        }
    }

    func testRepairedWalkFramesKeepTheirGroundAndUpperBodyRegistration() throws {
        for breed in ["cat_maine_coon", "cat_siamese", "fox"] {
            let first = try XCTUnwrap(PetSpriteGeometry.load(assetName: "island_\(breed)_walk_0"))
            let second = try XCTUnwrap(PetSpriteGeometry.load(assetName: "island_\(breed)_walk_1"))
            XCTAssertEqual(first.sourceSize, PetSpriteGeometry.canvas)
            XCTAssertEqual(second.sourceSize, PetSpriteGeometry.canvas)
            XCTAssertEqual(first.visibleBounds.minY, second.visibleBounds.minY)
            XCTAssertEqual(first.visibleBounds.maxX, second.visibleBounds.maxX)
            XCTAssertEqual(first.visibleBounds.maxY, PetSpriteGeometry.baseline)
            XCTAssertEqual(second.visibleBounds.maxY, PetSpriteGeometry.baseline)
            XCTAssertEqual(first.rect(in: PetSpriteGeometry.canvas).origin, .zero)
            XCTAssertEqual(second.rect(in: PetSpriteGeometry.canvas).origin, .zero)
        }
    }

    @MainActor
    func testPlayYardFetchesForAllSixResidentsWithoutGroundedJitter() throws {
        let pets = (0..<6).map { index in
            PetProfile(id: UUID(), name: "Pet \(index)", species: PetSpecies.allCases[index % 5],
                       coat: .sunrise, createdAt: .now)
        }
        let yard = PlayYardSimulation(pets: pets, hapticsEnabled: false)
        yard.configure(roomSize: CGSize(width: 393, height: 740))
        XCTAssertEqual(yard.frame.actors.count, 6)
        for round in 0..<6 {
            yard.throwAccessibleBall()
            XCTAssertEqual(yard.frame.fetcherID, pets[round].id)
            var previous = yard.frame.actors
            for _ in 0..<900 where yard.frame.phase != .ready {
                yard.advance(by: 1.0 / 30.0)
                for (old, new) in zip(previous, yard.frame.actors) {
                    if (old.pose == .run || old.pose == .walk),
                       (new.pose == .run || new.pose == .walk), !old.isAirborne, !new.isAirborne {
                        XCTAssertEqual(old.position.y, new.position.y, accuracy: 0.001)
                    }
                    XCTAssertLessThanOrEqual(abs(new.position.x - old.position.x), 8)
                    let dx = new.position.x - old.position.x
                    if abs(dx) > 0.1 {
                        XCTAssertEqual(new.direction, dx > 0 ? .right : .left)
                    }
                    XCTAssertTrue(new.position.x.isFinite && new.position.y.isFinite)
                }
                previous = yard.frame.actors
            }
            XCTAssertEqual(yard.frame.phase, .ready)
            XCTAssertEqual(yard.frame.score, round + 1)
        }
    }

    @MainActor
    func testPlayYardReleasesItsDisplayLinkAndCancelsInterruptedDrag() {
        var yard: PlayYardSimulation? = PlayYardSimulation(pets: [.starter], hapticsEnabled: false)
        weak let weakYard = yard
        yard?.configure(roomSize: CGSize(width: 393, height: 740))
        yard?.start(reduceMotion: false)
        yard?.dragBall(to: CGPoint(x: 180, y: 400))
        yard?.stop()
        XCTAssertEqual(yard?.frame.isDraggingBall, false)
        yard?.start(reduceMotion: false)
        yard = nil
        XCTAssertNil(weakYard)
    }

    @MainActor
    func testChangingLeadUpdatesSharedProfileAndWidgetNavigation() async {
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let cat = PetProfile(id: UUID(), name: "Milo", species: .cat, coat: .cloud, createdAt: .now)
        _ = await controller.addPet(cat)
        _ = await controller.makeLeadPet(id: cat.id)
        XCTAssertEqual(controller.lifeState.profile.id, cat.id)
        XCTAssertEqual(PetLifeStore.load().profile.id, cat.id)
        controller.selectedTab = .settings
        controller.handleDeepLink(URL(string: "petisland://playroom")!)
        XCTAssertEqual(controller.selectedTab, .island)
        XCTAssertTrue(controller.showsPlayYard)
        controller.showsPlayYard = false
        controller.selectedTab = .pets
        controller.handleDeepLink(URL(string: "https://playroom")!)
        XCTAssertEqual(controller.selectedTab, .pets)
        XCTAssertFalse(controller.showsPlayYard)
    }

    func testCollectionAndArcadeRecoverTheirLastGoodSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let petURL = folder.appendingPathComponent("state.json")
        let store = FilePetStore(fileURL: petURL)
        var original = PersistedAppState()
        original.profile.name = "Saved friend"
        try await store.save(original)
        var changed = original
        changed.profile.name = "Next save"
        try await store.save(changed)
        try Data("broken json".utf8).write(to: petURL)
        let recovered = try await store.load()
        XCTAssertEqual(recovered.profile.name, "Saved friend")
        XCTAssertEqual(recovered.profile.id, original.profile.id)

        let arcadeURL = folder.appendingPathComponent("arcade.json")
        let arcadeStore = FileArcadeStore(fileURL: arcadeURL)
        let arcade = ArcadeState(progress: ArcadeProgress(coins: 42))
        try await arcadeStore.save(arcade)
        try await arcadeStore.save(ArcadeState(progress: ArcadeProgress(coins: 50)))
        try Data("broken json".utf8).write(to: arcadeURL)
        let recoveredArcade = try await arcadeStore.load()
        XCTAssertEqual(recoveredArcade.progress.coins, 42)
    }

    func testArcadeSimulationClockPreservesLowFrameRateTimeAndBoundsStalls() {
        var clock = ArcadeSimulationClock()
        XCTAssertEqual(clock.steps(for: 1.0 / 15), 8)
        XCTAssertEqual(clock.steps(for: 4), 30)
        XCTAssertEqual(clock.steps(for: .nan), 0)
        XCTAssertEqual(clock.steps(for: -1), 0)
    }

    func testArcadePhysicsMatchesAt30And60And120FPS() {
        let size = CGSize(width: 393, height: 852)
        func simulate(fps: Int) -> (SkyHopEngine, SkyPawsEngine, PetsDashEngine) {
            var hop = SkyHopEngine(), paws = SkyPawsEngine(), dash = PetsDashEngine()
            hop.start(in: size, seed: 1); paws.start(in: size, seed: 1); dash.start(in: size, seed: 1)
            hop.setSteering(1); paws.flap(); dash.jump(); dash.moveLane(-1)
            for _ in 0..<(fps / 2) {
                hop.update(deltaTime: 1 / Double(fps), in: size)
                paws.update(deltaTime: 1 / Double(fps), in: size)
                dash.update(deltaTime: 1 / Double(fps), in: size)
            }
            return (hop, paws, dash)
        }
        let reference = simulate(fps: 120)
        for fps in [30, 60] {
            let run = simulate(fps: fps)
            XCTAssertEqual(run.0.playerPosition.x, reference.0.playerPosition.x, accuracy: 0.001)
            XCTAssertEqual(run.0.playerPosition.y, reference.0.playerPosition.y, accuracy: 0.001)
            XCTAssertEqual(run.1.playerY, reference.1.playerY, accuracy: 0.001)
            XCTAssertEqual(run.1.gates, reference.1.gates)
            XCTAssertEqual(run.2.jumpHeight, reference.2.jumpHeight, accuracy: 0.001)
            XCTAssertEqual(run.2.lanePosition, reference.2.lanePosition, accuracy: 0.001)
            XCTAssertEqual(run.2.trackProgress, reference.2.trackProgress, accuracy: 0.001)
        }
    }

    func testDashSceneryAndObstaclesCoverTheSameWorldDistance() {
        let size = CGSize(width: 393, height: 852)
        var engine = PetsDashEngine()
        engine.start(in: size, seed: 1)
        engine.objects = [PetsDashObject(id: 99, kind: .rock, lane: 0, progress: 0.25)]
        for _ in 0..<30 { engine.update(deltaTime: 1.0 / 60, in: size) }
        XCTAssertEqual(engine.objects[0].progress - 0.25, engine.trackProgress, accuracy: 0.0001)
    }

    func testDashLaneChangeHasContinuousPositionAndArrivesWithoutOvershoot() {
        let size = CGSize(width: 393, height: 852)
        var engine = PetsDashEngine()
        engine.start(in: size, seed: 1)
        engine.moveLane(1)
        XCTAssertEqual(engine.lanePosition, 1)
        engine.update(deltaTime: 0.09, in: size)
        XCTAssertGreaterThan(engine.lanePosition, 1)
        XCTAssertLessThan(engine.lanePosition, 2)
        engine.update(deltaTime: 0.12, in: size)
        XCTAssertEqual(engine.lanePosition, 2)
        engine.moveLane(-1)
        engine.update(deltaTime: 0.05, in: size)
        let beforeReversal = engine.lanePosition
        engine.moveLane(1)
        XCTAssertEqual(engine.lanePosition, beforeReversal)
        engine.update(deltaTime: 0.2, in: size)
        XCTAssertEqual(engine.lanePosition, 2)
    }

    func testDashCollisionFollowsVisibleLaneInsteadOfInstantTargetLane() {
        let size = CGSize(width: 393, height: 852)
        var engine = PetsDashEngine()
        engine.start(in: size, seed: 1)
        engine.objects = [PetsDashObject(id: 99, kind: .rock, lane: 0, progress: 0.84)]
        engine.moveLane(-1)
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.phase, .playing, "The pet has not reached the new lane yet")
        engine.objects = [PetsDashObject(id: 100, kind: .rock, lane: 1, progress: 0.84)]
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.phase, .gameOver, "The pet is still physically in its old lane")
    }

    func testDashLandingOnObstacleDoesNotGetEarlyJumpImmunity() {
        let size = CGSize(width: 393, height: 852)
        var engine = PetsDashEngine()
        engine.start(in: size, seed: 1)
        engine.jumpHeight = 0.5
        engine.objects = [PetsDashObject(id: 99, kind: .rock, lane: 1, progress: 0.83)]
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertFalse(engine.objects[0].didResolve)
        engine.jumpHeight = 0
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.phase, .gameOver)
    }

    func testDashWellTimedJumpClearsObstacleAndAwardsOnlyOnce() {
        let size = CGSize(width: 393, height: 852)
        var engine = PetsDashEngine()
        engine.start(in: size, seed: 1)
        engine.objects = [PetsDashObject(id: 99, kind: .barrier, lane: 1, progress: 0.70)]
        engine.jump()
        for _ in 0..<4 { engine.update(deltaTime: 0.25, in: size) }
        XCTAssertEqual(engine.phase, .playing)
        XCTAssertEqual(engine.objects.first { $0.id == 99 }?.didResolve, true)
        XCTAssertGreaterThanOrEqual(engine.score, 124)
        XCTAssertLessThan(engine.score, 130)
        engine.update(deltaTime: 0.25, in: size)
        XCTAssertLessThan(engine.score, 140, "Passing the same obstacle must not reward it again")
    }

    func testDashCollectsOnlyAtPetDepthAndBelowTheCoin() {
        let size = CGSize(width: 393, height: 852)
        var engine = PetsDashEngine()
        engine.start(in: size, seed: 1)
        engine.objects = [PetsDashObject(id: 99, kind: .coin, lane: 1, progress: 0.76)]
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.coinsCollected, 0)
        engine.objects[0].progress = 0.84
        engine.jumpHeight = 0.5
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.coinsCollected, 0)
        engine.jumpHeight = 0
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.coinsCollected, 1)
    }

    func testHopButtonNudgeReleasesSteeringAndCanBeOverriddenByHold() {
        let size = CGSize(width: 393, height: 852)
        var engine = SkyHopEngine()
        engine.start(in: size, seed: 1)
        engine.nudgeSteering(1)
        engine.update(deltaTime: 0.20, in: size)
        XCTAssertEqual(engine.steering, 0)
        engine.nudgeSteering(-1)
        engine.setSteering(1)
        engine.update(deltaTime: 0.20, in: size)
        XCTAssertEqual(engine.steering, 1)
        engine.setSteering(0)
        XCTAssertEqual(engine.steering, 0)
    }

    func testPetsDashCannotCollectCoinsAlreadyBehindPlayer() {
        var engine = PetsDashEngine()
        let size = CGSize(width: 393, height: 852)
        engine.start(in: size)
        engine.objects = [PetsDashObject(id: 1, kind: .coin, lane: 1, progress: 1.04)]
        engine.update(deltaTime: 1.0 / 60, in: size)
        XCTAssertEqual(engine.coinsCollected, 0)
    }

    func testPetsDashRepeatedJumpCannotBoostTakeoff() {
        let size = CGSize(width: 393, height: 852)
        var once = PetsDashEngine()
        once.start(in: size, seed: 1)
        once.jump()
        once.update(deltaTime: 0.005, in: size)
        var repeated = once
        repeated.jump()
        once.update(deltaTime: 0.01, in: size)
        repeated.update(deltaTime: 0.01, in: size)
        XCTAssertEqual(once.jumpHeight, repeated.jumpHeight)
    }

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
            PetsDashObject(id: 7, kind: .coin, lane: 1, progress: 0.82)
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
        XCTAssertEqual(PetSpecies.allCases.count, 6)
        XCTAssertEqual(PetSpecies.selectableCases, [.cat, .dog, .fox, .parrot, .penguin, .lion])
    }

    func testNewCompanionsPersistAndHaveDedicatedArcadeArtwork() throws {
        for (species, breed) in [(PetSpecies.lion, PetBreed.adultLion), (.lion, .lioness),
                                  (.lion, .lionCub), (.dog, .cardigan)] {
            let profile = PetProfile(id: UUID(), name: "New pet", species: species, coat: .sunrise,
                                     createdAt: Date(timeIntervalSince1970: 1000), breed: breed)
            let decoded = try JSONDecoder().decode(PetProfile.self, from: JSONEncoder().encode(profile))
            XCTAssertEqual(decoded, profile)
            XCTAssertEqual(decoded.resolvedBreed, breed)
            let rear = PetsDashArtworkLibrary.assetNames(for: species, breed: breed)
            let plane = SkyPawsArtworkLibrary.assetNames(for: species, breed: breed)
            XCTAssertEqual(rear.count, 4)
            XCTAssertEqual(Set(rear).count, 4)
            XCTAssertEqual(plane.count, 1)
            for name in rear + plane {
                let image = try XCTUnwrap(UIImage(named: name), name)
                XCTAssertGreaterThan(image.size.width, 0, name)
                XCTAssertTrue(name.contains(try XCTUnwrap(breed.companionArtworkToken)), name)
            }
        }
    }

    func testNewCompanionBlinksBrieflyInsteadOfClosingEyesHalfTheTime() {
        let clip = PetAnimationLibrary.naturalClip(for: .lion, breed: .adultLion, pose: .idle)
        XCTAssertEqual(clip.cycleDuration, 1.94, accuracy: 0.0001)
        XCTAssertEqual(clip.frameIndex(at: 0), 0)
        XCTAssertEqual(clip.frameIndex(at: 1.79), 0)
        XCTAssertEqual(clip.frameIndex(at: 1.81), 1)
        XCTAssertEqual(clip.frameIndex(at: 1.93), 1)
        XCTAssertEqual(clip.frameIndex(at: 1.95), 0)
        XCTAssertEqual(clip.frameIndex(at: -0.01), 1)
        XCTAssertEqual(clip.frameIndex(at: 1.81, phaseOffset: 1), 0)
    }

    func testLionRunKeepsItsHeadRegisteredWithoutGroundingAirborneFeet() throws {
        let clip = PetAnimationLibrary.naturalClip(for: .lion, breed: .adultLion, pose: .run)
        let geometry = try clip.frames.map { try XCTUnwrap(PetSpriteGeometry.load(assetName: $0)) }
        let tops = geometry.map { $0.visibleBounds.minY }
        XCTAssertLessThanOrEqual(try XCTUnwrap(tops.max()) - XCTUnwrap(tops.min()), 6)
        for index in geometry.indices {
            XCTAssertEqual(geometry[index].rect(in: PetSpriteGeometry.canvas).origin, .zero)
            XCTAssertLessThanOrEqual(abs(tops[index] - tops[(index + 1) % tops.count]), 3)
        }
        XCTAssertLessThan(geometry[4].visibleBounds.maxY, geometry[0].visibleBounds.maxY - 8)
    }

    @MainActor
    func testAllNewCompanionTimerModesAreRegistered() throws {
        try registerTimerFonts()
        for family in ["PetIslandTimer", "PetIslandLockTimer"] {
            for breed in ["LionAdult", "Lioness", "LionCub", "DogCardigan"] {
                for mode in ["Run", "Walk", "Sleep", "RunSleep", "WalkSleep", "RunWalkSleep"] {
                    let name = family + breed + mode
                    let font = CTFontCreateWithName(name as CFString, 36, nil)
                    XCTAssertEqual(CTFontCopyPostScriptName(font) as String, name)
                }
            }
        }
    }

    func testVisualVariantsAreScopedToTheirSpecies() {
        XCTAssertEqual(
            PetBreed.available(for: .dog),
            [.shepherd, .corgi, .cardigan, .doberman, .bullTerrier]
        )
        XCTAssertEqual(
            PetBreed.available(for: .cat),
            [.classicCat, .britishShorthair, .maineCoon, .siamese]
        )
        XCTAssertEqual(PetBreed.available(for: .fox), [.redFox, .arcticFox])
        XCTAssertEqual(PetBreed.available(for: .lion), [.adultLion, .lioness, .lionCub])
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

    @MainActor
    func testControllerBootstrapPreservesNonDogLeadPet() async {
        let cat = PetProfile(
            id: UUID(), name: "Milo", species: .cat,
            coat: .midnight, createdAt: Date(timeIntervalSince1970: 1_000),
            breed: .maineCoon
        )
        var persisted = PersistedAppState()
        persisted.pets = [cat]
        persisted.activePetIDs = [cat.id]
        persisted.completedOnboarding = true
        persisted.normalizePetCollection()
        let store = InMemoryPetStore(persisted)
        let controller = PetSessionController(store: store)

        await controller.bootstrap()

        XCTAssertEqual(controller.profile, cat)
        XCTAssertEqual(controller.pets, [cat])
        XCTAssertEqual(controller.activePetIDs, [cat.id])
        XCTAssertFalse(controller.pets.contains { $0.species == .dog })

        let saved = await store.load()
        XCTAssertEqual(saved.profile, cat)
        XCTAssertEqual(saved.pets, [cat])
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

    func testPetLifeStateRoundTripKeepsSpeciesAndPlacement() throws {
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

        XCTAssertEqual(decoded.profile.species, .cat)
        XCTAssertEqual(decoded.profile.breed, cat.breed)
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

    func testPlayYardThrowVelocityNeverProducesADeadThrow() {
        let velocity = PlayYardGameRules.throwVelocity(
            drag: .zero,
            prediction: .zero,
            sampledVelocity: .zero,
            reduceMotion: false
        )

        XCTAssertEqual(
            hypot(velocity.dx, velocity.dy),
            PlayYardGameRules.minimumThrowSpeed,
            accuracy: 0.5
        )
        XCTAssertLessThan(velocity.dy, 0)
    }

    func testPlayYardThrowVelocityIsClampedForWildGesturePredictions() {
        let velocity = PlayYardGameRules.throwVelocity(
            drag: CGVector(dx: 900, dy: -1_200),
            prediction: CGVector(dx: 4_000, dy: -5_000),
            sampledVelocity: CGVector(dx: 12_000, dy: -16_000),
            reduceMotion: false
        )

        XCTAssertLessThanOrEqual(
            hypot(velocity.dx, velocity.dy),
            PlayYardGameRules.maximumThrowSpeed + 0.01
        )
        XCTAssertGreaterThanOrEqual(velocity.dx, -PlayYardGameRules.maximumHorizontalThrowSpeed)
        XCTAssertLessThanOrEqual(velocity.dx, PlayYardGameRules.maximumHorizontalThrowSpeed)
        XCTAssertGreaterThanOrEqual(velocity.dy, -PlayYardGameRules.maximumUpwardThrowSpeed)
        XCTAssertLessThanOrEqual(velocity.dy, PlayYardGameRules.maximumDownwardThrowSpeed)
    }

    func testPlayYardDragCannotPullTheBallIntoTheHUD() {
        let drag = PlayYardGameRules.constrainedDrag(CGVector(dx: 500, dy: -900))

        XCTAssertEqual(
            hypot(drag.dx, drag.dy),
            PlayYardGameRules.maximumDragDistance,
            accuracy: 0.01
        )
    }

    func testPlayYardGesturePredictionOnlyAddsAControlledFlick() {
        let drag = CGVector(dx: 20, dy: -100)
        let controlled = PlayYardGameRules.throwVelocity(
            drag: drag,
            prediction: .zero,
            sampledVelocity: .zero,
            reduceMotion: false
        )
        let wild = PlayYardGameRules.throwVelocity(
            drag: drag,
            prediction: CGVector(dx: 4_000, dy: -5_000),
            sampledVelocity: CGVector(dx: 12_000, dy: -16_000),
            reduceMotion: false
        )

        XCTAssertLessThan(abs(wild.dy - controlled.dy), 60)
        XCTAssertLessThan(abs(wild.dx - controlled.dx), 60)
    }

    func testPlayYardCarriedBallIsSmallerThanThrownBall() {
        XCTAssertLessThan(
            PlayYardMouthLayout.carriedBallDiameter,
            PlayYardGameRules.ballDiameter
        )
    }

    func testPlayYardMouthAnchorMirrorsWithDirectionForEverySpecies() {
        for species in PetSpecies.allCases {
            let right = PlayYardMouthLayout.offset(
                for: species,
                size: 90,
                direction: .right
            )
            let left = PlayYardMouthLayout.offset(
                for: species,
                size: 90,
                direction: .left
            )

            XCTAssertGreaterThan(right.width, 0)
            XCTAssertEqual(left.width, -right.width, accuracy: 0.01)
            XCTAssertEqual(left.height, right.height, accuracy: 0.01)
        }
    }

    func testPlayYardCatchRulesRequireTheBallToBeReachable() {
        XCTAssertTrue(
            PlayYardGameRules.shouldCatch(
                ballHeight: 4,
                horizontalDistance: 24,
                directDistance: 28,
                isAirborne: false,
                isFlying: false
            )
        )
        XCTAssertFalse(
            PlayYardGameRules.shouldCatch(
                ballHeight: 90,
                horizontalDistance: 24,
                directDistance: 94,
                isAirborne: false,
                isFlying: false
            )
        )
        XCTAssertTrue(
            PlayYardGameRules.shouldCatch(
                ballHeight: 90,
                horizontalDistance: 18,
                directDistance: 34,
                isAirborne: true,
                isFlying: false
            )
        )
    }

    func testPlayYardBallMustBeSlowAndOnTheGroundToSettle() {
        XCTAssertTrue(
            PlayYardGameRules.ballIsSettled(
                ballHeight: 0,
                velocity: CGVector(dx: 8, dy: 0)
            )
        )
        XCTAssertFalse(
            PlayYardGameRules.ballIsSettled(
                ballHeight: 0,
                velocity: CGVector(dx: 80, dy: 0)
            )
        )
        XCTAssertFalse(
            PlayYardGameRules.ballIsSettled(
                ballHeight: 42,
                velocity: .zero
            )
        )
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

    func testSkyHopGeneratesFragilePlatformsWithoutUnsafeConsecutivePairs() {
        let size = CGSize(width: 390, height: 844)
        var engine = SkyHopEngine()

        engine.start(in: size, seed: 42)

        XCTAssertEqual(engine.platforms.first?.kind, .stable)
        XCTAssertTrue(engine.platforms.contains { $0.kind == .fragile })
        let pairs = zip(engine.platforms, engine.platforms.dropFirst())
        XCTAssertFalse(pairs.contains { lower, upper in
            lower.kind == .fragile && upper.kind == .fragile
        })
    }

    func testSkyHopFragilePlatformBreaksAfterItsFirstLanding() {
        let size = CGSize(width: 390, height: 844)
        let fragileID = 9_001
        var engine = SkyHopEngine()
        engine.start(in: size, seed: 17)
        engine.platforms = [
            SkyHopPlatform(
                id: fragileID,
                x: size.width / 2,
                y: 600,
                width: 100,
                kind: .fragile
            )
        ]
        engine.obstacles = []
        engine.playerPosition = CGPoint(x: size.width / 2, y: 560)
        engine.velocity = CGVector(dx: 0, dy: 600)

        engine.update(deltaTime: 1.0 / 24.0, in: size)

        XCTAssertLessThan(engine.velocity.dy, 0)
        XCTAssertNotNil(engine.platforms.first { $0.id == fragileID }?.crumbleElapsed)

        for _ in 0..<10 {
            engine.update(deltaTime: 1.0 / 24.0, in: size)
        }
        XCTAssertFalse(engine.platforms.contains { $0.id == fragileID })
    }

    func testSkyHopGeneratesBothObstacleKindsInsidePlayableBounds() {
        let size = CGSize(width: 390, height: 844)
        var engine = SkyHopEngine()

        engine.start(in: size, seed: 1_234)

        XCTAssertTrue(engine.obstacles.contains { $0.kind == .stormCloud })
        XCTAssertTrue(engine.obstacles.contains { $0.kind == .spikeOrb })
        XCTAssertTrue(engine.obstacles.allSatisfy { obstacle in
            obstacle.x >= 34 && obstacle.x <= size.width - 34
        })
    }

    func testSkyHopObstacleCollisionEndsTheRun() {
        let size = CGSize(width: 390, height: 844)
        var engine = SkyHopEngine()
        engine.start(in: size, seed: 99)
        engine.playerPosition = CGPoint(x: size.width / 2, y: 420)
        engine.velocity = .zero
        engine.obstacles = [
            SkyHopObstacle(
                id: 77,
                kind: .stormCloud,
                x: engine.playerPosition.x,
                y: engine.playerPosition.y,
                size: 46
            )
        ]

        engine.update(deltaTime: 1.0 / 60.0, in: size)

        XCTAssertEqual(engine.phase, .gameOver)
        XCTAssertEqual(engine.gameOverReason, .obstacle(.stormCloud))
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
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertFalse(settings.hapticsEnabled)
        XCTAssertTrue(settings.minimizeMotion)
        XCTAssertNil(settings.liveActivityBackgroundColor)
    }

    func testLiveActivityColorSurvivesSettingsRoundTrip() throws {
        let color = PetColorSelection(red: 0.94, green: 0.87, blue: 0.76)
        let settings = AppSettings(appearance: .light, liveActivityBackgroundColor: color)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testLegacyLiveActivityContentStillDecodes() throws {
        let content = PetActivityAttributes.ContentState(snapshot: .initial(at: .now), lastInteraction: nil)
        let encoded = try JSONEncoder().encode(content)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(json["backgroundColor"])
        let decoded = try JSONDecoder().decode(PetActivityAttributes.ContentState.self, from: encoded)
        XCTAssertNil(decoded.backgroundColor)
        XCTAssertEqual(decoded.appearance.background, PetActivityAppearance.defaultBackground)
    }

    func testLiveActivityReactionsPreserveCustomBackground() throws {
        let color = PetColorSelection(red: 0.74, green: 0.68, blue: 0.88)
        let initial = PetSnapshot.initial(at: .now)
        let content = PetActivityAttributes.ContentState(snapshot: initial, lastInteraction: nil, backgroundColor: color)
        let snapshots = PetLiveMotionSequence.snapshots(from: initial, action: .run, species: .lion)
        for snapshot in snapshots {
            let updated = content.updating(snapshot: snapshot, lastInteraction: "run")
            XCTAssertEqual(updated.backgroundColor, color)
            XCTAssertEqual(updated.snapshot, snapshot)
            XCTAssertEqual(updated.lastInteraction, "run")
            XCTAssertEqual(try JSONDecoder().decode(PetActivityAttributes.ContentState.self,
                from: JSONEncoder().encode(updated)), updated)
        }
    }

    func testLiveActivityTextContrastAcrossRGBColors() {
        for red in 0...10 {
            for green in 0...10 {
                for blue in 0...10 {
                    let palette = PetActivityAppearance(background: .init(
                        red: Double(red) / 10, green: Double(green) / 10, blue: Double(blue) / 10))
                    let luminance = palette.relativeLuminance
                    let contrast = palette.usesDarkText ? (luminance + 0.05) / 0.05 : 1.05 / (luminance + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5)
                }
            }
        }
        XCTAssertFalse(PetActivityAppearance(background: nil).usesDarkText)
        XCTAssertTrue(PetActivityAppearance(background: .init(red: 1, green: 1, blue: 1)).usesDarkText)
    }

    @MainActor
    func testActivityColorSaveAndResetPreserveOtherSettingsAndPet() async throws {
        let store = InMemoryPetStore()
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        await controller.updateDynamicIslandSettings(mode: .walkSleep, durationMinutes: 120)
        let profile = controller.profile
        let color = PetColorSelection(red: 0.86, green: 0.89, blue: 0.94)
        let saved = await controller.updateLiveActivityBackgroundColor(color)
        XCTAssertTrue(saved)
        let persisted = await store.load()
        XCTAssertEqual(persisted.settings.liveActivityBackgroundColor, color)
        XCTAssertEqual(controller.settings.liveActivityBackgroundColor, color)
        XCTAssertEqual(controller.settings.dynamicIslandMotionMode, .walkSleep)
        XCTAssertEqual(controller.settings.defaultSessionMinutes, 120)
        XCTAssertEqual(controller.profile, profile)
        let reset = await controller.updateLiveActivityBackgroundColor(nil)
        XCTAssertTrue(reset)
        let resetState = await store.load()
        XCTAssertNil(resetState.settings.liveActivityBackgroundColor)
        XCTAssertEqual(resetState.settings.dynamicIslandMotionMode, .walkSleep)
    }

    @MainActor
    func testFailedActivityColorSaveKeepsPreviousColor() async throws {
        let store = FailablePetStore()
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let previous = PetColorSelection(red: 0.15, green: 0.27, blue: 0.44)
        let saved = await controller.updateLiveActivityBackgroundColor(previous)
        XCTAssertTrue(saved)
        await store.setFailure(true)
        let reset = await controller.updateLiveActivityBackgroundColor(nil)
        XCTAssertFalse(reset)
        XCTAssertEqual(controller.settings.liveActivityBackgroundColor, previous)
        let persisted = await store.load()
        XCTAssertEqual(persisted.settings.liveActivityBackgroundColor, previous)
        XCTAssertNotNil(controller.alertMessage)
    }

    func testAppearancePreferenceSurvivesPersistenceRoundTrip() throws {
        let settings = AppSettings(appearance: .dark)

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )

        XCTAssertEqual(decoded.appearance, .dark)
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

private actor FailablePetStore: PetStore {
    private var value = PersistedAppState()
    private var fails = false
    func setFailure(_ value: Bool) { fails = value }
    func load() async -> PersistedAppState { value }
    func save(_ state: PersistedAppState) async throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        value = state
    }
}

private actor FailableArcadeStore: ArcadeStore {
    private var value: ArcadeState
    private var fails = false
    init(_ value: ArcadeState = ArcadeState()) { self.value = value }
    func setFailure(_ value: Bool) { fails = value }
    func load() async -> ArcadeState { value }
    func save(_ state: ArcadeState) async throws {
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        value = state
    }
}
