import CoreGraphics
import XCTest
@testable import PetIsland

final class PetCozyBoxTests: XCTestCase {
    private let canvasSize = CGSize(width: 360, height: 236)
    private let frameDuration = 1.0 / 60

    @MainActor
    func testRepeatedVisitsIncludePeekingAndSleepingWithoutChangingPetIdentity() throws {
        let cat = makePet(species: .cat, breed: .classicCat)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        var poses = Set<PetPose>()
        for _ in 0..<16 {
            XCTAssertTrue(simulation.requestCatToBox(cat.id))
            XCTAssertTrue(advance(simulation, until: .resting))
            let inside = try XCTUnwrap(simulation.actors.first)
            XCTAssertEqual(inside.profile, cat)
            XCTAssertTrue(inside.pose == .idle || inside.pose == .sleep)
            poses.insert(inside.pose)
            simulation.pet(cat.id)
            XCTAssertTrue(advance(simulation, until: .empty))
        }
        XCTAssertEqual(poses, [.idle, .sleep])
    }

    @MainActor
    func testCompetingCatsCannotStealReservationDuringApproachRestOrExit() {
        let cats = PetBreed.available(for: .cat).map { makePet(species: .cat, breed: $0) }
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: cats, size: canvasSize, hasCozyBox: true)
        for expected in cats {
            XCTAssertTrue(simulation.requestCatToBox(expected.id))
            for phase: HabitatMotionSimulation.CozyBoxPhase in [.approaching, .inspecting, .entering, .resting, .exiting] {
                XCTAssertTrue(advance(simulation, until: phase))
                for challenger in cats {
                    XCTAssertFalse(simulation.requestCatToBox(challenger.id))
                    XCTAssertEqual(simulation.boxOccupantID, expected.id)
                }
            }
            XCTAssertTrue(advance(simulation, until: .empty))
            XCTAssertNil(simulation.boxOccupantID)
        }
    }

    @MainActor
    func testAutomaticVisitsReserveOnlyNearbyCatsAndKeepOneOwner() {
        let cats = PetBreed.available(for: .cat).map { makePet(species: .cat, breed: $0) }
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: cats, size: canvasSize, hasCozyBox: true)
        var visits = 0
        for _ in 0..<180 * 60 {
            let previousOwner = simulation.boxOccupantID
            let previousActors = simulation.actors
            simulation.advance(by: frameDuration)
            if let owner = simulation.boxOccupantID {
                if let previousOwner {
                    XCTAssertEqual(owner, previousOwner, "A queued arrival must not replace the current owner.")
                } else if let actor = previousActors.first(where: { $0.id == owner }) {
                    let distance = hypot(actor.position.x - simulation.boxPosition.x,
                                         actor.position.y - simulation.boxRenderDepth)
                    XCTAssertLessThanOrEqual(distance, 78 * 1.35 + 0.01)
                    visits += 1
                }
            }
        }
        XCTAssertGreaterThan(visits, 1)
    }

    @MainActor
    func testAllFourCatBreedsCompleteBoxVisitWithContinuousGroundedMotion() throws {
        for breed in PetBreed.available(for: .cat) {
            let cat = makePet(species: .cat, breed: breed)
            let simulation = HabitatMotionSimulation()
            simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
            XCTAssertTrue(simulation.requestCatToBox(cat.id), "\(breed)")
            var phases: Set<HabitatMotionSimulation.CozyBoxPhase> = [.approaching]
            var previous = try XCTUnwrap(simulation.actors.first)
            var completed = false

            for _ in 0..<3_600 {
                simulation.advance(by: frameDuration)
                let actor = try XCTUnwrap(simulation.actors.first)
                phases.insert(simulation.boxPhase)
                XCTAssertEqual(actor.profile, cat, "A box must not substitute or modify the cat artwork identity.")
                XCTAssertTrue(actor.position.x.isFinite && actor.position.y.isFinite && actor.visualOffsetY.isFinite)
                XCTAssertEqual(abs(actor.facing), 1)
                let distance = hypot(actor.position.x - previous.position.x,
                                     actor.position.y + actor.visualOffsetY - previous.position.y - previous.visualOffsetY)
                XCTAssertLessThan(distance, 3, "\(breed): a pose transition must not teleport the cat.")
                let clip = PetAnimationLibrary.naturalClip(for: .cat, breed: breed, pose: actor.pose)
                XCTAssertTrue(clip.frames.indices.contains(actor.step), "\(breed): invalid \(actor.pose) frame")
                if simulation.boxPhase == .resting {
                    XCTAssertEqual(actor.pose, simulation.boxRestPose)
                    XCTAssertEqual(actor.position.x, simulation.boxPosition.x, accuracy: 0.001)
                    XCTAssertEqual(actor.position.y + 78 * 0.31, simulation.boxPosition.y, accuracy: 0.001)
                    XCTAssertEqual(actor.visualOffsetY, -simulation.boxSize.height * (simulation.boxRestPose == .sleep ? 0.27 : 0.04), accuracy: 0.001)
                }
                previous = actor
                if simulation.boxPhase == .empty {
                    completed = true
                    break
                }
                XCTAssertEqual(simulation.boxOccupantID, cat.id)
            }

            XCTAssertTrue(completed, "\(breed): the cat must leave the box again.")
            XCTAssertEqual(phases, [.approaching, .inspecting, .entering, .resting, .exiting, .empty])
            XCTAssertNil(simulation.boxOccupantID)
        }
    }

    @MainActor
    func testApproachGaitAdvancesWithDistanceRatherThanElapsedTime() throws {
        let cat = makePet(species: .cat, breed: .classicCat)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        XCTAssertTrue(simulation.requestCatToBox())
        var samples = 0

        for _ in 0..<600 {
            let before = try XCTUnwrap(simulation.actors.first)
            let phase = simulation.boxPhase
            simulation.advance(by: frameDuration)
            let after = try XCTUnwrap(simulation.actors.first)
            if phase == .approaching && simulation.boxPhase == .approaching {
                let distance = hypot(after.position.x - before.position.x, after.position.y - before.position.y)
                XCTAssertEqual(after.gaitPhase - before.gaitPhase, distance / (78 * 0.38), accuracy: 0.000_001)
                if distance > 0.01 { samples += 1 }
            }
            if simulation.boxPhase == .inspecting { break }
        }

        XCTAssertGreaterThan(samples, 30)
        XCTAssertEqual(simulation.boxPhase, .inspecting)
    }

    @MainActor
    func testBoxChoosesNearestCatAndAllowsOnlyOneReservation() {
        let farCat = makePet(species: .cat, breed: .classicCat)
        let nearCat = makePet(species: .cat, breed: .maineCoon)
        let dog = makePet(species: .dog, breed: .cardigan)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [farCat, nearCat, dog], size: canvasSize, hasCozyBox: true)

        XCTAssertFalse(simulation.requestCatToBox(dog.id))
        XCTAssertFalse(simulation.requestCatToBox(UUID()))
        XCTAssertTrue(simulation.requestCatToBox())
        XCTAssertEqual(simulation.boxOccupantID, nearCat.id)
        XCTAssertTrue(simulation.isBoxOccupied)
        XCTAssertFalse(simulation.requestCatToBox(farCat.id))
        XCTAssertFalse(simulation.requestCatToBox(nearCat.id))
        XCTAssertEqual(simulation.boxOccupantID, nearCat.id)
    }

    @MainActor
    func testOtherSpeciesKeepExactlyTheSameMotionWhenBoxIsEnabled() {
        let pets = [
            makePet(species: .dog, breed: .cardigan),
            makePet(species: .fox, breed: .redFox),
            makePet(species: .parrot, breed: .classicParrot),
            makePet(species: .penguin, breed: .classicPenguin),
            makePet(species: .lion, breed: .lionCub)
        ]
        let original = HabitatMotionSimulation()
        let furnished = HabitatMotionSimulation()
        original.configure(pets: pets, size: canvasSize)
        furnished.configure(pets: pets, size: canvasSize, hasCozyBox: true)

        for pet in pets { XCTAssertFalse(furnished.requestCatToBox(pet.id)) }
        for _ in 0..<3_000 {
            original.advance(by: frameDuration)
            furnished.advance(by: frameDuration)
            XCTAssertEqual(furnished.actors, original.actors)
        }

        XCTAssertNil(furnished.boxOccupantID)
        XCTAssertEqual(furnished.boxPhase, .empty)
    }

    @MainActor
    func testDisablingUnusedBoxLeavesCatSimulationExactlyUnchanged() {
        let cat = makePet(species: .cat, breed: .siamese)
        let original = HabitatMotionSimulation()
        let toggled = HabitatMotionSimulation()
        original.configure(pets: [cat], size: canvasSize)
        toggled.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        toggled.configure(pets: [cat], size: canvasSize, hasCozyBox: false)

        XCTAssertFalse(toggled.requestCatToBox())
        for _ in 0..<2_400 {
            original.advance(by: frameDuration)
            toggled.advance(by: frameDuration)
            XCTAssertEqual(toggled.actors, original.actors)
        }
        XCTAssertNil(toggled.boxOccupantID)
    }

    @MainActor
    func testCatMayVisitBoxByItselfWithinAmbientWindow() {
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [makePet(species: .cat, breed: .britishShorthair)],
                             size: canvasSize, hasCozyBox: true)

        for _ in 0..<14 * 60 { simulation.advance(by: frameDuration) }
        XCTAssertNil(simulation.boxOccupantID)
        for _ in 0..<90 * 60 {
            simulation.advance(by: frameDuration)
            if simulation.isBoxOccupied { break }
        }

        XCTAssertTrue(simulation.isBoxOccupied)
        XCTAssertEqual(simulation.boxPhase, .approaching)
    }

    @MainActor
    func testRemovingWalkingCatClearsBoxWithoutChangingAnotherResident() throws {
        let cat = makePet(species: .cat, breed: .maineCoon)
        let dog = makePet(species: .dog, breed: .corgi)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat, dog], size: canvasSize, hasCozyBox: true)
        XCTAssertTrue(simulation.requestCatToBox(cat.id))
        let dogBefore = try XCTUnwrap(simulation.actors.first { $0.id == dog.id })

        // Discovery departure removes a resident from the foreground cast.
        simulation.configure(pets: [dog], size: canvasSize, hasCozyBox: true)

        XCTAssertEqual(simulation.actors, [dogBefore])
        XCTAssertNil(simulation.boxOccupantID)
        XCTAssertEqual(simulation.boxPhase, .empty)
        XCTAssertFalse(simulation.requestCatToBox())
        simulation.configure(pets: [], size: canvasSize, hasCozyBox: true)
        simulation.start(reduceMotion: false, active: true)
        XCTAssertFalse(simulation.isRunning)
    }

    @MainActor
    func testRemovingBoxDuringEntryPreservesTheDrawnPosition() throws {
        let cat = makePet(species: .cat, breed: .britishShorthair)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        XCTAssertTrue(simulation.requestCatToBox())
        XCTAssertTrue(advance(simulation, until: .entering))
        for _ in 0..<30 { simulation.advance(by: frameDuration) }
        let before = try XCTUnwrap(simulation.actors.first)
        XCTAssertLessThan(before.visualOffsetY, -1)

        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: false)

        let after = try XCTUnwrap(simulation.actors.first)
        XCTAssertEqual(after.position.x, before.position.x, accuracy: 0.001)
        XCTAssertEqual(after.position.y, before.position.y, accuracy: 0.001)
        XCTAssertEqual(after.visualOffsetY, before.visualOffsetY, accuracy: 0.001)
        XCTAssertNil(simulation.boxOccupantID)
        XCTAssertEqual(simulation.boxPhase, .empty)
        XCTAssertEqual(after.pose, .idle)
        var previous = after
        for _ in 0..<60 {
            simulation.advance(by: frameDuration)
            let actor = try XCTUnwrap(simulation.actors.first)
            XCTAssertLessThan(abs(actor.visualOffsetY - previous.visualOffsetY), 2)
            previous = actor
        }
        XCTAssertEqual(previous.visualOffsetY, 0)
    }

    @MainActor
    func testPettingCatInsideBoxStartsContinuousExitAndReleasesReservation() throws {
        let cat = makePet(species: .cat, breed: .classicCat)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        XCTAssertTrue(simulation.requestCatToBox())
        XCTAssertTrue(advance(simulation, until: .entering))
        for _ in 0..<25 { simulation.advance(by: frameDuration) }
        var previous = try XCTUnwrap(simulation.actors.first)

        simulation.pet(cat.id)

        XCTAssertEqual(simulation.boxPhase, .exiting)
        XCTAssertEqual(simulation.actors.first?.position, previous.position)
        XCTAssertEqual(simulation.actors.first?.visualOffsetY, previous.visualOffsetY)
        for _ in 0..<300 {
            simulation.advance(by: frameDuration)
            let actor = try XCTUnwrap(simulation.actors.first)
            XCTAssertLessThan(hypot(actor.position.x - previous.position.x,
                                    actor.position.y + actor.visualOffsetY - previous.position.y - previous.visualOffsetY), 3)
            previous = actor
            if simulation.boxPhase == .empty { break }
        }

        XCTAssertNil(simulation.boxOccupantID)
        XCTAssertEqual(simulation.boxPhase, .empty)
        XCTAssertEqual(previous.visualOffsetY, 0)
    }

    @MainActor
    func testResizeRetargetsEveryVisitPhaseWithoutInvalidCoordinates() throws {
        for phase: HabitatMotionSimulation.CozyBoxPhase in [.approaching, .inspecting, .entering, .resting, .exiting] {
            let cat = makePet(species: .cat, breed: .siamese)
            let simulation = HabitatMotionSimulation()
            simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
            XCTAssertTrue(simulation.requestCatToBox())
            XCTAssertTrue(advance(simulation, until: phase))
            let newSize = CGSize(width: 420, height: 280)

            simulation.configure(pets: [cat], size: newSize, hasCozyBox: true)

            var previous = try XCTUnwrap(simulation.actors.first)
            XCTAssertTrue(simulation.boxPosition.x.isFinite && simulation.boxPosition.y.isFinite)
            for _ in 0..<10 {
                simulation.advance(by: frameDuration)
                let actor = try XCTUnwrap(simulation.actors.first)
                XCTAssertTrue(actor.position.x.isFinite && actor.position.y.isFinite && actor.visualOffsetY.isFinite)
                XCTAssertGreaterThanOrEqual(actor.position.x, 0)
                XCTAssertLessThanOrEqual(actor.position.x, newSize.width)
                XCTAssertGreaterThanOrEqual(actor.position.y, 0)
                XCTAssertLessThanOrEqual(actor.position.y, newSize.height)
                XCTAssertLessThan(hypot(actor.position.x - previous.position.x,
                                        actor.position.y + actor.visualOffsetY - previous.position.y - previous.visualOffsetY), 4)
                previous = actor
            }
            XCTAssertEqual(simulation.boxOccupantID, cat.id)
        }
    }

    @MainActor
    func testReduceMotionUsesStaticBoxPoseWithoutStartingDisplayLink() throws {
        let cat = makePet(species: .cat, breed: .maineCoon)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        simulation.start(reduceMotion: true, active: true)

        XCTAssertTrue(simulation.requestCatToBox())
        XCTAssertEqual(simulation.boxPhase, .resting)
        XCTAssertEqual(simulation.actors.first?.pose, simulation.boxRestPose)
        let inside = try XCTUnwrap(simulation.actors.first)
        XCTAssertEqual(inside.visualOffsetY, -simulation.boxSize.height * (simulation.boxRestPose == .sleep ? 0.27 : 0.04), accuracy: 0.001)
        XCTAssertFalse(simulation.isRunning)
        let stationary = simulation.actors
        simulation.advance(by: 30)
        XCTAssertEqual(simulation.actors, stationary)
        simulation.pet(cat.id)
        let outside = try XCTUnwrap(simulation.actors.first)
        XCTAssertNil(simulation.boxOccupantID)
        XCTAssertEqual(outside.visualOffsetY, 0)
        XCTAssertGreaterThan(abs(outside.position.x - simulation.boxPosition.x), 40,
                             "A static exit must free the box floor for the next cat.")
        XCTAssertFalse(simulation.isRunning)
        simulation.start(reduceMotion: false, active: false)
        XCTAssertFalse(simulation.isRunning)
    }

    @MainActor
    func testInvalidGeometryAndTimeDoNotCorruptActiveVisit() {
        let cat = makePet(species: .cat, breed: .classicCat)
        let simulation = HabitatMotionSimulation()
        simulation.configure(pets: [cat], size: canvasSize, hasCozyBox: true)
        XCTAssertTrue(simulation.requestCatToBox())
        let before = simulation.actors

        simulation.configure(pets: [cat], size: CGSize(width: CGFloat.nan, height: 236), hasCozyBox: true)
        simulation.configure(pets: [cat], size: canvasSize, petScale: .infinity, hasCozyBox: true)
        for delta in [Double.nan, .infinity, -.infinity, -1, 0] { simulation.advance(by: delta) }

        XCTAssertEqual(simulation.actors, before)
        XCTAssertEqual(simulation.size, canvasSize)
        XCTAssertEqual(simulation.boxOccupantID, cat.id)
    }

    @MainActor
    private func advance(_ simulation: HabitatMotionSimulation,
                         until phase: HabitatMotionSimulation.CozyBoxPhase) -> Bool {
        if simulation.boxPhase == phase { return true }
        for _ in 0..<3_600 {
            simulation.advance(by: frameDuration)
            if simulation.boxPhase == phase { return true }
        }
        return false
    }

    private func makePet(species: PetSpecies, breed: PetBreed) -> PetProfile {
        PetProfile(id: UUID(), name: breed.rawValue, species: species, coat: .sunrise,
                   createdAt: Date(timeIntervalSince1970: 1_000), breed: breed)
    }
}
