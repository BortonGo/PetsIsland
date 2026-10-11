import CoreGraphics
import XCTest
@testable import PetIsland

final class PetEncounterTests: XCTestCase {
    private let canvas = CGSize(width: 360, height: 236)
    private let dt = 1.0 / 60

    private func pet(_ index: Int, species: PetSpecies = .cat, breed: PetBreed? = nil) -> PetProfile {
        PetProfile(id: UUID(uuidString: String(format: "EC000000-0000-0000-0000-%012d", index))!,
                   name: "Pet \(index)", species: species, coat: .sunrise, createdAt: .distantPast,
                   breed: breed, outfit: PetOutfit(headwear: .knitHat))
    }

    @MainActor private func advance(_ simulation: HabitatMotionSimulation,
                                    until phase: HabitatMotionSimulation.EncounterPhase?) -> Bool {
        for _ in 0..<1_500 {
            if simulation.encounter?.phase == phase { return true }
            simulation.advance(by: dt)
        }
        return simulation.encounter?.phase == phase
    }

    @MainActor
    func testAllBreedsMeetFaceEachOtherAndFinishWithoutChangingArtworkOrGaits() throws {
        for species in PetSpecies.allCases {
            for breed in PetBreed.available(for: species) {
                for fps in [30, 60] {
                    let pets = [pet(1, species: species, breed: breed), pet(2, species: .dog, breed: .corgi)]
                    let simulation = HabitatMotionSimulation()
                    simulation.configure(pets: pets, size: canvas)
                    let before = simulation.actors
                    XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id), "\(breed)")
                    XCTAssertEqual(simulation.actors.map(\.position), before.map(\.position))
                    var phases = Set<HabitatMotionSimulation.EncounterPhase>()
                    var totalDistance = 0.0
                    for _ in 0..<(fps * 25) {
                        guard let visit = simulation.encounter else { break }
                        phases.insert(visit.phase)
                        let previous = simulation.actors
                        simulation.advance(by: 1 / Double(fps))
                        for (old, actor) in zip(previous, simulation.actors) {
                            let distance = hypot(actor.position.x - old.position.x, actor.position.y - old.position.y)
                            totalDistance += distance
                            XCTAssertLessThanOrEqual(distance, 28 / Double(fps) + 0.001, "No teleport: \(breed)")
                            XCTAssertEqual(actor.profile, old.profile)
                            XCTAssertEqual(actor.visualOffsetY, 0)
                            XCTAssertEqual(abs(actor.facing), 1)
                            let clip = PetAnimationLibrary.naturalClip(for: actor.profile.species,
                                breed: actor.profile.resolvedBreed, pose: actor.pose)
                            XCTAssertTrue(clip.frames.indices.contains(actor.step), "\(breed) / \(actor.pose)")
                            if actor.pose == .walk || actor.pose == .fly, distance > 0 {
                                let stride = 78 * PetAnimationLibrary.enclosureStrideRatio(
                                    for: actor.profile.species, breed: actor.profile.resolvedBreed, pose: actor.pose)
                                XCTAssertEqual(actor.gaitPhase - old.gaitPhase, distance / stride, accuracy: 0.000001)
                            }
                        }
                        if simulation.encounter?.phase == .greeting {
                            XCTAssertEqual(simulation.actors[0].facing, 1)
                            XCTAssertEqual(simulation.actors[1].facing, -1)
                            XCTAssertEqual(simulation.actors[0].position.y, simulation.actors[1].position.y, accuracy: 0.2)
                            XCTAssertGreaterThan(simulation.actors[1].position.x - simulation.actors[0].position.x, 60)
                        }
                    }
                    XCTAssertEqual(phases, Set(HabitatMotionSimulation.EncounterPhase.allCases), "\(breed) / \(fps)")
                    XCTAssertNil(simulation.encounter)
                    XCTAssertGreaterThan(totalDistance, 10)
                    XCTAssertEqual(simulation.actors.map(\.profile), pets)
                    XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[1].id), "Pair needs a break")
                }
            }
        }
    }

    @MainActor
    func testPairReservationIsAtomicAndCannotBeStolenByAmbientFurniture() throws {
        let pets = [pet(1), pet(2), pet(3, species: .dog)]
        let simulation = HabitatMotionSimulation()
        let layout = [HabitatFurniturePlacement(item: .playBall, slot: .right)]
        simulation.configure(pets: Array(pets.prefix(2)), size: canvas, furniture: layout)
        XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        for phase in HabitatMotionSimulation.EncounterPhase.allCases {
            XCTAssertTrue(advance(simulation, until: phase))
            let reserved = simulation.encounter
            XCTAssertFalse(simulation.requestEncounter(between: pets[1].id, and: pets[0].id))
            XCTAssertFalse(simulation.requestEncounter(between: pets[1].id, and: pets[2].id))
            for participant in pets.prefix(2) {
                XCTAssertFalse(simulation.requestFurniture(.right, petID: participant.id, interruptsEncounter: false))
            }
            XCTAssertEqual(simulation.encounter, reserved)
            XCTAssertTrue(simulation.furnitureVisits.isEmpty)
        }
    }

    @MainActor
    func testManualFurnitureInvitationReleasesBothParticipantsWithoutJumping() {
        for phase in HabitatMotionSimulation.EncounterPhase.allCases {
            for item in [HabitatItemKind.cozyBox, .playBall] {
                let pets = [pet(1), pet(2)]
                let simulation = HabitatMotionSimulation()
                simulation.configure(pets: pets, size: canvas, furniture: [.init(item: item, slot: .right)])
                XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
                XCTAssertTrue(advance(simulation, until: phase))
                let positions = simulation.actors.map(\.position)
                XCTAssertFalse(simulation.requestFurniture(.right, petID: pets[0].id, interruptsEncounter: false))
                XCTAssertTrue(simulation.requestFurniture(.right, petID: pets[0].id))
                XCTAssertNil(simulation.encounter)
                XCTAssertEqual(simulation.actors.map(\.position), positions)
                XCTAssertEqual(simulation.actors[1].pose, .idle)
                XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
            }
        }
    }

    @MainActor
    func testOccupiedFurnitureSleepingAndTiredPetsCannotBeRecruited() {
        let pets = [pet(1), pet(2)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas, hasCozyBox: true)
        XCTAssertTrue(simulation.requestCatToBox(pets[0].id))
        XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        let tired = HabitatMotionSimulation()
        tired.configure(pets: pets, size: canvas, vitals: [pets[0].id: PetVitals(fullness: 1, happiness: 1, energy: 0.1)])
        XCTAssertFalse(tired.requestEncounter(between: pets[0].id, and: pets[1].id))
        tired.configure(pets: pets, size: canvas)
        tired.pet(pets[1].id)
        XCTAssertFalse(tired.requestEncounter(between: pets[0].id, and: pets[1].id))
        let sleeping = HabitatMotionSimulation()
        sleeping.configure(pets: [pets[0]], size: canvas)
        for _ in 0..<18_000 {
            sleeping.advance(by: dt)
            if sleeping.actors[0].pose == .sleep { break }
        }
        XCTAssertEqual(sleeping.actors[0].pose, .sleep)
        sleeping.configure(pets: pets, size: canvas)
        XCTAssertFalse(sleeping.requestEncounter(between: pets[0].id, and: pets[1].id))
    }

    @MainActor
    func testPettingEitherParticipantDuringEveryPhaseCancelsOnlyTheEncounter() {
        for phase in HabitatMotionSimulation.EncounterPhase.allCases {
            for index in 0...1 {
                let pets = [pet(1), pet(2)]
                let simulation = HabitatMotionSimulation()
                simulation.configure(pets: pets, size: canvas)
                XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
                XCTAssertTrue(advance(simulation, until: phase))
                let positions = simulation.actors.map(\.position)
                simulation.pet(pets[index].id)
                XCTAssertNil(simulation.encounter)
                XCTAssertEqual(simulation.actors.map(\.position), positions)
                XCTAssertEqual(simulation.actors[index].pose, .play)
                XCTAssertEqual(simulation.actors[1 - index].pose, .idle)
                XCTAssertEqual(simulation.actors[index].affection, 1.5)
                XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
            }
        }
    }

    @MainActor
    func testDepartureResizeAndFurnitureEditsReleaseReservations() {
        for phase in HabitatMotionSimulation.EncounterPhase.allCases {
            for mutation in 0..<4 {
                let pets = [pet(1), pet(2)]
                let simulation = HabitatMotionSimulation()
                simulation.configure(pets: pets, size: canvas)
                XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
                XCTAssertTrue(advance(simulation, until: phase))
                let before = simulation.actors
                switch mutation {
                case 0: simulation.configure(pets: [pets[0]], size: canvas)
                case 1: simulation.configure(pets: pets, size: CGSize(width: 280, height: 220), petScale: 1.2)
                case 2: simulation.configure(pets: pets, size: canvas, hasCozyBox: true)
                default: simulation.configure(pets: [], size: canvas)
                }
                XCTAssertNil(simulation.encounter)
                if mutation == 0 || mutation == 2 {
                    XCTAssertEqual(simulation.actors[0].position, before[0].position)
                    XCTAssertEqual(simulation.actors[0].gaitPhase, before[0].gaitPhase)
                }
                for _ in 0..<60 { simulation.advance(by: dt) }
                XCTAssertTrue(simulation.actors.allSatisfy { $0.position.x.isFinite && $0.position.y.isFinite })
                XCTAssertEqual(simulation.actors.count, mutation == 0 ? 1 : (mutation == 3 ? 0 : 2))
            }
        }
    }

    @MainActor
    func testRenamingAndUnchangedConfigurationDoNotRestartTheMeeting() {
        var pets = [pet(1), pet(2)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas)
        XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        for _ in 0..<30 { simulation.advance(by: dt) }
        let visit = simulation.encounter
        let before = simulation.actors
        pets[0].name = "Renamed"
        simulation.configure(pets: pets, size: canvas)
        XCTAssertEqual(simulation.encounter, visit)
        XCTAssertEqual(simulation.actors.map(\.position), before.map(\.position))
        XCTAssertEqual(simulation.actors.map(\.gaitPhase), before.map(\.gaitPhase))
        XCTAssertEqual(simulation.actors[0].profile.name, "Renamed")
    }

    @MainActor
    func testReduceMotionCancelsTheMeetingWithoutMovingEitherPet() {
        for phase in HabitatMotionSimulation.EncounterPhase.allCases {
            let pets = [pet(1), pet(2)]
            let simulation = HabitatMotionSimulation()
            simulation.configure(pets: pets, size: canvas)
            XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
            XCTAssertTrue(advance(simulation, until: phase))
            let positions = simulation.actors.map(\.position)
            simulation.start(reduceMotion: true, active: true)
            XCTAssertFalse(simulation.isRunning)
            XCTAssertNil(simulation.encounter)
            XCTAssertEqual(simulation.actors.map(\.position), positions)
            let still = simulation.actors
            for _ in 0..<300 { simulation.advance(by: dt) }
            XCTAssertEqual(simulation.actors, still)
            XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        }
    }

    @MainActor
    func testBackgroundPauseAndPowerChangesPreserveEncounter() async throws {
        let pets = [pet(1), pet(2)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas)
        XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        simulation.start(reduceMotion: false, active: true)
        simulation.start(reduceMotion: false, active: false)
        let before = simulation.actors, visit = simulation.encounter
        simulation.setPowerPolicy(.constrained)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(simulation.isRunning)
        XCTAssertEqual(simulation.actors, before)
        XCTAssertEqual(simulation.encounter, visit)
        simulation.start(reduceMotion: false, active: true, powerPolicy: .constrained)
        defer { simulation.stop() }
        XCTAssertTrue(simulation.isRunning)
        XCTAssertEqual(simulation.encounter, visit)
        XCTAssertEqual(simulation.preferredFramesPerSecond, 30)
    }

    @MainActor
    func testRestTimerDoesNotPublishIdenticalPictures() throws {
        let pets = [pet(1), pet(2)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas)
        XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        XCTAssertTrue(advance(simulation, until: .resting))
        let elapsed = try XCTUnwrap(simulation.encounter?.elapsed)
        var publications = 0, visibleChanges = 0
        let observation = simulation.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }
        for _ in 0..<120 {
            let before = simulation.actors
            simulation.advance(by: dt)
            if !before.elementsEqual(simulation.actors, by: { $0.hasSameAppearance(as: $1) }) { visibleChanges += 1 }
        }
        XCTAssertEqual(try XCTUnwrap(simulation.encounter?.elapsed), elapsed + 2, accuracy: 0.000001)
        XCTAssertEqual(publications, visibleChanges)
        XCTAssertLessThan(publications, 30)
    }

    @MainActor
    func testAutomaticMeetingsAreInfrequentAndAlsoLeaveTimeForFurniture() {
        let pets = [pet(1), pet(2, species: .dog, breed: .corgi)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas, furniture: [.init(item: .playBall, slot: .right)])
        var meetings = 0, greetings = 0, usedFurniture = false, wasMeeting = false, wasGreeting = false
        for _ in 0..<(180 * 60) {
            simulation.advance(by: dt)
            if simulation.encounter != nil && !wasMeeting { meetings += 1 }
            if simulation.encounter?.phase == .greeting && !wasGreeting { greetings += 1 }
            wasMeeting = simulation.encounter != nil
            wasGreeting = simulation.encounter?.phase == .greeting
            usedFurniture = usedFurniture || !simulation.furnitureVisits.isEmpty
            if let visit = simulation.encounter {
                XCTAssertFalse(simulation.furnitureVisits.values.contains { visit.contains($0.petID) })
                XCTAssertFalse(simulation.boxOccupantID.map(visit.contains) ?? false)
            }
        }
        XCTAssertGreaterThan(greetings, 0)
        XCTAssertLessThanOrEqual(meetings, 6)
        XCTAssertTrue(usedFurniture)
    }

    @MainActor
    func testCrowdedMeetingCannotCutThroughAnotherResident() {
        let pets = [pet(1), pet(2), pet(3)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: CGSize(width: 360, height: 155))
        let before = simulation.actors
        XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[2].id))
        XCTAssertEqual(simulation.actors, before)
        XCTAssertNil(simulation.encounter)
    }

    @MainActor
    func testNewArrivalBlockingThePathCancelsRatherThanTrappingThePair() {
        let pets = [pet(1), pet(2)]
        let visitor = pet(3)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas)
        XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        let position = simulation.actors[0].position
        simulation.configure(pets: [visitor] + pets, size: canvas)
        simulation.pet(visitor.id)
        for _ in 0..<90 { simulation.advance(by: dt) }
        XCTAssertNil(simulation.encounter)
        XCTAssertEqual(simulation.actors.first { $0.id == pets[0].id }?.position, position)
        XCTAssertEqual(simulation.actors.map(\.profile), [visitor] + pets)
    }

    @MainActor
    func testSmallAndFullEnclosuresStayBoundedWithOnePairAndNoSharedReservations() {
        for size in [CGSize(width: 280, height: 210), canvas, CGSize(width: 600, height: 300)] {
            let pets = PetSpecies.allCases.enumerated().map { pet($0.offset + 1, species: $0.element) }
            let simulation = HabitatMotionSimulation()
            simulation.configure(pets: pets, size: size, petScale: 1.2, furniture: [
                .init(item: .cozyBox, slot: .left), .init(item: .softBed, slot: .right), .init(item: .birdPerch, slot: .perch)
            ])
            var completedMeetings = 0, wasResting = false
            for _ in 0..<14_400 {
                let before = simulation.actors
                simulation.advance(by: dt)
                if wasResting, simulation.encounter == nil { completedMeetings += 1 }
                wasResting = simulation.encounter?.phase == .resting
                if let visit = simulation.encounter {
                    XCTAssertNotEqual(visit.leftID, visit.rightID)
                    XCTAssertEqual(simulation.actors.filter { visit.contains($0.id) }.count, 2)
                    XCTAssertFalse(simulation.furnitureVisits.values.contains { visit.contains($0.petID) })
                    XCTAssertFalse(simulation.boxOccupantID.map(visit.contains) ?? false)
                }
                for (old, actor) in zip(before, simulation.actors) {
                    XCTAssertEqual(old.profile, actor.profile)
                    XCTAssertTrue(actor.position.x.isFinite && actor.position.y.isFinite)
                    XCTAssertTrue((0...size.width).contains(actor.position.x))
                    XCTAssertTrue((0...size.height).contains(actor.position.y + actor.visualOffsetY))
                    XCTAssertLessThan(hypot(actor.position.x - old.position.x, actor.position.y - old.position.y), 3)
                }
            }
            // Dense small scenes may reasonably defer social visits, never force them.
            if size.width == 600 { XCTAssertGreaterThan(completedMeetings, 0) }
        }
    }

    @MainActor
    func testInvalidTimeGeometryAndParticipantsDoNotMutateTheSimulation() {
        let pets = [pet(1), pet(2)]
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: pets, size: canvas)
        XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: pets[0].id))
        XCTAssertFalse(simulation.requestEncounter(between: pets[0].id, and: UUID()))
        XCTAssertTrue(simulation.requestEncounter(between: pets[0].id, and: pets[1].id))
        let before = simulation.actors, encounter = simulation.encounter
        simulation.configure(pets: pets, size: CGSize(width: CGFloat.nan, height: 236))
        for delta in [Double.nan, .infinity, -1, 0] { simulation.advance(by: delta) }
        XCTAssertEqual(simulation.actors, before)
        XCTAssertEqual(simulation.encounter, encounter)
    }
}
