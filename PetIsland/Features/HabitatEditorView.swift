import SwiftUI
import UIKit

/// Drafts the theme and residents; furniture placement is saved immediately.
struct HabitatEditorView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
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
    @State private var initialPetIDs: [UUID]
    @State private var initialTheme: HabitatTheme
    @State private var confirmsDiscard = false

    private var hasChanges: Bool {
        selectedPetIDs != initialPetIDs || selectedTheme != initialTheme
    }

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
        _initialPetIDs = State(initialValue: selectedPetIDs.wrappedValue)
        _initialTheme = State(initialValue: selectedTheme.wrappedValue)
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
                    if dynamicTypeSize.isAccessibilitySize { saveStatus }
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if hasChanges { confirmsDiscard = true }
                        else { dismiss() }
                    }
                    .accessibilityIdentifier("habitat.close")
                }
            }
            .alert("Discard enclosure changes?", isPresented: $confirmsDiscard) {
                Button("Keep editing", role: .cancel) { }
                Button("Discard changes", role: .destructive) {
                    selectedPetIDs = initialPetIDs
                    selectedTheme = initialTheme
                    dismiss()
                }
            } message: {
                Text("The background and resident selection will not be saved. Furniture changes are already saved and will stay.")
            }
            .sheet(isPresented: $showsFurniture) {
                HabitatFurnitureView(controller: controller)
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    private var habitatPreview: some View {
        HabitatEditorCanvas(
            theme: selectedTheme,
            pets: presentPets,
            vitalsByPetID: vitalsByPetID,
            hasCozyBox: hasCozyBox,
            furniture: controller.habitat.configuration.furniture,
            isAnimationEnabled: !showsFurniture
        )
        .frame(height: 236)
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your enclosure")
                    .font(.headline)
                Text("Selected: \(selectedPets.count) of \(maximumPets)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("habitat.selectionCount")
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
                    .font(.system(size: 22))
                    .foregroundStyle(PetDesign.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Furniture").font(.subheadline.weight(.semibold))
                    Text(controller.habitat.configuration.furniture.isEmpty
                         ? String(localized: "Choose an item")
                         : controller.habitat.configuration.furniture.map { $0.item.title }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Furniture changes save immediately.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PetDesign.secondary)
                    .accessibilityHidden(true)
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
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityIdentifier("habitat.theme.\(theme.theme.rawValue)")
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
            if selectedPets.count >= maximumPets, pets.count > selectedPets.count {
                Text("To choose another pet, first remove a resident.")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("habitat.capacityHint")
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
        let reason: String? = isAway ? (isSelected ? String(localized: "A space is kept for your exploring pet.")
                                        : String(localized: "Available after the walk"))
            : cannotRemoveLast ? String(localized: "At least one resident is required")
            : selectionIsFull && !isSelected ? String(localized: "No free places") : nil

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
                        animatesMotion: false, accessory: pet.outfit?.headwear
                    )
                    .frame(width: 66, height: 56)

                    Image(systemName: isAway ? "clock.fill" : isSelected ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? PetDesign.onAccent : PetDesign.accent,
                            isSelected ? PetDesign.accent : PetDesign.surface
                        )
                        .offset(x: 5, y: -3)
                        .accessibilityHidden(true)
                }

                Text(pet.name)
                    .font(.caption.bold())
                    .foregroundStyle(PetDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if let reason { Text(reason) }
                    else { Text(pet.species.displayName) }
                }
                    .font(.caption2)
                    .foregroundStyle(PetDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
        .buttonStyle(ResidentChoiceStyle())
        .disabled(isAway || (selectionIsFull && !isSelected) || cannotRemoveLast)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(Text(reason ?? ""))
        .accessibilityIdentifier("habitat.resident.\(pet.id.uuidString)")
    }

    /// Keep the reason readable even when this choice cannot be tapped.
    private struct ResidentChoiceStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
        }
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

    private var saveStatus: some View {
        Text(hasChanges ? "Unsaved background or residents" : "Background and residents are saved")
            .font(.caption.weight(.medium))
            .foregroundStyle(PetDesign.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("habitat.saveStatus")
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            if !dynamicTypeSize.isAccessibilitySize { saveStatus }
            Button {
                guard !controller.isBusy else { return }
                if hasChanges {
                    if onSave() {
                        initialPetIDs = selectedPetIDs
                        initialTheme = selectedTheme
                    } else {
                        controller.alertMessage = nil
                        saveFailed = true
                    }
                } else { dismiss() }
            } label: {
                Text(hasChanges ? "Save enclosure" : "Done")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .controlSize(.large)
            .disabled(controller.isBusy || (hasChanges && selectedPets.isEmpty))
            .accessibilityIdentifier("habitat.save")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habitat.saveBar")
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
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
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
    var furniture: [HabitatFurniturePlacement]? = nil
    var isAnimationEnabled = true
    @PetReduceMotion private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var power = PetPowerMonitor.shared
    @StateObject private var motion = HabitatMotionSimulation()
    @State private var isVisible = false
    @State private var isInViewport = false

    init(theme: HabitatTheme, pets: [PetProfile], vitalsByPetID: [UUID: PetVitals], petScale: CGFloat = 1,
         hasCozyBox: Bool = false, furniture: [HabitatFurniturePlacement]? = nil, isAnimationEnabled: Bool = true,
         motion: HabitatMotionSimulation? = nil) {
        self.theme = theme
        self.pets = pets
        self.vitalsByPetID = vitalsByPetID
        self.petScale = petScale
        self.hasCozyBox = hasCozyBox
        self.furniture = furniture
        self.isAnimationEnabled = isAnimationEnabled
        _motion = StateObject(wrappedValue: motion ?? HabitatMotionSimulation())
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HabitatThemeBackdrop(theme: palette)
                    .equatable()
                if pets.isEmpty {
                    VStack(spacing: 8) {
                        if motion.furniture.isEmpty {
                            Image(systemName: "pawprint")
                                .font(.system(size: 28))
                                .accessibilityHidden(true)
                        }
                        Text("Empty enclosure")
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(palette.foreground)
                    .frame(width: max(0, proxy.size.width - 40))
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.44)
                }
                if motion.hasCozyBox {
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
                ForEach(motion.furniture.filter { $0.item != .cozyBox }) { placement in
                    furnitureArtwork(placement, layer: .back)
                        .zIndex(motion.furnitureDepth(placement) - 0.2)
                    furnitureArtwork(placement, layer: .front)
                        .zIndex(motion.furnitureDepth(placement) + 0.2)
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
                                   animatesMotion: false, usesNaturalGait: true, accessory: actor.profile.outfit?.headwear)
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
                            ? boxDepth : motion.renderDepth(for: actor))
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("habitat.pet.\(actor.id.uuidString)")
                    .accessibilityLabel(actor.profile.name)
                    .accessibilityValue(motion.encounterStatus(for: actor.id) ?? status(for: actor.pose))
                    .accessibilityAction(named: Text("Stroke pet")) { motion.pet(actor.id) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onAppear {
                isVisible = true
                configure(in: proxy.size)
                motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && isInViewport && scenePhase == .active, powerPolicy: power.policy)
            }
            .onChange(of: pets) { previous, value in
                configure(in: proxy.size)
                if previous.isEmpty && !value.isEmpty {
                    motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && isVisible && isInViewport && scenePhase == .active, powerPolicy: power.policy)
                }
            }
            .onChange(of: vitalsByPetID) { _, _ in configure(in: proxy.size) }
            .onChange(of: proxy.size) { _, value in configure(in: value) }
            .onChange(of: hasCozyBox) { _, _ in configure(in: proxy.size) }
            .onChange(of: furniture) { _, _ in configure(in: proxy.size) }
            .onChange(of: petScale) { _, _ in configure(in: proxy.size) }
        }
        .onDisappear { isVisible = false; motion.stop() }
        .onPetViewportVisibilityChange { value in
            isInViewport = value
            motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && isVisible && value && scenePhase == .active, powerPolicy: power.policy)
        }
        .onChange(of: reduceMotion) { _, value in motion.start(reduceMotion: value, active: isAnimationEnabled && isVisible && isInViewport && scenePhase == .active, powerPolicy: power.policy) }
        .onChange(of: scenePhase) { _, phase in motion.start(reduceMotion: reduceMotion, active: isAnimationEnabled && isVisible && isInViewport && phase == .active, powerPolicy: power.policy) }
        .onChange(of: isAnimationEnabled) { _, value in motion.start(reduceMotion: reduceMotion, active: value && isVisible && isInViewport && scenePhase == .active, powerPolicy: power.policy) }
        .onChange(of: power.policy) { _, value in motion.setPowerPolicy(value) }
    }

    private func configure(in size: CGSize) {
        motion.configure(pets: pets, size: size, petScale: petScale,
                         vitals: vitalsByPetID, hasCozyBox: hasCozyBox, furniture: furniture)
    }

    private func furnitureArtwork(_ placement: HabitatFurniturePlacement, layer: HabitatItemArtwork.Layer) -> some View {
        let frame = motion.furnitureFrame(placement)
        let visit = motion.furnitureVisits[placement.slot]
        let active = visit?.phase == .using
        return Button {
            if let visit { motion.pet(visit.petID) }
            else { _ = motion.requestFurniture(placement.slot) }
        } label: {
            HabitatItemArtwork(item: placement.item, layer: layer,
                               activity: visit?.elapsed ?? 0, active: active)
                .frame(width: frame.width, height: frame.height)
                .frame(width: max(44, frame.width), height: max(44, frame.height))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(layer == .front)
        .accessibilityHidden(layer == .back)
        .accessibilityLabel(placement.item.title)
        .accessibilityValue(visit != nil ? Text("In use") : Text("Available"))
        .accessibilityHint(visit == nil ? Text("Invite a pet") : Text("Stroke pet"))
        .disabled(!pets.contains { placement.item.supports($0.species) })
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

        /// Timers, random seeds and steering still advance while a pet rests,
        /// but none of them requires a new SwiftUI render of the enclosure.
        func hasSameAppearance(as other: Actor) -> Bool {
            id == other.id && profile == other.profile && position == other.position
                && pose == other.pose && facing == other.facing && step == other.step
                && affection == other.affection && visualOffsetY == other.visualOffsetY
        }

        mutating func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64.max >> 11)
        }
    }

    private(set) var actors: [Actor] = [] {
        willSet {
            if !actors.elementsEqual(newValue, by: { $0.hasSameAppearance(as: $1) }) {
                objectWillChange.send()
            }
        }
    }
    @Published private(set) var boxOccupantID: UUID?
    @Published private(set) var boxPhase: CozyBoxPhase = .empty
    enum FurniturePhase: String { case approaching, settling, using, leaving }
    struct FurnitureVisit: Equatable {
        let placement: HabitatFurniturePlacement
        let petID: UUID
        var phase: FurniturePhase = .approaching
        var elapsed = 0.0
        var origin: CGPoint = .zero
        var originOffset: CGFloat = 0
        var exitPoint: CGPoint = .zero

        func hasSameAppearance(as other: Self) -> Bool {
            guard placement == other.placement, petID == other.petID, phase == other.phase else { return false }
            // These four objects animate their own artwork while occupied.
            // Bed/stone rest timers and approach bookkeeping are invisible.
            let animated = phase == .using && [.leafNest, .birdPerch, .splashBath, .playBall].contains(placement.item)
            return !animated || elapsed == other.elapsed
        }
    }
    private(set) var furnitureVisits: [HabitatFurnitureSlot: FurnitureVisit] = [:] {
        willSet {
            if furnitureVisits.count != newValue.count || !furnitureVisits.allSatisfy({ slot, visit in
                newValue[slot].map { visit.hasSameAppearance(as: $0) } ?? false
            }) { objectWillChange.send() }
        }
    }
    private(set) var furniture: [HabitatFurniturePlacement] = []
    private var nextFurnitureVisit: [HabitatFurnitureSlot: Double] = [:]
    enum EncounterPhase: String, CaseIterable { case approaching, greeting, resting }
    struct Encounter: Equatable {
        let leftID: UUID
        let rightID: UUID
        let leftTarget: CGPoint
        let rightTarget: CGPoint
        let napsTogether: Bool
        var phase: EncounterPhase = .approaching
        var elapsed = 0.0

        func contains(_ id: UUID) -> Bool { id == leftID || id == rightID }
        func target(for id: UUID) -> CGPoint { id == leftID ? leftTarget : rightTarget }
    }
    private(set) var encounter: Encounter? {
        willSet {
            // The phase is exposed to VoiceOver; its timer is not a drawn frame.
            if encounter?.phase != newValue?.phase { objectWillChange.send() }
        }
    }
    private var nextEncounter = 8.0
    private var encounterCooldowns: [UUID: Double] = [:]
    private var encounterSeed: UInt64 = 0x4845_4C4C_4F21
    private(set) var boxRestPose: PetPose = .sleep
    private(set) var size = CGSize.zero
    private(set) var hasCozyBox = false
    private var petWidth: CGFloat = 78
    private var vitals: [UUID: PetVitals] = [:]
    private var reduced = false
    private var clock = 0.0
    private var displayLink: CADisplayLink?
    private var powerPolicy: PetAnimationPowerPolicy = .normal
    var preferredFramesPerSecond: Int? { displayLink.flatMap { $0.preferredFrameRateRange.preferred.map(Int.init) } }
    private var lastTimestamp: CFTimeInterval?
    var isRunning: Bool { displayLink != nil }
    var isBoxOccupied: Bool { boxOccupantID != nil }
    var boxRenderDepth: CGFloat { boxCenter.y }
    var boxSize: CGSize {
        furnitureFrame(boxPlacement).size
    }
    /// The illustrated box floor (94% down its image), rather than its frame center.
    var boxPosition: CGPoint {
        guard size.width > 1, size.height > 1 else { return .zero }
        return HabitatFurnitureLayout.ground(for: boxPlacement.slot, in: size)
    }
    private var boxPlacement: HabitatFurniturePlacement {
        furniture.first { $0.item == .cozyBox } ?? .init(item: .cozyBox, slot: .right)
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
                   vitals: [UUID: PetVitals] = [:], hasCozyBox: Bool = false,
                   furniture: [HabitatFurniturePlacement]? = nil) {
        guard newSize.width.isFinite, newSize.height.isFinite,
              newSize.width > 1, newSize.height > 1, petScale.isFinite, petScale > 0 else { return }
        self.vitals = vitals
        let previousSize = size
        let previousPetWidth = petWidth
        let previousFurniture = self.furniture
        let wasBoxEnabled = self.hasCozyBox
        let oldBoxSlot = boxPlacement.slot
        let placements = PetHabitatState.normalizedFurniture(furniture ?? (hasCozyBox ? [.init(item: .cozyBox, slot: .right)] : []))
        if previousSize != newSize || self.furniture != placements || previousPetWidth != min(newSize.width * 0.24, 78) * petScale {
            objectWillChange.send()
        }
        size = newSize
        petWidth = min(size.width * 0.24, 78) * petScale
        self.furniture = placements
        self.hasCozyBox = self.furniture.contains { $0.item == .cozyBox }
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
        if !self.hasCozyBox || oldBoxSlot != boxPlacement.slot || !actors.contains(where: { $0.id == boxOccupantID && $0.profile.species == .cat }) {
            cancelBoxVisit()
        } else if previousSize != size || previousPetWidth != petWidth {
            retargetBoxAfterResize()
        }
        if self.hasCozyBox && !wasBoxEnabled { scheduleNextBoxVisit() }
        if !self.hasCozyBox { nextBoxVisit = .infinity }
        reconcileFurnitureVisits(resized: previousSize != size || previousPetWidth != petWidth)
        if let encounter, previousSize != size || previousPetWidth != petWidth || previousFurniture != placements
            || !actors.contains(where: { $0.id == encounter.leftID })
            || !actors.contains(where: { $0.id == encounter.rightID }) {
            endEncounter()
        }
        encounterCooldowns = encounterCooldowns.filter { id, _ in actors.contains { $0.id == id } }
        if actors.isEmpty { stop() }
    }

    func start(reduceMotion: Bool, active: Bool, powerPolicy: PetAnimationPowerPolicy = .normal) {
        setPowerPolicy(powerPolicy)
        reduced = reduceMotion
        guard active, !actors.isEmpty else { stop(); return }
        if reduceMotion {
            stop()
            endEncounter()
            if boxPhase != .resting { cancelBoxVisit() }
            for slot in Array(furnitureVisits.keys) { cancelFurnitureVisit(slot) }
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
        // Visibility and scene activation can arrive together. Reusing the
        // current link avoids throwing away its timestamp and a display frame.
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: Target(self), selector: #selector(Target.tick(_:)))
        let rate = Float(powerPolicy.framesPerSecond)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func setPowerPolicy(_ value: PetAnimationPowerPolicy) {
        powerPolicy = value
        let rate = Float(value.framesPerSecond)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: rate, preferred: rate)
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
        if encounter?.contains(id) == true { endEncounter() }
        if let visit = furnitureVisits.values.first(where: { $0.petID == id }) {
            if reduced || visit.phase == .approaching { cancelFurnitureVisit(visit.placement.slot) }
            else { beginFurnitureExit(visit.placement.slot, actor: actors[index]); return }
        }
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
    func requestCatToBox(_ petID: UUID? = nil, interruptsEncounter: Bool = true) -> Bool {
        guard hasCozyBox, boxOccupantID == nil, size.width > 1 else { return false }
        let candidates = actors.indices.filter { index in
            actors[index].profile.species == .cat && !furnitureVisits.values.contains(where: { $0.petID == actors[index].id })
                && (petID == nil || actors[index].id == petID)
                && (interruptsEncounter || encounter?.contains(actors[index].id) != true)
        }
        guard let index = candidates.min(by: {
            hypot(actors[$0].position.x - boxCenter.x, actors[$0].position.y - boxCenter.y)
                < hypot(actors[$1].position.x - boxCenter.x, actors[$1].position.y - boxCenter.y)
        }) else { return false }
        if encounter?.contains(actors[index].id) == true { endEncounter() }
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
        requestAmbientFurnitureVisits()
        if hasCozyBox, boxOccupantID == nil, clock >= nextBoxVisit {
            let nearby = actors.filter {
                $0.profile.species == .cat && encounter?.contains($0.id) != true
                    && hypot($0.position.x - boxCenter.x, $0.position.y - boxCenter.y) <= petWidth * 1.35
            }.min {
                hypot($0.position.x - boxCenter.x, $0.position.y - boxCenter.y)
                    < hypot($1.position.x - boxCenter.x, $1.position.y - boxCenter.y)
            }
            if let nearby, requestCatToBox(nearby.id, interruptsEncounter: false) { }
            else { nextBoxVisit = clock + 2 }
        }
        requestAmbientEncounter()
        advanceEncounterClock(by: dt)
        let previous = actors
        var next = actors
        for index in next.indices {
            var actor = next[index]
            actor.affection = max(actor.affection - dt, 0)
            if let encounter, encounter.contains(actor.id) {
                advanceEncounterActor(&actor, encounter: encounter, neighbours: previous, by: dt)
                updateAnimationFrame(for: &actor)
                next[index] = actor
                continue
            }
            if let visit = furnitureVisits.values.first(where: { $0.petID == actor.id }) {
                advanceFurnitureVisit(visit.placement.slot, actor: &actor, by: dt)
                updateAnimationFrame(for: &actor)
                next[index] = actor
                continue
            }
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
                avoidFurniture(for: &actor)
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
                let stride = petWidth * PetAnimationLibrary.enclosureStrideRatio(
                    for: actor.profile.species, breed: actor.profile.resolvedBreed, pose: actor.pose)
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
            if furnitureBlocks(candidate) { continue }
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


extension HabitatMotionSimulation {
    func furnitureFrame(_ placement: HabitatFurniturePlacement) -> CGRect {
        HabitatFurnitureLayout.frame(for: placement, in: size, petWidth: petWidth)
    }

    func furnitureDepth(_ placement: HabitatFurniturePlacement) -> Double {
        Double(HabitatFurnitureLayout.ground(for: placement.slot, in: size).y - petWidth * 72 / 220)
    }

    func renderDepth(for actor: Actor) -> Double {
        if let visit = furnitureVisits.values.first(where: { $0.petID == actor.id && $0.phase != .approaching }) {
            return furnitureDepth(visit.placement)
        }
        return Double(actor.position.y)
    }

    private func furnitureCenter(_ placement: HabitatFurniturePlacement) -> CGPoint {
        let floorSlot: HabitatFurnitureSlot = placement.slot == .perch ? .right : placement.slot
        let ground = HabitatFurnitureLayout.ground(for: floorSlot, in: size)
        let side: CGFloat = placement.slot == .left ? 1 : -1
        return bounded(CGPoint(x: ground.x + (placement.item == .playBall ? side * petWidth * 0.42 : 0),
                               y: ground.y - petWidth * 72 / 220))
    }

    private func furnitureApproach(_ placement: HabitatFurniturePlacement) -> CGPoint {
        let center = furnitureCenter(placement)
        return bounded(CGPoint(x: center.x, y: center.y + petWidth * 0.48))
    }

    private func furnitureRestOffset(_ placement: HabitatFurniturePlacement) -> CGFloat {
        let height = furnitureFrame(placement).height
        switch placement.item {
        case .birdPerch:
            return HabitatFurnitureLayout.ground(for: .perch, in: size).y
                - HabitatFurnitureLayout.ground(for: .right, in: size).y - height * 0.08
        case .softBed: return -height * 0.48
        case .warmStone: return -height * 0.64
        case .leafNest, .splashBath: return -height * 0.20
        case .cozyBox, .playBall: return 0
        }
    }

    @discardableResult
    func requestFurniture(_ slot: HabitatFurnitureSlot, petID: UUID? = nil, interruptsEncounter: Bool = true) -> Bool {
        guard let placement = furniture.first(where: { $0.slot == slot }), size.width > 1 else { return false }
        if placement.item == .cozyBox { return requestCatToBox(petID, interruptsEncounter: interruptsEncounter) }
        guard furnitureVisits[slot] == nil else { return false }
        let target = furnitureApproach(placement)
        let candidates = actors.indices.filter { index in
            let actor = actors[index]
            return placement.item.supports(actor.profile.species) && actor.id != boxOccupantID
                && (petID == nil || actor.id == petID)
                && !furnitureVisits.values.contains(where: { $0.petID == actor.id })
                && (interruptsEncounter || encounter?.contains(actor.id) != true)
        }
        guard let index = candidates.min(by: {
            hypot(actors[$0].position.x - target.x, actors[$0].position.y - target.y)
                < hypot(actors[$1].position.x - target.x, actors[$1].position.y - target.y)
        }) else { return false }
        if encounter?.contains(actors[index].id) == true { endEncounter() }
        // Reserve synchronously on the main actor, before the first movement.
        var visit = FurnitureVisit(placement: placement, petID: actors[index].id, exitPoint: target)
        actors[index].target = target
        actors[index].velocity = .zero
        actors[index].turning = 0
        actors[index].travelling = true
        actors[index].pose = actors[index].profile.species == .parrot ? .fly : .walk
        if reduced {
            visit.phase = .using
            actors[index].position = furnitureCenter(placement)
            actors[index].visualOffsetY = furnitureRestOffset(placement)
            actors[index].travelling = false
            actors[index].pose = furniturePose(visit, actor: actors[index])
            actors[index].step = 0
        }
        furnitureVisits[slot] = visit
        return true
    }

    private func furniturePose(_ visit: FurnitureVisit, actor: Actor) -> PetPose {
        switch visit.placement.item {
        case .softBed: .sleep
        case .leafNest: visit.elapsed < 2 ? .play : .sleep
        case .warmStone: actor.profile.resolvedBreed == .lionCub && visit.elapsed < 2 ? .play : .sleep
        case .splashBath, .playBall: .play
        case .birdPerch, .cozyBox: .idle
        }
    }

    private func requestAmbientFurnitureVisits() {
        for placement in furniture where placement.item != .cozyBox && furnitureVisits[placement.slot] == nil {
            guard clock >= nextFurnitureVisit[placement.slot, default: .infinity] else { continue }
            nextFurnitureVisit[placement.slot] = clock + 3
            let target = furnitureApproach(placement)
            if let nearby = actors.first(where: { actor in
                placement.item.supports(actor.profile.species) && actor.id != boxOccupantID
                    && !furnitureVisits.values.contains(where: { $0.petID == actor.id })
                    && hypot(actor.position.x - target.x, actor.position.y - target.y) < petWidth * 1.5
                && encounter?.contains(actor.id) != true
            }) { _ = requestFurniture(placement.slot, petID: nearby.id, interruptsEncounter: false) }
        }
    }

    private func reconcileFurnitureVisits(resized: Bool) {
        for slot in Array(furnitureVisits.keys) {
            guard var visit = furnitureVisits[slot] else { continue }
            guard furniture.contains(visit.placement), let index = actors.firstIndex(where: { $0.id == visit.petID }),
                  visit.placement.item.supports(actors[index].profile.species) else {
                cancelFurnitureVisit(slot)
                continue
            }
            if resized {
                visit.exitPoint = furnitureApproach(visit.placement)
                if visit.phase == .using {
                    actors[index].position = furnitureCenter(visit.placement)
                    actors[index].visualOffsetY = furnitureRestOffset(visit.placement)
                } else if visit.phase != .approaching {
                    visit.origin = actors[index].position
                    visit.originOffset = actors[index].visualOffsetY
                    visit.elapsed = 0
                }
                furnitureVisits[slot] = visit
            }
        }
        nextFurnitureVisit = nextFurnitureVisit.filter { slot, _ in furniture.contains { $0.slot == slot } }
        for placement in furniture where nextFurnitureVisit[placement.slot] == nil {
            nextFurnitureVisit[placement.slot] = clock + 9 + Double(HabitatFurnitureSlot.allCases.firstIndex(of: placement.slot) ?? 0) * 7
        }
    }

    private func beginFurnitureExit(_ slot: HabitatFurnitureSlot, actor: Actor) {
        guard var visit = furnitureVisits[slot], visit.phase != .leaving else { return }
        visit.phase = .leaving
        visit.elapsed = 0
        visit.origin = actor.position
        visit.originOffset = actor.visualOffsetY
        furnitureVisits[slot] = visit
    }

    private func finishFurnitureVisit(_ slot: HabitatFurnitureSlot, actor: inout Actor) {
        if reduced { actor.visualOffsetY = 0 }
        actor.velocity = .zero
        actor.target = actor.position
        actor.travelling = false
        actor.turning = 0
        actor.pose = .idle
        actor.waiting = 2
        furnitureVisits[slot] = nil
        nextFurnitureVisit[slot] = clock + 25
    }

    private func cancelFurnitureVisit(_ slot: HabitatFurnitureSlot) {
        guard let visit = furnitureVisits[slot] else { return }
        if let index = actors.firstIndex(where: { $0.id == visit.petID }) {
            var actor = actors[index]
            finishFurnitureVisit(slot, actor: &actor)
            actors[index] = actor
        } else { furnitureVisits[slot] = nil }
    }

    private func advanceFurnitureVisit(_ slot: HabitatFurnitureSlot, actor: inout Actor, by dt: Double) {
        guard var visit = furnitureVisits[slot] else { return }
        visit.elapsed += dt
        switch visit.phase {
        case .approaching:
            // A recently removed raised item may still be settling. Do not
            // carry that vertical offset all the way to the next object.
            let settling = petWidth * dt * 1.2
            actor.visualOffsetY = actor.visualOffsetY < 0
                ? min(actor.visualOffsetY + settling, 0) : max(actor.visualOffsetY - settling, 0)
            let target = furnitureApproach(visit.placement)
            let dx = target.x - actor.position.x, dy = target.y - actor.position.y
            let distance = hypot(dx, dy)
            let step = min(distance, 34 * dt)
            actor.target = target
            actor.facing = abs(dx) > 1 ? (dx < 0 ? -1 : 1) : actor.facing
            actor.position = bounded(CGPoint(x: actor.position.x + dx / max(distance, 0.001) * step,
                                             y: actor.position.y + dy / max(distance, 0.001) * step))
            actor.gaitPhase += step / max(petWidth * 0.38, 1)
            actor.pose = actor.profile.species == .parrot ? .fly : .walk
            if distance < 1 {
                visit.phase = .settling; visit.elapsed = 0
                visit.origin = actor.position; visit.originOffset = actor.visualOffsetY
                actor.facing = visit.placement.slot == .left ? -1 : 1
            } else if visit.elapsed > 25 {
                finishFurnitureVisit(slot, actor: &actor)
                return
            }
        case .settling, .leaving:
            let leaving = visit.phase == .leaving
            let target = leaving ? visit.exitPoint : furnitureCenter(visit.placement)
            let p = min(visit.elapsed / 1.4, 1)
            let t = p * p * (3 - 2 * p)
            let old = actor.position
            actor.position = bounded(CGPoint(x: visit.origin.x + (target.x - visit.origin.x) * t,
                                             y: visit.origin.y + (target.y - visit.origin.y) * t))
            let offset = leaving ? 0 : furnitureRestOffset(visit.placement)
            actor.visualOffsetY = visit.originOffset + (offset - visit.originOffset) * t
            actor.pose = actor.profile.species == .parrot ? .fly : .walk
            actor.gaitPhase += hypot(actor.position.x - old.x, actor.position.y - old.y) / max(petWidth * 0.38, 1)
            if p >= 1 {
                actor.travelling = false; actor.velocity = .zero
                if leaving { finishFurnitureVisit(slot, actor: &actor); return }
                visit.phase = .using; visit.elapsed = 0
                actor.pose = furniturePose(visit, actor: actor)
            }
        case .using:
            actor.pose = furniturePose(visit, actor: actor)
            actor.velocity = .zero; actor.travelling = false
            actor.position = furnitureCenter(visit.placement)
            actor.visualOffsetY = furnitureRestOffset(visit.placement)
            if visit.placement.item == .birdPerch { actor.position.x += sin(visit.elapsed * 1.4) * furnitureFrame(visit.placement).width * 0.02 }
            if visit.elapsed >= 12 {
                visit.phase = .leaving; visit.elapsed = 0
                visit.origin = actor.position; visit.originOffset = actor.visualOffsetY
            }
        }
        furnitureVisits[slot] = visit
    }

    private func furnitureBlocks(_ point: CGPoint) -> Bool {
        furniture.contains { placement in
            guard placement.slot != .perch else { return false }
            let ground = HabitatFurnitureLayout.ground(for: placement.slot, in: size)
            let center = CGPoint(x: ground.x, y: ground.y - petWidth * 72 / 220)
            let frame = furnitureFrame(placement)
            return abs(point.x - center.x) < frame.width / 2 + petWidth * 0.2
                && abs(point.y - center.y) < max(frame.height * 0.38, petWidth * 0.16)
        }
    }

    private func avoidFurniture(for actor: inout Actor) {
        guard actor.profile.species != .parrot, !furniture.isEmpty else { return }
        let ahead = CGPoint(x: actor.position.x + actor.facing * petWidth * 0.35, y: actor.position.y)
        if furnitureBlocks(ahead) || furnitureBlocks(actor.target) {
            actor.target.y = groundRange.upperBound
        }
    }
}

// Encounters are transient foreground behavior. They share the enclosure clock
// and never change profiles, vitals, saves, artwork or Live Activity state.
extension HabitatMotionSimulation {
    func encounterStatus(for id: UUID) -> String? {
        guard let encounter, encounter.contains(id) else { return nil }
        switch encounter.phase {
        case .approaching: return String(localized: "Meeting a neighbour", table: "HabitatInteractions")
        case .greeting: return String(localized: "Saying hello", table: "HabitatInteractions")
        case .resting: return String(localized: "Resting together", table: "HabitatInteractions")
        }
    }

    private func availableForEncounter(_ actor: Actor) -> Bool {
        actor.id != boxOccupantID && !furnitureVisits.values.contains { $0.petID == actor.id }
            && actor.visualOffsetY == 0 && actor.affection == 0
            && [.idle, .walk, .run, .fly].contains(actor.pose)
            && (vitals[actor.id]?.energy ?? 1) >= 0.18
            && clock >= encounterCooldowns[actor.id, default: 0]
    }

    /// Both pets are reserved together, synchronously on the main actor.
    /// Manual furniture invitations can interrupt; ambient furniture cannot.
    @discardableResult
    func requestEncounter(between firstID: UUID, and secondID: UUID) -> Bool {
        guard !reduced, encounter == nil, firstID != secondID, size.width > 1,
              let first = actors.first(where: { $0.id == firstID }),
              let second = actors.first(where: { $0.id == secondID }),
              availableForEncounter(first), availableForEncounter(second),
              hypot(first.position.x - second.position.x, first.position.y - second.position.y) <= petWidth * 3.2
        else { return false }
        let left = first.position.x <= second.position.x ? first : second
        let right = left.id == firstID ? second : first
        let spacing = petWidth * 0.82
        let midpoint = CGPoint(x: (left.position.x + right.position.x) / 2,
                               y: (left.position.y + right.position.y) / 2)
        var best: (CGPoint, CGPoint, CGFloat)?
        for y in [midpoint.y, groundRange.upperBound, groundRange.lowerBound] {
            for x in [midpoint.x, size.width / 2] {
                let a = bounded(CGPoint(x: x - spacing / 2, y: y))
                let b = bounded(CGPoint(x: x + spacing / 2, y: y))
                guard b.x - a.x >= spacing - 0.01,
                      encounterPathIsClear(from: left.position, to: a, excluding: [left.id, right.id]),
                      encounterPathIsClear(from: right.position, to: b, excluding: [left.id, right.id]),
                      encounterPathIsClear(from: a, to: b, excluding: [left.id, right.id]) else { continue }
                let travel = hypot(a.x - left.position.x, a.y - left.position.y)
                    + hypot(b.x - right.position.x, b.y - right.position.y)
                if best == nil || travel < best!.2 { best = (a, b, travel) }
            }
        }
        guard let best else { return false }
        let visit = Encounter(leftID: left.id, rightID: right.id, leftTarget: best.0, rightTarget: best.1,
                              napsTogether: encounterRandom() < 0.45)
        encounter = visit
        for index in actors.indices where visit.contains(actors[index].id) {
            actors[index].target = visit.target(for: actors[index].id)
            actors[index].velocity = .zero
            actors[index].travelling = true
            actors[index].turning = 0
            actors[index].blockedFor = 0
            actors[index].pose = .idle
            updateAnimationFrame(for: &actors[index])
        }
        return true
    }

    private func encounterRandom() -> Double {
        encounterSeed = encounterSeed &* 6364136223846793005 &+ 1442695040888963407
        return Double(encounterSeed >> 11) / Double(UInt64.max >> 11)
    }

    private func requestAmbientEncounter() {
        guard encounter == nil, actors.count > 1, clock >= nextEncounter else { return }
        nextEncounter = clock + 3
        let candidates = actors.filter(availableForEncounter)
        guard candidates.count > 1 else { return }
        // Rotate the first candidate without consuming the pets' walking seeds.
        let offset = Int(encounterRandom() * Double(candidates.count)) % candidates.count
        for step in candidates.indices {
            let first = candidates[(step + offset) % candidates.count]
            let neighbours = candidates.filter { $0.id != first.id }.sorted {
                hypot($0.position.x - first.position.x, $0.position.y - first.position.y)
                    < hypot($1.position.x - first.position.x, $1.position.y - first.position.y)
            }
            for second in neighbours {
                if requestEncounter(between: first.id, and: second.id) { return }
            }
        }
    }

    private func encounterPathIsClear(from origin: CGPoint, to target: CGPoint, excluding ids: [UUID]) -> Bool {
        let distance = hypot(target.x - origin.x, target.y - origin.y)
        let samples = max(1, Int(ceil(distance / max(petWidth * 0.15, 1))))
        for step in 0...samples {
            let progress = CGFloat(step) / CGFloat(samples)
            let point = CGPoint(x: origin.x + (target.x - origin.x) * progress,
                                y: origin.y + (target.y - origin.y) * progress)
            if furnitureBlocks(point) { return false }
            if actors.contains(where: { other in
                !ids.contains(other.id) && (
                    encounterSpaceOverlaps(point, other.position)
                    || (other.travelling && encounterSpaceOverlaps(point, other.target)))
            }) { return false }
        }
        return true
    }

    private func encounterSpaceOverlaps(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < petWidth * 0.8 && abs(first.y - second.y) < petWidth * 0.30
    }

    private func advanceEncounterClock(by dt: Double) {
        guard var visit = encounter else { return }
        visit.elapsed += dt
        switch visit.phase {
        case .approaching:
            let participants = actors.filter { visit.contains($0.id) }
            if participants.count != 2 || visit.elapsed > 10 || participants.contains(where: { $0.blockedFor > 1.2 }) {
                endEncounter(); return
            }
            if participants.allSatisfy({
                hypot($0.position.x - visit.target(for: $0.id).x, $0.position.y - visit.target(for: $0.id).y) < 0.1
                    && $0.turning == 0 && $0.facing == ($0.id == visit.leftID ? 1 : -1)
            }) {
                visit.phase = .greeting
                visit.elapsed = 0
                for index in actors.indices where visit.contains(actors[index].id) { actors[index].affection = 1.5 }
            }
        case .greeting:
            if visit.elapsed >= 2.4 { visit.phase = .resting; visit.elapsed = 0 }
        case .resting:
            if visit.elapsed >= (visit.napsTogether ? 7 : 4.5) { endEncounter(); return }
        }
        encounter = visit
    }

    private func advanceEncounterActor(_ actor: inout Actor, encounter visit: Encounter, neighbours: [Actor], by dt: Double) {
        actor.velocity = visit.phase == .approaching ? actor.velocity : .zero
        actor.travelling = visit.phase == .approaching
        guard visit.phase == .approaching else {
            actor.pose = visit.phase == .resting && visit.napsTogether ? .sleep : .idle
            return
        }
        let target = visit.target(for: actor.id)
        let dx = target.x - actor.position.x, dy = target.y - actor.position.y
        let distance = hypot(dx, dy)
        let facingTarget = distance < 0.1
            ? (actor.id == visit.leftID ? visit.rightTarget : visit.leftTarget) : target
        faceBoxTarget(&actor, target: facingTarget)
        if actor.turning > 0 {
            actor.turning = max(0, actor.turning - dt)
            actor.facing = actor.turning > 0.11 ? actor.turnFrom : actor.desiredFacing
            actor.pose = .idle
            return
        }
        guard distance >= 0.1 else { actor.velocity = .zero; actor.pose = .idle; return }
        let speed = min(28, sqrt(distance * 100), hypot(actor.velocity.dx, actor.velocity.dy) + dt * 90)
        let travel = min(distance, speed * dt)
        let next = CGPoint(x: actor.position.x + dx / distance * travel, y: actor.position.y + dy / distance * travel)
        // A new visitor has right of way. Stop, then abandon a blocked meeting
        // instead of pushing through furniture or dragging the other pet along.
        if furnitureBlocks(next) || neighbours.contains(where: {
            !visit.contains($0.id) && encounterSpaceOverlaps(next, $0.position)
        }) {
            actor.velocity = .zero
            actor.pose = .idle
            actor.blockedFor += dt
            return
        }
        actor.blockedFor = 0
        actor.position = next
        actor.velocity = CGVector(dx: dx / distance * speed, dy: dy / distance * speed)
        actor.pose = actor.profile.species == .parrot ? .fly : .walk
        let stride = petWidth * PetAnimationLibrary.enclosureStrideRatio(
            for: actor.profile.species, breed: actor.profile.resolvedBreed, pose: actor.pose)
        actor.gaitPhase += travel / max(stride, 1)
    }

    private func endEncounter() {
        guard let visit = encounter else { return }
        encounter = nil
        nextEncounter = clock + 18 + encounterRandom() * 12
        for index in actors.indices where visit.contains(actors[index].id) {
            encounterCooldowns[actors[index].id] = clock + 35
            actors[index].velocity = .zero
            actors[index].target = actors[index].position
            actors[index].travelling = false
            actors[index].turning = 0
            actors[index].blockedFor = 0
            actors[index].affection = 0
            actors[index].pose = .idle
            // Stagger departures so the pair does not immediately walk in lockstep.
            actors[index].waiting = actors[index].id == visit.leftID ? 0.8 : 2
            updateAnimationFrame(for: &actors[index])
        }
    }
}

#if DEBUG
/// Isolated UI fixture: it uses the real canvas and simulation without a store.
struct HabitatEncounterDebugHost: View {
    @StateObject private var motion = HabitatMotionSimulation()
    @State private var active = false
    @State private var pets = [
        PetProfile(id: UUID(uuidString: "EC000000-0000-0000-0000-000000000001")!, name: "Pixel",
                   species: .cat, coat: .sunrise, createdAt: .distantPast, breed: .classicCat,
                   outfit: PetOutfit(headwear: .knitHat)),
        PetProfile(id: UUID(uuidString: "EC000000-0000-0000-0000-000000000002")!, name: "Corgi",
                   species: .dog, coat: .sunrise, createdAt: .distantPast, breed: .corgi)
    ]

    var body: some View {
        VStack(spacing: 20) {
            HabitatEditorCanvas(theme: .sunnyMeadow, pets: pets, vitalsByPetID: [:],
                                isAnimationEnabled: active, motion: motion)
                .frame(height: 250)
            Text(motion.encounter?.phase.rawValue ?? "free").accessibilityIdentifier("encounter.phase")
            Button("Meet") {
                _ = motion.requestEncounter(between: pets[0].id, and: pets[1].id)
                active = true
            }
                .disabled(pets.count < 2).accessibilityIdentifier("encounter.meet")
            Button("Remove neighbour") { pets = Array(pets.prefix(1)) }
                .accessibilityIdentifier("encounter.remove")
            Button(active ? "Pause" : "Resume") { active.toggle() }.accessibilityIdentifier("encounter.pause")
        }
        .padding(20)
        .environment(\.petMinimizeMotion, ProcessInfo.processInfo.arguments.contains("-encounter-reduced-motion"))
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-encounter-light") ? .light : .dark)
    }
}
#endif

private struct HabitatThemeBackdrop: View, Equatable {
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
                animatesMotion: false, accessory: pet.outfit?.headwear
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
private struct HabitatThemePresentation: Identifiable, Equatable {
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
