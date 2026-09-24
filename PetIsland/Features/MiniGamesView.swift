import SwiftUI

private struct ActiveArcadeSession: Identifiable {
    let game: MiniGameKind
    let pet: PetProfile

    var id: String { "\(game.rawValue)-\(pet.id.uuidString)" }
}

private enum ArcadePage: Hashable {
    case games
    case shop
}

struct MiniGamesView: View {
    @ObservedObject var controller: PetSessionController
    var showsDismissButton = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedPetID: UUID?
    @State private var activeSession: ActiveArcadeSession?
    @State private var message: String?
    @State private var selectedPage: ArcadePage = .games

    init(controller: PetSessionController, showsDismissButton: Bool = true) {
        self.controller = controller
        self.showsDismissButton = showsDismissButton
        _selectedPetID = State(initialValue: controller.pets.first?.id)
        _selectedPage = State(
            initialValue: ProcessInfo.processInfo.arguments.contains("-arcade-shop-preview")
                ? .shop
                : .games
        )
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 18, pinnedViews: [.sectionHeaders]) {
                        walletHeader
                        petPicker
                        if let selectedPet {
                            Section {
                                arcadeContent(for: selectedPet)
                            } header: {
                                arcadePageHeader(for: selectedPet)
                                    .id("arcade-page-header")
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                }
                .onChange(of: selectedPage) { _, _ in
                    withAnimation(.snappy) {
                        scrollProxy.scrollTo("arcade-page-header", anchor: .top)
                    }
                }
            }
            .background(PetDesign.background)
            .petPage()
            .navigationTitle(showsDismissButton ? "Pet Arcade" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsDismissButton ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            switch session.game {
            case .skyHop:
                SkyHopGameView(
                    pet: session.pet,
                    highScore: controller.arcadeProgress.highScore(for: .skyHop)
                ) { score, runID in
                    await controller.completeMiniGame(.skyHop, score: score, petID: session.pet.id, runID: runID)
                }
            case .skyPaws:
                SkyPawsGameView(
                    pet: session.pet,
                    highScore: controller.arcadeProgress.highScore(for: .skyPaws)
                ) { score, runID in
                    await controller.completeMiniGame(.skyPaws, score: score, petID: session.pet.id, runID: runID)
                }
            case .petsDash:
                PetsDashGameView(
                    pet: session.pet,
                    highScore: controller.arcadeProgress.highScore(for: .petsDash)
                ) { score, runID in
                    await controller.completeMiniGame(.petsDash, score: score, petID: session.pet.id, runID: runID)
                }
            }
        }
        .alert("Pet Arcade", isPresented: messageIsPresented) {
            Button("OK", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onChange(of: controller.pets.map(\.id), initial: true) { _, petIDs in
            if let selectedPetID, petIDs.contains(selectedPetID) {
            } else {
                selectedPetID = petIDs.first
            }
            if ProcessInfo.processInfo.arguments.contains("-pets-dash-preview"),
               activeSession == nil,
               let selectedPet {
                activeSession = ActiveArcadeSession(game: .petsDash, pet: selectedPet)
            } else if ProcessInfo.processInfo.arguments.contains("-sky-paws-preview"),
               activeSession == nil,
               let selectedPet {
                activeSession = ActiveArcadeSession(game: .skyPaws, pet: selectedPet)
            } else if ProcessInfo.processInfo.arguments.contains("-sky-hop-preview"),
                      activeSession == nil,
                      let selectedPet {
                activeSession = ActiveArcadeSession(game: .skyHop, pet: selectedPet)
            }
        }
    }

    private var selectedPet: PetProfile? {
        guard let selectedPetID else { return controller.pets.first }
        return controller.pets.first { $0.id == selectedPetID }
    }

    private var messageIsPresented: Binding<Bool> {
        Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }

    @ViewBuilder
    private func arcadeContent(for pet: PetProfile) -> some View {
        switch selectedPage {
        case .games:
            VStack(spacing: 18) {
                vitalsCard(for: pet)
                skyHopCard(for: pet)
                skyPawsCard(for: pet)
                petsDashCard(for: pet)
                economyCard
            }
        case .shop:
            shop(for: pet)
        }
    }

    private func arcadePageHeader(for pet: PetProfile) -> some View {
        VStack(spacing: 10) {
            Picker("Arcade section", selection: $selectedPage) {
                Text("Games").tag(ArcadePage.games)
                Text("Shop").tag(ArcadePage.shop)
            }
            .pickerStyle(.segmented)

            if selectedPage == .shop {
                shopStatusBar(for: pet)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.vertical, 10)
        .background(PetDesign.background)
        .zIndex(1)
    }

    private func shopStatusBar(for pet: PetProfile) -> some View {
        let vitals = controller.vitals(for: pet.id)

        return VStack(spacing: 9) {
            HStack {
                Label(pet.name, systemImage: "pawprint.fill")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Spacer()
                Label("\(controller.arcadeProgress.coins)", systemImage: "dollarsign.circle.fill")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                compactVital("fork.knife", value: vitals.fullness, color: PetDesign.accent)
                compactVital("heart.fill", value: vitals.happiness, color: PetDesign.accent)
                compactVital("bolt.fill", value: vitals.energy, color: PetDesign.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            PetDesign.surface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func compactVital(_ symbol: String, value: Double, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.bold())
            ProgressView(value: value)
                .tint(color)
            Text("\(Int(value * 100))%")
                .font(.caption2.bold().monospacedDigit())
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var walletHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            PetScreenHeading(title: "Games")
            Label("\(controller.arcadeProgress.coins)", systemImage: "circle.circle")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(PetDesign.soft, in: Capsule())
                .accessibilityLabel("\(controller.arcadeProgress.coins) coins")
        }
    }

    private var petPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your player")
                .font(.headline)

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(controller.pets) { pet in
                        let isSelected = selectedPetID == pet.id
                        Button {
                            selectedPetID = pet.id
                        } label: {
                            VStack(spacing: 7) {
                                PetArtwork(
                                    species: pet.species,
                                    coat: pet.coat,
                                    customColor: pet.customColor,
                                    breed: pet.resolvedBreed,
                                    pose: pet.species == .parrot ? .fly : .jump,
                                    step: 0,
                                    animatesMotion: false
                                )
                                .frame(width: 68, height: 58)
                                Text(pet.name)
                                    .font(.caption.bold())
                                    .lineLimit(1)
                            }
                            .frame(width: 88, height: 94)
                            .background(
                                isSelected ? PetDesign.soft : Color.clear,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(isSelected ? PetDesign.separator : .clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func vitalsCard(for pet: PetProfile) -> some View {
        let vitals = controller.vitals(for: pet.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How \(pet.name) feels")
                    .font(.headline)
                Spacer()
                if vitals.energy < ArcadeEconomy.tiredEnergyThreshold {
                    Label("Tired", systemImage: "moon.zzz.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 12) {
                vital("fork.knife", value: vitals.fullness, color: PetDesign.accent, title: "Full")
                vital("heart.fill", value: vitals.happiness, color: PetDesign.accent, title: "Happy")
                vital("bolt.fill", value: vitals.energy, color: PetDesign.accent, title: "Energy")
            }
        }
        .padding(16)
        .background(
            PetDesign.surface,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func vital(_ symbol: String, value: Double, color: Color, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.caption.bold())
                .foregroundStyle(color)
            ProgressView(value: value)
                .tint(color)
            Text("\(Int(value * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func skyHopCard(for pet: PetProfile) -> some View {
        arcadeGameCard(for: pet, game: .skyHop, title: "Sky Hop",
                       subtitle: "Jump between platforms and avoid obstacles.")
    }

    private func skyPawsCard(for pet: PetProfile) -> some View {
        arcadeGameCard(for: pet, game: .skyPaws, title: "Sky Paws",
                       subtitle: "Tap to fly through the cloud gates.")
    }

    private func petsDashCard(for pet: PetProfile) -> some View {
        arcadeGameCard(for: pet, game: .petsDash, title: "Pets Dash",
                       subtitle: "Dodge obstacles and collect coins.")
    }

    private func arcadeGameCard(
        for pet: PetProfile, game: MiniGameKind,
        title: LocalizedStringKey, subtitle: LocalizedStringKey
    ) -> some View {
        Button { activeSession = ActiveArcadeSession(game: game, pet: pet) } label: {
            HStack(spacing: 16) {
                ArcadeGameCover(pet: pet, game: game)
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(PetDesign.title(.title2))
                    Text(subtitle)
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text("Play").font(.caption.weight(.semibold))
                        Image(systemName: "arrow.up.right").font(.caption)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .petSurface()
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Play as \(pet.name)")
    }

    private func shop(for pet: PetProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Prize shop", systemImage: "storefront.fill")
                    .font(.title3.bold())
                Spacer()
                Text("For \(pet.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize
                      ? [GridItem(.flexible())]
                      : [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ArcadeItemKind.allCases) { item in
                    shopItem(item, pet: pet)
                }
            }
        }
    }

    private func shopItem(_ item: ArcadeItemKind, pet: PetProfile) -> some View {
        let price = ArcadeEconomy.price(of: item)
        let owned = controller.arcadeProgress.inventory[item]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: item.symbol)
                    .font(.title2)
                    .foregroundStyle(item.color)
                    .frame(width: 34, height: 34)
                    .background(item.color.opacity(0.12), in: Circle())
                Spacer()
                if owned > 0 {
                    Text("×\(owned)")
                        .font(.caption.bold().monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            Text(item.title)
                .font(.headline)
            Text(item.effectDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    Task {
                        if await controller.purchaseArcadeItem(item) {
                            message = String(localized: "\(item.title) added to your inventory.")
                        } else if controller.arcadeProgress.coins < price {
                            message = String(localized: "You need \(price) coins to buy \(item.title.lowercased()).")
                        } else {
                            showShopSaveFailure()
                        }
                    }
                } label: {
                    Label("\(price)", systemImage: "dollarsign.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(controller.isBusy || controller.arcadeProgress.coins < price)
                .accessibilityLabel("Buy \(item.title) for \(price) coins")

                Button {
                    Task {
                        if await controller.useArcadeItem(item, for: pet.id) {
                            message = String(localized: "\(pet.name) used \(item.title.lowercased()).")
                        } else {
                            showShopSaveFailure()
                        }
                    }
                } label: {
                    Text("Give")
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PetPrimaryButtonStyle())
                .disabled(controller.isBusy || owned == 0)
                .accessibilityLabel("Give \(item.title) to \(pet.name)")
            }
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(
            PetDesign.surface,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private func showShopSaveFailure() {
        message = controller.alertMessage
            ?? String(localized: "Arcade progress could not be saved. Please try again.")
        controller.alertMessage = nil
    }

    private var economyCard: some View {
        DisclosureGroup {
            Text("Rest gently restores energy. Time away never takes food or happiness away.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Playing lifts happiness and spends a little fullness and energy. A tired pet can still play, but earns 25% fewer performance coins. Food and items never expire, and there are no paid currencies.")
                .font(.footnote)
                .foregroundStyle(PetDesign.secondary)
                .padding(.top, 10)
        } label: {
            Label("A fair rhythm", systemImage: "heart")
                .font(.subheadline)
        }
        .padding(18)
        .petSurface()
    }

}

/// Keeps long instructions and rewards reachable at accessibility text sizes.
struct GamePanelViewport<Content: View>: View {
    let safeArea: EdgeInsets
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content.fixedSize(horizontal: false, vertical: true)
            ScrollView {
                content.fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, max(safeArea.top, 58))
        .padding(.bottom, max(safeArea.bottom, 24))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

struct GamePausePanel: View {
    let safeArea: EdgeInsets
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onResume: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { }
                .accessibilityHidden(true)
            GamePanelViewport(safeArea: safeArea) {
                panel.padding(.horizontal, 20)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private var panel: some View {
        VStack(spacing: 18) {
            Image(systemName: "moon.zzz").font(.title2)
            Text("Pause").font(.system(.title2, design: .rounded).bold())
            Text("Your game is waiting for you.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Keep playing", action: onResume)
                .buttonStyle(PetPrimaryButtonStyle())
            Button("Leave this game", action: onExit)
                .font(.subheadline)
            Text("An unfinished game does not earn a reward.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}

private struct SkyHopGameView: View {
    let pet: PetProfile
    let highScore: Int
    let onFinish: (Int, UUID) async -> ArcadePayout?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = SkyHopEngine()
    @State private var lastTick: Date?
    @State private var payout: ArcadePayout?
    @State private var isSavingResult = false
    @State private var didSaveResult = false
    @State private var runID = UUID()
    @State private var isPaused = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active || isPaused || engine.phase != .playing)) { timeline in
                ZStack {
                    ArcadeSky(travel: engine.climbedDistance, vertical: true)
                    platforms
                    obstacles
                    player
                    gameHUD(insets: proxy.safeAreaInsets)
                        .disabled(isPaused)
                        .accessibilityHidden(isPaused)

                    if isPaused {
                        GamePausePanel(safeArea: proxy.safeAreaInsets) {
                            lastTick = nil
                            isPaused = false
                        } onExit: { dismiss() }
                        .zIndex(100)
                    }
                    if engine.phase == .ready {
                        GamePanelViewport(safeArea: proxy.safeAreaInsets) {
                            startOverlay(size: proxy.size)
                        }
                    } else if engine.phase == .gameOver {
                        GamePanelViewport(safeArea: proxy.safeAreaInsets) {
                            gameOverOverlay(size: proxy.size)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(steeringGesture(in: proxy.size), including: engine.phase == .playing && !isPaused ? .all : .subviews)
                .onChange(of: timeline.date) { oldDate, newDate in
                    tick(from: oldDate, to: newDate, size: proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    engine.resize(to: newSize)
                }
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-sky-hop-autostart"),
                       engine.phase == .ready {
                        restart(in: proxy.size)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                lastTick = nil
                engine.setSteering(0)
                if engine.phase == .playing { isPaused = true }
            }
        }
    }

    private var platforms: some View {
        ForEach(engine.platforms) { platform in
            let progress = platform.crumbleProgress
            ArcadePlatformArtwork(fragile: platform.kind == .fragile)
                .frame(width: platform.width, height: 30)
                .rotationEffect(.degrees(Double(platform.id.isMultiple(of: 2) ? progress * 11 : -progress * 11)))
                .scaleEffect(x: 1 - progress * 0.16, y: 1 - progress * 0.4)
                .opacity(1 - progress)
                .position(x: platform.x, y: platform.y + 15)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var obstacles: some View {
        ForEach(engine.obstacles) { obstacle in
            obstacleArtwork(obstacle)
                .frame(width: obstacle.size, height: obstacle.size)
                .position(x: obstacle.x, y: obstacle.y)
                .shadow(color: .black.opacity(0.24), radius: 5, y: 4)
                .accessibilityHidden(true)
        }
    }

    private func obstacleArtwork(_ obstacle: SkyHopObstacle) -> some View {
        ArcadeHazardArtwork(storm: obstacle.kind == .stormCloud, rotation: engine.elapsedTime * 45)
    }

    private var player: some View {
        PetArtwork(
            species: pet.species,
            coat: pet.coat,
            customColor: pet.customColor,
            breed: pet.resolvedBreed,
            pose: pet.species == .parrot ? .fly : .jump,
            direction: engine.facingLeft ? .left : .right,
            step: Int(engine.elapsedTime * 10),
            animatesMotion: false
        )
        .frame(width: SkyHopEngine.playerSize.width, height: SkyHopEngine.playerSize.height)
        .position(engine.playerPosition)
        .contentTransition(.identity)
        .transaction { transaction in transaction.animation = nil }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 4)
        .accessibilityLabel("\(pet.name), jumping")
    }

    private func gameHUD(insets: EdgeInsets) -> some View {
        VStack {
            ArcadeHUD(score: engine.score, highScore: highScore, playing: engine.phase == .playing) {
                if engine.phase == .playing { engine.setSteering(0); isPaused = true } else { dismiss() }
            }
            .padding(.top, max(insets.top, 54) + 8)
            Spacer()
            if engine.phase == .playing {
                HStack(spacing: 12) {
                    controlHint(symbol: "arrow.left", direction: -1)
                    Text("Hold either side to steer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ArcadePalette.ink)
                        .multilineTextAlignment(.center)
                    controlHint(symbol: "arrow.right", direction: 1)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, max(insets.bottom, 24) + 8)
            }
        }
    }

    private func controlHint(symbol: String, direction: Double) -> some View {
        Button { engine.nudgeSteering(direction) } label: { Image(systemName: symbol) }
            .buttonStyle(ArcadeControlStyle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in engine.setSteering(direction) }
                    .onEnded { _ in engine.setSteering(0) }
            )
    }

    private func startOverlay(size: CGSize) -> some View {
        VStack(spacing: 16) {
            PetArtwork(
                species: pet.species,
                coat: pet.coat,
                customColor: pet.customColor,
                breed: pet.resolvedBreed,
                pose: pet.species == .parrot ? .fly : .jump,
                step: 0,
                animatesMotion: false
            )
            .frame(width: 110, height: 92)
            Text("Ready, \(pet.name)?")
                .font(.system(.title2, design: .rounded).bold())
            Text("Land on platforms and climb as high as you can.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                Label("Fragile platforms break after one landing.", systemImage: "bolt.fill")
                    .foregroundStyle(.orange)
                Label("Avoid storm clouds and spike orbs.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            .font(.footnote.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                restart(in: size)
            } label: {
                Label("Start jumping", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .controlSize(.large)
            Button("Back to Arcade") { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private func gameOverOverlay(size: CGSize) -> some View {
        VStack(spacing: 14) {
            Text(gameOverTitle)
                .font(.system(.title2, design: .rounded).bold())
            Text("\(engine.score) points")
                .font(.title2.monospacedDigit())

            if case .obstacle? = engine.gameOverReason {
                Text("Watch the hazards and try another route.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isSavingResult {
                ProgressView("Counting coins…")
            } else if let payout {
                Label("+\(payout.coinsEarned) coins", systemImage: "dollarsign.circle.fill")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
                if payout.receivedDailyBonus {
                    Text("Includes the +\(ArcadeEconomy.firstGameDailyBonus) first-game bonus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if payout.wasTired {
                    Text("\(pet.name) was tired, so performance coins were reduced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button {
                restart(in: size)
            } label: {
                Label("Play again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(isSavingResult || !didSaveResult)

            if payout == nil && !isSavingResult {
                Text("Your reward is not saved yet. Retry before starting another game.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Save reward again") { saveResultIfNeeded() }
            }
            Button(payout == nil ? "Leave without reward" : "Back to Arcade") { dismiss() }
                .disabled(isSavingResult)
        }
        .padding(24)
        .frame(maxWidth: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private func steeringGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard engine.phase == .playing, !isPaused else { return }
                engine.setSteering(value.location.x < size.width / 2 ? -1 : 1)
            }
            .onEnded { _ in engine.setSteering(0) }
    }

    private var gameOverTitle: String {
        if payout?.isNewHighScore == true { return String(localized: "New record!") }
        if case .obstacle? = engine.gameOverReason { return String(localized: "Obstacle hit!") }
        return String(localized: "Nice jump!")
    }

    private func tick(from oldDate: Date, to newDate: Date, size: CGSize) {
        guard engine.phase == .playing, scenePhase == .active, !isPaused else {
            lastTick = nil
            return
        }
        let anchor = lastTick ?? oldDate
        lastTick = newDate
        engine.update(deltaTime: newDate.timeIntervalSince(anchor), in: size)
        if engine.phase == .gameOver { saveResultIfNeeded() }
    }

    private func restart(in size: CGSize) {
        isPaused = false
        runID = UUID()
        payout = nil
        isSavingResult = false
        didSaveResult = false
        lastTick = nil
        engine.start(in: size)
    }

    private func saveResultIfNeeded() {
        guard !didSaveResult, !isSavingResult else { return }
        didSaveResult = true
        isSavingResult = true
        let finalScore = engine.score
        Task {
            payout = await onFinish(finalScore, runID)
            didSaveResult = payout != nil
            isSavingResult = false
        }
    }
}

enum SkyHopPlatformKind: Equatable {
    case stable
    case fragile
}

struct SkyHopPlatform: Identifiable, Equatable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var kind: SkyHopPlatformKind
    var crumbleElapsed: CGFloat?

    init(
        id: Int,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        kind: SkyHopPlatformKind = .stable,
        crumbleElapsed: CGFloat? = nil
    ) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.kind = kind
        self.crumbleElapsed = crumbleElapsed
    }

    var crumbleProgress: CGFloat {
        min(max((crumbleElapsed ?? 0) / SkyHopEngine.crumbleDuration, 0), 1)
    }

    var isSolid: Bool { crumbleElapsed == nil }
}

enum SkyHopObstacleKind: Equatable {
    case stormCloud
    case spikeOrb
}

struct SkyHopObstacle: Identifiable, Equatable {
    let id: Int
    var kind: SkyHopObstacleKind
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
}

enum SkyHopGameOverReason: Equatable {
    case fell
    case obstacle(SkyHopObstacleKind)
}

struct SkyHopEngine {
    enum Phase: Equatable {
        case ready
        case playing
        case gameOver
    }

    static let playerSize = CGSize(width: 58, height: 52)
    static let platformHeight: CGFloat = 13
    static let crumbleDuration: CGFloat = 0.36

    var phase: Phase = .ready
    var playerPosition = CGPoint(x: 180, y: 500)
    var velocity = CGVector.zero
    var steering = 0.0
    var score = 0
    var platforms: [SkyHopPlatform] = []
    var obstacles: [SkyHopObstacle] = []
    var elapsedTime = 0.0
    var gameOverReason: SkyHopGameOverReason?

    private(set) var climbedDistance: CGFloat = 0
    private(set) var facingLeft = false
    private var steeringPulseRemaining: TimeInterval = 0
    private var clock = ArcadeSimulationClock()
    private var nextPlatformID = 0
    private var nextObstacleID = 0
    private var generatedPlatformCount = 0
    private var stablePlatformStreak = 0
    private var randomState: UInt64 = 0x534B_5948_4F50_2026
    private var lastLandedPlatformID: Int?
    private var viewportSize = CGSize.zero
    static let maximumPlatformShift: CGFloat = 160
    private var heightScore: CGFloat = 0

    mutating func start(in size: CGSize, seed: UInt64? = nil) {
        guard size.width > 120, size.height > 240 else { return }
        phase = .playing
        viewportSize = size
        score = 0
        heightScore = 0
        steering = 0
        randomState = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
        nextPlatformID = 0
        nextObstacleID = 0
        generatedPlatformCount = 0
        stablePlatformStreak = 0
        lastLandedPlatformID = nil
        elapsedTime = 0
        climbedDistance = 0
        facingLeft = false
        steeringPulseRemaining = 0
        clock = ArcadeSimulationClock()
        gameOverReason = nil
        playerPosition = CGPoint(x: size.width / 2, y: size.height - 125)
        velocity = CGVector(dx: 0, dy: -570)
        platforms = []
        obstacles = []

        var y = size.height - 72
        addPlatform(x: size.width / 2, y: y, width: 112, kind: .stable)
        while y > -100 {
            guard let lowerPlatform = platforms.last else { break }
            y -= random(in: 76...108)
            addPlatform(
                x: nextPlatformX(from: lowerPlatform.x, in: size),
                y: y,
                width: random(in: 72...112),
                kind: nextPlatformKind(difficulty: 0)
            )
            if let upperPlatform = platforms.last {
                addObstacleIfNeeded(between: lowerPlatform, and: upperPlatform, in: size)
            }
        }
    }

    mutating func resize(to size: CGSize) {
        guard size.width > 120, size.height > 240, viewportSize != .zero else { return }
        let xScale = size.width / viewportSize.width
        let yScale = size.height / viewportSize.height
        playerPosition.x *= xScale
        playerPosition.y *= yScale
        for index in platforms.indices {
            platforms[index].x *= xScale
            platforms[index].y *= yScale
        }
        for index in obstacles.indices {
            obstacles[index].x *= xScale
            obstacles[index].y *= yScale
            obstacles[index].size *= min(xScale, yScale)
        }
        viewportSize = size
    }

    mutating func update(deltaTime rawDeltaTime: TimeInterval, in size: CGSize) {
        guard phase == .playing, rawDeltaTime.isFinite, size.width > 0, size.height > 0 else { return }
        if viewportSize == .zero { viewportSize = size }
        let steps = clock.steps(for: rawDeltaTime)
        for _ in 0..<steps where phase == .playing { advance(in: size) }
    }

    mutating func setSteering(_ direction: Double) {
        steeringPulseRemaining = 0
        steering = min(max(direction, -1), 1)
    }

    // VoiceOver/button activation is a brief nudge, never a stuck held key.
    mutating func nudgeSteering(_ direction: Double) {
        guard phase == .playing else { return }
        steering = min(max(direction, -1), 1)
        steeringPulseRemaining = 0.18
    }

    private mutating func advance(in size: CGSize) {
        let dt = CGFloat(ArcadeSimulationClock.step)
        elapsedTime += Double(dt)
        if steeringPulseRemaining > 0 {
            steeringPulseRemaining = max(0, steeringPulseRemaining - Double(dt))
            if steeringPulseRemaining == 0 { steering = 0 }
        }
        let previousPosition = playerPosition
        let acceleration = CGFloat(steering) * 1_450
        velocity.dx += acceleration * dt
        if abs(steering) < 0.01 {
            velocity.dx *= max(1 - 5 * dt, 0)
        }
        velocity.dx = min(max(velocity.dx, -270), 270)
        velocity.dy += 1_000 * dt
        if abs(velocity.dx) > 15 { facingLeft = velocity.dx < 0 }
        playerPosition.x += velocity.dx * dt
        playerPosition.y += velocity.dy * dt

        let halfWidth = Self.playerSize.width / 2
        if playerPosition.x < -halfWidth { playerPosition.x = size.width + halfWidth }
        if playerPosition.x > size.width + halfWidth { playerPosition.x = -halfWidth }

        landIfNeeded(from: previousPosition)
        scrollWorldIfNeeded(in: size)
        advanceCrumblingPlatforms(by: dt)
        endGameIfPlayerHitsObstacle()
        removeAndAddPlatforms(in: size)

        if phase == .playing, playerPosition.y > size.height + Self.playerSize.height {
            phase = .gameOver
            steering = 0
            gameOverReason = .fell
        }
    }

    private mutating func landIfNeeded(from previousPosition: CGPoint) {
        guard velocity.dy > 0 else { return }
        let previousFeet = previousPosition.y + Self.playerSize.height * 0.38
        let currentFeet = playerPosition.y + Self.playerSize.height * 0.38
        let playerReach = Self.playerSize.width * 0.3

        let landingIndex = platforms.indices
            .filter { index in
                let platform = platforms[index]
                return platform.isSolid
                    && previousFeet <= platform.y
                    && currentFeet >= platform.y
                    && abs(playerPosition.x - platform.x) <= platform.width / 2 + playerReach
            }
            .min { platforms[$0].y < platforms[$1].y }

        guard let landingIndex else { return }
        let landing = platforms[landingIndex]
        playerPosition.y = landing.y - Self.playerSize.height * 0.38
        velocity.dy = -570
        if landing.kind == .fragile {
            platforms[landingIndex].crumbleElapsed = 0
        }
        if lastLandedPlatformID != landing.id {
            score += 20
            lastLandedPlatformID = landing.id
        }
    }

    private mutating func scrollWorldIfNeeded(in size: CGSize) {
        let ceiling = size.height * 0.38
        guard playerPosition.y < ceiling else { return }
        let shift = ceiling - playerPosition.y
        climbedDistance += shift
        playerPosition.y = ceiling
        for index in platforms.indices { platforms[index].y += shift }
        for index in obstacles.indices { obstacles[index].y += shift }
        let previousScore = Int(heightScore)
        heightScore += shift * 1.8
        score += Int(heightScore) - previousScore
    }

    private mutating func advanceCrumblingPlatforms(by deltaTime: CGFloat) {
        for index in platforms.indices where platforms[index].crumbleElapsed != nil {
            let elapsed = (platforms[index].crumbleElapsed ?? 0) + deltaTime
            platforms[index].crumbleElapsed = elapsed
            platforms[index].y += (90 + elapsed * 520) * deltaTime
        }
    }

    private mutating func endGameIfPlayerHitsObstacle() {
        guard phase == .playing else { return }
        let horizontalReach = Self.playerSize.width * 0.27
        let verticalReach = Self.playerSize.height * 0.3

        guard let collision = obstacles.first(where: { obstacle in
            abs(playerPosition.x - obstacle.x) <= horizontalReach + obstacle.size * 0.3
                && abs(playerPosition.y - obstacle.y) <= verticalReach + obstacle.size * 0.3
        }) else { return }

        phase = .gameOver
        steering = 0
        velocity = .zero
        gameOverReason = .obstacle(collision.kind)
    }

    private mutating func removeAndAddPlatforms(in size: CGSize) {
        platforms.removeAll {
            $0.y > size.height + 60
                || ($0.crumbleElapsed ?? 0) >= Self.crumbleDuration
        }
        obstacles.removeAll { $0.y > size.height + 70 }
        var topY = platforms.map(\.y).min() ?? size.height
        while topY > -110 {
            guard let lowerPlatform = platforms.min(by: { $0.y < $1.y }) else { break }
            let difficulty = min(CGFloat(score) / 2_000, 1)
            let minimumGap = 76 + difficulty * 12
            let maximumGap = 104 + difficulty * 18
            topY -= random(in: minimumGap...maximumGap)
            let width = random(in: (68 - difficulty * 8)...(108 - difficulty * 14))
            addPlatform(
                x: nextPlatformX(from: lowerPlatform.x, in: size),
                y: topY,
                width: width,
                kind: nextPlatformKind(difficulty: difficulty)
            )
            if let upperPlatform = platforms.min(by: { $0.y < $1.y }) {
                addObstacleIfNeeded(between: lowerPlatform, and: upperPlatform, in: size)
            }
        }
    }

    private mutating func addPlatform(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        kind: SkyHopPlatformKind
    ) {
        platforms.append(
            SkyHopPlatform(id: nextPlatformID, x: x, y: y, width: width, kind: kind)
        )
        nextPlatformID += 1
        generatedPlatformCount += 1
        stablePlatformStreak = kind == .stable ? stablePlatformStreak + 1 : 0
    }

    private mutating func nextPlatformX(from previous: CGFloat, in size: CGSize) -> CGFloat {
        let lower = max(52, previous - Self.maximumPlatformShift)
        let upper = min(max(size.width - 52, 53), previous + Self.maximumPlatformShift)
        return random(in: lower...max(lower, upper))
    }

    private mutating func nextPlatformKind(difficulty: CGFloat) -> SkyHopPlatformKind {
        guard generatedPlatformCount >= 3,
              platforms.last?.kind != .fragile else {
            return .stable
        }
        let fragileChance = 0.23 + Double(difficulty) * 0.12
        return stablePlatformStreak >= 3 || randomUnit() < fragileChance ? .fragile : .stable
    }

    private mutating func addObstacleIfNeeded(
        between lowerPlatform: SkyHopPlatform,
        and upperPlatform: SkyHopPlatform,
        in size: CGSize
    ) {
        guard generatedPlatformCount >= 5,
              generatedPlatformCount % 4 == 1 else { return }

        let pathCenter = (lowerPlatform.x + upperPlatform.x) / 2
        let obstacleX: CGFloat
        if pathCenter < size.width / 2 {
            obstacleX = random(in: max(size.width * 0.7, 34)...max(size.width - 34, 35))
        } else {
            obstacleX = random(in: 34...max(size.width * 0.3, 35))
        }
        let obstacle = SkyHopObstacle(
            id: nextObstacleID,
            kind: nextObstacleID.isMultiple(of: 2) ? .stormCloud : .spikeOrb,
            x: obstacleX,
            y: (lowerPlatform.y + upperPlatform.y) / 2 + random(in: -7...7),
            size: nextObstacleID.isMultiple(of: 2) ? 46 : 38
        )
        obstacles.append(obstacle)
        nextObstacleID += 1
    }

    private mutating func random(in range: ClosedRange<CGFloat>) -> CGFloat {
        range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(randomUnit())
    }

    private mutating func randomUnit() -> Double {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(randomState >> 11) / Double(1 << 53)
    }
}

private extension ArcadeItemKind {
    var title: String {
        switch self {
        case .food: String(localized: "Pet food")
        case .treat: String(localized: "Treat")
        case .toy: String(localized: "New toy")
        case .vitamins: String(localized: "Vitamins")
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .treat: "birthday.cake.fill"
        case .toy: "tennisball.fill"
        case .vitamins: "bolt.heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .food: .green
        case .treat: .pink
        case .toy: .orange
        case .vitamins: .cyan
        }
    }

    var effectDescription: String {
        switch self {
        case .food: String(localized: "+24% fullness")
        case .treat: String(localized: "+10% fullness, +14% happiness")
        case .toy: String(localized: "+22% happiness")
        case .vitamins: String(localized: "+25% energy")
        }
    }
}

#if DEBUG
private struct MiniGamesPreview: View {
    @StateObject private var controller = PetSessionController(store: InMemoryPetStore())

    var body: some View {
        MiniGamesView(controller: controller)
            .task { await controller.bootstrap() }
    }
}

#Preview("Pet Arcade") {
    MiniGamesPreview()
}
#endif
