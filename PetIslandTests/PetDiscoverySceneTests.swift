import XCTest
@testable import PetIsland

final class PetDiscoverySceneTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func walk(_ route: PetWalkRoute, reversed: Bool = false) -> PetDiscoveryWalk {
        PetDiscoveryWalk(id: UUID(uuidString: reversed ? "02000000-0000-0000-0000-000000000001" : "01000000-0000-0000-0000-000000000001")!,
                         pet: .starter, route: route, startedAt: start,
                         endsAt: start.addingTimeInterval(route.duration), discovery: route.discoveryIDs[0])!
    }

    func testReopeningSavedWalkRestoresSamePositionAndBehavior() throws {
        for route in PetWalkRoute.allCases {
            let original = walk(route)
            let decoded = try JSONDecoder().decode(PetDiscoveryWalk.self, from: JSONEncoder().encode(original))
            let first = PetDiscoveryScenePlan(walk: original), reopened = PetDiscoveryScenePlan(walk: decoded)
            for seconds in [0.0, 10, 22.7, 59.99, 355, route.duration - 6, route.duration + 900] {
                let date = start.addingTimeInterval(seconds)
                XCTAssertEqual(first.frame(at: date), reopened.frame(at: date))
            }
        }
    }

    func testPetVisitsEveryRouteLandmarkAndStopsAtItsCoordinates() {
        for route in PetWalkRoute.allCases {
            for reversed in [false, true] {
                let plan = PetDiscoveryScenePlan(walk: walk(route, reversed: reversed))
                var visited: [PetDiscoveryScenePlan.Activity] = []
                for second in [10.0, 25, 40, 55] {
                    let frame = plan.frame(at: start.addingTimeInterval(second))
                    XCTAssertFalse(frame.isMoving)
                    let later = plan.frame(at: start.addingTimeInterval(second + 3))
                    XCTAssertEqual(frame.position, later.position)
                    if let stop = plan.stops.first(where: { $0.activity == frame.activity }) {
                        XCTAssertEqual(frame.position, stop.point)
                        XCTAssertEqual(frame.direction, stop.facing)
                        visited.append(frame.activity)
                    } else { XCTAssertEqual(frame.activity, .lookingAround) }
                }
                XCTAssertEqual(visited.count, 3)
                XCTAssertTrue(plan.stops.allSatisfy { visited.contains($0.activity) })
            }
        }
    }

    func testMovementNeverTeleportsAtStopsTurnsOrCycleSeams() {
        for route in PetWalkRoute.allCases {
            for reversed in [false, true] {
                let plan = PetDiscoveryScenePlan(walk: walk(route, reversed: reversed))
                var previous = plan.frame(at: start).position
                for tick in 1...2_400 {
                    let frame = plan.frame(at: start.addingTimeInterval(Double(tick) / 20))
                    XCTAssertLessThan(hypot(frame.position.x - previous.x, frame.position.y - previous.y), 0.006)
                    XCTAssertTrue((0.15...0.77).contains(frame.position.x))
                    XCTAssertTrue((0.66...0.89).contains(frame.position.y))
                    if route == .shore {
                        XCTAssertGreaterThanOrEqual(frame.position.y, 0.74, "Keep grounded pets on the dry side of the shoreline")
                    }
                    previous = frame.position
                }
            }
        }
    }

    func testFinalReturnIsContinuousAndPetLeavesSceneExactlyAtDeadline() {
        for route in PetWalkRoute.allCases {
            let savedWalk = walk(route), plan = PetDiscoveryScenePlan(walk: walk(route))
            let before = plan.frame(at: savedWalk.endsAt.addingTimeInterval(-12.001))
            let transition = plan.frame(at: savedWalk.endsAt.addingTimeInterval(-12))
            XCTAssertLessThan(hypot(before.position.x - transition.position.x, before.position.y - transition.position.y), 0.001)
            XCTAssertEqual(transition.activity, .headingHome)
            let last = plan.frame(at: savedWalk.endsAt.addingTimeInterval(-0.001))
            XCTAssertFalse(last.isHome)
            XCTAssertEqual(last.position.x, PetDiscoveryScenePlan.home.x, accuracy: 0.001)
            XCTAssertEqual(last.position.y, PetDiscoveryScenePlan.home.y, accuracy: 0.001)
            let returned = plan.frame(at: savedWalk.endsAt)
            XCTAssertTrue(returned.isHome)
            XCTAssertFalse(returned.isMoving)
            XCTAssertEqual(returned, plan.frame(at: savedWalk.endsAt.addingTimeInterval(86_400)))
        }
    }

    func testFrameSamplingDoesNotChangeWalkTimingFindOrPersistence() throws {
        var state = PetDiscoveriesState()
        state.startWalk(pet: .starter, route: .grove, at: start)
        let before = state
        let savedWalk = try XCTUnwrap(state.activeWalk), plan = PetDiscoveryScenePlan(walk: savedWalk)
        for second in stride(from: 0.0, through: 7_200, by: 0.3) {
            _ = plan.frame(at: start.addingTimeInterval(second))
        }
        XCTAssertEqual(state, before)
        XCTAssertNil(state.collectWalk(at: savedWalk.endsAt.addingTimeInterval(-0.1)))
        let find = try XCTUnwrap(state.collectWalk(at: savedWalk.endsAt))
        XCTAssertEqual(find.discovery, savedWalk.discovery)
        XCTAssertNil(state.collectWalk(at: savedWalk.endsAt))
    }

    func testInvalidAndBackwardsClockKeepFiniteStartingFrame() {
        let plan = PetDiscoveryScenePlan(walk: walk(.shore)), initial = plan.frame(at: start)
        for date in [start.addingTimeInterval(-86_400), Date(timeIntervalSince1970: .nan), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertEqual(plan.frame(at: date), initial)
        }
    }

    func testDistanceForGaitMatchesActualTravelAtAnyViewportSize() {
        let plan = PetDiscoveryScenePlan(walk: walk(.garden))
        let first = plan.frame(at: start), middle = plan.frame(at: start.addingTimeInterval(4.5))
        for size in [CGSize(width: 320, height: 220), CGSize(width: 600, height: 300)] {
            let distance = hypot((middle.position.x - first.position.x) * size.width,
                                 (middle.position.y - first.position.y) * size.height)
            XCTAssertEqual(middle.travelledDistance(in: size), distance, accuracy: 0.00001)
        }
    }
}
