import AppIntents
import SwiftUI
import WidgetKit

struct ThrowBallIntent: AppIntent {
    static let title: LocalizedStringResource = "Throw a ball"
    static let description = IntentDescription("Play fetch with your Pet Island dog.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try PetLifeStore.update { state in
            state.throwBall(at: .now)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: PetEnclosureWidget.kind)
        return .result()
    }
}

struct PetEnclosureEntry: TimelineEntry {
    let date: Date
    let state: PetLifeState
    let habitat: SharedPetHabitat
    let presentation: PetLifePresentation
    let petProjections: [HabitatPetProjection]
}

struct PetEnclosureProvider: TimelineProvider {
    func placeholder(in context: Context) -> PetEnclosureEntry {
        entry(for: .initial(), at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (PetEnclosureEntry) -> Void) {
        let state = context.isPreview ? PetLifeState.initial() : PetLifeStore.load()
        let habitat = context.isPreview ? SharedPetHabitat.initial() : PetHabitatStore.load()
        completion(entry(for: state, habitat: habitat, at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PetEnclosureEntry>) -> Void) {
        let state = PetLifeStore.load()
        let habitat = PetHabitatStore.load()
        let now = Date.now
        let dates = timelineDates(for: state, startingAt: now)
        let entries = dates.map { entry(for: state, habitat: habitat, at: $0) }
        completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(120))))
    }

    private func entry(for state: PetLifeState, habitat: SharedPetHabitat = .initial(), at date: Date) -> PetEnclosureEntry {
        let pets = habitat.residents.map(\.profile)
        var enclosureState = state
        enclosureState.placement = .enclosure
        return PetEnclosureEntry(
            date: date,
            state: state,
            habitat: habitat,
            presentation: PetLifeEngine.presentation(for: enclosureState, at: date),
            petProjections: PetHabitatEngine.projections(
                for: habitat.configuration,
                pets: pets,
                at: date
            )
        )
    }

    private func timelineDates(for state: PetLifeState, startingAt now: Date) -> [Date] {
        var dates = [now]

        // AppIntent-triggered fetch gets a handful of short-lived states. The
        // system may coalesce them, but each entry remains correct on its own.
        if let thrownAt = state.lastBallThrownAt {
            let age = now.timeIntervalSince(thrownAt)
            if age >= 0, age < PetLifeEngine.ballReactionDuration {
                for reactionTime in PetLifeEngine.ballReactionTimelineOffsets where reactionTime > age {
                    dates.append(now.addingTimeInterval(reactionTime - age))
                }
            }
        }

        let ambientStart = dates.last ?? now
        for step in 1...30 {
            dates.append(ambientStart.addingTimeInterval(TimeInterval(step) * 120))
        }
        return dates
    }
}

struct PetEnclosureWidget: Widget {
    nonisolated static let kind = "PetIsland.Enclosure"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: PetEnclosureProvider()) { entry in
            PetEnclosureView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.08, green: 0.13, blue: 0.19)
                }
                .widgetURL(URL(string: "petisland://enclosure"))
        }
        .configurationDisplayName("Pet Enclosure")
        .description("A tiny living yard for your Pet Island friends.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct PetEnclosureView: View {
    let entry: PetEnclosureEntry

    private var presentation: PetLifePresentation { entry.presentation }
    private var petIsHere: Bool { !entry.petProjections.isEmpty }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                enclosureBackground(size: proxy.size)
                enclosureProps(size: proxy.size)

                if petIsHere {
                    if let ball = presentation.ball {
                        Image(systemName: "tennisball.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.yellow, .white)
                            .shadow(color: .black.opacity(0.22), radius: 2, y: 2)
                            .position(
                                x: horizontalPosition(ball.x, in: proxy.size.width, inset: 22),
                                y: min(max(ball.y * proxy.size.height, 46), proxy.size.height - 28)
                            )
                            .animation(
                                .easeInOut(duration: PetLifeEngine.widgetMotionSegmentDuration),
                                value: ball
                            )
                    }

                    ForEach(entry.petProjections) { projection in
                        if let resident = entry.habitat.residents.first(where: { $0.id == projection.petID }) {
                            WidgetPetArtwork(
                                profile: resident.profile,
                                pose: effectivePose(for: projection),
                                direction: effectiveDirection(for: projection),
                                framePhase: Double(effectiveStep(for: projection))
                            )
                            .frame(width: petSize, height: petSize * 0.86)
                            .shadow(color: .black.opacity(0.24), radius: 2, y: 3)
                            .position(
                                x: horizontalPosition(effectivePosition(for: projection), in: proxy.size.width, inset: 35),
                                y: min(max(effectiveVerticalPosition(for: projection) * proxy.size.height, 58), proxy.size.height - 28)
                            )
                            .animation(
                                .linear(duration: PetLifeEngine.widgetMotionSegmentDuration),
                                value: effectivePosition(for: projection)
                            )
                            .animation(
                                .easeInOut(duration: PetLifeEngine.widgetMotionSegmentDuration),
                                value: effectiveVerticalPosition(for: projection)
                            )
                            .animation(
                                .easeInOut(duration: 0.24),
                                value: effectivePose(for: projection)
                            )
                            .animation(
                                .linear(duration: PetLifeEngine.widgetMotionSegmentDuration),
                                value: effectiveStep(for: projection)
                            )
                            .zIndex(Double(projection.depth + 2))
                        }
                    }
                } else {
                    awayState
                        .position(x: proxy.size.width * 0.55, y: proxy.size.height * 0.65)
                }

                VStack(spacing: 0) {
                    header
                    Spacer()
                    footer
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .clipped()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private func enclosureBackground(size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: themePalette.sky,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(themePalette.light.opacity(0.68))
                .frame(width: 31, height: 31)
                .blur(radius: 0.4)
                .position(x: size.width - 43, y: 35)

            Ellipse()
                .fill(themePalette.ground.opacity(0.8))
                .frame(width: size.width * 0.78, height: 88)
                .position(x: size.width * 0.18, y: size.height * 0.68)

            Ellipse()
                .fill(themePalette.ground.opacity(0.92))
                .frame(width: size.width * 1.12, height: 104)
                .position(x: size.width * 0.7, y: size.height * 0.81)

            LinearGradient(
                colors: [themePalette.ground, themePalette.ground.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: size.height * 0.47)
            .position(x: size.width / 2, y: size.height * 0.79)
        }
    }

    private func enclosureProps(size: CGSize) -> some View {
        ZStack {
            dogHouse
                .position(x: 49, y: size.height - 55)

            HStack(alignment: .bottom, spacing: 11) {
                ForEach(0..<18, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.62) : Color.white.opacity(0.48))
                        .frame(width: 4, height: index.isMultiple(of: 3) ? 27 : 23)
                }
            }
            .overlay {
                Capsule()
                    .fill(Color.white.opacity(0.52))
                    .frame(height: 4)
                    .offset(y: 3)
            }
            .position(x: size.width / 2, y: size.height - 14)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "camera.macro")
                        .font(.system(size: 11))
                        .foregroundStyle(index == 1 ? .pink : .yellow, .green)
                }
            }
            .position(x: size.width - 85, y: size.height - 28)
        }
    }

    private var dogHouse: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(red: 0.76, green: 0.35, blue: 0.21))
                .frame(width: 58, height: 43)
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.22, green: 0.14, blue: 0.12))
                .frame(width: 24, height: 29)
            Image(systemName: "triangle.fill")
                .resizable()
                .foregroundStyle(Color(red: 0.42, green: 0.18, blue: 0.16))
                .frame(width: 68, height: 32)
                .rotationEffect(.degrees(0))
                .offset(y: -34)
        }
        .frame(width: 72, height: 70)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Label(activityLabel, systemImage: activitySymbol)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)

            Spacer(minLength: 4)
            VitalsStrip(vitals: presentation.vitals)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            Label(placementLabel, systemImage: placementSymbol)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.black.opacity(0.24), in: Capsule())

            Spacer()

            Button(intent: ThrowBallIntent()) {
                Label("Ball", systemImage: "tennisball.fill")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(petIsHere ? 0.88 : 0.42), in: Capsule())
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            }
            .buttonStyle(.plain)
            .disabled(!petIsHere)
            .accessibilityLabel("Throw a ball")
        }
    }

    private var awayState: some View {
        VStack(spacing: 4) {
            Image(systemName: entry.state.placement == .dynamicIsland ? "rectangle.inset.filled.and.person.filled" : "house.fill")
                .font(.title2)
            Text(entry.state.placement == .dynamicIsland ? "Exploring Dynamic Island" : "Playing in the app")
                .font(.caption2.bold())
        }
        .foregroundStyle(.white.opacity(0.83))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }

    private func horizontalPosition(_ normalized: Double, in width: CGFloat, inset: CGFloat) -> CGFloat {
        inset + CGFloat(min(max(normalized, 0), 1)) * max(width - inset * 2, 0)
    }

    private var activityLabel: LocalizedStringKey {
        switch presentation.activity {
        case .away: "Away from the yard"
        case .watching: "Watching butterflies"
        case .patrolling: "Exploring the yard"
        case .playing: "Chasing the ball"
        case .resting: "Taking a little rest"
        case .sleeping: "Dreaming"
        }
    }

    private var activitySymbol: String {
        switch presentation.activity {
        case .away: "location.fill"
        case .watching: "sparkles"
        case .patrolling: "pawprint.fill"
        case .playing: "tennisball.fill"
        case .resting, .sleeping: "moon.zzz.fill"
        }
    }

    private var placementLabel: LocalizedStringKey {
        switch entry.state.placement {
        case .home: "In the app"
        case .dynamicIsland: "On Dynamic Island"
        case .enclosure: "In the enclosure"
        }
    }

    private var placementSymbol: String {
        switch entry.state.placement {
        case .home: "house.fill"
        case .dynamicIsland: "capsule.fill"
        case .enclosure: "leaf.fill"
        }
    }

    private var accessibilityDescription: Text {
        Text(headerTitle)
            + Text(", ")
            + Text(activityLabel)
    }

    private var petSize: CGFloat {
        switch entry.petProjections.count {
        case 0...2: 62
        case 3...4: 52
        default: 44
        }
    }

    private var headerTitle: String {
        let residents = entry.habitat.residents
        if residents.count == 1 { return residents[0].profile.name }
        return "\(residents.count) friends"
    }

    private func effectivePose(for projection: HabitatPetProjection) -> PetPose {
        guard presentation.activity == .playing else { return projection.pose }
        if residentProfile(for: projection)?.species == .parrot { return .fly }
        return presentation.pose
    }

    private func effectiveDirection(for projection: HabitatPetProjection) -> PetDirection {
        guard presentation.activity == .playing else { return projection.direction }
        return presentation.direction
    }

    private func effectivePosition(for projection: HabitatPetProjection) -> Double {
        guard presentation.activity == .playing else { return projection.position }
        let index = Double(entry.petProjections.firstIndex(where: { $0.id == projection.id }) ?? 0)
        let trailingOffset = index * 0.09
        let position = presentation.direction == .right
            ? presentation.position - trailingOffset
            : presentation.position + trailingOffset
        return min(max(position, 0.08), 0.92)
    }

    private func effectiveVerticalPosition(for projection: HabitatPetProjection) -> Double {
        guard presentation.activity == .playing else { return projection.verticalPosition }
        let jumpOffset = presentation.lane - 0.75
        let flightOffset = residentProfile(for: projection)?.species == .parrot ? -0.08 : 0
        return min(max(projection.verticalPosition + jumpOffset + flightOffset, 0.38), 0.88)
    }

    private func effectiveStep(for projection: HabitatPetProjection) -> Int {
        guard presentation.activity == .playing else { return projection.spriteStep }
        let phaseOffset = (entry.petProjections.firstIndex(where: { $0.id == projection.id }) ?? 0) * 2
        return presentation.spriteStep + phaseOffset
    }

    private func residentProfile(for projection: HabitatPetProjection) -> PetProfile? {
        entry.habitat.residents.first(where: { $0.id == projection.petID })?.profile
    }

    private var themePalette: WidgetHabitatPalette {
        WidgetHabitatPalette.palette(for: entry.habitat.configuration.theme)
    }
}

/// SwiftUI interpolates `framePhase` while the timeline entry transitions.
/// Rounding that value selects successive pixel-art frames, so the legs cycle
/// during the same system animation that moves the pet across the enclosure.
private struct WidgetPetArtwork: View, Animatable {
    let profile: PetProfile
    let pose: PetPose
    let direction: PetDirection
    var framePhase: Double

    var animatableData: Double {
        get { framePhase }
        set { framePhase = newValue }
    }

    var body: some View {
        sprite
            .contentTransition(.identity)
            .offset(x: strideOffsetX, y: strideOffsetY)
    }

    @ViewBuilder
    private var sprite: some View {
        if let atlas = WidgetSpriteAtlasLibrary.descriptor(for: profile, pose: pose) {
            WidgetAtlasSprite(
                profile: profile,
                direction: direction,
                atlas: atlas,
                framePhase: framePhase
            )
        } else {
            PetArtwork(
                species: profile.species,
                coat: profile.coat,
                customColor: profile.customColor,
                breed: profile.resolvedBreed,
                pose: pose,
                direction: direction,
                step: Int(floor(framePhase)),
                animatesMotion: false
            )
        }
    }

    private var isStridePose: Bool {
        pose == .run || pose == .walk || pose == .fly
    }

    /// Integer-pixel contact motion preserves the crisp sprite while making
    /// each planted foot produce a short, visible push instead of a float.
    private var strideOffsetY: CGFloat {
        guard isStridePose else { return 0 }
        let contact = abs(sin(framePhase * .pi / 2))
        return -round(contact * (pose == .fly ? 3 : 2))
    }

    private var strideOffsetX: CGFloat {
        guard isStridePose else { return 0 }
        let push = round(sin(framePhase * .pi / 2))
        return direction == .right ? push : -push
    }
}

private struct WidgetSpriteAtlasDescriptor {
    let assetName: String
    let frameCount: Int
}

/// All movement frames live in one bitmap. WidgetKit therefore sees one stable
/// image node while SwiftUI interpolates only numeric crop coordinates.
private enum WidgetSpriteAtlasLibrary {
    static func descriptor(
        for profile: PetProfile,
        pose: PetPose
    ) -> WidgetSpriteAtlasDescriptor? {
        guard pose == .run || pose == .walk || pose == .fly else { return nil }

        return switch (profile.species, profile.resolvedBreed) {
        case (.dog, .shepherd): .init(assetName: "widget_atlas_dog_shepherd_run", frameCount: 6)
        case (.dog, .corgi): .init(assetName: "widget_atlas_dog_corgi_run", frameCount: 4)
        case (.dog, .doberman): .init(assetName: "widget_atlas_dog_doberman_run", frameCount: 4)
        case (.dog, .bullTerrier): .init(assetName: "widget_atlas_dog_bull_terrier_run", frameCount: 4)
        case (.cat, .classicCat): .init(assetName: "widget_atlas_cat_classic_run", frameCount: 4)
        case (.cat, .britishShorthair): .init(assetName: "widget_atlas_cat_british_run", frameCount: 4)
        case (.cat, .maineCoon): .init(assetName: "widget_atlas_cat_maine_coon_run", frameCount: 4)
        case (.cat, .siamese): .init(assetName: "widget_atlas_cat_siamese_run", frameCount: 4)
        case (.fox, .redFox): .init(assetName: "widget_atlas_fox_red_run", frameCount: 4)
        case (.fox, .arcticFox): .init(assetName: "widget_atlas_fox_arctic_run", frameCount: 4)
        case (.parrot, .classicParrot): .init(assetName: "widget_atlas_parrot_classic_fly", frameCount: 8)
        case (.parrot, .cockatiel): .init(assetName: "widget_atlas_parrot_cockatiel_fly", frameCount: 8)
        case (.parrot, .budgie): .init(assetName: "widget_atlas_parrot_budgie_fly", frameCount: 8)
        case (.parrot, .macaw): .init(assetName: "widget_atlas_parrot_macaw_fly", frameCount: 8)
        case (.penguin, .classicPenguin): .init(assetName: "widget_atlas_penguin_classic_run", frameCount: 4)
        case (.penguin, .rockhopper): .init(assetName: "widget_atlas_penguin_rockhopper_run", frameCount: 4)
        case (.bear, _): .init(assetName: "widget_atlas_bear_run", frameCount: 16)
        case (.lizard, _): .init(assetName: "widget_atlas_lizard_run", frameCount: 4)
        case (.bunny, _): .init(assetName: "widget_atlas_bunny_run", frameCount: 1)
        default: nil
        }
    }
}

private struct WidgetAtlasSprite: View {
    let profile: PetProfile
    let direction: PetDirection
    let atlas: WidgetSpriteAtlasDescriptor
    let framePhase: Double

    var body: some View {
        atlasCanvas
            .overlay {
                if let customColor = profile.customColor {
                    Color(
                        red: customColor.red,
                        green: customColor.green,
                        blue: customColor.blue
                    )
                    .blendMode(.color)
                    .opacity(0.58)
                    .mask(atlasCanvas)
                }
            }
            .scaleEffect(x: direction == .right ? 1 : -1, y: 1)
            .aspectRatio(1.25, contentMode: .fit)
            .compositingGroup()
            .accessibilityHidden(true)
    }

    private var atlasCanvas: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
            let rawFrame = Int(floor(framePhase))
            let frame = ((rawFrame % atlas.frameCount) + atlas.frameCount) % atlas.frameCount
            let visibleRect = CGRect(origin: .zero, size: size)
            context.clip(to: Path(visibleRect))
            context.draw(
                Image(atlas.assetName).interpolation(.none),
                in: CGRect(
                    x: -CGFloat(frame) * size.width,
                    y: 0,
                    width: size.width * CGFloat(atlas.frameCount),
                    height: size.height
                )
            )
        }
    }
}

private struct WidgetHabitatPalette {
    let sky: [Color]
    let ground: Color
    let light: Color

    static func palette(for theme: HabitatTheme) -> WidgetHabitatPalette {
        switch theme {
        case .meadow:
            WidgetHabitatPalette(sky: [.blue.opacity(0.8), .mint.opacity(0.55)], ground: .green, light: .yellow)
        case .cozyRoom:
            WidgetHabitatPalette(sky: [.orange.opacity(0.82), .brown.opacity(0.62)], ground: .brown, light: .yellow)
        case .moonlitGarden:
            WidgetHabitatPalette(sky: [.indigo.opacity(0.94), .purple.opacity(0.7)], ground: Color(red: 0.08, green: 0.3, blue: 0.23), light: .white)
        case .arcticCove:
            WidgetHabitatPalette(sky: [.cyan.opacity(0.72), .white], ground: Color(red: 0.7, green: 0.88, blue: 0.93), light: .white)
        case .desertCamp:
            WidgetHabitatPalette(sky: [.orange.opacity(0.86), .yellow.opacity(0.64)], ground: Color(red: 0.68, green: 0.38, blue: 0.17), light: .yellow)
        }
    }
}

private struct VitalsStrip: View {
    let vitals: PetVitals

    var body: some View {
        HStack(spacing: 5) {
            VitalMeter(symbol: "fork.knife", value: vitals.fullness, color: .orange)
            VitalMeter(symbol: "heart.fill", value: vitals.happiness, color: .pink)
            VitalMeter(symbol: "bolt.fill", value: vitals.energy, color: .yellow)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.black.opacity(0.22), in: Capsule())
    }
}

private struct VitalMeter: View {
    let symbol: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(color)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: 18 * CGFloat(min(max(value, 0), 1)))
            }
            .frame(width: 18, height: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(symbol == "heart.fill" ? "Happiness" : symbol == "bolt.fill" ? "Energy" : "Fullness"))
        .accessibilityValue(Text("\(Int(value * 100)) percent"))
    }
}

#if DEBUG
#Preview(as: .systemMedium) {
    PetEnclosureWidget()
} timeline: {
    let state = PetLifeState.initial()
    let habitat = SharedPetHabitat.initial()
    PetEnclosureEntry(
        date: .now,
        state: state,
        habitat: habitat,
        presentation: PetLifeEngine.presentation(for: state, at: .now),
        petProjections: PetHabitatEngine.projections(
            for: habitat.configuration,
            pets: habitat.residents.map(\.profile),
            at: .now
        )
    )
}
#endif
