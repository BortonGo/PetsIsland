import SwiftUI

struct PetProfileOverview: Equatable {
    enum Location: Equatable { case home, enclosure, withYou, walking }
    let pet: PetProfile
    let vitals: PetVitals
    let location: Location
    let walk: PetDiscoveryWalk?
    let memories: [PetDiscoveryMemory]
}

struct PetProfileRefreshSchedule: TimelineSchedule {
    var paused: Bool

    func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        if paused { return AnySequence([startDate]) }
        return AnySequence(PeriodicTimelineSchedule(from: startDate, by: 60).entries(from: startDate, mode: mode))
    }
}

#if DEBUG
/// Local QA fixture, with a different lead to catch accidental cross-pet actions.
struct PetProfileDebugHostView: View {
    @StateObject private var controller: PetSessionController
    private let petID: UUID
    private let backupFixture: IslandBackup?

    init() {
        let args = ProcessInfo.processInfo.arguments
        var state = PersistedAppState()
        let lead = PetProfile(id: UUID(uuidString: "CD000000-0000-0000-0000-000000000001")!, name: "Корги", species: .dog, coat: .sunrise, createdAt: .now, breed: .corgi)
        let pet = PetProfile(id: UUID(uuidString: "CD000000-0000-0000-0000-000000000002")!,
                             name: args.contains("-profile-long-name") ? "Пиксель Пушистый Исследователь Острова" : "Пиксель", species: .cat, coat: .sunrise,
                             createdAt: .now.addingTimeInterval(-86400 * 21), breed: .maineCoon,
                             outfit: PetOutfit(headwear: .knitHat))
        petID = pet.id
        state.pets = [lead, pet]
        state.activePetIDs = [lead.id]
        state.completedOnboarding = true
        state.normalizePetCollection()
        if !args.contains("-profile-empty") {
            state.discoveries.startWalk(pet: pet, route: .garden, at: .now.addingTimeInterval(-86400))
            state.discoveries.collectWalk(at: .now)
        }
        if args.contains("-profile-stories") {
            state.discoveries = PetDiscoveriesState()
            for day in 0..<8 {
                let start = Date.now.addingTimeInterval(Double(day - 12) * 86400)
                state.discoveries.startWalk(pet: pet, route: .garden, at: start)
                state.discoveries.collectWalk(at: start.addingTimeInterval(3600))
            }
            state.discoveries.startWalk(pet: lead, route: .grove, at: .now.addingTimeInterval(-7200))
            state.discoveries.collectWalk(at: .now)
        }
        if args.contains("-profile-away") || args.contains("-profile-ready") {
            state.discoveries.startWalk(pet: pet, route: .shore,
                                       at: .now.addingTimeInterval(args.contains("-profile-ready") ? -3600 : -300))
        }
        if args.contains("-profile-returning") {
            let end = Date.now.addingTimeInterval(15)
            let walk = PetDiscoveryWalk(pet: pet, route: .shore, startedAt: end.addingTimeInterval(-PetWalkRoute.shore.duration),
                                        endsAt: end, discovery: .shell, story: .curious)
            state.discoveries = PetDiscoveriesState(activeWalk: walk, memories: state.discoveries.memories)
        }
        var inventory = ArcadeInventory()
        if !args.contains("-profile-empty") {
            inventory.add(.food, count: 3); inventory.add(.treat, count: 2); inventory.add(.toy)
        }
        var arcade = ArcadeState(progress: ArcadeProgress(coins: args.contains("-profile-no-coins") ? 0 : 120,
                                                         inventory: inventory, ownedAccessories: [.knitHat]),
                                 vitalsByPetID: [pet.id: PetVitals(fullness: 0.65, happiness: 0.82, energy: 0.72)])
        if args.contains("-profile-bond") {
            for daysAgo in (1...6).reversed() {
                let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
                arcade.bondsByPetID[pet.id, default: PetBond()].shareAttention(at: date)
                arcade.bondsByPetID[pet.id, default: PetBond()].recordCare(.toy, at: date)
                arcade.bondsByPetID[pet.id, default: PetBond()].recordGame(.bubblePaws, at: date)
            }
        }
        var recoveryData: Data?
        backupFixture = args.contains("-profile-backup")
            ? IslandBackup(app: state, arcade: arcade, habitat: PetHabitatState(residentPetIDs: state.pets.map(\.id))) : nil
        if args.contains("-profile-backup") {
            var saved = state
            saved.pets[1].name = "Луна"
            let backup = IslandBackup(app: saved, arcade: arcade,
                                      habitat: PetHabitatState(residentPetIDs: saved.pets.map(\.id)))
            recoveryData = try? IslandBackupCodec.encode(backup)
        }
        let store: any PetStore = args.contains("-profile-fail-walk-save") ? PetWalkFailurePreviewStore(state) : InMemoryPetStore(state)
        _controller = StateObject(wrappedValue: PetSessionController(store: store, arcadeStore: InMemoryArcadeStore(arcade),
            backupStore: InMemoryIslandBackupStore(recovery: recoveryData)))
    }

    var body: some View {
        Group {
            if controller.operation == .loading { ProgressView() }
            else if ProcessInfo.processInfo.arguments.contains("-profile-collection") || ProcessInfo.processInfo.arguments.contains("-profile-backup") {
                HomeView(controller: controller)
                    .onAppear { controller.selectedTab = ProcessInfo.processInfo.arguments.contains("-profile-backup") ? .settings : .pets }
            }
            else { PetProfileView(controller: controller, petID: petID) }
        }
        .task {
            if let backupFixture, controller.operation == .loading {
                try? PetHabitatStore.save(backupFixture.sharedHabitat)
                try? PetLifeStore.save(backupFixture.sharedLife)
            }
            await controller.bootstrap()
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-profile-light") ? .light : .dark)
        .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("-profile-largest") ? .accessibility5
                        : ProcessInfo.processInfo.arguments.contains("-profile-large") ? .accessibility3 : .large)
        .environment(\.petMinimizeMotion, ProcessInfo.processInfo.arguments.contains("-profile-reduced-motion"))
    }
}

/// Fail only the first walk mutation, after bootstrap, so UI tests can retry
/// without touching the real save or changing production persistence.
private actor PetWalkFailurePreviewStore: PetStore {
    private var state: PersistedAppState
    private var hasFailed = false
    init(_ state: PersistedAppState) { self.state = state }
    func load() -> PersistedAppState { state }
    func save(_ candidate: PersistedAppState) throws {
        if !hasFailed, candidate.discoveries != state.discoveries {
            hasFailed = true
            throw CocoaError(.fileWriteUnknown)
        }
        state = candidate
    }
}
#endif

/// The collection opens a companion's card; editing remains a separate action.
/// Artwork is a still from the existing approved sprite and outfit libraries.
struct PetProfileView: View {
    @ObservedObject var controller: PetSessionController
    let petID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var route: Route?
    @State private var selectedMemory: PetDiscoveryMemory?
    @State private var isVisible = false
    @State private var isGiving = false
    @State private var feedback: String?
    @State private var errorMessage: String?

    private enum Route: String, Identifiable {
        case wardrobe, edit, walks, shop, album
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Vitals recover slowly. No animation clock, and no periodic
                // updates while another sheet covers the card or the app sleeps.
                TimelineView(PetProfileRefreshSchedule(paused: !isVisible || scenePhase != .active || route != nil || selectedMemory != nil)) { context in
                    content(at: context.date)
                }
            }
            .petPage()
            .navigationTitle("Pet card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { route = .edit } label: { Label("Edit", systemImage: "pencil") }
                        .disabled(controller.isBusy || controller.session?.petID == petID || controller.profileOverview(for: petID) == nil)
                        .accessibilityIdentifier("profile.edit")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            isVisible = true
#if DEBUG
            if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-profile-route=") }) {
                route = Route(rawValue: String(argument.dropFirst("-profile-route=".count)))
            }
#endif
        }
        .onDisappear { isVisible = false }
        .sheet(item: $route) { destination in
            if let pet = controller.pets.first(where: { $0.id == petID }) {
                switch destination {
                case .wardrobe: PetWardrobeView(controller: controller, petID: petID)
                case .edit:
                    PetProfileEditor(initialProfile: pet, isNew: false, sessionIsActive: controller.session?.petID == petID) {
                        await controller.updatePet($0)
                    }
                case .walks: PetDiscoveriesView(controller: controller, preferredPetID: petID)
                case .shop: MiniGamesView(controller: controller, initialPetID: petID, startsInShop: true)
                case .album: PetDiscoveriesAlbum(controller: controller, petID: petID)
                }
            } else {
                ContentUnavailableView("Pet not found", systemImage: "pawprint")
            }
        }
        .sheet(item: $selectedMemory) { memory in
            PetDiscoveryMemoryView(memory: memory, isNew: false)
        }
        .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        if let overview = controller.profileOverview(for: petID, at: date) {
            VStack(spacing: 20) {
                portrait(overview)
                vitals(overview.vitals)
                PetBondView(controller: controller, overview: overview, date: date)
                care(overview.pet)
                destinations(overview)
                memories(overview.memories)
                Text("Together since \(overview.pet.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView("Pet not found", systemImage: "pawprint")
        }
    }

    private func portrait(_ overview: PetProfileOverview) -> some View {
        let pet = overview.pet
        return VStack(spacing: 9) {
            PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                       breed: pet.resolvedBreed, pose: .idle, animatesMotion: false,
                       accessory: pet.outfit?.headwear)
                .frame(width: 210, height: 150)
                .frame(maxWidth: .infinity)
                .background { Ellipse().fill(PetDesign.soft).frame(width: 200, height: 110) }
                .accessibilityHidden(true)
            Text(pet.name).font(PetDesign.title(.title)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(pet.resolvedBreed?.displayName ?? pet.species.displayName)
                .font(.subheadline).foregroundStyle(PetDesign.secondary)
            location(overview)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(PetDesign.soft, in: Capsule())
            if overview.location == .walking, let walk = overview.walk {
                Text("Back at \(walk.endsAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }

    @ViewBuilder private func location(_ overview: PetProfileOverview) -> some View {
        switch overview.location {
        case .walking: Label("Out exploring", systemImage: "pawprint")
        case .withYou: Label("On Dynamic Island", systemImage: "iphone")
        case .enclosure: Label("In the enclosure", systemImage: "leaf")
        case .home: Label("At home", systemImage: "house")
        }
    }

    private func vitals(_ value: PetVitals) -> some View {
        (dynamicTypeSize.isAccessibilitySize
         ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))) {
            vital("Full", symbol: "fork.knife", value: value.fullness)
            vital("Happy", symbol: "heart", value: value.happiness)
            vital("Energy", symbol: "bolt", value: value.energy)
        }
        .padding(18).petSurface(radius: 22)
    }

    private func vital(_ title: LocalizedStringKey, symbol: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption.weight(.medium))
            ProgressView(value: value).tint(PetDesign.accent)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit()).foregroundStyle(PetDesign.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
    }

    private func care(_ pet: PetProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Care").font(PetDesign.title(.title3)).accessibilityAddTraits(.isHeader)
            ForEach(ArcadeItemKind.allCases) { item in
                careItem(item, pet: pet)
                if item != ArcadeItemKind.allCases.last { Divider().overlay(PetDesign.separator) }
            }
            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(PetDesign.secondary)
                    .accessibilityIdentifier("profile.care.feedback")
            }
            Button { route = .shop } label: {
                Label("Restock supplies", systemImage: "basket").frame(maxWidth: .infinity)
            }
            .buttonStyle(PetQuietButtonStyle())
            .accessibilityIdentifier("profile.shop")
        }
        .padding(18).petSurface(radius: 22)
    }

    private func careItem(_ item: ArcadeItemKind, pet: PetProfile) -> some View {
        let reason = controller.arcadeItemUnavailableReason(item, for: petID)
        let quantity = controller.arcadeProgress.inventory[item]
        return (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                : AnyLayout(HStackLayout(spacing: 12))) {
            Image(systemName: item.symbol).font(.title3).foregroundStyle(PetDesign.secondary)
                .frame(width: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text("In stock: \(quantity)").font(.caption.monospacedDigit())
                    .foregroundStyle(PetDesign.secondary)
                    .accessibilityIdentifier("profile.stock.\(item.rawValue)")
                Text(reason ?? item.effectDescription).font(.caption2).foregroundStyle(PetDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                guard !isGiving else { return }
                isGiving = true
                Task {
                    defer { isGiving = false }
                    if await controller.useArcadeItem(item, for: petID) {
                        feedback = String(localized: "\(pet.name) used \(item.title.lowercased()).")
                    } else if let reason = controller.arcadeItemUnavailableReason(item, for: petID) {
                        feedback = reason
                    } else {
                        errorMessage = controller.alertMessage ?? String(localized: "Your changes could not be saved. Please try again.")
                        controller.alertMessage = nil
                    }
                }
            } label: { Text("Give").font(.subheadline.weight(.semibold)).frame(minWidth: 54, minHeight: 44) }
            .buttonStyle(.bordered)
            .disabled(isGiving || controller.isBusy || reason != nil)
            .accessibilityLabel("Give \(item.title) to \(pet.name)")
            .accessibilityIdentifier("profile.give.\(item.rawValue)")
        }
    }

    private func destinations(_ overview: PetProfileOverview) -> some View {
        VStack(spacing: 12) {
            destination("Wardrobe", detail: overview.pet.outfit?.headwear?.title ?? String(localized: "No accessory"), symbol: "sparkles", route: .wardrobe)
            destination(overview.walk != nil && overview.location != .walking ? "A find for you!" : "Walks",
                        detail: walkDetail(overview), symbol: "safari", route: .walks)
                .disabled(overview.location == .withYou && controller.discoveries.activeWalk == nil)
        }
    }

    private func walkDetail(_ overview: PetProfileOverview) -> String {
        if let walk = overview.walk {
            return overview.location == .walking ? walk.route.discoveryTitle : String(localized: "See the find")
        }
        if let other = controller.discoveries.activeWalk {
            return String(localized: "\(other.pet.name)'s walk is here. One friend explores at a time.")
        }
        if overview.location == .withYou { return String(localized: "Bring a pet home first") }
        return String(localized: "Pick a path")
    }

    private func destination(_ title: LocalizedStringKey, detail: String, symbol: String, route destination: Route) -> some View {
        Button { route = destination } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").font(.caption)
            }
            .padding(18).petSurface(radius: 22).contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.\(destination.rawValue)")
    }

    private func memories(_ memories: [PetDiscoveryMemory]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Walk memories").font(PetDesign.title(.title3)).accessibilityAddTraits(.isHeader)
            if memories.isEmpty {
                Label("Your first shared memory is still ahead. Bring back a find from a walk.", systemImage: "book.closed")
                    .font(.subheadline).foregroundStyle(PetDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(memories.prefix(3)) { memory in
                    Button { selectedMemory = memory } label: {
                        HStack(spacing: 12) {
                            DiscoveryIllustration(kind: memory.discovery, size: 44).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(memory.discovery.discoveryTitle).font(.subheadline.weight(.medium))
                                Text(memory.foundAt, format: .dateTime.day().month().year())
                                    .font(.caption).foregroundStyle(PetDesign.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .frame(minHeight: 52).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Button("All memories") { route = .album }
                    .frame(minHeight: 44).accessibilityIdentifier("profile.album")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).petSurface(radius: 22)
    }
}
