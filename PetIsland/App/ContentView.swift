import ActivityKit
import SwiftUI

struct ContentView: View {
    @StateObject private var controller = PetSessionController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-arcade-preview") {
            MiniGamesDebugHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-sprite-preview") {
            DynamicIslandSpritePreview()
        } else if ProcessInfo.processInfo.arguments.contains("-live-activity-recovery-test") {
            LiveActivityRecoveryHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-pet-live-activity-smoke-test") {
            PetLiveActivitySmokeHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-live-activity-smoke-test") {
            LiveActivitySmokeHostView()
        } else if ProcessInfo.processInfo.arguments.contains("-playroom-preview") {
            PlayYardView(pets: Self.previewParty)
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
        [
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
                get: { controller.operation != .loading && !controller.completedOnboarding },
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
    }
}

#if DEBUG
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
            Text(status)
                .font(.body.monospaced())
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(24)
        .task { await startPetActivity() }
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
                _ = await controller.addPet(party[1])
                _ = await controller.addPet(party[2])
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
                    Text("29 × 25 pt compact sprite")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        ForEach(PetSpecies.selectableCases) { species in
                            PetArtwork(
                                species: species,
                                coat: .sunrise,
                                pose: species == .parrot ? .fly : .idle
                            )
                            .frame(width: 29, height: 25)
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
                .frame(width: 29, height: 25)
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
