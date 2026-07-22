import SwiftUI
import UIKit

struct SessionComposerView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var selectedMinutes = 20
    @State private var customMinutes = 90.0
    @State private var usesCustomDuration = false

    init(controller: PetSessionController) {
        self.controller = controller
        let preferred = min(max(controller.settings.defaultSessionMinutes, 10), 480)
        let isPreset = SessionPreset.allCases.contains { $0.rawValue == preferred }
        _selectedMinutes = State(initialValue: isPreset ? preferred : SessionPreset.short.rawValue)
        _customMinutes = State(initialValue: Double(preferred))
        _usesCustomDuration = State(initialValue: !isPreset)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("How long should your pet stay close?")
                    .font(.title2.bold())
                VStack(spacing: 10) {
                    ForEach(SessionPreset.allCases) { preset in
                        durationButton(minutes: preset.rawValue)
                    }
                    Button {
                        usesCustomDuration = true
                    } label: {
                        HStack {
                            Label("Custom", systemImage: "slider.horizontal.3")
                            Spacer()
                            if usesCustomDuration { Image(systemName: "checkmark.circle.fill") }
                        }
                        .frame(minHeight: 38)
                    }
                    .buttonStyle(.bordered)
                }

                if usesCustomDuration {
                    VStack(alignment: .leading) {
                        Text(formattedDuration(minutes: Int(customMinutes)))
                            .font(.headline.monospacedDigit())
                        Slider(value: $customMinutes, in: 10...480, step: 10)
                            .accessibilityValue(formattedDuration(minutes: Int(customMinutes)))
                    }
                }
                Spacer()
                Button {
                    let minutes = usesCustomDuration ? Int(customMinutes) : selectedMinutes
                    Task { await controller.startSession(duration: TimeInterval(minutes * 60)) }
                } label: {
                    Label("Place on the island", systemImage: "sparkles")
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controller.isBusy)
            }
            .padding(20)
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private func durationButton(minutes: Int) -> some View {
        Button {
            selectedMinutes = minutes
            usesCustomDuration = false
        } label: {
            HStack {
                Label(durationTitle(minutes), systemImage: minutes == 20 ? "cup.and.saucer.fill" : "clock.fill")
                Spacer()
                if selectedMinutes == minutes && !usesCustomDuration { Image(systemName: "checkmark.circle.fill") }
            }
            .frame(minHeight: 38)
        }
        .buttonStyle(.bordered)
    }

    private func durationTitle(_ minutes: Int) -> String {
        switch minutes {
        case 20: String(localized: "A little while · 20 min")
        case 40: String(localized: "A walk · 40 min")
        case 60: String(localized: "An hour · 60 min")
        case 120: String(localized: "A long stay · 2 h")
        default: String(localized: "An adventure · 4 h")
        }
    }

    private func formattedDuration(minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }
}

struct PetEditorView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PetProfile

    init(controller: PetSessionController) {
        self.controller = controller
        _draft = State(initialValue: controller.profile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PetHabitatView(profile: draft, snapshot: .init(pose: .idle, position: 0.5, direction: .right, revision: 0, generatedAt: .now))
                        .frame(height: 210)
                        .listRowInsets(EdgeInsets())
                }
                Section("Your dog") { PetPicker(profile: $draft, allowedSpecies: [.dog]) }
            }
            .navigationTitle("Edit pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await controller.updateProfile(draft); dismiss() }
                    }
                    .disabled(controller.session != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if controller.session != nil {
                    Text("Changes are available after the active session ends.")
                        .font(.footnote).foregroundStyle(.secondary).padding(10)
                }
            }
        }
    }
}

struct PetPicker: View {
    @Binding var profile: PetProfile
    var allowedSpecies: [PetSpecies] = PetSpecies.selectableCases

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $profile.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)

            Text("Species")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(allowedSpecies) { species in
                        speciesButton(species)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            if !PetBreed.available(for: profile.species).isEmpty {
                variantPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Picker("Coat", selection: $profile.coat) {
                ForEach(PetCoat.allCases) { coat in Text(coat.displayName).tag(coat) }
            }
            .pickerStyle(.segmented)

            Toggle("Custom color", isOn: customColorEnabled)
            if profile.customColor != nil {
                ColorPicker("Pet color", selection: customColor, supportsOpacity: false)
            }
        }
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(variantSectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(PetBreed.available(for: profile.species)) { variant in
                        variantButton(variant)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
    }

    private var variantSectionTitle: LocalizedStringKey {
        profile.species == .dog ? "Breed" : "Variant"
    }

    private func variantButton(_ variant: PetBreed) -> some View {
        let isSelected = profile.resolvedBreed == variant

        return Button {
            withAnimation(.snappy) { profile.breed = variant }
        } label: {
            VStack(spacing: 4) {
                PetArtwork(
                    species: profile.species,
                    coat: profile.coat,
                    customColor: profile.customColor,
                    breed: variant,
                    pose: profile.species == .parrot ? .fly : .idle,
                    direction: .right,
                    step: 0,
                    animatesMotion: false
                )
                .frame(width: 66, height: 52)

                Text(variant.displayName)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: 88, height: 82)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(variant.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customColorEnabled: Binding<Bool> {
        Binding(
            get: { profile.customColor != nil },
            set: { enabled in
                profile.customColor = enabled
                    ? (profile.customColor ?? PetColorSelection(red: 0.26, green: 0.68, blue: 0.92))
                    : nil
            }
        )
    }

    private var customColor: Binding<Color> {
        Binding(
            get: {
                let value = profile.customColor ?? PetColorSelection(red: 0.26, green: 0.68, blue: 0.92)
                return Color(red: value.red, green: value.green, blue: value.blue)
            },
            set: { color in
                let uiColor = UIColor(color)
                var red: CGFloat = 0
                var green: CGFloat = 0
                var blue: CGFloat = 0
                var alpha: CGFloat = 0
                guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
                profile.customColor = PetColorSelection(
                    red: Double(red),
                    green: Double(green),
                    blue: Double(blue)
                )
            }
        )
    }

    private func speciesButton(_ species: PetSpecies) -> some View {
        let isSelected = profile.species == species
        let previewPose: PetPose = species == .parrot ? .fly : .idle
        let colors = PetColors.resolve(
            species: species,
            coat: profile.coat,
            customColor: profile.customColor
        )

        return Button {
            withAnimation(.snappy) {
                profile.species = species
                profile.breed = PetBreed.defaultVariant(for: species)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    colors.secondary.opacity(0.36),
                                    colors.primary.opacity(0.16)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Capsule()
                        .fill(colors.detail.opacity(0.16))
                        .frame(width: 52, height: 4)
                        .padding(.bottom, 6)

                    PetArtwork(
                        species: species,
                        coat: profile.coat,
                        customColor: profile.customColor,
                        breed: species == profile.species ? profile.resolvedBreed : PetBreed.defaultVariant(for: species),
                        pose: previewPose,
                        direction: .right,
                        step: 0,
                        animatesMotion: false
                    )
                    .frame(width: 68, height: 56)
                    .padding(.bottom, species == .parrot ? 1 : 3)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(5)
                    }
                }
                .frame(width: 72, height: 61)

                Text(species.displayName)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 88, height: 96)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(species.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppSettings

    init(controller: PetSessionController) {
        self.controller = controller
        _draft = State(initialValue: controller.settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Experience") {
                    Toggle("Haptic feedback", isOn: $draft.hapticsEnabled)
                    Toggle("Minimize pet motion", isOn: $draft.minimizeMotion)
                }
                Section("About Live Activities") {
                    Label("Dynamic Island is available on supported iPhones.", systemImage: "iphone.gen3")
                    Label("On Always-On Display your pet sleeps to save energy.", systemImage: "moon.zzz.fill")
                    Label("iOS controls how often widgets and Live Activities refresh.", systemImage: "sparkles")
                }
                Section("About") {
                    LabeledContent("Privacy", value: "No account · No tracking")
                    LabeledContent("License", value: "MIT Open Source")
                    LabeledContent("Version", value: "1.0")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await controller.updateSettings(draft); dismiss() } }
                }
            }
        }
    }
}

struct SessionSummaryView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            PetPortraitArtwork(
                species: controller.profile.species,
                coat: controller.profile.coat,
                customColor: controller.profile.customColor,
                breed: controller.profile.resolvedBreed,
                pose: .sleep
            )
                .frame(width: 180, height: 140)
            Text("Session complete").font(.largeTitle.bold())
            Text("Your pet enjoyed staying close.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 5) {
                Text("\(controller.history.completedSessions)").monospacedDigit()
                Text("Sessions together")
            }
            .font(.headline).padding(12).background(.thinMaterial, in: Capsule())
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(28)
        .presentationDetents([.medium])
    }
}

#if DEBUG
#Preview("Новая прогулка") {
    SessionComposerView(
        controller: PetSessionController(store: InMemoryPetStore())
    )
}

#Preview("Настройки") {
    SettingsView(
        controller: PetSessionController(store: InMemoryPetStore())
    )
}

#Preview("Завершение прогулки") {
    SessionSummaryView(
        controller: PetSessionController(store: InMemoryPetStore())
    )
}
#endif
