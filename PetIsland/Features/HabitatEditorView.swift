import SwiftUI
import UIKit

/// Drafts the theme and residents; furniture placement is saved immediately.
struct HabitatEditorView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pets: [PetProfile]
    @Binding var selectedPetIDs: [UUID]
    @Binding var selectedTheme: HabitatTheme
    private var hasCozyBox: Bool { controller.habitat.configuration.hasCozyBox }
    var vitalsByPetID: [UUID: PetVitals]
    var unavailablePetIDs: Set<UUID>
    var maximumPets: Int
    var onSave: () -> Bool
    @State private var saveFailed = false
    @State private var showsFurniture = false

    init(
        controller: PetSessionController,
        pets: [PetProfile],
        selectedPetIDs: Binding<[UUID]>,
        selectedTheme: Binding<HabitatTheme>,
        vitalsByPetID: [UUID: PetVitals] = [:],
        unavailablePetIDs: Set<UUID> = [],
        maximumPets: Int = 3,
        onSave: @escaping () -> Bool = { true }
    ) {
        self.controller = controller
        self.pets = pets
        _selectedPetIDs = selectedPetIDs
        _selectedTheme = selectedTheme
        self.vitalsByPetID = vitalsByPetID
        self.unavailablePetIDs = unavailablePetIDs
        self.maximumPets = max(maximumPets, 1)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    habitatPreview
                    themePicker
                    furniturePicker
                    petPicker
                    statusPanel
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .petPage()
            .alert("Could not save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            } message: { Text("Your draft is safe. Please try saving again.") }
            .navigationTitle("Enclosure")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsFurniture) {
                HabitatFurnitureView(controller: controller)
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
    }

    private var habitatPreview: some View {
        HabitatEditorCanvas(
            theme: selectedTheme,
            pets: presentPets,
            vitalsByPetID: vitalsByPetID,
            hasCozyBox: hasCozyBox,
            isAnimationEnabled: !showsFurniture
        )
        .frame(height: 236)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your enclosure")
                    .font(.headline)
                Text("\(presentPets.count)/\(maximumPets) residents")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            .padding(12)
        }
        .accessibilityElement(children: .contain)
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader(
                title: "Background",
                subtitle: "Choose the atmosphere of the enclosure",
                symbol: "paintpalette.fill"
            )

            themeGroup(title: "Calm landscapes", vivid: false)
            themeGroup(title: "Colorful landscapes", vivid: true)
        }
    }

    private var furniturePicker: some View {
        Button { showsFurniture = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.title3)
                    .foregroundStyle(PetDesign.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Furniture").font(.subheadline.weight(.semibold))
                    Text(hasCozyBox ? "Cozy box" : "Choose an item")
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PetDesign.secondary)
            }
            .padding(14)
            .background(PetDesign.surface, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("furniture.open")
    }

    private func themeGroup(title: LocalizedStringKey, vivid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PetDesign.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 11) {
                    ForEach(HabitatThemePresentation.options.filter { $0.theme.isVivid == vivid }) { theme in
                        themeButton(theme)
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func themeButton(_ theme: HabitatThemePresentation) -> some View {
        let isSelected = theme.theme == selectedTheme

        return Button {
            selectedTheme = theme.theme
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HabitatThemeSwatch(theme: theme)
                    .frame(height: 68)

                Label(theme.name, systemImage: theme.symbol)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .frame(minHeight: 34, alignment: .topLeading)
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 240 : 120, alignment: .leading)
            .padding(9)
            .background(
                isSelected ? PetDesign.accent.opacity(0.14) : PetDesign.surface,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? PetDesign.accent : Color.secondary.opacity(0.13), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var petPicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeader(
                title: "Residents",
                subtitle: "Pick up to \(maximumPets) pets for this enclosure",
                symbol: "pawprint.fill"
            )

            if maximumPets < PetHabitatState.maximumResidents {
                Text("One space is reserved for your travelling pet.")
                    .font(.caption)
                    .foregroundStyle(PetDesign.secondary)
            }
            if selectedPets.contains(where: { unavailablePetIDs.contains($0.id) }) {
                Text("A space is kept for your exploring pet.")
                    .font(.caption)
                    .foregroundStyle(PetDesign.secondary)
            }
            if pets.isEmpty {
                ContentUnavailableView(
                    "No pets yet",
                    systemImage: "pawprint",
                    description: Text("Create a pet before editing the enclosure.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 104), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(pets) { pet in
                        residentButton(pet)
                    }
                }
            }
        }
    }

    private func residentButton(_ pet: PetProfile) -> some View {
        let isSelected = selectedPets.contains { $0.id == pet.id }
        let selectionIsFull = selectedPets.count >= maximumPets
        let cannotRemoveLast = isSelected && selectedPets.count == 1
        let isAway = unavailablePetIDs.contains(pet.id)

        return Button {
            toggleSelection(of: pet.id)
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    PetArtwork(
                        species: pet.species,
                        coat: pet.coat,
                        customColor: pet.customColor,
                        breed: pet.resolvedBreed,
                        pose: pet.species == .parrot ? .fly : .idle,
                        direction: .right,
                        step: 0,
                        animatesMotion: false
                    )
                    .frame(width: 66, height: 56)

                    Image(systemName: isAway ? "clock.fill" : isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? PetDesign.onAccent : PetDesign.accent,
                            isSelected ? PetDesign.accent : PetDesign.surface
                        )
                        .offset(x: 5, y: -3)
                }

                Text(pet.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                Text(isAway ? "Out exploring" : pet.species.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(
                isSelected ? PetDesign.accent.opacity(0.12) : PetDesign.surface,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? PetDesign.accent : Color.clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .disabled(isAway || (selectionIsFull && !isSelected) || cannotRemoveLast)
        .opacity((selectionIsFull && !isSelected) ? 0.48 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isAway ? Text("A space is kept for your exploring pet.") :
                           cannotRemoveLast ? Text("At least one resident is required") : Text(""))
    }

    @ViewBuilder
    private var statusPanel: some View {
        if !presentPets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Status",
                    subtitle: "Visible wellbeing of every resident",
                    symbol: "heart.text.square.fill"
                )

                VStack(spacing: 0) {
                    ForEach(Array(presentPets.enumerated()), id: \.element.id) { index, pet in
                        HabitatResidentStatusRow(
                            pet: pet,
                            vitals: vitals(for: pet)
                        )
                        if index < presentPets.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .background(
                    PetDesign.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
        }
    }

    private var saveBar: some View {
        Button {
            saveFailed = !onSave()
        } label: {
            Label("Save enclosure", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(PetPrimaryButtonStyle())
        .controlSize(.large)
        .disabled(selectedPets.isEmpty)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var selectedPets: [PetProfile] {
        let petsByID = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, $0) })
        var seen = Set<UUID>()
        return selectedPetIDs
            .filter { seen.insert($0).inserted }
            .compactMap { petsByID[$0] }
            .prefix(maximumPets)
            .map { $0 }
    }

    private var presentPets: [PetProfile] {
        selectedPets.filter { !unavailablePetIDs.contains($0.id) }
    }

    private func vitals(for pet: PetProfile) -> PetVitals {
        vitalsByPetID[pet.id] ?? PetVitals()
    }

    private func toggleSelection(of id: UUID) {
        guard !unavailablePetIDs.contains(id) else { return }
        var normalizedIDs = selectedPets.map(\.id)
        if let index = normalizedIDs.firstIndex(of: id) {
            guard normalizedIDs.count > 1 else { return }
            normalizedIDs.remove(at: index)
        } else {
            guard pets.contains(where: { $0.id == id }), normalizedIDs.count < maximumPets else { return }
            normalizedIDs.append(id)
        }
        selectedPetIDs = normalizedIDs
    }

    private func sectionHeader(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        symbol: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.body.bold())
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct HabitatEditorCanvas: View {
    let theme: HabitatTheme
    let pets: [PetProfile]
    let vitalsByPetID: [UUID: PetVitals]
    var petScale: CGFloat = 1
    var hasCozyBox = false
    var isAnimationEnabled = true
    @PetReduceMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = HabitatMotionSimulation()
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HabitatThemeBackdrop(theme: palette)
                if pets.isEmpty {
                    if hasCozyBox {
                        Label("Empty enclosure", systemImage: "pawprint")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(palette.foreground)
                            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.44)
                    } else {
                        ContentUnavailableView("Empty enclosure", systemImage: "pawprint")
                            .foregroundStyle(palette.foreground)
                    }
                }
                if hasCozyBox {
                    cozyBox(layer: .back)
                        .zIndex(boxDepth - 0.2)
                    Button {
                        if let occupant = motion.boxOccupantID {
                            motion.pet(occupant)
                        } else {
                            motion.requestCatToBox()
                        }
                    } label: {
                        cozyBoxArtwork(layer: .front)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(boxArtworkPosition)
                    .zIndex(boxDepth + 0.2)
                    .disabled(!pets.contains(where: { $0.species == .cat }))
                    .accessibilityLabel("Cozy box")
                    .accessibilityValue(boxStatus)
                    .accessibilityHint(motion.boxOccupantID == nil ? Text("Invite a cat") : Text("Stroke pet"))
                }
                ForEach(motion.actors) { actor in
                    let width = min(proxy.size.width * 0.24, 78) * petScale
                    ZStack {
                        Ellipse().fill(.black.opacity(0.12))
                            .frame(width: width * 0.48, height: 5)
                            .offset(y: width * 0.31)
                        PetArtwork(species: actor.profile.species, coat: actor.profile.coat,
                                   customColor: actor.profile.customColor, breed: actor.profile.resolvedBreed,
                                   pose: actor.pose, direction: .right, step: reduceMotion ? 0 : actor.step,
                                   animatesMotion: false, usesNaturalGait: true)
                            .scaleEffect(x: actor.facing, y: 1)
                            .offset(y: actor.visualOffsetY)
                        if actor.affection > 0 {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(red: 0.88, green: 0.48, blue: 0.52))
                                .opacity(min(actor.affection, 1))
                                .offset(y: -width * 0.4 - (reduceMotion ? 0 : (1.5 - actor.affection) * 7))
                        }
                    }
                    .frame(width: width, height: width * 0.8)
                    .contentShape(Rectangle())
                    .onTapGesture { motion.pet(actor.id) }
                    .position(actor.position)
                    .zIndex(actor.id == motion.boxOccupantID && motion.boxPhase.containsCat
                            ? boxDepth : Double(actor.position.y))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(actor.profile.name)
                    .accessibilityValue(status(for: actor.pose))
                    .accessibilityAction(named: Text("Stroke pet")) { motion.pet(actor.id) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onAppear {
                isVisible = true
                configure(in: proxy.size)
                motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && scenePhase == .active)
            }
            .onChange(of: pets) { previous, value in
                configure(in: proxy.size)
                if previous.isEmpty && !value.isEmpty {
                    motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && isVisible && scenePhase == .active)
                }
            }
            .onChange(of: vitalsByPetID) { _, _ in configure(in: proxy.size) }
            .onChange(of: proxy.size) { _, value in configure(in: value) }
            .onChange(of: hasCozyBox) { _, _ in configure(in: proxy.size) }
            .onChange(of: petScale) { _, _ in configure(in: proxy.size) }
        }
        .onDisappear { isVisible = false; motion.stop() }
        .onChange(of: reduceMotion) { _, value in motion.start(reduceMotion: value, active: isAnimationEnabled && isVisible && scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && isVisible && phase == .active) }
        .onChange(of: isAnimationEnabled) { _, value in motion.start(reduceMotion: reduceMotion, active: value && isVisible && scenePhase == .active) }
    }

    private func configure(in size: CGSize) {
        motion.configure(pets: pets, size: size, petScale: petScale,
                         vitals: vitalsByPetID, hasCozyBox: hasCozyBox)
    }

    private var boxDepth: Double {
        Double(motion.boxRenderDepth)
    }

    private var boxArtworkPosition: CGPoint {
        CGPoint(x: motion.boxPosition.x,
                y: motion.boxPosition.y - (HabitatCozyBoxArtwork.groundAnchor.y - 0.5) * motion.boxSize.height)
    }

    private func cozyBoxArtwork(layer: HabitatCozyBoxArtwork.Layer) -> some View {
        HabitatCozyBoxArtwork(layer: layer)
            .frame(width: motion.boxSize.width, height: motion.boxSize.height)
    }

    private func cozyBox(layer: HabitatCozyBoxArtwork.Layer) -> some View {
        cozyBoxArtwork(layer: layer).position(boxArtworkPosition)
    }

    private var boxStatus: String {
        if !pets.contains(where: { $0.species == .cat }) {
            return String(localized: "No cats are home right now")
        }
        switch motion.boxPhase {
        case .resting:
            return motion.boxRestPose == .sleep
                ? String(localized: "Resting in the box")
                : String(localized: "Peeking out of the box")
        case .inspecting: return String(localized: "Inspecting the box")
        default: return ""
        }
    }

    private func status(for pose: PetPose) -> String {
        switch pose {
        case .sleep: String(localized: "sleeping")
        case .run: String(localized: "running")
        case .walk: String(localized: "wandering")
        case .fly: String(localized: "flying")
        case .play, .eat, .jump: String(localized: "playing")
        case .idle: String(localized: "watching")
        }
    }

    private var palette: HabitatThemePresentation {
        HabitatThemePresentation.options.first { $0.theme == theme } ?? HabitatThemePresentation.options[0]
    }
}

/// Foreground simulation owns velocity, gait phase and per-pet state. Editing
/// the cast never recalculates the positions of animals already in the scene.
@MainActor
final class HabitatMotionSimulation: ObservableObject {
    enum CozyBoxPhase: String, Equatable {
        case empty, approaching, inspecting, entering, resting, exiting

        var containsCat: Bool {
            self == .entering || self == .resting || self == .exiting
        }
    }

    struct Actor: Identifiable, Equatable {
        let id: UUID
        var profile: PetProfile
        var position: CGPoint
        var target: CGPoint
        var velocity = CGVector.zero
        var pose: PetPose = .idle
        var facing: CGFloat = 1
        var gaitPhase = 0.0
        var step = 0
        var affection = 0.0
        var waiting = 1.0
        var travelling = false
        var turning = 0.0
        var turnFrom: CGFloat = 1
        var desiredFacing: CGFloat = 1
        var pace = 28.0
        var seed: UInt64
        var blockedFor = 0.0
        /// A small entry/exit arc; the floor shadow keeps the ordinary ground anchor.
        var visualOffsetY: CGFloat = 0

        mutating func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
    }

    @Published private(set) var actors: [Actor] = []
    @Published private(set) var boxOccupantID: UUID?
    @Published private(set) var boxPhase: CozyBoxPhase = .empty
    private(set) var boxRestPose: PetPose = .sleep
    private(set) var size = CGSize.zero
    private(set) var hasCozyBox = false
    private var petWidth: CGFloat = 78
    private var vitals: [UUID: PetVitals] = [:]
    private var reduced = false
    private var clock = 0.0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    var isRunning: Bool { displayLink != nil }
    var isBoxOccupied: Bool { boxOccupantID != nil }
    var boxRenderDepth: CGFloat { boxCenter.y }
    var boxSize: CGSize {
        let width = petWidth * 0.9
        return CGSize(width: width, height: width / 1.4)
    }
    /// The illustrated box floor (94% down its image), rather than its frame center.
    var boxPosition: CGPoint {
        guard size.width > 1, size.height > 1 else { return .zero }
        let center = bounded(CGPoint(x: size.width * 0.69,
                                     y: (groundRange.lowerBound + groundRange.upperBound) / 2))
        return CGPoint(x: center.x, y: center.y + petWidth * 0.31)
    }

    private var boxApproachSide: CGFloat = -1
    private var boxPhaseElapsed = 0.0
    private var boxPhaseDuration = 1.0
    private var boxMotionOrigin = CGPoint.zero
    private var boxMotionOriginOffset: CGFloat = 0
    private var nextBoxVisit = Double.infinity
    private var boxRandomSeed: UInt64 = 0x434F_5A59_424F_5821

    @MainActor
    private final class Target: NSObject {
        weak var simulation: HabitatMotionSimulation?
        init(_ simulation: HabitatMotionSimulation) { self.simulation = simulation }
        @objc func tick(_ link: CADisplayLink) { simulation?.tick(link) }
    }

    func configure(pets: [PetProfile], size newSize: CGSize, petScale: CGFloat = 1,
                   vitals: [UUID: PetVitals] = [:], hasCozyBox: Bool = false) {
        guard newSize.width.isFinite, newSize.height.isFinite,
              newSize.width > 1, newSize.height > 1, petScale.isFinite, petScale > 0 else { return }
        self.vitals = vitals
        let previousSize = size
        let previousPetWidth = petWidth
        let wasBoxEnabled = self.hasCozyBox
        size = newSize
        petWidth = min(size.width * 0.24, 78) * petScale
        self.hasCozyBox = hasCozyBox
        let existing = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0) })
        actors = pets.enumerated().map { index, profile in
            if var actor = existing[profile.id] {
                actor.profile = profile
                if previousSize != size, previousSize.width > 1 {
                    actor.position.x *= size.width / previousSize.width
                    actor.position.y *= size.height / previousSize.height
                    actor.target.x *= size.width / previousSize.width
                    actor.target.y *= size.height / previousSize.height
                    actor.position = bounded(actor.position)
                    actor.target = bounded(actor.target)
                }
                return actor
            }
            let seed = withUnsafeBytes(of: profile.id.uuid) { bytes in
                bytes.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            }
            let position = bounded(CGPoint(x: size.width * (0.18 + Double(index % 3) * 0.24 + Double(index / 3) * 0.25),
                                           y: groundRange.lowerBound + Double(index % 3) * (groundRange.upperBound - groundRange.lowerBound) / 2))
            var actor = Actor(id: profile.id, profile: profile, position: position, target: position, seed: seed)
            actor.waiting = 0.25 + actor.random() * 1.4
            actor.gaitPhase = actor.random()
            if reduced { actor.pose = .idle }
            return actor
        }
        if !hasCozyBox || !actors.contains(where: { $0.id == boxOccupantID && $0.profile.species == .cat }) {
            cancelBoxVisit()
        } else if previousSize != size || previousPetWidth != petWidth {
            retargetBoxAfterResize()
        }
        if hasCozyBox && !wasBoxEnabled { scheduleNextBoxVisit() }
        if !hasCozyBox { nextBoxVisit = .infinity }
        if actors.isEmpty { stop() }
    }

    func start(reduceMotion: Bool, active: Bool) {
        reduced = reduceMotion
        stop()
        guard active, !actors.isEmpty else { return }
        if reduceMotion {
            if boxPhase != .resting { cancelBoxVisit() }
            actors = actors.map { actor in
                var actor = actor
                actor.velocity = .zero
                actor.pose = actor.id == boxOccupantID ? boxRestPose : .idle
                actor.visualOffsetY = actor.id == boxOccupantID ? boxRestOffset : 0
                actor.facing = actor.facing < 0 ? -1 : 1
                actor.turning = 0
                actor.affection = 0
                return actor
            }
            return
        }
        let link = CADisplayLink(target: Target(self), selector: #selector(Target.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = nil
    }

    deinit { displayLink?.invalidate() }

    private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let previous = lastTimestamp else { return }
        advance(by: link.timestamp - previous)
    }

    func pet(_ id: UUID) {
        guard let index = actors.firstIndex(where: { $0.id == id }) else { return }
        if boxOccupantID == id {
            if boxPhase.containsCat && !reduced {
                actors[index].affection = 1.5
                beginBoxExit(from: actors[index])
                return
            }
            if reduced && boxPhase.containsCat {
                actors[index].position = boxApproachPoint
                actors[index].visualOffsetY = 0
            }
            cancelBoxVisit()
        }
        actors[index].velocity = .zero
        actors[index].travelling = false
        actors[index].turning = 0
        actors[index].facing = actors[index].facing < 0 ? -1 : 1
        actors[index].pose = .play
        actors[index].waiting = 2.5
        actors[index].affection = reduced ? 0 : 1.5
    }

    /// A box reserves one present cat. Other species keep their normal simulation.
    @discardableResult
    func requestCatToBox(_ petID: UUID? = nil) -> Bool {
        guard hasCozyBox, boxOccupantID == nil, size.width > 1 else { return false }
        let candidates = actors.indices.filter {
            actors[$0].profile.species == .cat && (petID == nil || actors[$0].id == petID)
        }
        guard let index = candidates.min(by: {
            hypot(actors[$0].position.x - boxCenter.x, actors[$0].position.y - boxCenter.y)
                < hypot(actors[$1].position.x - boxCenter.x, actors[$1].position.y - boxCenter.y)
        }) else { return false }
        // This main-actor reservation happens synchronously, before any cat
        // advances. A second manual or ambient request cannot steal the box.
        boxOccupantID = actors[index].id
        boxRestPose = boxRandom() < 0.5 ? .idle : .sleep
        boxApproachSide = actors[index].position.x <= boxCenter.x ? -1 : 1
        boxPhaseElapsed = 0
        actors[index].visualOffsetY = 0
        actors[index].blockedFor = 0
        if reduced {
            actors[index].position = boxCenter
            actors[index].target = boxCenter
            actors[index].velocity = .zero
            actors[index].travelling = false
            actors[index].turning = 0
            actors[index].pose = boxRestPose
            actors[index].visualOffsetY = boxRestOffset
            actors[index].step = 0
            boxPhase = .resting
            boxPhaseDuration = 8
        } else {
            boxPhase = .approaching
            actors[index].target = boxApproachPoint
            actors[index].travelling = true
            actors[index].pace = 30
            actors[index].pose = .walk
            faceBoxTarget(&actors[index], target: boxApproachPoint)
        }
        return true
    }

    func advance(by rawDelta: TimeInterval) {
        guard !actors.isEmpty, !reduced, rawDelta.isFinite, rawDelta > 0, size.width > 1 else { return }
        let dt = min(rawDelta, 1.0 / 15)
        clock += dt
        if hasCozyBox, boxOccupantID == nil, clock >= nextBoxVisit {
            let nearby = actors.filter {
                $0.profile.species == .cat && hypot($0.position.x - boxCenter.x, $0.position.y - boxCenter.y) <= petWidth * 1.35
            }.min {
                hypot($0.position.x - boxCenter.x, $0.position.y - boxCenter.y)
                    < hypot($1.position.x - boxCenter.x, $1.position.y - boxCenter.y)
            }
            if let nearby { _ = requestCatToBox(nearby.id) }
            else { nextBoxVisit = clock + 2 }
        }
        let previous = actors
        var next = actors
        for index in next.indices {
            var actor = next[index]
            actor.affection = max(actor.affection - dt, 0)
            if actor.id != boxOccupantID, actor.visualOffsetY != 0 {
                // Removing a raised box lets its cat settle without teleporting
                // or shifting the floor lane used by every other resident.
                let settling = petWidth * dt * 1.2
                actor.visualOffsetY = actor.visualOffsetY < 0
                    ? min(actor.visualOffsetY + settling, 0)
                    : max(actor.visualOffsetY - settling, 0)
            }
            if hasCozyBox, actor.id == boxOccupantID {
                advanceBoxVisit(for: &actor, neighbours: previous, by: dt)
                updateAnimationFrame(for: &actor)
                next[index] = actor
                continue
            }
            if actor.turning > 0 {
                actor.turning = max(0, actor.turning - dt)
                let progress = 1 - actor.turning / 0.22
                // Change direction while standing; never squash the animal to a line.
                actor.facing = progress < 0.5 ? actor.turnFrom : actor.desiredFacing
                if actor.turning == 0 { actor.facing = actor.desiredFacing }
                next[index] = actor
                continue
            }
            if !actor.travelling {
                actor.waiting -= dt
                if actor.waiting <= 0 {
                    chooseDestination(for: &actor)
                    actor.travelling = true
                    actor.pose = actor.profile.species == .parrot ? .fly : .walk
                    actor.desiredFacing = actor.target.x >= actor.position.x ? 1 : -1
                    if actor.desiredFacing != actor.facing {
                        actor.turnFrom = actor.facing
                        actor.turning = 0.22
                        actor.pose = .idle
                    }
                }
            } else {
                let dx = actor.target.x - actor.position.x
                let dy = actor.target.y - actor.position.y
                let distance = hypot(dx, dy)
                let speed = min(actor.pace, sqrt(max(distance - 1, 0) * 130))
                var desired = CGVector(dx: dx / max(distance, 1) * speed,
                                       dy: dy / max(distance, 1) * speed)
                // Yield before walking through a neighbour on the same ground plane.
                let neighbour = previous.first { other in
                    other.id != actor.id && abs(other.position.y - actor.position.y) < 14 &&
                    (other.position.x - actor.position.x) * actor.facing > 0 &&
                    abs(other.position.x - actor.position.x) < petWidth * 0.8
                }
                if let neighbour {
                    desired.dx *= 0.12
                    actor.blockedFor += dt
                    if actor.facing != neighbour.facing || actor.blockedFor > 0.5 {
                        // Stable opposite passing lanes prevent two neighbours
                        // from repeatedly choosing the same side of each other.
                        actor.target.y = actor.id.uuidString < neighbour.id.uuidString
                            ? groundRange.lowerBound : groundRange.upperBound
                        desired.dy = min(max((actor.target.y - actor.position.y) * 4, -30), 30)
                    }
                } else { actor.blockedFor = 0 }
                let blend = 1 - exp(-dt * 7)
                actor.velocity.dx += (desired.dx - actor.velocity.dx) * blend
                actor.velocity.dy += (desired.dy - actor.velocity.dy) * blend
                let oldPosition = actor.position
                actor.position = bounded(CGPoint(x: actor.position.x + actor.velocity.dx * dt,
                                                 y: actor.position.y + actor.velocity.dy * dt))
                let travelled = hypot(actor.position.x - oldPosition.x, actor.position.y - oldPosition.y)
                let actualSpeed = travelled / dt
                actor.pose = actor.profile.species == .parrot ? .fly : (actualSpeed > 40 ? .run : .walk)
                // Continuous cycles survive a walk/run switch; only stride length changes.
                let stride = petWidth * (actor.pose == .run ? 0.55 : 0.38)
                actor.gaitPhase += travelled / max(stride, 1)
                if distance < 2 && actualSpeed < 7 {
                    actor.travelling = false
                    actor.velocity = .zero
                    let rest = actor.random()
                    actor.pose = rest > ((vitals[actor.id]?.energy ?? 1) < 0.18 ? 0.4 : 0.9) ? .sleep : (rest > 0.7 ? .play : .idle)
                    actor.waiting = actor.pose == .sleep ? 5 + actor.random() * 5 : 0.7 + actor.random() * 2.5
                }
            }
            let clip = PetAnimationLibrary.naturalClip(for: actor.profile.species, breed: actor.profile.resolvedBreed, pose: actor.pose)
            if actor.pose == .walk || actor.pose == .run {
                actor.step = Int(actor.gaitPhase.truncatingRemainder(dividingBy: 1) * Double(clip.frames.count))
            } else {
                actor.step = clip.frameIndex(at: clock)
            }
            next[index] = actor
        }
        actors = next
    }

    private var boxCenter: CGPoint {
        CGPoint(x: boxPosition.x, y: boxPosition.y - petWidth * 0.31)
    }

    private var boxRestOffset: CGFloat { -boxSize.height * (boxRestPose == .sleep ? 0.27 : 0.04) }

    private var boxApproachPoint: CGPoint {
        bounded(CGPoint(x: boxCenter.x + boxApproachSide * petWidth * 0.76, y: boxCenter.y))
    }

    private func boxRandom() -> Double {
        boxRandomSeed = boxRandomSeed &* 6364136223846793005 &+ 1442695040888963407
        return Double(boxRandomSeed >> 11) / Double(UInt64.max >> 11)
    }

    private func scheduleNextBoxVisit() {
        nextBoxVisit = clock + 15 + boxRandom() * 30
    }

    private func faceBoxTarget(_ actor: inout Actor, target: CGPoint) {
        guard abs(target.x - actor.position.x) > 0.5 else { return }
        let facing: CGFloat = target.x >= actor.position.x ? 1 : -1
        if actor.turning > 0, actor.desiredFacing == facing { return }
        guard actor.facing != facing else {
            actor.turning = 0
            actor.desiredFacing = facing
            return
        }
        actor.turnFrom = actor.facing
        actor.desiredFacing = facing
        actor.turning = 0.22
        actor.velocity = .zero
        actor.pose = .idle
    }

    private func advanceBoxVisit(for actor: inout Actor, neighbours: [Actor], by dt: TimeInterval) {
        let target = boxPhase == .entering ? boxCenter : boxApproachPoint
        if boxPhase == .approaching || boxPhase == .entering || boxPhase == .exiting {
            faceBoxTarget(&actor, target: target)
            if actor.turning > 0 {
                actor.turning = max(0, actor.turning - dt)
                let progress = 1 - actor.turning / 0.22
                actor.facing = progress < 0.5 ? actor.turnFrom : actor.desiredFacing
                if actor.turning == 0 { actor.facing = actor.desiredFacing }
                return
            }
        }

        switch boxPhase {
        case .empty:
            break
        case .approaching:
            actor.target = boxApproachPoint
            let dx = actor.target.x - actor.position.x
            let dy = actor.target.y - actor.position.y
            let distance = hypot(dx, dy)
            let speed = min(30, sqrt(max(distance - 1, 0) * 130))
            var desired = CGVector(dx: dx / max(distance, 1) * speed,
                                   dy: dy / max(distance, 1) * speed)
            if let neighbour = neighbours.first(where: {
                $0.id != actor.id && abs($0.position.y - actor.position.y) < 14
                    && ($0.position.x - actor.position.x) * actor.facing > 0
                    && abs($0.position.x - actor.position.x) < petWidth * 0.8
            }) {
                // Use a passing lane, without replacing the reserved destination.
                let lane = actor.id.uuidString < neighbour.id.uuidString
                    ? groundRange.lowerBound : groundRange.upperBound
                desired.dx *= 0.25
                desired.dy = min(max((lane - actor.position.y) * 4, -30), 30)
            }
            let blend = 1 - exp(-dt * 7)
            actor.velocity.dx += (desired.dx - actor.velocity.dx) * blend
            actor.velocity.dy += (desired.dy - actor.velocity.dy) * blend
            let old = actor.position
            actor.position = bounded(CGPoint(x: old.x + actor.velocity.dx * dt,
                                             y: old.y + actor.velocity.dy * dt))
            let travelled = hypot(actor.position.x - old.x, actor.position.y - old.y)
            actor.gaitPhase += travelled / max(petWidth * 0.38, 1)
            actor.pose = .walk
            if distance < 2 && travelled / dt < 7 {
                actor.velocity = .zero
                actor.travelling = false
                actor.pose = .idle
                boxPhase = .inspecting
                boxPhaseElapsed = 0
                boxPhaseDuration = 1.25
            }
        case .inspecting:
            actor.pose = .idle
            actor.velocity = .zero
            boxPhaseElapsed += dt
            if boxPhaseElapsed >= boxPhaseDuration {
                boxPhase = .entering
                boxPhaseElapsed = 0
                boxPhaseDuration = 1.15
                boxMotionOrigin = actor.position
                boxMotionOriginOffset = actor.visualOffsetY
                actor.travelling = true
            }
        case .entering, .exiting:
            boxPhaseElapsed += dt
            let progress = min(boxPhaseElapsed / boxPhaseDuration, 1)
            let eased = progress * progress * (3 - 2 * progress)
            let old = actor.position
            actor.position = bounded(CGPoint(
                x: boxMotionOrigin.x + (target.x - boxMotionOrigin.x) * eased,
                y: boxMotionOrigin.y + (target.y - boxMotionOrigin.y) * eased
            ))
            let targetOffset: CGFloat = boxPhase == .entering ? boxRestOffset : 0
            actor.visualOffsetY = boxMotionOriginOffset + (targetOffset - boxMotionOriginOffset) * eased
                - sin(.pi * eased) * petWidth * 0.11
            actor.velocity = CGVector(dx: (actor.position.x - old.x) / dt,
                                      dy: (actor.position.y - old.y) / dt)
            actor.target = target
            actor.pose = .walk
            actor.gaitPhase += hypot(actor.position.x - old.x, actor.position.y - old.y)
                / max(petWidth * 0.38, 1)
            if progress >= 1 {
                actor.visualOffsetY = targetOffset
                actor.velocity = .zero
                actor.travelling = false
                if boxPhase == .entering {
                    boxPhase = .resting
                    boxPhaseElapsed = 0
                    boxPhaseDuration = (boxRestPose == .sleep ? 10 : 6) + boxRandom() * 5
                    actor.pose = boxRestPose
                } else {
                    endBoxVisit(for: &actor)
                }
            }
        case .resting:
            actor.pose = boxRestPose
            actor.velocity = .zero
            actor.visualOffsetY = boxRestOffset
            boxPhaseElapsed += dt
            if boxPhaseElapsed >= boxPhaseDuration { beginBoxExit(from: actor) }
        }
    }

    private func beginBoxExit(from actor: Actor) {
        boxPhase = .exiting
        boxPhaseElapsed = 0
        boxPhaseDuration = 1.15
        boxMotionOrigin = actor.position
        boxMotionOriginOffset = actor.visualOffsetY
    }

    private func endBoxVisit(for actor: inout Actor) {
        // A removed item keeps its cat at the same drawn position, then the
        // regular tick settles only this offset. Reduce Motion uses a static exit.
        if reduced { actor.visualOffsetY = 0 }
        actor.target = actor.position
        actor.velocity = .zero
        actor.travelling = false
        actor.turning = 0
        actor.pose = .idle
        actor.waiting = 1.5
        boxOccupantID = nil
        boxPhase = .empty
        boxPhaseElapsed = 0
        if hasCozyBox { scheduleNextBoxVisit() }
    }

    private func cancelBoxVisit() {
        guard let occupantID = boxOccupantID else { return }
        if let index = actors.firstIndex(where: { $0.id == occupantID }) {
            var actor = actors[index]
            endBoxVisit(for: &actor)
            actors[index] = actor
        } else {
            boxOccupantID = nil
            boxPhase = .empty
            boxPhaseElapsed = 0
            if hasCozyBox { scheduleNextBoxVisit() }
        }
    }

    private func retargetBoxAfterResize() {
        guard let index = actors.firstIndex(where: { $0.id == boxOccupantID }) else { return }
        switch boxPhase {
        case .entering, .exiting:
            boxMotionOrigin = actors[index].position
            boxMotionOriginOffset = actors[index].visualOffsetY
            boxPhaseDuration = max(boxPhaseDuration - boxPhaseElapsed, 0.25)
            boxPhaseElapsed = 0
        case .resting:
            actors[index].position = boxCenter
            actors[index].target = boxCenter
            actors[index].visualOffsetY = boxRestOffset
        case .approaching, .inspecting:
            actors[index].target = boxApproachPoint
            boxPhase = .approaching
        case .empty:
            break
        }
    }

    private func updateAnimationFrame(for actor: inout Actor) {
        let clip = PetAnimationLibrary.naturalClip(for: actor.profile.species,
                                                   breed: actor.profile.resolvedBreed, pose: actor.pose)
        if actor.pose == .walk || actor.pose == .run {
            actor.step = Int(actor.gaitPhase.truncatingRemainder(dividingBy: 1) * Double(clip.frames.count))
        } else {
            actor.step = clip.frameIndex(at: clock)
        }
    }

    private func chooseDestination(for actor: inout Actor) {
        let xRange = (petWidth * 0.46)...max(size.width - petWidth * 0.46, petWidth * 0.46)
        // Look for breathing room instead of sending every resident to the
        // opposite edge. Reserve neighbours' destinations as well as their
        // current resting places, so they do not all stop in the same corner.
        let neighbours = actors.filter { $0.id != actor.id }
        var best = actor.position
        var bestScore = -Double.infinity
        for _ in 0..<12 {
            let candidate = bounded(CGPoint(
                x: xRange.lowerBound + actor.random() * (xRange.upperBound - xRange.lowerBound),
                y: groundRange.lowerBound + actor.random() * (groundRange.upperBound - groundRange.lowerBound)
            ))
            let clearance = neighbours.map { other in
                let occupied = other.travelling ? other.target : other.position
                return hypot((candidate.x - occupied.x) / (petWidth * 0.8),
                             (candidate.y - occupied.y) / (petWidth * 0.34))
            }.min() ?? 2
            let travel = hypot(candidate.x - actor.position.x, candidate.y - actor.position.y)
            let score = min(clearance, 2) + min(travel / (petWidth * 1.5), 1) * 0.6
            if score > bestScore { best = candidate; bestScore = score }
        }
        actor.target = best
        actor.pace = actor.random() > 0.58 ? 54 + actor.random() * 17 : 22 + actor.random() * 10
    }

    private var groundRange: ClosedRange<CGFloat> {
        let top = max(size.height * 0.58, petWidth * 0.4 + 45)
        return min(top, size.height - petWidth * 0.4 - 8)...max(top, size.height - petWidth * 0.4 - 8)
    }

    private func bounded(_ point: CGPoint) -> CGPoint {
        let inset = min(petWidth * 0.46, size.width / 2)
        return CGPoint(x: min(max(point.x, inset), size.width - inset),
                       y: min(max(point.y, groundRange.lowerBound), groundRange.upperBound))
    }
}

private struct HabitatThemeBackdrop: View {
    let theme: HabitatThemePresentation

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: theme.sky, startPoint: .top, endPoint: .bottom)
                if theme.theme.isVivid {
                    HabitatVividScenery(theme: theme)
                } else {
                    Circle()
                        .fill(theme.light)
                        .frame(width: min(43, size.height * 0.18), height: min(43, size.height * 0.18))
                        .position(x: size.width * 0.74, y: size.height * 0.36)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height * 0.65))
                        path.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.76),
                                          control: CGPoint(x: size.width * 0.4, y: size.height * 0.47))
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.addLine(to: CGPoint(x: 0, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(theme.ground.opacity(0.6))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height * 0.92))
                        path.addQuadCurve(to: CGPoint(x: size.width, y: size.height * 0.68),
                                          control: CGPoint(x: size.width * 0.5, y: size.height * 0.58))
                        path.addLine(to: CGPoint(x: size.width, y: size.height))
                        path.addLine(to: CGPoint(x: 0, y: size.height))
                        path.closeSubpath()
                    }
                    .fill(theme.ground.opacity(0.48))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Static scenery uses relative coordinates so thumbnails and the enclosure
/// show the same landscape without affecting the pets' animation timeline.
private struct HabitatVividScenery: View {
    let theme: HabitatThemePresentation

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let unit = min(w / 360, h / 236)
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            func ellipse(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: w * x, y: h * y, width: w * width, height: h * height))
            }

            if theme.theme == .warmRoom {
                let window = CGRect(x: w * 0.64, y: h * 0.12, width: w * 0.23, height: h * 0.34)
                context.fill(Path(roundedRect: window, cornerRadius: 9 * unit), with: .color(Color(red: 0.57, green: 0.8, blue: 0.93)))
                context.fill(ellipse(0.78, 0.16, 0.045, 0.065), with: .color(theme.light))
                context.stroke(Path(roundedRect: window, cornerRadius: 9 * unit), with: .color(theme.fence), lineWidth: 6 * unit)
                var panes = Path()
                panes.move(to: point(0.755, 0.12))
                panes.addLine(to: point(0.755, 0.46))
                panes.move(to: point(0.64, 0.29))
                panes.addLine(to: point(0.87, 0.29))
                context.stroke(panes, with: .color(theme.fence), lineWidth: 4 * unit)
                context.fill(Path(CGRect(x: 0, y: h * 0.57, width: w, height: h * 0.43)), with: .color(theme.ground))
                var boards = Path()
                for row in 0...4 {
                    let y = 0.57 + CGFloat(row) * 0.11
                    boards.move(to: point(0, y))
                    boards.addLine(to: point(1, y))
                }
                for column in 0...5 {
                    let x = CGFloat(column) / 5
                    boards.move(to: point(0.5 + (x - 0.5) * 0.7, 0.57))
                    boards.addLine(to: point(x, 1))
                }
                context.stroke(boards, with: .color(theme.fence.opacity(0.24)), lineWidth: unit)
                context.fill(ellipse(0.18, 0.69, 0.64, 0.23), with: .color(Color(red: 0.91, green: 0.66, blue: 0.4).opacity(0.6)))
            } else {
                if theme.theme == .starryNight {
                    let stars: [(CGFloat, CGFloat)] = [(0.12, 0.12), (0.28, 0.26), (0.43, 0.09), (0.56, 0.2), (0.66, 0.07), (0.9, 0.16), (0.94, 0.4), (0.39, 0.4), (0.09, 0.44), (0.61, 0.38)]
                    for (index, star) in stars.enumerated() {
                        let radius = CGFloat(index.isMultiple(of: 3) ? 2 : 1) * unit
                        let center = point(star.0, star.1)
                        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.8)))
                    }
                }

                let sunSize = 40 * unit
                let sun = CGRect(x: w * 0.77 - sunSize / 2, y: h * 0.25 - sunSize / 2, width: sunSize, height: sunSize)
                context.fill(Path(ellipseIn: sun.insetBy(dx: -9 * unit, dy: -9 * unit)), with: .color(theme.light.opacity(0.1)))
                context.drawLayer { celestial in
                    celestial.fill(Path(ellipseIn: sun), with: .color(theme.light))
                    if theme.theme == .starryNight {
                        celestial.blendMode = .destinationOut
                        celestial.fill(Path(ellipseIn: sun.offsetBy(dx: 10 * unit, dy: -5 * unit)), with: .color(.black))
                    }
                }

                if theme.theme == .sunnyMeadow || theme.theme == .snowyCove {
                    for cloud in [(CGFloat(0.13), CGFloat(0.3), CGFloat(0.2)), (0.46, 0.15, 0.14), (0.83, 0.41, 0.16)] {
                        var shape = ellipse(cloud.0, cloud.1, cloud.2, 0.055)
                        shape.addPath(ellipse(cloud.0 + cloud.2 * 0.2, cloud.1 - 0.04, cloud.2 * 0.45, 0.09))
                        shape.addPath(ellipse(cloud.0 + cloud.2 * 0.51, cloud.1 - 0.018, cloud.2 * 0.35, 0.068))
                        context.fill(shape, with: .color(.white.opacity(0.85)))
                    }
                }

                if theme.theme == .snowyCove {
                    var mountains = Path()
                    mountains.move(to: point(0, 0.7))
                    for peak in [(CGFloat(0.15), CGFloat(0.35)), (0.31, 0.63), (0.49, 0.3), (0.75, 0.64), (0.9, 0.43), (1, 0.65)] {
                        mountains.addLine(to: point(peak.0, peak.1))
                    }
                    mountains.closeSubpath()
                    context.fill(mountains, with: .color(Color(red: 0.66, green: 0.81, blue: 0.88)))
                }

                var farHill = Path()
                farHill.move(to: point(0, 0.62))
                farHill.addQuadCurve(to: point(1, 0.7), control: point(0.4, 0.37))
                farHill.addLine(to: point(1, 1))
                farHill.addLine(to: point(0, 1))
                farHill.closeSubpath()
                context.fill(farHill, with: .color(theme.ground))
                var nearHill = Path()
                nearHill.move(to: point(0, 0.86))
                nearHill.addQuadCurve(to: point(1, 0.62), control: point(0.54, 0.55))
                nearHill.addLine(to: point(1, 1))
                nearHill.addLine(to: point(0, 1))
                nearHill.closeSubpath()
                context.fill(nearHill, with: .color(theme.ground))
                context.fill(nearHill, with: .color(theme.theme == .starryNight ? .black.opacity(0.14) : .white.opacity(0.2)))

                if theme.theme == .sunnyMeadow || theme.theme == .starryNight {
                    for index in 0..<16 {
                        let x = CGFloat((index * 67 + 17) % 360) / 360
                        let y = 0.78 + CGFloat((index * 29) % 19) / 100
                        var grass = Path()
                        grass.move(to: point(x - 0.007, y - 0.018))
                        grass.addLine(to: point(x, y))
                        grass.addLine(to: point(x + 0.006, y - 0.026))
                        context.stroke(grass, with: .color(theme.fence.opacity(0.4)), lineWidth: unit)
                        if theme.theme == .sunnyMeadow && index.isMultiple(of: 3) {
                            context.fill(ellipse(x, y - 0.031, 0.009, 0.014), with: .color(index.isMultiple(of: 2) ? .white : theme.light))
                        }
                    }
                }
            }
        }
    }
}

private struct HabitatThemeSwatch: View {
    let theme: HabitatThemePresentation

    var body: some View {
        HabitatThemeBackdrop(theme: theme)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct HabitatResidentStatusRow: View {
    let pet: PetProfile
    let vitals: PetVitals

    var body: some View {
        HStack(spacing: 12) {
            PetArtwork(
                species: pet.species,
                coat: pet.coat,
                customColor: pet.customColor,
                breed: pet.resolvedBreed,
                pose: .idle,
                direction: .right,
                step: 0,
                animatesMotion: false
            )
            .frame(width: 46, height: 42)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(pet.name).font(.subheadline.bold()).lineLimit(1)
                    Spacer()
                    Text(overallStatus)
                        .font(.caption2.bold())
                        .foregroundStyle(statusColor)
                }
                HStack(spacing: 10) {
                    vital("fork.knife", value: vitals.fullness, tint: PetDesign.accent)
                    vital("heart.fill", value: vitals.happiness, tint: PetDesign.accent)
                    vital("bolt.fill", value: vitals.energy, tint: PetDesign.accent)
                }
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pet.name), \(overallStatus)")
        .accessibilityValue("Fullness \(percent(vitals.fullness)), happiness \(percent(vitals.happiness)), energy \(percent(vitals.energy))")
    }

    private func vital(_ symbol: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            ProgressView(value: value)
                .tint(tint)
                .frame(minWidth: 34)
        }
        .accessibilityHidden(true)
    }

    private var overallStatus: String {
        let minimum = min(vitals.fullness, vitals.happiness, vitals.energy)
        if minimum < 0.2 { return String(localized: "Needs care") }
        if vitals.energy < 0.38 { return String(localized: "Sleepy") }
        if vitals.happiness > 0.75 { return String(localized: "Happy") }
        return String(localized: "Calm")
    }

    private var statusColor: Color {
        let minimum = min(vitals.fullness, vitals.happiness, vitals.energy)
        if minimum < 0.2 { return .red }
        if vitals.energy < 0.38 { return .orange }
        return PetDesign.secondary
    }

    private func percent(_ value: Double) -> String {
        String(localized: "\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

private struct HabitatStatusDots: View {
    let vitals: PetVitals

    var body: some View {
        HStack(spacing: 3) {
            dot(value: vitals.fullness, color: .orange)
            dot(value: vitals.happiness, color: .pink)
            dot(value: vitals.energy, color: .cyan)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(.black.opacity(0.2), in: Capsule())
        .accessibilityHidden(true)
    }

    private func dot(value: Double, color: Color) -> some View {
        Circle()
            .fill(value < 0.2 ? Color.red : color)
            .frame(width: 5, height: 5)
            .opacity(0.45 + min(max(value, 0), 1) * 0.55)
    }
}

/// Presentation-only colors. The shared enum preserves stable saved theme IDs.
private struct HabitatThemePresentation: Identifiable {
    var id: HabitatTheme { theme }
    let theme: HabitatTheme
    let name: LocalizedStringKey
    let symbol: String
    let sky: [Color]
    let ground: Color
    let fence: Color
    let light: Color
    let foreground: Color

    static let options: [HabitatThemePresentation] = [
        HabitatThemePresentation(
            theme: .meadow, name: "Meadow", symbol: "leaf",
            sky: [PetDesign.sky, PetDesign.horizon], ground: PetDesign.hill,
            fence: PetDesign.separator, light: PetDesign.light, foreground: PetDesign.ink
        ),
        HabitatThemePresentation(
            theme: .moonlitGarden, name: "Starlight", symbol: "moon.stars",
            sky: [PetDesign.adaptive(0xE3E7F0, 0x272D3D), PetDesign.adaptive(0xD9DFEA, 0x374054)],
            ground: PetDesign.adaptive(0xBCC6D7, 0x535F75), fence: PetDesign.separator,
            light: PetDesign.adaptive(0xF7F8FC, 0xAFBACD), foreground: PetDesign.ink
        ),
        HabitatThemePresentation(
            theme: .cozyRoom, name: "Cozy room", symbol: "sofa",
            sky: [PetDesign.adaptive(0xF0ECE8, 0x35312E), PetDesign.adaptive(0xE9E2DC, 0x433C37)],
            ground: PetDesign.adaptive(0xD5C9BF, 0x655B53), fence: PetDesign.separator,
            light: PetDesign.adaptive(0xE4D9C8, 0xAD9B84), foreground: PetDesign.ink
        ),
        HabitatThemePresentation(
            theme: .arcticCove, name: "Arctic cove", symbol: "snowflake",
            sky: [PetDesign.adaptive(0xEFF5F8, 0x2A3540), PetDesign.adaptive(0xE3EDF2, 0x364755)],
            ground: PetDesign.adaptive(0xCEDFE8, 0x5A7181), fence: PetDesign.separator,
            light: PetDesign.adaptive(0xDBE8EF, 0xA0B3C1), foreground: PetDesign.ink
        ),
        HabitatThemePresentation(
            theme: .desertCamp, name: "Desert camp", symbol: "sun.horizon",
            sky: [PetDesign.adaptive(0xF3EEE8, 0x39312C), PetDesign.adaptive(0xEDE3D7, 0x4B4035)],
            ground: PetDesign.adaptive(0xD8C6AE, 0x746451), fence: PetDesign.separator,
            light: PetDesign.adaptive(0xE8D8BC, 0xB9A17D), foreground: PetDesign.ink
        ),
        HabitatThemePresentation(
            theme: .sunnyMeadow, name: "Sunny meadow", symbol: "sun.max",
            sky: [Color(red: 0.28, green: 0.67, blue: 0.94), Color(red: 0.76, green: 0.92, blue: 0.98)],
            ground: Color(red: 0.29, green: 0.62, blue: 0.3), fence: Color(red: 0.13, green: 0.38, blue: 0.16),
            light: Color(red: 1, green: 0.89, blue: 0.39), foreground: .white
        ),
        HabitatThemePresentation(
            theme: .starryNight, name: "Starry night", symbol: "moon.stars",
            sky: [Color(red: 0.07, green: 0.09, blue: 0.24), Color(red: 0.2, green: 0.22, blue: 0.46)],
            ground: Color(red: 0.11, green: 0.28, blue: 0.25), fence: Color(red: 0.61, green: 0.73, blue: 0.66),
            light: Color(red: 0.9, green: 0.94, blue: 1), foreground: .white
        ),
        HabitatThemePresentation(
            theme: .warmRoom, name: "Warm cottage", symbol: "house",
            sky: [Color(red: 0.91, green: 0.57, blue: 0.39), Color(red: 0.98, green: 0.8, blue: 0.58)],
            ground: Color(red: 0.63, green: 0.39, blue: 0.24), fence: Color(red: 0.42, green: 0.24, blue: 0.12),
            light: Color(red: 1, green: 0.88, blue: 0.48), foreground: Color(red: 0.25, green: 0.14, blue: 0.08)
        ),
        HabitatThemePresentation(
            theme: .snowyCove, name: "Snowy cove", symbol: "snowflake",
            sky: [Color(red: 0.4, green: 0.7, blue: 0.91), Color(red: 0.84, green: 0.93, blue: 0.97)],
            ground: Color(red: 0.82, green: 0.91, blue: 0.95), fence: Color(red: 0.48, green: 0.58, blue: 0.65),
            light: .white, foreground: Color(red: 0.08, green: 0.18, blue: 0.26)
        ),
        HabitatThemePresentation(
            theme: .sunsetDunes, name: "Sunset dunes", symbol: "sun.horizon",
            sky: [Color(red: 0.88, green: 0.39, blue: 0.35), Color(red: 0.99, green: 0.79, blue: 0.47)],
            ground: Color(red: 0.72, green: 0.43, blue: 0.23), fence: Color(red: 0.37, green: 0.2, blue: 0.11),
            light: Color(red: 1, green: 0.9, blue: 0.62), foreground: .white
        )
    ]
}

#if DEBUG
private struct HabitatEditorPreviewContainer: View {
    @State private var selectedPetIDs: [UUID]
    @State private var theme: HabitatTheme = .meadow
    private let pets: [PetProfile]

    init() {
        let dog = PetProfile.starter
        let cat = PetProfile(
            id: UUID(),
            name: "Mochi",
            species: .cat,
            coat: .cloud,
            createdAt: .now
        )
        let parrot = PetProfile(
            id: UUID(),
            name: "Kiwi",
            species: .parrot,
            coat: .sunrise,
            createdAt: .now
        )
        pets = [dog, cat, parrot]
        _selectedPetIDs = State(initialValue: [dog.id, cat.id])
    }

    var body: some View {
        HabitatEditorView(
            controller: PetSessionController(store: InMemoryPetStore(), arcadeStore: InMemoryArcadeStore()),
            pets: pets,
            selectedPetIDs: $selectedPetIDs,
            selectedTheme: $theme
        )
    }
}

#Preview("Редактор домика") {
    HabitatEditorPreviewContainer()
}
#endif
