import SwiftUI

struct BubblePawsGameView: View {
    let pet: PetProfile
    let highScore: Int
    let onFinish: (Int, UUID) async -> ArcadePayout?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.petMinimizeMotion) private var minimizeMotion
    @State private var engine = BubblePawsEngine()
    @State private var isPaused = false
    @State private var lastTick: Date?
    @State private var runID = UUID()
    @State private var payout: ArcadePayout?
    @State private var isSavingResult = false
    @State private var didSaveResult = false

    private var finished: Bool { engine.phase == .won || engine.phase == .gameOver }

    var body: some View {
        ZStack {
            BubbleGardenBackground().ignoresSafeArea()
            VStack(spacing: 10) {
                header.padding(.top, 8)
                status
                GeometryReader { proxy in
                    let scale = min(max(proxy.size.width - 24, 1) / BubbleBoard.width,
                                    max(proxy.size.height, 1) / BubbleBoard.height)
                    TimelineView(.animation(minimumInterval: 1.0 / 60,
                                            paused: !engine.needsAnimation || scenePhase != .active || isPaused)) { timeline in
                        playfield
                            .frame(width: BubbleBoard.width, height: BubbleBoard.height)
                            .scaleEffect(scale)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                            .onChange(of: timeline.date) { _, date in tick(at: date) }
                    }
                }
                controls.padding(.bottom, 8)
            }
            .disabled(isPaused || engine.phase != .playing)
            .accessibilityHidden(isPaused || engine.phase != .playing)

            if isPaused {
                GamePausePanel(safeArea: EdgeInsets()) {
                    lastTick = nil; isPaused = false
                } onExit: { dismiss() }
            } else if engine.phase != .playing {
                GamePanelViewport(safeArea: EdgeInsets()) { panel }
            }
        }
        .persistentSystemOverlays(.hidden)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                lastTick = nil
                if engine.phase == .playing { isPaused = true }
            }
        }
        .onChange(of: engine.phase) { _, _ in
            if finished { saveResultIfNeeded() }
        }
        .onAppear {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-bubble-paws-autostart"), engine.phase == .ready { restart() }
#endif
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if engine.phase == .playing { isPaused = true; lastTick = nil }
                else if !isSavingResult { dismiss() }
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.09), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause game")
            VStack(alignment: .leading, spacing: 2) {
                Text("Bubble Paws").font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text("\(engine.score) points")
                    .font(.system(.title2, design: .rounded).bold().monospacedDigit())
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "trophy.fill").font(.caption).foregroundStyle(BubblePalette.cream)
                Text("\(max(engine.score, highScore))")
                    .font(.system(.subheadline, design: .rounded).bold().monospacedDigit())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("BEST")
            .accessibilityValue("\(max(engine.score, highScore))")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var status: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Round \(engine.level) of \(BubblePawsEngine.totalLevels)")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                HStack(spacing: 4) {
                    ForEach(1...BubblePawsEngine.totalLevels, id: \.self) { level in
                        Capsule().fill(level <= engine.level ? BubblePalette.cream : .white.opacity(0.16))
                            .frame(width: 18, height: 3)
                    }
                }.accessibilityHidden(true)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text("Ceiling in \(engine.missesRemaining) misses")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                HStack(spacing: 4) {
                    ForEach(0..<engine.missesBeforeDescent, id: \.self) { index in
                        Capsule().fill(index < engine.missesRemaining
                                       ? (engine.missesRemaining <= 2 ? BubblePalette.coral : .white.opacity(0.7))
                                       : .white.opacity(0.14))
                            .frame(width: 13, height: 3)
                    }
                }.accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white.opacity(0.84))
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var playfield: some View {
        ZStack(alignment: .topLeading) {
            BubblePlayfieldScenery(ceiling: engine.board.ceiling,
                                   isDangerous: engine.board.cells.keys.contains { engine.board.center(of: $0).y > 360 })
                .allowsHitTesting(false)
            if engine.canShoot { trajectory }
            ForEach(engine.board.cells.keys.sorted(), id: \.self) { cell in
                BubbleOrb(color: engine.board.cells[cell]!)
                    .frame(width: 38, height: 38)
                    .position(engine.board.center(of: cell))
            }
            ForEach(engine.effects) { effect in
                let t = effect.age / 0.6
                BubbleOrb(color: effect.color)
                    .frame(width: 38, height: 38)
                    .scaleEffect(reduceMotion || minimizeMotion ? 1 : (effect.falling ? 1 : 1 + t * 0.55))
                    .opacity(1 - t)
                    .position(x: effect.origin.x,
                              y: effect.origin.y + ((reduceMotion || minimizeMotion) ? 0 : (effect.falling ? 200 * t * t : -14 * t)))
            }
            if let flight = engine.flight {
                BubbleOrb(color: flight.color).frame(width: 38, height: 38).position(flight.position)
            }
            // Existing artwork is rendered as-is; only this game's stage changes.
            PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                       breed: pet.resolvedBreed, pose: .idle, animatesMotion: false)
                .frame(width: 96, height: 88)
                .position(x: 68, y: 505)
                .accessibilityHidden(true)
            BubbleCannon(angle: engine.aimAngle)
                .frame(width: 104, height: 104)
                .position(BubbleBoard.launcher)
            if engine.flight == nil {
                BubbleOrb(color: engine.currentColor).frame(width: 34, height: 34)
                    .position(BubbleBoard.launcher)
            }
            Button {
                engine.swapColors()
            } label: {
                VStack(spacing: 4) {
                    ZStack(alignment: .bottomTrailing) {
                        BubbleOrb(color: engine.nextColor).frame(width: 38, height: 38)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                            .padding(4)
                            .background(BubblePalette.night, in: Circle())
                            .offset(x: 5, y: 3)
                    }
                    Text("Swap").font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(BubblePalette.cream)
                .frame(width: 72, height: 70)
            }
            .buttonStyle(.plain)
            .disabled(!engine.canShoot)
            .position(x: 263, y: 510)
            .accessibilityLabel("Swap bubbles")
            .accessibilityValue(Text(engine.nextColor.name))
            .accessibilityIdentifier("bubble.swap")

            Rectangle().fill(.clear).contentShape(Rectangle())
                .frame(width: 320, height: 463)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !isPaused else { return }
                        engine.aim(at: value.location)
                    }
                    .onEnded { value in
                        guard !isPaused, scenePhase == .active else { return }
                        engine.aim(at: value.location)
                        fire()
                    })
                .accessibilityLabel("Bubble field")
                .accessibilityHint("Drag to aim, release to shoot. You can also use the aim and shoot buttons below.")
        }
    }

    private var trajectory: some View {
        let plan = engine.preview
        return Canvas { context, _ in
            let count = min(Int(plan.length / 13), 130)
            for step in 2..<max(count, 2) {
                let p = plan.point(at: CGFloat(step) * 13)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)),
                             with: .color(engine.currentColor.tint.opacity(0.72)))
            }
            if let landing = plan.landing {
                let p = engine.board.center(of: landing)
                context.stroke(Path(ellipseIn: CGRect(x: p.x - 18, y: p.y - 18, width: 36, height: 36)),
                               with: .color(engine.currentColor.tint.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { engine.setAim(engine.aimAngle - .pi / 36) } label: { Image(systemName: "arrow.left") }
                .buttonStyle(BubbleAimButtonStyle())
                .accessibilityLabel("Aim left")
                .accessibilityIdentifier("bubble.left")
            Button(action: fire) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                    Text("Shoot")
                }
                .font(.subheadline.bold())
                .foregroundStyle(BubblePalette.night)
                .frame(width: 144, height: 52)
                .background(BubblePalette.cream.gradient, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(engine.currentColor.name))
            .accessibilityIdentifier("bubble.shoot")
            Button { engine.setAim(engine.aimAngle + .pi / 36) } label: { Image(systemName: "arrow.right") }
                .buttonStyle(BubbleAimButtonStyle())
                .accessibilityLabel("Aim right")
                .accessibilityIdentifier("bubble.right")
        }
        .disabled(!engine.canShoot)
        .opacity(engine.canShoot ? 1 : 0.5)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var panel: some View {
        VStack(spacing: 16) {
            HStack(spacing: -4) {
                ForEach([BubbleColor.rose, .honey, .mint], id: \.self) { color in
                    BubbleOrb(color: color).frame(width: 42, height: 42)
                }
            }
            Text(engine.phase == .ready ? "Bubble Paws" : engine.phase == .roundCleared ? "A little more sparkle!" : engine.phase == .won ? "The sky is clear!" : "Nice popping!")
                .font(.system(.title2, design: .rounded).bold())
                .multilineTextAlignment(.center)
            if engine.phase == .ready {
                Text("Aim, release, pop! Match 3 of the same color. Cut a cluster loose to drop the bubbles below it.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Text("Five fresh layouts per run. Misses accumulate: the ceiling lowers after 5, or 4 in the later rounds. Swap colors and use wall bounces.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Let's pop!") { restart() }
                    .buttonStyle(PetPrimaryButtonStyle())
                    .accessibilityIdentifier("bubble.start")
            } else if engine.phase == .roundCleared {
                Text("\(engine.score) points").font(.title3.monospacedDigit())
                Text("Ready for the next round?").foregroundStyle(.secondary)
                Button("Next round") { engine.nextRound(); lastTick = nil }
                    .buttonStyle(PetPrimaryButtonStyle())
            } else {
                Text("\(engine.score) points").font(.title3.monospacedDigit())
                if isSavingResult { ProgressView("Counting coins…") }
                else if let payout {
                    Label("+\(payout.coinsEarned) coins", systemImage: "dollarsign.circle.fill")
                        .font(.title3.bold()).foregroundStyle(.orange)
                    if payout.isNewHighScore { Text("New record!").font(.subheadline.bold()) }
                } else {
                    Text("Your reward is not saved yet. Retry before starting another game.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Save reward again") { saveResultIfNeeded() }
                }
                Button("Play again") { restart() }
                    .buttonStyle(PetPrimaryButtonStyle())
                    .disabled(isSavingResult || !didSaveResult)
            }
            Button(finished && payout == nil ? "Leave without reward" : "Back to Arcade") { dismiss() }
                .disabled(isSavingResult)
        }
        .padding(24)
        .frame(maxWidth: 350)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
        .padding(20)
    }

    private func fire() {
        guard !isPaused, scenePhase == .active else { return }
        if engine.shoot() { lastTick = nil }
    }
    private func tick(at date: Date) {
        guard scenePhase == .active, !isPaused, engine.needsAnimation else { lastTick = nil; return }
        let dt = lastTick.map { date.timeIntervalSince($0) } ?? 1.0 / 60
        lastTick = date
        engine.update(deltaTime: dt)
        if !engine.needsAnimation { lastTick = nil }
    }
    private func restart() {
        runID = UUID(); payout = nil; didSaveResult = false; isSavingResult = false
        isPaused = false; lastTick = nil; engine.start()
    }
    private func saveResultIfNeeded() {
        guard finished, !didSaveResult, !isSavingResult else { return }
        isSavingResult = true
        let score = engine.score, id = runID
        Task {
            payout = await onFinish(score, id)
            didSaveResult = payout != nil
            isSavingResult = false
        }
    }
}

private enum BubblePalette {
    static let night = Color(red: 0.14, green: 0.16, blue: 0.25)
    static let cream = Color(red: 1.0, green: 0.86, blue: 0.65)
    static let coral = Color(red: 1.0, green: 0.55, blue: 0.49)
}

private struct BubbleAimButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .frame(width: 52, height: 52)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.08), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.16)))
    }
}

struct BubbleOrb: View {
    let color: BubbleColor
    var body: some View {
        GeometryReader { proxy in
            let d = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(color.tint)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.36), .clear, .black.opacity(0.28)],
                                             center: .init(x: 0.32, y: 0.25), startRadius: 0, endRadius: d * 0.77))
                Circle().strokeBorder(BubblePalette.night.opacity(0.65), lineWidth: d * 0.035)
                Circle().trim(from: 0.08, to: 0.36)
                    .stroke(.white.opacity(0.32), style: StrokeStyle(lineWidth: d * 0.035, lineCap: .round))
                    .padding(d * 0.1)
                Ellipse().fill(.white.opacity(0.78))
                    .frame(width: d * 0.23, height: d * 0.12)
                    .rotationEffect(.degrees(-35)).offset(x: -d * 0.18, y: -d * 0.23)
                Image(systemName: color.symbol)
                    .font(.system(size: d * 0.27, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .offset(x: d * 0.03, y: d * 0.07)
            }
            .frame(width: d, height: d)
        }
        .accessibilityHidden(true)
    }
}

/// The barrel rotates around the same chamber from which the simulation fires.
struct BubbleCannon: View {
    var angle: Double = 0
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 104
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 52, y: 52)
            func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
                Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
            }
            context.fill(Path(ellipseIn: CGRect(x: -44, y: 35, width: 88, height: 14)), with: .color(.black.opacity(0.18)))
            context.fill(rounded(-32, 18, 64, 19, 7), with: .color(Color(red: 0.37, green: 0.32, blue: 0.44)))
            var barrel = context
            barrel.rotate(by: .radians(angle))
            let tube = rounded(-18, -47, 36, 66, 9)
            barrel.fill(tube, with: .linearGradient(Gradient(colors: [BubblePalette.cream, Color(red: 0.72, green: 0.47, blue: 0.30)]),
                                                  startPoint: CGPoint(x: -18, y: 0), endPoint: CGPoint(x: 18, y: 0)))
            barrel.stroke(tube, with: .color(BubblePalette.night), lineWidth: 2.5)
            let rim = rounded(-22, -47, 44, 12, 5)
            barrel.fill(rim, with: .color(BubblePalette.cream))
            barrel.stroke(rim, with: .color(BubblePalette.night), lineWidth: 2)
            barrel.fill(rounded(-10, -30, 5, 30, 2), with: .color(.white.opacity(0.25)))
            let chamber = Path(ellipseIn: CGRect(x: -23, y: -23, width: 46, height: 46))
            context.fill(chamber, with: .color(Color(red: 0.39, green: 0.33, blue: 0.46)))
            context.stroke(chamber, with: .color(BubblePalette.cream), lineWidth: 3)
            for x: CGFloat in [-27, 27] {
                let wheel = Path(ellipseIn: CGRect(x: x - 12, y: 16, width: 24, height: 24))
                context.fill(wheel, with: .color(BubblePalette.night))
                context.stroke(wheel, with: .color(Color(red: 0.67, green: 0.56, blue: 0.51)), lineWidth: 3)
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: 25, width: 6, height: 6)), with: .color(BubblePalette.cream))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct BubblePlayfieldScenery: View {
    let ceiling: CGFloat
    let isDangerous: Bool
    var body: some View {
        Canvas { context, _ in
            context.translateBy(x: 10, y: 10)
            let well = Path(roundedRect: CGRect(x: -4, y: -8, width: 328, height: 465), cornerRadius: 18)
            context.fill(well, with: .color(BubblePalette.night.opacity(0.14)))
            for x: CGFloat in [-6, 322] {
                let rail = Path(roundedRect: CGRect(x: x, y: 8, width: 4, height: 413), cornerRadius: 2)
                context.fill(rail, with: .color(.white.opacity(0.18)))
                for y in stride(from: 25, through: 410, by: 28) {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: CGFloat(y), width: 4, height: 4)),
                                 with: .color(BubblePalette.cream.opacity(0.55)))
                }
            }
            let top = Path(roundedRect: CGRect(x: 0, y: ceiling - 8, width: 320, height: 6), cornerRadius: 3)
            context.fill(top, with: .color(BubblePalette.cream.opacity(0.6)))
            var line = Path()
            line.move(to: CGPoint(x: 6, y: BubbleBoard.dangerY))
            line.addLine(to: CGPoint(x: 314, y: BubbleBoard.dangerY))
            context.stroke(line, with: .color(BubblePalette.coral.opacity(isDangerous ? 0.85 : 0.35)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [3, 7]))
            // A single shared ground plane anchors the pet, launcher wheels and spare bubble.
            let front = Path(roundedRect: CGRect(x: 7, y: 541, width: 306, height: 18), cornerRadius: 9)
            context.fill(front, with: .color(Color(red: 0.25, green: 0.26, blue: 0.35)))
            let topStone = Path(roundedRect: CGRect(x: 4, y: 534, width: 312, height: 13), cornerRadius: 6)
            context.fill(topStone, with: .linearGradient(Gradient(colors: [Color(red: 0.59, green: 0.54, blue: 0.59),
                                                                                          Color(red: 0.40, green: 0.39, blue: 0.49)]),
                                                        startPoint: CGPoint(x: 0, y: 534), endPoint: CGPoint(x: 0, y: 547)))
            for x in [22, 292] {
                var tuft = Path()
                tuft.move(to: CGPoint(x: x, y: 536)); tuft.addQuadCurve(to: CGPoint(x: x - 6, y: 523), control: CGPoint(x: x - 1, y: 525))
                tuft.move(to: CGPoint(x: x, y: 536)); tuft.addQuadCurve(to: CGPoint(x: x + 5, y: 520), control: CGPoint(x: x + 1, y: 525))
                context.stroke(tuft, with: .color(Color(red: 0.67, green: 0.66, blue: 0.63)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
        .frame(width: 340, height: 580)
        .offset(x: -10, y: -10)
        .frame(width: 320, height: 560, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

struct BubbleGardenBackground: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [BubblePalette.night, Color(red: 0.29, green: 0.30, blue: 0.45),
                                  Color(red: 0.54, green: 0.45, blue: 0.53)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let moon = CGRect(x: w * 0.72, y: h * 0.32, width: w * 0.2, height: w * 0.2)
            context.fill(Path(ellipseIn: moon.insetBy(dx: -12, dy: -12)), with: .color(BubblePalette.cream.opacity(0.025)))
            context.fill(Path(ellipseIn: moon), with: .color(BubblePalette.cream.opacity(0.07)))
            for i in 0..<28 {
                let x = CGFloat((i * 137 + 37) % 997) / 997 * w
                let y = CGFloat((i * 193 + 131) % 991) / 991 * h * 0.8
                let r: CGFloat = i.isMultiple(of: 4) ? 2 : 1
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.26)))
            }
            for layer in 0..<3 {
                let base = h * (0.76 + CGFloat(layer) * 0.075)
                var hill = Path()
                hill.move(to: CGPoint(x: 0, y: h)); hill.addLine(to: CGPoint(x: 0, y: base))
                hill.addCurve(to: CGPoint(x: w, y: base + 20),
                              control1: CGPoint(x: w * 0.3, y: base - h * 0.10),
                              control2: CGPoint(x: w * 0.6, y: base + h * 0.12))
                hill.addLine(to: CGPoint(x: w, y: h)); hill.closeSubpath()
                context.fill(hill, with: .color(BubblePalette.night.opacity(0.20 + Double(layer) * 0.15)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension BubbleColor {
    var tint: Color {
        switch self {
        case .rose: Color(red: 0.94, green: 0.43, blue: 0.51)
        case .honey: Color(red: 0.97, green: 0.73, blue: 0.27)
        case .mint: Color(red: 0.28, green: 0.73, blue: 0.62)
        case .sky: Color(red: 0.29, green: 0.64, blue: 0.95)
        case .lilac: Color(red: 0.68, green: 0.48, blue: 0.89)
        }
    }
    var symbol: String {
        switch self {
        case .rose: "heart.fill"
        case .honey: "star.fill"
        case .mint: "leaf.fill"
        case .sky: "drop.fill"
        case .lilac: "moon.fill"
        }
    }
    var name: LocalizedStringKey {
        switch self {
        case .rose: "Pink heart"
        case .honey: "Yellow star"
        case .mint: "Mint leaf"
        case .sky: "Blue drop"
        case .lilac: "Purple moon"
        }
    }
}

struct BubblePawsCover: View {
    let pet: PetProfile
    var body: some View {
        ZStack {
            BubbleGardenBackground()
            VStack(spacing: 0) {
                HStack(spacing: 2) {
                    ForEach([BubbleColor.rose, .honey, .mint], id: \.self) { color in
                        BubbleOrb(color: color).frame(width: 24, height: 24)
                    }
                }
                HStack(spacing: 2) {
                    BubbleOrb(color: .honey).frame(width: 24, height: 24)
                    BubbleOrb(color: .mint).frame(width: 24, height: 24)
                }
                Spacer()
            }.padding(.top, 10)
            PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                       breed: pet.resolvedBreed, pose: .idle, animatesMotion: false)
                .frame(width: 62, height: 54).offset(x: -15, y: 35)
            BubbleCannon(angle: 0.2).frame(width: 54, height: 54).offset(x: 26, y: 28)
        }
    }
}
