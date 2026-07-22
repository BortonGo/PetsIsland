import SwiftUI

struct PetsDashGameView: View {
    let pet: PetProfile
    let highScore: Int
    let onFinish: (Int) async -> ArcadePayout?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = PetsDashEngine()
    @State private var lastTick: Date?
    @State private var payout: ArcadePayout?
    @State private var isSavingResult = false
    @State private var didSaveResult = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active)) { timeline in
                let animationFrame = frame(at: timeline.date)

                ZStack {
                    PetsDashTrack(progress: engine.trackProgress)

                    ForEach(engine.objects) { object in
                        dashObject(object, in: proxy.size)
                            .zIndex(Double(object.progress))
                    }

                    player(frame: animationFrame, in: proxy.size)
                        .zIndex(2)

                    gameHUD(topInset: proxy.safeAreaInsets.top)
                        .zIndex(4)

                    if engine.phase == .ready {
                        startOverlay(size: proxy.size, frame: animationFrame)
                            .zIndex(5)
                    } else if engine.phase == .gameOver {
                        gameOverOverlay(size: proxy.size)
                            .zIndex(5)
                    }
                }
                .contentShape(Rectangle())
                .gesture(swipeGesture)
                .onChange(of: timeline.date) { oldDate, newDate in
                    tick(from: oldDate, to: newDate, size: proxy.size)
                }
                .onAppear {
                    if ProcessInfo.processInfo.arguments.contains("-pets-dash-autostart") {
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

    private func player(frame: Int, in size: CGSize) -> some View {
        PetsDashPlayerArtwork(pet: pet, frame: frame)
            .frame(width: 118, height: 118)
            .scaleEffect(x: engine.isJumping ? 0.98 : 1, y: engine.isJumping ? 1.03 : 1)
            .position(
                x: PetsDashLayout.laneX(engine.lane, progress: PetsDashEngine.playerProgress, in: size),
                y: PetsDashLayout.playerY(in: size) - engine.jumpHeight * 150
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: engine.lane)
            .transaction { transaction in
                if engine.lane == engine.previousLane { transaction.animation = nil }
            }
            .shadow(color: .black.opacity(0.22), radius: 5, y: 5)
            .accessibilityLabel(
                pet.species == .parrot
                    ? "\(pet.name), flying in lane \(engine.lane + 1)"
                    : "\(pet.name), running in lane \(engine.lane + 1)"
            )
    }

    @ViewBuilder
    private func dashObject(_ object: PetsDashObject, in size: CGSize) -> some View {
        let scale = PetsDashLayout.scale(for: object.progress)
        let x = PetsDashLayout.laneX(object.lane, progress: object.progress, in: size)
        let y = PetsDashLayout.y(for: object.progress, in: size)

        Group {
            switch object.kind {
            case .barrier:
                PetsDashBarrier()
                    .frame(width: 76, height: 66)
            case .rock:
                PetsDashRock()
                    .frame(width: 72, height: 54)
            case .coin:
                ZStack {
                    Circle().fill(.yellow)
                    Circle().stroke(.orange, lineWidth: 5)
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 23, weight: .black))
                        .foregroundStyle(.orange)
                }
                .frame(width: 54, height: 54)
                .rotation3DEffect(
                    .degrees(Double(engine.trackProgress * 720)),
                    axis: (x: 0, y: 1, z: 0)
                )
                .shadow(color: .orange.opacity(0.32), radius: 7)
            }
        }
        .scaleEffect(scale)
        .opacity(object.progress < -0.02 || (object.kind == .coin && object.didResolve) ? 0 : 1)
        .position(x: x, y: y)
        .allowsHitTesting(false)
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
                        .foregroundStyle(.white.opacity(0.74))
                    Text("\(engine.score)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(.white)
                }

                if engine.coinsCollected > 0 {
                    Label("\(engine.coinsCollected)", systemImage: "pawprint.fill")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.18), in: Capsule())
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("BEST")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.74))
                    Text("\(max(highScore, engine.score))")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, max(topInset, 58) + 38)

            Spacer()

            if engine.phase == .playing {
                HStack(spacing: 20) {
                    controlButton(symbol: "arrow.left") { engine.moveLane(-1) }
                    controlButton(
                        symbol: pet.species == .parrot ? "arrow.up" : "figure.jumprope"
                    ) { engine.jump() }
                    controlButton(symbol: "arrow.right") { engine.moveLane(1) }
                }
                .padding(.bottom, 28)
            }
        }
    }

    private func controlButton(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func startOverlay(size: CGSize, frame: Int) -> some View {
        VStack(spacing: 15) {
            PetsDashPlayerArtwork(pet: pet, frame: frame)
                .frame(width: 124, height: 124)

            Text("Ready to dash?")
                .font(.largeTitle.bold())

            Text(
                pet.species == .parrot
                    ? "Switch lanes, flap over obstacles and collect paw coins."
                    : "Switch lanes, jump over obstacles and collect paw coins."
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Label("Swipe", systemImage: "arrow.left.and.right")
                Label(pet.species == .parrot ? "Flap" : "Jump", systemImage: "arrow.up")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            Button {
                restart(in: size)
            } label: {
                Label("Start running", systemImage: "play.fill")
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
            Text(payout?.isNewHighScore == true ? "New record!" : "Great dash!")
                .font(.largeTitle.bold())

            Text("\(engine.score) points · \(engine.coinsCollected) paw coins")
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.center)

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
                Label("Run again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSavingResult)

            Button("Back to Arcade") { dismiss() }
                .disabled(isSavingResult)
        }
        .padding(24)
        .frame(maxWidth: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard engine.phase == .playing else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > abs(vertical) {
                    engine.moveLane(horizontal > 0 ? 1 : -1)
                } else if vertical < -16 {
                    engine.jump()
                }
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

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pets-dash-autopilot") {
            engine.runAutopilot()
        }
#endif

        if engine.phase == .gameOver { saveResultIfNeeded() }
    }

    private func frame(at date: Date) -> Int {
        let framesPerSecond = engine.phase == .playing ? 10.0 : 4.0
        return Int(date.timeIntervalSinceReferenceDate * framesPerSecond) % 4
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

struct PetsDashPlayerArtwork: View {
    let pet: PetProfile
    var frame = 0

    var body: some View {
        let assets = PetsDashArtworkLibrary.assetNames(
            for: pet.species,
            breed: pet.resolvedBreed
        )

        if !assets.isEmpty {
            Image(assets[positiveModulo(frame, assets.count)])
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            PetArtwork(
                species: pet.species,
                coat: pet.coat,
                customColor: pet.customColor,
                breed: pet.resolvedBreed,
                pose: pet.species == .parrot ? .fly : .run,
                step: frame,
                animatesMotion: false
            )
        }
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        ((value % divisor) + divisor) % divisor
    }
}

enum PetsDashArtworkLibrary {
    static func assetNames(for species: PetSpecies, breed: PetBreed?) -> [String] {
        guard let token = token(for: species, breed: breed) else { return [] }
        return (0..<4).map { "pets_dash_\(token)_\(String(format: "%02d", $0))" }
    }

    private static func token(for species: PetSpecies, breed: PetBreed?) -> String? {
        switch species {
        case .cat:
            return switch breed ?? .classicCat {
            case .britishShorthair: "cat_british"
            case .maineCoon: "cat_maine_coon"
            case .siamese: "cat_siamese"
            default: "cat_classic"
            }
        case .dog:
            return switch breed ?? .shepherd {
            case .corgi: "dog_corgi"
            case .doberman: "dog_doberman"
            case .bullTerrier: "dog_bull_terrier"
            default: "dog_shepherd"
            }
        case .fox:
            return breed == .arcticFox ? "fox_arctic" : "fox_red"
        case .parrot:
            return switch breed ?? .classicParrot {
            case .cockatiel: "parrot_cockatiel"
            case .budgie: "parrot_budgie"
            case .macaw: "parrot_macaw"
            default: "parrot_classic"
            }
        case .penguin:
            return breed == .rockhopper ? "penguin_rockhopper" : "penguin_classic"
        case .bear, .lizard, .bunny:
            return nil
        }
    }
}

struct PetsDashObject: Identifiable, Equatable {
    enum Kind: Equatable {
        case barrier
        case rock
        case coin

        var isObstacle: Bool { self != .coin }
    }

    let id: Int
    let kind: Kind
    let lane: Int
    var progress: CGFloat
    var didResolve = false
}

struct PetsDashEngine {
    enum Phase: Equatable {
        case ready
        case playing
        case gameOver
    }

    static let playerProgress: CGFloat = 0.86

    var phase: Phase = .ready
    var lane = 1
    private(set) var previousLane = 1
    var jumpHeight: CGFloat = 0
    var score = 0
    var coinsCollected = 0
    var objects: [PetsDashObject] = []
    var trackProgress: CGFloat = 0

    var isJumping: Bool { jumpHeight > 0.02 }

    private var jumpVelocity: CGFloat = 0
    private var scoreDistance = 0.0
    private var scoreBonus = 0
    private var spawnCountdown = 0.75
    private var nextObjectID = 0
    private var randomState: UInt64 = 0x5045_5453_4441_5348

    mutating func start(in size: CGSize, seed: UInt64? = nil) {
        guard size.width > 180, size.height > 320 else { return }
        phase = .playing
        lane = 1
        previousLane = 1
        jumpHeight = 0
        jumpVelocity = 0
        score = 0
        coinsCollected = 0
        objects = []
        trackProgress = 0
        scoreDistance = 0
        scoreBonus = 0
        spawnCountdown = 0.65
        nextObjectID = 0
        randomState = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
    }

    mutating func moveLane(_ direction: Int) {
        guard phase == .playing, direction != 0 else { return }
        previousLane = lane
        lane = min(max(lane + (direction > 0 ? 1 : -1), 0), 2)
    }

    mutating func jump() {
        guard phase == .playing, jumpHeight <= 0.025 else { return }
        jumpVelocity = 2.45
    }

    mutating func update(deltaTime rawDeltaTime: TimeInterval, in size: CGSize) {
        guard phase == .playing, size.width > 0, size.height > 0 else { return }
        let deltaTime = min(max(rawDeltaTime, 0), 1.0 / 24.0)
        guard deltaTime > 0 else { return }
        let dt = CGFloat(deltaTime)

        let difficulty = min(CGFloat(score) / 3_200, 1)
        let speed = 0.30 + difficulty * 0.14
        trackProgress = (trackProgress + dt * (0.72 + difficulty * 0.38))
            .truncatingRemainder(dividingBy: 1)

        if jumpHeight > 0 || jumpVelocity > 0 {
            jumpVelocity -= (5.5 + difficulty * 0.25) * dt
            jumpHeight += jumpVelocity * dt
            if jumpHeight <= 0 {
                jumpHeight = 0
                jumpVelocity = 0
            }
        }

        scoreDistance += deltaTime * Double(24 + difficulty * 12)
        spawnCountdown -= deltaTime
        while spawnCountdown <= 0 {
            spawnWave(difficulty: difficulty)
            spawnCountdown += Double(1.12 - difficulty * 0.32)
        }

        for index in objects.indices {
            objects[index].progress += speed * dt
        }

        resolveObjects()
        objects.removeAll {
            $0.progress > 1.12 || ($0.kind == .coin && $0.didResolve)
        }
        score = max(Int(scoreDistance.rounded(.down)) + scoreBonus, 0)
    }

    mutating func runAutopilot() {
        guard phase == .playing else { return }
        let danger = objects
            .filter {
                $0.kind.isObstacle && !$0.didResolve && $0.lane == lane && $0.progress > 0.58
            }
            .min { $0.progress > $1.progress }
        if let danger, danger.progress > 0.70, jumpHeight <= 0.025 {
            jump()
        }
    }

    private mutating func resolveObjects() {
        for index in objects.indices where !objects[index].didResolve {
            let object = objects[index]

            if object.kind == .coin,
               object.lane == lane,
               object.progress >= 0.78 {
                objects[index].didResolve = true
                coinsCollected += 1
                scoreBonus += 50
                continue
            }

            if object.kind.isObstacle,
               object.lane == lane,
               object.progress >= 0.82,
               object.progress <= 1.01 {
                if jumpHeight < 0.18 {
                    phase = .gameOver
                    jumpVelocity = 0
                    return
                }
                objects[index].didResolve = true
                scoreBonus += 100
                continue
            }

            if object.progress > 1.0 {
                objects[index].didResolve = true
                if object.kind.isObstacle { scoreBonus += 40 }
            }
        }
    }

    private mutating func spawnWave(difficulty: CGFloat) {
        let firstObstacleLane = randomInt(upperBound: 3)
        let firstKind: PetsDashObject.Kind = randomInt(upperBound: 2) == 0 ? .barrier : .rock
        append(firstKind, lane: firstObstacleLane, progress: 0)

        var blockedLanes = Set([firstObstacleLane])
        if difficulty > 0.35, randomInt(upperBound: 4) == 0 {
            let candidates = (0..<3).filter { !blockedLanes.contains($0) }
            if let secondLane = candidates.randomElement(using: &randomState) {
                append(randomInt(upperBound: 2) == 0 ? .barrier : .rock, lane: secondLane, progress: -0.02)
                blockedLanes.insert(secondLane)
            }
        }

        let safeLanes = (0..<3).filter { !blockedLanes.contains($0) }
        if let coinLane = safeLanes.randomElement(using: &randomState) {
            append(.coin, lane: coinLane, progress: -0.08)
        }
    }

    private mutating func append(_ kind: PetsDashObject.Kind, lane: Int, progress: CGFloat) {
        objects.append(
            PetsDashObject(
                id: nextObjectID,
                kind: kind,
                lane: lane,
                progress: progress
            )
        )
        nextObjectID += 1
    }

    private mutating func randomInt(upperBound: Int) -> Int {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((randomState >> 32) % UInt64(max(upperBound, 1)))
    }
}

private enum PetsDashLayout {
    static func laneX(_ lane: Int, progress rawProgress: CGFloat, in size: CGSize) -> CGFloat {
        let progress = min(max(rawProgress, 0), 1)
        let topSpacing = size.width * 0.12
        let bottomSpacing = size.width * 0.29
        let spacing = topSpacing + (bottomSpacing - topSpacing) * pow(progress, 1.1)
        return size.width / 2 + CGFloat(lane - 1) * spacing
    }

    static func y(for rawProgress: CGFloat, in size: CGSize) -> CGFloat {
        let progress = min(max(rawProgress, 0), 1.1)
        let horizon = max(size.height * 0.30, 225)
        return horizon + pow(progress, 1.42) * (size.height - horizon + 45)
    }

    static func playerY(in size: CGSize) -> CGFloat {
        y(for: PetsDashEngine.playerProgress, in: size)
    }

    static func scale(for rawProgress: CGFloat) -> CGFloat {
        let progress = min(max(rawProgress, 0), 1)
        return 0.23 + progress * 0.95
    }
}

private struct PetsDashTrack: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let horizon = max(size.height * 0.30, 225)

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.28, green: 0.63, blue: 0.96),
                        Color(red: 0.72, green: 0.9, blue: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .fill(.yellow.opacity(0.82))
                    .frame(width: 92, height: 92)
                    .position(x: size.width * 0.78, y: horizon * 0.47)

                PetsDashHorizon()
                    .frame(height: 104)
                    .position(x: size.width / 2, y: horizon - 32)

                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.31, y: horizon))
                    path.addLine(to: CGPoint(x: size.width * 0.69, y: horizon))
                    path.addLine(to: CGPoint(x: size.width * 1.08, y: size.height + 30))
                    path.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height + 30))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.29, green: 0.31, blue: 0.36), Color(red: 0.12, green: 0.13, blue: 0.17)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                laneEdges(in: size, horizon: horizon)
                laneDashes(in: size)
            }
        }
        .ignoresSafeArea()
    }

    private func laneEdges(in size: CGSize, horizon: CGFloat) -> some View {
        ZStack {
            ForEach([-1, 1], id: \.self) { edge in
                Path { path in
                    path.move(to: CGPoint(x: size.width / 2 + CGFloat(edge) * size.width * 0.19, y: horizon))
                    path.addLine(to: CGPoint(x: size.width / 2 + CGFloat(edge) * size.width * 0.58, y: size.height + 30))
                }
                .stroke(.white.opacity(0.34), lineWidth: 3)
            }
        }
    }

    private func laneDashes(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<13, id: \.self) { index in
                let raw = CGFloat(index) / 13 + progress
                let dashProgress = raw.truncatingRemainder(dividingBy: 1)
                ForEach([0, 1], id: \.self) { boundary in
                    Capsule()
                        .fill(.white.opacity(0.72))
                        .frame(width: 4 + dashProgress * 5, height: 10 + dashProgress * 30)
                        .position(
                            x: size.width / 2 + CGFloat(boundary == 0 ? -1 : 1) * (size.width * (0.063 + dashProgress * 0.13)),
                            y: PetsDashLayout.y(for: dashProgress, in: size)
                        )
                }
            }
        }
    }
}

private struct PetsDashHorizon: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle().fill(Color(red: 0.22, green: 0.68, blue: 0.35))
                HStack(alignment: .bottom, spacing: 12) {
                    ForEach(0..<11, id: \.self) { index in
                        VStack(spacing: -5) {
                            Circle()
                                .fill(index.isMultiple(of: 2) ? Color.green : Color.mint)
                                .frame(width: 42, height: 42)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.brown)
                                .frame(width: 8, height: 28)
                        }
                    }
                }
                .frame(width: proxy.size.width)
            }
        }
    }
}

private struct PetsDashBarrier: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 45) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.24, green: 0.18, blue: 0.15))
                    .frame(width: 9, height: 48)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.24, green: 0.18, blue: 0.15))
                    .frame(width: 9, height: 48)
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.orange)
                .frame(height: 31)
                .overlay {
                    HStack(spacing: 7) {
                        ForEach(0..<4, id: \.self) { _ in
                            Rectangle()
                                .fill(.white)
                                .frame(width: 10)
                                .rotationEffect(.degrees(-25))
                        }
                    }
                    .clipped()
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black.opacity(0.34), lineWidth: 3))
                .offset(y: -15)
        }
    }
}

private struct PetsDashRock: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.32, green: 0.36, blue: 0.42))
                .frame(width: 66, height: 42)
            Circle()
                .fill(Color(red: 0.46, green: 0.51, blue: 0.57))
                .frame(width: 34, height: 34)
                .offset(x: -13, y: -17)
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 23, height: 7)
                .rotationEffect(.degrees(-18))
                .offset(x: -15, y: -25)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.black.opacity(0.24), lineWidth: 3)
        )
    }
}

private extension Array where Element == Int {
    func randomElement(using state: inout UInt64) -> Int? {
        guard !isEmpty else { return nil }
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return self[Int((state >> 32) % UInt64(count))]
    }
}

#if DEBUG
private struct PetsDashArtworkQAPreview: View {
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
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let frame = Int(timeline.date.timeIntervalSinceReferenceDate * 10) % 4
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 14
                ) {
                    ForEach(pets) { pet in
                        VStack(spacing: 7) {
                            PetsDashPlayerArtwork(pet: pet, frame: frame)
                                .frame(width: 120, height: 120)
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

#Preview("Pets Dash · Овчарка") {
    PetsDashGameView(
        pet: .starter,
        highScore: 1_200,
        onFinish: { _ in nil }
    )
}

#Preview("Pets Dash · Попугай") {
    PetsDashGameView(
        pet: PetProfile(
            id: UUID(), name: "Кеша", species: .parrot, coat: .sunrise,
            createdAt: .now, breed: .macaw
        ),
        highScore: 850,
        onFinish: { _ in nil }
    )
}

#Preview("Pets Dash · Все бегуны") {
    PetsDashArtworkQAPreview()
}
#endif
