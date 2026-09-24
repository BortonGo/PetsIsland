import SwiftUI
import UIKit

extension PetActivityAppearance {
    var backgroundColor: Color {
        Color(.sRGB, red: background.red, green: background.green, blue: background.blue, opacity: 1)
    }

    var foregroundColor: Color { usesDarkText ? .black : .white }
}

private struct PetMinimizeMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var petMinimizeMotion: Bool {
        get { self[PetMinimizeMotionKey.self] }
        set { self[PetMinimizeMotionKey.self] = newValue }
    }
}

/// The system accessibility preference is read-only. Combine it with the
/// app setting without overriding the user's system preference.
@propertyWrapper
struct PetReduceMotion: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var systemValue
    @Environment(\.petMinimizeMotion) private var appValue
    var wrappedValue: Bool { systemValue || appValue }
}

extension PetSpecies {
    var displayName: LocalizedStringKey {
        switch self {
        case .cat: "Cat"
        case .dog: "Dog"
        case .fox: "Fox"
        case .parrot: "Parrot"
        case .penguin: "Penguin"
        case .lion: "Lion"
        }
    }

    var personalityName: LocalizedStringKey {
        switch self {
        case .cat, .parrot: "curious"
        case .dog, .penguin: "playful"
        case .fox, .lion: "calm"
        }
    }
}

extension PetCoat {
    var displayName: LocalizedStringKey {
        switch self {
        case .sunrise: "Sunrise"
        case .cloud: "Cloud"
        case .midnight: "Midnight"
        }
    }
}

extension PetBreed {
    var displayName: LocalizedStringKey {
        switch self {
        case .shepherd: "Shepherd"
        case .corgi: "Corgi"
        case .cardigan: "Cardigan Welsh corgi"
        case .doberman: "Doberman"
        case .bullTerrier: "Bull terrier"
        case .classicCat: "Classic cat"
        case .britishShorthair: "British shorthair"
        case .maineCoon: "Maine coon"
        case .siamese: "Siamese"
        case .redFox: "Red fox"
        case .arcticFox: "Arctic fox"
        case .classicParrot: "Classic parrot"
        case .cockatiel: "Cockatiel"
        case .budgie: "Budgie"
        case .macaw: "Macaw"
        case .classicPenguin: "Classic penguin"
        case .rockhopper: "Rockhopper"
        case .adultLion: "Adult lion"
        case .lioness: "Lioness"
        case .lionCub: "Lion cub"
        }
    }
}

struct PetColors: Equatable {
    let primary: Color
    let secondary: Color
    let detail: Color

    static func resolve(
        species: PetSpecies,
        coat: PetCoat,
        customColor: PetColorSelection? = nil
    ) -> PetColors {
        if let customColor {
            let luminance = 0.2126 * customColor.red + 0.7152 * customColor.green + 0.0722 * customColor.blue
            return PetColors(
                primary: Color(red: customColor.red, green: customColor.green, blue: customColor.blue),
                secondary: Color(
                    red: customColor.red + (1 - customColor.red) * 0.48,
                    green: customColor.green + (1 - customColor.green) * 0.48,
                    blue: customColor.blue + (1 - customColor.blue) * 0.48
                ),
                detail: luminance < 0.2 ? Color(red: 0.9, green: 0.94, blue: 1) : Color(red: 0.08, green: 0.09, blue: 0.14)
            )
        }

        return switch (species, coat) {
        case (.cat, .sunrise): PetColors(primary: Color(red: 0.96, green: 0.48, blue: 0.22), secondary: .white, detail: Color(red: 0.26, green: 0.12, blue: 0.1))
        case (.cat, .cloud): PetColors(primary: Color(red: 0.65, green: 0.7, blue: 0.8), secondary: .white, detail: Color(red: 0.14, green: 0.16, blue: 0.23))
        case (.cat, .midnight): PetColors(primary: Color(red: 0.13, green: 0.15, blue: 0.24), secondary: Color(red: 0.58, green: 0.86, blue: 0.96), detail: .white)
        case (.dog, .sunrise): PetColors(primary: Color(red: 0.66, green: 0.4, blue: 0.22), secondary: Color(red: 0.94, green: 0.74, blue: 0.48), detail: Color(red: 0.2, green: 0.12, blue: 0.08))
        case (.dog, .cloud): PetColors(primary: Color(red: 0.88, green: 0.82, blue: 0.72), secondary: .white, detail: Color(red: 0.25, green: 0.19, blue: 0.15))
        case (.dog, .midnight): PetColors(primary: Color(red: 0.15, green: 0.13, blue: 0.17), secondary: Color(red: 0.74, green: 0.5, blue: 0.32), detail: .white)
        case (.fox, .sunrise): PetColors(primary: Color(red: 0.94, green: 0.32, blue: 0.12), secondary: Color(red: 1, green: 0.89, blue: 0.75), detail: Color(red: 0.25, green: 0.09, blue: 0.05))
        case (.fox, .cloud): PetColors(primary: Color(red: 0.66, green: 0.63, blue: 0.69), secondary: .white, detail: Color(red: 0.18, green: 0.15, blue: 0.21))
        case (.fox, .midnight): PetColors(primary: Color(red: 0.17, green: 0.2, blue: 0.3), secondary: Color(red: 0.68, green: 0.77, blue: 0.95), detail: .white)
        case (.parrot, .sunrise): PetColors(primary: Color(red: 0.12, green: 0.69, blue: 0.4), secondary: Color(red: 0.99, green: 0.76, blue: 0.14), detail: Color(red: 0.05, green: 0.17, blue: 0.12))
        case (.parrot, .cloud): PetColors(primary: Color(red: 0.2, green: 0.61, blue: 0.88), secondary: Color(red: 0.88, green: 0.96, blue: 1), detail: Color(red: 0.05, green: 0.16, blue: 0.29))
        case (.parrot, .midnight): PetColors(primary: Color(red: 0.26, green: 0.17, blue: 0.5), secondary: Color(red: 0.96, green: 0.39, blue: 0.6), detail: .white)
        case (.penguin, .sunrise): PetColors(primary: Color(red: 0.08, green: 0.14, blue: 0.22), secondary: .white, detail: Color(red: 0.08, green: 0.1, blue: 0.15))
        case (.penguin, .cloud): PetColors(primary: Color(red: 0.2, green: 0.39, blue: 0.56), secondary: Color(red: 0.9, green: 0.97, blue: 1), detail: Color(red: 0.05, green: 0.14, blue: 0.24))
        case (.penguin, .midnight): PetColors(primary: Color(red: 0.08, green: 0.07, blue: 0.13), secondary: Color(red: 0.72, green: 0.78, blue: 0.96), detail: .white)
        case (.lion, .sunrise): PetColors(primary: Color(red: 0.83, green: 0.53, blue: 0.24), secondary: Color(red: 0.98, green: 0.82, blue: 0.54), detail: Color(red: 0.31, green: 0.16, blue: 0.09))
        case (.lion, .cloud): PetColors(primary: Color(red: 0.78, green: 0.74, blue: 0.68), secondary: .white, detail: Color(red: 0.27, green: 0.23, blue: 0.20))
        case (.lion, .midnight): PetColors(primary: Color(red: 0.23, green: 0.19, blue: 0.24), secondary: Color(red: 0.67, green: 0.59, blue: 0.47), detail: .white)
        }
    }
}

/// A deterministic frame sequence used by foreground pet renderers.
///
/// The clip owns its playback cadence, so adding more intermediate frames does
/// not require changes to the playroom or habitat simulations. WidgetKit and
/// ActivityKit continue to advance only when the system supplies a new state.
struct PetAnimationClip: Equatable, Sendable {
    let frames: [String]
    let frameDuration: TimeInterval
    private let frameDurations: [TimeInterval]?

    /// Foreground SwiftUI timelines may sample slightly faster than the
    /// quickest clip. Individual clips still decide when their frame changes.
    static let foregroundRefreshInterval: TimeInterval = 1.0 / 30.0

    init(frames: [String], frameDuration: TimeInterval) {
        precondition(!frames.isEmpty, "A pet animation clip requires at least one frame")
        precondition(
            frameDuration.isFinite && frameDuration > 0,
            "A pet animation clip requires a positive finite frame duration"
        )
        self.frames = frames
        self.frameDuration = frameDuration
        self.frameDurations = nil
    }

    init(frames: [String], frameDurations: [TimeInterval]) {
        precondition(!frames.isEmpty && frames.count == frameDurations.count)
        precondition(frameDurations.allSatisfy { $0.isFinite && $0 > 0 })
        self.frames = frames
        self.frameDuration = frameDurations[0]
        self.frameDurations = frameDurations
    }

    var cycleDuration: TimeInterval {
        frameDurations?.reduce(0, +) ?? frameDuration * Double(frames.count)
    }

    /// Returns a stable, looping frame index without allowing a long-running
    /// animation clock to overflow `Int`.
    func frameIndex(at elapsedTime: TimeInterval, phaseOffset: Int = 0) -> Int {
        guard frames.count > 1, elapsedTime.isFinite else { return 0 }

        let remainder = elapsedTime.truncatingRemainder(dividingBy: cycleDuration)
        let cycleTime = remainder >= 0 ? remainder : remainder + cycleDuration
        let timeIndex: Int
        if let frameDurations {
            var end: TimeInterval = 0
            timeIndex = frameDurations.firstIndex { duration in
                end += duration
                return cycleTime < end
            } ?? frames.count - 1
        } else {
            timeIndex = Int(floor(cycleTime / frameDuration))
        }
        let normalizedTimeIndex = positiveModulo(timeIndex, frames.count)
        let normalizedPhase = positiveModulo(phaseOffset, frames.count)
        return positiveModulo(normalizedTimeIndex + normalizedPhase, frames.count)
    }

    func frameName(at elapsedTime: TimeInterval, phaseOffset: Int = 0) -> String {
        frames[frameIndex(at: elapsedTime, phaseOffset: phaseOffset)]
    }

    func frameName(forStep step: Int) -> String {
        frames[positiveModulo(step, frames.count)]
    }

    /// A planted foot advances with travel, so stopping cannot leave the pet
    /// running in place and a slow walk cannot play a fast gallop cycle.
    func frameIndex(distance: Double, strideLength: Double, phaseOffset: Int = 0) -> Int {
        guard distance.isFinite, strideLength.isFinite, strideLength > 0 else { return 0 }
        let cycles = distance / strideLength
        return frameIndex(at: cycles.truncatingRemainder(dividingBy: 1) * cycleDuration,
                          phaseOffset: phaseOffset)
    }

    /// A full pair of steps covers a small part of the sprite canvas. Using
    /// nearly a whole canvas per cycle left each paw frozen while the pet slid.
    func travelFrameIndex(distance: Double, canvasWidth: Double, pose: PetPose, phaseOffset: Int = 0) -> Int {
        frameIndex(distance: distance,
                   strideLength: canvasWidth * (pose == .run ? 0.26 : 0.18),
                   phaseOffset: phaseOffset)
    }

    private func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

struct PetArtwork: View {
    let species: PetSpecies
    var coat: PetCoat = .sunrise
    var customColor: PetColorSelection? = nil
    var breed: PetBreed? = nil
    let pose: PetPose
    var direction: PetDirection = .right
    var step = 0
    var animatesMotion = true
    var usesNaturalGait = false

    @PetReduceMotion private var reduceMotion

    var body: some View {
        if animatesMotion {
            baseArtwork
                .phaseAnimator([false, true, false], trigger: step) { content, lifted in
                    content.offset(y: motionOffset(lifted: lifted && !reduceMotion))
                } animation: { _ in
                    reduceMotion ? .linear(duration: 0) : .easeInOut(duration: 0.38)
                }
        } else {
            baseArtwork
        }
    }

    private var baseArtwork: some View {
        ImportedPetSprite(
            species: species,
            coat: coat,
            customColor: customColor,
            breed: breed,
            pose: pose,
            step: step,
            usesNaturalGait: usesNaturalGait
        )
        .scaleEffect(x: direction == .right ? 1 : -1, y: 1)
        // Sprite frames and facing are discrete. Interpolating their layout
        // produces sliding paws and a sideways squash at every turn.
        .transaction { $0.animation = nil }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func motionOffset(lifted: Bool) -> CGFloat {
        if pose == .jump && !reduceMotion { return lifted ? -14 : -4 }
        if species == .parrot && pose == .fly { return lifted ? -13 : -5 }
        return 0
    }
}

/// Frame-based sprites shared by the app, widget and Live Activity. Approved
/// Pet Island sheets use original six-pose artwork; legacy frames remain as a
/// temporary fallback for species that have not received a new sheet yet.
private struct ImportedPetSprite: View {
    let species: PetSpecies
    let coat: PetCoat
    let customColor: PetColorSelection?
    let breed: PetBreed?
    let pose: PetPose
    let step: Int
    var usesNaturalGait = false

    var body: some View {
        let clip = usesNaturalGait
            ? PetAnimationLibrary.naturalClip(for: species, breed: breed, pose: pose)
            : PetAnimationLibrary.clip(for: species, breed: breed, pose: pose)
        let assetName = clip.frameName(forStep: step)
        let image = GroundedPetImage(assetName: assetName, usesNaturalGait: usesNaturalGait)
        image.petCoat(species: species, coat: coat, customColor: customColor)
    }
}

/// Uses the original pixels with a shared 220 × 176 canvas and ground at 160.
/// No per-frame fit-to-bounds scaling: changing the stance must not resize the
/// animal. Old square shepherd frames are adapted to the same coordinate space.
struct PetSpriteGeometry {
    let sourceSize: CGSize
    let visibleBounds: CGRect
    let scale: CGFloat
    let horizontalAnchor: CGFloat
    let preservesAuthoredBaseline: Bool

    static let canvas = CGSize(width: 220, height: 176)
    static let baseline: CGFloat = 160

    init(sourceSize: CGSize, visibleBounds: CGRect, assetName: String) {
        self.sourceSize = sourceSize
        preservesAuthoredBaseline = assetName.hasPrefix("fluid_") || assetName.hasPrefix("companion_")
        self.visibleBounds = visibleBounds
        horizontalAnchor = sourceSize == Self.canvas || preservesAuthoredBaseline
            ? sourceSize.width / 2
            : (assetName.contains("_lie_") ? 161.5 : 203.5)
        if assetName.hasPrefix("sprite_dog_") {
            scale = assetName.contains("_lie_")
                ? 180 / 259
                : 148 / 273
        } else {
            scale = 1
        }
    }

    func rect(in size: CGSize) -> CGRect {
        let fit = min(size.width / Self.canvas.width, size.height / Self.canvas.height)
        let origin = CGPoint(x: (size.width - Self.canvas.width * fit) / 2,
                             y: (size.height - Self.canvas.height * fit) / 2)
        // Retain the authored horizontal registration for original sheets.
        return CGRect(x: origin.x + (Self.canvas.width / 2 - horizontalAnchor * scale) * fit,
                      y: origin.y + (preservesAuthoredBaseline ? 0 : Self.baseline - visibleBounds.maxY * scale) * fit,
                      width: sourceSize.width * scale * fit,
                      height: sourceSize.height * scale * fit)
    }

    static func load(assetName: String) -> PetSpriteGeometry? {
        if let cached = cache.object(forKey: assetName as NSString) { return cached.geometry }
        guard let cgImage = UIImage(named: assetName)?.cgImage else { return nil }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else { return nil }
        var left = width, right = 0, top = height, bottom = 0
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
                left = min(left, x); right = max(right, x + 1)
                top = min(top, y); bottom = max(bottom, y + 1)
            }
        }
        guard right > left, bottom > top else { return nil }
        let geometry = PetSpriteGeometry(
            sourceSize: CGSize(width: width, height: height),
            visibleBounds: CGRect(x: left, y: top, width: right - left, height: bottom - top),
            assetName: assetName
        )
        cache.setObject(CachedGeometry(geometry), forKey: assetName as NSString)
        return geometry
    }

    private final class CachedGeometry: NSObject {
        let geometry: PetSpriteGeometry
        init(_ geometry: PetSpriteGeometry) { self.geometry = geometry }
    }
    private static let cache = NSCache<NSString, CachedGeometry>()
}

/// Font glyphs and PNGs share the same canvas, including transparent margins.
/// Timer font ascenders are generated at 176/220 em with zero descent.
struct PetTimerSpriteLayout {
    let canvasSize: CGSize

    init(viewport: CGSize) {
        let fit = min(viewport.width / PetSpriteGeometry.canvas.width,
                      viewport.height / PetSpriteGeometry.canvas.height)
        canvasSize = CGSize(width: PetSpriteGeometry.canvas.width * fit,
                            height: PetSpriteGeometry.canvas.height * fit)
    }

    var fontSize: CGFloat { canvasSize.width }
}

/// Clip from the trailing edge instead of offsetting a guessed number of
/// characters. This keeps the final timer glyph fixed across minute/hour rolls.
struct PetTimerGlyph: View {
    let timerStart: Date
    let timerEnd: Date
    let fontName: String
    let viewport: CGSize
    var direction: PetDirection = .right

    var body: some View {
        let validEnd = max(timerEnd.addingTimeInterval(24 * 60 * 60),
                           timerStart.addingTimeInterval(1))
        PetTimerGlyphViewport(
            text: Text(timerInterval: timerStart...validEnd, countsDown: false, showsHours: true),
            fontName: fontName, viewport: viewport, direction: direction
        )
    }
}

struct PetTimerGlyphViewport: View {
    let text: Text
    let fontName: String
    let viewport: CGSize
    var direction: PetDirection = .right

    var body: some View {
        let layout = PetTimerSpriteLayout(viewport: viewport)
        text
            .font(.custom(fontName, fixedSize: layout.fontSize))
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .unredacted()
            .lineLimit(1)
            .multilineTextAlignment(.trailing)
            // Archived system timers need an explicit proposed width. Their
            // live text can grow beyond the intrinsic size captured at launch.
            .frame(width: layout.fontSize * 12, height: layout.canvasSize.height, alignment: .trailing)
            .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .trailing)
            .clipped()
            .scaleEffect(x: direction == .right ? 1 : -1, y: 1)
            .frame(width: viewport.width, height: viewport.height)
            .contentTransition(.identity)
            .transaction { $0.animation = nil }
    }
}

private struct GroundedPetImage: View {
    let assetName: String
    var usesNaturalGait = false

    var body: some View {
        GeometryReader { proxy in
            // Foreground gait sheets have a fixed 12px gutter on both sides.
            // Give extended paws drawing space without moving or scaling the
            // original 220px character coordinate system between poses.
            let gutter = usesNaturalGait ? 12 * min(proxy.size.width / 220, proxy.size.height / 176) : 0
            Canvas { context, _ in
                let rect = PetSpriteGeometry.load(assetName: assetName)?.rect(in: proxy.size)
                    ?? CGRect(origin: .zero, size: proxy.size)
                context.draw(Image(assetName).interpolation(.none), in: rect.offsetBy(dx: gutter, dy: 0))
            }
            .frame(width: proxy.size.width + gutter * 2, height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

extension View {
    func petCoat(species: PetSpecies, coat: PetCoat, customColor: PetColorSelection?) -> some View {
        modifier(PetCoatModifier(species: species, coat: coat, customColor: customColor))
    }
}

private struct PetCoatModifier: ViewModifier {
    let species: PetSpecies
    let coat: PetCoat
    let customColor: PetColorSelection?

    func body(content: Content) -> some View {
        let treatment = SpriteColorTreatment(species: species, coat: coat, customColor: customColor)
        content.saturation(treatment.saturation)
            .brightness(treatment.brightness)
            .contrast(treatment.contrast)
            .overlay {
                if let tint = treatment.tint {
                    tint.opacity(treatment.tintOpacity).blendMode(.sourceAtop)
                }
            }
            .compositingGroup()
    }
}

/// Keeps the hand-drawn light and shadow pixels intact while making each coat
/// visibly different. A custom color has priority over the three presets.
private struct SpriteColorTreatment {
    let saturation: Double
    let brightness: Double
    let contrast: Double
    let tint: Color?
    let tintOpacity: Double

    init(species: PetSpecies, coat: PetCoat, customColor: PetColorSelection?) {
        if let customColor {
            let luminance = 0.2126 * customColor.red
                + 0.7152 * customColor.green
                + 0.0722 * customColor.blue
            saturation = 0.92
            brightness = luminance < 0.12 ? 0.06 : 0
            contrast = luminance < 0.12 ? 1.08 : 1
            tint = Color(
                red: customColor.red,
                green: customColor.green,
                blue: customColor.blue
            )
            tintOpacity = 0.62
            return
        }

        let palette = PetColors.resolve(species: species, coat: coat)
        switch coat {
        case .sunrise:
            saturation = 1
            brightness = 0
            contrast = 1
            tint = nil
            tintOpacity = 0
        case .cloud:
            saturation = 0.34
            brightness = 0.12
            contrast = 0.94
            tint = palette.primary
            tintOpacity = 0.22
        case .midnight:
            saturation = 0.58
            brightness = -0.12
            contrast = 1.12
            tint = palette.primary
            tintOpacity = 0.4
        }
    }
}

enum PetAnimationLibrary {
    static func naturalClip(for species: PetSpecies, breed: PetBreed?, pose: PetPose) -> PetAnimationClip {
        if let clip = companionClip(for: species, breed: breed, pose: pose) { return clip }
        if pose == .walk || pose == .run {
            let token: String? = switch breed ?? PetBreed.defaultVariant(for: species) {
            case .shepherd: "dog_shepherd"
            case .maineCoon: "cat_maine_coon"
            case .corgi: "dog_corgi"
            case .doberman: "dog_doberman"
            case .bullTerrier: "dog_bull_terrier"
            case .classicCat: "cat"
            case .britishShorthair: "cat_british"
            case .siamese: "cat_siamese"
            case .redFox: "fox"
            case .arcticFox: "fox_arctic"
            case .classicPenguin: "penguin"
            case .rockhopper: "penguin_rockhopper"
            default: nil
            }
            if let token {
                return PetAnimationClip(frames: (0..<8).map { "fluid_\(token)_\(pose.rawValue)_\($0)" },
                                        frameDuration: pose == .run ? 0.08 : 0.11)
            }
        }
        return clip(for: species, breed: breed, pose: pose)
    }

    static func clip(
        for species: PetSpecies,
        breed: PetBreed?,
        pose: PetPose
    ) -> PetAnimationClip {
        if let clip = companionClip(for: species, breed: breed, pose: pose) { return clip }
        let frames: [String]
        if species == .dog,
           let dogFrames = originalDogBreedFrames(for: breed ?? .shepherd, pose: pose) {
            frames = dogFrames
        } else if let originalFrames = originalPetIslandFrames(
            for: species,
            variant: breed,
            pose: pose
        ) {
            frames = originalFrames
        } else {
            let state = state(for: species, pose: pose)
            let count = frameCount(for: species, state: state)
            frames = (0..<count).map { "sprite_\(species.rawValue)_\(state)_\($0)" }
        }

        return PetAnimationClip(frames: frames, frameDuration: frameDuration(for: pose))
    }

    private static func companionClip(for species: PetSpecies, breed: PetBreed?, pose: PetPose) -> PetAnimationClip? {
        let variants = PetBreed.available(for: species)
        let variant = breed.flatMap { variants.contains($0) ? $0 : nil } ?? variants.first
        guard let token = variant?.companionArtworkToken else { return nil }
        let state: String
        let durations: [TimeInterval]
        switch pose {
        case .walk: state = "walk"; durations = Array(repeating: 0.11, count: 8)
        case .run: state = "run"; durations = Array(repeating: 0.08, count: 8)
        case .idle: state = "idle"; durations = [1.8, 0.14]
        case .jump, .fly: state = "jump"; durations = [0.18, 0.22]
        case .play, .eat: state = "play"; durations = [0.24, 0.24]
        case .sleep: state = "sleep"; durations = [0.8, 0.8]
        }
        let frames = durations.indices.map { "companion_\(token)_\(state)_\(String(format: "%02d", $0))" }
        return PetAnimationClip(frames: frames, frameDurations: durations)
    }

    /// Movement clips are intentionally quicker than expressive or resting
    /// poses. Existing two-frame walks still loop correctly; approved 6–8
    /// frame sequences can replace their arrays later without renderer changes.
    private static func frameDuration(for pose: PetPose) -> TimeInterval {
        switch pose {
        case .run: 0.09
        case .walk: 0.13
        case .fly: 0.11
        case .jump: 0.14
        case .play, .eat: 0.17
        case .idle: 0.36
        case .sleep: 0.68
        }
    }

    /// Every selectable dog breed has a dedicated two-frame gallop. Slower
    /// movement and expressive poses continue to use the original breed art.
    private static func originalDogBreedFrames(
        for breed: PetBreed,
        pose: PetPose
    ) -> [String]? {
        if pose == .run {
            let token: String
            switch breed {
            case .shepherd:
                token = "shepherd"
            case .corgi:
                token = "corgi"
            case .doberman:
                token = "doberman"
            case .bullTerrier:
                token = "bull_terrier"
            case .cardigan, .adultLion, .lioness, .lionCub,
                 .classicCat, .britishShorthair, .maineCoon, .siamese,
                 .redFox, .arcticFox, .classicParrot, .cockatiel, .budgie,
                 .macaw, .classicPenguin, .rockhopper:
                return nil
            }
            let prefix = "island_dog_\(token)_run_"
            return [prefix + "0", prefix + "1"]
        }

        let token: String
        switch breed {
        case .shepherd:
            if pose == .walk {
                return ["island_dog_shepherd_walk_0", "island_dog_shepherd_walk_1"]
            }
            if pose == .jump {
                // The first gallop frame is the shepherd's clear airborne pose.
                // Reuse it here so pet pickers do not fall back to standing art.
                return ["island_dog_shepherd_run_0"]
            }
            return nil
        case .corgi:
            token = "corgi"
        case .doberman:
            token = "doberman"
        case .bullTerrier:
            token = "bull_terrier"
        case .cardigan, .adultLion, .lioness, .lionCub,
             .classicCat, .britishShorthair, .maineCoon, .siamese,
             .redFox, .arcticFox, .classicParrot, .cockatiel, .budgie,
             .macaw, .classicPenguin, .rockhopper:
            return nil
        }

        let prefix = "island_dog_\(token)_"
        return sixPoseFrames(prefix: prefix, pose: pose)
    }

    private static func sixPoseFrames(prefix: String, pose: PetPose) -> [String] {
        switch pose {
        case .idle:
            [prefix + "idle"]
        case .walk:
            [prefix + "walk_0", prefix + "walk_1"]
        case .run:
            [prefix + "walk_0", prefix + "idle", prefix + "walk_1", prefix + "idle"]
        case .jump, .fly:
            [prefix + "jump"]
        case .play, .eat:
            [prefix + "play"]
        case .sleep:
            [prefix + "sleep"]
        }
    }

    private static func originalPetIslandFrames(
        for species: PetSpecies,
        variant: PetBreed?,
        pose: PetPose
    ) -> [String]? {
        guard species == .cat || species == .fox || species == .parrot || species == .penguin else {
            return nil
        }

        let prefix = originalVariantPrefix(for: species, variant: variant)
        if species == .parrot, pose == .fly || pose == .walk || pose == .run {
            let flightToken = switch variant ?? .classicParrot {
            case .cockatiel: "cockatiel"
            case .budgie: "budgie"
            case .macaw: "macaw"
            default: "classic"
            }
            return (0..<8).map {
                "island_parrot_\(flightToken)_fly_\(String(format: "%02d", $0))"
            }
        }

        return switch pose {
        case .idle:
            [prefix + "idle"]
        case .walk:
            [prefix + "walk_0", prefix + "walk_1"]
        case .run:
            species == .parrot
                ? [prefix + "walk_1", prefix + "jump", prefix + "walk_0", prefix + "jump"]
                : [prefix + "run_0", prefix + "run_1"]
        case .jump:
            species == .cat && variant == .maineCoon
                ? [prefix + "run_0"]
                : [prefix + "jump"]
        case .fly:
            species == .parrot
                ? [prefix + "walk_1", prefix + "jump", prefix + "walk_0", prefix + "jump"]
                : [prefix + "jump"]
        case .play, .eat:
            [prefix + "play"]
        case .sleep:
            [prefix + "sleep"]
        }
    }

    private static func originalVariantPrefix(
        for species: PetSpecies,
        variant: PetBreed?
    ) -> String {
        switch (species, variant) {
        case (.cat, .some(.britishShorthair)): "island_cat_british_"
        case (.cat, .some(.maineCoon)): "island_cat_maine_coon_"
        case (.cat, .some(.siamese)): "island_cat_siamese_"
        case (.fox, .some(.arcticFox)): "island_fox_arctic_"
        case (.parrot, .some(.cockatiel)): "island_parrot_cockatiel_"
        case (.parrot, .some(.budgie)): "island_parrot_budgie_"
        case (.parrot, .some(.macaw)): "island_parrot_macaw_"
        case (.penguin, .some(.rockhopper)): "island_penguin_rockhopper_"
        default: "island_\(species.rawValue)_"
        }
    }

    private static func state(for species: PetSpecies, pose: PetPose) -> String {
        if species == .cat || species == .penguin {
            return "idle"
        }

        switch pose {
        case .idle: return "idle"
        case .walk: return "walk"
        case .run, .jump, .fly: return "run"
        case .play: return "swipe"
        case .eat: return "with_ball"
        case .sleep:
            return species == .dog ? "lie" : "idle"
        }
    }

    private static func frameCount(for species: PetSpecies, state: String) -> Int {
        return switch (species, state) {
        case (.dog, "idle"): 4
        case (.dog, "walk"): 3
        case (.dog, "run"): 6
        case (.dog, "swipe"): 3
        case (.dog, "with_ball"): 4
        case (.dog, "lie"): 3
        case (.fox, "idle"): 5
        case (.fox, "walk"): 8
        case (.fox, "run"): 6
        case (.fox, "swipe"): 11
        case (.fox, "with_ball"): 5
        case (.parrot, "idle"): 6
        case (.parrot, "walk"): 4
        case (.parrot, "run"): 4
        case (.parrot, "swipe"): 4
        case (.parrot, "with_ball"): 2
        case (.cat, "idle"), (.penguin, "idle"): 1
        default: 1
        }
    }
}

/// Compatibility wrapper for larger app surfaces. It intentionally shares the
/// exact same sprite source as widgets and Dynamic Island, so a pet keeps one
/// recognizable visual identity everywhere.
struct PetPortraitArtwork: View {
    let species: PetSpecies
    var coat: PetCoat = .sunrise
    var customColor: PetColorSelection? = nil
    var breed: PetBreed? = nil
    let pose: PetPose
    var direction: PetDirection = .right
    var step = 0

    var body: some View {
        PetArtwork(
            species: species,
            coat: coat,
            customColor: customColor,
            breed: breed,
            pose: pose,
            direction: direction,
            step: step
        )
    }
}

private struct PixelPetCanvas: View {
    let rows: [String]
    let palette: PetColors
    let accent: Color
    let pose: PetPose
    let step: Int

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let rowCount = max(rows.count, 1)
            let columnCount = max(rows.map(\.count).max() ?? 1, 1)
            let pixel = max(floor(min(size.width / CGFloat(columnCount), size.height / CGFloat(rowCount))), 1)
            let spriteWidth = CGFloat(columnCount) * pixel
            let spriteHeight = CGFloat(rowCount) * pixel
            let origin = CGPoint(x: floor((size.width - spriteWidth) / 2), y: floor((size.height - spriteHeight) / 2))

            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, ink) in row.enumerated() where ink != "." {
                    let wingLift: CGFloat = ink == "F" && pose == .fly
                        ? (step.isMultiple(of: 2) ? -pixel : pixel)
                        : 0
                    let rect = CGRect(
                        x: origin.x + CGFloat(columnIndex) * pixel,
                        y: origin.y + CGFloat(rowIndex) * pixel + wingLift,
                        width: pixel,
                        height: pixel
                    )

                    if ink == "E" {
                        drawEye(context: &context, rect: rect, sleeping: pose == .sleep, color: palette.detail)
                    } else if let color = color(for: ink) {
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }

            drawPoseEffect(context: &context, origin: origin, pixel: pixel, columns: columnCount)
        }
    }

    private func color(for ink: Character) -> Color? {
        switch ink {
        case "P": palette.primary
        case "S": palette.secondary
        case "D": palette.detail
        case "W": .white
        case "A": accent
        case "R": Color(red: 1, green: 0.48, blue: 0.56)
        case "F": palette.secondary
        default: nil
        }
    }

    private func drawEye(
        context: inout GraphicsContext,
        rect: CGRect,
        sleeping: Bool,
        color: Color
    ) {
        if sleeping {
            let line = CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: max(rect.height * 0.3, 1))
            context.fill(Path(line), with: .color(color))
        } else {
            context.fill(Path(rect), with: .color(color))
            let highlight = CGRect(
                x: rect.minX + rect.width * 0.14,
                y: rect.minY + rect.height * 0.12,
                width: max(rect.width * 0.32, 1),
                height: max(rect.height * 0.32, 1)
            )
            context.fill(Path(highlight), with: .color(.white))
        }
    }

    private func drawPoseEffect(
        context: inout GraphicsContext,
        origin: CGPoint,
        pixel: CGFloat,
        columns: Int
    ) {
        let right = origin.x + CGFloat(columns - 2) * pixel

        if pose == .play || pose == .jump {
            for (x, y) in [(right, origin.y + pixel), (right + pixel, origin.y), (right + pixel, origin.y + pixel * 2)] {
                context.fill(Path(CGRect(x: x, y: y, width: pixel, height: pixel)), with: .color(.yellow))
            }
        }

        if pose == .eat {
            let carrot = CGRect(x: right, y: origin.y + pixel * 9, width: pixel * 2, height: pixel * 4)
            context.fill(Path(carrot), with: .color(.orange))
            context.fill(
                Path(CGRect(x: right, y: origin.y + pixel * 8, width: pixel * 2, height: pixel)),
                with: .color(.green)
            )
        }

        if pose == .sleep {
            for index in 0..<3 {
                let x = right - CGFloat(index) * pixel
                let y = origin.y + CGFloat(3 - index) * pixel
                context.fill(Path(CGRect(x: x, y: y, width: pixel, height: pixel)), with: .color(palette.secondary))
            }
        }
    }
}

private enum PixelPetLibrary {
    static func rows(for species: PetSpecies) -> [String] {
        switch species {
        case .cat, .lion: cat
        case .dog: dog
        case .fox: fox
        case .parrot: parrot
        case .penguin: penguin
        }
    }

    static func accent(for species: PetSpecies) -> Color {
        switch species {
        case .parrot, .penguin: Color(red: 1, green: 0.66, blue: 0.12)
        case .cat, .dog, .fox, .lion: Color(red: 1, green: 0.48, blue: 0.55)
        }
    }

    private static func sprite(_ value: String) -> [String] {
        value.split(separator: "\n").map(String.init)
    }

    private static let cat = sprite("""
    ....DD......DD......
    ...DPPD....DPPD.....
    ..DPPPPDDDDPPPPD....
    .DPPPPPPPPPPPPPPD...
    DPPPPPPPPPPPPPPPPD..
    DPPPPEPPPPPPEPPPPPD..
    DPPPPPPPRPPPPPPPPPD..
    .DPPPPPPDDDPPPPPPD...
    ..DPPPPPPPPPPPPPD....
    .DDDDPPPPPPPPPPD.....
    DPPPDPPPPPPPPPPPDD...
    DPPPDPPPPPPPPPPPPPD..
    .DDD.DPPPPPPPPPPPPD..
    .....DPPPPPPPPPPPD...
    ......DDPPDDPPDDD....
    .......DD..DD........
    """)

    private static let dog = sprite("""
    ..DDD..........DDD...
    .DPPPD........DPPPD..
    DPPPPDDDDDDDDDDPPPPD.
    DPPPPPPPPPPPPPPPPPPD.
    .DPPPPPPPPPPPPPPPPD..
    .DPPPPEPPPPPPEPPPPD..
    .DPPPPPPSSSPPPPPPPD..
    ..DPPPSSSDSASSSPPD...
    ...DPPPSSSSSPPPPD....
    ....DDPPPPPPPPDD.....
    ..DDDPPPPPPPPPPDDD...
    .DPPPPPPPPPPPPPPPPD..
    DPPPDPPPPPPPPPPDPPPD.
    .DDD.DPPPPPPPPPD.DDD.
    .....DDPPDDPPDDD......
    ......DD..DD..........
    """)

    private static let fox = sprite("""
    ....DD..........DD....
    ...DPPD........DPPD...
    ..DPPPPDDDDDDDDPPPPD..
    .DPPPPPPPPPPPPPPPPPD..
    DPPPPEPPPPPPPPEPPPPPD.
    DPPPPPPPPSSPPPPPPPPPD.
    .DPPPPPSSSASSPPPPPPD..
    ..DPPPSSDDDSSPPPPPD...
    ...DDPPPPPPPPPPPDD....
    .DDD.DPPPPPPPPPD.......
    DPPPDDPPPPPPPPPPDDD....
    DPPPPPPPPPPPPPPPPPPD...
    .DSSSSSPPPPPPPPPPPPD...
    ..DSSSDDPPPPPPPPDDD....
    ...DDD..DDPPDDPPD......
    .........DD..DD........
    """)

    private static let parrot = sprite("""
    ..........AA..........
    .........APPA.........
    ........DPPPPD........
    .......DPPPEPPDAA.....
    ..FFF.DPPPPSSSDAAA....
    .FFFFFPPPPPSSSDAA.....
    FFFFFFPPPPPPPPPD......
    .FFFFPPPPPPPPPD.......
    ..DPPPPPPPPPPD........
    ...DPPPPPPPPD.........
    AA..DPPPPPPD..........
    AAA..DPPPPD...........
    .AA...DPPD............
    ......D..D............
    """)

    private static let bear = sprite("""
    ...DDD........DDD.....
    ..DPPPD......DPPPD....
    ..DPPPPDDDDDDPPPPD....
    .DPPPPPPPPPPPPPPPPD...
    DPPPPEPPPPPPPPEPPPPD..
    DPPPPPPPPPPPPPPPPPPD..
    DPPPPPPSSSSPPPPPPPPD..
    .DPPPPSSSASSPPPPPPD...
    ..DPPPSSDDDSSPPPPD....
    ...DDPPPPPPPPPPDD.....
    ..DPPPPPPPPPPPPPPD....
    .DPPPPPPPPPPPPPPPPD...
    .DPPPDPPPPPPPPDPPPD...
    ..DDD.DPPPPPPPD.DDD...
    ......DDPPDDPPD.......
    .......DD..DD.........
    """)

    private static let penguin = sprite("""
    ......DDDDDDDD........
    ....DDPPPPPPPPDD......
    ...DPPPPPPPPPPPPD.....
    ..DPPPSSEPPESSPPPD....
    ..DPPSSSSSSSSSSPPD....
    .DPPPSSSSAASSSSPPPD...
    DPPPPPPPPPPPPPPPPPPD..
    DPPPPSSSSSSSSSSPPPPD..
    DPPPSSSSSSSSSSSSPPPD..
    .DPPSSSSSSSSSSSSPPD...
    ..DPPSSSSSSSSSSPPD....
    ...DPPSSSSSSSSPPD.....
    ....DDPPPPPPPPDD......
    .....DDAA..AADD.......
    ......DD..DD..........
    """)

    private static let lizard = sprite("""
    ............DDDDD.....
    ..........DDPPPPPD....
    .........DPPPPEPPD....
    ..DDDDDDDDPPPPPPPD....
    .DPPPPPPPPPPPPPPPD....
    DPPSSPSSPSSPPPPPPD....
    DPPPPPPPPPPPPPPPD.....
    .DPPPPPPPPPPPPPD......
    ..DDPPPPPPPPDDD.......
    DPPD.DPPDPPD.DPPD.....
    .DD...DD.DD...DD......
    ..DD..................
    .DPPD.................
    ..DDD.................
    """)

    private static let bunny = sprite("""
    .....DD....DD.........
    ....DPPD..DPPD........
    ....DPPD..DPPD........
    ....DPPD..DPPD........
    ...DPPPPDDPPPPD.......
    ..DPPPPPPPPPPPPD......
    .DPPPPEPPPPPEPPPD.....
    DPPPPPPPRPPPPPPPPD....
    DPPPPPPDDDPPPPPPPD....
    .DPPPPPPPPPPPPPPD.....
    ..DDPPPPPPPPPPDD......
    DD.DPPPPPPPPPPD.......
    DSDDPPPPPPPPPPDDD.....
    .DD.DPPPPPPPPDPPPD....
    .....DDPPDDPPD.DDD....
    ......DD..DD..........
    """)
}

struct PetHabitatView: View {
    let profile: PetProfile
    var companions: [PetProfile] = []
    let snapshot: PetSnapshot
    var animated = true

    @PetReduceMotion private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.7), Color.cyan.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: proxy.size.width * 0.7)
                    .offset(x: -proxy.size.width * 0.25, y: -proxy.size.height * 0.2)
                Capsule()
                    .fill(.black.opacity(0.22))
                    .frame(height: 8)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 28)
                HStack(alignment: .bottom, spacing: -18) {
                    ForEach(Array(([profile] + companions).prefix(3).enumerated()), id: \.element.id) { index, pet in
                        PetPortraitArtwork(
                            species: pet.species,
                            coat: pet.coat,
                            customColor: pet.customColor,
                            breed: pet.resolvedBreed,
                            pose: pet.species == .parrot && snapshot.pose == .walk ? .fly : snapshot.pose,
                            direction: index.isMultiple(of: 2) ? snapshot.direction : oppositeDirection(snapshot.direction),
                            step: snapshot.revision + index
                        )
                        .frame(
                            width: min(proxy.size.width * 0.31, 112),
                            height: min(proxy.size.height * 0.44, 102)
                        )
                        .offset(y: index.isMultiple(of: 2) ? 0 : 5)
                        .zIndex(Double(3 - index))
                    }
                }
                .offset(y: -30)
                .animation(animated && !reduceMotion ? .snappy(duration: 0.5) : nil, value: snapshot)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(profile.name) + Text(", ") + Text("virtual pet"))
    }
}

private func oppositeDirection(_ direction: PetDirection) -> PetDirection {
    direction == .right ? .left : .right
}
