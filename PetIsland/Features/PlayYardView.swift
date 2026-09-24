import SwiftUI
import UIKit

/// An in-app playground for all six enclosure residents.
///
/// The simulation runs only while this view is visible. Dynamic Island artwork
/// and behavior remain independent from this foreground-only experience.
struct PlayYardView: View {
    @Environment(\.dismiss) private var dismiss
    @PetReduceMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var simulation: PlayYardSimulation

    init(pets: [PetProfile], hapticsEnabled: Bool = true) {
        let visiblePets = pets.isEmpty ? [PetProfile.starter] : Array(pets.prefix(PetHabitatState.maximumResidents))
        _simulation = StateObject(wrappedValue: PlayYardSimulation(pets: visiblePets, hapticsEnabled: hapticsEnabled))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    PlayYardBackdrop()

                    if simulation.frame.phase == .ready {
                        PlayYardBallReadyMarker()
                            .frame(width: 50, height: 50)
                            .position(simulation.frame.ballPosition)
                            .transition(.scale.combined(with: .opacity))
                    }

                    if let dragOrigin = simulation.frame.dragOrigin {
                        PlayYardAimGuide(origin: dragOrigin, end: simulation.frame.ballPosition)
                            .allowsHitTesting(false)
                            .zIndex(2)
                    }

                    ForEach(simulation.frame.actors) { actor in
                        PlayYardPetFigure(
                            actor: actor,
                            carriesBall: simulation.frame.phase == .returning
                                && actor.id == simulation.frame.fetcherID
                        )
                        .frame(width: actor.size, height: actor.size)
                        .position(actor.position)
                        .zIndex(actor.profile.species == .parrot ? 3 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(actor.profile.name)
                        .accessibilityValue(actor.profile.species.displayName)
                    }

                    if simulation.frame.phase != .returning {
                        yardBall
                            .rotationEffect(.radians(simulation.frame.ballAngle))
                            .position(simulation.frame.ballPosition)
                            .zIndex(4)
                    }

                    gameHUD
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)
                        .zIndex(5)
                }
                .coordinateSpace(name: PlayYardCoordinateSpace.name)
                .clipShape(Rectangle())
                .onAppear {
                    simulation.configure(roomSize: proxy.size)
                    simulation.start(reduceMotion: reduceMotion)
                }
                .onChange(of: proxy.size) { _, newSize in
                    simulation.configure(roomSize: newSize)
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Playroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        simulation.reset()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") {
                        simulation.stop()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: reduceMotion) { _, newValue in
            simulation.setReduceMotion(newValue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { simulation.start(reduceMotion: reduceMotion) }
            else { simulation.stop() }
        }
        .onDisappear {
            simulation.stop()
        }
    }

    private var yardBall: some View {
        YardBall()
            .frame(
                width: PlayYardGameRules.ballDiameter,
                height: PlayYardGameRules.ballDiameter
            )
            .scaleEffect(simulation.frame.isDraggingBall ? 1.12 : 1)
            .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
            .contentShape(Circle().inset(by: -18))
            .allowsHitTesting(simulation.frame.phase == .ready)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(PlayYardCoordinateSpace.name))
                    .onChanged { value in
                        simulation.dragBall(to: value.location)
                    }
                    .onEnded { value in
                        simulation.throwBall(toward: value.predictedEndLocation)
                    }
            )
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: simulation.frame.isDraggingBall)
            .accessibilityLabel("Ball")
            .accessibilityHint("Drag and throw it for your pets")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { simulation.throwAccessibleBall() }
    }

    private var gameHUD: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                scoreCard(
                    title: String(localized: "Fetches"),
                    value: simulation.frame.score,
                    symbol: "pawprint.fill",
                    color: .green
                )
                scoreCard(
                    title: String(localized: "Throws"),
                    value: simulation.frame.throwCount,
                    symbol: "figure.disc.sports",
                    color: .orange
                )
            }
            .padding(.horizontal, 16)

            Label(phaseTitle, systemImage: phaseSymbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.34))
                }
                .contentTransition(.numericText())
        }
        .allowsHitTesting(false)
    }

    private func scoreCard(title: String, value: Int, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value, format: .number)
                    .font(.title3.bold())
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.3))
        }
    }

    private var activePetName: String? {
        guard let fetcherID = simulation.frame.fetcherID else { return nil }
        return simulation.frame.actors.first { $0.id == fetcherID }?.profile.name
    }

    private var phaseTitle: String {
        switch simulation.frame.phase {
        case .ready:
            String(localized: "Swipe the ball and release")
        case .inFlight:
            String(localized: "Catch it!")
        case .fetching:
            String(localized: "Running after the ball")
        case .returning:
            if let activePetName {
                String.localizedStringWithFormat(
                    String(localized: "%@ is bringing the ball back"),
                    activePetName
                )
            } else {
                String(localized: "Bringing the ball back")
            }
        case .celebrating:
            String(localized: "Good catch!")
        }
    }

    private var phaseSymbol: String {
        switch simulation.frame.phase {
        case .ready: "hand.draw.fill"
        case .inFlight: "sparkles"
        case .fetching: "figure.run"
        case .returning: "arrow.uturn.backward.circle.fill"
        case .celebrating: "star.fill"
        }
    }
}

private enum PlayYardCoordinateSpace {
    static let name = "pet-island-play-yard"
}

enum PlayYardPhase: Equatable {
    case ready
    case inFlight
    case fetching
    case returning
    case celebrating
}

enum PlayYardMouthLayout {
    static let carriedBallDiameter: CGFloat = 21

    static func offset(
        for species: PetSpecies,
        size: CGFloat,
        direction: PetDirection
    ) -> CGSize {
        let proportions: (forward: CGFloat, vertical: CGFloat) = switch species {
        case .dog: (0.42, 0.01)
        case .cat: (0.39, -0.01)
        case .lion: (0.38, -0.03)
        case .fox: (0.43, 0)
        case .penguin: (0.36, -0.04)
        case .parrot: (0.32, -0.07)
        }
        let directionSign: CGFloat = direction == .right ? 1 : -1
        return CGSize(
            width: proportions.forward * size * directionSign,
            height: proportions.vertical * size
        )
    }
}

private struct PlayYardBallReadyMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.2))
            Circle()
                .strokeBorder(.white.opacity(0.82), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
        }
        .accessibilityHidden(true)
    }
}

private struct PlayYardAimGuide: View {
    let origin: CGPoint
    let end: CGPoint

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: origin)
            path.addLine(to: end)
            context.stroke(
                path,
                with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 7])
            )

            context.fill(
                Path(ellipseIn: CGRect(x: origin.x - 5, y: origin.y - 5, width: 10, height: 10)),
                with: .color(.white.opacity(0.78))
            )
        }
        .accessibilityHidden(true)
    }
}

/// This is the only rendering seam between the playroom physics and the pet
/// artwork. It can be swapped for frame-based sprite sheets without touching
/// the simulation.
private struct PlayYardPetFigure: View {
    let actor: PlayYardSimulation.Actor
    let carriesBall: Bool

    @PetReduceMotion private var reduceMotion

    var body: some View {
        ZStack {
            if actor.profile.species != .parrot {
                Ellipse()
                    .fill(.black.opacity(0.16))
                    .frame(width: actor.size * 0.58, height: actor.size * 0.12)
                    .scaleEffect(x: shadowScale)
                    .offset(y: actor.size * 0.34)
                    .blur(radius: 0.4)
            }

            PetArtwork(
                species: actor.profile.species,
                coat: actor.profile.coat,
                customColor: actor.profile.customColor,
                breed: actor.profile.resolvedBreed,
                pose: actor.pose,
                direction: actor.direction,
                step: actor.step,
                animatesMotion: false, usesNaturalGait: true
            )
            .offset(y: bodyLift)

            if carriesBall {
                let mouth = PlayYardMouthLayout.offset(
                    for: actor.profile.species,
                    size: actor.size,
                    direction: actor.direction
                )
                YardBall()
                    .frame(
                        width: PlayYardMouthLayout.carriedBallDiameter,
                        height: PlayYardMouthLayout.carriedBallDiameter
                    )
                    .offset(x: mouth.width, y: mouth.height + bodyLift)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .accessibilityHidden(true)
    }

    private var bodyLift: CGFloat {
        guard !reduceMotion else { return 0 }
        if actor.pose == .fly {
            return (sin(actor.motionPhase) * 2.5).rounded()
        }
        // The art already contains foot lift. Moving the entire grounded body
        // adds a second, unrelated bounce and breaks its contact with the floor.
        return 0
    }

    private var shadowScale: CGFloat {
        guard !reduceMotion else { return 1 }
        return actor.isAirborne ? 0.85 : 1
    }
}

private struct YardBall: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.98, green: 0.93, blue: 0.24), Color(red: 0.66, green: 0.82, blue: 0.08)],
                        center: .topLeading,
                        startRadius: 2,
                        endRadius: 34
                    )
                )

            Circle()
                .strokeBorder(.white.opacity(0.7), lineWidth: 2)

            Canvas { context, size in
                var seam = Path()
                seam.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.34))
                seam.addCurve(
                    to: CGPoint(x: size.width * 0.88, y: size.height * 0.66),
                    control1: CGPoint(x: size.width * 0.42, y: size.height * 0.48),
                    control2: CGPoint(x: size.width * 0.58, y: size.height * 0.52)
                )
                context.stroke(seam, with: .color(.white.opacity(0.88)), lineWidth: 2.2)

                var oppositeSeam = Path()
                oppositeSeam.move(to: CGPoint(x: size.width * 0.34, y: size.height * 0.12))
                oppositeSeam.addCurve(
                    to: CGPoint(x: size.width * 0.66, y: size.height * 0.88),
                    control1: CGPoint(x: size.width * 0.48, y: size.height * 0.42),
                    control2: CGPoint(x: size.width * 0.52, y: size.height * 0.58)
                )
                context.stroke(oppositeSeam, with: .color(.white.opacity(0.88)), lineWidth: 2.2)
            }
            .padding(2)
        }
        .drawingGroup()
    }
}

private struct PlayYardBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            Image("PlayYardBackground")
                .resizable()
                .interpolation(.none)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.02), .black.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .accessibilityHidden(true)
    }
}

/// Tunable, deterministic locomotion rules kept outside the display-link
/// object so the jump conditions can be unit tested without rendering a view.
enum PlayYardMotionRules {
    static let gravity: CGFloat = 780
    static let minimumBallHeight: CGFloat = 38
    static let maximumJumpDistance: CGFloat = 148

    static func shouldJump(
        ballHeight: CGFloat,
        horizontalDistance: CGFloat,
        isAirborne: Bool,
        cooldown: TimeInterval,
        reduceMotion: Bool
    ) -> Bool {
        !reduceMotion
            && !isAirborne
            && cooldown <= 0
            && ballHeight >= minimumBallHeight
            && horizontalDistance >= 18
            && horizontalDistance <= maximumJumpDistance
    }

    static func launchVelocity(for ballHeight: CGFloat) -> CGFloat {
        let desiredHeight = min(max(ballHeight + 18, 66), 142)
        return -sqrt(2 * gravity * desiredHeight)
    }
}

/// Stable rules for a throw-and-fetch round. Keeping them independent from
/// CADisplayLink makes the controls and catch conditions deterministic.
enum PlayYardGameRules {
    static let ballDiameter: CGFloat = 30
    static let maximumDragDistance: CGFloat = 112
    static let minimumThrowSpeed: CGFloat = 180
    static let maximumThrowSpeed: CGFloat = 430
    static let maximumHorizontalThrowSpeed: CGFloat = 360
    static let maximumUpwardThrowSpeed: CGFloat = 400
    static let maximumDownwardThrowSpeed: CGFloat = 220
    static let maximumFlightDuration: TimeInterval = 2.4

    static func constrainedDrag(_ drag: CGVector) -> CGVector {
        drag.limited(to: maximumDragDistance)
    }

    static func throwVelocity(
        drag: CGVector,
        prediction: CGVector,
        sampledVelocity: CGVector,
        reduceMotion: Bool
    ) -> CGVector {
        let controlledPrediction = prediction.limited(to: 80)
        let controlledSample = sampledVelocity.limited(to: 700)
        var velocity = CGVector(
            dx: drag.dx * 2.35 + controlledPrediction.dx * 0.24 + controlledSample.dx * 0.025,
            dy: drag.dy * 2.35 + controlledPrediction.dy * 0.24 + controlledSample.dy * 0.025
        )
        let maximum = reduceMotion ? maximumThrowSpeed * 0.78 : maximumThrowSpeed
        velocity = velocity.limited(to: maximum)

        let speed = hypot(velocity.dx, velocity.dy)
        if speed < minimumThrowSpeed {
            let dragLength = hypot(drag.dx, drag.dy)
            let source = dragLength > 8 ? drag : CGVector(dx: 0.35, dy: -0.94)
            let sourceLength = hypot(source.dx, source.dy)
            let direction = CGVector(
                dx: source.dx / sourceLength,
                dy: source.dy / sourceLength
            )
            velocity = CGVector(
                dx: direction.dx * minimumThrowSpeed,
                dy: direction.dy * minimumThrowSpeed
            )
        }

        velocity.dx = min(max(velocity.dx, -maximumHorizontalThrowSpeed), maximumHorizontalThrowSpeed)
        velocity.dy = min(
            max(velocity.dy, -maximumUpwardThrowSpeed),
            maximumDownwardThrowSpeed
        )
        return velocity.limited(to: maximum)
    }

    static func shouldCatch(
        ballHeight: CGFloat,
        horizontalDistance: CGFloat,
        directDistance: CGFloat,
        isAirborne: Bool,
        isFlying: Bool
    ) -> Bool {
        if isFlying {
            return directDistance <= 44
        }
        if isAirborne {
            return directDistance <= 38
        }
        return ballHeight <= 30 && horizontalDistance <= 32
    }

    static func ballIsSettled(ballHeight: CGFloat, velocity: CGVector) -> Bool {
        ballHeight <= 1
            && abs(velocity.dx) < 26
            && abs(velocity.dy) < 32
    }
}

@MainActor
final class PlayYardSimulation: NSObject, ObservableObject {
    struct Actor: Identifiable {
        let profile: PetProfile
        var position: CGPoint = .zero
        var direction: PetDirection = .right
        var pose: PetPose = .idle
        var step = 0
        var motionPhase: Double = 0
        var verticalVelocity: CGFloat = 0
        var isAirborne = false
        var landingTimeRemaining: TimeInterval = 0
        var jumpCooldown: TimeInterval = 0
        var distanceTravelled: CGFloat = 0
        var gaitPhase = 0.0
        let size: CGFloat

        var id: UUID { profile.id }
    }

    struct Frame {
        var actors: [Actor]
        var ballPosition = CGPoint.zero
        var ballAngle: Double = 0
        var isDraggingBall = false
        var dragOrigin: CGPoint?
        var phase: PlayYardPhase = .ready
        var fetcherID: UUID?
        var score = 0
        var throwCount = 0
    }

    @Published private(set) var frame: Frame

    private var displayLink: CADisplayLink?
    private var roomSize = CGSize.zero
    private var ballVelocity = CGVector.zero
    private var lastTimestamp: CFTimeInterval?
    private var animationClock: TimeInterval = 0
    private var reduceMotion = false
    private var lastDragPoint: CGPoint?
    private var lastDragTime: CFTimeInterval?
    private var sampledDragVelocity = CGVector.zero
    private var ballRestTime: TimeInterval = 0
    private var ballHasBounced = false
    private var carryTimeRemaining: TimeInterval = 0
    private var celebrationTimeRemaining: TimeInterval = 0
    private var roundElapsed: TimeInterval = 0
    private var nextFetcherIndex = 0
    private let hapticsEnabled: Bool
#if DEBUG
    private var scheduledDebugThrow = false
#endif

    init(pets: [PetProfile], hapticsEnabled: Bool = true) {
        self.hapticsEnabled = hapticsEnabled
        frame = Frame(
            actors: pets.prefix(PetHabitatState.maximumResidents).map { profile in
                let size: CGFloat
                switch profile.species {
                case .dog:
                    size = 88
                case .cat:
                    size = 90
                case .lion:
                    size = 96
                case .fox, .penguin:
                    size = 92
                case .parrot:
                    size = 84
                }
                return Actor(
                    profile: profile,
                    pose: profile.species == .parrot ? .fly : .idle,
                    size: size
                )
            }
        )
        super.init()
    }

    deinit {
        displayLink?.invalidate()
    }

    func configure(roomSize: CGSize) {
        guard roomSize.width > 1, roomSize.height > 1 else { return }
        let hadUsableSize = self.roomSize.width > 1 && self.roomSize.height > 1
        self.roomSize = roomSize

        if hadUsableSize {
            clampFrameToRoom()
        } else {
            reset()
        }
    }

    func start(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        guard displayLink == nil else {
            setReduceMotion(reduceMotion)
            return
        }

        let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.update(_:)))
        link.preferredFramesPerSecond = reduceMotion ? 15 : 60
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = nil

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-playroom-autoplay"), !scheduledDebugThrow {
            scheduledDebugThrow = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.performDebugThrow()
            }
        }
#endif
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
        if frame.isDraggingBall {
            frame.isDraggingBall = false
            frame.dragOrigin = nil
            frame.ballPosition = readyBallPoint
            lastDragPoint = nil
            lastDragTime = nil
            sampledDragVelocity = .zero
        }
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        displayLink?.preferredFramesPerSecond = enabled ? 15 : 30
    }

    func reset() {
        guard roomSize.width > 1, roomSize.height > 1 else { return }

        let count = max(frame.actors.count, 1)
        for index in frame.actors.indices {
            let x = spectatorX(for: index, count: count)
            let isFlying = frame.actors[index].profile.species == .parrot
            frame.actors[index].position = CGPoint(
                x: x,
                y: isFlying ? max(170, roomSize.height * 0.5) : groundY(for: frame.actors[index])
            )
            frame.actors[index].direction = index.isMultiple(of: 2) ? .right : .left
            frame.actors[index].pose = isFlying ? .fly : .idle
            frame.actors[index].step = 0
            frame.actors[index].motionPhase = 0
            frame.actors[index].verticalVelocity = 0
            frame.actors[index].isAirborne = false
            frame.actors[index].landingTimeRemaining = 0
            frame.actors[index].jumpCooldown = 0
            frame.actors[index].distanceTravelled = 0
        }

        frame.ballPosition = readyBallPoint
        frame.ballAngle = 0
        frame.isDraggingBall = false
        frame.dragOrigin = nil
        frame.phase = .ready
        frame.fetcherID = nil
        frame.score = 0
        frame.throwCount = 0
        ballVelocity = .zero
        sampledDragVelocity = .zero
        lastDragPoint = nil
        lastDragTime = nil
        ballRestTime = 0
        ballHasBounced = false
        carryTimeRemaining = 0
        celebrationTimeRemaining = 0
        roundElapsed = 0
        nextFetcherIndex = 0
        animationClock = 0
    }

    func dragBall(to point: CGPoint) {
        guard roomSize.width > 1, roomSize.height > 1, frame.phase == .ready else { return }
        let now = CACurrentMediaTime()

        if !frame.isDraggingBall {
            frame.isDraggingBall = true
            frame.dragOrigin = frame.ballPosition
            ballVelocity = .zero
            sampledDragVelocity = .zero
        }

        let origin = frame.dragOrigin ?? frame.ballPosition
        let requested = clampedBallPoint(point)
        let offset = PlayYardGameRules.constrainedDrag(
            CGVector(dx: requested.x - origin.x, dy: requested.y - origin.y)
        )
        let clamped = clampedBallPoint(
            CGPoint(x: origin.x + offset.dx, y: origin.y + offset.dy)
        )

        if let previousPoint = lastDragPoint, let previousTime = lastDragTime {
            let elapsed = max(now - previousTime, 1.0 / 120.0)
            let currentVelocity = CGVector(
                dx: (clamped.x - previousPoint.x) / elapsed,
                dy: (clamped.y - previousPoint.y) / elapsed
            )
            sampledDragVelocity = CGVector(
                dx: sampledDragVelocity.dx * 0.55 + currentVelocity.dx * 0.45,
                dy: sampledDragVelocity.dy * 0.55 + currentVelocity.dy * 0.45
            )
        }

        frame.ballPosition = clamped
        lastDragPoint = clamped
        lastDragTime = now
    }

    func throwBall(toward predictedEndPoint: CGPoint) {
        guard frame.isDraggingBall, frame.phase == .ready else { return }
        let origin = frame.dragOrigin ?? frame.ballPosition
        let drag = CGVector(
            dx: frame.ballPosition.x - origin.x,
            dy: frame.ballPosition.y - origin.y
        )
        let prediction = CGVector(
            dx: predictedEndPoint.x - frame.ballPosition.x,
            dy: predictedEndPoint.y - frame.ballPosition.y
        )
        ballVelocity = PlayYardGameRules.throwVelocity(
            drag: drag,
            prediction: prediction,
            sampledVelocity: sampledDragVelocity,
            reduceMotion: reduceMotion
        )

        frame.isDraggingBall = false
        frame.dragOrigin = nil
        frame.phase = .inFlight
        frame.throwCount += 1
        if !frame.actors.isEmpty {
            let fetcherIndex = nextFetcherIndex % frame.actors.count
            frame.fetcherID = frame.actors[fetcherIndex].id
            nextFetcherIndex = (fetcherIndex + 1) % frame.actors.count
        }
        lastDragPoint = nil
        lastDragTime = nil
        sampledDragVelocity = .zero
        ballRestTime = 0
        ballHasBounced = false
        carryTimeRemaining = 0
        celebrationTimeRemaining = 0
        roundElapsed = 0

        if hapticsEnabled { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    func throwAccessibleBall() {
        guard frame.phase == .ready else { return }
        let start = frame.ballPosition
        dragBall(to: CGPoint(x: start.x + 60, y: start.y - 70))
        throwBall(toward: CGPoint(x: start.x + 120, y: start.y - 150))
    }

    @MainActor
    private final class DisplayLinkTarget: NSObject {
        weak var simulation: PlayYardSimulation?
        init(_ simulation: PlayYardSimulation) { self.simulation = simulation }
        @objc func update(_ link: CADisplayLink) { simulation?.update(link) }
    }

    @objc private func update(_ link: CADisplayLink) {
        guard roomSize.width > 1, roomSize.height > 1 else { return }
        guard let previousTimestamp = lastTimestamp else {
            lastTimestamp = link.timestamp
            return
        }

        let deltaTime = min(max(link.timestamp - previousTimestamp, 0), 1.0 / 15.0)
        lastTimestamp = link.timestamp
        advance(by: deltaTime)
    }

    /// Also drives deterministic physics regression tests without a display link.
    func advance(by deltaTime: TimeInterval) {
        guard deltaTime.isFinite, deltaTime > 0, roomSize.width > 1, roomSize.height > 1 else { return }
        let deltaTime = min(deltaTime, 1.0 / 15.0)
        animationClock += deltaTime

        var nextFrame = frame
        if nextFrame.phase == .inFlight || nextFrame.phase == .fetching {
            roundElapsed += deltaTime
            advanceBall(in: &nextFrame, by: deltaTime)
        }
        if nextFrame.phase == .returning {
            carryTimeRemaining = max(carryTimeRemaining - deltaTime, 0)
        }
        advancePets(in: &nextFrame, by: deltaTime)

        if nextFrame.phase == .celebrating {
            celebrationTimeRemaining = max(celebrationTimeRemaining - deltaTime, 0)
            if celebrationTimeRemaining == 0 {
                prepareNextRound(in: &nextFrame)
            }
        }
        frame = nextFrame
    }

    private func advanceBall(in frame: inout Frame, by deltaTime: TimeInterval) {
        let floor = ballFloorY
        guard frame.ballPosition.x.isFinite,
              frame.ballPosition.y.isFinite,
              ballVelocity.dx.isFinite,
              ballVelocity.dy.isFinite else {
            frame.ballPosition = CGPoint(x: roomSize.width * 0.5, y: floor)
            ballVelocity = .zero
            ballRestTime = 0.12
            frame.phase = .fetching
            return
        }

        let restingOnFloor = frame.ballPosition.y >= floor - 0.5 && abs(ballVelocity.dy) < 64

        if !restingOnFloor {
            ballVelocity.dy = min(ballVelocity.dy + 1_050 * deltaTime, 1_100)
        } else {
            ballVelocity.dy = 0
            frame.ballPosition.y = floor
        }

        frame.ballPosition.x += ballVelocity.dx * deltaTime
        frame.ballPosition.y += ballVelocity.dy * deltaTime

        let left = ballRadius + 10
        let right = max(roomSize.width - ballRadius - 10, left)
        let top = ballRadius + 12

        if frame.ballPosition.x <= left {
            frame.ballPosition.x = left
            ballVelocity.dx = abs(ballVelocity.dx) * 0.72
        } else if frame.ballPosition.x >= right {
            frame.ballPosition.x = right
            ballVelocity.dx = -abs(ballVelocity.dx) * 0.72
        }

        if frame.ballPosition.y <= top {
            frame.ballPosition.y = top
            ballVelocity.dy = max(abs(ballVelocity.dy) * 0.22, 120)
        } else if frame.ballPosition.y >= floor {
            frame.ballPosition.y = floor
            let impactSpeed = abs(ballVelocity.dy)
            if impactSpeed < 150 || ballHasBounced || roundElapsed > 1.8 {
                ballVelocity.dy = 0
            } else {
                ballHasBounced = true
                let bounce = reduceMotion ? 0 : min(impactSpeed * 0.18, 110)
                ballVelocity.dy = -bounce
            }
            ballVelocity.dx *= 0.72
        }

        let horizontalFriction = pow(0.965, deltaTime * 60)
        ballVelocity.dx *= horizontalFriction
        if abs(ballVelocity.dx) < 1.5 { ballVelocity.dx = 0 }

        if !reduceMotion {
            frame.ballAngle += Double(ballVelocity.dx / max(ballRadius, 1)) * deltaTime
        }

        if roundElapsed >= PlayYardGameRules.maximumFlightDuration {
            frame.ballPosition.y = floor
            ballVelocity = .zero
            ballRestTime = 0.12
        }

        let ballHeight = max(floor - frame.ballPosition.y, 0)
        if PlayYardGameRules.ballIsSettled(ballHeight: ballHeight, velocity: ballVelocity) {
            ballRestTime += deltaTime
        } else {
            ballRestTime = 0
        }
        if frame.phase == .inFlight && ballRestTime >= 0.12 {
            frame.phase = .fetching
        }
    }

    private func advancePets(in frame: inout Frame, by deltaTime: TimeInterval) {
        let count = frame.actors.count
        guard count > 0 else { return }

        for index in frame.actors.indices {
            var actor = frame.actors[index]
            let previousPosition = actor.position
            let isFlying = actor.profile.species == .parrot
            let ground = groundY(for: actor)
            let speed = movementSpeed(for: actor.profile.species)
            let isFetcher = actor.id == frame.fetcherID
            actor.jumpCooldown = max(actor.jumpCooldown - deltaTime, 0)
            actor.landingTimeRemaining = max(actor.landingTimeRemaining - deltaTime, 0)

            if isFetcher && (frame.phase == .inFlight || frame.phase == .fetching) {
                let target = CGPoint(
                    x: frame.ballPosition.x,
                    y: isFlying
                        ? (frame.phase == .fetching
                            ? max(actor.size * 0.44, frame.ballPosition.y - 28)
                            : min(frame.ballPosition.y, ground - 48))
                        : ground
                )
                let dx = target.x - actor.position.x
                let horizontalDistance = abs(dx)

                if isFlying {
                    move(&actor, toward: target, speed: speed, deltaTime: deltaTime)
                    actor.pose = .fly
                } else {
                    let isRunning = horizontalDistance > 26
                    if isRunning {
                        let direction: CGFloat = dx >= 0 ? 1 : -1
                        actor.direction = dx >= 0 ? .right : .left
                        let airControl: CGFloat = actor.isAirborne ? 0.84 : 1
                        actor.position.x += direction * min(
                            speed * airControl * deltaTime,
                            max(horizontalDistance - 22, 0)
                        )
                    }

                    let ballHeight = max(ballFloorY - frame.ballPosition.y, 0)
                    if frame.phase == .fetching && PlayYardMotionRules.shouldJump(
                        ballHeight: ballHeight,
                        horizontalDistance: horizontalDistance,
                        isAirborne: actor.isAirborne,
                        cooldown: actor.jumpCooldown,
                        reduceMotion: reduceMotion
                    ) {
                        actor.isAirborne = true
                        actor.verticalVelocity = PlayYardMotionRules.launchVelocity(for: ballHeight)
                    }

                    if actor.isAirborne {
                        actor.verticalVelocity += PlayYardMotionRules.gravity * deltaTime
                        actor.position.y += actor.verticalVelocity * deltaTime
                        actor.pose = .jump

                        if actor.position.y >= ground {
                            actor.position.y = ground
                            actor.verticalVelocity = 0
                            actor.isAirborne = false
                            actor.landingTimeRemaining = 0.12
                            actor.jumpCooldown = 0.68
                        }
                    } else if actor.landingTimeRemaining > 0 {
                        actor.position.y = ground
                        actor.pose = .play
                    } else if isRunning {
                        actor.position.y = ground
                        actor.pose = .run
                    } else {
                        actor.position.y = ground
                        actor.pose = .play
                    }
                }

                let ballHeight = max(ballFloorY - frame.ballPosition.y, 0)
                let directDistance = hypot(
                    frame.ballPosition.x - actor.position.x,
                    frame.ballPosition.y - actor.position.y
                )
                if frame.phase == .fetching && PlayYardGameRules.shouldCatch(
                    ballHeight: ballHeight,
                    horizontalDistance: abs(frame.ballPosition.x - actor.position.x),
                    directDistance: directDistance,
                    isAirborne: actor.isAirborne,
                    isFlying: isFlying
                ) {
                    beginReturn(with: &actor, in: &frame)
                }
            } else if isFetcher && frame.phase == .returning {
                let homeY = isFlying ? ground - 48 : ground
                let home = CGPoint(x: roomSize.width * 0.5, y: homeY)
                let dx = home.x - actor.position.x
                let distance = hypot(dx, home.y - actor.position.y)
                if distance > 0.01 {
                    move(&actor, toward: home, speed: speed * 0.72, deltaTime: deltaTime)
                    actor.pose = isFlying ? .fly : .run
                    attachBall(to: actor, in: &frame)
                } else if carryTimeRemaining > 0 {
                    actor.position = home
                    actor.pose = isFlying ? .fly : .idle
                    attachBall(to: actor, in: &frame)
                } else {
                    actor.position = home
                    actor.pose = isFlying ? .fly : .play
                    frame.ballPosition = readyBallPoint
                    frame.phase = .celebrating
                    frame.score += 1
                    celebrationTimeRemaining = reduceMotion ? 0.35 : 0.85
                    if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            } else if isFetcher && frame.phase == .celebrating {
                actor.position.y = isFlying ? ground - 48 : ground
                actor.pose = isFlying ? .fly : .play
            } else {
                moveSpectator(
                    &actor,
                    index: index,
                    count: count,
                    ground: ground,
                    speed: speed,
                    deltaTime: deltaTime
                )
            }

            let clip = PetAnimationLibrary.naturalClip(
                for: actor.profile.species,
                breed: actor.profile.resolvedBreed,
                pose: actor.pose
            )
            let travelled = hypot(actor.position.x - previousPosition.x, actor.position.y - previousPosition.y)
            actor.distanceTravelled += travelled
            if actor.pose == .walk || actor.pose == .run {
                actor.gaitPhase = (actor.gaitPhase + travelled / max(actor.size * (actor.pose == .run ? 0.55 : 0.38), 1))
                    .truncatingRemainder(dividingBy: 1)
                actor.step = reduceMotion ? 0 : Int(actor.gaitPhase * Double(clip.frames.count))
            } else {
                actor.step = reduceMotion ? 0 : clip.frameIndex(at: animationClock, phaseOffset: index)
            }
            let motionSpeed: Double = switch actor.pose {
            case .run: 13
            case .walk: 8
            case .fly: 10
            case .idle, .play: 2.4
            default: 0
            }
            actor.motionPhase = animationClock * motionSpeed + Double(index) * 0.8
            actor.position.x = min(max(actor.position.x, actor.size * 0.4), roomSize.width - actor.size * 0.4)
            actor.position.y = min(max(actor.position.y, actor.size * 0.44), ground)
            frame.actors[index] = actor
        }
    }

    private func moveSpectator(
        _ actor: inout Actor,
        index: Int,
        count: Int,
        ground: CGFloat,
        speed: CGFloat,
        deltaTime: TimeInterval
    ) {
        let isFlying = actor.profile.species == .parrot
        let target = CGPoint(
            x: spectatorX(for: index, count: count),
            y: isFlying ? max(170, roomSize.height * 0.5) : ground
        )
        let dx = target.x - actor.position.x
        let distance = hypot(dx, target.y - actor.position.y)
        if distance > 0.01 {
            move(&actor, toward: target, speed: speed * 0.38, deltaTime: deltaTime)
            actor.direction = dx >= 0 ? .right : .left
            actor.pose = isFlying ? .fly : .walk
        } else {
            actor.position = target
            actor.pose = isFlying ? .fly : .idle
        }
    }

    private func move(
        _ actor: inout Actor,
        toward target: CGPoint,
        speed: CGFloat,
        deltaTime: TimeInterval
    ) {
        let dx = target.x - actor.position.x
        let dy = target.y - actor.position.y
        let distance = hypot(dx, dy)
        guard distance > 0 else { return }
        let travel = min(speed * deltaTime, distance)
        actor.position.x += dx / distance * travel
        actor.position.y += dy / distance * travel
        if abs(dx) > 2 {
            actor.direction = dx >= 0 ? .right : .left
        }
    }

    private func beginReturn(with actor: inout Actor, in frame: inout Frame) {
        frame.phase = .returning
        ballVelocity = .zero
        ballRestTime = 0
        actor.verticalVelocity = 0
        actor.isAirborne = false
        actor.pose = actor.profile.species == .parrot ? .fly : .run
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-playroom-hold-carry") {
            carryTimeRemaining = 8
        } else {
            carryTimeRemaining = reduceMotion ? 0.35 : 0.8
        }
#else
        carryTimeRemaining = reduceMotion ? 0.35 : 0.8
#endif
        attachBall(to: actor, in: &frame)
        if hapticsEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    private func attachBall(to actor: Actor, in frame: inout Frame) {
        let mouth = PlayYardMouthLayout.offset(
            for: actor.profile.species,
            size: actor.size,
            direction: actor.direction
        )
        frame.ballPosition = CGPoint(
            x: actor.position.x + mouth.width,
            y: actor.position.y + mouth.height
        )
        frame.ballAngle += reduceMotion ? 0 : 0.08
    }

    private func prepareNextRound(in frame: inout Frame) {
        frame.phase = .ready
        frame.fetcherID = nil
        frame.ballPosition = readyBallPoint
        frame.ballAngle = 0
        frame.dragOrigin = nil
        frame.isDraggingBall = false
        ballVelocity = .zero
        sampledDragVelocity = .zero
        lastDragPoint = nil
        lastDragTime = nil
        ballRestTime = 0
        ballHasBounced = false
        carryTimeRemaining = 0
        roundElapsed = 0
    }

#if DEBUG
    private func performDebugThrow() {
        guard frame.phase == .ready else { return }
        let start = frame.ballPosition
        dragBall(to: CGPoint(x: start.x - 72, y: start.y - 118))
        throwBall(toward: CGPoint(x: start.x - 126, y: start.y - 205))
    }
#endif

    private func clampFrameToRoom() {
        frame.ballPosition = clampedBallPoint(frame.ballPosition)
        for index in frame.actors.indices {
            let actor = frame.actors[index]
            frame.actors[index].position = CGPoint(
                x: min(max(actor.position.x, actor.size * 0.4), roomSize.width - actor.size * 0.4),
                y: min(max(actor.position.y, actor.size * 0.44), groundY(for: actor))
            )
        }
    }

    private func groundY(for actor: Actor) -> CGFloat {
        max(actor.size * 0.52, roomSize.height - actor.size * 0.5 - 54)
    }

    private var ballRadius: CGFloat { PlayYardGameRules.ballDiameter * 0.5 }
    private var ballFloorY: CGFloat { max(ballRadius + 12, roomSize.height - ballRadius - 56) }

    private var readyBallPoint: CGPoint {
        CGPoint(
            x: roomSize.width * 0.5,
            y: max(ballRadius + 36, ballFloorY - 94)
        )
    }

    private func spectatorX(for index: Int, count: Int) -> CGFloat {
        let fractions: [CGFloat]
        switch count {
        case 1: fractions = [0.18]
        case 2: fractions = [0.18, 0.82]
        case 3: fractions = [0.14, 0.86, 0.65]
        default: fractions = (0..<count).map { CGFloat($0 + 1) / CGFloat(count + 1) }
        }
        let fraction = fractions[min(index, fractions.count - 1)]
        return min(max(roomSize.width * fraction, 34), max(roomSize.width - 34, 34))
    }

    private func clampedBallPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, ballRadius + 10), max(roomSize.width - ballRadius - 10, ballRadius + 10)),
            y: min(max(point.y, ballRadius + 12), ballFloorY)
        )
    }

    private func movementSpeed(for species: PetSpecies) -> CGFloat {
        switch species {
        case .parrot: 236
        case .dog, .fox, .lion: 214
        case .cat, .penguin: 196
        }
    }
}

private extension CGVector {
    func limited(to maximumLength: CGFloat) -> CGVector {
        let length = hypot(dx, dy)
        guard length > maximumLength, length > 0 else { return self }
        let scale = maximumLength / length
        return CGVector(dx: dx * scale, dy: dy * scale)
    }
}

#if DEBUG
#Preview("Игровая комната") {
    PlayYardView(
        pets: [
            .starter,
            PetProfile(
                id: UUID(),
                name: "Моти",
                species: .cat,
                coat: .cloud,
                createdAt: .now
            ),
            PetProfile(
                id: UUID(),
                name: "Кеша",
                species: .parrot,
                coat: .sunrise,
                createdAt: .now
            )
        ]
    )
}
#endif
