import AppIntents
import Foundation
import WidgetKit

/// Shared by the app and extension. One snapshot owns the entire care action.
struct HabitatWidgetCareIntent: AppIntent {
    static let title = LocalizedStringResource("Care for enclosure pets", table: "EnclosureWidget")
    static let description = IntentDescription(LocalizedStringResource(
        "Give the pets at home a little attention without opening the app.", table: "EnclosureWidget"))
    static let openAppWhenRun = false
    static let isDiscoverable = false

    // A primitive wire value survives WidgetKit's cross-process button archive
    // on older runtimes; validate it back into the domain enum before use.
    @Parameter(title: "Action", default: "") var actionValue: String
    @Parameter(title: "Request") var request: String

    init() { }
    init(action: HabitatWidgetAction, requestID: UUID) {
        actionValue = action.rawValue
        request = requestID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let action = HabitatWidgetAction(rawValue: actionValue),
              let requestID = UUID(uuidString: request) else { return .result() }
        try PetHabitatStore.update {
            _ = $0.performWidgetAction(action, requestID: requestID, at: .now)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
        return .result()
    }
}

/// Keep the identity used by older archived widgets. The same single-file
/// transaction now handles their button, without changing the Dynamic Island lead.
struct ThrowBallIntent: AppIntent {
    static let title: LocalizedStringResource = "Throw a ball"
    static let openAppWhenRun = false
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        try await HabitatWidgetCareIntent(action: .play, requestID: UUID()).perform()
    }
}

enum PetEnclosureTimeline {
    static let refreshInterval: TimeInterval = 3_600

    static func dates(for habitat: SharedPetHabitat, startingAt now: Date) -> [Date] {
        guard now.timeIntervalSinceReferenceDate.isFinite else { return [] }
        var dates = [now]
        // The deadlines belong to the action even if its recipients have left.
        // Keep cooldown expiry for new residents, and feedback expiry in case a
        // scheduled return makes a recipient visible before the reaction ends.
        if let receipt = habitat.lastWidgetInteraction,
           receipt.date.timeIntervalSinceReferenceDate.isFinite, receipt.date <= now {
            for offset in [HabitatWidgetInteraction.cooldown, HabitatWidgetInteraction.feedbackDuration] {
                let deadline = receipt.date.addingTimeInterval(offset)
                if deadline.timeIntervalSinceReferenceDate.isFinite, deadline > now { dates.append(deadline) }
            }
        }
        // Predrawn snapshots, not a background animation loop. A button press
        // reloads immediately; these sparse moments cover ordinary idle time.
        dates += (1...12).map { now.addingTimeInterval(TimeInterval($0) * 300) }
        if let returnDate = habitat.discoveryWalk?.endsAt,
           returnDate.timeIntervalSinceReferenceDate.isFinite, returnDate > now {
            dates.append(returnDate)
        }
        return Array(Set(dates)).sorted()
    }
}
