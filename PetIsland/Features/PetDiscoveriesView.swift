import SwiftUI

/// A dedicated sheet keeps walks and their album one tap away from the island.
struct PetDiscoveriesView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PetDiscoveriesContent(controller: controller)
                    .padding(20)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
            }
            .petPage()
            .navigationTitle("Walks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .disabled(controller.isBusy)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Walks use their saved return time without changing any pet sprite or animation.
private struct PetDiscoveriesContent: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsAlbum = false
    @State private var showsCancelConfirmation = false
    @State private var collectedMemory: PetDiscoveryMemory?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let walk = controller.discoveries.activeWalk {
                Group {
                    if scenePhase == .active, !walk.isReady(at: .now) {
                        // The UI displays whole minutes. The controller schedules
                        // the exact return once; no per-second polling is needed.
                        TimelineView(.periodic(from: walk.startedAt, by: 60)) { context in
                            walkContent(walk, at: context.date)
                        }
                    } else {
                        walkContent(walk, at: .now)
                    }
                }
                .padding(20)
                .petSurface()
            } else {
                PetDiscoveryWalkPicker(controller: controller)
            }
            Button { showsAlbum = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Finds album").font(.subheadline.weight(.semibold))
                        Text("\(controller.discoveries.discoveredKinds.count) of \(PetDiscoveryKind.allCases.count) treasures")
                            .font(.caption)
                            .foregroundStyle(PetDesign.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                }
                .padding(20)
                .petSurface()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("discoveries.album")
        }
        .foregroundStyle(PetDesign.ink)
        .sheet(isPresented: $showsAlbum) {
            PetDiscoveriesAlbum(controller: controller)
        }
        .sheet(item: $collectedMemory) { memory in
            PetDiscoveryMemoryView(memory: memory, isNew: true)
        }
        .confirmationDialog("End this walk?", isPresented: $showsCancelConfirmation, titleVisibility: .visible) {
            Button("End walk", role: .destructive) {
                Task { _ = await controller.cancelDiscoveryWalk() }
            }
        } message: {
            Text("Your pet will come home without a find. Everything in your album will stay.")
        }
    }

    private func walkContent(_ walk: PetDiscoveryWalk, at now: Date) -> some View {
        let ready = walk.isReady(at: now)
        return VStack(alignment: .leading, spacing: 15) {
            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
             : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                DiscoveryPetPortrait(pet: walk.pet)
                    .frame(width: 78, height: 68)
                    .background(PetDesign.soft, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 5) {
                    Text(ready ? String(localized: "A find for you!") : String(localized: "Out exploring"))
                        .font(.headline)
                    Text(walk.pet.name)
                        .font(.subheadline.weight(.medium))
                    Label(walk.route.discoveryTitle, systemImage: walk.route.discoverySymbol)
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if ready {
                Text("\(walk.pet.name) is home. Your find will wait here until you're ready.")
                    .font(.subheadline)
                    .foregroundStyle(PetDesign.secondary)
                Button {
                    Task { collectedMemory = await controller.collectDiscoveryWalk() }
                } label: {
                    Label("See the find", systemImage: "gift.fill")
                }
                .buttonStyle(PetPrimaryButtonStyle())
                .disabled(controller.isBusy)
                .accessibilityIdentifier("discoveries.collect")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: walk.progress(at: now))
                        .tint(PetDesign.accent)
                        .accessibilityLabel("Walk progress")
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            remainingTime(walk.endsAt.timeIntervalSince(now))
                            Spacer(minLength: 10)
                            returnTime(walk.endsAt)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            remainingTime(walk.endsAt.timeIntervalSince(now))
                            returnTime(walk.endsAt)
                        }
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PetDesign.secondary)
                }
                Button("End walk") { showsCancelConfirmation = true }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PetDesign.secondary)
                    .frame(minHeight: 44)
                    .disabled(controller.isBusy)
            }
        }
    }

    @ViewBuilder private func remainingTime(_ seconds: TimeInterval) -> some View {
        if seconds < 60 {
            Text("Almost back")
        } else {
            Text("\(Int(ceil(seconds / 60))) min left")
        }
    }

    private func returnTime(_ date: Date) -> some View {
        Text("Back at \(date.formatted(date: .omitted, time: .shortened))")
    }
}

private struct PetDiscoveryWalkPicker: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPetID: UUID?
    @State private var selectedRoute: PetWalkRoute = .garden
    @State private var isStarting = false

    private var selectedPet: PetProfile? {
        controller.availableDiscoveryPets.first { $0.id == selectedPetID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Who's going?").font(PetDesign.title(.title3))
                if controller.availableDiscoveryPets.isEmpty {
                    Label("Bring a pet home from Dynamic Island before starting a walk.", systemImage: "house")
                        .font(.subheadline)
                        .foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .petSurface(radius: 20)
                } else {
                    HStack(spacing: 16) {
                        if let pet = selectedPet {
                            DiscoveryPetPortrait(pet: pet)
                                .frame(width: 76, height: 66)
                                .accessibilityHidden(true)
                        }
                        Picker("Walk companion", selection: $selectedPetID) {
                            if selectedPetID == nil {
                                Text("Choose a pet").tag(Optional<UUID>.none)
                            }
                            ForEach(controller.availableDiscoveryPets) { pet in
                                Text(pet.name).tag(Optional(pet.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(PetDesign.ink)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .disabled(isStarting)
                    }
                    .padding(12)
                    .petSurface(radius: 20)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a path").font(PetDesign.title(.title3))
                ForEach(PetWalkRoute.allCases, id: \.self) { route in
                    routeButton(route)
                }
            }
            Label {
                Text("Your pet leaves the enclosure for the walk and returns automatically. You can close the app; the find will wait for you.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "moon.stars")
            }
            .font(.footnote)
            .foregroundStyle(PetDesign.secondary)
            .padding(.horizontal, 2)
            Button {
                guard let petID = selectedPetID, !isStarting else { return }
                isStarting = true
                Task {
                    _ = await controller.startDiscoveryWalk(petID: petID, route: selectedRoute)
                    isStarting = false
                }
            } label: {
                if isStarting {
                    Label("Getting ready…", systemImage: "hourglass")
                } else if controller.availableDiscoveryPets.isEmpty {
                    Label("Bring a pet home first", systemImage: "house")
                } else {
                    Label("Start walk", systemImage: "pawprint.fill")
                }
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .disabled(selectedPet == nil || isStarting || controller.isBusy || controller.discoveries.activeWalk != nil)
            .accessibilityIdentifier("discoveries.confirmStart")
        }
        .interactiveDismissDisabled(isStarting)
        .onChange(of: controller.availableDiscoveryPets.map(\.id), initial: true) { _, availableIDs in
            if selectedPetID.map({ !availableIDs.contains($0) }) ?? true {
                selectedPetID = availableIDs.contains(controller.profile.id)
                    ? controller.profile.id : availableIDs.first
            }
        }
    }

    private func routeButton(_ route: PetWalkRoute) -> some View {
        let selected = selectedRoute == route
        return Button { selectedRoute = route } label: {
            HStack(alignment: .center, spacing: 10) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: route.discoverySymbol)
                        .font(.body)
                        .foregroundStyle(route.discoveryTint)
                        .frame(width: 34, height: 34)
                        .background(route.discoveryTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 4) {
                    (dynamicTypeSize.isAccessibilitySize
                     ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                     : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                        Text(route.discoveryTitle)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(route.discoveryMinutes) min")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(PetDesign.secondary)
                            .fixedSize()
                    }
                    Text(route.discoverySubtitle)
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? PetDesign.accent : PetDesign.secondary)
                    .font(.body)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 64)
            .petSurface(radius: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? PetDesign.accent : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .disabled(isStarting)
    }
}

private struct PetDiscoveriesAlbum: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedMemory: PetDiscoveryMemory?

    private var newestMemories: [PetDiscoveryMemory] {
        controller.discoveries.memories.sorted { $0.foundAt > $1.foundAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Small things, sweet memories.")
                            .font(PetDesign.title(.title2))
                        Text("\(controller.discoveries.discoveredKinds.count) of \(PetDiscoveryKind.allCases.count) treasures")
                            .font(.subheadline)
                            .foregroundStyle(PetDesign.secondary)
                        if newestMemories.isEmpty {
                            Text("Every walk brings a little something. Your first find is waiting out there.")
                                .font(.subheadline)
                                .foregroundStyle(PetDesign.secondary)
                                .padding(.top, 3)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 135), spacing: 12)], spacing: 12) {
                        ForEach(PetDiscoveryKind.allCases, id: \.self) { kind in
                            treasureTile(kind)
                        }
                    }
                    if !newestMemories.isEmpty {
                        Text("Walk memories")
                            .font(PetDesign.title(.title3))
                            .accessibilityAddTraits(.isHeader)
                        ForEach(newestMemories) { memory in
                            Button { selectedMemory = memory } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    DiscoveryIllustration(kind: memory.discovery, size: 54)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(memory.discovery.discoveryTitle).font(.headline)
                                        Text(memory.pet.name).font(.subheadline)
                                        Text(memory.foundAt, format: .dateTime.day().month().year())
                                            .font(.caption)
                                            .foregroundStyle(PetDesign.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(PetDesign.secondary)
                                        .padding(.top, 8)
                                }
                                .padding(16)
                                .petSurface(radius: 20)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(24)
            }
            .navigationTitle("Finds album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .petPage()
        }
        .sheet(item: $selectedMemory) { memory in
            PetDiscoveryMemoryView(memory: memory, isNew: false)
        }
    }

    private func treasureTile(_ kind: PetDiscoveryKind) -> some View {
        let memory = newestMemories.first { $0.discovery == kind }
        return Button {
            selectedMemory = memory
        } label: {
            VStack(spacing: 12) {
                if memory != nil {
                    DiscoveryIllustration(kind: kind, size: 86)
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(PetDesign.secondary.opacity(0.65))
                        .frame(width: 86, height: 86)
                        .background(PetDesign.soft, in: Circle())
                }
                Text(memory == nil ? String(localized: "Still a mystery") : kind.discoveryTitle)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                if memory == nil {
                    Text(kind.discoveryRoute.discoveryTitle)
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .top)
            .padding(14)
            .petSurface(radius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .disabled(memory == nil)
        .accessibilityElement(children: .combine)
    }
}

private struct PetDiscoveryMemoryView: View {
    let memory: PetDiscoveryMemory
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    DiscoveryIllustration(kind: memory.discovery, size: 160)
                        .padding(.top, 12)
                    VStack(spacing: 12) {
                        if isNew {
                            Text("A little treasure for you")
                                .font(.subheadline)
                                .foregroundStyle(PetDesign.secondary)
                        }
                        Text(memory.discovery.discoveryTitle)
                            .font(PetDesign.title(.largeTitle))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(memory.discovery.discoveryStory(petName: memory.pet.name))
                            .font(.body)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    VStack(spacing: 6) {
                        DiscoveryPetPortrait(pet: memory.pet)
                            .frame(width: 100, height: 80)
                        Text(memory.pet.name).font(.headline)
                        Label(memory.route.discoveryTitle, systemImage: memory.route.discoverySymbol)
                        Text(memory.foundAt, format: .dateTime.day().month().year())
                    }
                    .font(.caption)
                    .foregroundStyle(PetDesign.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .petSurface()
                    if isNew {
                        Label("Saved in your album", systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(PetDesign.secondary)
                    }
                    ShareLink(item: "\(memory.discovery.discoveryTitle)\n\(memory.discovery.discoveryStory(petName: memory.pet.name))") {
                        Label("Share a memory", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PetQuietButtonStyle())
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(isNew ? String(localized: "A new memory") : String(localized: "Walk memory"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .petPage()
        }
    }
}

private struct DiscoveryPetPortrait: View {
    let pet: PetProfile

    var body: some View {
        PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                   breed: pet.resolvedBreed, pose: pet.species == .parrot ? .fly : .idle,
                   animatesMotion: false)
            .padding(5)
            .accessibilityHidden(true)
    }
}

/// Small vector keepsakes stay crisp at every text size and don't add any pet sprite variants.
private struct DiscoveryIllustration: View {
    let kind: PetDiscoveryKind
    var size: CGFloat = 100

    var body: some View {
        ZStack {
            Circle().fill(kind.discoveryRoute.discoveryTint.opacity(0.1))
            Circle().strokeBorder(kind.discoveryRoute.discoveryTint.opacity(0.12), lineWidth: 1)
            artwork
                .foregroundStyle(kind.discoveryRoute.discoveryTint)
        }
        .frame(width: 100, height: 100)
        .scaleEffect(size / 100)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var artwork: some View {
        switch kind {
        case .stripedPebble:
            Ellipse().fill(PetDesign.adaptive(0x9CA7B2, 0xADBAC7))
                .overlay {
                    VStack(spacing: 9) {
                        Capsule().fill(.white.opacity(0.65)).frame(height: 4)
                        Capsule().fill(.white.opacity(0.65)).frame(height: 4)
                    }
                    .rotationEffect(.degrees(-28))
                    .clipShape(Ellipse())
                }
                .frame(width: 58, height: 42)
                .rotationEffect(.degrees(-12))
        case .clover:
            ZStack {
                ForEach(0..<4) { index in
                    Image(systemName: "heart.fill")
                        .font(.system(size: 27))
                        .offset(y: -13)
                        .rotationEffect(.degrees(Double(index) * 90))
                }
            }
            .rotationEffect(.degrees(-12))
        case .tinyFlower:
            Image(systemName: "camera.macro").font(.system(size: 49, weight: .light))
                .foregroundStyle(PetDesign.adaptive(0xB87B87, 0xDFA5B0))
        case .ribbon:
            ZStack {
                Capsule().frame(width: 17, height: 39).rotationEffect(.degrees(20)).offset(x: -7, y: 17)
                Capsule().frame(width: 17, height: 39).rotationEffect(.degrees(-20)).offset(x: 7, y: 17)
                Ellipse().frame(width: 32, height: 23).rotationEffect(.degrees(28)).offset(x: -13, y: -5)
                Ellipse().frame(width: 32, height: 23).rotationEffect(.degrees(-28)).offset(x: 13, y: -5)
                Circle().fill(.white.opacity(0.25)).frame(width: 14, height: 14).offset(y: -5)
            }
            .foregroundStyle(PetDesign.adaptive(0xB07F8E, 0xD5A6B3))
        case .shell:
            Image(systemName: "fossil.shell.fill").font(.system(size: 50))
                .foregroundStyle(PetDesign.adaptive(0xB18D78, 0xD7B59C))
                .rotationEffect(.degrees(-15))
        case .seaGlass:
            RoundedRectangle(cornerRadius: 14)
                .fill(PetDesign.adaptive(0x77AAA9, 0x97CCCB))
                .frame(width: 40, height: 51)
                .overlay(alignment: .topLeading) {
                    Capsule().fill(.white.opacity(0.5)).frame(width: 4, height: 24).padding(9)
                }
                .rotationEffect(.degrees(24))
        case .driftwood:
            Capsule().fill(PetDesign.adaptive(0xA18A73, 0xCCB8A1))
                .frame(width: 66, height: 19)
                .overlay {
                    Capsule().fill(.white.opacity(0.3)).frame(width: 47, height: 3).offset(y: -3)
                }
                .rotationEffect(.degrees(-25))
        case .smoothStone:
            Ellipse().fill(PetDesign.adaptive(0x97A1B0, 0xB8C3D2))
                .frame(width: 55, height: 43)
                .overlay(alignment: .topLeading) {
                    Ellipse().fill(.white.opacity(0.25)).frame(width: 26, height: 12).padding(9)
                }
                .rotationEffect(.degrees(-18))
        case .feather:
            Image(systemName: "leaf.fill").font(.system(size: 51, weight: .light))
                .foregroundStyle(PetDesign.adaptive(0xA897B5, 0xC9BBD5))
                .overlay { Capsule().fill(.white.opacity(0.6)).frame(width: 3, height: 46).rotationEffect(.degrees(40)) }
        case .pinecone:
            ZStack {
                ForEach(0..<4) { row in
                    Capsule()
                        .frame(width: CGFloat(20 + row * 7), height: 17)
                        .offset(y: CGFloat(row * 10 - 15))
                        .opacity(1 - Double(row) * 0.1)
                }
            }
            .foregroundStyle(PetDesign.adaptive(0x927663, 0xC8A98D))
            .rotationEffect(.degrees(-15))
        case .acorn:
            ZStack {
                Capsule().frame(width: 5, height: 13).rotationEffect(.degrees(15)).offset(y: -24)
                Ellipse().fill(PetDesign.adaptive(0xBB9672, 0xD6B18E)).frame(width: 35, height: 44).offset(y: 7)
                Capsule().frame(width: 43, height: 20).offset(y: -8)
            }
            .foregroundStyle(PetDesign.adaptive(0x866D5B, 0xAB9079))
            .rotationEffect(.degrees(15))
        case .mapleLeaf:
            Image(systemName: "leaf.fill").font(.system(size: 53))
                .foregroundStyle(PetDesign.adaptive(0xC28B67, 0xE0AD86))
                .rotationEffect(.degrees(-32))
        }
    }
}

private extension PetWalkRoute {
    var discoveryTitle: String {
        switch self {
        case .garden: String(localized: "Quiet garden")
        case .shore: String(localized: "Along the shore")
        case .grove: String(localized: "Little grove")
        }
    }

    var discoverySubtitle: String {
        switch self {
        case .garden: String(localized: "Soft grass and tiny surprises.")
        case .shore: String(localized: "Waves, warm sand and sea treasures.")
        case .grove: String(localized: "Rustling leaves and hidden keepsakes.")
        }
    }

    var discoveryMinutes: Int {
        Int(duration / 60)
    }

    var discoverySymbol: String {
        switch self { case .garden: "leaf"; case .shore: "water.waves"; case .grove: "tree" }
    }

    var discoveryTint: Color {
        switch self {
        case .garden: PetDesign.adaptive(0x758879, 0xA8BCAB)
        case .shore: PetDesign.adaptive(0x668B9F, 0x9EBFCF)
        case .grove: PetDesign.adaptive(0x9D8069, 0xCDB095)
        }
    }
}

private extension PetDiscoveryKind {
    var discoveryTitle: String {
        switch self {
        case .stripedPebble: String(localized: "Striped pebble")
        case .clover: String(localized: "Lucky clover")
        case .tinyFlower: String(localized: "Tiny flower")
        case .ribbon: String(localized: "Little ribbon")
        case .shell: String(localized: "Seashell")
        case .seaGlass: String(localized: "Sea glass")
        case .driftwood: String(localized: "Driftwood")
        case .smoothStone: String(localized: "Smooth stone")
        case .feather: String(localized: "Soft feather")
        case .pinecone: String(localized: "Pinecone")
        case .acorn: String(localized: "Acorn")
        case .mapleLeaf: String(localized: "Amber leaf")
        }
    }

    var discoveryRoute: PetWalkRoute {
        switch self {
        case .stripedPebble, .clover, .tinyFlower, .ribbon: .garden
        case .shell, .seaGlass, .driftwood, .smoothStone: .shore
        case .feather, .pinecone, .acorn, .mapleLeaf: .grove
        }
    }

    func discoveryStory(petName: String) -> String {
        switch self {
        case .stripedPebble: String(localized: "\(petName) thinks this pebble is a tiny sleeping egg. Please keep it somewhere cosy.")
        case .clover: String(localized: "\(petName) checked every leaf. This one has enough luck for both of you.")
        case .tinyFlower: String(localized: "\(petName) found the smallest flower in the garden. Somehow, it makes the whole island feel brighter.")
        case .ribbon: String(localized: "\(petName) insists this ribbon belongs on something important. Your album will do nicely.")
        case .shell: String(localized: "\(petName) listened to this shell for a long time. Apparently, the sea says hello.")
        case .seaGlass: String(localized: "\(petName) spotted a piece of the sea that fits in a paw. It catches the light just for you.")
        case .driftwood: String(localized: "\(petName) thinks this is a very small boat. All it needs is a captain.")
        case .smoothStone: String(localized: "\(petName) chose the smoothest stone on the beach. A tiny piece of calm to bring home.")
        case .feather: String(localized: "\(petName) followed this feather as it floated down. The sky must have sent you a present.")
        case .pinecone: String(localized: "\(petName) carefully counted the scales. Then lost count. It is a very good pinecone anyway.")
        case .acorn: String(localized: "\(petName) found a tiny hat with an acorn underneath. A whole tree, tucked into your album.")
        case .mapleLeaf: String(localized: "\(petName) caught a leaf before it touched the ground. A little piece of sunshine, saved for later.")
        }
    }
}
