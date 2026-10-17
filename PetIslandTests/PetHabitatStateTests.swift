import XCTest
@testable import PetIsland

final class PetHabitatStateTests: XCTestCase {
    func testWidgetPettingPersistsFeedbackAndCareWithoutChangingThePetsOrHabitat() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 3, at: date.addingTimeInterval(-3_600))
        let original = shared
        let requestID = UUID()

        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: requestID, at: date))

        XCTAssertEqual(shared.configuration, original.configuration)
        XCTAssertEqual(shared.residents.map(\.profile), original.residents.map(\.profile))
        XCTAssertEqual(shared.discoveryWalk, original.discoveryWalk)
        XCTAssertEqual(shared.appliedCareEventIDs, original.appliedCareEventIDs)
        XCTAssertEqual(shared.visibleProjections(at: date), original.visibleProjections(at: date))
        for resident in shared.residents {
            XCTAssertEqual(resident.vitals.fullness, 0.5, accuracy: 0.000001)
            XCTAssertEqual(resident.vitals.happiness, 0.56, accuracy: 0.000001)
            XCTAssertEqual(resident.vitals.energy, 0.54, accuracy: 0.000001)
            XCTAssertEqual(resident.vitalsUpdatedAt, date)
        }
        let feedback = try XCTUnwrap(shared.widgetInteraction(at: date))
        XCTAssertEqual(feedback.requestID, requestID)
        XCTAssertEqual(feedback.action, .pet)
        XCTAssertEqual(feedback.date, date)
        XCTAssertEqual(feedback.petIDs, original.residents.map(\.id))
        XCTAssertEqual(shared.processedWidgetRequestIDs, [requestID])
    }

    func testWidgetPlayRetainsTheExistingCareEffect() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 2, at: date)
        var oldBehavior = shared
        oldBehavior.playWithResidents(at: date)

        XCTAssertTrue(shared.performWidgetAction(.play, requestID: UUID(), at: date))

        XCTAssertEqual(shared.residents, oldBehavior.residents)
        XCTAssertEqual(shared.lastWidgetInteraction?.action, .play)
    }

    func testWidgetActionsClampHappinessAndEnergyWithoutChangingFullness() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        shared.residents[0].vitals = PetVitals(fullness: 0.42, happiness: 0.98, energy: 0.01)

        XCTAssertTrue(shared.performWidgetAction(.play, requestID: UUID(), at: date))
        XCTAssertEqual(shared.residents[0].vitals, PetVitals(fullness: 0.42, happiness: 1, energy: 0))
    }

    func testWidgetActionsIgnoreEmptyUnselectedAndDynamicIslandResidents() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 2, at: date)
        shared.configuration.setDynamicIslandLead(shared.residents[0].id)
        shared.configuration.setResidents([])
        let original = shared

        for action in HabitatWidgetAction.allCases {
            XCTAssertFalse(shared.canPerformWidgetAction(at: date))
            XCTAssertFalse(shared.performWidgetAction(action, requestID: UUID(), at: date))
            XCTAssertEqual(shared, original)
        }
        shared.residents = []
        let empty = shared
        XCTAssertFalse(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        XCTAssertEqual(shared, empty)
    }

    func testWidgetActionsSkipWalkingAndDynamicIslandPetsEvenWithAStaleResidentPayload() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 3, at: date)
        let leadID = shared.residents[0].id
        let walkingPet = shared.residents[1].profile
        let homeID = shared.residents[2].id
        shared.configuration.setDynamicIslandLead(leadID)
        shared.discoveryWalk = try XCTUnwrap(PetDiscoveryWalk(
            pet: walkingPet, route: .garden, startedAt: date,
            endsAt: date.addingTimeInterval(60), discovery: .clover
        ))
        let original = shared

        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        XCTAssertEqual(shared.residents[0], original.residents[0])
        XCTAssertEqual(shared.residents[1], original.residents[1])
        XCTAssertEqual(shared.widgetInteraction(at: date)?.petIDs, [homeID])

        let returnedAt = date.addingTimeInterval(60)
        XCTAssertTrue(shared.performWidgetAction(.play, requestID: UUID(), at: returnedAt))
        XCTAssertEqual(shared.widgetInteraction(at: returnedAt)?.petIDs, [walkingPet.id, homeID])
        XCTAssertEqual(shared.residents[0], original.residents[0])
        XCTAssertGreaterThan(shared.residents[1].vitals.happiness, original.residents[1].vitals.happiness)
        XCTAssertEqual(shared.discoveryWalk, original.discoveryWalk)
    }

    func testAllWalkingResidentsCannotReceiveWidgetCareUntilTheirReturn() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        let returnedAt = date.addingTimeInterval(60)
        shared.discoveryWalk = try XCTUnwrap(PetDiscoveryWalk(
            pet: shared.residents[0].profile, route: .garden, startedAt: date,
            endsAt: returnedAt, discovery: .clover
        ))
        let original = shared

        XCTAssertFalse(shared.canPerformWidgetAction(at: date))
        XCTAssertFalse(shared.performWidgetAction(.play, requestID: UUID(), at: date))
        XCTAssertEqual(shared, original)
        XCTAssertTrue(shared.canPerformWidgetAction(at: returnedAt))
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: returnedAt))
    }

    func testWidgetCooldownAppliesAcrossActionsAndRetriedRequestsStayIdempotent() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        let firstID = UUID()
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: firstID, at: date))
        let firstSnapshot = shared

        XCTAssertFalse(shared.performWidgetAction(.play, requestID: UUID(), at: date.addingTimeInterval(4.999)))
        XCTAssertFalse(shared.canPerformWidgetAction(at: date.addingTimeInterval(4.999)))
        XCTAssertEqual(shared, firstSnapshot)
        XCTAssertTrue(shared.canPerformWidgetAction(at: date.addingTimeInterval(5)))
        XCTAssertFalse(shared.performWidgetAction(.play, requestID: firstID, at: date.addingTimeInterval(5)))
        XCTAssertEqual(shared, firstSnapshot)

        let secondID = UUID()
        XCTAssertTrue(shared.performWidgetAction(.play, requestID: secondID, at: date.addingTimeInterval(5)))
        let secondSnapshot = shared
        XCTAssertFalse(shared.performWidgetAction(.pet, requestID: firstID, at: date.addingTimeInterval(10)))
        XCTAssertEqual(shared, secondSnapshot)
        XCTAssertEqual(shared.processedWidgetRequestIDs, [firstID, secondID])
    }

    func testWidgetFeedbackExpiresAndOnlyNamesRecipientsWhoAreStillAtHome() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 3, at: date)
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        let originalReceipt = shared.lastWidgetInteraction
        XCTAssertNil(shared.widgetInteraction(at: date.addingTimeInterval(-0.001)))
        XCTAssertNotNil(shared.widgetInteraction(at: date.addingTimeInterval(11.999)))
        XCTAssertNil(shared.widgetInteraction(at: date.addingTimeInterval(12)))

        shared.configuration.setDynamicIslandLead(shared.residents[0].id)
        shared.discoveryWalk = try XCTUnwrap(PetDiscoveryWalk(
            pet: shared.residents[1].profile, route: .garden, startedAt: date,
            endsAt: date.addingTimeInterval(60), discovery: .clover
        ))
        let homeID = shared.residents[2].id
        XCTAssertEqual(shared.widgetInteraction(at: date)?.petIDs, [homeID])
        shared.reconcile()
        XCTAssertEqual(shared.lastWidgetInteraction, originalReceipt, "App synchronization keeps the durable receipt.")
        XCTAssertEqual(shared.widgetInteraction(at: date)?.petIDs, [homeID])
        shared.configuration.setResidents([])
        XCTAssertNil(shared.widgetInteraction(at: date))
    }

    func testWidgetCareAndFeedbackSurviveRoundTripAndLegacySnapshotsStillLoad() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 2, at: date)
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        XCTAssertEqual(try PropertyListDecoder().decode(SharedPetHabitat.self, from: PropertyListEncoder().encode(shared)), shared)
        let encoded = try JSONEncoder().encode(shared)
        XCTAssertEqual(try JSONDecoder().decode(SharedPetHabitat.self, from: encoded), shared)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "lastWidgetInteraction")
        legacyObject.removeValue(forKey: "processedWidgetRequestIDs")
        let legacy = try JSONDecoder().decode(SharedPetHabitat.self, from: JSONSerialization.data(withJSONObject: legacyObject))
        XCTAssertNil(legacy.lastWidgetInteraction)
        XCTAssertTrue(legacy.processedWidgetRequestIDs.isEmpty)
        XCTAssertEqual(legacy.residents, shared.residents)
        XCTAssertEqual(legacy.configuration, shared.configuration)
    }

    func testWidgetRequestHistoryIsBoundedOnWritesAndReads() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        let requests = (0..<40).map { _ in UUID() }
        for (index, id) in requests.enumerated() {
            XCTAssertTrue(shared.performWidgetAction(.pet, requestID: id, at: date.addingTimeInterval(Double(index) * 5)))
        }
        XCTAssertEqual(shared.processedWidgetRequestIDs, Array(requests.suffix(32)))
        shared.processedWidgetRequestIDs = requests
        let decoded = try PropertyListDecoder().decode(SharedPetHabitat.self, from: PropertyListEncoder().encode(shared))
        XCTAssertEqual(decoded.processedWidgetRequestIDs, Array(requests.suffix(32)))
        shared.reconcile()
        XCTAssertEqual(shared.processedWidgetRequestIDs, Array(requests.suffix(32)))
    }

    func testWidgetCareMergesOnceWithoutChangingWalletOrOverwritingNewerAppCare() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        let pet = shared.residents[0].profile
        var arcade = ArcadeState(progress: ArcadeProgress(coins: 42))
        arcade.reconcile(with: [pet])
        let progress = arcade.progress
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))

        arcade.mergeVitals(from: shared)
        let firstMerge = arcade
        arcade.mergeVitals(from: shared)
        XCTAssertEqual(arcade, firstMerge)
        XCTAssertEqual(arcade.progress, progress)
        XCTAssertEqual(arcade.vitalsByPetID[pet.id], shared.residents[0].vitals)

        arcade.vitalsByPetID[pet.id] = PetVitals(fullness: 0.9, happiness: 0.9, energy: 0.9)
        arcade.vitalsUpdatedAtByPetID[pet.id] = date.addingTimeInterval(1)
        let newerAppCare = arcade
        arcade.mergeVitals(from: shared)
        XCTAssertEqual(arcade, newerAppCare)
    }

    func testWidgetCareRejectsInvalidDatesAndDoesNotRollbackNewerCare() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 2, at: date)
        let original = shared
        for invalidDate in [Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: .nan)] {
            XCTAssertFalse(shared.canPerformWidgetAction(at: invalidDate))
            XCTAssertFalse(shared.performWidgetAction(.pet, requestID: UUID(), at: invalidDate))
            XCTAssertNil(shared.widgetInteraction(at: invalidDate))
            XCTAssertEqual(shared, original)
        }
        XCTAssertFalse(shared.performWidgetAction(.pet, requestID: UUID(), at: date.addingTimeInterval(-1)))
        XCTAssertEqual(shared, original)

        shared.residents[0].vitalsUpdatedAt = date.addingTimeInterval(60)
        let newerResident = shared.residents[0]
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        XCTAssertEqual(shared.residents[0], newerResident)
        XCTAssertEqual(shared.lastWidgetInteraction?.petIDs, [shared.residents[1].id])
    }

    func testFutureWidgetReceiptDoesNotKeepAvailableResidentsLocked() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        shared.lastWidgetInteraction = HabitatWidgetInteraction(
            requestID: UUID(), action: .play, date: date.addingTimeInterval(3_600), petIDs: shared.residents.map(\.id)
        )
        XCTAssertNil(shared.widgetInteraction(at: date))
        XCTAssertTrue(shared.canPerformWidgetAction(at: date))
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        XCTAssertEqual(shared.residents[0].vitals.happiness, 0.56, accuracy: 0.000001)
        XCTAssertEqual(shared.lastWidgetInteraction?.date, date)
    }

    func testWidgetTimelineUsesThirteenSparseOrderedUniqueAmbientSnapshots() {
        let date = Date(timeIntervalSince1970: 50_000)
        let shared = makeWidgetHabitat(count: 3, at: date)

        let dates = PetEnclosureTimeline.dates(for: shared, startingAt: date)

        XCTAssertEqual(dates, (0...12).map { date.addingTimeInterval(Double($0) * 300) })
        XCTAssertEqual(dates.count, 13)
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertEqual(dates.last, date.addingTimeInterval(PetEnclosureTimeline.refreshInterval))
    }

    func testWidgetTimelineSchedulesExactCareDeadlinesIncludingMidwayRefreshes() {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))

        for age in [0.0, 2.5, 5.0, 6.0, 11.999, 12.0] {
            let now = date.addingTimeInterval(age)
            let dates = PetEnclosureTimeline.dates(for: shared, startingAt: now)
            let futureCareDeadlines = [5.0, 12.0].filter { $0 > age }.map { date.addingTimeInterval($0) }
            let ambientDates = (0...12).map { now.addingTimeInterval(Double($0) * 300) }
            XCTAssertEqual(dates, Array(Set(ambientDates + futureCareDeadlines)).sorted(), "Refresh at age \(age)")
            XCTAssertEqual(dates.filter { $0 < now.addingTimeInterval(300) }, [now] + futureCareDeadlines)
        }

        // Changing residents can hide feedback while the shared cooldown is
        // still active. The new residents need their button enabled at +5 s.
        let replacement = makeWidgetHabitat(count: 1, at: date)
        shared.configuration = replacement.configuration
        shared.residents = replacement.residents
        let midway = date.addingTimeInterval(2)
        XCTAssertNil(shared.widgetInteraction(at: midway))
        XCTAssertFalse(shared.canPerformWidgetAction(at: midway))
        XCTAssertTrue(PetEnclosureTimeline.dates(for: shared, startingAt: midway).contains(date.addingTimeInterval(5)))
    }

    func testWidgetTimelineIncludesWalkReturnAndRejectsInvalidStartingDates() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        let returnedAt = date.addingTimeInterval(429)
        shared.discoveryWalk = try XCTUnwrap(PetDiscoveryWalk(
            pet: shared.residents[0].profile, route: .garden, startedAt: date,
            endsAt: returnedAt, discovery: .clover
        ))

        let dates = PetEnclosureTimeline.dates(for: shared, startingAt: date)
        XCTAssertEqual(dates.count, 14)
        XCTAssertEqual(dates.filter { $0 == returnedAt }.count, 1)
        XCTAssertTrue(dates.allSatisfy { $0.timeIntervalSinceReferenceDate.isFinite && $0 >= date })
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertEqual(PetEnclosureTimeline.dates(for: shared, startingAt: returnedAt).count, 13)

        shared.discoveryWalk = try XCTUnwrap(PetDiscoveryWalk(
            pet: shared.residents[0].profile, route: .garden, startedAt: date,
            endsAt: date.addingTimeInterval(300), discovery: .clover
        ))
        XCTAssertEqual(PetEnclosureTimeline.dates(for: shared, startingAt: date).count, 13,
                       "A return coinciding with an ambient entry must not duplicate it.")
        for invalidDate in [Date(timeIntervalSinceReferenceDate: .infinity), Date(timeIntervalSinceReferenceDate: -.infinity),
                            Date(timeIntervalSinceReferenceDate: .nan)] {
            XCTAssertTrue(PetEnclosureTimeline.dates(for: shared, startingAt: invalidDate).isEmpty)
        }
    }

    func testWidgetTimelineClearsFeedbackWhenItsRecipientReturnsBeforeExpiry() throws {
        let date = Date(timeIntervalSince1970: 50_000)
        var shared = makeWidgetHabitat(count: 1, at: date)
        XCTAssertTrue(shared.performWidgetAction(.pet, requestID: UUID(), at: date))
        let now = date.addingTimeInterval(2)
        let returnedAt = date.addingTimeInterval(7)
        let expiredAt = date.addingTimeInterval(12)
        shared.discoveryWalk = try XCTUnwrap(PetDiscoveryWalk(
            pet: shared.residents[0].profile, route: .garden,
            startedAt: date.addingTimeInterval(1), endsAt: returnedAt, discovery: .clover
        ))
        XCTAssertNil(shared.widgetInteraction(at: now))
        XCTAssertNotNil(shared.widgetInteraction(at: returnedAt))
        XCTAssertNil(shared.widgetInteraction(at: expiredAt))

        let dates = PetEnclosureTimeline.dates(for: shared, startingAt: now)
        XCTAssertEqual(dates.filter { $0 < now.addingTimeInterval(300) },
                       [now, date.addingTimeInterval(5), returnedAt, expiredAt])

        // Clock skew must not schedule a reaction that has not happened yet.
        shared.discoveryWalk = nil
        shared.lastWidgetInteraction = HabitatWidgetInteraction(
            requestID: UUID(), action: .pet, date: now.addingTimeInterval(60), petIDs: shared.residents.map(\.id)
        )
        XCTAssertEqual(PetEnclosureTimeline.dates(for: shared, startingAt: now),
                       (0...12).map { now.addingTimeInterval(Double($0) * 300) })
    }

    func testConcurrentWidgetActionsAtomicallySaveOneCareEffectAndMatchingFeedback() async throws {
        let date = Date(timeIntervalSince1970: 50_000)
        let initial = makeWidgetHabitat(count: 2, at: date)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "habitat.plist")
        let requests = (0..<32).map { _ in UUID() }
        let accepted = try await withThrowingTaskGroup(of: Bool.self, returning: Int.self) { group in
            for requestID in requests {
                group.addTask {
                    let file = SharedSnapshotFile<SharedPetHabitat>(url: url)
                    var didApply = false
                    try file.update(fallback: { initial }) { shared in
                        didApply = shared.performWidgetAction(.pet, requestID: requestID, at: date)
                    }
                    return didApply
                }
            }
            var count = 0
            for try await didApply in group where didApply { count += 1 }
            return count
        }
        XCTAssertEqual(accepted, 1)
        let restored = try SharedSnapshotFile<SharedPetHabitat>(url: url).load(fallback: { initial })
        let feedback = try XCTUnwrap(restored.widgetInteraction(at: date))
        XCTAssertTrue(requests.contains(feedback.requestID))
        XCTAssertEqual(restored.processedWidgetRequestIDs, [feedback.requestID])
        XCTAssertEqual(feedback.petIDs, initial.residents.map(\.id))
        for resident in restored.residents {
            XCTAssertEqual(resident.vitals.happiness, 0.56, accuracy: 0.000001)
            XCTAssertEqual(resident.vitals.energy, 0.5, accuracy: 0.000001)
        }
        XCTAssertEqual(restored.configuration, initial.configuration)
        XCTAssertEqual(restored.residents.map(\.profile), initial.residents.map(\.profile))
    }

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
        XCTAssertFalse(decoded.hasCozyBox)
        XCTAssertEqual(decoded.revision, 0)
    }

    func testCozyBoxStartsDisabledAndOnlyChangesRevisionWhenToggled() {
        let epoch = Date(timeIntervalSince1970: 12_345)
        let residentIDs = [UUID(), UUID()]
        var state = PetHabitatState(theme: .sunnyMeadow, residentPetIDs: residentIDs,
                                    simulationEpoch: epoch, behaviorSeed: 42, revision: 7)
        XCTAssertFalse(state.hasCozyBox)
        XCTAssertFalse(state.setCozyBox(false))
        XCTAssertEqual(state.revision, 7)
        XCTAssertTrue(state.setCozyBox(true))
        XCTAssertEqual(state.revision, 8)
        XCTAssertTrue(state.hasCozyBox)
        XCTAssertFalse(state.setCozyBox(true))
        XCTAssertEqual(state.revision, 8)
        XCTAssertTrue(state.setCozyBox(false))
        XCTAssertEqual(state.revision, 9)
        XCTAssertFalse(state.hasCozyBox)
        XCTAssertEqual(state.residentPetIDs, residentIDs)
        XCTAssertEqual(state.theme, .sunnyMeadow)
        XCTAssertEqual(state.simulationEpoch, epoch)
        XCTAssertEqual(state.behaviorSeed, 42)
        XCTAssertNil(state.leadDynamicIslandPetID)
    }

    func testCozyBoxSharedRoundTripPreservesDiscoveriesAndResidents() throws {
        let epoch = Date(timeIntervalSince1970: 12_345)
        let pets = makePets(count: 3, createdAt: epoch)
        let walk = try XCTUnwrap(PetDiscoveryWalk(pet: pets[0], route: .garden, startedAt: epoch,
                                                 endsAt: epoch.addingTimeInterval(1_200), discovery: .clover))
        var shared = SharedPetHabitat(
            configuration: PetHabitatState(theme: .warmRoom, residentPetIDs: pets.map(\.id),
                                           simulationEpoch: epoch, hasCozyBox: true),
            residents: pets.map { SharedHabitatResident(profile: $0, vitals: PetVitals(), vitalsUpdatedAt: epoch) },
            discoveryWalk: walk
        )
        shared.appliedCareEventIDs = [UUID()]
        for enabled in [true, false] {
            shared.configuration.setCozyBox(enabled)
            let json = try JSONEncoder().encode(shared)
            XCTAssertEqual(try JSONDecoder().decode(SharedPetHabitat.self, from: json), shared)
            let plist = try PropertyListEncoder().encode(shared)
            var restored = try PropertyListDecoder().decode(SharedPetHabitat.self, from: plist)
            restored.reconcile()
            XCTAssertEqual(restored, shared)
            XCTAssertEqual(restored.configuration.hasCozyBox, enabled)
            XCTAssertEqual(restored.discoveryWalk, walk)
            XCTAssertEqual(restored.visibleResidents(at: epoch).map(\.id), Array(pets.dropFirst()).map(\.id))
        }
    }

    func testExistingFullHabitatMigratesWithoutAddingBoxOrLosingFields() throws {
        let epoch = Date(timeIntervalSince1970: 12_345)
        let ids = [UUID(), UUID(), UUID()]
        let original = PetHabitatState(theme: .starryNight, residentPetIDs: ids,
                                       leadDynamicIslandPetID: ids[1], simulationEpoch: epoch,
                                       behaviorSeed: 543, revision: 23)
        let data = try JSONEncoder().encode(original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "hasCozyBox")
        let legacyData = try JSONSerialization.data(withJSONObject: json)
        XCTAssertEqual(try JSONDecoder().decode(PetHabitatState.self, from: legacyData), original)
    }

    func testCozyBoxSurvivesDynamicIslandMovesAndResidentReconciliation() {
        let ids = [UUID(), UUID(), UUID()]
        var state = PetHabitatState(residentPetIDs: ids, hasCozyBox: true)
        XCTAssertTrue(state.setDynamicIslandLead(ids[1]))
        XCTAssertTrue(state.hasCozyBox)
        XCTAssertEqual(state.residentPetIDs, [ids[0], ids[2]])
        state.reconcile(availablePetIDs: Set(ids))
        XCTAssertTrue(state.hasCozyBox)
        XCTAssertTrue(state.returnDynamicIslandLeadToHabitat())
        XCTAssertTrue(state.hasCozyBox)
        XCTAssertEqual(state.residentPetIDs, [ids[0], ids[2], ids[1]])
        state.reconcile(availablePetIDs: Set([ids[0], ids[1]]))
        XCTAssertTrue(state.hasCozyBox)
        XCTAssertEqual(state.residentPetIDs, [ids[0], ids[1]])
    }

    func testCozyBoxSelectionPreservesAllWidgetPetMovement() {
        let epoch = Date(timeIntervalSince1970: 12_345)
        let pets = makePets(count: 6, createdAt: epoch)
        let original = PetHabitatState(residentPetIDs: pets.map(\.id), simulationEpoch: epoch, behaviorSeed: 42)
        var withBox = original
        XCTAssertTrue(withBox.setCozyBox(true))
        for second in stride(from: 0.0, through: 96, by: 0.5) {
            let date = epoch.addingTimeInterval(second)
            let before = PetHabitatEngine.projections(for: original, pets: pets, at: date)
            let after = PetHabitatEngine.projections(for: withBox, pets: pets, at: date)
            XCTAssertEqual(before.count, after.count)
            for (old, new) in zip(before, after) {
                XCTAssertEqual(new.petID, old.petID)
                XCTAssertEqual(new.position, old.position)
                XCTAssertEqual(new.verticalPosition, old.verticalPosition)
                XCTAssertEqual(new.lane, old.lane)
                XCTAssertEqual(new.direction, old.direction)
                XCTAssertEqual(new.pose, old.pose)
                XCTAssertEqual(new.status, old.status)
                XCTAssertEqual(new.depth, old.depth)
                // All scenery edits already advance this shared refresh index.
                XCTAssertEqual(new.spriteStep, old.spriteStep + 1)
            }
        }
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

    private func makeWidgetHabitat(count: Int, at date: Date) -> SharedPetHabitat {
        let pets = makePets(count: count, createdAt: date)
        return SharedPetHabitat(
            configuration: PetHabitatState(residentPetIDs: pets.map(\.id), simulationEpoch: date),
            residents: pets.map {
                SharedHabitatResident(profile: $0, vitals: PetVitals(fullness: 0.5, happiness: 0.5, energy: 0.5), vitalsUpdatedAt: date)
            }
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
