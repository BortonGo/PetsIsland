import SwiftUI

private struct ActiveArcadeSession: Identifiable {
    let game: MiniGameKind
    let pet: PetProfile

    var id: String { "\(game.rawValue)-\(pet.id.uuidString)" }
}

struct MiniGamesView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPetID: UUID?
    @State private var activeSession: ActiveArcadeSession?
    @State private var message: String?

    init(controller: PetSessionController) {
        self.controller = controller
        _selectedPetID = State(initialValue: controller.pets.first?.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    walletHeader
                    petPicker
                    if let selectedPet {
                        vitalsCard(for: selectedPet)
                        skyHopCard(for: selectedPet)
                        skyPawsCard(for: selectedPet)
                        petsDashCard(for: selectedPet)
                        shop(for: selectedPet)
                    }
                    economyCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pet Arcade")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            switch session.game {
            case .skyHop:
                SkyHopGameView(
                    pet: session.pet,
                    highScore: controller.arcadeProgress.highScore(for: .skyHop)
                ) { score in
                    await controller.completeMiniGame(.skyHop, score: score, petID: session.pet.id)
                }
            case .skyPaws:
                SkyPawsGameView(
                    pet: session.pet,
                    highScore: controller.arcadeProgress.highScore(for: .skyPaws)
                ) { score in
                    await controller.completeMiniGame(.skyPaws, score: score, petID: session.pet.id)
                }
            case .petsDash:
                PetsDashGameView(
                    pet: session.pet,
                    highScore: controller.arcadeProgress.highScore(for: .petsDash)
                ) { score in
                    await controller.completeMiniGame(.petsDash, score: score, petID: session.pet.id)
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

    private var walletHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.yellow.opacity(0.2))
                Image(systemName: "dollarsign.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("Arcade wallet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(controller.arcadeProgress.coins) coins")
                    .font(.title2.bold().monospacedDigit())
            }
            Spacer()
        }
        .padding(18)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
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
                            .frame(width: 92, height: 100)
                            .background(
                                isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
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
                vital("fork.knife", value: vitals.fullness, color: .green, title: "Full")
                vital("heart.fill", value: vitals.happiness, color: .pink, title: "Happy")
                vital("bolt.fill", value: vitals.energy, color: .cyan, title: "Energy")
            }
        }
        .padding(16)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    private func vital(_ symbol: String, value: Double, color: Color, title: String) -> some View {
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
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.72), .cyan.opacity(0.34)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Circle()
                    .fill(.white.opacity(0.28))
                    .frame(width: 92, height: 92)
                    .offset(x: 115, y: -58)
                Capsule().fill(.green).frame(width: 92, height: 12).offset(x: -78, y: 72)
                Capsule().fill(.mint).frame(width: 74, height: 12).offset(x: 74, y: 8)
                Capsule().fill(.green).frame(width: 62, height: 12).offset(x: -48, y: -62)
                PetArtwork(
                    species: pet.species,
                    coat: pet.coat,
                    customColor: pet.customColor,
                    breed: pet.resolvedBreed,
                    pose: pet.species == .parrot ? .fly : .jump,
                    step: 0,
                    animatesMotion: false
                )
                .frame(width: 72, height: 64)
                .offset(x: 55, y: 54)
            }
            .frame(height: 220)
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sky Hop")
                            .font(.title2.bold())
                        Text("Jump higher, land on platforms and collect coins.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                }

                Label("100 points = 1 coin · record +5 · first game today +10", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    activeSession = ActiveArcadeSession(game: .skyHop, pet: pet)
                } label: {
                    Label("Play as \(pet.name)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(18)
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func skyPawsCard(for pet: PetProfile) -> some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.19, green: 0.52, blue: 0.95),
                        Color(red: 0.72, green: 0.92, blue: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                ForEach(0..<4, id: \.self) { index in
                    HStack(spacing: -14) {
                        Circle().frame(width: 34, height: 34)
                        Circle().frame(width: 46, height: 46)
                        Circle().frame(width: 30, height: 30)
                    }
                    .foregroundStyle(.white.opacity(0.62))
                    .offset(
                        x: CGFloat([-108, 104, -78, 88][index]),
                        y: CGFloat([-62, -26, 76, 68][index])
                    )
                }

                SkyPawsPlayerArtwork(pet: pet, frame: 0)
                    .frame(width: 128, height: 92)
                    .offset(x: 24, y: 12)
            }
            .frame(height: 220)
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sky Paws")
                            .font(.title2.bold())
                        Text(
                            pet.species == .parrot
                                ? "Flap through cloud gates and keep your rhythm."
                                : "Pilot a tiny plane through the cloud gates."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "airplane.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                }

                Label("Tap to climb · every gate adds 100 points", systemImage: "hand.tap.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    activeSession = ActiveArcadeSession(game: .skyPaws, pet: pet)
                } label: {
                    Label("Fly as \(pet.name)", systemImage: "airplane")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(18)
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func petsDashCard(for pet: PetProfile) -> some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.7, blue: 0.42),
                            Color(red: 0.62, green: 0.88, blue: 0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    Path { path in
                        path.move(to: CGPoint(x: size.width * 0.32, y: 0))
                        path.addLine(to: CGPoint(x: size.width * 0.68, y: 0))
                        path.addLine(to: CGPoint(x: size.width * 0.92, y: size.height))
                        path.addLine(to: CGPoint(x: size.width * 0.08, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(Color(red: 0.17, green: 0.18, blue: 0.22))

                    ForEach([-1, 1], id: \.self) { direction in
                        Path { path in
                            path.move(
                                to: CGPoint(
                                    x: size.width / 2 + CGFloat(direction) * size.width * 0.06,
                                    y: 0
                                )
                            )
                            path.addLine(
                                to: CGPoint(
                                    x: size.width / 2 + CGFloat(direction) * size.width * 0.15,
                                    y: size.height
                                )
                            )
                        }
                        .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 3, dash: [12, 12]))
                    }

                    RoundedRectangle(cornerRadius: 5)
                        .fill(.orange)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(.white, style: StrokeStyle(lineWidth: 4, dash: [12, 7]))
                        )
                        .frame(width: 56, height: 32)
                        .offset(x: -82, y: -26)

                    PetsDashPlayerArtwork(pet: pet, frame: 0)
                        .frame(width: 112, height: 112)
                        .offset(x: 34, y: 42)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 4)
                }
            }
            .frame(height: 220)
            .clipped()

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pets Dash")
                            .font(.title2.bold())
                        Text(
                            pet.species == .parrot
                                ? "Fly between three lanes, dodge barriers and collect paw coins."
                                : "Race down three lanes, dodge barriers and collect paw coins."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "figure.run.circle.fill")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                }

                Label("Swipe between lanes · swipe up to jump", systemImage: "arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    activeSession = ActiveArcadeSession(game: .petsDash, pet: pet)
                } label: {
                    Label(
                        pet.species == .parrot ? "Fly as \(pet.name)" : "Run as \(pet.name)",
                        systemImage: "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(18)
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
                .lineLimit(2, reservesSpace: true)

            Button {
                Task {
                    if await controller.purchaseArcadeItem(item) {
                        message = "\(item.title) added to your inventory."
                    } else {
                        message = "You need \(price) coins to buy \(item.title.lowercased())."
                    }
                }
            } label: {
                Label("\(price)", systemImage: "dollarsign.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(controller.arcadeProgress.coins < price)

            Button("Use for \(pet.name)") {
                Task {
                    if await controller.useArcadeItem(item, for: pet.id) {
                        message = "\(pet.name) used \(item.title.lowercased())."
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(owned == 0)
        }
        .padding(14)
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var economyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("A fair rhythm", systemImage: "heart.text.square.fill")
                .font(.headline)
            Text("Playing lifts happiness and spends a little fullness and energy. A tired pet can still play, but earns 25% fewer performance coins. Food and items never expire, and there are no paid currencies.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.purple.opacity(0.09), in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct SkyHopGameView: View {
    let pet: PetProfile
    let highScore: Int
    let onFinish: (Int) async -> ArcadePayout?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = SkyHopEngine()
    @State private var lastTick: Date?
    @State private var payout: ArcadePayout?
    @State private var isSavingResult = false
    @State private var didSaveResult = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
                ZStack {
                    gameBackground
                    platforms
                    player
                    gameHUD(topInset: proxy.safeAreaInsets.top)

                    if engine.phase == .ready {
                        startOverlay(size: proxy.size)
                    } else if engine.phase == .gameOver {
                        gameOverOverlay(size: proxy.size)
                    }
                }
                .contentShape(Rectangle())
                .gesture(steeringGesture(in: proxy.size))
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
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { lastTick = nil }
        }
    }

    private var gameBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.48, blue: 0.92), Color(red: 0.62, green: 0.9, blue: 0.96)],
                startPoint: .top,
                endPoint: .bottom
            )
            ForEach(0..<9, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: CGFloat(28 + (index % 3) * 18))
                    .position(
                        x: CGFloat((index * 83) % 390),
                        y: CGFloat(70 + ((index * 127) % 720))
                    )
            }
        }
    }

    private var platforms: some View {
        ForEach(engine.platforms) { platform in
            Capsule()
                .fill(
                    LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom)
                )
                .overlay(Capsule().stroke(.white.opacity(0.55), lineWidth: 2))
                .frame(width: platform.width, height: SkyHopEngine.platformHeight)
                .position(x: platform.x, y: platform.y)
                .shadow(color: .black.opacity(0.14), radius: 3, y: 3)
        }
    }

    private var player: some View {
        PetArtwork(
            species: pet.species,
            coat: pet.coat,
            customColor: pet.customColor,
            breed: pet.resolvedBreed,
            pose: pet.species == .parrot ? .fly : .jump,
            direction: engine.velocity.dx < 0 ? .left : .right,
            step: 0,
            animatesMotion: false
        )
        .frame(width: SkyHopEngine.playerSize.width, height: SkyHopEngine.playerSize.height)
        .position(engine.playerPosition)
        .contentTransition(.identity)
        .transaction { transaction in transaction.animation = nil }
        .shadow(color: .black.opacity(0.18), radius: 4, y: 4)
        .accessibilityLabel("\(pet.name), jumping")
    }

    private func gameHUD(topInset: CGFloat) -> some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text("SCORE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.72))
                    Text("\(engine.score)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("BEST")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.72))
                    Text("\(max(highScore, engine.score))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, max(topInset, 58) + 38)
            Spacer()

            if engine.phase == .playing {
                HStack {
                    controlHint(symbol: "arrow.left", direction: -1)
                    Spacer()
                    Text("Hold either side to steer")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                    controlHint(symbol: "arrow.right", direction: 1)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
    }

    private func controlHint(symbol: String, direction: Double) -> some View {
        Button {
            engine.steering = direction
        } label: {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in engine.steering = direction }
                .onEnded { _ in engine.steering = 0 }
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
                .font(.largeTitle.bold())
            Text("Land on platforms and climb as high as you can.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                restart(in: size)
            } label: {
                Label("Start jumping", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 330)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private func gameOverOverlay(size: CGSize) -> some View {
        VStack(spacing: 14) {
            Text(payout?.isNewHighScore == true ? "New record!" : "Nice jump!")
                .font(.largeTitle.bold())
            Text("\(engine.score) points")
                .font(.title2.monospacedDigit())

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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSavingResult)

            Button("Back to Arcade") { dismiss() }
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
                guard engine.phase == .playing else { return }
                engine.steering = value.location.x < size.width / 2 ? -1 : 1
            }
            .onEnded { _ in engine.steering = 0 }
    }

    private func tick(from oldDate: Date, to newDate: Date, size: CGSize) {
        guard engine.phase == .playing, scenePhase == .active else {
            lastTick = nil
            return
        }
        let anchor = lastTick ?? oldDate
        lastTick = newDate
        engine.update(deltaTime: newDate.timeIntervalSince(anchor), in: size)
        if engine.phase == .gameOver { saveResultIfNeeded() }
    }

    private func restart(in size: CGSize) {
        payout = nil
        isSavingResult = false
        didSaveResult = false
        lastTick = nil
        engine.start(in: size)
    }

    private func saveResultIfNeeded() {
        guard !didSaveResult else { return }
        didSaveResult = true
        isSavingResult = true
        let finalScore = engine.score
        Task {
            payout = await onFinish(finalScore)
            isSavingResult = false
        }
    }
}

struct SkyHopPlatform: Identifiable, Equatable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
}

struct SkyHopEngine {
    enum Phase: Equatable {
        case ready
        case playing
        case gameOver
    }

    static let playerSize = CGSize(width: 58, height: 52)
    static let platformHeight: CGFloat = 13

    var phase: Phase = .ready
    var playerPosition = CGPoint(x: 180, y: 500)
    var velocity = CGVector.zero
    var steering = 0.0
    var score = 0
    var platforms: [SkyHopPlatform] = []

    private var nextPlatformID = 0
    private var randomState: UInt64 = 0x534B_5948_4F50_2026
    private var lastLandedPlatformID: Int?
    private var viewportSize = CGSize.zero

    mutating func start(in size: CGSize, seed: UInt64? = nil) {
        guard size.width > 120, size.height > 240 else { return }
        phase = .playing
        viewportSize = size
        score = 0
        steering = 0
        randomState = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
        nextPlatformID = 0
        lastLandedPlatformID = nil
        playerPosition = CGPoint(x: size.width / 2, y: size.height - 125)
        velocity = CGVector(dx: 0, dy: -570)
        platforms = []

        var y = size.height - 72
        addPlatform(x: size.width / 2, y: y, width: 112)
        while y > -100 {
            y -= random(in: 76...108)
            addPlatform(
                x: random(in: 52...max(size.width - 52, 53)),
                y: y,
                width: random(in: 72...112)
            )
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
        viewportSize = size
    }

    mutating func update(deltaTime rawDeltaTime: TimeInterval, in size: CGSize) {
        guard phase == .playing, size.width > 0, size.height > 0 else { return }
        if viewportSize == .zero { viewportSize = size }
        let dt = CGFloat(min(max(rawDeltaTime, 0), 1.0 / 24.0))
        guard dt > 0 else { return }

        let previousPosition = playerPosition
        let acceleration = CGFloat(steering) * 1_450
        velocity.dx += acceleration * dt
        if abs(steering) < 0.01 {
            velocity.dx *= max(1 - 5 * dt, 0)
        }
        velocity.dx = min(max(velocity.dx, -270), 270)
        velocity.dy += 1_000 * dt
        playerPosition.x += velocity.dx * dt
        playerPosition.y += velocity.dy * dt

        let halfWidth = Self.playerSize.width / 2
        if playerPosition.x < -halfWidth { playerPosition.x = size.width + halfWidth }
        if playerPosition.x > size.width + halfWidth { playerPosition.x = -halfWidth }

        landIfNeeded(from: previousPosition)
        scrollWorldIfNeeded(in: size)
        removeAndAddPlatforms(in: size)

        if playerPosition.y > size.height + Self.playerSize.height {
            phase = .gameOver
            steering = 0
        }
    }

    private mutating func landIfNeeded(from previousPosition: CGPoint) {
        guard velocity.dy > 0 else { return }
        let previousFeet = previousPosition.y + Self.playerSize.height * 0.38
        let currentFeet = playerPosition.y + Self.playerSize.height * 0.38
        let playerReach = Self.playerSize.width * 0.3

        let landing = platforms
            .filter { platform in
                previousFeet <= platform.y
                    && currentFeet >= platform.y
                    && abs(playerPosition.x - platform.x) <= platform.width / 2 + playerReach
            }
            .min { $0.y < $1.y }

        guard let landing else { return }
        playerPosition.y = landing.y - Self.playerSize.height * 0.38
        velocity.dy = -570
        if lastLandedPlatformID != landing.id {
            score += 20
            lastLandedPlatformID = landing.id
        }
    }

    private mutating func scrollWorldIfNeeded(in size: CGSize) {
        let ceiling = size.height * 0.38
        guard playerPosition.y < ceiling else { return }
        let shift = ceiling - playerPosition.y
        playerPosition.y = ceiling
        for index in platforms.indices { platforms[index].y += shift }
        score += max(Int(shift * 1.8), 1)
    }

    private mutating func removeAndAddPlatforms(in size: CGSize) {
        platforms.removeAll { $0.y > size.height + 60 }
        var topY = platforms.map(\.y).min() ?? size.height
        while topY > -110 {
            let difficulty = min(CGFloat(score) / 2_000, 1)
            let minimumGap = 76 + difficulty * 12
            let maximumGap = 104 + difficulty * 18
            topY -= random(in: minimumGap...maximumGap)
            let width = random(in: (68 - difficulty * 8)...(108 - difficulty * 14))
            addPlatform(
                x: random(in: 48...max(size.width - 48, 49)),
                y: topY,
                width: width
            )
        }
    }

    private mutating func addPlatform(x: CGFloat, y: CGFloat, width: CGFloat) {
        platforms.append(SkyHopPlatform(id: nextPlatformID, x: x, y: y, width: width))
        nextPlatformID += 1
    }

    private mutating func random(in range: ClosedRange<CGFloat>) -> CGFloat {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = CGFloat(Double(randomState >> 11) / Double(1 << 53))
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private extension ArcadeItemKind {
    var title: String {
        switch self {
        case .food: "Pet food"
        case .treat: "Treat"
        case .toy: "New toy"
        case .vitamins: "Vitamins"
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
        case .food: "+24% fullness"
        case .treat: "+10% fullness, +14% happiness"
        case .toy: "+22% happiness"
        case .vitamins: "+25% energy"
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
