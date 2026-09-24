import SwiftUI

struct PetsDashGameView: View {
    let pet: PetProfile
    let highScore: Int
    let onFinish: (Int, UUID) async -> ArcadePayout?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var engine = PetsDashEngine()
    @State private var lastTick: Date?
    @State private var payout: ArcadePayout?
    @State private var isSavingResult = false
    @State private var didSaveResult = false
    @State private var runID = UUID()
    @State private var isPaused = false
    @State private var didHandleSwipe = false

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: scenePhase != .active || isPaused || engine.phase != .playing)) { timeline in
                let animationFrame = engine.animationFrame

                ZStack {
                    PetsDashTrack(progress: engine.trackProgress)

                    ForEach(engine.objects) { object in
                        dashObject(object, in: proxy.size)
                            .zIndex(Double(object.progress))
                    }

                    player(frame: animationFrame, in: proxy.size)
                        .zIndex(Double(PetsDashEngine.playerProgress))

                    gameHUD(insets: proxy.safeAreaInsets)
                        .disabled(isPaused)
                        .accessibilityHidden(isPaused)
                        .zIndex(4)

                    if isPaused {
                        GamePausePanel(safeArea: proxy.safeAreaInsets) {
                            lastTick = nil
                            isPaused = false
                        } onExit: { dismiss() }
                        .zIndex(100)
                    }
                    if engine.phase == .ready {
                        GamePanelViewport(safeArea: proxy.safeAreaInsets) {
                            startOverlay(size: proxy.size, frame: animationFrame)
                        }
                            .zIndex(5)
                    } else if engine.phase == .gameOver {
                        GamePanelViewport(safeArea: proxy.safeAreaInsets) {
                            gameOverOverlay(size: proxy.size)
                        }
                            .zIndex(5)
                    }
                }
                .contentShape(Rectangle())
                .gesture(swipeGesture, including: engine.phase == .playing && !isPaused ? .all : .subviews)
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
            if phase != .active {
                lastTick = nil
                didHandleSwipe = false
                if engine.phase == .playing { isPaused = true }
            }
        }
    }

    private func player(frame: Int, in size: CGSize) -> some View {
        let x = PetsDashLayout.laneX(engine.lanePosition, progress: PetsDashEngine.playerProgress, in: size)
        let ground = PetsDashLayout.playerY(in: size)
        let lift = engine.jumpHeight * 160
        return ZStack {
            Ellipse()
                .fill(ArcadePalette.ink.opacity(0.24 - Double(engine.jumpHeight) * 0.16))
                .frame(width: 52 - engine.jumpHeight * 28, height: 14 - engine.jumpHeight * 5)
                .position(x: x, y: ground + 2)
            PetsDashPlayerArtwork(pet: pet, frame: pet.species == .parrot ? Int(engine.elapsedTime * 12) : (engine.isJumping ? 1 : frame))
                .frame(width: 108, height: 108)
                .rotationEffect(.degrees(Double(CGFloat(engine.lane) - engine.lanePosition) * 8), anchor: .bottom)
                // All rear sprites share a 160 px canvas and a 150 px foot line.
                .position(x: x, y: ground - 47.25 - lift)
            let age = engine.elapsedTime - engine.lastCoinTime
            if age >= 0, age < 0.5 {
                Text(verbatim: "+50")
                    .font(.system(.subheadline, design: .rounded).bold())
                    .foregroundStyle(ArcadePalette.ink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(ArcadePalette.gold, in: Capsule())
                    .opacity(1 - age / 0.5)
                    .position(x: x + 38, y: ground - 85 - CGFloat(age * 45))
                    .accessibilityHidden(true)
            }
        }
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            pet.species == .parrot
                ? "\(pet.name), flying in lane \(engine.lane + 1)"
                : "\(pet.name), running in lane \(engine.lane + 1)"
        )
    }

    private func dashObject(_ object: PetsDashObject, in size: CGSize) -> some View {
        let scale = PetsDashLayout.scale(for: object.progress)
        let x = PetsDashLayout.laneX(CGFloat(object.lane), progress: object.progress, in: size)
        let y = PetsDashLayout.y(for: object.progress, in: size)
        return ZStack {
            Ellipse().fill(ArcadePalette.ink.opacity(object.kind == .coin ? 0.10 : 0.22))
                .frame(width: 60 * scale, height: 13 * scale)
                .position(x: x, y: y + 2 * scale)
            Group {
                switch object.kind {
                case .barrier:
                    PetsDashBarrier().frame(width: 76, height: 60)
                case .rock:
                    PetsDashRock().frame(width: 68, height: 48)
                case .coin:
                    ZStack {
                        Circle().fill(ArcadePalette.gold)
                        Circle().stroke(Color(red: 0.75, green: 0.44, blue: 0.16), lineWidth: 3)
                        Circle().stroke(.white.opacity(0.65), lineWidth: 2).padding(5)
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 18, weight: .black))
                            .foregroundStyle(Color(red: 0.68, green: 0.39, blue: 0.13))
                    }
                    .frame(width: 37, height: 37)
                    .scaleEffect(x: 0.82 + 0.18 * abs(cos(engine.elapsedTime * 4)))
                }
            }
            .scaleEffect(scale, anchor: .bottom)
            .frame(width: 80, height: 60, alignment: .bottom)
            .position(x: x, y: y - 30 - (object.kind == .coin ? 18 * scale : 0))
        }
        .opacity(object.progress < 0 || object.didResolve && object.kind == .coin ? 0 : min(Double(object.progress * 12), 1))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func gameHUD(insets: EdgeInsets) -> some View {
        VStack {
            ArcadeHUD(score: engine.score, highScore: highScore, coins: engine.coinsCollected,
                      playing: engine.phase == .playing) {
                if engine.phase == .playing { isPaused = true } else { dismiss() }
            }
            .padding(.top, max(insets.top, 54) + 8)
            Spacer()
            if engine.phase == .playing {
                HStack(spacing: 22) {
                    Button { engine.moveLane(-1) } label: { Image(systemName: "arrow.left") }
                        .buttonStyle(ArcadeControlStyle())
                    Button { engine.jump() } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(ArcadeControlStyle(prominent: true))
                        .accessibilityLabel(pet.species == .parrot ? Text("Flap") : Text("Jump"))
                    Button { engine.moveLane(1) } label: { Image(systemName: "arrow.right") }
                        .buttonStyle(ArcadeControlStyle())
                }
                .padding(.bottom, max(insets.bottom, 24) + 8)
            }
        }
    }

    private func startOverlay(size: CGSize, frame: Int) -> some View {
        VStack(spacing: 15) {
            PetsDashPlayerArtwork(pet: pet, frame: frame)
                .frame(width: 124, height: 124)

            Text("Ready to dash?")
                .font(.system(.title2, design: .rounded).bold())

            Text(
                pet.species == .parrot
                    ? String(localized: "Switch lanes, flap over obstacles and collect paw coins.")
                    : String(localized: "Switch lanes, jump over obstacles and collect paw coins.")
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Label("Swipe", systemImage: "arrow.left.and.right")
                Label(pet.species == .parrot
                      ? String(localized: "Flap") : String(localized: "Jump"), systemImage: "arrow.up")
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)

            Button {
                restart(in: size)
            } label: {
                Label("Start running", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .controlSize(.large)
            Button("Back to Arcade") { dismiss() }
        }
        .padding(24)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private func gameOverOverlay(size: CGSize) -> some View {
        VStack(spacing: 14) {
            Text(payout?.isNewHighScore == true
                 ? String(localized: "New record!") : String(localized: "Great dash!"))
                .font(.system(.title2, design: .rounded).bold())

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
        .frame(maxWidth: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard engine.phase == .playing, !isPaused, !didHandleSwipe else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if abs(horizontal) > abs(vertical) {
                    engine.moveLane(horizontal > 0 ? 1 : -1)
                    didHandleSwipe = true
                } else if vertical < -16 {
                    engine.jump()
                    didHandleSwipe = true
                }
            }
            .onEnded { _ in didHandleSwipe = false }
    }

    private func tick(from oldDate: Date, to newDate: Date, size: CGSize) {
        guard engine.phase == .playing, scenePhase == .active, !isPaused else {
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

struct PetsDashPlayerArtwork: View {
    let pet: PetProfile
    var frame = 0

    var body: some View {
        let assets = PetsDashArtworkLibrary.assetNames(
            for: pet.species,
            breed: pet.resolvedBreed
        )

        if !assets.isEmpty {
            GeometryReader { proxy in
                let registration = PetsDashArtworkLibrary.registration(for: pet.resolvedBreed, frame: frame)
                let scale = min(proxy.size.width, proxy.size.height) / 160
                Image(assets[positiveModulo(frame, assets.count)])
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .petCoat(species: pet.species, coat: pet.coat, customColor: pet.customColor)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .offset(x: registration.width * scale, y: registration.height * scale)
            }
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

    /// Register the head/torso, not the changing wingspan. Coordinates are in
    /// the original 160 px canvas; ground animals already share a fixed foot line.
    static func registration(for breed: PetBreed?, frame: Int) -> CGSize {
        let index = ((frame % 4) + 4) % 4
        let offsets: [CGSize]
        switch breed {
        case .classicParrot:
            offsets = [CGSize(width: 0, height: -9), .zero, .zero, .zero]
        case .cockatiel:
            offsets = [CGSize(width: 0, height: -11), .zero,
                       CGSize(width: 16, height: 0), CGSize(width: 3, height: 0)]
        case .budgie:
            offsets = [CGSize(width: 0, height: -9), .zero, .zero, CGSize(width: 2, height: 0)]
        case .macaw:
            offsets = [CGSize(width: 0, height: -13), .zero,
                       CGSize(width: 20, height: 0), CGSize(width: 3, height: 0)]
        default:
            return .zero
        }
        return offsets[index]
    }

    private static func token(for species: PetSpecies, breed: PetBreed?) -> String? {
        if let token = (breed ?? PetBreed.defaultVariant(for: species))?.companionArtworkToken { return token }
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
        case .lion:
            return "lion_adult"
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
    private(set) var lanePosition: CGFloat = 1
    private var laneStart: CGFloat = 1
    private var laneTransition: CGFloat = 1
    var jumpHeight: CGFloat = 0
    var score = 0
    var coinsCollected = 0
    var objects: [PetsDashObject] = []
    private(set) var trackProgress: CGFloat = 0
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var lastCoinTime: TimeInterval = -10
    private var gaitDistance: CGFloat = 0
    private var clock = ArcadeSimulationClock()

    var animationFrame: Int { Int(gaitDistance * 44) % 4 }

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
        lanePosition = 1
        laneStart = 1
        laneTransition = 1
        elapsedTime = 0
        lastCoinTime = -10
        gaitDistance = 0
        clock = ArcadeSimulationClock()
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
        let target = min(max(lane + (direction > 0 ? 1 : -1), 0), 2)
        guard target != lane else { return }
        laneStart = lanePosition
        laneTransition = 0
        lane = target
    }

    mutating func jump() {
        guard phase == .playing, jumpHeight == 0, jumpVelocity == 0 else { return }
        jumpVelocity = 2.45
    }

    mutating func update(deltaTime rawDeltaTime: TimeInterval, in size: CGSize) {
        guard phase == .playing, rawDeltaTime.isFinite, size.width > 0, size.height > 0 else { return }
        let steps = clock.steps(for: rawDeltaTime)
        for _ in 0..<steps where phase == .playing {
            advance(by: ArcadeSimulationClock.step)
        }
    }

    private mutating func advance(by deltaTime: TimeInterval) {
        let dt = CGFloat(deltaTime)
        elapsedTime += deltaTime
        let difficulty = min(CGFloat(score) / 3_200, 1)
        let speed = 0.30 + difficulty * 0.14
        let travel = speed * dt
        trackProgress = (trackProgress + travel).arcadeWrapped(1.4)
        if !isJumping { gaitDistance += travel }
        laneTransition = min(laneTransition + dt / 0.18, 1)
        let eased = laneTransition * laneTransition * (3 - 2 * laneTransition)
        lanePosition = laneStart + (CGFloat(lane) - laneStart) * eased

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
            $0.progress > 1.35 || ($0.kind == .coin && $0.didResolve)
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

            let overlapsLane = abs(CGFloat(object.lane) - lanePosition) < 0.48
            let contactStart = Self.playerProgress - 0.04
            let contactEnd = Self.playerProgress + 0.04
            if object.kind == .coin, overlapsLane,
               object.progress >= contactStart, object.progress <= contactEnd,
               jumpHeight < 0.34 {
                objects[index].didResolve = true
                coinsCollected += 1
                lastCoinTime = elapsedTime
                scoreBonus += 50
                continue
            }

            if object.kind.isObstacle, overlapsLane,
               object.progress >= contactStart, object.progress <= contactEnd,
               jumpHeight < 0.30 {
                phase = .gameOver
                jumpVelocity = 0
                return
            }

            // Remain collidable throughout the crossing: landing early on a
            // hurdle must not grant immunity after one airborne frame.
            if object.progress > contactEnd {
                objects[index].didResolve = true
                if object.kind.isObstacle { scoreBonus += overlapsLane ? 100 : 40 }
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

/// A single ground projection for the trail, lane guides, scenery and hitboxes.
/// Progress is world distance; ground objects never use a separate scroll speed.
enum PetsDashLayout {
    static func horizon(in size: CGSize) -> CGFloat { size.height * 0.31 }
    static func depth(_ progress: CGFloat) -> CGFloat {
        let p = max(progress, 0)
        return 0.13 + 0.87 * p * p
    }
    static func laneX(_ lane: CGFloat, progress: CGFloat, in size: CGSize) -> CGFloat {
        size.width / 2 + (lane - 1) * size.width * 0.30 * depth(progress)
    }
    static func y(for progress: CGFloat, in size: CGSize) -> CGFloat {
        let p = max(progress, 0)
        return horizon(in: size) + p * p * (size.height * 0.88 - horizon(in: size))
    }
    static func playerY(in size: CGSize) -> CGFloat { y(for: PetsDashEngine.playerProgress, in: size) }
    static func scale(for progress: CGFloat) -> CGFloat {
        depth(progress) / depth(PetsDashEngine.playerProgress)
    }
}

struct PetsDashTrack: View {
    let progress: CGFloat

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let horizon = PetsDashLayout.horizon(in: size)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [ArcadePalette.sky, ArcadePalette.mist]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            context.fill(Path(ellipseIn: CGRect(x: w * 0.73, y: horizon * 0.50, width: 48, height: 48)),
                         with: .color(Color(red: 1, green: 0.93, blue: 0.73)))
            for i in 0..<4 {
                let x = CGFloat(i) * w * 0.34 - 40
                context.fill(ArcadeCloudShape().path(in: CGRect(x: x, y: horizon * (i.isMultiple(of: 2) ? 0.45 : 0.68),
                                                                width: 92, height: 28)), with: .color(.white.opacity(0.44)))
            }
            for layer in 0..<3 {
                var hill = Path()
                let base = horizon + CGFloat(layer) * 13
                hill.move(to: CGPoint(x: -10, y: base + 40))
                hill.addLine(to: CGPoint(x: -10, y: base - 18))
                hill.addCurve(to: CGPoint(x: w * 0.5, y: base),
                              control1: CGPoint(x: w * 0.15, y: base - 110 + CGFloat(layer) * 22),
                              control2: CGPoint(x: w * 0.30, y: base - 55))
                hill.addCurve(to: CGPoint(x: w + 10, y: base - 20),
                              control1: CGPoint(x: w * 0.75, y: base - 80),
                              control2: CGPoint(x: w * 0.95, y: base - 85 + CGFloat(layer) * 20))
                hill.addLine(to: CGPoint(x: w + 10, y: base + 40)); hill.closeSubpath()
                let colors = [Color(red: 0.56, green: 0.72, blue: 0.71),
                              Color(red: 0.43, green: 0.65, blue: 0.60), ArcadePalette.grass]
                context.fill(hill, with: .color(colors[layer]))
            }
            context.fill(Path(CGRect(x: 0, y: horizon + 25, width: w, height: h)), with: .linearGradient(
                Gradient(colors: [ArcadePalette.grass, ArcadePalette.grassLight]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
            // Broad banks frame the trail without pretending to be extra lanes.
            drawStrip(context, size: size, left: -0.65, right: 2.65, color: Color(red: 0.74, green: 0.73, blue: 0.48))
            drawStrip(context, size: size, left: -0.5, right: 2.5, color: ArcadePalette.sand)
            for lane in 0..<3 {
                drawStrip(context, size: size, left: CGFloat(lane) - 0.34,
                          right: CGFloat(lane) + 0.34, color: .white.opacity(0.075))
            }
            // Pebbled boundaries and ground flecks share object travel exactly.
            for i in 0..<19 {
                let p = (CGFloat(i) / 19 * 1.4 + progress).arcadeWrapped(1.4)
                let scale = PetsDashLayout.scale(for: p)
                let y = PetsDashLayout.y(for: p, in: size)
                for lane in [CGFloat(0.5), 1.5] {
                    let x = PetsDashLayout.laneX(lane, progress: p, in: size)
                    context.fill(Path(ellipseIn: CGRect(x: x - 2 * scale, y: y,
                                                        width: 4 * scale, height: 7 * scale)),
                                 with: .color(Color(red: 0.63, green: 0.53, blue: 0.38).opacity(0.32)))
                }
                for side in [-1, 1] {
                    let lane = CGFloat(side) * (1.9 + CGFloat(i % 3) * 0.18) + 1
                    let x = PetsDashLayout.laneX(lane, progress: p, in: size)
                    var tuft = Path()
                    tuft.move(to: CGPoint(x: x - 7 * scale, y: y))
                    tuft.addLine(to: CGPoint(x: x - 3 * scale, y: y - 10 * scale))
                    tuft.addLine(to: CGPoint(x: x, y: y - 3 * scale))
                    tuft.addLine(to: CGPoint(x: x + 5 * scale, y: y - 13 * scale))
                    tuft.addLine(to: CGPoint(x: x + 7 * scale, y: y)); tuft.closeSubpath()
                    context.fill(tuft, with: .color(ArcadePalette.grass.opacity(0.75)))
                    if i.isMultiple(of: 3) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y - 8 * scale, width: 4 * scale, height: 4 * scale)),
                                     with: .color(Color(red: 1, green: 0.94, blue: 0.77)))
                    }
                }
            }
            // Trees ordered by depth. Their roots sit on the same plane as rocks.
            let trees = (0..<16).map { id -> (id: Int, depth: CGFloat, lane: CGFloat) in
                let side: CGFloat = id.isMultiple(of: 2) ? -1 : 1
                let offset: CGFloat = side > 0 ? 0.085 : 0
                let depth = (CGFloat(id / 2) / 8 * 1.4 + progress + offset).arcadeWrapped(1.4)
                return (id, depth, 1 + side * (2.4 + CGFloat(id % 3) * 0.3))
            }.sorted { $0.depth < $1.depth }
            for item in trees {
                let scale = PetsDashLayout.scale(for: item.depth)
                let x = PetsDashLayout.laneX(item.lane, progress: item.depth, in: size)
                let y = PetsDashLayout.y(for: item.depth, in: size)
                tree(context, at: CGPoint(x: x, y: y),
                     scale: scale * (item.id.isMultiple(of: 3) ? 1.13 : 1),
                     alternate: item.id.isMultiple(of: 3))
            }
            // Bottom vignette gives touch controls contrast without covering paws.
            context.fill(Path(CGRect(x: 0, y: h * 0.88, width: w, height: h * 0.12)), with: .linearGradient(
                Gradient(colors: [.clear, ArcadePalette.ink.opacity(0.18)]),
                startPoint: CGPoint(x: 0, y: h * 0.88), endPoint: CGPoint(x: 0, y: h)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawStrip(_ context: GraphicsContext, size: CGSize, left: CGFloat, right: CGFloat, color: Color) {
        var p = Path()
        p.move(to: CGPoint(x: PetsDashLayout.laneX(left, progress: 0, in: size), y: PetsDashLayout.y(for: 0, in: size)))
        p.addLine(to: CGPoint(x: PetsDashLayout.laneX(right, progress: 0, in: size), y: PetsDashLayout.y(for: 0, in: size)))
        p.addLine(to: CGPoint(x: PetsDashLayout.laneX(right, progress: 1.4, in: size), y: PetsDashLayout.y(for: 1.4, in: size)))
        p.addLine(to: CGPoint(x: PetsDashLayout.laneX(left, progress: 1.4, in: size), y: PetsDashLayout.y(for: 1.4, in: size)))
        p.closeSubpath()
        context.fill(p, with: .color(color))
    }

    private func tree(_ context: GraphicsContext, at point: CGPoint, scale s: CGFloat, alternate: Bool) {
        var c = context
        c.translateBy(x: point.x, y: point.y); c.scaleBy(x: s, y: s)
        c.fill(Path(ellipseIn: CGRect(x: -27, y: -4, width: 68, height: 13)), with: .color(ArcadePalette.ink.opacity(0.12)))
        c.fill(Path(CGRect(x: -4, y: -40, width: 8, height: 40)), with: .color(Color(red: 0.42, green: 0.40, blue: 0.30)))
        var crown = Path()
        crown.move(to: CGPoint(x: -32, y: -31)); crown.addLine(to: CGPoint(x: -25, y: -68))
        crown.addLine(to: CGPoint(x: -8, y: -91)); crown.addLine(to: CGPoint(x: 16, y: -85))
        crown.addLine(to: CGPoint(x: 32, y: -57)); crown.addLine(to: CGPoint(x: 27, y: -27)); crown.closeSubpath()
        c.fill(crown, with: .color(alternate ? Color(red: 0.24, green: 0.48, blue: 0.41) : Color(red: 0.34, green: 0.55, blue: 0.39)))
        var light = Path()
        light.move(to: CGPoint(x: -25, y: -68)); light.addLine(to: CGPoint(x: -8, y: -91))
        light.addLine(to: CGPoint(x: 16, y: -85)); light.addLine(to: CGPoint(x: 9, y: -48))
        light.addLine(to: CGPoint(x: -32, y: -31)); light.closeSubpath()
        c.fill(light, with: .color(ArcadePalette.grassLight.opacity(0.35)))
    }
}

private struct PetsDashBarrier: View {
    var body: some View {
        Canvas { c, size in
            let w = size.width, h = size.height
            for x in [CGFloat(9), w - 16] {
                c.fill(Path(roundedRect: CGRect(x: x, y: 8, width: 9, height: h - 8), cornerRadius: 2),
                       with: .color(Color(red: 0.42, green: 0.29, blue: 0.22)))
            }
            c.fill(Path(roundedRect: CGRect(x: 0, y: 12, width: w, height: 22), cornerRadius: 3),
                   with: .color(ArcadePalette.coral))
            c.fill(Path(CGRect(x: 3, y: 13, width: w - 6, height: 4)), with: .color(.white.opacity(0.28)))
            for x in [w * 0.26, w * 0.63] {
                var flag = Path()
                flag.move(to: CGPoint(x: x, y: 14)); flag.addLine(to: CGPoint(x: x + 10, y: 14))
                flag.addLine(to: CGPoint(x: x + 5, y: 28)); flag.closeSubpath()
                c.fill(flag, with: .color(Color(red: 1, green: 0.89, blue: 0.65)))
            }
        }
    }
}

private struct PetsDashRock: View {
    var body: some View {
        Canvas { c, size in
            let w = size.width, h = size.height
            var rock = Path()
            rock.move(to: CGPoint(x: 0, y: h * 0.77)); rock.addLine(to: CGPoint(x: w * 0.16, y: h * 0.22))
            rock.addLine(to: CGPoint(x: w * 0.46, y: 0)); rock.addLine(to: CGPoint(x: w * 0.80, y: h * 0.14))
            rock.addLine(to: CGPoint(x: w, y: h * 0.73)); rock.addLine(to: CGPoint(x: w * 0.83, y: h))
            rock.addLine(to: CGPoint(x: w * 0.16, y: h)); rock.closeSubpath()
            c.fill(rock, with: .color(Color(red: 0.33, green: 0.42, blue: 0.47)))
            var facet = Path()
            facet.move(to: CGPoint(x: w * 0.16, y: h * 0.22)); facet.addLine(to: CGPoint(x: w * 0.46, y: 0))
            facet.addLine(to: CGPoint(x: w * 0.80, y: h * 0.14)); facet.addLine(to: CGPoint(x: w * 0.59, y: h * 0.59))
            facet.addLine(to: CGPoint(x: w * 0.12, y: h * 0.69)); facet.closeSubpath()
            c.fill(facet, with: .color(Color(red: 0.53, green: 0.62, blue: 0.63)))
        }
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
        onFinish: { _, _ in nil }
    )
}

#Preview("Pets Dash · Попугай") {
    PetsDashGameView(
        pet: PetProfile(
            id: UUID(), name: "Кеша", species: .parrot, coat: .sunrise,
            createdAt: .now, breed: .macaw
        ),
        highScore: 850,
        onFinish: { _, _ in nil }
    )
}

#Preview("Pets Dash · Все бегуны") {
    PetsDashArtworkQAPreview()
}
#endif
