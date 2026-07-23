import SwiftUI
import UIKit

/// An in-app playground for up to three pets.
///
/// The simulation runs only while this view is visible. Dynamic Island artwork
/// and behavior remain independent from this foreground-only experience.
struct PlayYardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var simulation: PlayYardSimulation

    init(pets: [PetProfile]) {
        let visiblePets = pets.isEmpty ? [PetProfile.starter] : Array(pets.prefix(3))
        _simulation = StateObject(wrappedValue: PlayYardSimulation(pets: visiblePets))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    PlayYardBackdrop()

                    ForEach(simulation.frame.actors) { actor in
                        PlayYardPetFigure(actor: actor)
                        .frame(width: actor.size, height: actor.size)
                        .position(actor.position)
                        .shadow(color: .black.opacity(0.14), radius: 5, y: 4)
                        .zIndex(actor.profile.species == .parrot ? 3 : 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(actor.profile.name)
                        .accessibilityValue(actor.profile.species.displayName)
                    }

                    yardBall
                        .position(simulation.frame.ballPosition)
                        .rotationEffect(.radians(simulation.frame.ballAngle))
                        .zIndex(4)

                    hint
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 14)
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
        .onDisappear {
            simulation.stop()
        }
    }

    private var yardBall: some View {
        YardBall()
            .frame(width: 42, height: 42)
            .scaleEffect(simulation.frame.isDraggingBall ? 1.12 : 1)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
            .contentShape(Circle().inset(by: -12))
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
    }

    private var hint: some View {
        Label("Drag and throw the ball", systemImage: "hand.draw.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.28))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum PlayYardCoordinateSpace {
    static let name = "pet-island-play-yard"
}

/// This is the only rendering seam between the playroom physics and the pet
/// artwork. It can be swapped for frame-based sprite sheets without touching
/// the simulation.
private struct PlayYardPetFigure: View {
    let actor: PlayYardSimulation.Actor

    var body: some View {
        PetArtwork(
            species: actor.profile.species,
            coat: actor.profile.coat,
            customColor: actor.profile.customColor,
            breed: actor.profile.resolvedBreed,
            pose: actor.pose,
            direction: actor.direction,
            step: actor.step,
            animatesMotion: false
        )
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
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color(.systemTeal).opacity(0.34), Color(.systemBlue).opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                HStack(spacing: max(proxy.size.width * 0.2, 48)) {
                    cloud(scale: 0.75).offset(y: -proxy.size.height * 0.38)
                    cloud(scale: 1).offset(y: -proxy.size.height * 0.48)
                }
                .foregroundStyle(.white.opacity(0.62))

                RoundedRectangle(cornerRadius: 52, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.44, green: 0.76, blue: 0.36), Color(red: 0.2, green: 0.52, blue: 0.24)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: max(proxy.size.height * 0.26, 150))
                    .offset(y: 42)
                    .shadow(color: .black.opacity(0.08), radius: 12, y: -4)
            }
        }
        .accessibilityHidden(true)
    }

    private func cloud(scale: CGFloat) -> some View {
        HStack(spacing: -9) {
            Circle().frame(width: 34, height: 34)
            Circle().frame(width: 48, height: 48).offset(y: -8)
            Circle().frame(width: 38, height: 38)
        }
        .scaleEffect(scale)
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

@MainActor
private final class PlayYardSimulation: NSObject, ObservableObject {
    struct Actor: Identifiable {
        let profile: PetProfile
        var position: CGPoint = .zero
        var direction: PetDirection = .right
        var pose: PetPose = .idle
        var step = 0
        var verticalVelocity: CGFloat = 0
        var isAirborne = false
        var landingTimeRemaining: TimeInterval = 0
        var jumpCooldown: TimeInterval = 0
        let size: CGFloat

        var id: UUID { profile.id }
    }

    struct Frame {
        var actors: [Actor]
        var ballPosition = CGPoint.zero
        var ballAngle: Double = 0
        var isDraggingBall = false
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

    init(pets: [PetProfile]) {
        frame = Frame(
            actors: pets.prefix(3).map { profile in
                Actor(
                    profile: profile,
                    pose: profile.species == .parrot ? .fly : .idle,
                    size: profile.species == .parrot ? 62 : 70
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

        let link = CADisplayLink(target: self, selector: #selector(update(_:)))
        link.preferredFramesPerSecond = reduceMotion ? 15 : 30
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastTimestamp = nil
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    func setReduceMotion(_ enabled: Bool) {
        reduceMotion = enabled
        displayLink?.preferredFramesPerSecond = enabled ? 15 : 30
    }

    func reset() {
        guard roomSize.width > 1, roomSize.height > 1 else { return }

        let count = max(frame.actors.count, 1)
        for index in frame.actors.indices {
            let x = roomSize.width * CGFloat(index + 1) / CGFloat(count + 1)
            let isFlying = frame.actors[index].profile.species == .parrot
            frame.actors[index].position = CGPoint(
                x: x,
                y: isFlying ? max(110, roomSize.height * 0.32) : groundY(for: frame.actors[index])
            )
            frame.actors[index].direction = index.isMultiple(of: 2) ? .right : .left
            frame.actors[index].pose = isFlying ? .fly : .idle
            frame.actors[index].step = 0
            frame.actors[index].verticalVelocity = 0
            frame.actors[index].isAirborne = false
            frame.actors[index].landingTimeRemaining = 0
            frame.actors[index].jumpCooldown = 0
        }

        frame.ballPosition = CGPoint(
            x: roomSize.width * 0.5,
            y: min(roomSize.height * 0.54, ballFloorY - 72)
        )
        frame.ballAngle = 0
        frame.isDraggingBall = false
        ballVelocity = .zero
        sampledDragVelocity = .zero
        lastDragPoint = nil
        lastDragTime = nil
        animationClock = 0
    }

    func dragBall(to point: CGPoint) {
        guard roomSize.width > 1, roomSize.height > 1 else { return }
        let now = CACurrentMediaTime()
        let clamped = clampedBallPoint(point)

        if !frame.isDraggingBall {
            frame.isDraggingBall = true
            ballVelocity = .zero
            sampledDragVelocity = .zero
        } else if let previousPoint = lastDragPoint, let previousTime = lastDragTime {
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
        guard frame.isDraggingBall else { return }
        let prediction = CGVector(
            dx: predictedEndPoint.x - frame.ballPosition.x,
            dy: predictedEndPoint.y - frame.ballPosition.y
        )
        let proposedVelocity = CGVector(
            dx: sampledDragVelocity.dx * 0.72 + prediction.dx * 2.8,
            dy: sampledDragVelocity.dy * 0.72 + prediction.dy * 2.8
        )

        ballVelocity = proposedVelocity.limited(to: reduceMotion ? 540 : 980)
        frame.isDraggingBall = false
        lastDragPoint = nil
        lastDragTime = nil
        sampledDragVelocity = .zero
    }

    @objc private func update(_ link: CADisplayLink) {
        guard roomSize.width > 1, roomSize.height > 1 else { return }
        guard let previousTimestamp = lastTimestamp else {
            lastTimestamp = link.timestamp
            return
        }

        let deltaTime = min(max(link.timestamp - previousTimestamp, 0), 1.0 / 15.0)
        lastTimestamp = link.timestamp
        animationClock += deltaTime

        var nextFrame = frame
        if !nextFrame.isDraggingBall {
            advanceBall(in: &nextFrame, by: deltaTime)
        }
        advancePets(in: &nextFrame, by: deltaTime)
        frame = nextFrame
    }

    private func advanceBall(in frame: inout Frame, by deltaTime: TimeInterval) {
        let floor = ballFloorY
        let restingOnFloor = frame.ballPosition.y >= floor - 0.5 && abs(ballVelocity.dy) < 42

        if !restingOnFloor {
            ballVelocity.dy += (reduceMotion ? 360 : 520) * deltaTime
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
            ballVelocity.dy = abs(ballVelocity.dy) * 0.7
        } else if frame.ballPosition.y >= floor {
            frame.ballPosition.y = floor
            if abs(ballVelocity.dy) < 86 {
                ballVelocity.dy = 0
            } else {
                ballVelocity.dy = -abs(ballVelocity.dy) * (reduceMotion ? 0.28 : 0.58)
            }
            ballVelocity.dx *= 0.92
        }

        let horizontalFriction = pow(0.992, deltaTime * 60)
        ballVelocity.dx *= horizontalFriction
        if abs(ballVelocity.dx) < 1.5 { ballVelocity.dx = 0 }

        if !reduceMotion {
            frame.ballAngle += Double(ballVelocity.dx / max(ballRadius, 1)) * deltaTime
        }
    }

    private func advancePets(in frame: inout Frame, by deltaTime: TimeInterval) {
        let count = frame.actors.count
        guard count > 0 else { return }

        for index in frame.actors.indices {
            var actor = frame.actors[index]
            let isFlying = actor.profile.species == .parrot
            let ground = groundY(for: actor)
            let formation = CGFloat(index) - CGFloat(count - 1) / 2
            let target = CGPoint(
                x: min(max(frame.ballPosition.x + formation * 54, actor.size * 0.42), roomSize.width - actor.size * 0.42),
                y: isFlying ? min(frame.ballPosition.y - 50, ground - 54) : ground
            )

            let dx = target.x - actor.position.x
            let dy = target.y - actor.position.y
            let horizontalDistance = abs(dx)
            let speed = movementSpeed(for: actor.profile.species) * (reduceMotion ? 0.62 : 1)
            actor.jumpCooldown = max(actor.jumpCooldown - deltaTime, 0)
            actor.landingTimeRemaining = max(actor.landingTimeRemaining - deltaTime, 0)

            if isFlying {
                let distance = hypot(dx, dy)
                if distance > 5 {
                    let travel = min(speed * deltaTime, distance)
                    actor.position.x += dx / distance * travel
                    actor.position.y += dy / distance * travel
                }
                actor.pose = .fly
            } else {
                let ballHeight = max(ballFloorY - frame.ballPosition.y, 0)
                if PlayYardMotionRules.shouldJump(
                    ballHeight: ballHeight,
                    horizontalDistance: horizontalDistance,
                    isAirborne: actor.isAirborne,
                    cooldown: actor.jumpCooldown,
                    reduceMotion: reduceMotion
                ) {
                    actor.isAirborne = true
                    actor.verticalVelocity = PlayYardMotionRules.launchVelocity(for: ballHeight)
                }

                let isRunning = horizontalDistance > 34
                if isRunning {
                    let direction: CGFloat = dx >= 0 ? 1 : -1
                    let airControl: CGFloat = actor.isAirborne ? 0.82 : 1
                    let runSpeed = speed * 1.16 * airControl
                    actor.position.x += direction * min(runSpeed * deltaTime, horizontalDistance - 34)
                }

                if actor.isAirborne {
                    actor.verticalVelocity += PlayYardMotionRules.gravity * deltaTime
                    actor.position.y += actor.verticalVelocity * deltaTime
                    actor.pose = .jump

                    if actor.position.y >= ground {
                        actor.position.y = ground
                        actor.verticalVelocity = 0
                        actor.isAirborne = false
                        actor.landingTimeRemaining = 0.14
                        actor.jumpCooldown = 0.72
                        actor.pose = .play
                    }
                } else if actor.landingTimeRemaining > 0 {
                    actor.position.y = ground
                    actor.pose = .play
                } else if isRunning {
                    // The sprite frames carry the leg motion. A tiny contact
                    // bounce gives weight without making the whole pet float.
                    let contactBounce = reduceMotion
                        ? 0
                        : abs(sin(animationClock * 16 + Double(index))) * 1.8
                    actor.position.y = ground - contactBounce
                    actor.pose = .run
                } else {
                    actor.position.y = ground
                    actor.pose = .play
                }
            }

            if abs(dx) > 2 {
                actor.direction = dx >= 0 ? .right : .left
            }
            let clip = PetAnimationLibrary.clip(
                for: actor.profile.species,
                breed: actor.profile.resolvedBreed,
                pose: actor.pose
            )
            actor.step = clip.frameIndex(at: animationClock, phaseOffset: index)
            actor.position.x = min(max(actor.position.x, actor.size * 0.4), roomSize.width - actor.size * 0.4)
            actor.position.y = min(max(actor.position.y, actor.size * 0.44), ground)
            frame.actors[index] = actor
        }
    }

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
        max(actor.size * 0.52, roomSize.height - actor.size * 0.5 - 20)
    }

    private var ballRadius: CGFloat { 21 }
    private var ballFloorY: CGFloat { max(ballRadius + 12, roomSize.height - ballRadius - 22) }

    private func clampedBallPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, ballRadius + 10), max(roomSize.width - ballRadius - 10, ballRadius + 10)),
            y: min(max(point.y, ballRadius + 12), ballFloorY)
        )
    }

    private func movementSpeed(for species: PetSpecies) -> CGFloat {
        switch species {
        case .parrot: 190
        case .dog, .fox: 150
        case .cat, .penguin: 136
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
