import ActivityKit
import SwiftUI

struct ContentView: View {
    @StateObject private var controller = PetSessionController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-release-support-preview") {
#if targetEnvironment(simulator)
            AuthorSupportPreviewHost()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-release-privacy-preview") {
#if targetEnvironment(simulator)
            SupportPrivacyView()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-home-clarity-preview") {
#if targetEnvironment(simulator)
            HomeClarityDebugHostView()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-enclosure-editor-preview") {
#if targetEnvironment(simulator)
            HabitatEditorDebugHostView()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-furniture-clarity-preview") {
#if targetEnvironment(simulator)
            HabitatFurnitureDebugHostView()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-settings-clarity-preview") {
#if targetEnvironment(simulator)
            SettingsClarityDebugHostView()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-onboarding-preview") {
#if targetEnvironment(simulator)
            PetOnboardingDebugHostView()
#else
            appContent
#endif
        } else if ProcessInfo.processInfo.arguments.contains("-habitat-encounter-preview") {
            HabitatEncounterDebugHost()
        } else if ProcessInfo.processInfo.arguments.contains("-pet-profile-preview") {
            PetProfileDebugHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-discovery-scene-preview") {
            PetDiscoverySceneDebugHost()
        } else if ProcessInfo.processInfo.arguments.contains("-arcade-preview") {
            MiniGamesDebugHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-color-preview") {
            PetColorDebugView()
        } else if ProcessInfo.processInfo.arguments.contains("-sprite-preview") {
            DynamicIslandSpritePreview()
        } else if ProcessInfo.processInfo.arguments.contains("-live-activity-recovery-test") {
            LiveActivityRecoveryHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-pet-live-activity-smoke-test") {
            PetLiveActivitySmokeHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-live-activity-smoke-test") {
            LiveActivitySmokeHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-playroom-preview") {
            let pets = ProcessInfo.processInfo.arguments.contains("-playroom-bird-preview")
                ? Array(Self.previewParty.suffix(3))
                : Self.previewParty
            PlayYardView(pets: pets)
        } else if ProcessInfo.processInfo.arguments.contains("-settings-preview") {
            HomeDebugHostView(showsSettings: true)
        } else if ProcessInfo.processInfo.arguments.contains("-home-preview") || ProcessInfo.processInfo.arguments.contains("-design-preview") {
            HomeDebugHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-collection-preview") {
            PetCollectionDebugPreview()
        } else {
            appContent
        }
#else
        appContent
#endif
    }

#if DEBUG
    fileprivate static var previewParty: [PetProfile] {
        if ProcessInfo.processInfo.arguments.contains("-new-pets-preview") {
            let cast: [(String, PetSpecies, PetBreed)] = [
                ("Лев", .lion, .adultLion), ("Львица", .lion, .lioness),
                ("Львёнок", .lion, .lionCub), ("Кардиган", .dog, .cardigan)
            ]
            return cast.map { name, species, breed in
                PetProfile(id: UUID(), name: name, species: species, coat: .sunrise, createdAt: .now, breed: breed)
            }
        }
        return [
            PetProfile(
                id: UUID(), name: "Мейн-кун", species: .cat, coat: .sunrise,
                createdAt: .now, breed: .maineCoon
            ),
            PetProfile(
                id: UUID(), name: "Овчарка", species: .dog, coat: .sunrise,
                createdAt: .now, breed: .shepherd
            ),
            PetProfile(
                id: UUID(), name: "Корги", species: .dog, coat: .sunrise,
                createdAt: .now, breed: .corgi
            ),
            PetProfile(
                id: UUID(), name: "Пингвин", species: .penguin, coat: .cloud,
                createdAt: .now, breed: .classicPenguin
            ),
            PetProfile(
                id: UUID(), name: "Кеша", species: .parrot, coat: .sunrise,
                createdAt: .now, breed: .macaw
            )
        ]
    }
#endif

    private var appContent: some View {
        Group {
            if controller.operation == .loading {
                ProgressView("Preparing your island…")
                    .controlSize(.large)
            } else if controller.operation == .loadFailed {
                ContentUnavailableView {
                    Label("Your island needs a moment", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("We couldn’t read your saved island. Your files have been kept. Try again after unlocking your iPhone.")
                } actions: {
                    Button("Try again") { Task { await controller.bootstrap() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                HomeView(controller: controller)
            }
        }
        .task { await controller.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await controller.sceneBecameActive() }
            case .background:
                Task { await controller.sceneEnteredBackground() }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onOpenURL { controller.handleDeepLink($0) }
        .fullScreenCover(
            isPresented: Binding(
                get: { controller.operation != .loading && controller.operation != .loadFailed && !controller.completedOnboarding },
                set: { _ in }
            )
        ) {
            OnboardingView(controller: controller)
        }
        .alert(
            "Pet Island",
            isPresented: Binding(
                get: { controller.alertMessage != nil },
                set: { if !$0 { controller.alertMessage = nil } }
            )
        ) {
            Button("OK") { controller.alertMessage = nil }
        } message: {
            Text(controller.alertMessage ?? "")
        }
        .preferredColorScheme(controller.settings.appearance.colorScheme)
        .environment(\.petMinimizeMotion, controller.settings.minimizeMotion)
    }
}

private extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

#if DEBUG
private struct HomeDebugHostView: View {
    @StateObject private var controller: PetSessionController
    @State private var preparedPreviewHabitat = false
    let showsSettings: Bool

    init(showsSettings: Bool = false) {
        self.showsSettings = showsSettings
        var state = PersistedAppState()
        state.completedOnboarding = true
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-design-preview") {
            let cat = PetProfile(id: UUID(), name: "Pixel", species: .cat, coat: .sunrise, createdAt: .now, breed: .maineCoon)
            let fox = PetProfile(id: UUID(), name: "Лис", species: .fox, coat: .sunrise, createdAt: .now, breed: .redFox)
            let bird = PetProfile(id: UUID(), name: "Кеша", species: .parrot, coat: .sunrise, createdAt: .now, breed: .cockatiel)
            state.pets = [cat, fox, bird]
            if arguments.contains("-design-crowded") {
                state.pets = ContentView.previewParty + [fox]
            }
            state.activePetIDs = state.pets.map(\.id)
        }
        if arguments.contains("-design-dark") { state.settings.appearance = .dark }
        if arguments.contains("-new-pets-preview") {
            state.pets = ContentView.previewParty
            state.activePetIDs = state.pets.map(\.id)
        }
        if arguments.contains("-design-light") { state.settings.appearance = .light }
        _controller = StateObject(
            wrappedValue: PetSessionController(
                store: InMemoryPetStore(state),
                arcadeStore: InMemoryArcadeStore()
            )
        )
    }

    var body: some View {
        Group {
            if showsSettings {
                SettingsView(controller: controller, showsDismissButton: false)
            } else if controller.operation == .loadFailed {
                ContentUnavailableView {
                    Label("Your island needs a moment", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text("We couldn’t read your saved island. Your files have been kept. Try again after unlocking your iPhone.")
                } actions: {
                    Button("Try again") { Task { await controller.bootstrap() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                HomeView(controller: controller)
            }
        }
        .task {
            await controller.bootstrap()
            let arguments = ProcessInfo.processInfo.arguments
            preparePreviewHabitat()
            if arguments.contains("-design-pets") { controller.selectedTab = .pets }
            if arguments.contains("-design-arcade") { controller.selectedTab = .arcade }
            if arguments.contains("-design-settings") { controller.selectedTab = .settings }
        }
        .preferredColorScheme(controller.settings.appearance.colorScheme)
        .environment(\.petMinimizeMotion, controller.settings.minimizeMotion)
        .onChange(of: controller.isBusy) { _, busy in
            // Wait for all bootstrap writes before installing the QA cast.
            if !busy { preparePreviewHabitat() }
        }
    }

    private func preparePreviewHabitat() {
        guard !preparedPreviewHabitat,
              ProcessInfo.processInfo.arguments.contains("-design-preview"),
              !controller.isBusy else { return }
        preparedPreviewHabitat = controller.saveHabitat(theme: .meadow, residentPetIDs: controller.pets.map(\.id))
    }
}

private struct PetColorDebugView: View {
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(PetSpecies.allCases) { species in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(species.displayName)
                                .font(.headline)

                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(PetCoat.allCases) { coat in
                                    VStack(spacing: 4) {
                                        PetArtwork(
                                            species: species,
                                            coat: coat,
                                            breed: PetBreed.defaultVariant(for: species),
                                            pose: species == .parrot ? .fly : .idle,
                                            animatesMotion: false
                                        )
                                        .frame(height: 58)

                                        Text(coat.displayName)
                                            .font(.caption2.bold())
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pet colors")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LiveActivityRecoveryHostView: View {
    @StateObject private var controller: PetSessionController
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let now = Date.now
        let pet = PetProfile(
            id: UUID(), name: "Рыжик", species: .fox, coat: .sunrise,
            createdAt: now
        )
        let parrot = PetProfile(
            id: UUID(), name: "Кеша", species: .parrot, coat: .cloud,
            createdAt: now
        )
        let dog = PetProfile(
            id: UUID(), name: "Дружок", species: .dog, coat: .sunrise,
            createdAt: now
        )
        let snapshot = PetBehaviorMachine().initialSnapshot(for: dog.species, at: now)
        var state = PersistedAppState()
        state.pets = [dog, pet, parrot]
        state.activePetIDs = [dog.id, pet.id, parrot.id]
        state.activeSession = PetSession(
            id: UUID(), petID: dog.id, startedAt: now,
            endsAt: now.addingTimeInterval(20 * 60), snapshot: snapshot
        )
        state.completedOnboarding = true
        _controller = StateObject(
            wrappedValue: PetSessionController(store: InMemoryPetStore(state))
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            PetArtwork(species: .dog, pose: .idle)
                .frame(width: 80, height: 68)
            Text("Live Activity recovery test")
                .font(.title2.bold())
            Text(String(describing: controller.liveActivityConnection))
                .font(.body.monospaced())
            Text("A persisted app session started without an ActivityKit activity.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .task { await controller.bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            Task { await controller.sceneEnteredBackground() }
        }
    }
}

private struct PetLiveActivitySmokeHostView: View {
    @State private var status = "Preparing…"
    @State private var activity: Activity<PetActivityAttributes>?

    private var qaSpecies: PetSpecies {
        argumentValue(after: "-qa-species").flatMap(PetSpecies.init(rawValue:)) ?? .parrot
    }

    private var qaBreed: PetBreed? {
        guard let rawValue = argumentValue(after: "-qa-breed"),
              let breed = PetBreed(rawValue: rawValue),
              PetBreed.available(for: qaSpecies).contains(breed) else {
            return PetBreed.defaultVariant(for: qaSpecies)
        }
        return breed
    }

    private var qaMode: DynamicIslandMotionMode {
        argumentValue(after: "-qa-mode").flatMap(DynamicIslandMotionMode.init(rawValue:)) ?? .run
    }

    var body: some View {
        VStack(spacing: 16) {
            PetArtwork(
                species: qaSpecies,
                breed: qaBreed,
                pose: qaMode.initialPose(for: qaSpecies),
                step: 1
            )
                .frame(width: 80, height: 68)
            Text("Pet Live Activity smoke test")
                .font(.title2.bold())
            HStack {
                Button("Light background") {
                    Task { await updateBackground(.init(red: 0.86, green: 0.89, blue: 0.94)) }
                }
                Button("Dark background") {
                    Task { await updateBackground(.init(red: 0.15, green: 0.27, blue: 0.44)) }
                }
                Button("Default background") {
                    Task { await updateBackground(nil) }
                }
            }
            .buttonStyle(.bordered)
            Text(status)
                .font(.body.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(24)
        .task { await startPetActivity() }
    }

    @MainActor
    private func updateBackground(_ color: PetColorSelection?) async {
        guard let activity else { return }
        var state = activity.content.state
        state.backgroundColor = color
        await activity.update(ActivityContent(state: state, staleDate: activity.attributes.endsAt))
    }

    @MainActor
    private func startPetActivity() async {
        for existing in Activity<LiveActivitySmokeAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        for existing in Activity<PetActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "ActivityKit authorization: disabled"
            return
        }

        let now = Date.now
        let endsAt = now.addingTimeInterval(20 * 60)
        let identity = PetActivityIdentity(
            id: UUID(),
            name: qaBreed?.rawValue ?? qaSpecies.rawValue,
            species: qaSpecies,
            coat: .sunrise,
            customColor: nil,
            breed: qaBreed
        )
        do {
            let requested = try Activity.request(
                attributes: PetActivityAttributes(
                    sessionID: UUID(), pet: identity, companions: [],
                    startedAt: now, endsAt: endsAt, motionMode: qaMode
                ),
                content: ActivityContent(
                    state: .init(
                        snapshot: PetSnapshot(
                            pose: qaMode.initialPose(for: qaSpecies),
                            position: 0.35, direction: .right,
                            revision: 1, generatedAt: now
                        ),
                        lastInteraction: nil
                    ),
                    staleDate: endsAt
                ),
                pushType: nil
            )
            activity = requested
            status = "id: \(requested.id)\nstate: \(String(describing: requested.activityState))"
        } catch {
            status = "request failed:\n\(String(reflecting: error))"
        }
    }

    private func argumentValue(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}

private struct LiveActivitySmokeHostView: View {
    @State private var status = "Preparing…"
    @State private var activity: Activity<LiveActivitySmokeAttributes>?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: activity == nil ? "pawprint" : "pawprint.fill")
                .font(.system(size: 52))
                .foregroundStyle(activity == nil ? Color.secondary : Color.cyan)
            Text("Live Activity smoke test")
                .font(.title2.bold())
            Text(status)
                .font(.body.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(24)
        .task { await startSmokeActivity() }
    }

    @MainActor
    private func startSmokeActivity() async {
        for existing in Activity<LiveActivitySmokeAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "ActivityKit authorization: disabled"
            return
        }

        let endsAt = Date.now.addingTimeInterval(20 * 60)
        do {
            let requested = try Activity.request(
                attributes: LiveActivitySmokeAttributes(endsAt: endsAt),
                content: ActivityContent(
                    state: .init(message: "registered"),
                    staleDate: endsAt
                ),
                pushType: nil
            )
            activity = requested
            status = "id: \(requested.id)\nstate: \(String(describing: requested.activityState))"
        } catch {
            status = "request failed:\n\(String(reflecting: error))"
        }
    }
}

private struct PetCollectionDebugPreview: View {
    @StateObject private var controller = PetSessionController(store: InMemoryPetStore())
    @State private var populated = false

    var body: some View {
        PetCollectionView(controller: controller)
            .task {
                await controller.bootstrap()
                guard !populated else { return }
                populated = true
                let party = ContentView.previewParty
                await controller.completeOnboarding(profile: party[0])
                for pet in party.dropFirst() { _ = await controller.addPet(pet) }
            }
    }
}

private struct MiniGamesDebugHostView: View {
    @StateObject private var controller: PetSessionController

    init() {
        let previewParty = ContentView.previewParty
        let party: [PetProfile]
        if ProcessInfo.processInfo.arguments.contains("-arcade-shepherd-preview") {
            party = Array(previewParty.dropFirst()) + [previewParty[0]]
        } else if ProcessInfo.processInfo.arguments.contains("-arcade-parrot-preview"),
                  let parrot = previewParty.last {
            party = [parrot] + Array(previewParty.dropLast())
        } else {
            party = previewParty
        }
        var appState = PersistedAppState()
        appState.pets = party
        appState.activePetIDs = party.map(\.id)
        appState.completedOnboarding = true
        appState.normalizePetCollection()

        let vitals = Dictionary(uniqueKeysWithValues: party.map { pet in
            (pet.id, PetVitals(fullness: 0.7, happiness: 0.82, energy: 0.68))
        })
        let arcade = ArcadeState(
            progress: ArcadeProgress(coins: 42, totalScore: 1_850, gamesPlayed: 5, highScores: [.skyHop: 720]),
            vitalsByPetID: vitals
        )
        _controller = StateObject(
            wrappedValue: PetSessionController(
                store: InMemoryPetStore(appState),
                arcadeStore: InMemoryArcadeStore(arcade)
            )
        )
    }

    var body: some View {
        MiniGamesView(controller: controller)
            .task { await controller.bootstrap() }
    }
}
#endif

#if DEBUG
#Preview("Приложение") {
    ContentView()
}

#Preview("Питомцы Dynamic Island") {
    DynamicIslandSpritePreview()
}

#Preview("Коллекция питомцев") {
    PetCollectionDebugPreview()
}

#Preview("Pet Arcade") {
    MiniGamesDebugHostView()
}
#endif

#if DEBUG
private struct DynamicIslandSpritePreview: View {
    private let profile = PetProfile(
        id: UUID(), name: "Кеша", species: .parrot, coat: .sunrise,
        createdAt: .now, customColor: nil
    )

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                Text("Dynamic Island · actual size")
                    .font(.title2.bold())

                compactIsland

                VStack(spacing: 10) {
                    Text("33 × 28 pt compact sprite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(PetSpecies.selectableCases) { species in
                            PetArtwork(
                                species: species,
                                coat: .sunrise,
                                pose: species == .parrot ? .fly : .idle
                            )
                            .frame(width: 33, height: 28)
                        }
                    }
                    .padding(12)
                    .background(.black, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Expanded Live Activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.12)).frame(height: 4)
                        PetArtwork(
                            species: profile.species,
                            coat: profile.coat,
                            breed: profile.resolvedBreed,
                            pose: .fly,
                            step: 1
                        )
                        .frame(width: 66, height: 58)
                    }
                    .frame(height: 72)
                    .padding(18)
                    .background(.black, in: RoundedRectangle(cornerRadius: 34))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 72)
        }
        .background(Color(.systemGroupedBackground))
        .preferredColorScheme(.dark)
    }

    private var compactIsland: some View {
        HStack(spacing: 8) {
            PetArtwork(species: .parrot, coat: .sunrise, pose: .fly, step: 1)
                .frame(width: 33, height: 28)
            Spacer(minLength: 82)
            Text("19:42")
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(.yellow)
        }
        .padding(.horizontal, 9)
        .frame(width: 230, height: 37)
        .background(.black, in: Capsule())
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Exercises the real editor and persistence on disposable UI-test simulators.
private struct HabitatEditorDebugHostView: View {
    @StateObject private var controller: PetSessionController
    @State private var showsEditor = false
    @State private var draftTheme: HabitatTheme = .meadow
    @State private var draftPetIDs: [UUID] = []
    @State private var hasFailed = false
    private let initialIDs: [UUID]
    private let initialHabitat: SharedPetHabitat

    init() {
        let args = ProcessInfo.processInfo.arguments
        let names = args.contains("-editor-full") ? ["Pixel", "Luna", "Mochi", "Leo", "Kiwi", "Snow", "Sunny"] : ["Pixel", "Luna", "Mochi"]
        var state = PersistedAppState()
        state.completedOnboarding = true
        state.pets = names.enumerated().map { index, name in
            PetProfile(id: UUID(uuidString: "ED000000-0000-0000-0000-00000000000\(index + 1)")!,
                       name: name, species: index == 0 ? .dog : .cat, coat: .sunrise,
                       createdAt: .distantPast, breed: index == 0 ? .corgi : .classicCat)
        }
        state.activePetIDs = [state.pets[0].id]
        let residentIDs = Array(state.pets.prefix(args.contains("-editor-full") ? 6 : 2).map(\.id))
        initialIDs = residentIDs
        initialHabitat = SharedPetHabitat(
            configuration: PetHabitatState(residentPetIDs: residentIDs),
            residents: state.pets.filter { residentIDs.contains($0.id) }.map {
                SharedHabitatResident(profile: $0, vitals: PetVitals())
            }
        )
        if args.contains("-editor-away") {
            state.discoveries.startWalk(pet: state.pets[1], route: .garden, at: .now)
        }
        _controller = StateObject(wrappedValue: PetSessionController(
            store: InMemoryPetStore(state),
            arcadeStore: InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 120, ownedHabitatItems: [.cozyBox])))
        ))
    }

    var body: some View {
        VStack(spacing: 12) {
            Button("Edit enclosure") { openEditor() }.accessibilityIdentifier("editor.fixture.open")
            Button("Reload saved enclosure") {
                Task { await controller.bootstrap() }
            }.accessibilityIdentifier("editor.fixture.reload")
            Text(controller.habitat.configuration.theme.rawValue).accessibilityIdentifier("editor.fixture.theme")
            Text(controller.habitat.configuration.residentPetIDs.compactMap { id in controller.pets.first { $0.id == id }?.name }.joined(separator: ","))
                .accessibilityIdentifier("editor.fixture.residents")
            Text(controller.pets.map(\.name).joined(separator: ",")).accessibilityIdentifier("editor.fixture.pets")
            Text("\(controller.arcadeProgress.coins)").accessibilityIdentifier("editor.fixture.coins")
            Text(controller.habitat.configuration.furniture.map { "\($0.item.rawValue):\($0.slot.rawValue)" }.joined(separator: ","))
                .accessibilityIdentifier("editor.fixture.furniture")
        }
        .sheet(isPresented: $showsEditor) {
            HabitatEditorView(controller: controller, pets: controller.pets,
                              selectedPetIDs: $draftPetIDs, selectedTheme: $draftTheme,
                              unavailablePetIDs: Set(controller.pets.filter { controller.isPetOnDiscoveryWalk($0.id) }.map(\.id)),
                              maximumPets: PetHabitatState.maximumResidents) {
                if !hasFailed, ProcessInfo.processInfo.arguments.contains("-editor-fail-save") {
                    hasFailed = true
                    return false
                }
                if controller.saveHabitat(theme: draftTheme, residentPetIDs: draftPetIDs) {
                    showsEditor = false
                    return true
                }
                return false
            }
        }
        .task {
            guard controller.operation == .loading else { return }
            try? PetHabitatStore.save(initialHabitat)
            await controller.bootstrap()
            _ = controller.saveHabitat(theme: .meadow, residentPetIDs: initialIDs)
            openEditor()
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-editor-light") ? .light : .dark)
        .environment(\.petMinimizeMotion, true)
    }

    private func openEditor() {
        draftTheme = controller.habitat.configuration.theme
        draftPetIDs = controller.habitat.configuration.residentPetIDs
        showsEditor = true
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
/// Uses the real home screen with disposable saved states for UI regression checks.
private struct HomeClarityDebugHostView: View {
    @StateObject private var controller: PetSessionController
    @State private var ready = false
    private let initialHabitat: SharedPetHabitat
    private let initialLife: PetLifeState

    init() {
        let args = ProcessInfo.processInfo.arguments
        var names = args.contains("-home-large") ? ["Пиксель Длиннохвостый", "Луна Пушистая"] :
            args.contains("-home-multiple") ? ["Pixel", "Luna"] : ["Pixel"]
        if args.contains("-home-single") { names = Array(names.prefix(1)) }
        var state = PersistedAppState()
        state.completedOnboarding = true
        state.settings.minimizeMotion = true
        state.pets = names.enumerated().map { index, name in
            PetProfile(id: UUID(uuidString: "AE000000-0000-0000-0000-00000000000\(index + 1)")!,
                       name: name, species: index == 0 ? .dog : .cat, coat: .sunrise,
                       createdAt: .distantPast, breed: index == 0 ? .corgi : .classicCat)
        }
        state.activePetIDs = [state.pets[0].id]
        let withYou = args.contains("-home-with-you")
        if withYou {
            state.activeSession = PetSession(id: UUID(), petID: state.pets[0].id, startedAt: .now,
                                             endsAt: Date.now.addingTimeInterval(3_600), snapshot: .initial(at: .now))
        }
        if args.contains("-home-away") {
            state.discoveries.startWalk(pet: state.pets[0], route: .garden, at: .now)
        }
        let residents = withYou ? Array(state.pets.dropFirst()) : state.pets
        initialHabitat = SharedPetHabitat(
            configuration: PetHabitatState(theme: .sunnyMeadow, residentPetIDs: residents.map(\.id),
                                           leadDynamicIslandPetID: withYou ? state.pets[0].id : nil),
            residents: residents.map { SharedHabitatResident(profile: $0, vitals: PetVitals()) }
        )
        initialLife = PetLifeState(profile: state.pets[0], placement: withYou ? .dynamicIsland : .enclosure)
        _controller = StateObject(wrappedValue: PetSessionController(
            store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(coins: 120)))
        ))
    }

    var body: some View {
        Group {
            if ready { HomeView(controller: controller) }
            else { ProgressView() }
        }
        .task {
            guard !ready else { return }
            try? PetHabitatStore.save(initialHabitat)
            try? PetLifeStore.save(initialLife)
            await controller.bootstrap()
            ready = true
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-home-large") ? .light : .dark)
        .environment(\.petMinimizeMotion, true)
    }
}
#endif
