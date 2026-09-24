import ActivityKit
import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class PetSessionController: ObservableObject {
    enum Operation: Equatable {
        case loading
        case loadFailed
        case idle
        case starting
        case active
        case stopping
    }

    enum LiveActivityConnection: Equatable {
        case unavailable
        case inactive
        case starting
        case active
        case stale
        case dismissed
        case failed

        var isConnected: Bool { self == .active || self == .stale }
    }

    @Published private(set) var operation: Operation = .loading
    @Published private(set) var profile: PetProfile = .starter
    @Published private(set) var pets: [PetProfile] = []
    @Published private(set) var activePetIDs: [UUID] = []
    @Published private(set) var activeParty: [PetProfile] = []
    @Published private(set) var session: PetSession?
    @Published private(set) var history = PetHistory()
    @Published var settings = AppSettings()
    @Published var completedOnboarding = false
    @Published var alertMessage: String?
    @Published var showsSessionComposer = false
    @Published var showsPetEditor = false
    @Published var showsSettings = false
    @Published var showsSessionSummary = false
    @Published var selectedTab: AppTab = .island
    @Published var showsPlayYard = false
    @Published private(set) var liveActivitiesEnabled = true
    @Published private(set) var liveActivityConnection: LiveActivityConnection = .inactive
    @Published private(set) var placement: PetPlacement = .enclosure
    @Published private(set) var lifeState = PetLifeState.initial()
    @Published private(set) var habitat = SharedPetHabitat.initial()
    @Published private(set) var arcadeProgress = ArcadeProgress()

    private let store: any PetStore
    private let arcadeStore: any ArcadeStore
    private let behavior = PetBehaviorMachine()
    private var activity: Activity<PetActivityAttributes>?
    private var state = PersistedAppState()
    private var arcadeState = ArcadeState()
    private var expiryTask: Task<Void, Never>?
    private var activityObservationTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var didBootstrap = false
    private var bootstrapTask: Task<Void, Never>?
    private var shouldReconnectMissingActivity = false
    @Published private(set) var isSavingChanges = false
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        store: any PetStore = FilePetStore(),
        arcadeStore: any ArcadeStore = FileArcadeStore()
    ) {
        self.store = store
        self.arcadeStore = arcadeStore
    }

    var isBusy: Bool { isSavingChanges || operation == .starting || operation == .stopping || operation == .loading || operation == .loadFailed }

    func bootstrap() async {
        if let bootstrapTask {
            await bootstrapTask.value
            return
        }
        let task = Task { await self.performBootstrap() }
        bootstrapTask = task
        await task.value
        bootstrapTask = nil
    }

    private func performBootstrap() async {
        guard operation != .starting, operation != .stopping, !isSavingChanges else { return }
        await beginSave()
        defer { finishSave() }
        if !didBootstrap {
            operation = .loading
            do {
                let loadedState = try await store.load()
                let loadedArcade = try await arcadeStore.load()
                state = loadedState
                arcadeState = loadedArcade
            } catch {
                operation = .loadFailed
                return
            }
            arcadeState.reconcile(with: state.pets)
            _ = await flushCareEvents()
            arcadeState.mergeVitals(from: PetHabitatStore.load())
            publishPetCollection()
            synchronizeSharedLifeState()
            synchronizeSharedHabitat()
            history = state.history
            settings = state.settings
            completedOnboarding = state.completedOnboarding
            didBootstrap = true
            observeAuthorization()
            await persist()
            _ = await commitArcade(arcadeState)
        }
        _ = await flushCareEvents()
        reloadSharedLifeState()
        if placement == .dynamicIsland {
            await reconcileActivities(at: .now)
        } else {
            await clearLiveActivityState()
        }
    }

    @discardableResult
    func completeOnboarding(profile newProfile: PetProfile) async -> Bool {
        await beginSave()
        defer { finishSave() }
        var profile = newProfile
        profile.normalizeName()
        var candidate = state
        candidate.pets = [profile]
        candidate.activePetIDs = [profile.id]
        candidate.completedOnboarding = true
        return await commitState(candidate)
    }

    @discardableResult
    func updateProfile(_ newProfile: PetProfile) async -> Bool {
        await updatePet(newProfile)
    }

    @discardableResult
    func addPet(_ newPet: PetProfile) async -> Bool {
        await beginSave()
        defer { finishSave() }
        guard !state.pets.contains(where: { $0.id == newPet.id }), state.pets.count < 12 else { return false }
        var normalized = newPet
        normalized.normalizeName()
        var candidate = state
        candidate.pets.append(normalized)
        if session == nil, candidate.activePetIDs.count < PersistedAppState.maximumActivePets {
            candidate.activePetIDs.append(normalized.id)
        }
        return await commitState(candidate)
    }

    @discardableResult
    func updatePet(_ updatedPet: PetProfile) async -> Bool {
        await beginSave()
        defer { finishSave() }
        guard session?.petID != updatedPet.id,
              let index = state.pets.firstIndex(where: { $0.id == updatedPet.id }) else { return false }
        var normalized = updatedPet
        normalized.normalizeName()
        var candidate = state
        candidate.pets[index] = normalized
        return await commitState(candidate)
    }

    @discardableResult
    func removePet(id: UUID) async -> Bool {
        await beginSave()
        defer { finishSave() }
        guard state.pets.count > 1, state.pets.contains(where: { $0.id == id }),
              session?.petID != id else { return false }
        var candidate = state
        candidate.pets.removeAll { $0.id == id }
        candidate.activePetIDs.removeAll { $0 == id }
        return await commitState(candidate)
    }

    @discardableResult
    func togglePetActive(id: UUID) async -> Bool {
        await beginSave()
        defer { finishSave() }
        guard session == nil, state.pets.contains(where: { $0.id == id }) else { return false }
        var candidate = state
        if let index = candidate.activePetIDs.firstIndex(of: id) {
            guard candidate.activePetIDs.count > 1 else { return false }
            candidate.activePetIDs.remove(at: index)
        } else {
            guard candidate.activePetIDs.count < PersistedAppState.maximumActivePets else { return false }
            candidate.activePetIDs.append(id)
        }
        return await commitState(candidate)
    }

    @discardableResult
    func makeLeadPet(id: UUID) async -> Bool {
        await beginSave()
        defer { finishSave() }
        guard session == nil, state.pets.contains(where: { $0.id == id }) else { return false }
        var candidate = state
        candidate.activePetIDs.removeAll { $0 == id }
        candidate.activePetIDs.insert(id, at: 0)
        candidate.activePetIDs = Array(candidate.activePetIDs.prefix(PersistedAppState.maximumActivePets))
        return await commitState(candidate)
    }

    @discardableResult
    func updateSettings(_ newSettings: AppSettings) async -> Bool {
        await beginSave()
        defer { finishSave() }
        var candidate = state
        candidate.settings = newSettings
        return await commitState(candidate, syncPets: false)
    }

    func updateDynamicIslandSettings(mode: DynamicIslandMotionMode? = nil, durationMinutes: Int? = nil) async {
        await beginSave()
        defer { finishSave() }
        var candidate = state
        if let mode { candidate.settings.dynamicIslandMotionMode = mode }
        if let durationMinutes { candidate.settings.defaultSessionMinutes = min(max(durationMinutes, 20), 240) }
        _ = await commitState(candidate, syncPets: false)
    }

    @discardableResult
    func updateLiveActivityBackgroundColor(_ color: PetColorSelection?) async -> Bool {
        await beginSave()
        defer { finishSave() }
        var candidate = state
        candidate.settings.liveActivityBackgroundColor = color
        return await commitState(candidate, syncPets: false)
    }

    private func beginSave() async {
        if isSavingChanges {
            await withCheckedContinuation { saveWaiters.append($0) }
        } else {
            isSavingChanges = true
        }
    }

    private func finishSave() {
        if saveWaiters.isEmpty { isSavingChanges = false }
        else { saveWaiters.removeFirst().resume() }
    }

    private func commitState(_ candidate: PersistedAppState, syncPets: Bool = true) async -> Bool {
        do { try await store.save(candidate) }
        catch {
            alertMessage = String(localized: "Your changes could not be saved. Please try again.")
            return false
        }
        let activityColorChanged = settings.liveActivityBackgroundColor != candidate.settings.liveActivityBackgroundColor
        state = candidate
        settings = candidate.settings
        completedOnboarding = candidate.completedOnboarding
        publishPetCollection()
        if syncPets {
            synchronizeSharedLifeState()
            synchronizeSharedHabitat()
        }
        if activityColorChanged, let activity {
            var content = activity.content.state
            content.backgroundColor = settings.liveActivityBackgroundColor
            await activity.update(ActivityContent(state: content, staleDate: activity.attributes.endsAt))
        }
        return true
    }

    var habitatResidents: [PetProfile] {
        let residentsByID = Dictionary(uniqueKeysWithValues: habitat.residents.map { ($0.id, $0.profile) })
        return habitat.configuration.residentPetIDs.compactMap { residentsByID[$0] }
    }

    var habitatVitalsByPetID: [UUID: PetVitals] {
        Dictionary(uniqueKeysWithValues: state.pets.map { ($0.id, vitals(for: $0.id)) })
    }

    func vitals(for petID: UUID, at date: Date = .now) -> PetVitals {
        (arcadeState.vitalsByPetID[petID] ?? PetVitals()).projected(
            from: arcadeState.vitalsUpdatedAtByPetID[petID] ?? .distantPast, to: date)
    }

    func completeMiniGame(
        _ game: MiniGameKind, score: Int, petID: UUID, at date: Date = .now,
        runID: UUID = UUID()
    ) async -> ArcadePayout? {
        await beginSave()
        defer { finishSave() }
        if let saved = arcadeState.completedRuns.first(where: { $0.id == runID }) { return saved.payout }
        guard state.pets.contains(where: { $0.id == petID }), await flushCareEvents() else { return nil }
        arcadeState.mergeVitals(from: PetHabitatStore.load())
        var candidate = arcadeState
        let currentVitals = vitals(for: petID, at: date)
        let payout = candidate.progress.record(game: game, score: score,
                                               wasTired: currentVitals.energy < ArcadeEconomy.tiredEnergyThreshold,
                                               at: date)
        let event = PetCareEvent(petID: petID, fullness: -0.02, happiness: 0.08, energy: -0.055, date: date)
        candidate.vitalsByPetID[petID] = event.applying(to: currentVitals)
        candidate.vitalsUpdatedAtByPetID[petID] = date
        candidate.pendingCareEvents.append(event)
        candidate.completedRuns.append(CompletedArcadeRun(id: runID, payout: payout))
        candidate.completedRuns = Array(candidate.completedRuns.suffix(128))
        guard await commitArcade(candidate) else { return nil }
        _ = await flushCareEvents()
        Haptics.success(enabled: settings.hapticsEnabled)
        return payout
    }

    func purchaseArcadeItem(_ item: ArcadeItemKind) async -> Bool {
        await beginSave()
        defer { finishSave() }
        var candidate = arcadeState
        guard candidate.progress.purchase(item), await commitArcade(candidate) else { return false }
        Haptics.success(enabled: settings.hapticsEnabled)
        return true
    }

    func useArcadeItem(_ item: ArcadeItemKind, for petID: UUID) async -> Bool {
        await beginSave()
        defer { finishSave() }
        guard state.pets.contains(where: { $0.id == petID }), await flushCareEvents() else { return false }
        arcadeState.mergeVitals(from: PetHabitatStore.load())
        var candidate = arcadeState
        guard candidate.progress.consume(item) else { return false }
        let neutral = PetVitals(fullness: 0.5, happiness: 0.5, energy: 0.5)
        let effect = ArcadeEconomy.vitals(neutral, afterUsing: item)
        let event = PetCareEvent(petID: petID, fullness: effect.fullness - 0.5,
                                 happiness: effect.happiness - 0.5, energy: effect.energy - 0.5, date: .now)
        candidate.vitalsByPetID[petID] = event.applying(to: vitals(for: petID))
        candidate.vitalsUpdatedAtByPetID[petID] = event.date
        candidate.pendingCareEvents.append(event)
        guard await commitArcade(candidate) else { return false }
        _ = await flushCareEvents()
        Haptics.success(enabled: settings.hapticsEnabled)
        return true
    }

    private func commitArcade(_ candidate: ArcadeState) async -> Bool {
        do { try await arcadeStore.save(candidate) }
        catch {
            alertMessage = String(localized: "Arcade progress could not be saved. Please try again.")
            return false
        }
        arcadeState = candidate
        arcadeProgress = candidate.progress
        return true
    }

    /// The local commit contains both the reward and an outbox. A failed shared
    /// write can be replayed after launch without losing or duplicating care.
    private func flushCareEvents() async -> Bool {
        guard !arcadeState.pendingCareEvents.isEmpty else { return true }
        do {
            let events = arcadeState.pendingCareEvents
            habitat = try PetHabitatStore.update { shared in
                for event in events { shared.apply(event) }
            }
            var acknowledged = arcadeState
            for resident in habitat.residents {
                acknowledged.vitalsByPetID[resident.id] = resident.vitals
                acknowledged.vitalsUpdatedAtByPetID[resident.id] = resident.vitalsUpdatedAt
            }
            acknowledged.pendingCareEvents = []
            guard await commitArcade(acknowledged) else { return false }
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
            return true
        } catch {
            alertMessage = String(localized: "Pet rewards are saved and will sync when the enclosure is available.")
            return false
        }
    }

    /// Saves the enclosure composition and theme as one atomic App Group
    /// snapshot, so the Home Screen widget observes a consistent update.
    @discardableResult
    func saveHabitat(theme: HabitatTheme, residentPetIDs: [UUID]) -> Bool {
        guard !isBusy else { return false }
        do {
            habitat = try PetHabitatStore.update { shared in
                shared.configuration.setTheme(theme)
                shared.configuration.setResidents(residentPetIDs)
                let selected = Set(shared.configuration.residentPetIDs)
                shared.residents = state.pets.compactMap { pet in
                    guard selected.contains(pet.id) else { return nil }
                    if var existing = shared.residents.first(where: { $0.id == pet.id }) {
                        existing.profile = pet
                        return existing
                    }
                    return SharedHabitatResident(
                        profile: pet,
                        vitals: arcadeState.vitalsByPetID[pet.id] ?? PetVitals(),
                        vitalsUpdatedAt: arcadeState.vitalsUpdatedAtByPetID[pet.id] ?? .distantPast
                    )
                }
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
            Haptics.success(enabled: settings.hapticsEnabled)
            return true
        } catch {
            alertMessage = String(localized: "The enclosure could not be saved.")
            return false
        }
    }

    func startSession(duration: TimeInterval) async {
        guard operation == .idle, !isSavingChanges else { return }
        await beginSave()
        defer { finishSave() }
        operation = .starting
        let now = Date.now
        let clampedDuration = duration.isFinite ? min(max(duration, 10 * 60), 8 * 60 * 60) : 20 * 60
        let party = activeParty.isEmpty ? [profile] : activeParty
        let leadPet = party[0]
        var snapshot = behavior.initialSnapshot(for: leadPet.species, at: now)
        snapshot.pose = settings.dynamicIslandMotionMode.initialPose(for: leadPet.species)
        let newSession = PetSession(
            id: UUID(), petID: leadPet.id, startedAt: now,
            endsAt: now.addingTimeInterval(clampedDuration), snapshot: snapshot
        )

        for existing in Activity<PetActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        shouldReconnectMissingActivity = true
        guard requestLiveActivity(for: newSession, party: party, reportsFailure: true) != nil else {
            operation = .idle
            updateSharedPlacement(.enclosure)
            synchronizeSharedHabitat()
            return
        }

        session = newSession
        state.activeSession = newSession
        operation = .active
        updateSharedPlacement(.dynamicIsland)
        synchronizeSharedHabitat()
        showsSessionComposer = false
        await persist()
        scheduleExpiry(for: newSession)
        Haptics.success(enabled: settings.hapticsEnabled)
    }

    /// Moves the lead pet between the two system surfaces. ActivityKit still
    /// needs an internal expiry date, but no duration is exposed in this flow.
    /// A fresh activity is created whenever the pet is taken along.
    func placePet(in newPlacement: PetPlacement) async {
        guard !isBusy, newPlacement != placement else { return }

        switch newPlacement {
        case .dynamicIsland:
            moveLeadInSharedHabitat(toDynamicIsland: true)
            updateSharedPlacement(.dynamicIsland)
            if session == nil {
                await startSession(duration: TimeInterval(settings.defaultSessionMinutes * 60))
            } else if !liveActivityConnection.isConnected {
                await reconnectLiveActivity()
            }
        case .enclosure, .home:
            if session != nil {
                await endSession(
                    showSummary: false,
                    removeImmediately: true,
                    recordsHistory: false,
                    movesToEnclosure: false
                )
            } else {
                await beginSave()
                await clearLiveActivityState()
                finishSave()
            }
            moveLeadInSharedHabitat(toDynamicIsland: false)
            updateSharedPlacement(newPlacement)
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
        Haptics.success(enabled: settings.hapticsEnabled)
    }

    /// Explicit user action for recovering a session whose system Live
    /// Activity was removed or could not be registered during installation.
    func reconnectLiveActivity() async {
        guard !isBusy, let session, !session.isExpired(at: .now) else { return }
        await beginSave()
        defer { finishSave() }
        operation = .starting
        defer { operation = .active }
        for existing in Activity<PetActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        shouldReconnectMissingActivity = true
        let party = activeParty.isEmpty ? [profile] : activeParty
        _ = requestLiveActivity(for: session, party: party, reportsFailure: true)
        await persist()
    }

    func interact(_ interaction: PetInteraction) async {
        await beginSave()
        defer { finishSave() }
        guard operation == .active, var current = session else { return }
        let pet = state.pets.first(where: { $0.id == current.petID }) ?? profile
        let snapshot = behavior.reacting(
            to: interaction,
            species: pet.species,
            from: current.snapshot,
            at: .now
        )
        current.snapshot = snapshot
        session = current
        state.activeSession = current
        await persist()

        if let activity {
            let label: String
            switch interaction {
            case .pet: label = "pet"
            case .play: label = "play"
            case .snack: label = "snack"
            }
            await activity.update(
                ActivityContent(
                    state: activity.content.state.updating(snapshot: snapshot, lastInteraction: label),
                    staleDate: current.endsAt
                )
            )
        }
        Haptics.light(enabled: settings.hapticsEnabled)
    }

    func endSession(
        showSummary: Bool = true,
        removeImmediately: Bool = false,
        recordsHistory: Bool = true,
        movesToEnclosure: Bool = true
    ) async {
        await beginSave()
        defer { finishSave() }
        guard operation == .active, let current = session else { return }
        operation = .stopping
        expiryTask?.cancel()
        let now = min(Date.now, current.endsAt)
        if recordsHistory {
            history.record(current, endedAt: now)
            state.history = history
        }
        state.activeSession = nil

        let finalSnapshot = PetSnapshot(
            pose: .sleep,
            position: current.snapshot.position,
            direction: current.snapshot.direction,
            revision: current.snapshot.revision + 1,
            generatedAt: now
        )
        if let activity {
            let policy: ActivityUIDismissalPolicy = removeImmediately
                ? .immediate
                : .after(Date.now.addingTimeInterval(15 * 60))
            await activity.end(
                ActivityContent(
                    state: activity.content.state.updating(snapshot: finalSnapshot, lastInteraction: "finished"),
                    staleDate: Date.now
                ),
                dismissalPolicy: policy
            )
        }
        activity = nil
        liveActivityConnection = .inactive
        session = nil
        operation = .idle
        showsSessionSummary = showSummary
        await persist()
        if movesToEnclosure {
            updateSharedPlacement(.enclosure)
            synchronizeSharedHabitat()
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
        }
        Haptics.success(enabled: settings.hapticsEnabled)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "petisland" else { return }
        switch url.host?.lowercased() {
        case "play", "playroom":
            selectedTab = .island
            showsPlayYard = true
        case "enclosure", "island", "session":
            selectedTab = .island
        default:
            return
        }
        if session != nil { showsSessionComposer = false }
    }

    func sceneBecameActive() async {
        await bootstrap()
    }

    /// The compact Live Activity uses a system-rendered timer and needs no
    /// background frame updates. Persist once before iOS suspends the app.
    func sceneEnteredBackground() async {
        await beginSave()
        defer { finishSave() }
        guard operation == .active else { return }
        await persist()
    }

    private func reconcileActivities(at now: Date) async {
        let activities = Activity<PetActivityAttributes>.activities
        var restoredActivity: Activity<PetActivityAttributes>?

        if var savedSession = state.activeSession, !savedSession.isExpired(at: now) {
            restoredActivity = activities.first { $0.attributes.sessionID == savedSession.id }
            if let restoredActivity,
               restoredActivity.content.state.snapshot.revision > savedSession.snapshot.revision {
                savedSession.snapshot = restoredActivity.content.state.snapshot
                state.activeSession = savedSession
                await persist()
            }
            session = savedSession
            operation = .active
            scheduleExpiry(for: savedSession)
            if restoredActivity == nil, shouldReconnectMissingActivity, state.dismissedActivitySessionID != savedSession.id {
                let party = [profile]
                restoredActivity = requestLiveActivity(
                    for: savedSession,
                    party: party,
                    reportsFailure: false
                )
            }
        } else if let orphan = activities.first(where: { $0.attributes.endsAt > now }) {
            let attrs = orphan.attributes
            recoverParty(from: attrs)
            let restored = PetSession(
                id: attrs.sessionID,
                petID: attrs.pet.id,
                startedAt: attrs.startedAt,
                endsAt: attrs.endsAt,
                snapshot: orphan.content.state.snapshot
            )
            restoredActivity = orphan
            session = restored
            state.activeSession = restored
            operation = .active
            scheduleExpiry(for: restored)
            await persist()
        } else {
            if let expired = state.activeSession {
                history.record(expired, endedAt: expired.endsAt)
                state.history = history
                state.activeSession = nil
                showsSessionSummary = true
                await persist()
            }
            session = nil
            operation = .idle
            if placement == .dynamicIsland {
                updateSharedPlacement(.enclosure)
                synchronizeSharedHabitat()
                WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
            }
        }

        for item in activities where item.id != restoredActivity?.id {
            await item.end(nil, dismissalPolicy: .immediate)
        }
        activity = restoredActivity
        liveActivitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
        if let restoredActivity {
            updateLiveActivityConnection(restoredActivity.activityState)
            observeCurrentActivity()
        } else if session == nil {
            liveActivityConnection = liveActivitiesEnabled ? .inactive : .unavailable
        } else if !liveActivitiesEnabled {
            liveActivityConnection = .unavailable
        } else {
            liveActivityConnection = .dismissed
        }
    }

    private func scheduleExpiry(for session: PetSession) {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            do {
                try await Task.sleep(until: .now + .seconds(max(session.endsAt.timeIntervalSinceNow, 0)), clock: .continuous)
            } catch { return }
            guard !Task.isCancelled else { return }
            await self?.endSession()
        }
    }

    private func observeCurrentActivity() {
        activityObservationTask?.cancel()
        guard let activity else { return }
        activityObservationTask = Task { [weak self] in
            for await activityState in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                self?.updateLiveActivityConnection(activityState)
                if activityState == .dismissed {
                    await self?.activityWasDismissed(activityID: activity.id)
                    return
                }
            }
        }
    }

    private func activityWasDismissed(activityID: String) async {
        await beginSave()
        defer { finishSave() }
        guard activity?.id == activityID else { return }
        activity = nil
        shouldReconnectMissingActivity = false
        state.dismissedActivitySessionID = session?.id
        liveActivityConnection = .dismissed
        await persist()
    }

    private func observeAuthorization() {
        authorizationTask?.cancel()
        authorizationTask = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard !Task.isCancelled else { return }
                self?.liveActivitiesEnabled = enabled
                if !enabled {
                    self?.liveActivityConnection = .unavailable
                }
            }
        }
    }

    private func publishPetCollection() {
        state.normalizePetCollection()
        arcadeState.reconcile(with: state.pets)
        // Initialize rest only after the bootstrap merge: an unknown local
        // timestamp must not hide older, valid care performed by a widget.
        for pet in state.pets where arcadeState.vitalsUpdatedAtByPetID[pet.id] == nil || arcadeState.vitalsUpdatedAtByPetID[pet.id] == .distantPast {
            arcadeState.vitalsUpdatedAtByPetID[pet.id] = .now
        }
        pets = state.pets
        activePetIDs = state.activePetIDs
        activeParty = state.activeParty
        profile = state.profile
        arcadeProgress = arcadeState.progress
    }

    private func activityIdentity(for pet: PetProfile) -> PetActivityIdentity {
        PetActivityIdentity(
            id: pet.id,
            name: pet.name,
            species: pet.species,
            coat: pet.coat,
            customColor: pet.customColor,
            breed: pet.resolvedBreed
        )
    }

    @discardableResult
    private func requestLiveActivity(
        for session: PetSession,
        party: [PetProfile],
        reportsFailure: Bool
    ) -> Activity<PetActivityAttributes>? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveActivitiesEnabled = false
            liveActivityConnection = .unavailable
            if reportsFailure {
                alertMessage = String(localized: "Enable Live Activities in Settings to take your pet to Dynamic Island.")
            }
            return nil
        }

        liveActivitiesEnabled = true
        liveActivityConnection = .starting
        let resolvedParty = [party.first ?? profile]
        guard let leadPet = resolvedParty.first else {
            liveActivityConnection = .failed
            return nil
        }

        let attributes = PetActivityAttributes(
            sessionID: session.id,
            pet: activityIdentity(for: leadPet),
            companions: [],
            startedAt: session.startedAt,
            endsAt: session.endsAt,
            motionMode: settings.dynamicIslandMotionMode
        )
        let content = ActivityContent(
            state: PetActivityAttributes.ContentState(
                snapshot: session.snapshot,
                lastInteraction: nil,
                backgroundColor: settings.liveActivityBackgroundColor
            ),
            staleDate: session.endsAt
        )

        do {
            let requested = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            activity = requested
            state.dismissedActivitySessionID = nil
            updateLiveActivityConnection(requested.activityState)
            observeCurrentActivity()
            return requested
        } catch {
            liveActivityConnection = .failed
            if reportsFailure {
                alertMessage = String(localized: "Live Activity could not start. Please try again.")
            }
            return nil
        }
    }

    private func updateLiveActivityConnection(_ state: ActivityState) {
        switch state {
        case .pending: liveActivityConnection = .starting
        case .active: liveActivityConnection = .active
        case .stale: liveActivityConnection = .stale
        case .ended: liveActivityConnection = .inactive
        case .dismissed: liveActivityConnection = .dismissed
        @unknown default: liveActivityConnection = .failed
        }
    }

    private func recoverParty(from attributes: PetActivityAttributes) {
        let identities = [attributes.pet]
        for identity in identities where !state.pets.contains(where: { $0.id == identity.id }) {
            state.pets.append(
                PetProfile(
                    id: identity.id,
                    name: identity.name,
                    species: identity.species,
                    coat: identity.coat,
                    createdAt: attributes.startedAt,
                    customColor: identity.customColor,
                    breed: identity.breed
                )
            )
        }
        state.activePetIDs = identities.map(\.id)
        publishPetCollection()
    }

    private func synchronizeSharedLifeState() {
        do {
            lifeState = try PetLifeStore.update { shared in
                if shared.profile.id != profile.id {
                    shared = PetLifeState(profile: profile, placement: placement,
                                          vitals: vitals(for: profile.id))
                }
                shared.profile = profile
                if state.activeSession != nil { shared.move(to: .dynamicIsland) }
            }
            placement = lifeState.placement
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
        } catch {
            alertMessage = String(localized: "Pixel's widget state could not be saved.")
        }
    }

    private func synchronizeSharedHabitat() {
        do {
            habitat = try PetHabitatStore.update { shared in
                let knownIDs = Set(state.pets.map(\.id))
                shared.configuration.reconcile(availablePetIDs: knownIDs)

                if placement == .dynamicIsland {
                    shared.configuration.setDynamicIslandLead(profile.id)
                } else if shared.configuration.leadDynamicIslandPetID != nil {
                    if !shared.configuration.returnDynamicIslandLeadToHabitat() {
                        shared.configuration.setDynamicIslandLead(nil)
                    }
                }

                if shared.configuration.residentPetIDs.isEmpty,
                   shared.configuration.leadDynamicIslandPetID == nil {
                    shared.configuration.setResidents([profile.id])
                }

                let selected = Set(shared.configuration.residentPetIDs)
                shared.residents = state.pets.compactMap { pet in
                    guard selected.contains(pet.id) else { return nil }
                    if var existing = shared.residents.first(where: { $0.id == pet.id }) {
                        existing.profile = pet
                        return existing
                    }
                    return SharedHabitatResident(
                        profile: pet,
                        vitals: arcadeState.vitalsByPetID[pet.id] ?? PetVitals(),
                        vitalsUpdatedAt: arcadeState.vitalsUpdatedAtByPetID[pet.id] ?? .distantPast
                    )
                }
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
        } catch {
            alertMessage = String(localized: "The enclosure state could not be synchronized.")
        }
    }

    private func moveLeadInSharedHabitat(toDynamicIsland: Bool) {
        do {
            habitat = try PetHabitatStore.update { shared in
                if toDynamicIsland {
                    shared.configuration.setDynamicIslandLead(profile.id)
                } else {
                    if !shared.configuration.returnDynamicIslandLeadToHabitat() {
                        shared.configuration.setDynamicIslandLead(nil)
                    }
                    if shared.configuration.residentPetIDs.isEmpty {
                        shared.configuration.setResidents([profile.id])
                    }
                }

                let selected = Set(shared.configuration.residentPetIDs)
                shared.residents = state.pets.compactMap { pet in
                    guard selected.contains(pet.id) else { return nil }
                    if var existing = shared.residents.first(where: { $0.id == pet.id }) {
                        existing.profile = pet
                        return existing
                    }
                    return SharedHabitatResident(
                        profile: pet,
                        vitals: arcadeState.vitalsByPetID[pet.id] ?? PetVitals(),
                        vitalsUpdatedAt: arcadeState.vitalsUpdatedAtByPetID[pet.id] ?? .distantPast
                    )
                }
            }
        } catch {
            alertMessage = String(localized: "The pet could not be moved.")
        }
    }

    private func reloadSharedLifeState() {
        lifeState = PetLifeStore.load()
        placement = lifeState.placement
        habitat = PetHabitatStore.load()
        let previous = arcadeState
        arcadeState.mergeVitals(from: habitat)
        if previous != arcadeState { Task { await persistArcade() } }
    }

    private func updateSharedPlacement(_ newPlacement: PetPlacement) {
        do {
            lifeState = try PetLifeStore.update { shared in
                shared.profile = profile
                shared.move(to: newPlacement)
            }
            placement = lifeState.placement
        } catch {
            alertMessage = String(localized: "Pixel's location could not be saved.")
        }
    }

    private func clearLiveActivityState() async {
        expiryTask?.cancel()
        for existing in Activity<PetActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        session = nil
        state.activeSession = nil
        operation = .idle
        liveActivityConnection = liveActivitiesEnabled ? .inactive : .unavailable
        await persist()
    }

    private func persist() async {
        do {
            try await store.save(state)
        } catch {
            alertMessage = String(localized: "Your changes could not be saved. Please try again.")
        }
    }

    private func persistArcade() async {
        await beginSave()
        defer { finishSave() }
        do {
            try await arcadeStore.save(arcadeState)
        } catch {
            alertMessage = String(localized: "Arcade progress could not be saved. Please try again.")
        }
    }
}

private enum Haptics {
    static func light(enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
