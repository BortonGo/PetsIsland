import XCTest
@testable import PetIsland

final class PetHabitatStateTests: XCTestCase {
    func testWidgetCareMergesIntoArcadeWithoutOverwritingNewerAppCare() throws {
        let pet = makePets(count: 1, createdAt: .now)[0]
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = SharedPetHabitat(configuration: PetHabitatState(residentPetIDs: [pet.id]),
                                     residents: [SharedHabitatResident(profile: pet, vitals: PetVitals())])
        var arcade = ArcadeState(progress: ArcadeProgress(coins: 42))
        arcade.reconcile(with: [pet])
        shared.playWithResidents(at: date)
        arcade.mergeVitals(from: shared)
        XCTAssertEqual(arcade.vitalsByPetID[pet.id], shared.residents[0].vitals)
        XCTAssertEqual(arcade.progress.coins, 42)
        let newer = PetVitals(fullness: 1, happiness: 1, energy: 1)
        arcade.vitalsByPetID[pet.id] = newer
        arcade.vitalsUpdatedAtByPetID[pet.id] = date.addingTimeInterval(1)
        arcade.mergeVitals(from: shared)
        XCTAssertEqual(arcade.vitalsByPetID[pet.id], newer)
        let restored = try JSONDecoder().decode(ArcadeState.self, from: JSONEncoder().encode(arcade))
        XCTAssertEqual(restored, arcade)
    }

    func testOldResidentPayloadDecodesWithoutCareTimestamp() throws {
        let pet = makePets(count: 1, createdAt: .now)[0]
        let payload = LegacyResident(profile: pet, vitals: PetVitals())
        let decoded = try JSONDecoder().decode(SharedHabitatResident.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(decoded.profile, pet)
        XCTAssertEqual(decoded.vitalsUpdatedAt, .distantPast)
    }

    func testSharedPayloadKeepsLeadOutsideResidentListAcrossRoundTrip() throws {
        let pets = makePets(count: 2, createdAt: .now)
        var shared = SharedPetHabitat(
            configuration: PetHabitatState(residentPetIDs: pets.map(\.id)),
            residents: pets.map { SharedHabitatResident(profile: $0, vitals: PetVitals()) }
        )
        shared.configuration.setDynamicIslandLead(pets[0].id)
        shared.residents.removeFirst()
        shared.reconcile()
        shared = try PropertyListDecoder().decode(SharedPetHabitat.self, from: PropertyListEncoder().encode(shared))
        shared.reconcile()
        XCTAssertEqual(shared.configuration.leadDynamicIslandPetID, pets[0].id)
        XCTAssertEqual(shared.configuration.residentPetIDs, [pets[1].id])
        XCTAssertTrue(shared.configuration.returnDynamicIslandLeadToHabitat())
        shared.residents.append(SharedHabitatResident(profile: pets[0], vitals: PetVitals()))
        shared.reconcile()
        XCTAssertEqual(shared.configuration.residentPetIDs, [pets[1].id, pets[0].id])
        XCTAssertNil(shared.configuration.leadDynamicIslandPetID)
    }

    func testAllSpeciesRemainContinuousAtEveryWalkRunTurnAndCycleBoundary() throws {
        let epoch = Date(timeIntervalSince1970: 35_000)
        let pets = makePets(count: 6, createdAt: epoch)
        let state = PetHabitatState(residentPetIDs: pets.map(\.id), simulationEpoch: epoch)
        var previous = PetHabitatEngine.projections(for: state, pets: pets, at: epoch)
        for frame in 1...6_000 {
            let next = PetHabitatEngine.projections(for: state, pets: pets,
                                                   at: epoch.addingTimeInterval(Double(frame) / 30))
            for (a, b) in zip(previous, next) {
                XCTAssertLessThan(abs(a.position - b.position), 0.004)
                XCTAssertEqual(a.verticalPosition, b.verticalPosition)
            }
            previous = next
        }
    }

    func testResidentsAreUniqueLimitedAndExcludeDynamicIslandLead() {
        let ids = (0..<8).map { _ in UUID() }
        let state = PetHabitatState(
            residentPetIDs: ids + [ids[0], ids[2]],
            leadDynamicIslandPetID: ids[1]
        )

        XCTAssertEqual(state.residentPetIDs.count, PetHabitatState.maximumResidents - 1)
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

    func testColorfulThemesSurviveSharedSnapshotWithoutChangingResidentsOrMotion() throws {
        let epoch = Date(timeIntervalSince1970: 12_345)
        let pets = makePets(count: 3, createdAt: epoch)
        var shared = SharedPetHabitat(
            configuration: PetHabitatState(residentPetIDs: pets.map(\.id), simulationEpoch: epoch),
            residents: pets.map { SharedHabitatResident(profile: $0, vitals: PetVitals()) }
        )
        let initialProjections = PetHabitatEngine.projections(for: shared.configuration, pets: pets, at: epoch)
        let themes: [HabitatTheme] = [.sunnyMeadow, .starryNight, .warmRoom, .snowyCove, .sunsetDunes]
        for theme in themes {
            XCTAssertTrue(shared.configuration.setTheme(theme))
            let data = try PropertyListEncoder().encode(shared)
            var restored = try PropertyListDecoder().decode(SharedPetHabitat.self, from: data)
            restored.reconcile()
            XCTAssertEqual(restored, shared)
            XCTAssertEqual(restored.configuration.theme, theme)
            let projections = PetHabitatEngine.projections(for: restored.configuration, pets: pets, at: epoch)
            // The widget's refresh frame can advance with the snapshot revision;
            // changing scenery must preserve the actual placement and behavior.
            XCTAssertEqual(projections.map(\.position), initialProjections.map(\.position))
            XCTAssertEqual(projections.map(\.verticalPosition), initialProjections.map(\.verticalPosition))
            XCTAssertEqual(projections.map(\.direction), initialProjections.map(\.direction))
            XCTAssertEqual(projections.map(\.pose), initialProjections.map(\.pose))
        }
    }

    func testExistingThemeIdentifiersKeepTheirSavedSelection() throws {
        let identifiers: [(String, HabitatTheme)] = [
            ("meadow", .meadow), ("cozyRoom", .cozyRoom), ("moonlitGarden", .moonlitGarden),
            ("arcticCove", .arcticCove), ("desertCamp", .desertCamp)
        ]
        let residentID = UUID()
        for (identifier, theme) in identifiers {
            let data = Data("{\"theme\":\"\(identifier)\",\"residentPetIDs\":[\"\(residentID.uuidString)\"]}".utf8)
            let restored = try JSONDecoder().decode(PetHabitatState.self, from: data)
            XCTAssertEqual(restored.theme, theme)
            XCTAssertEqual(restored.residentPetIDs, [residentID])
        }
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

    func testRunningMovesFasterThanWalkingInsideHabitat() throws {
        let epoch = Date(timeIntervalSince1970: 35_000)
        let pet = makePets(count: 1, createdAt: epoch)[0]
        let state = PetHabitatState(
            residentPetIDs: [pet.id],
            simulationEpoch: epoch,
            behaviorSeed: 11
        )
        let sampleDuration = 0.05
        var walkingDistance: Double?
        var runningDistance: Double?

        for sample in 0..<2_000 where walkingDistance == nil || runningDistance == nil {
            let date = epoch.addingTimeInterval(Double(sample) * sampleDuration)
            let nextDate = date.addingTimeInterval(sampleDuration)
            guard
                let current = PetHabitatEngine.projections(for: state, pets: [pet], at: date).first,
                let next = PetHabitatEngine.projections(for: state, pets: [pet], at: nextDate).first,
                current.status == next.status,
                current.direction == next.direction
            else { continue }

            let distance = abs(next.position - current.position)
            if current.status == .wandering, distance > 0 {
                walkingDistance = distance
            } else if current.status == .running, distance > 0 {
                runningDistance = distance
            }
        }

        let walk = try XCTUnwrap(walkingDistance)
        let run = try XCTUnwrap(runningDistance)
        XCTAssertEqual(
            run / walk,
            PetHabitatEngine.runningSpeedMultiplier,
            accuracy: 0.01
        )
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

private struct LegacyResident: Encodable {
    let profile: PetProfile
    let vitals: PetVitals
}
