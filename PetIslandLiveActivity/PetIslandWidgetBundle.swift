import WidgetKit
import SwiftUI

@main
struct PetIslandWidgetBundle: WidgetBundle {
    var body: some Widget {
        PetEnclosureWidget()
        PetLiveActivityWidget()
#if DEBUG
        LiveActivitySmokeWidget()
#endif
    }
}

#if DEBUG
private struct LiveActivitySmokeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitySmokeAttributes.self) { context in
            HStack(spacing: 8) {
                Text("🐾")
                Text("Pet Island · \(context.state.message)")
                    .font(.headline)
                Spacer()
                Text(timerInterval: Date.now...context.attributes.endsAt, countsDown: true)
                    .monospacedDigit()
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("🐾 Pet Island · \(context.state.message)")
                        .font(.headline)
                }
            } compactLeading: {
                Text("🐾")
            } compactTrailing: {
                Text("QA")
                    .font(.caption.bold())
            } minimal: {
                Text("🐾")
            }
            .keylineTint(.cyan)
        }
    }
}
#endif
