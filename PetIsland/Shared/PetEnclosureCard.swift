import AppIntents
import SwiftUI
import WidgetKit

/// A quiet, interactive snapshot. WidgetKit chooses refresh times; the card
/// deliberately avoids pretending that a still running frame is an animation.
struct PetEnclosureCard: View {
    let date: Date
    let habitat: SharedPetHabitat
    var family: WidgetFamily = .systemMedium
    let requestID: UUID
    var onAction: ((HabitatWidgetAction) -> Void)? = nil

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var compact: Bool { family == .systemSmall }
    private var residents: [SharedHabitatResident] {
        let selected = Set(habitat.configuration.residentPetIDs)
        var seen = Set<UUID>()
        return habitat.visibleResidents(at: date).filter {
            selected.contains($0.id) && $0.id != habitat.configuration.leadDynamicIslandPetID
                && seen.insert($0.id).inserted
        }
    }
    private var shownResidents: [SharedHabitatResident] { compact ? Array(residents.prefix(1)) : residents }
    private var palette: EnclosureCardPalette { .init(theme: habitat.configuration.theme) }
    private var foreground: Color { renderingMode == .fullColor ? palette.foreground : .primary }
    private var feedback: HabitatWidgetInteraction? { habitat.widgetInteraction(at: date) }
    private var activeWalk: PetDiscoveryWalk? {
        guard let walk = habitat.discoveryWalk,
              habitat.configuration.residentPetIDs.contains(walk.pet.id),
              walk.pet.id != habitat.configuration.leadDynamicIslandPetID,
              habitat.isPetAway(walk.pet.id, at: date) else { return nil }
        return walk
    }

    static func background(for theme: HabitatTheme) -> some View {
        let palette = EnclosureCardPalette(theme: theme)
        return LinearGradient(colors: palette.sky, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(spacing: 3) {
            header
            GeometryReader { geometry in scene(in: geometry.size) }
            controls
        }
        .padding(12)
        .foregroundStyle(foreground)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: compact ? 15 : 16, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let feedback {
                    Text(feedback.action == .pet ? "Thanks for the cuddles!" : "That was fun!", tableName: "EnclosureWidget")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("widget.feedback")
                } else {
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(foreground.opacity(0.72))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            if !compact, !residents.isEmpty {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 13, weight: .medium))
                    .padding(7)
                    .background(foreground.opacity(0.07), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 34, alignment: .top)
    }

    private var title: String {
        if compact, let pet = residents.first { return pet.profile.name }
        if residents.count == 1, let pet = residents.first { return pet.profile.name }
        if residents.isEmpty, let walk = activeWalk { return walk.pet.name }
        return String(localized: "Your island", table: "EnclosureWidget")
    }

    private var subtitle: String {
        if residents.isEmpty {
            return activeWalk == nil
                ? String(localized: "A place for your friends", table: "EnclosureWidget")
                : String(localized: "On a walk", table: "EnclosureWidget")
        }
        if residents.count > 1 {
            return String.localizedStringWithFormat(String(localized: "%lld at home", table: "EnclosureWidget"), residents.count)
        }
        return String(localized: "A little moment together", table: "EnclosureWidget")
    }

    private func scene(in size: CGSize) -> some View {
        ZStack {
            scenery(in: size)
            if residents.isEmpty {
                emptyScene
            } else {
                ForEach(Array(shownResidents.enumerated()), id: \.element.id) { index, resident in
                    let width = min(compact ? 96 : 110, min(size.width / CGFloat(shownResidents.count), size.height * 1.22))
                    let x = size.width * (CGFloat(index) + 0.5) / CGFloat(shownResidents.count)
                    let baseline = size.height * 0.88
                    let center = baseline - width * (PetSpriteGeometry.baseline - PetSpriteGeometry.canvas.height / 2) / PetSpriteGeometry.canvas.width
                    EnclosureWidgetPetArtwork(profile: resident.profile, pose: pose(for: resident),
                                              direction: index.isMultiple(of: 2) ? .right : .left)
                        .frame(width: width, height: width * 0.8)
                        .position(x: x, y: center)
                        .accessibilityHidden(true)
                    if feedback?.petIDs.contains(resident.id) == true {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(renderingMode == .fullColor ? .pink : foreground)
                            .position(x: x + width * 0.19, y: max(6, center - width * 0.34))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sceneDescription)
        .accessibilityIdentifier(residents.isEmpty ? "widget.empty" : "widget.scene")
    }

    private func scenery(in size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill((renderingMode == .fullColor ? palette.ground : foreground).opacity(0.16))
                .frame(width: size.width * 0.98, height: max(12, size.height * 0.37))
                .position(x: size.width * 0.5, y: size.height * 0.82)
            Capsule()
                .fill(foreground.opacity(0.09))
                .frame(width: size.width * 0.84, height: 1)
                .position(x: size.width * 0.5, y: size.height * 0.88)
            Image(systemName: palette.isNight ? "sparkles" : "leaf.fill")
                .font(.system(size: 11, weight: .medium))
                .rotationEffect(.degrees(-25))
                .foregroundStyle(foreground.opacity(0.2))
                .position(x: size.width * 0.07, y: size.height * 0.65)
            Image(systemName: palette.isNight ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(foreground.opacity(0.16))
                .position(x: size.width * 0.91, y: size.height * 0.19)
        }
        .accessibilityHidden(true)
    }

    private var emptyScene: some View {
        VStack(spacing: 4) {
            Image(systemName: activeWalk == nil ? "house" : "leaf")
                .font(.system(size: 21, weight: .light))
            if let walk = activeWalk {
                Text("Home at \(walk.endsAt.formatted(date: .omitted, time: .shortened))", tableName: "EnclosureWidget")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                Text("Choose who lives here", tableName: "EnclosureWidget")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(foreground.opacity(0.75))
    }

    private var sceneDescription: Text {
        if residents.isEmpty {
            if let walk = activeWalk {
                return Text("Home at \(walk.endsAt.formatted(date: .omitted, time: .shortened))", tableName: "EnclosureWidget")
            }
            return Text("Choose who lives here", tableName: "EnclosureWidget")
        }
        return Text(residents.map(\.profile.name).joined(separator: ", "))
    }

    private func pose(for resident: SharedHabitatResident) -> PetPose {
        if feedback?.petIDs.contains(resident.id) == true { return feedback?.action == .play ? .play : .idle }
        return habitat.visibleProjections(at: date).first(where: { $0.petID == resident.id })?.pose == .sleep ? .sleep : .idle
    }

    @ViewBuilder private var controls: some View {
        if residents.isEmpty {
            Link(destination: URL(string: "petisland://enclosure")!) {
                Label { Text("Open island", tableName: "EnclosureWidget") } icon: { Image(systemName: "arrow.up.right") }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(foreground.opacity(0.08), in: Capsule())
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        } else {
            HStack(spacing: 7) {
                careButton(.pet)
                if !compact { careButton(.play) }
            }
        }
    }

    private func careButton(_ action: HabitatWidgetAction) -> some View {
        Group {
            if let onAction {
                Button { onAction(action) } label: { actionLabel(action) }
                    .disabled(!habitat.canPerformWidgetAction(at: date))
            } else {
                Button(intent: HabitatWidgetCareIntent(action: action, requestID: requestID)) { actionLabel(action) }
                    // Keep the intent hit target during cooldown. A disabled
                    // widget button can fall through to the card's widgetURL.
                    // The shared-store transaction safely rejects rapid taps.
                    .opacity(habitat.canPerformWidgetAction(at: date) ? 1 : 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action == .pet ? "widget.pet" : "widget.play")
    }

    private func actionLabel(_ action: HabitatWidgetAction) -> some View {
        Label {
            Text(action == .pet ? "Pet" : "Play", tableName: "EnclosureWidget")
        } icon: {
            Image(systemName: action == .pet ? "hand.draw" : "tennisball")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 36)
        .background(foreground.opacity(action == .pet ? 0.1 : 0.065), in: Capsule())
    }
}

/// Native images opt out of Home Screen accent recoloring. The source pixels,
/// registration, coats and outfit ink are the same as the shared pet renderer.
struct EnclosureWidgetPetArtwork: View {
    let profile: PetProfile
    let pose: PetPose
    var direction: PetDirection = .right

    var body: some View {
        let asset = PetAnimationLibrary.clip(for: profile.species, breed: profile.resolvedBreed, pose: pose).frameName(forStep: 0)
        let dressed = profile.outfit?.headwear.flatMap { PetDressedAssets.frame(for: $0, assetName: asset) }
        GeometryReader { proxy in
            let rect = PetSpriteGeometry.load(assetName: asset)?.rect(in: proxy.size)
                ?? CGRect(origin: .zero, size: proxy.size)
            image(dressed.map { Image(uiImage: $0.image) } ?? Image(asset))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .petCoat(species: profile.species, coat: profile.coat, customColor: profile.customColor)
        .overlay {
            if profile.coat != .sunrise || profile.customColor != nil,
               let accessory = profile.outfit?.headwear, let dressed {
                GeometryReader { proxy in
                    if let geometry = PetSpriteGeometry.load(assetName: asset),
                       let rect = PetAccessoryAssets.frame(for: accessory, assetName: asset, geometry: geometry, viewport: proxy.size) {
                        image(Image(uiImage: dressed.ink.image))
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
            }
        }
        .scaleEffect(x: direction == .right ? 1 : -1, y: 1)
        .transaction { $0.animation = nil }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func image(_ source: Image) -> some View {
        if #available(iOS 18.0, *) {
            source.renderingMode(.original).resizable().interpolation(.none)
                .widgetAccentedRenderingMode(.fullColor)
        } else {
            source.renderingMode(.original).resizable().interpolation(.none)
        }
    }
}

private struct EnclosureCardPalette {
    let sky: [Color]
    let ground: Color
    let foreground: Color
    let isNight: Bool

    init(theme: HabitatTheme) {
        isNight = theme == .moonlitGarden || theme == .starryNight
        foreground = isNight ? .white : .primary
        switch theme {
        case .moonlitGarden, .starryNight:
            sky = [Color(red: 0.12, green: 0.15, blue: 0.21), Color(red: 0.22, green: 0.25, blue: 0.31)]
            ground = .white
        case .sunnyMeadow:
            sky = [Color(.systemBackground), Color.green.opacity(0.14)]
            ground = .green
        case .arcticCove, .snowyCove:
            sky = [Color(.secondarySystemBackground), Color.cyan.opacity(0.12)]
            ground = .cyan
        case .warmRoom, .sunsetDunes, .desertCamp, .cozyRoom:
            sky = [Color(.secondarySystemBackground), Color.orange.opacity(0.1)]
            ground = .brown
        case .meadow:
            sky = [Color(.secondarySystemBackground), Color(.tertiarySystemBackground)]
            ground = .gray
        }
    }
}

#if DEBUG
struct EnclosureWidgetPreviewHost: View {
    @State private var habitat = Self.fixture()
    @State private var date = Date.now
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        let small = arguments.contains("-widget-small")
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            PetEnclosureCard(date: date, habitat: habitat, family: small ? .systemSmall : .systemMedium,
                             requestID: UUID()) { action in
                let now = Date.now
                _ = habitat.performWidgetAction(action, requestID: UUID(), at: now)
                date = now
            }
            .frame(width: small ? 170 : 344, height: 170)
            .background(PetEnclosureCard.background(for: habitat.configuration.theme))
            .environment(\.widgetRenderingMode, arguments.contains("-widget-accented") ? .accented : .fullColor)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(20)
        }
        .preferredColorScheme(arguments.contains("-widget-dark") ? .dark : .light)
        .task(id: habitat.widgetInteraction(at: date)?.requestID) {
            guard let interaction = habitat.widgetInteraction(at: date) else { return }
            for offset in [HabitatWidgetInteraction.cooldown, HabitatWidgetInteraction.feedbackDuration] {
                let delay = max(0, interaction.date.addingTimeInterval(offset).timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                date = .now
            }
        }
    }

    private static func fixture() -> SharedPetHabitat {
        let arguments = ProcessInfo.processInfo.arguments
        let now = Date.now
        if arguments.contains("-widget-empty") {
            return SharedPetHabitat(configuration: .init(), residents: [])
        }
        let names = ["Pixel", "Mochi", "Sunny", "Coco", "Milo", "Luna"]
        let variants: [(PetSpecies, PetBreed)] = [(.dog, .corgi), (.cat, .classicCat), (.lion, .adultLion),
                                                (.fox, .redFox), (.penguin, .classicPenguin), (.parrot, .budgie)]
        let count = arguments.contains("-widget-six") ? 6 : arguments.contains("-widget-away") || arguments.contains("-widget-small") || arguments.contains("-widget-long-name") ? 1 : 2
        let residents = (0..<count).map { index in
            SharedHabitatResident(profile: PetProfile(id: UUID(),
                name: arguments.contains("-widget-long-name") ? "Константинополька" : names[index],
                species: variants[index].0, coat: .sunrise, createdAt: now, breed: variants[index].1),
                                  vitals: PetVitals(), vitalsUpdatedAt: now)
        }
        let walk = arguments.contains("-widget-away") ? PetDiscoveryWalk(pet: residents[0].profile, route: .garden,
            startedAt: now.addingTimeInterval(-300), endsAt: now.addingTimeInterval(900), discovery: .clover) : nil
        return SharedPetHabitat(configuration: PetHabitatState(residentPetIDs: residents.map(\.id), simulationEpoch: now),
                                residents: residents, discoveryWalk: walk)
    }
}
#endif
