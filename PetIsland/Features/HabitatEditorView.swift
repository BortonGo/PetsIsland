import SwiftUI
import UIKit

/// A controller-independent editor for the pets shown in the enclosure.
///
struct HabitatEditorView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pets: [PetProfile]
    @Binding var selectedPetIDs: [UUID]
    @Binding var selectedTheme: HabitatTheme
    var vitalsByPetID: [UUID: PetVitals]
    var maximumPets: Int
    var onSave: () -> Bool
    @State private var saveFailed = false

    init(
        pets: [PetProfile],
        selectedPetIDs: Binding<[UUID]>,
        selectedTheme: Binding<HabitatTheme>,
        vitalsByPetID: [UUID: PetVitals] = [:],
        maximumPets: Int = 3,
        onSave: @escaping () -> Bool = { true }
    ) {
        self.pets = pets
        _selectedPetIDs = selectedPetIDs
        _selectedTheme = selectedTheme
        self.vitalsByPetID = vitalsByPetID
        self.maximumPets = max(maximumPets, 1)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    habitatPreview
                    themePicker
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
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
    }

    private var habitatPreview: some View {
        HabitatEditorCanvas(
            theme: selectedTheme,
            pets: selectedPets,
            vitalsByPetID: vitalsByPetID
        )
        .frame(height: 236)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your enclosure")
                    .font(.headline)
                Text("\(selectedPets.count)/\(maximumPets) residents")
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

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
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
                Text(pet.species.displayName)
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
        .disabled((selectionIsFull && !isSelected) || cannotRemoveLast)
        .opacity((selectionIsFull && !isSelected) ? 0.48 : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(cannotRemoveLast ? "At least one resident is required" : "")
    }

    @ViewBuilder
    private var statusPanel: some View {
        if !selectedPets.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "Status",
                    subtitle: "Visible wellbeing of every resident",
                    symbol: "heart.text.square.fill"
                )

                VStack(spacing: 0) {
                    ForEach(Array(selectedPets.enumerated()), id: \.element.id) { index, pet in
                        HabitatResidentStatusRow(
                            pet: pet,
                            vitals: vitals(for: pet)
                        )
                        if index < selectedPets.count - 1 {
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

    private func vitals(for pet: PetProfile) -> PetVitals {
        vitalsByPetID[pet.id] ?? PetVitals()
    }

    private func toggleSelection(of id: UUID) {
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
    @PetReduceMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var motion = HabitatMotionSimulation()
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HabitatThemeBackdrop(theme: palette)
                if pets.isEmpty {
                    ContentUnavailableView("Empty enclosure", systemImage: "pawprint")
                        .foregroundStyle(palette.foreground)
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
                    .zIndex(Double(actor.position.y))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(actor.profile.name)
                    .accessibilityValue(status(for: actor.pose))
                    .accessibilityAction(named: Text("Stroke pet")) { motion.pet(actor.id) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onAppear {
                isVisible = true
                motion.configure(pets: pets, size: proxy.size, petScale: petScale, vitals: vitalsByPetID)
                motion.start(reduceMotion: reduceMotion, active: scenePhase == .active)
            }
            .onChange(of: pets) { _, value in motion.configure(pets: value, size: proxy.size, petScale: petScale, vitals: vitalsByPetID) }
            .onChange(of: vitalsByPetID) { _, value in motion.configure(pets: pets, size: proxy.size, petScale: petScale, vitals: value) }
            .onChange(of: proxy.size) { _, value in motion.configure(pets: pets, size: value, petScale: petScale, vitals: vitalsByPetID) }
        }
        .onDisappear { isVisible = false; motion.stop() }
        .onChange(of: reduceMotion) { _, value in motion.start(reduceMotion: value, active: isVisible && scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in motion.start(reduceMotion: reduceMotion, active: isVisible && phase == .active) }
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
    struct Actor: Identifiable {
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

        mutating func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
    }

    @Published private(set) var actors: [Actor] = []
    private(set) var size = CGSize.zero
    private var petWidth: CGFloat = 78
    private var vitals: [UUID: PetVitals] = [:]
    private var reduced = false
    private var clock = 0.0
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?

    @MainActor
    private final class Target: NSObject {
        weak var simulation: HabitatMotionSimulation?
        init(_ simulation: HabitatMotionSimulation) { self.simulation = simulation }
        @objc func tick(_ link: CADisplayLink) { simulation?.tick(link) }
    }

    func configure(pets: [PetProfile], size newSize: CGSize, petScale: CGFloat = 1, vitals: [UUID: PetVitals] = [:]) {
        guard newSize.width > 1, newSize.height > 1 else { return }
        self.vitals = vitals
        let previousSize = size
        size = newSize
        petWidth = min(size.width * 0.24, 78) * petScale
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
    }

    func start(reduceMotion: Bool, active: Bool) {
        reduced = reduceMotion
        stop()
        guard active else { return }
        if reduceMotion {
            actors = actors.map { actor in
                var actor = actor
                actor.velocity = .zero
                actor.pose = .idle
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
        actors[index].velocity = .zero
        actors[index].travelling = false
        actors[index].turning = 0
        actors[index].facing = actors[index].facing < 0 ? -1 : 1
        actors[index].pose = .play
        actors[index].waiting = 2.5
        actors[index].affection = reduced ? 0 : 1.5
    }

    func advance(by rawDelta: TimeInterval) {
        guard !reduced, rawDelta.isFinite, rawDelta > 0, size.width > 1 else { return }
        let dt = min(rawDelta, 1.0 / 15)
        clock += dt
        let previous = actors
        var next = actors
        for index in next.indices {
            var actor = next[index]
            actor.affection = max(actor.affection - dt, 0)
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
