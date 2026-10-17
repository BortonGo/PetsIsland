import SwiftUI
import WidgetKit

struct PetEnclosureEntry: TimelineEntry {
    let date: Date
    let habitat: SharedPetHabitat
    let requestID: UUID

    init(date: Date, habitat: SharedPetHabitat) {
        self.date = date
        self.habitat = habitat
        requestID = UUID()
    }
}

struct PetEnclosureProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEnclosureEntry {
        PetEnclosureEntry(date: .now, habitat: .initial())
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEnclosureEntry) -> Void) {
        completion(PetEnclosureEntry(date: .now, habitat: context.isPreview ? .initial() : PetHabitatStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEnclosureEntry>) -> Void) {
        let habitat = PetHabitatStore.load()
        let now = Date.now
        let entries = PetEnclosureTimeline.dates(for: habitat, startingAt: now).map {
            PetEnclosureEntry(date: $0, habitat: habitat)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(PetEnclosureTimeline.refreshInterval))))
    }
}

struct PetEnclosureWidget: Widget {
    nonisolated static let kind = "PetIsland.Enclosure"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PetEnclosureProvider()) { entry in
            PetEnclosureWidgetView(entry: entry)
                .containerBackground(for: .widget) { PetEnclosureCard.background(for: entry.habitat.configuration.theme) }
                .widgetURL(URL(string: "petisland://enclosure"))
        }
        .configurationDisplayName(Text("Your island", tableName: "EnclosureWidget"))
        .description(Text("A little care, right from your Home Screen.", tableName: "EnclosureWidget"))
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}

private struct PetEnclosureWidgetView: View {
    let entry: PetEnclosureEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        PetEnclosureCard(date: entry.date, habitat: entry.habitat, family: family, requestID: entry.requestID)
    }
}

#if DEBUG
#Preview(as: .systemMedium) { PetEnclosureWidget() } timeline: {
    PetEnclosureEntry(date: .now, habitat: .initial())
}
#Preview(as: .systemSmall) { PetEnclosureWidget() } timeline: {
    PetEnclosureEntry(date: .now, habitat: .initial())
}
#endif
