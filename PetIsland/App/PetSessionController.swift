import ActivityKit
import Foundation
import SwiftUI
import UIKit
import WidgetKit

@MainActor
final class PetSessionController: ObservableObject {
    enum Operation: Equatable {
        case loading
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
    @Published private(set) var liveActivitiesEnabled = true
    @Published private(set) var liveActivityConnection: LiveActivityConnection = .inactive
    @Published private(set) var placement: PetPlacement = .enclosure
    @Published private(set) var lifeState = PetLifeState.initial()
    @Published private(set) var habitat = SharedPetHabitat.initial()

    private let store: any PetStore
    private let behavior = PetBehaviorMachine()
    private var activity: Activity<PetActivityAttributes>?
    private var state = PersistedAppState()
    private var expiryTask: Task<Void, Never>?
    private var activityObservationTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Never>?
    private var didBootstrap = false
    private var shouldReconnectMissingActivity = true

    init(store: any PetStore = FilePetStore()) {
        self.store = store
    }

    var isBusy: Bool { operation == .starting || operation == .stopping || operation == .loading }

    func bootstrap() async {
        if !didBootstrap {
            state = await store.load()
            ensureMVPDog()
            publishPetCollection()
            synchronizeSharedLifeState()
            synchronizeSharedHabitat()
            history = state.history
            settings = state.settings
            completedOnboarding = state.completedOnboarding
            didBootstrap = true
            observeAuthorization()
            await persist()
        }
        reloadSharedLifeState()
        if placement == .dynamicIsland {
            await reconcileActivities(at: .now)
        } else {
            await clearLiveActivityState()
        }
    }

    func completeOnboarding(profile newProfile: PetProfile) async {
        var profile = newProfile
        profile.normalizeName()
        state.pets = [profile]
        state.activePetIDs = [profile.id]
        publishPetCollection()
        completedOnboarding = true
        state.completedOnboarding = true
        await persist()
        synchronizeSharedLifeState()
        synchronizeSharedHabitat()
    }

    func updateProfile(_ newProfile: PetProfile) async {
        _ = await updatePet(newProfile)
    }

    /// Adds a pet to the collection. It joins the active party when a slot is
    /// available and no session is currently running.
    @discardableResult
    func addPet(_ newPet: PetProfile) async -> Bool {
        guard !state.pets.contains(where: { $0.id == newPet.id }) else { return false }
        var normalized = newPet
        normalized.normalizeName()
        state.pets.append(normalized)
        if session == nil, state.activePetIDs.count < PersistedAppState.maximumActivePets {
            state.activePetIDs.append(normalized.id)
        }
        publishPetCollection()
        await persist()
        synchronizeSharedLifeState()
        synchronizeSharedHabitat()
        return true
    }

    @discardableResult
    func updatePet(_ updatedPet: PetProfile) async -> Bool {
        guard let index = state.pets.firstIndex(where: { $0.id == updatedPet.id }) else { return false }
        var normalized = updatedPet
        normalized.normalizeName()
        state.pets[index] = normalized
        publishPetCollection()
        await persist()
        synchronizeSharedLifeState()
        synchronizeSharedHabitat()
        return true
    }

    /// Removes a pet without ever leaving the collection or party empty.
    /// The pet leading a running session is protected until the session ends.
    @discardableResult
    func removePet(id: UUID) async -> Bool {
        guard state.pets.count > 1,
              state.pets.contains(where: { $0.id == id }),
              session?.petID != id,
              session == nil || !state.activePetIDs.contains(id) else { return false }

        state.pets.removeAll { $0.id == id }
        state.activePetIDs.removeAll { $0 == id }
        publishPetCollection()
        await persist()
        synchronizeSharedHabitat()
        return true
    }

    /// Toggles party membership. Party membership is locked for the duration
    /// of a Live Activity because ActivityKit attributes are immutable.
    @discardableResult
    func togglePetActive(id: UUID) async -> Bool {
        guard session == nil, state.pets.contains(where: { $0.id == id }) else { return false }
        if let index = state.activePetIDs.firstIndex(of: id) {
            guard state.activePetIDs.count > 1 else { return false }
            state.activePetIDs.remove(at: index)
        } else {
            guard state.activePetIDs.count < PersistedAppState.maximumActivePets else { return false }
            state.activePetIDs.append(id)
        }
        publishPetCollection()
        await persist()
        return true
    }

    /// Promotes a pet to the first party position. An inactive pet is added;
    /// when the party is full, the last companion yields its slot.
    @discardableResult
    func makeLeadPet(id: UUID) async -> Bool {
        guard session == nil, state.pets.contains(where: { $0.id == id }) else { return false }
        state.activePetIDs.removeAll { $0 == id }
        state.activePetIDs.insert(id, at: 0)
        state.activePetIDs = Array(state.activePetIDs.prefix(PersistedAppState.maximumActivePets))
        publishPetCollection()
        await persist()
        return true
    }

    func updateSettings(_ newSettings: AppSettings) async {
        settings = newSettings
        state.settings = newSettings
        await persist()
    }

    func updateDynamicIslandSettings(
        mode: DynamicIslandMotionMode? = nil,
        durationMinutes: Int? = nil
    ) async {
        if let mode { settings.dynamicIslandMotionMode = mode }
        if let durationMinutes {
            settings.defaultSessionMinutes = min(max(durationMinutes, 20), 240)
        }
        state.settings = settings
        await persist()
    }

    var habitatResidents: [PetProfile] {
        let residentsByID = Dictionary(uniqueKeysWithValues: habitat.residents.map { ($0.id, $0.profile) })
        return habitat.configuration.residentPetIDs.compactMap { residentsByID[$0] }
    }

    var habitatVitalsByPetID: [UUID: PetVitals] {
        Dictionary(uniqueKeysWithValues: habitat.residents.map { ($0.id, $0.vitals) })
    }

    /// Saves the enclosure composition and theme as one atomic App Group
    /// snapshot, so the Home Screen widget observes a consistent update.
    func saveHabitat(theme: HabitatTheme, residentPetIDs: [UUID]) {
        do {
            habitat = try PetHabitatStore.update { shared in
                shared.configuration.setTheme(theme)
                shared.configuration.setResidents(residentPetIDs)
                let selected = Set(shared.configuration.residentPetIDs)
                shared.residents = state.pets.compactMap { pet in
                    guard selected.contains(pet.id) else { return nil }
                    let previousVitals = shared.residents.first { $0.id == pet.id }?.vitals ?? PetVitals()
                    return SharedHabitatResident(profile: pet, vitals: previousVitals)
                }
            }
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
            Haptics.success(enabled: settings.hapticsEnabled)
        } catch {
            alertMessage = String(localized: "The enclosure could not be saved.")
        }
    }

    func startSession(duration: TimeInterval) async {
        guard operation == .idle else { return }
        operation = .starting
        let now = Date.now
        let clampedDuration = min(max(duration, 10 * 60), 8 * 60 * 60)
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
        _ = requestLiveActivity(for: newSession, party: party, reportsFailure: true)

        session = newSession
        state.activeSession = newSession
        operation = .active
        showsSessionComposer = false
        await persist()
        scheduleExpiry(for: newSession)
        Haptics.success(enabled: settings.hapticsEnabled)
    }

    /// Moves the single MVP dog between the two system surfaces. ActivityKit
    /// still needs an internal expiry date, but no duration is exposed to the
    /// user. A fresh activity is created whenever Pixel is taken along.
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
                await clearLiveActivityState()
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
        guard let session, !session.isExpired(at: .now) else { return }
        for existing in Activity<PetActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        shouldReconnectMissingActivity = true
        let party = activeParty.isEmpty ? [profile] : activeParty
        _ = requestLiveActivity(for: session, party: party, reportsFailure: true)
    }

    func interact(_ interaction: PetInteraction) async {
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
                    state: .init(snapshot: snapshot, lastInteraction: label),
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
                    state: .init(snapshot: finalSnapshot, lastInteraction: "finished"),
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
            WidgetCenter.shared.reloadTimelines(ofKind: "PetIsland.Enclosure")
        }
        Haptics.success(enabled: settings.hapticsEnabled)
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "petisland" else { return }
        if session != nil { showsSessionComposer = false }
    }

    func sceneBecameActive() async {
        await bootstrap()
        reloadSharedLifeState()
    }

    /// The compact Live Activity uses a system-rendered timer and needs no
    /// background frame updates. Persist once before iOS suspends the app.
    func sceneEnteredBackground() async {
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
            if restoredActivity == nil, shouldReconnectMissingActivity {
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
        guard activity?.id == activityID else { return }
        activity = nil
        shouldReconnectMissingActivity = false
        liveActivityConnection = .dismissed
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
        pets = state.pets
        activePetIDs = state.activePetIDs
        activeParty = state.activeParty
        profile = state.profile
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
                alertMessage = String(localized: "The session started in the app. Enable Live Activities in Settings to see your pet outside the app.")
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
                lastInteraction: nil
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
            updateLiveActivityConnection(requested.activityState)
            observeCurrentActivity()
            return requested
        } catch {
            liveActivityConnection = .failed
            if reportsFailure {
                alertMessage = String(localized: "The session started in the app, but Live Activity could not start.")
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

    private func ensureMVPDog() {
        if let dog = state.pets.first(where: { $0.species == .dog }) {
            state.activePetIDs = [dog.id]
            return
        }

        let dog = PetProfile(
            id: UUID(),
            name: "Pixel",
            species: .dog,
            coat: state.pets.first?.coat ?? .sunrise,
            createdAt: .now,
            customColor: state.pets.first?.customColor
        )
        state.pets.insert(dog, at: 0)
        state.activePetIDs = [dog.id]
    }

    private func synchronizeSharedLifeState() {
        var shared = PetLifeStore.load()
        shared.profile = profile
        shared.profile.species = .dog
        if state.activeSession != nil {
            shared.move(to: .dynamicIsland)
        }
        do {
            try PetLifeStore.save(shared)
            lifeState = shared
            placement = shared.placement
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
                    _ = shared.configuration.returnDynamicIslandLeadToHabitat()
                }

                if shared.configuration.residentPetIDs.isEmpty,
                   shared.configuration.leadDynamicIslandPetID == nil {
                    shared.configuration.setResidents([profile.id])
                }

                let selected = Set(shared.configuration.residentPetIDs)
                shared.residents = state.pets.compactMap { pet in
                    guard selected.contains(pet.id) else { return nil }
                    let oldVitals = shared.residents.first { $0.id == pet.id }?.vitals ?? PetVitals()
                    return SharedHabitatResident(profile: pet, vitals: oldVitals)
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
                } else if !shared.configuration.returnDynamicIslandLeadToHabitat(),
                          shared.configuration.leadDynamicIslandPetID == nil,
                          shared.configuration.residentPetIDs.isEmpty {
                    shared.configuration.setResidents([profile.id])
                }

                let selected = Set(shared.configuration.residentPetIDs)
                shared.residents = state.pets.compactMap { pet in
                    guard selected.contains(pet.id) else { return nil }
                    let oldVitals = shared.residents.first { $0.id == pet.id }?.vitals ?? PetVitals()
                    return SharedHabitatResident(profile: pet, vitals: oldVitals)
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
    }

    private func updateSharedPlacement(_ newPlacement: PetPlacement) {
        do {
            lifeState = try PetLifeStore.update { shared in
                shared.profile = profile
                shared.profile.species = .dog
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
