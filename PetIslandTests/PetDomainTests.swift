import XCTest
import CoreText
import SwiftUI
@testable import PetIsland

final class PetDomainTests: XCTestCase {

    func testProfileRefreshStopsWhenCoveredAndOtherwiseTicksOnceAMinute() {
        let start = Date(timeIntervalSince1970: 2000)
        XCTAssertEqual(Array(PetProfileRefreshSchedule(paused: true).entries(from: start, mode: .normal)), [start])
        let entries = Array(PetProfileRefreshSchedule(paused: false).entries(from: start, mode: .normal).prefix(3))
        XCTAssertEqual(entries, [start, start.addingTimeInterval(60), start.addingTimeInterval(120)])
    }

    @MainActor
    func testProfileOverviewIsReadOnlyAndUsesRequestedPet() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let state = profileCardState()
        let pet = state.pets[1]
        let store = InMemoryPetStore(state)
        let arcade = InMemoryArcadeStore(ArcadeState(vitalsByPetID: [pet.id: PetVitals(fullness: 0.4, happiness: 0.6, energy: 0.7)]))
        let controller = PetSessionController(store: store, arcadeStore: arcade)
        XCTAssertNil(controller.profileOverview(for: pet.id))
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: [pet.id]))
        let saved = await store.load()
        let shared = PetHabitatStore.load()
        let overview = try XCTUnwrap(controller.profileOverview(for: pet.id))
        XCTAssertEqual(overview.pet, pet)
        XCTAssertEqual(overview.vitals.fullness, 0.4)
        XCTAssertEqual(overview.location, .enclosure)
        XCTAssertEqual(controller.profileOverview(for: state.pets[0].id)?.location, .home)
        XCTAssertNil(controller.profileOverview(for: UUID()))
        for _ in 0..<20 { _ = controller.profileOverview(for: pet.id) }
        let after = await store.load()
        XCTAssertEqual(after, saved)
        XCTAssertEqual(PetHabitatStore.load(), shared, "Opening a card must not rewrite placement or sprites")
    }

    @MainActor
    func testProfileWalkReturnUpdatesLocationWithoutHidingUncollectedFind() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let state = profileCardState()
        let pet = state.pets[1]
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        XCTAssertTrue(controller.saveHabitat(theme: .meadow, residentPetIDs: [pet.id]))
        let start = Date.now
        let started = await controller.startDiscoveryWalk(petID: pet.id, route: .garden, at: start)
        XCTAssertTrue(started)
        let walk = try XCTUnwrap(controller.discoveries.activeWalk)
        XCTAssertEqual(controller.profileOverview(for: pet.id, at: walk.endsAt.addingTimeInterval(-1))?.location, .walking)
        XCTAssertEqual(controller.profileOverview(for: pet.id, at: walk.endsAt)?.location, .enclosure)
        XCTAssertEqual(controller.profileOverview(for: pet.id, at: walk.endsAt)?.walk, walk)
        XCTAssertNil(controller.profileOverview(for: state.pets[0].id)?.walk)
        let collected = await controller.collectDiscoveryWalk(at: walk.endsAt)
        XCTAssertNotNil(collected)
        let returned = try XCTUnwrap(controller.profileOverview(for: pet.id, at: walk.endsAt))
        XCTAssertNil(returned.walk)
        XCTAssertEqual(returned.memories.map(\.id), [walk.id])
    }

    @MainActor
    func testProfileMemoriesFollowIdentityAcrossRenameAndMatchingNames() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        var state = profileCardState()
        let start = Date.now.addingTimeInterval(-10000)
        let pet = state.pets[1]
        state.discoveries.startWalk(pet: pet, route: .garden, at: start)
        state.discoveries.collectWalk(at: start.addingTimeInterval(1300))
        state.discoveries.startWalk(pet: state.pets[0], route: .garden, at: start.addingTimeInterval(1500))
        state.discoveries.collectWalk(at: start.addingTimeInterval(2800))
        state.discoveries.startWalk(pet: pet, route: .shore, at: start.addingTimeInterval(3000))
        state.discoveries.collectWalk(at: start.addingTimeInterval(5500))
        state.pets[1].name = "Renamed"
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let overview = try XCTUnwrap(controller.profileOverview(for: pet.id))
        XCTAssertEqual(overview.pet.name, "Renamed")
        XCTAssertEqual(overview.memories.count, 2)
        XCTAssertEqual(overview.memories.map(\.route), [.shore, .garden])
        XCTAssertTrue(overview.memories.allSatisfy { $0.pet.id == pet.id && $0.pet.name == pet.name })
        XCTAssertEqual(controller.profileOverview(for: state.pets[0].id)?.memories.count, 1)
    }

    @MainActor
    func testProfileCareAndWardrobeOnlyChangeRequestedPet() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let state = profileCardState()
        let lead = state.pets[0], pet = state.pets[1]
        var stock = ArcadeInventory(); stock.add(.food, count: 2)
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore(
            ArcadeState(progress: ArcadeProgress(inventory: stock, ownedAccessories: [.knitHat]),
                        vitalsByPetID: [pet.id: PetVitals(fullness: 0.4, happiness: 0.6, energy: 0.7)])))
        await controller.bootstrap()
        let beforeLead = try XCTUnwrap(controller.profileOverview(for: lead.id))
        let fed = await controller.useArcadeItem(.food, for: pet.id)
        XCTAssertTrue(fed)
        let dressed = await controller.equipAccessory(.knitHat, for: pet.id)
        XCTAssertTrue(dressed)
        var renamed = pet; renamed.name = "New name"
        let saved = await controller.updatePet(renamed)
        XCTAssertTrue(saved)
        let overview = try XCTUnwrap(controller.profileOverview(for: pet.id))
        XCTAssertEqual(overview.pet.name, "New name")
        XCTAssertEqual(overview.pet.outfit?.headwear, .knitHat)
        XCTAssertEqual(overview.vitals.fullness, 0.64, accuracy: 0.0001)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 1)
        XCTAssertEqual(controller.profileOverview(for: lead.id)?.pet, beforeLead.pet)
        XCTAssertEqual(controller.profileOverview(for: lead.id)?.vitals.fullness, beforeLead.vitals.fullness)
        XCTAssertEqual(controller.profile.id, lead.id)
    }

    @MainActor
    func testProfileOfRemovedPetDoesNotFallBackToLead() async {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let state = profileCardState()
        let pet = state.pets[1]
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        let removed = await controller.removePet(id: pet.id)
        XCTAssertTrue(removed)
        XCTAssertNil(controller.profileOverview(for: pet.id))
        XCTAssertNotNil(controller.profileOverview(for: state.pets[0].id))
    }

    private func profileCardState() -> PersistedAppState {
        var state = PersistedAppState()
        state.pets = [
            PetProfile(id: UUID(), name: "Same name", species: .dog, coat: .sunrise, createdAt: .now, breed: .corgi),
            PetProfile(id: UUID(), name: "Same name", species: .cat, coat: .sunrise, createdAt: .now, breed: .maineCoon)
        ]
        state.activePetIDs = [state.pets[0].id]
        state.completedOnboarding = true
        state.normalizePetCollection()
        return state
    }

    func testPowerPolicyUsesThirtyFramesOnlyWhenEnergyOrHeatRequiresIt() {
        for thermal: ProcessInfo.ThermalState in [.nominal, .fair, .serious, .critical] {
            let regular = PetAnimationPowerPolicy(lowPowerMode: false, thermalState: thermal)
            XCTAssertEqual(regular.framesPerSecond, thermal == .nominal || thermal == .fair ? 60 : 30)
            let lowPower = PetAnimationPowerPolicy(lowPowerMode: true, thermalState: thermal)
            XCTAssertEqual(lowPower.framesPerSecond, 30)
            XCTAssertEqual(lowPower.frameInterval, 1.0 / 30)
        }
    }

    @MainActor
    func testPowerMonitorRespondsToEventsWithoutPollingOrRedundantPublications() async throws {
        let center = NotificationCenter()
        var current = PetAnimationPowerPolicy.normal
        var reads = 0
        var monitor: PetPowerMonitor? = PetPowerMonitor(center: center, readPolicy: { reads += 1; return current })
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(monitor?.policy, .normal)
        var publications = 0
        let observation = monitor?.objectWillChange.sink { publications += 1 }
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(publications, 0)
        current = .constrained
        center.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(monitor?.policy, .constrained)
        XCTAssertEqual(publications, 1)
        current = .normal
        center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(monitor?.policy, .normal)
        XCTAssertEqual(publications, 2)
        let lastReads = reads
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reads, lastReads, "No periodic work while idle")
        observation?.cancel()
        let wasReleased = { [weak monitor] in monitor == nil }
        monitor = nil
        XCTAssertTrue(wasReleased())
        center.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(reads, lastReads, "Observers must be released with their owner")
    }

    @MainActor
    func testPowerTransitionsPreservePetStateAndNeverRestartHiddenScenes() {
        let habitat = HabitatMotionSimulation()
        habitat.configure(pets: [.starter], size: CGSize(width: 345, height: 240))
        let yard = PlayYardSimulation(pets: [.starter], hapticsEnabled: false)
        yard.configure(roomSize: CGSize(width: 393, height: 740))
        defer { habitat.stop(); yard.stop() }
        habitat.start(reduceMotion: false, active: true)
        yard.start(reduceMotion: false)
        for _ in 0..<90 { habitat.advance(by: 1.0 / 60); yard.advance(by: 1.0 / 60) }
        let actors = habitat.actors
        let frame = yard.frame
        for policy: PetAnimationPowerPolicy in [.constrained, .normal, .constrained] {
            habitat.setPowerPolicy(policy); yard.setPowerPolicy(policy)
            XCTAssertEqual(habitat.preferredFramesPerSecond, policy.framesPerSecond)
            XCTAssertEqual(yard.preferredFramesPerSecond, policy.framesPerSecond)
            XCTAssertEqual(habitat.actors, actors, "Changing refresh rate must not reset position or gait")
            XCTAssertTrue(yard.frame.hasSameAppearance(as: frame, reduceMotion: false))
        }
        yard.setReduceMotion(true)
        XCTAssertEqual(yard.preferredFramesPerSecond, 15)
        yard.setPowerPolicy(.normal)
        XCTAssertEqual(yard.preferredFramesPerSecond, 15, "Accessibility setting takes precedence")
        yard.setReduceMotion(false)
        XCTAssertEqual(yard.preferredFramesPerSecond, 60)
        habitat.start(reduceMotion: false, active: false)
        yard.stop()
        habitat.setPowerPolicy(.constrained); yard.setPowerPolicy(.constrained)
        XCTAssertNil(habitat.preferredFramesPerSecond)
        XCTAssertNil(yard.preferredFramesPerSecond)
        habitat.start(reduceMotion: true, active: true, powerPolicy: .constrained)
        XCTAssertFalse(habitat.isRunning)
        habitat.start(reduceMotion: false, active: true, powerPolicy: .constrained)
        yard.start(reduceMotion: false, powerPolicy: .constrained)
        XCTAssertEqual(habitat.preferredFramesPerSecond, 30)
        XCTAssertEqual(yard.preferredFramesPerSecond, 30)
    }

    @MainActor
    func testLowerRefreshRateKeepsWalkingSpeedAndStrideDistance() {
        let pet = PetProfile(id: UUID(uuidString: "01000000-0000-0000-0000-000000000001")!,
                             name: "Pixel", species: .dog, coat: .sunrise, createdAt: .distantPast)
        var distances: [Double] = []
        var lastActors: [HabitatMotionSimulation.Actor] = []
        for fps in [60, 30] {
            let habitat = HabitatMotionSimulation()
            habitat.configure(pets: [pet], size: CGSize(width: 600, height: 300))
            var distance = 0.0
            for _ in 0..<(fps * 5) {
                let before = habitat.actors[0]
                habitat.advance(by: 1 / Double(fps))
                let after = habitat.actors[0]
                distance += hypot(after.position.x - before.position.x, after.position.y - before.position.y)
                XCTAssertEqual(after.visualOffsetY, 0)
            }
            distances.append(distance); lastActors.append(habitat.actors[0])
        }
        XCTAssertGreaterThan(distances[0], 20)
        XCTAssertEqual(distances[0], distances[1], accuracy: 3, "Rendering at 30 Hz must not halve the walking speed")
        XCTAssertEqual(lastActors[0].gaitPhase, lastActors[1].gaitPhase, accuracy: 0.12)
    }

    @MainActor
    func testFlyingAndFetchingRemainAnimatedAtBothRefreshRates() {
        let bird = PetProfile(id: UUID(), name: "Bird", species: .parrot, coat: .sunrise, createdAt: .now)
        for fps in [30, 60] {
            let flying = PlayYardSimulation(pets: [bird], hapticsEnabled: false)
            flying.configure(roomSize: CGSize(width: 393, height: 740))
            var publications = 0
            let observation = flying.objectWillChange.sink { publications += 1 }
            for _ in 0..<fps { flying.advance(by: 1 / Double(fps)) }
            XCTAssertEqual(publications, fps, "Continuous bird lift remains visible even between sprite changes")
            observation.cancel()
            let yard = PlayYardSimulation(pets: [.starter], hapticsEnabled: false)
            yard.configure(roomSize: CGSize(width: 393, height: 740))
            let start = yard.frame.ballPosition
            yard.dragBall(to: start)
            yard.dragBall(to: CGPoint(x: start.x + 60, y: start.y - 70))
            yard.throwBall(toward: CGPoint(x: start.x + 120, y: start.y - 150))
            for _ in 0..<(fps * 30) {
                yard.advance(by: 1 / Double(fps))
                XCTAssertTrue(yard.frame.ballPosition.x.isFinite && yard.frame.ballPosition.y.isFinite)
                if yard.frame.score > 0 { break }
            }
            XCTAssertEqual(yard.frame.throwCount, 1)
            XCTAssertEqual(yard.frame.score, 1, "Catching and returning the ball must work at \(fps) Hz")
        }
    }

    func testCareItemsRequireAPositiveBenefit() {
        let full = PetVitals(fullness: 1, happiness: 1, energy: 1)
        for item in ArcadeItemKind.allCases {
            XCTAssertFalse(ArcadeEconomy.hasBenefit(item, for: full), "\(item)")
        }
        XCTAssertFalse(ArcadeEconomy.hasBenefit(.toy, for: PetVitals(fullness: 0.5, happiness: 1, energy: 0.5)))
        XCTAssertFalse(ArcadeEconomy.hasBenefit(.food, for: PetVitals(fullness: 1, happiness: 0.5, energy: 0.5)))
        XCTAssertTrue(ArcadeEconomy.hasBenefit(.treat, for: PetVitals(fullness: 1, happiness: 0.5, energy: 1)))
        XCTAssertTrue(ArcadeEconomy.hasBenefit(.treat, for: PetVitals(fullness: 0.5, happiness: 1, energy: 1)))
        XCTAssertTrue(ArcadeEconomy.hasBenefit(.vitamins, for: PetVitals(fullness: 1, happiness: 0.5, energy: 1)))
        XCTAssertTrue(ArcadeEconomy.hasBenefit(.vitamins, for: PetVitals(fullness: 1, happiness: 1, energy: 0.5)))
        XCTAssertTrue(ArcadeEconomy.hasBenefit(.food, for: PetVitals(fullness: 0.99, happiness: 1, energy: 1)))
    }

    @MainActor
    func testCareRejectsUnloadedUnknownAndWalkingPetsWithoutConsumingItems() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let pet = PetProfile(id: UUID(), name: "Care test", species: .cat, coat: .sunrise, createdAt: .now)
        var state = PersistedAppState(); state.pets = [pet]; state.activePetIDs = [pet.id]
        var inventory = ArcadeInventory()
        for item in ArcadeItemKind.allCases { inventory.add(item) }
        let store = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 100, inventory: inventory)))
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: store)
        let unloaded = await controller.useArcadeItem(.food, for: pet.id)
        XCTAssertFalse(unloaded)
        await controller.bootstrap()
        let unknown = await controller.useArcadeItem(.food, for: UUID())
        XCTAssertFalse(unknown)
        let started = await controller.startDiscoveryWalk(petID: pet.id, route: .garden, at: .now)
        XCTAssertTrue(started)
        for item in ArcadeItemKind.allCases {
            XCTAssertNotNil(controller.arcadeItemUnavailableReason(item, for: pet.id))
            let given = await controller.useArcadeItem(item, for: pet.id)
            XCTAssertFalse(given)
            XCTAssertEqual(controller.arcadeProgress.inventory[item], 1)
        }
        // Shopping remains available while the pet is away; only giving is blocked.
        let bought = await controller.purchaseArcadeItem(.food)
        XCTAssertTrue(bought)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 2)
        _ = await controller.cancelDiscoveryWalk()
        let givenAfterReturn = await controller.useArcadeItem(.food, for: pet.id)
        XCTAssertTrue(givenAfterReturn)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 1)
    }

    @MainActor
    func testCareRechecksWidgetUpdatesAndSerializesRepeatedTaps() async throws {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let pet = PetProfile(id: UUID(), name: "Care test", species: .cat, coat: .sunrise, createdAt: .now)
        var state = PersistedAppState(); state.pets = [pet]; state.activePetIDs = [pet.id]
        var inventory = ArcadeInventory(); inventory.add(.food, count: 3); inventory.add(.toy)
        let store = InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(inventory: inventory)))
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: store)
        await controller.bootstrap()
        try PetHabitatStore.update { shared in
            let index = shared.residents.firstIndex { $0.id == pet.id }!
            shared.residents[index].vitals = PetVitals(fullness: 1, happiness: 1, energy: 0.5)
            shared.residents[index].vitalsUpdatedAt = .now
        }
        let food = await controller.useArcadeItem(.food, for: pet.id)
        let toy = await controller.useArcadeItem(.toy, for: pet.id)
        XCTAssertFalse(food); XCTAssertFalse(toy)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 3)
        XCTAssertEqual(controller.arcadeProgress.inventory[.toy], 1)
        XCTAssertEqual(controller.vitals(for: pet.id).energy, 0.5, accuracy: 0.001)
        try PetHabitatStore.update { shared in
            let index = shared.residents.firstIndex { $0.id == pet.id }!
            shared.residents[index].vitals.fullness = 0.9
            shared.residents[index].vitalsUpdatedAt = .now
        }
        async let first = controller.useArcadeItem(.food, for: pet.id)
        async let second = controller.useArcadeItem(.food, for: pet.id)
        let results = await [first, second]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 2)
        XCTAssertEqual(controller.vitals(for: pet.id).fullness, 1)
        let saved = await store.load()
        XCTAssertEqual(saved.progress.inventory[.food], 2)
        XCTAssertTrue(saved.pendingCareEvents.isEmpty)
    }

    @MainActor
    func testFailedCareSaveKeepsInventoryAndVitalsThenRetryAppliesOnce() async {
        let original = PetHabitatStore.load()
        defer { try? PetHabitatStore.save(original) }
        let pet = PetProfile(id: UUID(), name: "Care test", species: .cat, coat: .sunrise, createdAt: .now)
        var state = PersistedAppState(); state.pets = [pet]; state.activePetIDs = [pet.id]
        var inventory = ArcadeInventory(); inventory.add(.food)
        let store = FailableArcadeStore(ArcadeState(progress: ArcadeProgress(inventory: inventory)))
        let controller = PetSessionController(store: InMemoryPetStore(state), arcadeStore: store)
        await controller.bootstrap()
        let fullness = controller.vitals(for: pet.id).fullness
        await store.setFailure(true)
        let failed = await controller.useArcadeItem(.food, for: pet.id)
        XCTAssertFalse(failed)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 1)
        XCTAssertEqual(controller.vitals(for: pet.id).fullness, fullness)
        await store.setFailure(false)
        let retry = await controller.useArcadeItem(.food, for: pet.id)
        let duplicate = await controller.useArcadeItem(.food, for: pet.id)
        XCTAssertTrue(retry); XCTAssertFalse(duplicate)
        XCTAssertEqual(controller.arcadeProgress.inventory[.food], 0)
        XCTAssertEqual(controller.vitals(for: pet.id).fullness, min(fullness + 0.24, 1), accuracy: 0.00001)
    }

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
            let remaining = simulation.actors.first { $0.id == actor.id }
            XCTAssertEqual(remaining?.position, actor.position)
            XCTAssertEqual(remaining?.target, actor.target)
            XCTAssertEqual(remaining?.velocity, actor.velocity)
            XCTAssertEqual(remaining?.gaitPhase, actor.gaitPhase)
            XCTAssertEqual(remaining?.step, actor.step)
            XCTAssertEqual(remaining?.pose, actor.pose)
            XCTAssertEqual(remaining?.facing, actor.facing)
            XCTAssertEqual(remaining?.waiting, actor.waiting)
        }
    }

    @MainActor
    func testRestingEnclosureKeepsItsClockWithoutPublishingIdenticalPictures() {
        let simulation = HabitatMotionSimulation()
        let pet = PetProfile(id: UUID(uuidString: "01000000-0000-0000-0000-000000000001")!,
                             name: "Pixel", species: .dog, coat: .sunrise, createdAt: .distantPast)
        simulation.configure(pets: [pet], size: CGSize(width: 345, height: 240))
        let before = simulation.actors[0]
        var publications = 0
        let observation = simulation.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        for _ in 0..<6 { simulation.advance(by: 1.0 / 60) }
        XCTAssertEqual(simulation.actors[0].position, before.position)
        XCTAssertEqual(simulation.actors[0].step, before.step)
        XCTAssertEqual(publications, 0, "An invisible waiting timer must not invalidate the scene")
        XCTAssertEqual(simulation.actors[0].waiting, before.waiting - 0.1, accuracy: 0.000001)

        var movingFrames = 0
        for _ in 0..<600 {
            let position = simulation.actors[0].position
            let oldPublications = publications
            simulation.advance(by: 1.0 / 60)
            if position != simulation.actors[0].position {
                movingFrames += 1
                XCTAssertGreaterThan(publications, oldPublications, "Every new position must reach the renderer")
            }
        }
        XCTAssertGreaterThan(movingFrames, 120, "Suppressing idle redraws must not freeze the simulation")
        let oldPublications = publications
        simulation.pet(pet.id)
        XCTAssertGreaterThan(publications, oldPublications, "Touch feedback must still appear immediately")
    }

    @MainActor
    func testIdlePlayYardDoesNotPublishInvisibleMotionPhaseChanges() {
        let yard = PlayYardSimulation(pets: [.starter], hapticsEnabled: false)
        yard.configure(roomSize: CGSize(width: 393, height: 740))
        var publications = 0, visibleChanges = 0
        let observation = yard.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        for _ in 0..<120 {
            let before = yard.frame.actors[0]
            yard.advance(by: 1.0 / 60)
            let after = yard.frame.actors[0]
            if before.position != after.position || before.step != after.step || before.pose != after.pose {
                visibleChanges += 1
            }
        }
        print("Idle playroom: publications=\(publications), visible_changes=\(visibleChanges), ticks=120")
        XCTAssertEqual(publications, visibleChanges)
        XCTAssertGreaterThan(yard.frame.actors[0].motionPhase, 0, "Keep the internal clock advancing")
    }

    @MainActor
    func testPlayYardRestoresSixtyFPSAfterChangingReduceMotion() {
        let yard = PlayYardSimulation(pets: [.starter], hapticsEnabled: false)
        yard.configure(roomSize: CGSize(width: 393, height: 740))
        defer { yard.stop() }
        yard.start(reduceMotion: false)
        XCTAssertEqual(yard.preferredFramesPerSecond, 60)
        yard.setReduceMotion(true)
        XCTAssertEqual(yard.preferredFramesPerSecond, 15)
        yard.setReduceMotion(false)
        XCTAssertEqual(yard.preferredFramesPerSecond, 60)
        yard.start(reduceMotion: false)
        XCTAssertEqual(yard.preferredFramesPerSecond, 60, "Repeated activation must not halve the rate")
        yard.stop()
        yard.setReduceMotion(false)
        XCTAssertNil(yard.preferredFramesPerSecond, "Changing a preference must not restart a hidden game")
        yard.start(reduceMotion: false)
        XCTAssertEqual(yard.preferredFramesPerSecond, 60)
    }

    @MainActor
    func testScrollVisibilityStopsAndResumesOffscreenAnimation() async throws {
        var visibility: [Bool] = []
        let content = ScrollView {
            VStack(spacing: 0) {
                Color.blue.frame(height: 120)
                    .onPetViewportVisibilityChange { visibility.append($0) }
                Color.clear.frame(height: 900)
            }
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(in: host.view))
        XCTAssertEqual(visibility.last, true)
        scroll.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(visibility.last, false)
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(visibility.last, true)
        XCTAssertEqual(visibility.suffix(3), [true, false, true])
    }

    @MainActor
    func testEmptyEnclosureStopsRenderingAndPublishesNoAnimationFrames() {
        let simulation = HabitatMotionSimulation()
        let size = CGSize(width: 345, height: 240)
        simulation.configure(pets: [.starter], size: size)
        simulation.start(reduceMotion: false, active: true)
        XCTAssertTrue(simulation.isRunning)

        simulation.configure(pets: [], size: size)
        XCTAssertFalse(simulation.isRunning)
        var framePublications = 0
        let observation = simulation.objectWillChange.sink { framePublications += 1 }
        defer { observation.cancel(); simulation.stop() }
        simulation.start(reduceMotion: false, active: true)
        XCTAssertFalse(simulation.isRunning)
        for _ in 0..<600 { simulation.advance(by: 1.0 / 60) }
        XCTAssertEqual(framePublications, 0)
        XCTAssertTrue(simulation.actors.isEmpty)
    }

    @MainActor
    func testReturningResidentAnimatesOnlyWhenActiveAndMotionIsAllowed() {
        let simulation = HabitatMotionSimulation()
        let size = CGSize(width: 345, height: 240)
        simulation.configure(pets: [], size: size)
        simulation.start(reduceMotion: false, active: true)
        XCTAssertFalse(simulation.isRunning)

        simulation.configure(pets: [.starter], size: size)
        simulation.start(reduceMotion: false, active: false)
        XCTAssertFalse(simulation.isRunning)
        simulation.start(reduceMotion: true, active: true)
        XCTAssertFalse(simulation.isRunning)
        let stillPosition = simulation.actors[0].position
        for _ in 0..<120 { simulation.advance(by: 1.0 / 60) }
        XCTAssertEqual(simulation.actors[0].position, stillPosition)

        simulation.start(reduceMotion: false, active: true)
        defer { simulation.stop() }
        XCTAssertTrue(simulation.isRunning)
        var travelled = 0.0
        for _ in 0..<600 {
            let previous = simulation.actors[0].position
            simulation.advance(by: 1.0 / 60)
            let current = simulation.actors[0].position
            travelled += hypot(current.x - previous.x, current.y - previous.y)
        }
        XCTAssertGreaterThan(travelled, 1)
        simulation.start(reduceMotion: false, active: false)
        XCTAssertFalse(simulation.isRunning)
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
                    let sharedCorgiWalk = breed == .corgi && pose == .walk
                    let naturalFrameCount = sharedCorgiWalk ? 4 : (breed == .cardigan ? 2 : 8)
                    XCTAssertEqual(clip.frames.count, naturalFrameCount)
                    XCTAssertEqual(Set(clip.frames).count, naturalFrameCount)
                    for name in clip.frames {
                        XCTAssertNotNil(UIImage(named: name), name)
                        let geometry = PetSpriteGeometry.load(assetName: name)
                        let origin = breed.companionArtworkToken == nil && !sharedCorgiWalk
                            ? CGPoint(x: -12, y: 0) : .zero
                        XCTAssertEqual(geometry?.rect(in: PetSpriteGeometry.canvas).origin, origin, name)
                        XCTAssertEqual(geometry?.scale, 1, name)
                    }
                    XCTAssertEqual(PetAnimationLibrary.clip(for: species, breed: breed, pose: pose).frames.count,
                                   sharedCorgiWalk ? 4 : (breed.companionArtworkToken == nil || breed == .cardigan ? 2 : 8))
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
                                                 direction: direction, step: 0, animatesMotion: false,
                                                 surface: viewport.width == 84 ? .standard : .dynamicIsland)
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

    func testSleepingShepherdStaysCurledWithinItsStandingSize() throws {
        let idleName = PetAnimationLibrary.clip(for: .dog, breed: .shepherd, pose: .idle).frames[0]
        let idle = try XCTUnwrap(PetSpriteGeometry.load(assetName: idleName))
        let sleep = PetAnimationLibrary.clip(for: .dog, breed: .shepherd, pose: .sleep)
        XCTAssertEqual(PetAnimationLibrary.naturalClip(for: .dog, breed: .shepherd, pose: .sleep).frames,
                       sleep.frames, "The habitat and system surfaces must share the sleeping artwork")
        for name in sleep.frames {
            let geometry = try XCTUnwrap(PetSpriteGeometry.load(assetName: name))
            XCTAssertEqual(geometry.scale, idle.scale, "Sleeping must not magnify the original pixels")
            XCTAssertLessThanOrEqual(geometry.visibleBounds.width * geometry.scale,
                                     idle.visibleBounds.width * idle.scale, name)
            XCTAssertLessThan(geometry.visibleBounds.height * geometry.scale,
                              idle.visibleBounds.height * idle.scale * 0.65, name)
            for viewport in [PetSpriteGeometry.canvas, CGSize(width: 84, height: 72),
                             CGSize(width: 36, height: 30), CGSize(width: 28, height: 25)] {
                let fit = min(viewport.width / PetSpriteGeometry.canvas.width,
                              viewport.height / PetSpriteGeometry.canvas.height)
                let rect = geometry.rect(in: viewport)
                let idleRect = idle.rect(in: viewport)
                XCTAssertEqual(rect.minY + geometry.visibleBounds.maxY * geometry.scale * fit,
                               idleRect.minY + idle.visibleBounds.maxY * idle.scale * fit,
                               accuracy: 0.001, "Sleep must keep the same ground line")
                XCTAssertEqual(rect.minX + geometry.visibleBounds.midX * geometry.scale * fit,
                               viewport.width / 2, accuracy: 0.001, "Sleep must stay centered")
            }
        }
    }

    @MainActor
    func testShepherdMixedTimerSleepMatchesEachSurfacesStaticArtwork() throws {
        try registerTimerFonts()
        for viewport in [CGSize(width: 36, height: 30), CGSize(width: 28, height: 25),
                         CGSize(width: 84, height: 72)] {
            let family = viewport.width == 84 ? "PetIslandLockTimer" : "PetIslandTimer"
            for direction in [PetDirection.left, .right] {
                let artwork = PetArtwork(species: .dog, breed: .shepherd, pose: .sleep,
                                         direction: direction, animatesMotion: false, usesNaturalGait: true,
                                         surface: viewport.width == 84 ? .standard : .dynamicIsland)
                    .frame(width: viewport.width, height: viewport.height)
                let pngBounds = try renderedBounds(artwork)
                for mode in ["RunSleep", "WalkSleep", "RunWalkSleep"] {
                    for digit in 7...9 {
                        let glyph = PetTimerGlyphViewport(text: Text("\(digit)"),
                            fontName: family + "DogShepherd" + mode, viewport: viewport, direction: direction)
                        let bounds = try renderedBounds(glyph)
                        let sample = "\(family), \(mode), \(digit), \(direction)"
                        XCTAssertEqual(bounds.minX, pngBounds.minX, accuracy: 1.5, sample)
                        XCTAssertEqual(bounds.maxX, pngBounds.maxX, accuracy: 1.5, sample)
                        XCTAssertEqual(bounds.minY, pngBounds.minY, accuracy: 1.5, sample)
                        XCTAssertEqual(bounds.maxY, pngBounds.maxY, accuracy: 1.5, sample)
                    }
                }
            }
        }
    }

    func testDynamicIslandKeepsItsOriginalShepherdSleepSizeAndOtherPetsGeometry() throws {
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for pose in PetPose.allCases {
                    for name in PetAnimationLibrary.clip(for: species, breed: breed, pose: pose).frames {
                        let standard = try XCTUnwrap(PetSpriteGeometry.load(assetName: name))
                        let island = try XCTUnwrap(PetSpriteGeometry.load(assetName: name, surface: .dynamicIsland))
                        if species == .dog && breed == .shepherd && pose == .sleep {
                            XCTAssertEqual(island.visibleBounds.width * island.scale, 180, accuracy: 0.001)
                            XCTAssertLessThan(standard.scale, island.scale)
                            let rect = island.rect(in: PetSpriteGeometry.canvas)
                            XCTAssertEqual(rect.minY + island.visibleBounds.maxY * island.scale, 160, accuracy: 0.001)
                        } else {
                            XCTAssertEqual(standard.scale, island.scale, name)
                            XCTAssertEqual(standard.rect(in: PetSpriteGeometry.canvas),
                                           island.rect(in: PetSpriteGeometry.canvas), name)
                        }
                        // A shared asset loaded for DI must not replace its app geometry in the cache.
                        XCTAssertEqual(PetSpriteGeometry.load(assetName: name)?.scale, standard.scale)
                    }
                }
            }
        }
    }

    @MainActor
    func testAllPetsMeetLockScreenLineInEveryTimerModeAndSleepingArtwork() throws {
        try registerTimerFonts()
        let viewport = CGSize(width: 84, height: 72)
        let trackHeight: CGFloat = 86
        let lineTop = trackHeight - 7 - 4
        let breeds: [(PetSpecies, PetBreed, String)] = [
            (.dog, .shepherd, "DogShepherd"), (.dog, .corgi, "DogCorgi"),
            (.dog, .cardigan, "DogCardigan"), (.dog, .doberman, "DogDoberman"),
            (.dog, .bullTerrier, "DogBullTerrier"),
            (.cat, .classicCat, "CatClassic"), (.cat, .britishShorthair, "CatBritish"),
            (.cat, .maineCoon, "CatMaineCoon"), (.cat, .siamese, "CatSiamese"),
            (.fox, .redFox, "FoxRed"), (.fox, .arcticFox, "FoxArctic"),
            (.parrot, .classicParrot, "ParrotClassic"), (.parrot, .cockatiel, "ParrotCockatiel"),
            (.parrot, .budgie, "ParrotBudgie"), (.parrot, .macaw, "ParrotMacaw"),
            (.penguin, .classicPenguin, "PenguinClassic"), (.penguin, .rockhopper, "PenguinRockhopper"),
            (.lion, .adultLion, "LionAdult"), (.lion, .lioness, "Lioness"), (.lion, .lionCub, "LionCub")
        ]
        XCTAssertEqual(Set(breeds.map { $0.1 }), Set(PetBreed.allCases))
        for (species, breed, token) in breeds {
            let center = PetLockScreenSpriteAlignment.centerY(trackHeight: trackHeight, viewport: viewport)
            for direction in [PetDirection.left, .right] {
                for mode in ["Run", "Walk", "Sleep", "RunSleep", "WalkSleep", "RunWalkSleep"] {
                    for digit in 0...9 {
                        let bounds = try renderedBounds(PetTimerGlyphViewport(text: Text("1:00:\(digit)"),
                            fontName: "PetIslandLockTimer" + token + mode, viewport: viewport, direction: direction))
                        let isRun = mode == "Run" || (mode == "RunSleep" && digit < 7)
                            || (mode == "RunWalkSleep" && digit < 4)
                        // Preserve the authored flight frames; grounding each
                        // individual image would make these animals drop mid-stride.
                        let clearance: CGFloat = isRun && digit % 2 == 1
                            ? (breed == .cardigan ? 10 : breed == .adultLion ? 12 : 0) : 0
                        XCTAssertEqual(center - viewport.height / 2 + bounds.maxY,
                                       lineTop - clearance * 84 / 220, accuracy: 1,
                                       "\(token) \(mode) \(digit) \(direction)")
                    }
                }
                for step in PetAnimationLibrary.clip(for: species, breed: breed, pose: .sleep).frames.indices {
                    let bounds = try renderedBounds(PetArtwork(species: species, breed: breed, pose: .sleep,
                        direction: direction, step: step, animatesMotion: false)
                        .frame(width: viewport.width, height: viewport.height))
                    XCTAssertEqual(center - viewport.height / 2 + bounds.maxY, lineTop, accuracy: 1, token)
                }
            }
        }
    }

    @MainActor
    func testAllPetsMeetExpandedIslandLineWithoutChangingSpriteSize() throws {
        // Include a height-constrained viewport to catch assumptions that width
        // alone determines the fit, as well as the actual expanded DI size.
        for viewport in [CGSize(width: 50, height: 44), CGSize(width: 100, height: 50)] {
            let center = PetLockScreenSpriteAlignment.centerY(trackHeight: 72, viewport: viewport)
            for species in PetSpecies.allCases {
                for breed in PetBreed.available(for: species) {
                    for pose in [PetPose.walk, .sleep] {
                        let clip = PetAnimationLibrary.clip(for: species, breed: breed, pose: pose)
                        for step in clip.frames.indices {
                            for direction in [PetDirection.left, .right] {
                                let bounds = try renderedBounds(PetArtwork(species: species, breed: breed, pose: pose,
                                    direction: direction, step: step, animatesMotion: false, surface: .dynamicIsland)
                                    .frame(width: viewport.width, height: viewport.height))
                                XCTAssertEqual(center - viewport.height / 2 + bounds.maxY, 61, accuracy: 1,
                                               "\(breed) \(pose) \(step) \(viewport) \(direction)")
                            }
                        }
                    }
                }
            }
        }
    }

    func testAllForegroundPetsKeepGroundedWalkAndAuthoredFlightClearance() throws {
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for pose in [PetPose.walk, .run, .idle, .sleep, .play, .eat] {
                    let clip = PetAnimationLibrary.naturalClip(for: species, breed: breed, pose: pose)
                    for name in clip.frames {
                        let geometry = try XCTUnwrap(PetSpriteGeometry.load(assetName: name), name)
                        for viewport in [CGSize(width: 78, height: 62.4), CGSize(width: 104, height: 83.2)] {
                            let fit = viewport.width / 220
                            let rect = geometry.rect(in: viewport)
                            let foot = rect.minY + geometry.visibleBounds.maxY * geometry.scale * fit
                            let authoredClearance = geometry.preservesAuthoredBaseline
                                ? 160 - geometry.visibleBounds.maxY : 0
                            if pose != .run {
                                // Some original companion canvases include one
                                // extra contact pixel. Allow it plus float rounding.
                                XCTAssertEqual(foot, 160 * fit, accuracy: fit + 0.0001, name)
                            } else {
                                XCTAssertEqual(foot, (160 - authoredClearance) * fit, accuracy: 0.001, name)
                                XCTAssertLessThanOrEqual(foot, 161 * fit, name)
                            }
                        }
                    }
                }
            }
        }
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
        for breed in ["cat", "cat_british", "cat_maine_coon", "cat_siamese", "fox", "dog_corgi"] {
            let first = try XCTUnwrap(PetSpriteGeometry.load(assetName: "island_\(breed)_walk_0"))
            let second = try XCTUnwrap(PetSpriteGeometry.load(assetName: "island_\(breed)_walk_1"))
            XCTAssertEqual(first.sourceSize, PetSpriteGeometry.canvas)
            XCTAssertEqual(second.sourceSize, PetSpriteGeometry.canvas)
            // A cat's ears may move by one authored pixel while its grounded
            // paws and muzzle stay registered; the fox artwork is unchanged.
            XCTAssertEqual(first.visibleBounds.minY, second.visibleBounds.minY,
                           accuracy: breed.hasPrefix("cat") ? 1 : 0)
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

        XCTAssertEqual(walk.frames, (0..<4).map { "island_dog_corgi_walk_\($0)" })
        XCTAssertEqual(run.frames, ["island_dog_corgi_run_0", "island_dog_corgi_run_1"])
        XCTAssertLessThan(run.frameDuration, walk.frameDuration)
    }

    func testShepherdJumpUsesItsAirborneGallopFrame() {
        let jump = PetAnimationLibrary.clip(for: .dog, breed: .shepherd, pose: .jump)

        XCTAssertEqual(jump.frames, ["island_dog_shepherd_run_0"])
    }

    func testCatsUseTheirRestoredJumpArtwork() {
        for (breed, token) in [(PetBreed.classicCat, "cat"), (.britishShorthair, "cat_british"),
                               (.maineCoon, "cat_maine_coon"), (.siamese, "cat_siamese")] {
            let jump = PetAnimationLibrary.clip(for: .cat, breed: breed, pose: .jump)
            XCTAssertEqual(jump.frames, ["island_\(token)_jump"])
        }
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
    func testCorgiFourBeatWalkStaysRegisteredWithoutReplacingRun() throws {
        let walk = PetAnimationLibrary.clip(for: .dog, breed: .corgi, pose: .walk)
        XCTAssertEqual(walk, PetAnimationLibrary.naturalClip(for: .dog, breed: .corgi, pose: .walk))
        XCTAssertEqual(walk.frames.count, 4)
        XCTAssertEqual(walk.cycleDuration, 0.72, accuracy: 0.0001)
        XCTAssertEqual(walk.frameName(forStep: 4), walk.frameName(forStep: 0))
        for step in 0..<8 {
            XCTAssertEqual(walk.frameIndex(at: Double(step) * 0.18 + 0.001), step % 4)
            XCTAssertEqual(walk.travelFrameIndex(distance: Double(step) * 4.5 + 0.001,
                                                canvasWidth: 100, pose: .walk), step % 4)
        }

        for step in 0..<4 {
            let geometry = try XCTUnwrap(PetSpriteGeometry.load(assetName: walk.frames[step]))
            XCTAssertEqual(geometry.sourceSize, PetSpriteGeometry.canvas)
            XCTAssertEqual(geometry.visibleBounds.maxY, PetSpriteGeometry.baseline)
            XCTAssertEqual(geometry.visibleBounds.maxX, 178)
            XCTAssertEqual(geometry.visibleBounds.minY, 42, accuracy: 1)
            XCTAssertEqual(geometry.rect(in: PetSpriteGeometry.canvas).origin, .zero)
            for direction in [PetDirection.left, .right] {
                let standard = PetArtwork(species: .dog, breed: .corgi, pose: .walk,
                    direction: direction, step: step, animatesMotion: false)
                    .frame(width: 110, height: 88)
                let foreground = PetArtwork(species: .dog, breed: .corgi, pose: .walk,
                    direction: direction, step: step, animatesMotion: false, usesNaturalGait: true)
                    .frame(width: 110, height: 88)
                XCTAssertEqual(try renderedBounds(standard), try renderedBounds(foreground))
            }
        }
        let run = PetAnimationLibrary.clip(for: .dog, breed: .corgi, pose: .run)
        XCTAssertEqual(run.frames, ["island_dog_corgi_run_0", "island_dog_corgi_run_1"])
        XCTAssertEqual(run.frameDuration, 0.09)
        let naturalRun = PetAnimationLibrary.naturalClip(for: .dog, breed: .corgi, pose: .run)
        XCTAssertEqual(naturalRun.frames, (0..<8).map { "fluid_dog_corgi_run_\($0)" })
        XCTAssertEqual(naturalRun.frameDuration, 0.08)
    }

    func testCorgiShortWalkStridePreservesAllOtherGaits() {
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for pose in [PetPose.walk, .run] {
                    let ratio = PetAnimationLibrary.enclosureStrideRatio(for: species, breed: breed, pose: pose)
                    if species == .dog, breed == .corgi, pose == .walk {
                        XCTAssertEqual(ratio, 0.18)
                    } else {
                        XCTAssertEqual(ratio, pose == .run ? 0.55 : 0.38, "\(breed) \(pose)")
                    }
                }
            }
        }
    }

    @MainActor
    func testCorgiHabitatWalkUsesEveryApprovedPhaseAndStopsWithReducedMotion() throws {
        let pet = PetProfile(id: UUID(uuidString: "E2222222-2222-2222-2222-222222222222")!,
            name: "Corgi", species: .dog, coat: .sunrise, createdAt: .distantPast, breed: .corgi)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [pet], size: CGSize(width: 360, height: 180))
        var steps = Set<Int>()
        var transitions = 0
        for _ in 0..<2400 {
            let old = try XCTUnwrap(simulation.actors.first)
            simulation.advance(by: 1.0 / 30)
            let actor = try XCTUnwrap(simulation.actors.first)
            guard actor.pose == .walk else { continue }
            XCTAssertTrue((0..<4).contains(actor.step))
            steps.insert(actor.step)
            if old.pose == .walk, old.step != actor.step {
                XCTAssertEqual(actor.step, (old.step + 1) % 4, "Walking must not skip the forward reach")
                transitions += 1
            }
        }
        XCTAssertEqual(steps, Set(0..<4))
        XCTAssertGreaterThan(transitions, 12)
        simulation.start(reduceMotion: true, active: true)
        let positions = simulation.actors.map(\.position)
        simulation.advance(by: 1)
        XCTAssertEqual(simulation.actors.map(\.position), positions)
        XCTAssertFalse(simulation.isRunning)
    }

    func testCardiganPushOffTouchesGroundBeforeItsExtendedFlightFrame() throws {
        for pose in [PetPose.walk, .run] {
            let clip = PetAnimationLibrary.clip(for: .dog, breed: .cardigan, pose: pose)
            XCTAssertEqual(clip, PetAnimationLibrary.naturalClip(for: .dog, breed: .cardigan, pose: pose))
            XCTAssertEqual(clip.frames.count, 2)
            let first = try XCTUnwrap(PetSpriteGeometry.load(assetName: clip.frameName(forStep: 0)))
            let second = try XCTUnwrap(PetSpriteGeometry.load(assetName: clip.frameName(forStep: 1)))
            for geometry in [first, second] {
                XCTAssertEqual(geometry.sourceSize, PetSpriteGeometry.canvas)
                XCTAssertEqual(geometry.scale, 1)
                XCTAssertEqual(geometry.horizontalAnchor, 110)
                XCTAssertEqual(geometry.rect(in: PetSpriteGeometry.canvas).origin, .zero)
            }
            XCTAssertEqual(first.visibleBounds.maxY, PetSpriteGeometry.baseline)
            if pose == .run {
                XCTAssertEqual(second.visibleBounds.maxY, PetSpriteGeometry.baseline - 10)
                XCTAssertEqual(first.visibleBounds.minY - second.visibleBounds.minY, 14)
            } else {
                XCTAssertEqual(second.visibleBounds.maxY, PetSpriteGeometry.baseline)
                XCTAssertEqual(first.visibleBounds, second.visibleBounds)
            }
            // Moving and then stopping must keep the chosen contact/flight
            // frame stable; the next half-stride changes to the other drawing.
            let stride = 100.0 * (pose == .run ? 0.26 : 0.18)
            XCTAssertEqual(clip.travelFrameIndex(distance: 0, canvasWidth: 100, pose: pose), 0)
            XCTAssertEqual(clip.travelFrameIndex(distance: stride * 0.51, canvasWidth: 100, pose: pose), 1)
            XCTAssertEqual(clip.travelFrameIndex(distance: stride * 1.01, canvasWidth: 100, pose: pose), 0)
            XCTAssertEqual(clip.frameName(forStep: 2), clip.frameName(forStep: 0))
        }
    }

    @MainActor
    func testCardiganTimerModesMatchGroundedAndAirbornePNGFrames() throws {
        try assertTimerModesMatchPNGFrames(breed: .cardigan, fontToken: "DogCardigan")
    }

    @MainActor
    func testCorgiTimerModesMatchPNGFramesIncludingMixedWalkingDigits() throws {
        try assertTimerModesMatchPNGFrames(breed: .corgi, fontToken: "DogCorgi")
    }

    @MainActor
    private func assertTimerModesMatchPNGFrames(breed: PetBreed, fontToken: String) throws {
        try registerTimerFonts()
        let modes: [(String, [PetPose])] = [
            ("Run", Array(repeating: .run, count: 10)),
            ("Walk", Array(repeating: .walk, count: 10)),
            ("Sleep", Array(repeating: .sleep, count: 10)),
            ("RunSleep", [.run, .run, .run, .run, .run, .run, .run, .sleep, .sleep, .sleep]),
            ("WalkSleep", [.walk, .walk, .walk, .walk, .walk, .walk, .walk, .sleep, .sleep, .sleep]),
            ("RunWalkSleep", [.run, .run, .run, .run, .walk, .walk, .walk, .sleep, .sleep, .sleep])
        ]
        for viewport in [CGSize(width: 36, height: 30), CGSize(width: 28, height: 25), CGSize(width: 84, height: 72)] {
            let family = viewport.width == 84 ? "PetIslandLockTimer" : "PetIslandTimer"
            for (mode, poses) in modes {
                for digit in 0...9 {
                    for direction in [PetDirection.left, .right] {
                        let glyph = PetTimerGlyphViewport(text: Text("1:00:\(digit)"),
                            fontName: family + fontToken + mode, viewport: viewport, direction: direction)
                        // Timer glyphs keep a two-beat cadence using the opposite
                        // contact poses from the corgi's four-frame foreground walk.
                        let step = poses[digit] == .sleep ? 0
                            : (breed == .corgi && poses[digit] == .walk ? (digit % 2) * 2 : digit % 2)
                        let artwork = PetArtwork(species: .dog, breed: breed, pose: poses[digit],
                            direction: direction, step: step,
                            animatesMotion: false, surface: viewport.width == 84 ? .standard : .dynamicIsland)
                            .frame(width: viewport.width, height: viewport.height)
                        let fontBounds = try renderedBounds(glyph)
                        let pngBounds = try renderedBounds(artwork)
                        let sample = "\(breed), \(mode), digit \(digit), \(viewport), \(direction)"
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
        XCTAssertEqual(settings.liveActivityBackgroundTransparency, 0)
    }

    func testLiveActivityColorSurvivesSettingsRoundTrip() throws {
        let color = PetColorSelection(red: 0.94, green: 0.87, blue: 0.76)
        let settings = AppSettings(appearance: .light, liveActivityBackgroundColor: color,
                                   liveActivityBackgroundTransparency: 0.65)
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
        XCTAssertNil(decoded.backgroundTransparency)
        XCTAssertEqual(decoded.appearance.transparency, 0)
        XCTAssertEqual(decoded.appearance.background, PetActivityAppearance.defaultBackground)
    }

    func testLiveActivityReactionsPreserveCustomBackground() throws {
        let color = PetColorSelection(red: 0.74, green: 0.68, blue: 0.88)
        let initial = PetSnapshot.initial(at: .now)
        let content = PetActivityAttributes.ContentState(snapshot: initial, lastInteraction: nil,
                                                        backgroundColor: color, backgroundTransparency: 0.7)
        let snapshots = PetLiveMotionSequence.snapshots(from: initial, action: .run, species: .lion)
        for snapshot in snapshots {
            let updated = content.updating(snapshot: snapshot, lastInteraction: "run")
            XCTAssertEqual(updated.backgroundColor, color)
            XCTAssertEqual(updated.backgroundTransparency, 0.7)
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

    func testActivityTransparencyUpdatePreservesPetSnapshotAndInteraction() throws {
        let snapshot = PetSnapshot(pose: .walk, position: 0.6, direction: .left, revision: 37, generatedAt: .now)
        let content = PetActivityAttributes.ContentState(snapshot: snapshot, lastInteraction: "play")
        for color in [PetColorSelection(red: 0.55, green: 0.55, blue: 0.55),
                      PetColorSelection(red: 0.95, green: 0.45, blue: 0.65)] {
            for transparency in [0.0, 0.35, 1.0] {
                let updated = content.updatingAppearance(color: color, transparency: transparency)
                let decoded = try JSONDecoder().decode(PetActivityAttributes.ContentState.self,
                                                       from: JSONEncoder().encode(updated))
                XCTAssertEqual(decoded.snapshot, snapshot)
                XCTAssertEqual(decoded.lastInteraction, "play")
                XCTAssertEqual(decoded.appearance.background, color)
                XCTAssertEqual(decoded.appearance.transparency, transparency)
            }
        }
    }

    func testActivityTransparencyBoundsAndAccessibilityKeepSavedChoice() throws {
        for (value, expected) in [(-4.0, 0.0), (0.35, 0.35), (8.0, 1.0)] {
            let data = Data("{\"liveActivityBackgroundTransparency\":\(value)}".utf8)
            let settings = try JSONDecoder().decode(AppSettings.self, from: data)
            XCTAssertEqual(settings.liveActivityBackgroundTransparency, expected)
        }
        for invalid in [Double.nan, .infinity, -.infinity] {
            let settings = AppSettings(liveActivityBackgroundTransparency: invalid)
            XCTAssertEqual(settings.liveActivityBackgroundTransparency, 0)
            XCTAssertNoThrow(try JSONEncoder().encode(settings))
        }
        let color = PetColorSelection(red: 0.95, green: 0.45, blue: 0.65)
        let saved = PetActivityAppearance(background: color, transparency: 0.8)
        let reduced = saved.respectingReducedTransparency(true)
        XCTAssertEqual(reduced.transparency, 0)
        XCTAssertEqual(reduced.background, color)
        XCTAssertNotNil(reduced.systemBackgroundTint)
        XCTAssertNil(saved.systemBackgroundTint)
        XCTAssertEqual(saved.respectingReducedTransparency(false).transparency, 0.8)
        XCTAssertEqual(saved.transparency, 0.8)
    }

    @MainActor
    func testActivityTransparencyOnlySavePersistsWithoutChangingColorOrSessionSettings() async throws {
        let store = InMemoryPetStore()
        let controller = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await controller.bootstrap()
        await controller.updateDynamicIslandSettings(mode: .runWalkSleep, durationMinutes: 120)
        let color = PetColorSelection(red: 0.55, green: 0.55, blue: 0.55)
        let initial = await controller.updateLiveActivityBackgroundColor(color)
        XCTAssertTrue(initial)
        let before = await store.load()
        let saved = await controller.updateLiveActivityBackgroundColor(color, transparency: 0.6)
        XCTAssertTrue(saved)
        let after = await store.load()
        var expected = before
        expected.settings.liveActivityBackgroundTransparency = 0.6
        XCTAssertEqual(after, expected)
        let reloaded = PetSessionController(store: store, arcadeStore: InMemoryArcadeStore())
        await reloaded.bootstrap()
        XCTAssertEqual(reloaded.settings.liveActivityBackgroundTransparency, 0.6)
        XCTAssertEqual(reloaded.settings.liveActivityBackgroundColor, color)
        let colorOnly = await reloaded.updateLiveActivityBackgroundColor(nil)
        XCTAssertTrue(colorOnly)
        XCTAssertEqual(reloaded.settings.liveActivityBackgroundTransparency, 0.6)
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
        let saved = await controller.updateLiveActivityBackgroundColor(previous, transparency: 0.65)
        XCTAssertTrue(saved)
        await store.setFailure(true)
        let reset = await controller.updateLiveActivityBackgroundColor(nil, transparency: 0)
        XCTAssertFalse(reset)
        XCTAssertEqual(controller.settings.liveActivityBackgroundColor, previous)
        XCTAssertEqual(controller.settings.liveActivityBackgroundTransparency, 0.65)
        let persisted = await store.load()
        XCTAssertEqual(persisted.settings.liveActivityBackgroundColor, previous)
        XCTAssertEqual(persisted.settings.liveActivityBackgroundTransparency, 0.65)
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
