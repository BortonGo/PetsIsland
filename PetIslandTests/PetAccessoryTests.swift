import XCTest
import CoreText
import SwiftUI
import Darwin
@testable import PetIsland

final class PetAccessoryTests: XCTestCase {
    @MainActor
    func testRetainedSpriteUpdatesItsFrameColorDirectionAndAccessory() async throws {
        let original = PetArtwork(species: .dog, breed: .corgi, pose: .walk,
                                  animatesMotion: false, usesNaturalGait: true)
        var variants: [PetArtwork] = []
        var changed = original; changed.step = 1; variants.append(changed)
        changed = original; changed.direction = .left; variants.append(changed)
        variants.append(PetArtwork(species: .dog, breed: .corgi, pose: .sleep,
                                   animatesMotion: false, usesNaturalGait: true))
        changed = original; changed.breed = .cardigan; variants.append(changed)
        changed = original; changed.coat = .cloud; variants.append(changed)
        changed = original; changed.customColor = PetColorSelection(red: 0.4, green: 0.65, blue: 0.8); variants.append(changed)
        for accessory in PetAccessory.allCases {
            changed = original; changed.accessory = accessory; variants.append(changed)
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(rootView: original)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 260)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func snapshot(_ artwork: PetArtwork) async throws -> Data {
            host.rootView = artwork
            try await Task.sleep(for: .milliseconds(80))
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return try XCTUnwrap(UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }.pngData())
        }
        let baseline = try await snapshot(original)
        let unchanged = try await snapshot(original)
        XCTAssertEqual(unchanged, baseline)
        for (index, variant) in variants.enumerated() {
            let updated = try await snapshot(variant)
            XCTAssertNotEqual(updated, baseline, "A retained sprite must update changed input \(index)")
            let restored = try await snapshot(original)
            XCTAssertEqual(restored, baseline, "Removing an outfit or coat must restore the original pixels")
        }
    }

    @MainActor
    func testAccessoryColdStartRecordsTimeAndMemory() throws {
        // Run this test alone in a fresh test host to compare cold registration.
        _ = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let before = performanceSnapshot()
        let full = PetAccessoryTimerFonts.dressedName(baseFontName: "PetIslandTimerDogCorgiWalk", accessory: .tinyCrown)
        let ink = PetAccessoryTimerFonts.name(baseFontName: "PetIslandTimerDogCorgiWalk", accessory: .tinyCrown)
        let after = performanceSnapshot()
        XCTAssertEqual(full, "PetDressedTimerDogCorgiWalktinyCrown")
        XCTAssertEqual(ink, "PetAccessoryTimerDogCorgiWalktinyCrown")
        let report = "Accessory first use: wall_ms=\((after.wall-before.wall)*1000), cpu_ms=\((after.cpu-before.cpu)*1000), footprint_delta_bytes=\(Int64(after.memory)-Int64(before.memory))"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "Accessory first use — simulator measurement"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAccessorySixPetRenderingPerformance() throws {
        let breeds: [(PetSpecies, PetBreed)] = [(.dog, .corgi), (.dog, .shepherd), (.cat, .classicCat), (.fox, .redFox), (.lion, .adultLion), (.penguin, .classicPenguin)]
        // Same six residents and 12 gait phases before and after optimization.
        // These offscreen CPU/memory measurements are not device energy tests.
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric()], options: options) {
            for step in 0..<12 {
                autoreleasepool {
                    let renderer = ImageRenderer(content: HStack(spacing: 0) {
                        ForEach(breeds.indices, id: \.self) { index in
                            PetArtwork(species: breeds[index].0, breed: breeds[index].1,
                                pose: step < 6 ? .walk : .run, step: step, animatesMotion: false,
                                usesNaturalGait: true, accessory: PetAccessory.allCases[index % 3])
                                .frame(width: 84, height: 72)
                        }
                    })
                    renderer.scale = 2
                    XCTAssertNotNil(renderer.uiImage)
                }
            }
        }
    }

    private func performanceSnapshot() -> (wall: Double, cpu: Double, memory: UInt64) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return (ProcessInfo.processInfo.systemUptime, cpu, result == KERN_SUCCESS ? info.phys_footprint : 0)
    }

    func testPurchasesChargeOnceAndInsufficientCoinsChangeNothing() throws {
        for item in PetAccessory.allCases {
            var progress = ArcadeProgress(coins: item.price + 13)
            XCTAssertTrue(progress.purchaseAccessory(item))
            XCTAssertEqual(progress.coins, 13)
            let bought = progress
            XCTAssertFalse(progress.purchaseAccessory(item))
            XCTAssertEqual(progress, bought)
            XCTAssertEqual(try JSONDecoder().decode(ArcadeProgress.self, from: JSONEncoder().encode(progress)), bought)
            var poor = ArcadeProgress(coins: item.price - 1)
            let before = poor
            XCTAssertFalse(poor.purchaseAccessory(item))
            XCTAssertEqual(poor, before)
        }
    }

    func testLegacySavesAndUnknownFutureAccessoriesRemainReadable() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ArcadeProgress(coins: 42))) as? [String: Any])
        json.removeValue(forKey: "ownedAccessories")
        let legacy = try JSONDecoder().decode(ArcadeProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.ownedAccessories.isEmpty)
        XCTAssertEqual(legacy.coins, 42)
        json["ownedAccessories"] = ["knitHat", "futureAccessory"]
        let future = try JSONDecoder().decode(ArcadeProgress.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(future.ownedAccessories, [.knitHat])
        XCTAssertNil(try JSONDecoder().decode(PetOutfit.self, from: Data("{\"headwear\":\"futureAccessory\"}".utf8)).headwear)
        var petJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(PetProfile.starter)) as? [String: Any])
        petJSON.removeValue(forKey: "outfit")
        XCTAssertNil(try JSONDecoder().decode(PetProfile.self, from: JSONSerialization.data(withJSONObject: petJSON)).outfit)
    }

    func testLiveActivityUpdatesPreserveOutfitAndAnExplicitRemoval() throws {
        let initial = PetSnapshot.initial(at: .now)
        var content = PetActivityAttributes.ContentState(snapshot: initial, lastInteraction: nil, petOutfit: PetOutfit(headwear: .tinyCrown))
        XCTAssertEqual(content.updating(snapshot: initial, lastInteraction: "play").petOutfit?.headwear, .tinyCrown)
        XCTAssertEqual(content.updatingAppearance(color: nil, transparency: 0.5).petOutfit?.headwear, .tinyCrown)
        content.petOutfit = PetOutfit()
        let decoded = try JSONDecoder().decode(PetActivityAttributes.ContentState.self, from: JSONEncoder().encode(content))
        XCTAssertNotNil(decoded.petOutfit, "An empty outfit must override the accessory in immutable activity attributes")
        XCTAssertNil(decoded.petOutfit?.headwear)
        XCTAssertEqual(decoded.updating(snapshot: initial, lastInteraction: nil).petOutfit, PetOutfit())
    }

    @MainActor
    func testChangingAnAccessoryDoesNotResetEnclosureMovement() throws {
        var pet = PetProfile.starter
        let simulation = HabitatMotionSimulation()
        let size = CGSize(width: 360, height: 236)
        simulation.configure(pets: [pet], size: size)
        for _ in 0..<90 { simulation.advance(by: 1.0 / 60) }
        let before = try XCTUnwrap(simulation.actors.first)
        pet.outfit = PetOutfit(headwear: .ribbonBow)
        simulation.configure(pets: [pet], size: size)
        let after = try XCTUnwrap(simulation.actors.first)
        XCTAssertEqual(before.position, after.position)
        XCTAssertEqual(before.target, after.target)
        XCTAssertEqual(before.pose, after.pose)
        XCTAssertEqual(before.gaitPhase, after.gaitPhase)
        XCTAssertEqual(after.profile.outfit?.headwear, .ribbonBow)
        simulation.stop()
    }

    @MainActor
    func testOnePurchaseCanDressEverySpeciesAndPersistsAcrossRestart() async throws {
        let shared = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(shared) }
        var state = PersistedAppState()
        state.pets = PetSpecies.allCases.map { PetProfile(id: UUID(), name: $0.rawValue, species: $0, coat: .sunrise, createdAt: .now) }
        state.activePetIDs = [state.pets[0].id]
        let pets = InMemoryPetStore(state)
        let arcade = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 200)))
        let controller = PetSessionController(store: pets, arcadeStore: arcade)
        await controller.bootstrap()
        let unowned = await controller.equipAccessory(.knitHat, for: state.pets[0].id)
        XCTAssertFalse(unowned)
        async let first = controller.purchaseAccessory(.knitHat)
        async let duplicate = controller.purchaseAccessory(.knitHat)
        let results = await [first, duplicate]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        for pet in state.pets {
            let applied = await controller.equipAccessory(.knitHat, for: pet.id)
            XCTAssertTrue(applied)
        }
        XCTAssertEqual(controller.arcadeProgress.coins, 130)
        XCTAssertTrue(controller.pets.allSatisfy { $0.outfit?.headwear == .knitHat })
        let reopened = PetSessionController(store: pets, arcadeStore: arcade)
        await reopened.bootstrap()
        XCTAssertEqual(reopened.pets, controller.pets)
        XCTAssertEqual(reopened.arcadeProgress.ownedAccessories, [.knitHat])
        let removed = await reopened.equipAccessory(nil, for: state.pets[0].id)
        XCTAssertTrue(removed)
        XCTAssertNil(reopened.pets[0].outfit)
        XCTAssertEqual(reopened.pets[1].outfit?.headwear, .knitHat)
        XCTAssertEqual(reopened.arcadeProgress.coins, 130)
        XCTAssertEqual(reopened.arcadeProgress.ownedAccessories, [.knitHat])
    }

    @MainActor
    func testStaleProfileEditorDoesNotUndoOutfitAndHabitatReceivesIt() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: InMemoryArcadeStore(
            ArcadeState(progress: ArcadeProgress(ownedAccessories: [.tinyCrown]))))
        await controller.bootstrap()
        var draft = try XCTUnwrap(controller.pets.first)
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: [draft.id]))
        let equipped = await controller.equipAccessory(.tinyCrown, for: draft.id)
        XCTAssertTrue(equipped)
        draft.name = "New name"
        let saved = await controller.updatePet(draft)
        XCTAssertTrue(saved)
        XCTAssertEqual(controller.pets.first?.outfit?.headwear, .tinyCrown)
        XCTAssertEqual(PetHabitatStore.load().residents.first?.profile.outfit?.headwear, .tinyCrown)
        XCTAssertEqual(controller.pets.first?.name, "New name")
    }

    @MainActor
    func testFailedSavesDoNotSpendCoinsOrPublishUnstoredOutfits() async throws {
        let shared = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(shared) }
        let pets = AccessoryPetStore()
        let arcade = AccessoryArcadeStore()
        let controller = PetSessionController(store: pets, arcadeStore: arcade)
        let premature = await controller.purchaseAccessory(.knitHat)
        XCTAssertFalse(premature)
        await controller.bootstrap()
        await arcade.fail(true)
        let failedPurchase = await controller.purchaseAccessory(.knitHat)
        XCTAssertFalse(failedPurchase)
        XCTAssertEqual(controller.arcadeProgress.coins, 200)
        XCTAssertTrue(controller.arcadeProgress.ownedAccessories.isEmpty)
        await arcade.fail(false)
        let retried = await controller.purchaseAccessory(.knitHat)
        XCTAssertTrue(retried)
        let pet = try XCTUnwrap(controller.pets.first)
        await pets.fail(true)
        let failedEquip = await controller.equipAccessory(.knitHat, for: pet.id)
        XCTAssertFalse(failedEquip)
        XCTAssertNil(controller.pets.first?.outfit)
        XCTAssertTrue(controller.arcadeProgress.ownedAccessories.contains(.knitHat))
        await pets.fail(false)
        let equipped = await controller.equipAccessory(.knitHat, for: pet.id)
        XCTAssertTrue(equipped)
        let missing = await controller.equipAccessory(.knitHat, for: UUID())
        XCTAssertFalse(missing)
    }

    @MainActor
    func testAwayPetKeepsItsOutfitUntilReturning() async throws {
        let shared = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(shared) }
        let controller = PetSessionController(store: InMemoryPetStore(), arcadeStore: InMemoryArcadeStore(
            ArcadeState(progress: ArcadeProgress(ownedAccessories: [.ribbonBow]))))
        await controller.bootstrap()
        let pet = try XCTUnwrap(controller.pets.first)
        let started = await controller.startDiscoveryWalk(petID: pet.id, route: .garden, at: .now)
        XCTAssertTrue(started)
        let refused = await controller.equipAccessory(.ribbonBow, for: pet.id)
        XCTAssertFalse(refused)
        XCTAssertNil(controller.pets.first?.outfit)
        let returned = await controller.cancelDiscoveryWalk()
        XCTAssertTrue(returned)
        let applied = await controller.equipAccessory(.ribbonBow, for: pet.id)
        XCTAssertTrue(applied)
    }

    @MainActor
    func testEveryRenderedFrameHasAValidAccessoryAnchor() throws {
        let catalog = try XCTUnwrap(PetAccessoryAssets.catalog)
        XCTAssertEqual(catalog.version, 3)
        XCTAssertEqual(Set(catalog.poses.keys), Set(catalog.anchors.keys))
        var assets = Set<String>()
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for pose in PetPose.allCases {
                    assets.formUnion(PetAnimationLibrary.clip(for: species, breed: breed, pose: pose).frames)
                    assets.formUnion(PetAnimationLibrary.naturalClip(for: species, breed: breed, pose: pose).frames)
                }
            }
        }
        for name in assets {
            let anchor = try XCTUnwrap(catalog.anchors[name], name)
            XCTAssertEqual(anchor.count, 3, name)
            let pose = try XCTUnwrap(catalog.poses[name], name)
            XCTAssertLessThanOrEqual(abs(pose.angle), 20, name)
            XCTAssertTrue((0.85...1.1).contains(pose.width), name)
            XCTAssertTrue((0.8...1.1).contains(pose.height), name)
            XCTAssertLessThanOrEqual(abs(pose.bend), 0.12, name)
            for surface in [PetArtworkSurface.standard, .dynamicIsland] {
                let geometry = try XCTUnwrap(PetSpriteGeometry.load(assetName: name, surface: surface), name)
                for item in PetAccessory.allCases {
                    let rect = try XCTUnwrap(PetAccessoryAssets.frame(for: item, assetName: name, geometry: geometry, viewport: CGSize(width: 220, height: 176)), name)
                    XCTAssertTrue(rect.minX.isFinite && rect.minY.isFinite, name)
                    XCTAssertGreaterThan(rect.width, 0, name)
                    XCTAssertGreaterThanOrEqual(rect.minX, 0, name)
                    XCTAssertGreaterThanOrEqual(rect.minY, -1, name)
                    XCTAssertLessThanOrEqual(rect.maxX, 220, name)
                    XCTAssertLessThanOrEqual(rect.maxY, 176, name)
                }
            }
        }
    }

    @MainActor
    func testEveryOutfitPoseLoadsACompleteReplacementOnTheOriginalCanvas() throws {
        let catalog = try XCTUnwrap(PetAccessoryAssets.catalog)
        for item in PetAccessory.allCases {
            XCTAssertEqual(Set(PetDressedAssets.manifest(for: item).keys), Set(catalog.anchors.keys))
            for asset in catalog.anchors.keys {
                let full = try XCTUnwrap(PetDressedAssets.frame(for: item, assetName: asset), asset)
                let original = try XCTUnwrap(UIImage(named: asset), asset)
                XCTAssertEqual(full.image.size, original.size, asset)
                XCTAssertNotEqual(full.image.pngData(), original.pngData(), asset)
                XCTAssertNotNil(full.ink.image.cgImage, asset)
                XCTAssertGreaterThan(full.ink.sourceBounds.width, 5, asset)
                XCTAssertTrue(CGRect(origin: .zero, size: full.image.size).contains(full.ink.sourceBounds), asset)
            }
            XCTAssertNil(PetDressedAssets.frame(for: item, assetName: "unavailable-future-frame"))
        }
    }

    @MainActor
    func testSoftAccessoriesChangeShapeThroughoutEveryMovingClip() throws {
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for pose in [PetPose.walk, .run] {
                    for clip in [PetAnimationLibrary.clip(for: species, breed: breed, pose: pose),
                                 PetAnimationLibrary.naturalClip(for: species, breed: breed, pose: pose)] {
                        for item in [PetAccessory.knitHat, .ribbonBow] {
                            let frames = try clip.frames.map { asset in
                                try XCTUnwrap(PetAccessoryAssets.raster(for: item, assetName: asset)?.image.pngData(), asset)
                            }
                            XCTAssertGreaterThan(Set(frames).count, 1, "\(breed) \(pose) \(item) must not use one rigid accessory shape")
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testTimerAccessoriesMatchForegroundAttachmentAndMirroring() throws {
        let samples: [(PetSpecies, PetBreed, String)] = [
            (.dog, .shepherd, "DogShepherd"), (.dog, .corgi, "DogCorgi"), (.dog, .cardigan, "DogCardigan"),
            (.dog, .doberman, "DogDoberman"), (.dog, .bullTerrier, "DogBullTerrier"),
            (.cat, .classicCat, "CatClassic"), (.cat, .britishShorthair, "CatBritish"),
            (.cat, .maineCoon, "CatMaineCoon"), (.cat, .siamese, "CatSiamese"),
            (.fox, .redFox, "FoxRed"), (.fox, .arcticFox, "FoxArctic"),
            (.parrot, .classicParrot, "ParrotClassic"), (.parrot, .cockatiel, "ParrotCockatiel"),
            (.parrot, .budgie, "ParrotBudgie"), (.parrot, .macaw, "ParrotMacaw"),
            (.penguin, .classicPenguin, "PenguinClassic"), (.penguin, .rockhopper, "PenguinRockhopper"),
            (.lion, .adultLion, "LionAdult"), (.lion, .lioness, "Lioness"), (.lion, .lionCub, "LionCub")
        ]
        for (species, breed, token) in samples {
            for viewport in [CGSize(width: 36, height: 30), CGSize(width: 84, height: 72)] {
                let surface: PetArtworkSurface = viewport.width == 84 ? .standard : .dynamicIsland
                let family = surface == .standard ? "PetIslandLockTimer" : "PetIslandTimer"
                for mode in ["Run", "Walk", "Sleep", "RunSleep", "WalkSleep", "RunWalkSleep"] {
                    for digit in [0, 1, 4, 7] {
                        let sleeping = mode == "Sleep" || (mode.contains("Sleep") && digit >= 7)
                        let walking = mode == "Walk" || mode == "WalkSleep" || (mode == "RunWalkSleep" && digit >= 4)
                        let pose: PetPose = sleeping ? .sleep : walking ? .walk : .run
                        let fourPhaseLion = breed == .adultLion || breed == .lioness
                        let step = sleeping ? 0 : species == .parrot ? digit % 8
                            : (breed == .corgi && walking) ? (digit % 2) * 2
                            : fourPhaseLion ? (digit % 2) * (walking ? 2 : 1)
                            : (breed.companionArtworkToken != nil && breed != .cardigan) ? (digit % 2) * 4 : digit % 2
                        let asset = PetAnimationLibrary.clip(for: species, breed: breed, pose: pose).frameName(forStep: step)
                        let direction: PetDirection = digit.isMultiple(of: 2) ? .right : .left
                        for item in PetAccessory.allCases {
                            let name = try XCTUnwrap(PetAccessoryTimerFonts.name(baseFontName: family + token + mode, accessory: item))
                            let glyph = PetTimerGlyphViewport(text: Text("1:00:\(digit)"), fontName: name, viewport: viewport, direction: direction)
                            let layer = PetAccessoryOverlay(accessory: item, assetName: asset, surface: surface)
                                .frame(width: viewport.width, height: viewport.height)
                                .scaleEffect(x: direction == .left ? -1 : 1, y: 1)
                            let timer = try accessoryBounds(glyph)
                            let foreground = try accessoryBounds(layer)
                            let sample = "\(name), \(digit), \(direction)"
                            XCTAssertEqual(timer.minX, foreground.minX, accuracy: 1.5, sample)
                            XCTAssertEqual(timer.maxX, foreground.maxX, accuracy: 1.5, sample)
                            XCTAssertEqual(timer.minY, foreground.minY, accuracy: 1.5, sample)
                            XCTAssertEqual(timer.maxY, foreground.maxY, accuracy: 1.5, sample)
                            do {
                                let fullName = try XCTUnwrap(PetAccessoryTimerFonts.dressedName(baseFontName: family + token + mode, accessory: item))
                                let fullGlyph = PetTimerGlyphViewport(text: Text("1:00:\(digit)"), fontName: fullName, viewport: viewport, direction: direction)
                                let pet = PetArtwork(species: species, breed: breed, pose: pose, direction: direction,
                                                     step: step, animatesMotion: false, surface: surface, accessory: item)
                                    .frame(width: viewport.width, height: viewport.height)
                                let fullTimer = try accessoryBounds(fullGlyph)
                                let fullForeground = try accessoryBounds(pet)
                                XCTAssertEqual(fullTimer.minX, fullForeground.minX, accuracy: 1.5, sample)
                                XCTAssertEqual(fullTimer.maxX, fullForeground.maxX, accuracy: 1.5, sample)
                                XCTAssertEqual(fullTimer.minY, fullForeground.minY, accuracy: 1.5, sample)
                                XCTAssertEqual(fullTimer.maxY, fullForeground.maxY, accuracy: 1.5, sample)
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func accessoryBounds<V: View>(_ view: V) throws -> CGRect {
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
        XCTAssertGreaterThan(right, left, "Accessory pixels must remain visible in the timer font")
        return CGRect(x: CGFloat(left) / 3, y: CGFloat(top) / 3,
                      width: CGFloat(right - left) / 3, height: CGFloat(bottom - top) / 3)
    }

    @MainActor
    func testOutfitsUseTheAuthoredSilhouetteAndProduceReviewSheets() throws {
        for item in PetAccessory.allCases {
            var images = [UIImage]()
            var names = [String]()
            for species in PetSpecies.allCases {
                for breed in PetBreed.available(for: species) {
                    let asset = PetAnimationLibrary.clip(for: species, breed: breed, pose: .idle).frameName(forStep: 0)
                    let dressed = try XCTUnwrap(PetDressedAssets.frame(for: item, assetName: asset), asset)
                    let geometry = try XCTUnwrap(PetSpriteGeometry.load(assetName: asset), asset)
                    let viewport = CGSize(width: 220, height: 176)
                    let actual = PetArtwork(species: species, breed: breed, pose: .idle,
                                            animatesMotion: false, accessory: item)
                        .frame(width: viewport.width, height: viewport.height)
                    let expected = Canvas { context, _ in
                        context.draw(Image(uiImage: dressed.image).interpolation(.none), in: geometry.rect(in: viewport))
                    }.frame(width: viewport.width, height: viewport.height)
                    let rendered = try renderedImage(actual)
                    let reference = try renderedImage(expected)
                    let actualPixels = try rgba(rendered)
                    let expectedPixels = try rgba(reference)
                    XCTAssertEqual(actualPixels.count, expectedPixels.count, asset)
                    let differingAlpha = stride(from: 3, to: actualPixels.count, by: 4).filter {
                        abs(Int(actualPixels[$0]) - Int(expectedPixels[$0])) > 32
                    }.count
                    XCTAssertLessThan(differingAlpha, 30, "Bare ears must not be drawn behind the outfit: \(asset)")
                    images.append(rendered)
                    names.append(breed.rawValue)
                }
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: 880, height: 1000), format: format).image { renderer in
                UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1).setFill()
                renderer.fill(CGRect(x: 0, y: 0, width: 880, height: 1000))
                for (index, image) in images.enumerated() {
                    let x = (index % 4) * 220, y = (index / 4) * 200
                    (names[index] as NSString).draw(at: CGPoint(x: x + 10, y: y + 8),
                        withAttributes: [.foregroundColor: UIColor.white, .font: UIFont.systemFont(ofSize: 12)])
                    image.draw(in: CGRect(x: x, y: y + 24, width: 220, height: 176))
                }
            }
            let attachment = XCTAttachment(image: sheet)
            attachment.name = "\(item.rawValue) — actual app renderer, all 20 pets"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    private func renderedImage<V: View>(_ view: V) throws -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    private func rgba(_ image: UIImage) throws -> [UInt8] {
        let image = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    @MainActor
    func testAllAccessoryFontsRegisterWithoutSubstitution() {
        let breeds = ["DogShepherd", "DogCorgi", "DogCardigan", "DogDoberman", "DogBullTerrier", "CatClassic", "CatBritish", "CatMaineCoon", "CatSiamese", "FoxRed", "FoxArctic", "ParrotClassic", "ParrotCockatiel", "ParrotBudgie", "ParrotMacaw", "PenguinClassic", "PenguinRockhopper", "LionAdult", "Lioness", "LionCub"]
        for prefix in ["PetIslandTimer", "PetIslandLockTimer"] {
            for breed in breeds {
                for mode in ["Run", "Walk", "Sleep", "RunSleep", "WalkSleep", "RunWalkSleep"] {
                    for item in PetAccessory.allCases {
                        XCTAssertNotNil(PetAccessoryTimerFonts.dressedName(baseFontName: prefix + breed + mode, accessory: item))
                        XCTAssertNotNil(PetAccessoryTimerFonts.name(baseFontName: prefix + breed + mode, accessory: item), "\(prefix)\(breed)\(mode)\(item)")
                    }
                }
            }
        }
    }

    func testTimerCollectionsAreBundledOnlyInTheExtension() throws {
        XCTAssertNil(Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "PetOutfitFonts"))
        XCTAssertNil(Bundle.main.url(forResource: "PetAccessoryTimers", withExtension: "ttc"))
        XCTAssertNil(Bundle.main.url(forResource: "PetDressedTimers", withExtension: "ttc"))
        let directory = try XCTUnwrap(PetAccessoryTimerFonts.resourceDirectory)
        XCTAssertEqual(directory.deletingLastPathComponent().lastPathComponent, "PetIslandLiveActivity.appex")
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.filter { $0.pathExtension == "ttc" }.count, 60)
    }

    func testTimerRegistrationLoadsOnlyTheSelectedOutfitAndReusesItsModes() throws {
        let directory = try XCTUnwrap(PetAccessoryTimerFonts.resourceDirectory)
        let registry = PetAccessoryTimerFonts.Registry(directory: directory)
        XCTAssertEqual(registry.loadedCollectionCount, 0)
        for family in ["PetDressedTimer", "PetDressedLockTimer", "PetAccessoryTimer", "PetAccessoryLockTimer"] {
            for mode in ["Run", "Walk", "Sleep", "RunSleep", "WalkSleep", "RunWalkSleep"] {
                let name = family + "DogCorgi" + mode + "tinyCrown"
                XCTAssertEqual(registry.fontName(name), name)
            }
        }
        XCTAssertEqual(registry.loadedCollectionCount, 1)
        XCTAssertNotNil(registry.fontName("PetDressedTimerCatClassicWalkknitHat"))
        XCTAssertEqual(registry.loadedCollectionCount, 2)
        XCTAssertNil(registry.fontName("PetDressedTimerUnknownWalktinyCrown"))
        XCTAssertEqual(registry.loadedCollectionCount, 2)
        XCTAssertNil(PetAccessoryTimerFonts.Registry(directory: nil).fontName("PetDressedTimerDogCorgiWalktinyCrown"))
    }
}

private actor AccessoryPetStore: PetStore {
    private var value = PersistedAppState()
    private var fails = false
    func fail(_ enabled: Bool) { fails = enabled }
    func load() -> PersistedAppState { value }
    func save(_ state: PersistedAppState) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        value = state
    }
}

private actor AccessoryArcadeStore: ArcadeStore {
    private var value = ArcadeState(progress: ArcadeProgress(coins: 200))
    private var fails = false
    func fail(_ enabled: Bool) { fails = enabled }
    func load() -> ArcadeState { value }
    func save(_ state: ArcadeState) throws {
        if fails { throw CocoaError(.fileWriteUnknown) }
        value = state
    }
}
