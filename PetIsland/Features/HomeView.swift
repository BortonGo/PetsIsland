import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var controller: PetSessionController

    var body: some View {
        TabView(selection: $controller.selectedTab) {
            IslandView(controller: controller)
                .tabItem { Label("Island", systemImage: "house") }
                .tag(AppTab.island)

            PetCollectionView(controller: controller, showsDismissButton: false)
                .tabItem { Label("Pets", systemImage: "pawprint.fill") }
                .tag(AppTab.pets)

            MiniGamesView(controller: controller, showsDismissButton: false)
                .tabItem { Label("Arcade", systemImage: "gamecontroller.fill") }
                .tag(AppTab.arcade)

            SettingsView(controller: controller, showsDismissButton: false)
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(AppTab.settings)
        }
        .tint(PetDesign.accent)
    }
}

enum AppTab: Hashable {
    case island
    case pets
    case arcade
    case settings
}

private struct IslandView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.openURL) private var openURL
    @State private var showsHabitatEditor = false
    @State private var showsIslandSetup = false
    @State private var draftResidentIDs: [UUID] = []
    @State private var draftTheme: HabitatTheme = .meadow

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    HStack {
                        PetScreenHeading(title: "Island")
                        Button { showsIslandSetup = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.subheadline)
                                .frame(width: 44, height: 44)
                                .background(PetDesign.soft, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Island setup")
                    }
                    habitat
                    residentSummary
                    Button { controller.showsPlayYard = true } label: {
                        Label("Play together", systemImage: "tennisball")
                    }
                    .buttonStyle(PetPrimaryButtonStyle())
                    placementCard
                    activityAvailabilityNotice
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
            .petPage()
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showsHabitatEditor) {
            HabitatEditorView(
                pets: controller.pets.filter { $0.id != controller.habitat.configuration.leadDynamicIslandPetID },
                selectedPetIDs: $draftResidentIDs,
                selectedTheme: $draftTheme,
                vitalsByPetID: controller.habitatVitalsByPetID,
                maximumPets: PetHabitatState.maximumResidents - (controller.habitat.configuration.leadDynamicIslandPetID == nil ? 0 : 1)
            ) {
                if controller.saveHabitat(theme: draftTheme, residentPetIDs: draftResidentIDs) {
                    showsHabitatEditor = false
                    return true
                }
                return false
            }
        }
        .sheet(isPresented: $showsIslandSetup) {
            IslandSetupView(controller: controller)
        }
        .fullScreenCover(isPresented: $controller.showsPlayYard) {
            PlayYardView(
                pets: controller.habitatResidents.isEmpty ? [controller.profile] : controller.habitatResidents,
                hapticsEnabled: controller.settings.hapticsEnabled
            )
        }
    }

    private var habitat: some View {
        HabitatEditorCanvas(
            theme: controller.habitat.configuration.theme,
            pets: controller.habitatResidents,
            vitalsByPetID: controller.habitatVitalsByPetID,
            petScale: 1.2
        )
        .frame(height: 240)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Enclosure", systemImage: "leaf")
                    .font(.caption.weight(.medium))
                Text(verbatim: "\(themeTitle) · \(controller.habitatResidents.count)/\(PetHabitatState.maximumResidents)")
                    .font(.caption2)
            }
            .foregroundStyle(PetDesign.secondary)
            .padding(10)
            .background {
                if controller.habitat.configuration.theme.isVivid {
                    RoundedRectangle(cornerRadius: 14).fill(.regularMaterial)
                }
            }
            .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                draftResidentIDs = controller.habitat.configuration.residentPetIDs
                draftTheme = controller.habitat.configuration.theme
                showsHabitatEditor = true
            } label: {
                Image(systemName: "paintpalette")
                    .font(.subheadline)
                    .frame(width: 44, height: 44)
                    .background(PetDesign.surface.opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit enclosure")
            .padding(12)
        }
    }

    private var residentSummary: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(controller.habitatResidents.isEmpty ? String(localized: "A quiet moment") :
                     controller.habitatResidents.map(\.name).joined(separator: ", "))
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Text(controller.habitatResidents.isEmpty ? "Your pet is keeping you company." : "Tap a pet to say hello.")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "heart").foregroundStyle(PetDesign.secondary)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private var placementCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                Task {
                    await controller.placePet(in: controller.placement == .dynamicIsland ? .enclosure : .dynamicIsland)
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: controller.placement == .dynamicIsland ? "house" : "iphone")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(PetDesign.soft, in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 5) {
                        if controller.placement == .dynamicIsland {
                            Text("Bring \(controller.profile.name) home")
                                .font(.subheadline.weight(.medium))
                            Text("Back to the enclosure")
                                .font(.caption).foregroundStyle(PetDesign.secondary)
                        } else {
                            Text("Take \(controller.profile.name) with you")
                                .font(.subheadline.weight(.medium))
                            Text("Move to Dynamic Island")
                                .font(.caption).foregroundStyle(PetDesign.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if controller.isBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.up.right").font(.subheadline) }
                }
                .padding(16)
                .petSurface(radius: 20)
            }
            .buttonStyle(.plain)
            .disabled(controller.isBusy)

            if controller.placement == .dynamicIsland {
                liveActivityStatus.font(.caption)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var liveActivityStatus: some View {
        switch controller.liveActivityConnection {
        case .active:
            Label("\(controller.profile.name) is on Dynamic Island", systemImage: "checkmark.circle.fill")
                .foregroundStyle(PetDesign.secondary)
        case .stale:
            Label("\(controller.profile.name) is sleeping on Dynamic Island", systemImage: "moon.zzz.fill")
                .foregroundStyle(.secondary)
        case .starting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Taking your pet with you…")
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

    private var themeTitle: String {
        switch controller.habitat.configuration.theme {
        case .meadow: String(localized: "Meadow")
        case .cozyRoom: String(localized: "Cozy room")
        case .moonlitGarden: String(localized: "Starlight")
        case .arcticCove: String(localized: "Arctic cove")
        case .desertCamp: String(localized: "Desert camp")
        case .sunnyMeadow: String(localized: "Sunny meadow")
        case .starryNight: String(localized: "Starry night")
        case .warmRoom: String(localized: "Warm cottage")
        case .snowyCove: String(localized: "Snowy cove")
        case .sunsetDunes: String(localized: "Sunset dunes")
        }
    }
}

private struct IslandSetupView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Dynamic Island") {
                    Picker("Pet mode", selection: motionModeBinding) {
                        ForEach(DynamicIslandMotionMode.allCases) { mode in
                            Text(motionModeTitle(mode)).tag(mode)
                        }
                    }

                    Picker("Time on the island", selection: durationBinding) {
                        ForEach(SessionPreset.allCases) { preset in
                            Text(durationTitle(preset.rawValue)).tag(preset.rawValue)
                        }
                    }

                    if controller.session != nil {
                        Text("New settings will apply the next time the pet enters Dynamic Island.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        LiveActivityColorEditor(controller: controller)
                    } label: {
                        HStack {
                            Text("Card color")
                            Spacer()
                            Circle()
                                .fill(PetActivityAppearance(background: controller.settings.liveActivityBackgroundColor).backgroundColor)
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                                .accessibilityHidden(true)
                        }
                    }
                } header: {
                    Text("Live Activity appearance")
                } footer: {
                    Text("Customize the pet card on the Lock Screen. This does not change Dynamic Island.")
                }

                Section("Home Screen widget") {
                    Label("Add the medium Enclosure widget", systemImage: "square.grid.2x2.fill")
                    Text("Hold an empty area on the Home Screen, tap +, find Pet Island and choose Enclosure.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .petPage()
            .navigationTitle("Island setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
}

private struct LiveActivityColorEditor: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PetColorSelection?
    @State private var isSaving = false
    @State private var saveFailed = false

    init(controller: PetSessionController) {
        self.controller = controller
        _draft = State(initialValue: controller.settings.liveActivityBackgroundColor)
    }

    private var appearance: PetActivityAppearance { PetActivityAppearance(background: draft) }

    private let presets: [(name: LocalizedStringKey, color: PetColorSelection)] = [
        ("Graphite", .init(red: 0.15, green: 0.17, blue: 0.21)),
        ("Moonlight", .init(red: 0.86, green: 0.89, blue: 0.94)),
        ("Warm sand", .init(red: 0.95, green: 0.87, blue: 0.75)),
        ("Lilac", .init(red: 0.74, green: 0.68, blue: 0.88)),
        ("Blue hour", .init(red: 0.15, green: 0.27, blue: 0.44))
    ]

    var body: some View {
        Form {
            Section("Preview") {
                VStack(spacing: 8) {
                    HStack {
                        Label(controller.profile.name, systemImage: "pawprint.fill")
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Label("Resting", systemImage: "moon.zzz.fill")
                            .font(.caption.bold())
                    }
                    PetArtwork(
                        species: controller.profile.species,
                        coat: controller.profile.coat,
                        customColor: controller.profile.customColor,
                        breed: controller.profile.breed,
                        pose: .sleep,
                        animatesMotion: false
                    )
                    .frame(width: 84, height: 72)
                    .frame(maxWidth: .infinity)
                    Capsule()
                        .fill(appearance.foregroundColor.opacity(0.12))
                        .frame(height: 4)
                }
                .foregroundStyle(appearance.foregroundColor)
                .padding(14)
                .background(appearance.backgroundColor, in: RoundedRectangle(cornerRadius: 22))
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                HStack(spacing: 12) {
                    ForEach(presets.indices, id: \.self) { index in
                        let preset = presets[index]
                        let palette = PetActivityAppearance(background: preset.color)
                        Button { draft = preset.color } label: {
                            Circle()
                                .fill(palette.backgroundColor)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                                .overlay {
                                    if draft == preset.color {
                                        Image(systemName: "checkmark")
                                            .font(.body.bold())
                                            .foregroundStyle(palette.foregroundColor)
                                    }
                                }
                                .frame(height: 44)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.name)
                        .accessibilityAddTraits(draft == preset.color ? .isSelected : [])
                    }
                }
                ColorPicker("Choose any color", selection: colorBinding, supportsOpacity: false)
                Button("Use default color") { draft = nil }
                    .disabled(draft == nil)
            } header: {
                Text("Card color")
            } footer: {
                Text("Text adjusts automatically. Save to update the current Live Activity and future sessions.")
            }

            if saveFailed {
                Text("Your changes could not be saved. Please try again.")
                    .foregroundStyle(.red)
            }
        }
        .disabled(isSaving)
        .scrollContentBackground(.hidden)
        .petPage()
        .navigationTitle("Card color")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSaving)
        .navigationBarBackButtonHidden(isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    isSaving = true
                    Task {
                        let saved = await controller.updateLiveActivityBackgroundColor(draft)
                        isSaving = false
                        saveFailed = !saved
                        if saved { dismiss() }
                    }
                }
                .disabled(isSaving)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { appearance.backgroundColor },
            set: { color in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                      let components = UIColor(color).cgColor.converted(
                        to: space, intent: .defaultIntent, options: nil
                      )?.components, components.count >= 3 else { return }
                draft = PetColorSelection(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
            }
        )
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
