import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.openURL) private var openURL
    @State private var showsPlayYard = false
    @State private var showsMiniGames = false
    @State private var showsHabitatEditor = false
    @State private var draftResidentIDs: [UUID] = []
    @State private var draftTheme: HabitatTheme = .meadow

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    habitat
                    identity
                    placementCard
                    arcadeCard
                    playCard
                    widgetHelp
                    activityAvailabilityNotice
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pet Island")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { controller.showsPetEditor = true } label: {
                        Label("My pets", systemImage: "pawprint.fill")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { controller.showsSettings = true } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
        }
        .sheet(isPresented: $controller.showsPetEditor) {
            PetCollectionView(controller: controller)
        }
        .sheet(isPresented: $showsHabitatEditor) {
            HabitatEditorView(
                pets: controller.pets,
                selectedPetIDs: $draftResidentIDs,
                selectedTheme: $draftTheme,
                vitalsByPetID: controller.habitatVitalsByPetID,
                maximumPets: PetHabitatState.maximumResidents
            ) {
                controller.saveHabitat(theme: draftTheme, residentPetIDs: draftResidentIDs)
                showsHabitatEditor = false
            }
        }
        .fullScreenCover(isPresented: $showsPlayYard) {
            PlayYardView(pets: controller.habitatResidents.isEmpty ? [controller.profile] : controller.habitatResidents)
        }
        .fullScreenCover(isPresented: $showsMiniGames) {
            MiniGamesView(controller: controller)
        }
        .sheet(isPresented: $controller.showsSettings) {
            SettingsView(controller: controller)
        }
    }

    private var habitat: some View {
        HabitatEditorCanvas(
            theme: controller.habitat.configuration.theme,
            pets: controller.habitatResidents,
            vitalsByPetID: controller.habitatVitalsByPetID
        )
        .frame(height: 250)
        .overlay(alignment: .topTrailing) {
            Button {
                draftResidentIDs = controller.habitat.configuration.residentPetIDs
                draftTheme = controller.habitat.configuration.theme
                showsHabitatEditor = true
            } label: {
                Label("Edit enclosure", systemImage: "paintpalette.fill")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }

    private var identity: some View {
        VStack(spacing: 4) {
            Text("Your enclosure").font(.title2.bold())
            Text("\(controller.habitatResidents.count) of \(PetHabitatState.maximumResidents) residents · \(themeTitle)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where should Pixel live now?").font(.headline)
                Text(placementDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                placementButton(
                    title: "Enclosure",
                    symbol: "house.lodge.fill",
                    placement: .enclosure
                )
                placementButton(
                    title: "Dynamic Island",
                    symbol: "iphone.gen3.radiowaves.left.and.right",
                    placement: .dynamicIsland
                )
            }
            dynamicIslandSettings

            Button {
                draftResidentIDs = controller.habitat.configuration.residentPetIDs
                draftTheme = controller.habitat.configuration.theme
                showsHabitatEditor = true
            } label: {
                Label("Choose residents and background", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if controller.placement == .dynamicIsland {
                liveActivityStatus
            }
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var dynamicIslandSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dynamic Island settings", systemImage: "slider.horizontal.3")
                .font(.headline)

            Picker("Pet mode", selection: motionModeBinding) {
                ForEach(DynamicIslandMotionMode.allCases) { mode in
                    Text(motionModeTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Picker("Time on the island", selection: durationBinding) {
                ForEach(SessionPreset.allCases) { preset in
                    Text(durationTitle(preset.rawValue)).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)

            if controller.session != nil {
                Text("New settings will apply the next time the pet enters Dynamic Island.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var motionModeBinding: Binding<DynamicIslandMotionMode> {
        Binding(
            get: { controller.settings.dynamicIslandMotionMode },
            set: { value in Task { await controller.updateDynamicIslandSettings(mode: value) } }
        )
    }

    private var durationBinding: Binding<Int> {
        Binding(
            get: { controller.settings.defaultSessionMinutes },
            set: { value in Task { await controller.updateDynamicIslandSettings(durationMinutes: value) } }
        )
    }

    private func motionModeTitle(_ mode: DynamicIslandMotionMode) -> String {
        switch mode {
        case .run: String(localized: "Run")
        case .walk: String(localized: "Walk")
        case .sleep: String(localized: "Sleep")
        case .runSleep: String(localized: "Run + sleep")
        case .walkSleep: String(localized: "Walk + sleep")
        case .runWalkSleep: String(localized: "Run + walk + sleep")
        }
    }

    private func durationTitle(_ minutes: Int) -> String {
        switch minutes {
        case 20: String(localized: "20 min")
        case 40: String(localized: "40 min")
        case 60: String(localized: "1 hour")
        case 120: String(localized: "2 hours")
        case 240: String(localized: "4 hours")
        default: "\(minutes) min"
        }
    }

    private func placementButton(
        title: LocalizedStringKey,
        symbol: String,
        placement: PetPlacement
    ) -> some View {
        let selected = controller.placement == placement
        return Button {
            Task { await controller.placePet(in: placement) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.subheadline.bold()).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .foregroundStyle(selected ? Color.white : Color.accentColor)
            .background(
                selected ? Color.accentColor : Color.accentColor.opacity(0.09),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(selected ? Color.clear : Color.accentColor.opacity(0.25))
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var playCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Play together", systemImage: "tennisball.fill")
                .font(.headline)
            Text("Open the playroom for continuous animation while the app is on screen. The enclosure widget has its own throwable ball.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showsPlayYard = true
            } label: {
                Label("Open playroom", systemImage: "figure.play")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var arcadeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pet Arcade", systemImage: "gamecontroller.fill")
                    .font(.headline)
                Spacer()
                Label("\(controller.arcadeProgress.coins)", systemImage: "dollarsign.circle.fill")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.orange)
            }
            Text("Choose a pet, set a high score and spend your coins on food, treats, toys and vitamins.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showsMiniGames = true
            } label: {
                Label("Open Pet Arcade", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.13), .blue.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private var widgetHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Add Pixel's enclosure", systemImage: "square.grid.2x2.fill")
                .font(.headline)
            Text("Hold an empty area on the Home Screen, tap +, find Pet Island and add the medium Enclosure widget.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.green.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private var liveActivityStatus: some View {
        switch controller.liveActivityConnection {
        case .active:
            Label("Pixel is on Dynamic Island", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .stale:
            Label("Pixel is sleeping on Dynamic Island", systemImage: "moon.zzz.fill")
                .foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Taking Pixel with you…")
            }
        case .unavailable:
            Label("Live Activities are disabled", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .inactive, .dismissed, .failed:
            HStack {
                Label("Dynamic Island is not connected", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Retry") { Task { await controller.reconnectLiveActivity() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var activityAvailabilityNotice: some View {
        if !controller.liveActivitiesEnabled {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    "Live Activities are off. The enclosure widget still works.",
                    systemImage: "info.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
                .font(.footnote.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var placementTitle: LocalizedStringKey {
        switch controller.placement {
        case .home: "At home"
        case .enclosure: "In the enclosure"
        case .dynamicIsland: "On Dynamic Island"
        }
    }

    private var placementDescription: LocalizedStringKey {
        switch controller.placement {
        case .home:
            "Choose the enclosure or take Pixel with you."
        case .enclosure:
            "Pixel plays in the Home Screen widget and reacts when you throw the ball."
        case .dynamicIsland:
            "Pixel runs across the available island area, turns around and lies down."
        }
    }

    private var placementSymbol: String {
        switch controller.placement {
        case .home: "house.fill"
        case .enclosure: "house.lodge.fill"
        case .dynamicIsland: "iphone.gen3.radiowaves.left.and.right"
        }
    }

    private var themeTitle: String {
        switch controller.habitat.configuration.theme {
        case .meadow: "Meadow"
        case .cozyRoom: "Cozy room"
        case .moonlitGarden: "Starlight"
        case .arcticCove: "Arctic cove"
        case .desertCamp: "Desert camp"
        }
    }
}

#if DEBUG
private struct HomeViewPreview: View {
    @StateObject private var controller = PetSessionController(store: InMemoryPetStore())

    var body: some View {
        HomeView(controller: controller)
            .task { await controller.bootstrap() }
    }
}

#Preview("Главный экран") {
    HomeViewPreview()
}
#endif
