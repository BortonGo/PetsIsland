import SwiftUI

/// A controller-independent editor for the pets shown in the enclosure.
///
struct HabitatEditorView: View {
    let pets: [PetProfile]
    @Binding var selectedPetIDs: [UUID]
    @Binding var selectedTheme: HabitatTheme
    var vitalsByPetID: [UUID: PetVitals]
    var maximumPets: Int
    var onSave: () -> Void

    init(
        pets: [PetProfile],
        selectedPetIDs: Binding<[UUID]>,
        selectedTheme: Binding<HabitatTheme>,
        vitalsByPetID: [UUID: PetVitals] = [:],
        maximumPets: Int = 3,
        onSave: @escaping () -> Void = {}
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
            .background(Color(.systemGroupedBackground))
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

            ScrollView(.horizontal) {
                HStack(spacing: 11) {
                    ForEach(HabitatThemePresentation.options) { theme in
                        themeButton(theme)
                    }
                }
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
                    .frame(width: 104, height: 64)

                Label(theme.name, systemImage: theme.symbol)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            .padding(9)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.13), lineWidth: isSelected ? 2 : 1)
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

            if pets.isEmpty {
                ContentUnavailableView(
                    "No pets yet",
                    systemImage: "pawprint",
                    description: Text("Create a pet before editing the enclosure.")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 104), spacing: 10)],
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
                            isSelected ? Color.white : Color.accentColor,
                            isSelected ? Color.accentColor : Color(.secondarySystemGroupedBackground)
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
                isSelected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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
                    Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
        }
    }

    private var saveBar: some View {
        Button {
            onSave()
        } label: {
            Label("Save enclosure", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
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

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                HabitatThemeBackdrop(theme: palette)

                pixelFence(width: proxy.size.width)
                    .padding(.bottom, 13)

                if pets.isEmpty {
                    ContentUnavailableView("Empty enclosure", systemImage: "pawprint")
                        .foregroundStyle(palette.foreground)
                } else {
                    TimelineView(
                        .periodic(
                            from: .now,
                            by: PetAnimationClip.foregroundRefreshInterval
                        )
                    ) { timeline in
                        let state = PetHabitatState(
                            theme: theme,
                            residentPetIDs: pets.map(\.id),
                            simulationEpoch: pets.map(\.createdAt).min() ?? Date(timeIntervalSince1970: 0)
                        )
                        let projections = PetHabitatEngine.projections(for: state, pets: pets, at: timeline.date)
                        let animationTime = timeline.date.timeIntervalSince(state.simulationEpoch)

                        ZStack {
                            ForEach(projections) { projection in
                                if let pet = pets.first(where: { $0.id == projection.petID }) {
                                    let clip = PetAnimationLibrary.clip(
                                        for: pet.species,
                                        breed: pet.resolvedBreed,
                                        pose: projection.pose
                                    )
                                    let phaseOffset = pets.firstIndex(where: { $0.id == pet.id }) ?? 0
                                    VStack(spacing: 1) {
                                        Text(statusTitle(projection.status))
                                            .font(.system(size: 8, weight: .black, design: .rounded))
                                            .foregroundStyle(palette.foreground)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(.black.opacity(0.24), in: Capsule())
                                        PetArtwork(
                                            species: pet.species,
                                            coat: pet.coat,
                                            customColor: pet.customColor,
                                            breed: pet.resolvedBreed,
                                            pose: projection.pose,
                                            direction: projection.direction,
                                            step: clip.frameIndex(
                                                at: animationTime,
                                                phaseOffset: phaseOffset
                                            ),
                                            animatesMotion: false
                                        )
                                        .frame(width: min(proxy.size.width * 0.24, 78), height: 60)
                                    }
                                    .position(
                                        x: 36 + CGFloat(projection.position) * max(proxy.size.width - 72, 1),
                                        y: 46 + CGFloat(projection.verticalPosition) * max(proxy.size.height - 68, 1)
                                    )
                                    .zIndex(Double(projection.depth + 1))
                                }
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18))
            }
        }
    }

    private func statusTitle(_ status: HabitatPetStatus) -> String {
        switch status {
        case .watching: "watching"
        case .wandering: "wandering"
        case .running: "running"
        case .flying: "flying"
        case .playing: "playing"
        case .resting: "resting"
        case .sleeping: "sleeping"
        }
    }

    private func pixelFence(width: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<22, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.fence.opacity(index.isMultiple(of: 2) ? 0.9 : 0.72))
                    .frame(width: max((width - 120) / 22, 3), height: index.isMultiple(of: 3) ? 31 : 25)
            }
        }
        .overlay {
            Rectangle()
                .fill(palette.fence.opacity(0.78))
                .frame(height: 4)
                .offset(y: 5)
        }
        .accessibilityHidden(true)
    }

    private var palette: HabitatThemePresentation {
        HabitatThemePresentation.options.first { $0.theme == theme }
            ?? HabitatThemePresentation.options[0]
    }
}

private struct HabitatThemeBackdrop: View {
    let theme: HabitatThemePresentation

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                LinearGradient(colors: theme.sky, startPoint: .top, endPoint: .bottom)

                Circle()
                    .fill(theme.light.opacity(0.82))
                    .frame(width: 34, height: 34)
                    .position(x: proxy.size.width - 42, y: 38)

                Ellipse()
                    .fill(theme.ground.opacity(0.72))
                    .frame(width: proxy.size.width * 0.9, height: 92)
                    .offset(x: -proxy.size.width * 0.25, y: 29)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [theme.ground, theme.ground.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: proxy.size.height * 0.43)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HabitatThemeSwatch: View {
    let theme: HabitatThemePresentation

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: theme.sky, startPoint: .top, endPoint: .bottom)
            Rectangle()
                .fill(theme.ground)
                .frame(height: 22)
            HStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { _ in
                    Rectangle().fill(theme.fence).frame(width: 3, height: 14)
                }
            }
            .padding(.bottom, 5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
                    vital("fork.knife", value: vitals.fullness, tint: .orange)
                    vital("heart.fill", value: vitals.happiness, tint: .pink)
                    vital("bolt.fill", value: vitals.energy, tint: .cyan)
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
        return .green
    }

    private func percent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded())) percent"
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

/// Presentation-only theme data. Persistence continues to use a stable string
/// identifier until the shared habitat model supplies its own theme type.
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
            theme: .meadow,
            name: "Meadow",
            symbol: "sun.max.fill",
            sky: [Color(red: 0.36, green: 0.74, blue: 0.94), Color(red: 0.74, green: 0.9, blue: 0.83)],
            ground: Color(red: 0.22, green: 0.56, blue: 0.27),
            fence: Color(red: 0.95, green: 0.87, blue: 0.68),
            light: Color(red: 1, green: 0.88, blue: 0.28),
            foreground: .white
        ),
        HabitatThemePresentation(
            theme: .moonlitGarden,
            name: "Starlight",
            symbol: "moon.stars.fill",
            sky: [Color(red: 0.07, green: 0.09, blue: 0.24), Color(red: 0.2, green: 0.22, blue: 0.46)],
            ground: Color(red: 0.11, green: 0.28, blue: 0.25),
            fence: Color(red: 0.61, green: 0.63, blue: 0.78),
            light: Color(red: 0.9, green: 0.94, blue: 1),
            foreground: .white
        ),
        HabitatThemePresentation(
            theme: .cozyRoom,
            name: "Cozy room",
            symbol: "sofa.fill",
            sky: [Color(red: 0.91, green: 0.57, blue: 0.39), Color(red: 0.98, green: 0.8, blue: 0.58)],
            ground: Color(red: 0.48, green: 0.25, blue: 0.15),
            fence: Color(red: 0.31, green: 0.15, blue: 0.08),
            light: Color(red: 1, green: 0.77, blue: 0.35),
            foreground: .white
        ),
        HabitatThemePresentation(
            theme: .arcticCove,
            name: "Arctic cove",
            symbol: "snowflake",
            sky: [Color(red: 0.54, green: 0.74, blue: 0.9), Color(red: 0.84, green: 0.91, blue: 0.96)],
            ground: Color(red: 0.82, green: 0.9, blue: 0.93),
            fence: Color(red: 0.48, green: 0.58, blue: 0.65),
            light: .white,
            foreground: Color(red: 0.08, green: 0.18, blue: 0.26)
        ),
        HabitatThemePresentation(
            theme: .desertCamp,
            name: "Desert camp",
            symbol: "sun.horizon.fill",
            sky: [Color(red: 0.94, green: 0.5, blue: 0.3), Color(red: 0.99, green: 0.79, blue: 0.47)],
            ground: Color(red: 0.67, green: 0.38, blue: 0.19),
            fence: Color(red: 0.37, green: 0.2, blue: 0.11),
            light: Color(red: 1, green: 0.9, blue: 0.49),
            foreground: .white
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
