import SwiftUI

/// All games advance the same amount of simulation time at 30, 60 and 120 Hz.
/// Long interruptions are bounded; scene lifecycle pauses are handled by the views.
struct ArcadeSimulationClock {
    static let step: TimeInterval = 1.0 / 120.0
    private var remainder: TimeInterval = 0

    mutating func steps(for elapsed: TimeInterval) -> Int {
        guard elapsed.isFinite, elapsed > 0 else { return 0 }
        remainder += min(elapsed, 0.25)
        let count = Int((remainder + 1e-9) / Self.step)
        remainder = max(0, remainder - Double(count) * Self.step)
        return count
    }
}

enum ArcadePalette {
    static let ink = Color(red: 0.16, green: 0.23, blue: 0.29)
    static let sky = Color(red: 0.43, green: 0.72, blue: 0.85)
    static let mist = Color(red: 0.86, green: 0.92, blue: 0.89)
    static let grass = Color(red: 0.36, green: 0.62, blue: 0.49)
    static let grassLight = Color(red: 0.60, green: 0.76, blue: 0.53)
    static let sand = Color(red: 0.91, green: 0.79, blue: 0.59)
    static let coral = Color(red: 0.84, green: 0.39, blue: 0.29)
    static let gold = Color(red: 1.0, green: 0.77, blue: 0.32)
}

struct ArcadeHUD: View {
    let score: Int
    let highScore: Int
    var coins: Int? = nil
    let playing: Bool
    let onPause: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPause) {
                Image(systemName: playing ? "pause.fill" : "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 17))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? Text("Pause game") : Text("Close"))
            metric("SCORE", value: score)
            Spacer(minLength: 4)
            if let coins {
                Label("\(coins)", systemImage: "pawprint.fill")
                    .font(.system(.subheadline, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(ArcadePalette.gold)
                    .accessibilityLabel("\(coins) coins")
            }
            metric("BEST", value: max(score, highScore))
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(ArcadePalette.ink.opacity(0.88), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.18), lineWidth: 1))
        .padding(.horizontal, 18)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func metric(_ label: LocalizedStringKey, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .bold, design: .rounded)).tracking(1.2)
                .foregroundStyle(.white.opacity(0.66))
            Text("\(value)").font(.system(.title3, design: .rounded).bold().monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ArcadeControlStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(prominent ? ArcadePalette.ink : .white)
            .frame(width: prominent ? 76 : 58, height: 54)
            .background(prominent ? ArcadePalette.gold : ArcadePalette.ink.opacity(0.88),
                        in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.24), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Low contrast distant scenery, shared by the two sky games. All positions scale
/// with the viewport; only gameplay objects use saturated warning colors.
struct ArcadeSky: View {
    var travel: CGFloat = 0
    var vertical = false

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: vertical
                         ? [Color(red: 0.37, green: 0.50, blue: 0.71), Color(red: 0.87, green: 0.79, blue: 0.74)]
                         : [ArcadePalette.sky, ArcadePalette.mist]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let sun = CGPoint(x: w * 0.78, y: h * 0.23)
            context.fill(Path(ellipseIn: CGRect(x: sun.x - 41, y: sun.y - 41, width: 82, height: 82)),
                         with: .color(Color(red: 1, green: 0.91, blue: 0.70).opacity(0.85)))
            for layer in 0..<3 {
                let base = h * (0.77 + CGFloat(layer) * 0.08)
                var hill = Path()
                hill.move(to: CGPoint(x: -20, y: h))
                hill.addLine(to: CGPoint(x: -20, y: base))
                hill.addCurve(to: CGPoint(x: w + 20, y: base + 15),
                              control1: CGPoint(x: w * 0.25, y: base - h * 0.17),
                              control2: CGPoint(x: w * 0.68, y: base + h * 0.10))
                hill.addLine(to: CGPoint(x: w + 20, y: h)); hill.closeSubpath()
                context.fill(hill, with: .color(ArcadePalette.ink.opacity(0.035 + Double(layer) * 0.015)))
            }
            for i in 0..<9 {
                let depth = CGFloat(i % 3 + 1)
                let width: CGFloat = 65 + depth * 25
                let rawX = CGFloat((i * 137 + 37) % 997) / 997 * (w + 180)
                let x = (rawX - (vertical ? 0 : travel * depth * 0.07)).arcadeWrapped(w + 180) - 90
                let rawY = CGFloat((i * 193 + 131) % 991) / 991 * h
                let y = (rawY + (vertical ? travel * depth * 0.08 : 0)).arcadeWrapped(h + 100) - 50
                let rect = CGRect(x: x, y: y, width: width, height: width * 0.36)
                context.fill(ArcadeCloudShape().path(in: rect), with: .color(.white.opacity(0.18 + Double(depth) * 0.08)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ArcadeCloudShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        path.move(to: point(0.12, 1))
        path.addCurve(to: point(0.12, 0.45), control1: point(-0.06, 0.93), control2: point(-0.02, 0.45))
        path.addCurve(to: point(0.46, 0.17), control1: point(0.12, 0.01), control2: point(0.35, -0.05))
        path.addCurve(to: point(0.80, 0.42), control1: point(0.58, -0.16), control2: point(0.84, 0.05))
        path.addCurve(to: point(0.90, 1), control1: point(1.04, 0.38), control2: point(1.10, 0.95))
        path.closeSubpath()
        return path
    }
}

struct ArcadePlatformArtwork: View {
    let fragile: Bool
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let earth = Path { p in
                p.move(to: CGPoint(x: 0, y: 5)); p.addLine(to: CGPoint(x: w, y: 5))
                p.addLine(to: CGPoint(x: w * 0.80, y: 24)); p.addLine(to: CGPoint(x: w * 0.36, y: 29))
                p.addLine(to: CGPoint(x: w * 0.12, y: 20)); p.closeSubpath()
            }
            context.fill(earth, with: .color(fragile ? Color(red: 0.60, green: 0.39, blue: 0.30) : Color(red: 0.37, green: 0.44, blue: 0.49)))
            let top = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: 10), cornerRadius: 4)
            context.fill(top, with: .color(fragile ? ArcadePalette.sand : ArcadePalette.grassLight))
            var line = Path()
            if fragile {
                line.move(to: CGPoint(x: w * 0.58, y: 0)); line.addLine(to: CGPoint(x: w * 0.46, y: 10))
                line.addLine(to: CGPoint(x: w * 0.55, y: 14)); line.addLine(to: CGPoint(x: w * 0.42, y: 25))
            } else {
                line.move(to: CGPoint(x: 10, y: 3)); line.addLine(to: CGPoint(x: w - 10, y: 3))
            }
            context.stroke(line, with: .color(fragile ? ArcadePalette.ink.opacity(0.65) : .white.opacity(0.5)), lineWidth: 2)
        }
    }
}

extension CGFloat {
    func arcadeWrapped(_ length: CGFloat) -> CGFloat {
        let value = truncatingRemainder(dividingBy: length)
        return value < 0 ? value + length : value
    }
}

struct ArcadeHazardArtwork: View {
    let storm: Bool
    var rotation: Double = 0

    var body: some View {
        Canvas { c, size in
            let w = size.width, h = size.height
            if storm {
                let cloud = ArcadeCloudShape().path(in: CGRect(x: 0, y: 1, width: w, height: h * 0.62))
                c.fill(cloud, with: .color(Color(red: 0.32, green: 0.37, blue: 0.54)))
                let shine = ArcadeCloudShape().path(in: CGRect(x: w * 0.08, y: 0, width: w * 0.70, height: h * 0.43))
                c.fill(shine, with: .color(Color(red: 0.56, green: 0.59, blue: 0.73)))
                var bolt = Path()
                bolt.move(to: CGPoint(x: w * 0.55, y: h * 0.45))
                bolt.addLine(to: CGPoint(x: w * 0.34, y: h * 0.76))
                bolt.addLine(to: CGPoint(x: w * 0.49, y: h * 0.74))
                bolt.addLine(to: CGPoint(x: w * 0.41, y: h))
                bolt.addLine(to: CGPoint(x: w * 0.71, y: h * 0.64))
                bolt.addLine(to: CGPoint(x: w * 0.54, y: h * 0.66)); bolt.closeSubpath()
                c.fill(bolt, with: .color(ArcadePalette.gold))
            } else {
                var shape = Path()
                for i in 0..<16 {
                    let angle = Double(i) * .pi / 8 + rotation * .pi / 180
                    let radius = i.isMultiple(of: 2) ? w * 0.47 : w * 0.29
                    let point = CGPoint(x: w / 2 + CGFloat(cos(angle)) * radius,
                                        y: h / 2 + CGFloat(sin(angle)) * radius)
                    if i == 0 { shape.move(to: point) } else { shape.addLine(to: point) }
                }
                shape.closeSubpath()
                c.fill(shape, with: .color(ArcadePalette.coral))
                c.fill(Path(ellipseIn: CGRect(x: w * 0.23, y: h * 0.23, width: w * 0.54, height: h * 0.54)),
                       with: .color(Color(red: 0.97, green: 0.65, blue: 0.44)))
                for x in [w * 0.39, w * 0.61] {
                    c.fill(Path(ellipseIn: CGRect(x: x - 2, y: h * 0.40, width: 4, height: 5)),
                           with: .color(ArcadePalette.ink))
                }
            }
        }
    }
}

struct ArcadeGameCover: View {
    let pet: PetProfile
    let game: MiniGameKind

    var body: some View {
        ZStack {
            switch game {
            case .petsDash:
                PetsDashTrack(progress: 0.14)
                PetsDashPlayerArtwork(pet: pet, frame: 0)
                    .frame(width: 69, height: 69).offset(y: 22)
            case .skyPaws:
                ArcadeSky(travel: 80)
                SkyPawsPlayerArtwork(pet: pet, frame: 0)
                    .frame(width: 88, height: 66).rotationEffect(.degrees(-8)).offset(y: 4)
            case .skyHop:
                ArcadeSky(vertical: true)
                ArcadePlatformArtwork(fragile: false).frame(width: 55, height: 22).offset(x: 7, y: 36)
                ArcadePlatformArtwork(fragile: true).frame(width: 35, height: 16).offset(x: -28, y: -35)
                PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                           breed: pet.resolvedBreed, pose: .jump, animatesMotion: false)
                    .frame(width: 77, height: 67).offset(x: 5, y: -3)
            }
        }
        .frame(width: 100, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityHidden(true)
    }
}
