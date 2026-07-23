import SwiftUI

struct SkyPawsGameView: View {
    let pet: PetProfile
    let highScore: Int
    let onFinish: (Int) async -> ArcadePayout?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = SkyPawsEngine()
    @State private var lastTick: Date?
    @State private var payout: ArcadePayout?
    @State private var isSavingResult = false
    @State private var didSaveResult = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
                ZStack {
                    background
                    gates(in: proxy.size)
                    player(frame: wingFrame(at: timeline.date))
                    hud(topInset: proxy.safeAreaInsets.top)

                    if engine.phase == .ready {
                        startOverlay(size: proxy.size)
                    } else if engine.phase == .gameOver {
                        gameOverOverlay(size: proxy.size)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture()
                        .onEnded { _ in handleTap(in: proxy.size) }
                )
                .onChange(of: timeline.date) { oldDate, newDate in
                    tick(from: oldDate, to: newDate, size: proxy.size)
                }
                .onChange(of: proxy.size) { _, newSize in
                    engine.resize(to: newSize)
                }
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-sky-paws-autostart"),
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

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.15, green: 0.48, blue: 0.92),
                    Color(red: 0.46, green: 0.79, blue: 0.98),
                    Color(red: 0.77, green: 0.93, blue: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            ForEach(0..<7, id: \.self) { index in
                SkyPawsBackgroundCloud()
                    .frame(width: CGFloat(86 + (index % 3) * 24))
                    .opacity(0.2)
                    .position(
                        x: CGFloat((index * 97 + 42) % 410),
                        y: CGFloat(120 + ((index * 173) % 720))
                    )
            }
        }
    }

    private func gates(in size: CGSize) -> some View {
        ForEach(engine.gates) { gate in
            let topHeight = max(gate.gapCenter - gate.gapHeight / 2, 1)
            let bottomStart = gate.gapCenter + gate.gapHeight / 2
            let bottomHeight = max(size.height - bottomStart, 1)

            SkyPawsCloudColumn(height: topHeight, edgeAtBottom: true)
                .position(x: gate.x, y: topHeight / 2)

            SkyPawsCloudColumn(height: bottomHeight, edgeAtBottom: false)
                .position(x: gate.x, y: bottomStart + bottomHeight / 2)
        }
    }

    private func player(frame: Int) -> some View {
        SkyPawsPlayerArtwork(pet: pet, frame: frame)
            .frame(width: SkyPawsEngine.playerSize.width, height: SkyPawsEngine.playerSize.height)
            .rotationEffect(.degrees(engine.playerRotation))
            .position(x: engine.playerX, y: engine.playerY)
            .transaction { transaction in transaction.animation = nil }
            .accessibilityLabel("\(pet.name), flying")
    }

    private func hud(topInset: CGFloat) -> some View {
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
                        .foregroundStyle(.white.opacity(0.76))
                    Text("\(engine.score)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("BEST")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.76))
                    Text("\(max(highScore, engine.score))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, max(topInset, 58) + 38)

            Spacer()

            if engine.phase == .playing {
                Label("Tap anywhere to climb", systemImage: "hand.tap.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    private func startOverlay(size: CGSize) -> some View {
        VStack(spacing: 16) {
            SkyPawsPlayerArtwork(pet: pet, frame: 0)
                .frame(width: 172, height: 116)

            Text("Ready to fly?")
                .font(.largeTitle.bold())

            Text("Tap to rise, glide through the cloud gates and keep \(pet.name) in the sky.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                restart(in: size)
            } label: {
                Label("Take off", systemImage: "airplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private func gameOverOverlay(size: CGSize) -> some View {
        VStack(spacing: 14) {
            Text(payout?.isNewHighScore == true ? "New record!" : "Good flight!")
                .font(.largeTitle.bold())

            Text("\(engine.score) points · \(engine.gatesPassed) gates")
                .font(.title3.monospacedDigit())

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
                Label("Fly again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSavingResult)

            Button("Back to Arcade") { dismiss() }
                .disabled(isSavingResult)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private func wingFrame(at date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate * 7)
    }

    private func handleTap(in size: CGSize) {
        switch engine.phase {
        case .ready:
            restart(in: size)
        case .playing:
            engine.flap()
        case .gameOver:
            break
        }
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

struct SkyPawsPlayerArtwork: View {
    let pet: PetProfile
    var frame = 0

    var body: some View {
        let assetNames = SkyPawsArtworkLibrary.assetNames(
            for: pet.species,
            breed: pet.resolvedBreed
        )

        if let assetName = assetNames[safe: frame] {
            GeometryReader { proxy in
                ZStack {
                    Image(assetName)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()

                    if pet.species != .parrot {
                        SkyPawsPropeller(frame: frame)
                            .frame(
                                width: proxy.size.width * 0.23,
                                height: proxy.size.height * 0.68
                            )
                            .position(
                                x: proxy.size.width * 0.91,
                                y: proxy.size.height * 0.5
                            )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .accessibilityHidden(true)
        } else {
            PetArtwork(
                species: pet.species,
                coat: pet.coat,
                customColor: pet.customColor,
                breed: pet.resolvedBreed,
                pose: pet.species == .parrot ? .fly : .jump,
                step: frame,
                animatesMotion: false
            )
        }
    }
}

private struct SkyPawsPropeller: View {
    let frame: Int

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color(red: 0.07, green: 0.12, blue: 0.25))
                .frame(width: 7)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 0.55, green: 0.6, blue: 0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .padding(.vertical, 3)
            Circle()
                .fill(Color(red: 0.12, green: 0.17, blue: 0.29))
                .frame(width: 11, height: 11)
        }
        .rotationEffect(.degrees(Double(frame % 8) * 45))
        .transaction { transaction in transaction.animation = nil }
        .allowsHitTesting(false)
    }
}

enum SkyPawsArtworkLibrary {
    static func assetNames(for species: PetSpecies, breed: PetBreed?) -> [String] {
        switch species {
        case .cat:
            return switch breed ?? .classicCat {
            case .britishShorthair: ["sky_paws_cat_british"]
            case .maineCoon: ["sky_paws_cat_maine_coon"]
            case .siamese: ["sky_paws_cat_siamese"]
            default: ["sky_paws_cat_classic"]
            }

        case .dog:
            return switch breed ?? .shepherd {
            case .corgi: ["sky_paws_dog_corgi"]
            case .doberman: ["sky_paws_dog_doberman"]
            case .bullTerrier: ["sky_paws_dog_bull_terrier"]
            default: ["sky_paws_dog_shepherd"]
            }

        case .fox:
            return breed == .arcticFox
                ? ["sky_paws_fox_arctic"]
                : ["sky_paws_fox_red"]

        case .parrot:
            let token = switch breed ?? .classicParrot {
            case .cockatiel: "cockatiel"
            case .budgie: "budgie"
            case .macaw: "macaw"
            default: "classic"
            }
            return [
                "island_parrot_\(token)_fly_00",
                "island_parrot_\(token)_fly_04"
            ]

        case .penguin:
            return breed == .rockhopper
                ? ["sky_paws_penguin_rockhopper"]
                : ["sky_paws_penguin_classic"]

        }
    }
}

struct SkyPawsGate: Identifiable, Equatable {
    let id: Int
    var x: CGFloat
    var gapCenter: CGFloat
    var gapHeight: CGFloat
    var didScore = false
}

struct SkyPawsEngine {
    enum Phase: Equatable {
        case ready
        case playing
        case gameOver
    }

    static let playerSize = CGSize(width: 88, height: 66)
    static let gateWidth: CGFloat = 78
    static let maximumGateCenterShift: CGFloat = 96

    var phase: Phase = .ready
    var playerX: CGFloat = 92
    var playerY: CGFloat = 420
    var velocityY: CGFloat = 0
    var score = 0
    var gatesPassed = 0
    var gates: [SkyPawsGate] = []

    var playerRotation: Double {
        Double(min(max(velocityY / 14, -15), 24))
    }

    private var distanceScore = 0.0
    private var nextGateID = 0
    private var randomState: UInt64 = 0x534B_5950_4157_5326
    private var viewportSize = CGSize.zero

    mutating func start(in size: CGSize, seed: UInt64? = nil) {
        guard size.width > 180, size.height > 320 else { return }
        phase = .playing
        viewportSize = size
        playerX = min(max(size.width * 0.25, 82), 108)
        playerY = size.height * 0.48
        velocityY = -185
        score = 0
        gatesPassed = 0
        distanceScore = 0
        nextGateID = 0
        randomState = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
        gates = []

        var x = size.width + 120
        for _ in 0..<4 {
            addGate(x: x, in: size)
            x += 235
        }
    }

    mutating func resize(to size: CGSize) {
        guard size.width > 180, size.height > 320, viewportSize != .zero else { return }
        let xScale = size.width / viewportSize.width
        let yScale = size.height / viewportSize.height
        playerX *= xScale
        playerY *= yScale
        for index in gates.indices {
            gates[index].x *= xScale
            gates[index].gapCenter *= yScale
        }
        viewportSize = size
    }

    mutating func flap() {
        guard phase == .playing else { return }
        velocityY = -325
    }

    mutating func update(deltaTime rawDeltaTime: TimeInterval, in size: CGSize) {
        guard phase == .playing, size.width > 0, size.height > 0 else { return }
        if viewportSize == .zero { viewportSize = size }
        let dt = CGFloat(min(max(rawDeltaTime, 0), 1.0 / 24.0))
        guard dt > 0 else { return }

        let difficulty = min(CGFloat(score) / 2_800, 1)
        let speed = 148 + difficulty * 76
        velocityY += (735 + difficulty * 65) * dt
        playerY += velocityY * dt
        distanceScore += Double(dt * (14 + difficulty * 7))

        for index in gates.indices {
            gates[index].x -= speed * dt
            if !gates[index].didScore,
               gates[index].x + Self.gateWidth / 2 < playerX {
                gates[index].didScore = true
                gatesPassed += 1
                distanceScore += 100
            }
        }

        score = max(Int(distanceScore.rounded(.down)), 0)
        recycleGates(in: size)

        if hasCollision(in: size) {
            phase = .gameOver
            velocityY = 0
        }
    }

    private mutating func recycleGates(in size: CGSize) {
        gates.removeAll { $0.x < -Self.gateWidth }
        let spacing = 235 - min(CGFloat(score) / 3_000, 1) * 24
        var rightmost = gates.map(\.x).max() ?? size.width
        while rightmost < size.width + spacing * 2 {
            rightmost += spacing
            addGate(x: rightmost, in: size)
        }
    }

    private mutating func addGate(x: CGFloat, in size: CGSize) {
        let difficulty = min(CGFloat(score) / 2_800, 1)
        let gapHeight = 214 - difficulty * 48
        let safeTop: CGFloat = 120
        let safeBottom = max(size.height - 118, safeTop + 1)
        let halfGap = gapHeight / 2
        let minimumCenter = safeTop + halfGap
        let maximumCenter = max(safeBottom - halfGap, minimumCenter)
        let centerRange: ClosedRange<CGFloat>
        if let previousCenter = gates.last?.gapCenter {
            let reachableMinimum = max(minimumCenter, previousCenter - Self.maximumGateCenterShift)
            let reachableMaximum = min(maximumCenter, previousCenter + Self.maximumGateCenterShift)
            centerRange = reachableMinimum...max(reachableMaximum, reachableMinimum)
        } else {
            centerRange = minimumCenter...maximumCenter
        }
        gates.append(
            SkyPawsGate(
                id: nextGateID,
                x: x,
                gapCenter: random(in: centerRange),
                gapHeight: gapHeight
            )
        )
        nextGateID += 1
    }

    private func hasCollision(in size: CGSize) -> Bool {
        let hitbox = CGRect(
            x: playerX - Self.playerSize.width * 0.37,
            y: playerY - Self.playerSize.height * 0.31,
            width: Self.playerSize.width * 0.74,
            height: Self.playerSize.height * 0.62
        )
        if hitbox.minY <= 0 || hitbox.maxY >= size.height { return true }

        for gate in gates where abs(gate.x - playerX) <= Self.gateWidth / 2 + hitbox.width / 2 {
            let gapTop = gate.gapCenter - gate.gapHeight / 2
            let gapBottom = gate.gapCenter + gate.gapHeight / 2
            if hitbox.minY < gapTop || hitbox.maxY > gapBottom { return true }
        }
        return false
    }

    private mutating func random(in range: ClosedRange<CGFloat>) -> CGFloat {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = CGFloat(Double(randomState >> 11) / Double(1 << 53))
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private struct SkyPawsCloudColumn: View {
    let height: CGFloat
    let edgeAtBottom: Bool

    var body: some View {
        ZStack(alignment: edgeAtBottom ? .bottom : .top) {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white, Color(red: 0.72, green: 0.87, blue: 0.97)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .stroke(.white.opacity(0.9), lineWidth: 3)
                )

            HStack(spacing: -16) {
                Circle().frame(width: 52, height: 52)
                Circle().frame(width: 64, height: 64)
                Circle().frame(width: 48, height: 48)
            }
            .foregroundStyle(.white)
            .offset(y: edgeAtBottom ? 22 : -22)
        }
        .frame(width: SkyPawsEngine.gateWidth, height: height)
        .shadow(color: .blue.opacity(0.14), radius: 5, x: 2, y: 2)
    }
}

private struct SkyPawsBackgroundCloud: View {
    var body: some View {
        HStack(spacing: -20) {
            Circle().frame(width: 54, height: 54)
            Circle().frame(width: 74, height: 74)
            Circle().frame(width: 50, height: 50)
        }
        .foregroundStyle(.white)
    }
}

private extension Array {
    subscript(safe cyclicalIndex: Int) -> Element? {
        guard !isEmpty else { return nil }
        let index = ((cyclicalIndex % count) + count) % count
        return self[index]
    }
}

#if DEBUG
private struct SkyPawsArtworkQAPreview: View {
    private let pets: [PetProfile] = [
        ("Кот", PetSpecies.cat, PetBreed.classicCat),
        ("Британец", .cat, .britishShorthair),
        ("Мейн-кун", .cat, .maineCoon),
        ("Сиамский", .cat, .siamese),
        ("Овчарка", .dog, .shepherd),
        ("Корги", .dog, .corgi),
        ("Доберман", .dog, .doberman),
        ("Бультерьер", .dog, .bullTerrier),
        ("Лис", .fox, .redFox),
        ("Песец", .fox, .arcticFox),
        ("Попугай", .parrot, .classicParrot),
        ("Корелла", .parrot, .cockatiel),
        ("Волнистый", .parrot, .budgie),
        ("Ара", .parrot, .macaw),
        ("Пингвин", .penguin, .classicPenguin),
        ("Хохлатый", .penguin, .rockhopper)
    ].map { entry in
        let (name, species, breed) = entry
        return PetProfile(
            id: UUID(), name: name, species: species, coat: .sunrise,
            createdAt: .now, breed: breed
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 7.0)) { timeline in
            let frame = Int(timeline.date.timeIntervalSinceReferenceDate * 7)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    ForEach(pets) { pet in
                        VStack(spacing: 7) {
                            SkyPawsPlayerArtwork(pet: pet, frame: frame)
                                .frame(width: 150, height: 100)
                            Text(pet.name)
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 18)
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview("Sky Paws · Овчарка") {
    SkyPawsGameView(
        pet: .starter,
        highScore: 600,
        onFinish: { _ in nil }
    )
}

#Preview("Sky Paws · Попугай") {
    SkyPawsGameView(
        pet: PetProfile(
            id: UUID(), name: "Кеша", species: .parrot, coat: .sunrise,
            createdAt: .now, breed: .macaw
        ),
        highScore: 420,
        onFinish: { _ in nil }
    )
}

#Preview("Sky Paws · Все пилоты") {
    SkyPawsArtworkQAPreview()
}
#endif
