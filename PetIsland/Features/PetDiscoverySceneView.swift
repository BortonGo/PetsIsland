import SwiftUI

/// Only the visible, uncovered sheet runs a 30 Hz timeline. Dates drive the scene;
/// no frame updates are persisted and no background simulation is required.
struct PetDiscoverySceneView: View {
    let walk: PetDiscoveryWalk
    let isAnimationEnabled: Bool
    let isComplete: Bool
    let viewportHeight: CGFloat
    @Environment(\.scenePhase) private var scenePhase
    @PetReduceMotion private var reduceMotion
    @State private var isVisible = false
    @State private var isInViewport = false
    @State private var hasReturned = false

    private var animates: Bool {
        isVisible && isInViewport && isAnimationEnabled && scenePhase == .active && !reduceMotion && !hasReturned && !isComplete
    }

    var body: some View {
        let plan = PetDiscoveryScenePlan(walk: walk)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animates)) { timeline in
            let frame = plan.frame(at: hasReturned || isComplete ? walk.endsAt : timeline.date)
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    ZStack {
                        DiscoveryLandscape(route: walk.route)
                        if !frame.isHome {
                            pet(frame: frame, in: proxy.size)
                        }
                        DiscoveryLandscape(route: walk.route, foreground: true,
                                           activity: frame.activity, actionTime: animates ? frame.actionTime : 0)
                        if frame.isHome {
                            Label("Back home", systemImage: "house.fill")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(.regularMaterial, in: Capsule())
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        Label(walk.route.discoveryTitle, systemImage: walk.route.discoverySymbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(.regularMaterial, in: Capsule())
                            .padding(12)
                    }
                }
                .aspectRatio(1.5, contentMode: .fit)
                .clipped()
                HStack(spacing: 8) {
                    Image(systemName: frame.isHome ? "house" : frame.isMoving
                          ? (walk.pet.species == .parrot ? "bird" : "pawprint") : "sparkle.magnifyingglass")
                        .foregroundStyle(PetDesign.secondary)
                    Text(activityTitle(for: frame))
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(PetDesign.soft)
            }
            .onChange(of: frame.isHome, initial: true) { _, value in hasReturned = value }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(walk.pet.name), \(walk.route.discoveryTitle)"))
            .accessibilityValue(Text(activityTitle(for: frame)))
            .accessibilityIdentifier("discoveries.scene")
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .background {
            GeometryReader { geometry in
                let rect = geometry.frame(in: .named("discoveryScroll"))
                Color.clear.onChange(of: rect.maxY > 0 && rect.minY < viewportHeight, initial: true) { _, value in
                    isInViewport = value
                }
            }
        }
        .onAppear { isVisible = true; hasReturned = walk.isReady(at: .now) }
        .onDisappear { isVisible = false }
        .onChange(of: isComplete) { _, value in hasReturned = value }
    }

    private func activityTitle(for frame: PetDiscoveryScenePlan.Frame) -> LocalizedStringKey {
        walk.pet.species == .parrot && frame.activity == .walking ? "Flying over the path" : frame.activity.title
    }

    private func pet(frame: PetDiscoveryScenePlan.Frame, in size: CGSize) -> some View {
        let width = min(size.width * 0.27, 104)
        let pet = walk.pet
        let pose: PetPose = reduceMotion ? .idle : frame.isMoving ? (pet.species == .parrot ? .fly : .walk)
            : ([.bush, .stones, .roots, .log, .reeds].contains(frame.activity) && frame.actionTime < 2.4 ? .play : .idle)
        let clip = PetAnimationLibrary.naturalClip(for: pet.species, breed: pet.resolvedBreed, pose: pose)
        let step = reduceMotion ? 0 : frame.isMoving
            ? clip.travelFrameIndex(distance: frame.travelledDistance(in: size), canvasWidth: width, pose: pose)
            : clip.frameIndex(at: frame.actionTime)
        let flightLift = pet.species == .parrot && frame.isMoving && !reduceMotion
            ? sin(frame.movementProgress * .pi) * 20 : 0
        let ground = CGPoint(x: frame.position.x * size.width, y: frame.position.y * size.height)
        return ZStack {
            Ellipse().fill(.black.opacity(0.14))
                .frame(width: width * 0.51, height: 6)
                .position(ground)
            PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                       breed: pet.resolvedBreed, pose: pose, direction: frame.direction, step: step,
                       animatesMotion: false, usesNaturalGait: true)
                .frame(width: width, height: width * 0.8)
                // The shared artwork's baseline is 160 on its 220 × 176 canvas.
                .position(x: ground.x, y: ground.y - width * 72 / 220 - flightLift)
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
    }
}

extension PetDiscoveryScenePlan.Activity {
    var title: LocalizedStringKey {
        switch self {
        case .walking: "Following the path"
        case .flowers: "Sniffing the flowers"
        case .bush: "Peeking into the bushes"
        case .stones: "Looking between the pebbles"
        case .waves: "Watching the waves"
        case .reeds: "Listening to the reeds"
        case .roots: "Exploring the tree roots"
        case .log: "Checking behind the fallen branch"
        case .mushrooms: "Watching the little mushrooms"
        case .lookingAround: "Taking in the surroundings"
        case .headingHome: "Heading home with a find"
        case .returned: "The walk is over. Your pet is home."
        }
    }
}

/// Code-drawn scenery scales with the card. Landmarks share coordinates with the
/// walk plan, so a pet investigates an actual bush, rock or branch in the scene.
struct DiscoveryLandscape: View {
    let route: PetWalkRoute
    var foreground = false
    var activity: PetDiscoveryScenePlan.Activity = .walking
    var actionTime: TimeInterval = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            var painter = DiscoveryLandscapePainter(context: context, dark: colorScheme == .dark, route: route)
            painter.context.scaleBy(x: size.width / 360, y: size.height / 240)
            if foreground {
                painter.foreground(activity: activity, time: actionTime)
            } else {
                painter.background()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DiscoveryLandscapePainter {
    var context: GraphicsContext
    let dark: Bool
    let route: PetWalkRoute

    func color(_ day: UInt32, _ night: UInt32) -> Color {
        let hex = dark ? night : day
        return Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                     blue: Double(hex & 255) / 255)
    }
    func ellipse(_ rect: CGRect, _ fill: Color) { context.fill(Path(ellipseIn: rect), with: .color(fill)) }
    func rounded(_ rect: CGRect, _ radius: CGFloat, _ fill: Color) {
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(fill))
    }
    func line(_ points: [CGPoint], _ color: Color, width: CGFloat = 2) {
        guard let first = points.first else { return }
        var path = Path(); path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    func background() {
        let sky = route == .shore ? color(0x95CDD9, 0x293E55) : color(0xD4E5E3, 0x303D4B)
        context.fill(Path(CGRect(x: 0, y: 0, width: 360, height: 240)), with: .linearGradient(
            Gradient(colors: [sky, color(0xF3E8CD, 0x647071)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 230)))
        ellipse(CGRect(x: 270, y: 24, width: 36, height: 36), color(0xFFF4CF, 0xD5DFC9).opacity(0.9))
        for i in 0..<3 {
            let x = CGFloat(i * 114 - 20), y = CGFloat(43 + i % 2 * 24)
            ellipse(CGRect(x: x, y: y, width: 86, height: 15), .white.opacity(dark ? 0.07 : 0.28))
            ellipse(CGRect(x: x + 23, y: y - 7, width: 47, height: 20), .white.opacity(dark ? 0.05 : 0.2))
        }
        if route == .shore { shore() } else { meadow() }
        if route == .garden {
            // The fence sits beyond the footpath, never in front of the pet.
            for x in stride(from: 5, through: 355, by: 23) {
                rounded(CGRect(x: x, y: 112, width: 8, height: 31), 3, color(0xF4EEDB, 0x899895))
            }
            rounded(CGRect(x: 0, y: 123, width: 360, height: 5), 2, color(0xE8E1CD, 0x788A87))
            bush(x: 29, y: 140, scale: 0.85)
            bush(x: 315, y: 134, scale: 0.95)
        } else if route == .grove {
            for (x, y, scale) in [(18.0, 143.0, 0.75), (122, 141, 0.95), (258, 142, 0.8), (343, 157, 1.1)] {
                tree(x: x, y: y, scale: scale)
            }
        }
        for stop in PetDiscoveryScenePlan.stops(for: route) { landmark(stop, rustle: 0) }
        for i in 0..<18 {
            let x = CGFloat((i * 71 + 19) % 360), y = CGFloat(152 + (i * 43) % 82)
            if route == .shore {
                ellipse(CGRect(x: x, y: y, width: 3, height: 1.5), color(0xBCA887, 0x82776D).opacity(0.65))
            } else {
                line([CGPoint(x: x - 2, y: y), CGPoint(x: x, y: y + 4), CGPoint(x: x + 2, y: y - 2)],
                     color(0x7D9F73, 0x566F63).opacity(0.55), width: 1.5)
            }
        }
    }

    private func meadow() {
        var hill = Path(); hill.move(to: CGPoint(x: 0, y: 132))
        hill.addCurve(to: CGPoint(x: 360, y: 140), control1: CGPoint(x: 92, y: 72), control2: CGPoint(x: 202, y: 150))
        hill.addLine(to: CGPoint(x: 360, y: 240)); hill.addLine(to: CGPoint(x: 0, y: 240)); hill.closeSubpath()
        context.fill(hill, with: .color(color(0xADC69A, 0x4D685B)))
        var ground = Path(); ground.move(to: CGPoint(x: 0, y: 160))
        ground.addCurve(to: CGPoint(x: 360, y: 154), control1: CGPoint(x: 115, y: 131), control2: CGPoint(x: 222, y: 178))
        ground.addLine(to: CGPoint(x: 360, y: 240)); ground.addLine(to: CGPoint(x: 0, y: 240)); ground.closeSubpath()
        context.fill(ground, with: .color(route == .grove ? color(0xB0B788, 0x535F4D) : color(0xC1D4A1, 0x607B60)))
        var path = Path(); path.move(to: CGPoint(x: -12, y: 203))
        path.addCurve(to: CGPoint(x: 370, y: 176), control1: CGPoint(x: 100, y: 160), control2: CGPoint(x: 210, y: 227))
        context.stroke(path, with: .color(color(0xEEE0B7, 0x9C9277).opacity(0.7)), style: StrokeStyle(lineWidth: 27, lineCap: .round))
    }

    private func shore() {
        context.fill(Path(CGRect(x: 0, y: 100, width: 360, height: 140)), with: .color(color(0x73B9C6, 0x446D82)))
        for i in 0..<5 {
            line([CGPoint(x: CGFloat(i * 85 - 12), y: CGFloat(112 + i % 2 * 10)),
                  CGPoint(x: CGFloat(i * 85 + 35), y: CGFloat(112 + i % 2 * 10))], .white.opacity(0.25), width: 2)
        }
        var beach = Path(); beach.move(to: CGPoint(x: 0, y: 152))
        beach.addCurve(to: CGPoint(x: 360, y: 162), control1: CGPoint(x: 130, y: 128), control2: CGPoint(x: 228, y: 190))
        beach.addLine(to: CGPoint(x: 360, y: 240)); beach.addLine(to: CGPoint(x: 0, y: 240)); beach.closeSubpath()
        context.fill(beach, with: .color(color(0xE9D7AF, 0xA29982)))
        var foam = Path(); foam.move(to: CGPoint(x: 0, y: 152))
        foam.addCurve(to: CGPoint(x: 360, y: 162), control1: CGPoint(x: 130, y: 128), control2: CGPoint(x: 228, y: 190))
        context.stroke(foam, with: .color(.white.opacity(0.65)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        ellipse(CGRect(x: 18, y: 133, width: 34, height: 16), color(0x9CAAA6, 0x6C7D80))
        ellipse(CGRect(x: 40, y: 138, width: 24, height: 12), color(0xB8BDB0, 0x8B9790))
    }

    private func tree(x: CGFloat, y: CGFloat, scale: CGFloat) {
        rounded(CGRect(x: x - 7 * scale, y: y - 90 * scale, width: 14 * scale, height: 94 * scale), 5,
                color(0x8C7963, 0x655A52))
        line([CGPoint(x: x, y: y - 28 * scale), CGPoint(x: x - 21 * scale, y: y - 52 * scale)],
             color(0x8C7963, 0x655A52), width: 6 * scale)
        for (dx, dy, radius) in [(-22.0, -81.0, 31.0), (17, -94, 38), (35, -64, 27)] {
            ellipse(CGRect(x: x + (dx - radius) * scale, y: y + (dy - radius) * scale,
                           width: radius * 2 * scale, height: radius * 1.55 * scale), color(0x829F75, 0x3F594E))
        }
        ellipse(CGRect(x: x - 21 * scale, y: y - 127 * scale, width: 51 * scale, height: 29 * scale), color(0xA8BF88, 0x5B725B))
    }

    private func bush(x: CGFloat, y: CGFloat, scale: CGFloat) {
        for (dx, dy, radius) in [(-19.0, -9.0, 18.0), (0, -19, 25), (23, -8, 20)] {
            ellipse(CGRect(x: x + (dx - radius) * scale, y: y + (dy - radius) * scale,
                           width: radius * 2 * scale, height: radius * 1.6 * scale), color(0x739768, 0x3F6251))
        }
        ellipse(CGRect(x: x - 17 * scale, y: y - 43 * scale, width: 31 * scale, height: 16 * scale), color(0x9AB17D, 0x678566))
        for dx in [-19.0, 9, 24] { ellipse(CGRect(x: x + dx * scale, y: y - 15 * scale, width: 3, height: 3), color(0xE5C68C, 0xBDA983)) }
    }

    private func landmark(_ stop: PetDiscoveryScenePlan.Stop, rustle: Double) {
        let x = stop.landmark.x * 360, y = stop.landmark.y * 240
        switch stop.activity {
        case .flowers:
            for i in 0..<5 {
                let dx = CGFloat(i * 9 - 18), height = CGFloat(16 + i % 3 * 6)
                line([CGPoint(x: x + dx, y: y), CGPoint(x: x + dx + rustle, y: y - height)], color(0x668A66, 0x54765E), width: 2)
                for a in 0..<5 {
                    let angle = Double(a) * .pi * 2 / 5
                    ellipse(CGRect(x: x + dx + rustle + cos(angle) * 4 - 3, y: y - height + sin(angle) * 4 - 3, width: 6, height: 6),
                            i.isMultiple(of: 2) ? color(0xE8A9AD, 0xCC969D) : color(0xF3E4BD, 0xDCD1A5))
                }
                ellipse(CGRect(x: x + dx + rustle - 2, y: y - height - 2, width: 4, height: 4), color(0xC19C59, 0xA39061))
            }
        case .bush: bush(x: x + rustle, y: y, scale: 0.8)
        case .stones:
            for (dx, dy, w, h) in [(-14.0, -3.0, 21.0, 12.0), (4, -1, 17, 10), (-1, -9, 19, 14)] {
                ellipse(CGRect(x: x + dx, y: y + dy - h, width: w, height: h), color(0xABA89A, 0x777F7A))
                ellipse(CGRect(x: x + dx + 4, y: y + dy - h + 2, width: w * 0.45, height: 3), .white.opacity(0.25))
            }
        case .waves: break
        case .reeds:
            for i in 0..<7 {
                let dx = CGFloat(i * 5 - 14), height = CGFloat(22 + (i * 13) % 28)
                line([CGPoint(x: x + dx, y: y), CGPoint(x: x + dx + rustle + CGFloat(i % 3 - 1) * 7, y: y - height)], color(0x8B9B6A, 0x677C64), width: 2)
                if i.isMultiple(of: 2) { rounded(CGRect(x: x + dx + rustle - 2, y: y - height, width: 4, height: 11), 2, color(0xB18E60, 0xA48B68)) }
            }
        case .roots:
            tree(x: x, y: y - 3, scale: 0.95)
            line([CGPoint(x: x - 16, y: y), CGPoint(x: x, y: y - 8), CGPoint(x: x + 18, y: y)], color(0x8C7963, 0x655A52), width: 5)
        case .log:
            rounded(CGRect(x: x - 27, y: y - 16, width: 54, height: 17), 7, color(0x987E60, 0x756553))
            ellipse(CGRect(x: x + 17, y: y - 16, width: 12, height: 17), color(0xD0B88F, 0xAA9877))
            line([CGPoint(x: x - 18, y: y - 12), CGPoint(x: x + 13, y: y - 12)], color(0xC5AB80, 0x9A8668), width: 2)
            line([CGPoint(x: x - 5, y: y - 12), CGPoint(x: x - 12, y: y - 27)], color(0x987E60, 0x756553), width: 6)
        case .mushrooms:
            for (dx, height) in [(-10.0, 15.0), (10, 22)] {
                rounded(CGRect(x: x + dx - 2, y: y - height, width: 5, height: height), 2, color(0xE0D6B9, 0xB8B198))
                ellipse(CGRect(x: x + dx - 10, y: y - height - 7, width: 20, height: 12), color(0xC48A69, 0xAC7D65))
                ellipse(CGRect(x: x + dx - 5, y: y - height - 5, width: 4, height: 3), color(0xF0DAB5, 0xD0B896))
            }
        default: break
        }
    }

    func foreground(activity: PetDiscoveryScenePlan.Activity, time: TimeInterval) {
        // A few foreground tufts give the pet a ground plane without hiding its legs.
        for (x, y) in [(10.0, 228.0), (333, 237), (282, 231)] {
            line([CGPoint(x: x - 6, y: y - 10), CGPoint(x: x, y: y), CGPoint(x: x + 4, y: y - 15)],
                 route == .shore ? color(0xA49E74, 0x8A8C6D) : color(0x739366, 0x405D4C), width: 3)
        }
        guard let stop = PetDiscoveryScenePlan.stops(for: route).first(where: { $0.activity == activity }) else { return }
        let x = stop.landmark.x * 360, y = stop.landmark.y * 240
        // Rustling and ripples are visible only while the companion is inspecting this spot.
        let pulse = sin(time * 5) * min(time, 1)
        if [.flowers, .bush, .reeds].contains(activity) { landmark(stop, rustle: pulse * 1.3) }
        if activity == .waves {
            for i in 0..<3 {
                let width = 16 + Double(i) * 12 + pulse * 2
                let rect = CGRect(x: x - width / 2, y: y - 5 + Double(i) * 4, width: width, height: 4)
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.55 - Double(i) * 0.12)), lineWidth: 1)
            }
        } else {
            for i in 0..<3 {
                let dx = Double(i * 12 - 12), dy = -37.0 - Double(i % 2) * 9 - pulse * 2
                line([CGPoint(x: x + dx - 2, y: y + dy), CGPoint(x: x + dx + 2, y: y + dy)], color(0xF9E6B5, 0xE8D4A3), width: 1.5)
                line([CGPoint(x: x + dx, y: y + dy - 2), CGPoint(x: x + dx, y: y + dy + 2)], color(0xF9E6B5, 0xE8D4A3), width: 1.5)
            }
        }
    }
}

#if DEBUG
/// Uses an in-memory collection for simulator QA; never starts a real user walk.
struct PetDiscoverySceneDebugHost: View {
    @StateObject private var controller: PetSessionController
    private let dark: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let route: PetWalkRoute = arguments.contains("-discovery-scene-shore") ? .shore
            : arguments.contains("-discovery-scene-grove") ? .grove : .garden
        let elapsed: TimeInterval = arguments.contains("-discovery-scene-ready") ? route.duration + 1
            : arguments.contains("-discovery-scene-ending") ? route.duration - 3 : 20
        var state = PersistedAppState()
        state.completedOnboarding = true
        let bird = arguments.contains("-discovery-scene-bird")
        let pet = PetProfile(id: UUID(), name: bird ? "Кеша" : "Pixel", species: bird ? .parrot : .cat,
                             coat: .sunrise, createdAt: .now, breed: bird ? .macaw : .classicCat)
        state.profile = pet
        if !arguments.contains("-discovery-scene-picker") {
            let start = Date.now.addingTimeInterval(-elapsed)
            let walk = PetDiscoveryWalk(id: UUID(uuidString: "01000000-0000-0000-0000-000000000001")!,
                                        pet: pet, route: route, startedAt: start, endsAt: start.addingTimeInterval(route.duration),
                                        discovery: route.discoveryIDs[0])!
            state.discoveries = PetDiscoveriesState(activeWalk: walk)
        }
        state.settings.minimizeMotion = arguments.contains("-discovery-scene-reduced-motion")
        dark = arguments.contains("-discovery-scene-dark")
        _controller = StateObject(wrappedValue: PetSessionController(store: InMemoryPetStore(state), arcadeStore: InMemoryArcadeStore()))
    }

    var body: some View {
        PetDiscoveriesView(controller: controller)
            .task { await controller.bootstrap() }
            .environment(\.petMinimizeMotion, controller.settings.minimizeMotion)
            .preferredColorScheme(dark ? .dark : .light)
    }
}
#endif
