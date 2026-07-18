import XCTest
@testable import PetIsland

final class PetHabitatStateTests: XCTestCase {
    func testResidentsAreUniqueLimitedAndExcludeDynamicIslandLead() {
        let ids = (0..<8).map { _ in UUID() }
        let state = PetHabitatState(
            residentPetIDs: ids + [ids[0], ids[2]],
            leadDynamicIslandPetID: ids[1]
        )

        XCTAssertEqual(state.residentPetIDs.count, PetHabitatState.maximumResidents)
        XCTAssertEqual(Set(state.residentPetIDs).count, state.residentPetIDs.count)
        XCTAssertFalse(state.residentPetIDs.contains(ids[1]))
    }

    func testAssigningAndReturningDynamicIslandLeadPreservesSinglePlacement() {
        let ids = [UUID(), UUID(), UUID()]
        var state = PetHabitatState(residentPetIDs: ids)

        XCTAssertTrue(state.setDynamicIslandLead(ids[1]))
        XCTAssertEqual(state.leadDynamicIslandPetID, ids[1])
        XCTAssertFalse(state.residentPetIDs.contains(ids[1]))

        XCTAssertTrue(state.returnDynamicIslandLeadToHabitat())
        XCTAssertNil(state.leadDynamicIslandPetID)
        XCTAssertTrue(state.residentPetIDs.contains(ids[1]))
    }

    func testOlderPayloadMigratesWithSafeDefaults() throws {
        let residentID = UUID()
        let legacy = LegacyHabitatState(theme: .cozyRoom, residentPetIDs: [residentID])
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(PetHabitatState.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, PetHabitatState.currentSchemaVersion)
        XCTAssertEqual(decoded.theme, .cozyRoom)
        XCTAssertEqual(decoded.residentPetIDs, [residentID])
        XCTAssertNil(decoded.leadDynamicIslandPetID)
        XCTAssertEqual(decoded.revision, 0)
    }

    func testUnknownFutureThemeFallsBackWithoutLosingState() throws {
        let data = Data(#"{"theme":"underwater","residentPetIDs":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(PetHabitatState.self, from: data)

        XCTAssertEqual(decoded.theme, .meadow)
        XCTAssertTrue(decoded.residentPetIDs.isEmpty)
    }

    func testProjectionIsDeterministicAndCollisionSafeForSixPets() {
        let epoch = Date(timeIntervalSince1970: 10_000)
        let pets = makePets(count: 6, createdAt: epoch)
        let state = PetHabitatState(
            theme: .moonlitGarden,
            residentPetIDs: pets.map(\.id),
            simulationEpoch: epoch,
            behaviorSeed: 42
        )
        let date = epoch.addingTimeInterval(47.25)

        let first = PetHabitatEngine.projections(for: state, pets: pets, at: date)
        let second = PetHabitatEngine.projections(for: state, pets: pets, at: date)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 6)
        XCTAssertTrue(first.allSatisfy { (0...1).contains($0.position) })

        for lane in Dictionary(grouping: first, by: \.lane).values {
            let positions = lane.map(\.position).sorted()
            for pair in zip(positions, positions.dropFirst()) {
                XCTAssertGreaterThanOrEqual(
                    pair.1 - pair.0,
                    PetHabitatEngine.minimumHorizontalSeparation - 0.0001
                )
            }
        }

        let verticalPositions = Dictionary(grouping: first, by: \.lane)
            .values
            .compactMap { $0.first?.verticalPosition }
            .sorted()
        for pair in zip(verticalPositions, verticalPositions.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                pair.1 - pair.0,
                PetHabitatEngine.minimumVerticalSeparation - 0.0001
            )
        }
    }

    func testDynamicIslandLeadIsAbsentFromHabitatProjection() {
        let epoch = Date(timeIntervalSince1970: 20_000)
        let pets = makePets(count: 3, createdAt: epoch)
        let state = PetHabitatState(
            residentPetIDs: pets.map(\.id),
            leadDynamicIslandPetID: pets[0].id,
            simulationEpoch: epoch
        )

        let projections = PetHabitatEngine.projections(for: state, pets: pets, at: epoch)

        XCTAssertEqual(projections.map(\.petID), Array(pets.dropFirst()).map(\.id))
    }

    func testStateMachineVisitsMovementPlayAndSleepStates() {
        let epoch = Date(timeIntervalSince1970: 30_000)
        let pet = makePets(count: 1, createdAt: epoch)[0]
        let state = PetHabitatState(
            residentPetIDs: [pet.id],
            simulationEpoch: epoch,
            behaviorSeed: 7
        )

        let statuses = Set((0...120).compactMap { second in
            PetHabitatEngine.projections(
                for: state,
                pets: [pet],
                at: epoch.addingTimeInterval(TimeInterval(second))
            ).first?.status
        })

        XCTAssertTrue(statuses.contains(.wandering) || statuses.contains(.running))
        XCTAssertTrue(statuses.contains(.playing))
        XCTAssertTrue(statuses.contains(.sleeping))
    }

    private func makePets(count: Int, createdAt: Date) -> [PetProfile] {
        let species = PetSpecies.allCases
        return (0..<count).map { index in
            PetProfile(
                id: UUID(),
                name: "Pet \(index)",
                species: species[index % species.count],
                coat: .sunrise,
                createdAt: createdAt
            )
        }
    }
}

private struct LegacyHabitatState: Encodable {
    let theme: HabitatTheme
    let residentPetIDs: [UUID]
}
