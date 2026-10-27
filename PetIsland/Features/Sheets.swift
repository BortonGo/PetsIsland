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
                .buttonStyle(PetPrimaryButtonStyle())
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
                    HabitatEditorCanvas(theme: .meadow, pets: [draft], vitalsByPetID: [:])
                        .frame(height: 210)
                        .listRowInsets(EdgeInsets())
                }
                Section("Your pet") { PetPicker(profile: $draft, allowedSpecies: PetSpecies.selectableCases) }
            }
            .scrollContentBackground(.hidden)
            .petPage()
            .navigationTitle("Edit pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await controller.updateProfile(draft) { dismiss() } }
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
    @FocusState private var isNameFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @PetReduceMotion private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Pet name").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Name", text: $profile.name)
                    .font(.body)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isNameFieldFocused)
                    .onSubmit {
                        profile.normalizeName()
                        isNameFieldFocused = false
                    }
                    .accessibilityLabel("Pet name")
                    .accessibilityIdentifier("petPicker.name")
                    .padding(.horizontal, 14)
                    .frame(minHeight: 52)
                    .background(PetDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isNameFieldFocused ? Color.accentColor : Color(.separator), lineWidth: isNameFieldFocused ? 2 : 1)
                    }
                Text("Up to 16 characters. You can change the name later.")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
                if profile.name.count > 16 {
                    Text("Will be saved as: \(savedName)")
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                        .accessibilityIdentifier("petPicker.savedName")
                }
            }

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

            if isCorgiSelected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Corgi variant")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    corgiLayout {
                        variantButton(.corgi, isCorgiOption: true)
                        variantButton(.cardigan, isCorgiOption: true)
                    }
                }
                .accessibilityElement(children: .contain)
            }

            Text("Coat")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                coatPicker.pickerStyle(.menu)
            } else {
                coatPicker.pickerStyle(.segmented)
            }

            Toggle("Custom color", isOn: customColorEnabled)
            if profile.customColor != nil {
                ColorPicker("Pet color", selection: customColor, supportsOpacity: false)
            }
        }
    }

    private var savedName: String {
        var normalized = profile
        normalized.normalizeName()
        return normalized.name
    }

    private var corgiLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private var coatPicker: some View {
        Picker("Coat", selection: $profile.coat) {
            ForEach(PetCoat.allCases) { coat in Text(coat.displayName).tag(coat) }
        }
        .accessibilityIdentifier("petPicker.coat")
    }

    private var variantPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(variantSectionTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(PetBreed.available(for: profile.species).filter { $0 != .cardigan }) { variant in
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

    private var isCorgiSelected: Bool {
        profile.species == .dog && [.corgi, .cardigan].contains(profile.resolvedBreed)
    }

    private func variantButton(_ variant: PetBreed, isCorgiOption: Bool = false) -> some View {
        let isCorgiGroup = variant == .corgi && !isCorgiOption
        let isSelected = isCorgiGroup ? isCorgiSelected : profile.resolvedBreed == variant
        let previewBreed = isCorgiGroup && isSelected ? profile.resolvedBreed : variant
        let title: LocalizedStringKey = isCorgiOption
            ? (variant == .corgi ? "Pembroke" : "Cardigan") : variant.displayName

        return Button {
            // Tapping the selected family must not reset a saved Cardigan.
            if !isCorgiGroup || !isCorgiSelected {
                withAnimation(reduceMotion ? nil : .snappy) { profile.breed = variant }
            }
        } label: {
            VStack(spacing: 4) {
                PetArtwork(
                    species: profile.species,
                    coat: profile.coat,
                    customColor: profile.customColor,
                    breed: previewBreed,
                    pose: profile.species == .parrot ? .fly : .idle,
                    direction: .right,
                    step: 0,
                    animatesMotion: false, accessory: profile.outfit?.headwear
                )
                .frame(width: 66, height: 52)

                Text(title)
                    .font(.caption2.weight(isSelected ? .bold : .medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 140 : 88)
            .padding(.vertical, 5)
            .frame(minHeight: 82)
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("petPicker.variant.\(variant.rawValue).\(isCorgiOption ? "option" : "family")")
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
            withAnimation(reduceMotion ? nil : .snappy) {
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
                            .font(.system(size: 13, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(PetDesign.onAccent, PetDesign.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(5)
                    }
                }
                .frame(width: 72, height: 61)

                Text(species.displayName)
                    .font(.caption.weight(isSelected ? .bold : .medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: dynamicTypeSize.isAccessibilitySize ? 140 : 88)
            .padding(.vertical, 5)
            .frame(minHeight: 96)
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
        .accessibilityIdentifier("petPicker.species.\(species.rawValue)")
    }
}

/// Only the preferences edited on this screen. Applying them to the latest
/// settings keeps separately edited Live Activity options intact.
struct GeneralSettingsDraft: Equatable {
    var appearance: AppAppearance
    var hapticsEnabled: Bool
    var minimizeMotion: Bool

    init(_ settings: AppSettings) {
        appearance = settings.appearance
        hapticsEnabled = settings.hapticsEnabled
        minimizeMotion = settings.minimizeMotion
    }

    func applying(to settings: AppSettings) -> AppSettings {
        var result = settings
        result.appearance = appearance
        result.hapticsEnabled = hapticsEnabled
        result.minimizeMotion = minimizeMotion
        return result
    }
}

struct SettingsView: View {
    @ObservedObject var controller: PetSessionController
    var showsDismissButton = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var draft: GeneralSettingsDraft
    @State private var isSaving = false
    @State private var failedDraft: GeneralSettingsDraft?
    @State private var showsAppIcons = false
    @State private var showsIslandBackup = false
    @State private var showsAuthorSupport = false
    @State private var showsSupportPrivacy = false
    @State private var showsAppLanguage = false

    init(controller: PetSessionController, showsDismissButton: Bool = true) {
        self.controller = controller
        self.showsDismissButton = showsDismissButton
        _draft = State(initialValue: GeneralSettingsDraft(controller.settings))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        PetScreenHeading(title: "Settings")
                        Group {
                            if isSaving {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("Saving settings…")
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("settings.saving")
                            } else {
                                Text(showsDismissButton ? "Tap Done to save your changes." : "Changes save automatically.")
                                    .accessibilityIdentifier("settings.saveHint")
                            }
                        }
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Appearance").font(.subheadline.weight(.semibold))
                        appearanceLayout {
                            ForEach(AppAppearance.allCases) { appearance in
                                appearanceButton(appearance)
                            }
                        }
                        .disabled(isSaving || controller.isBusy)
                        Text("System follows the appearance selected in iOS Settings.")
                            .font(.caption).foregroundStyle(PetDesign.secondary)
                    }
                    .padding(18)
                    .petSurface()
                    Button { showsAppIcons = true } label: {
                        HStack(spacing: 14) {
                            Image(AppIconChoice.current.previewName)
                                .resizable()
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Text("App icon").font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(PetDesign.secondary)
                        }
                        .padding(18)
                        .petSurface()
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Haptic feedback", isOn: preference(\.hapticsEnabled))
                                .accessibilityIdentifier("settings.haptics")
                            Text("Gentle vibrations for actions and games.")
                                .font(.caption).foregroundStyle(PetDesign.secondary)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Minimize pet motion", isOn: preference(\.minimizeMotion))
                                .accessibilityIdentifier("settings.motion")
                            Text("Calmer animation inside the app. Choose the Dynamic Island movement mode separately in Island setup.")
                                .font(.caption).foregroundStyle(PetDesign.secondary)
                                .accessibilityIdentifier("settings.motionHint")
                            if systemReduceMotion {
                                Text("Reduce Motion is also enabled in iOS Settings.")
                                    .font(.caption).foregroundStyle(PetDesign.secondary)
                                    .accessibilityIdentifier("settings.systemMotion")
                            }
                        }
                    }
                    .disabled(isSaving || controller.isBusy)
                    .font(.subheadline)
                    .padding(18)
                    .petSurface()
                    Button { showsAppLanguage = true } label: {
                        HStack(spacing: 14) {
                            Label(String(localized: "App language", table: "ReleaseSupport"), systemImage: "globe")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(verbatim: PetAppLanguage.current.nativeName)
                                .font(.subheadline).foregroundStyle(PetDesign.secondary)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(PetDesign.secondary)
                        }.padding(18).petSurface()
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.language")
                    Button { showsIslandBackup = true } label: {
                        HStack(spacing: 14) {
                            Label("Island backup", systemImage: "externaldrive")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(PetDesign.secondary)
                        }.padding(18).petSurface()
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isBusy)
                    .accessibilityIdentifier("settings.backup")
                    Button { showsAuthorSupport = true } label: {
                        Label(String(localized: "Support the author", table: "ReleaseSupport"), systemImage: "heart")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18).petSurface()
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.authorSupport")
                    Button { showsSupportPrivacy = true } label: {
                        Label(String(localized: "Help and privacy", table: "ReleaseSupport"), systemImage: "questionmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18).petSurface()
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.supportPrivacy")
                    DisclosureGroup {
                        PetGettingStartedGuide()
                            .padding(.top, 16)
                    } label: {
                        Text("Quick guide")
                            .accessibilityIdentifier("settings.guide")
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(18)
                    .petSurface()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Dynamic Island is available on supported iPhones.", systemImage: "iphone.gen3")
                            Text("The enclosure and games work on every supported iPhone. Without Dynamic Island, your travelling pet appears on the Lock Screen.")
                            Label("On Always-On Display your pet sleeps to save energy.", systemImage: "moon.zzz")
                            Label("iOS controls how often widgets and Live Activities refresh.", systemImage: "sparkles")
                        }
                        .font(.footnote)
                        .foregroundStyle(PetDesign.secondary)
                        .padding(.top, 16)
                    } label: {
                        Text("About Live Activities").font(.subheadline.weight(.medium))
                    }
                    .padding(18)
                    .petSurface()
                    DisclosureGroup("Add the enclosure widget") {
                        Text("Touch and hold your Home Screen, open the widget gallery, and choose Pet Island → Your island. Choose its residents on the Island tab.", tableName: "EnclosureWidget")
                            .font(.footnote)
                            .foregroundStyle(PetDesign.secondary)
                            .padding(.top, 12)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(18)
                    .petSurface()
                    VStack(spacing: 14) {
                        LabeledContent("Privacy", value: String(localized: "No account · No tracking"))
                        LabeledContent("License", value: String(localized: "All rights reserved", table: "ReleaseSupport"))
                        LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                    }
                    .font(.caption)
                    .foregroundStyle(PetDesign.secondary)
                    .padding(.horizontal, 4)
                }
                .padding(24)
                .padding(.bottom, 12)
            }
            .petPage()
            .navigationTitle(showsDismissButton ? "Settings" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsDismissButton ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isSaving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { save(draft) }
                            .disabled(isSaving || controller.isBusy)
                    }
                }
            }
        }
        .sheet(isPresented: $showsAppIcons) { AppIconPickerView() }
        .sheet(isPresented: $showsIslandBackup) { IslandBackupView(controller: controller) }
        .sheet(isPresented: $showsAuthorSupport) { AuthorSupportView() }
        .sheet(isPresented: $showsSupportPrivacy) { SupportPrivacyView() }
        .sheet(isPresented: $showsAppLanguage) { AppLanguageView() }
        .interactiveDismissDisabled(isSaving)
        .alert("Settings were not saved", isPresented: Binding(
            get: { failedDraft != nil },
            set: { if !$0 { failedDraft = nil } }
        ), presenting: failedDraft) { failed in
            Button("Try again") { save(failed) }
                .disabled(isSaving || controller.isBusy)
            Button("Cancel", role: .cancel) { failedDraft = nil }
        } message: { _ in
            Text("Your previous settings are still in use. You can try saving again.")
        }
        .onChange(of: controller.settings) { _, newSettings in
            guard !showsDismissButton, !isSaving else { return }
            draft = GeneralSettingsDraft(newSettings)
        }
    }

    private func preference<Value: Equatable>(_ key: WritableKeyPath<GeneralSettingsDraft, Value>) -> Binding<Value> {
        Binding(get: { draft[keyPath: key] }, set: { value in
            guard !isSaving, !controller.isBusy, draft[keyPath: key] != value else { return }
            draft[keyPath: key] = value
            if !showsDismissButton { save(draft) }
        })
    }

    private func save(_ changes: GeneralSettingsDraft) {
        guard !isSaving, !controller.isBusy else { return }
        isSaving = true
        let candidate = changes.applying(to: controller.settings)
        Task {
            let saved = await controller.updateSettings(candidate)
            isSaving = false
            if saved {
                draft = GeneralSettingsDraft(controller.settings)
                failedDraft = nil
                if showsDismissButton { dismiss() }
            } else {
                // Keep the controls honest about the preferences actually in use.
                // Retain the attempted values separately for the Retry action.
                controller.alertMessage = nil
                if !showsDismissButton { draft = GeneralSettingsDraft(controller.settings) }
                failedDraft = changes
            }
        }
    }

    private func appearanceButton(_ appearance: AppAppearance) -> some View {
        let selected = draft.appearance == appearance
        return Button { preference(\.appearance).wrappedValue = appearance } label: {
            appearanceContentLayout {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: appearance == .system ? "circle.lefthalf.filled" : appearance == .light ? "sun.max" : "moon")
                        .font(.title2.weight(.light))
                }
                Text(appearanceTitle(appearance))
                    .font(.caption.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(selected ? PetDesign.accent : PetDesign.separator)
                }
            }
            .padding(dynamicTypeSize.isAccessibilitySize ? 14 : 0)
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 112)
            .background(selected ? PetDesign.soft : PetDesign.background,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                if dynamicTypeSize.isAccessibilitySize && selected {
                    RoundedRectangle(cornerRadius: 17).strokeBorder(PetDesign.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(appearance.rawValue)")
    }

    private var appearanceLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private var appearanceContentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 12))
    }

    private func appearanceTitle(_ appearance: AppAppearance) -> LocalizedStringKey {
        switch appearance {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Isolated settings fixture: save failures never touch the user's island.
struct SettingsClarityDebugHostView: View {
    @StateObject private var controller: PetSessionController

    init() {
        var state = PersistedAppState()
        state.completedOnboarding = true
        state.pets = [
            PetProfile(id: UUID(uuidString: "CE000000-0000-0000-0000-000000000001")!, name: "Pixel", species: .dog,
                       coat: .sunrise, createdAt: .now, breed: .cardigan),
            PetProfile(id: UUID(uuidString: "CE000000-0000-0000-0000-000000000002")!, name: "Luna", species: .cat,
                       coat: .cloud, createdAt: .now, breed: .britishShorthair)
        ]
        state.activePetIDs = [state.pets[0].id]
        state.settings = AppSettings(defaultSessionMinutes: 120, dynamicIslandMotionMode: .walkSleep,
                                     liveActivityBackgroundColor: .init(red: 0.7, green: 0.5, blue: 0.6),
                                     liveActivityBackgroundTransparency: 0.4)
        _controller = StateObject(wrappedValue: PetSessionController(
            store: SettingsClarityPreviewStore(state), arcadeStore: InMemoryArcadeStore()
        ))
    }

    var body: some View {
        Group {
            if controller.operation == .loading { ProgressView() }
            else { HomeView(controller: controller) }
        }
        .task {
            await controller.bootstrap()
            controller.selectedTab = .settings
        }
        .preferredColorScheme(controller.settings.appearance == .system ? nil : controller.settings.appearance == .light ? .light : .dark)
        .environment(\.petMinimizeMotion, true)
    }
}

private actor SettingsClarityPreviewStore: PetStore {
    private var state: PersistedAppState
    private var hasFailed = false
    init(_ state: PersistedAppState) { self.state = state }
    func load() -> PersistedAppState { state }
    func save(_ candidate: PersistedAppState) async throws {
        if candidate.settings != state.settings {
            if ProcessInfo.processInfo.arguments.contains("-settings-slow-save") {
                try await Task.sleep(for: .seconds(3))
            }
            if !hasFailed, ProcessInfo.processInfo.arguments.contains("-settings-fail-save") {
                hasFailed = true
                throw CocoaError(.fileWriteOutOfSpace)
            }
        }
        state = candidate
    }
}
#endif

enum AppIconChoice: String, CaseIterable, Identifiable {
    case classic, quietIsland, together, moonNap, pixelFriend, warmPaw

    var id: String { rawValue }
    var alternateName: String? {
        switch self {
        case .classic: nil
        case .quietIsland: "AppIconQuietIsland"
        case .together: "AppIconTogether"
        case .moonNap: "AppIconMoonNap"
        case .pixelFriend: "AppIconPixelFriend"
        case .warmPaw: "AppIconWarmPaw"
        }
    }
    var previewName: String { "app_icon_\(rawValue)_preview" }
    var title: LocalizedStringKey {
        switch self {
        case .classic: "Classic icon"
        case .quietIsland: "Quiet Island"
        case .together: "Together"
        case .moonNap: "Moon nap"
        case .pixelFriend: "Pixel friend"
        case .warmPaw: "Warm paw"
        }
    }

    @MainActor
    static var current: Self {
        allCases.first { $0.alternateName == UIApplication.shared.alternateIconName } ?? .classic
    }
}

private struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = AppIconChoice.current
    @State private var changing: AppIconChoice?
    @State private var showsError = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 16)], spacing: 16) {
                    ForEach(AppIconChoice.allCases) { icon in
                        Button { changeIcon(to: icon) } label: {
                            VStack(spacing: 12) {
                                Image(icon.previewName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                                    .accessibilityHidden(true)
                                Text(icon.title)
                                    .font(.subheadline.weight(.medium))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                if changing == icon {
                                    ProgressView().frame(height: 20)
                                } else {
                                    Image(systemName: selected == icon ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected == icon ? PetDesign.accent : PetDesign.separator)
                                        .frame(height: 20)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .padding(.horizontal, 8)
                            .petSurface()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.title)
                        .accessibilityAddTraits(selected == icon ? .isSelected : [])
                    }
                }
                .disabled(changing != nil || !UIApplication.shared.supportsAlternateIcons)
                .padding(24)
                Text(UIApplication.shared.supportsAlternateIcons
                    ? "Choose an icon for your Home Screen. You can return to the classic icon at any time."
                    : "Changing the app icon is not available on this device.")
                    .font(.footnote)
                    .foregroundStyle(PetDesign.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
            .petPage()
            .navigationTitle("App icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(changing != nil)
                }
            }
        }
        .interactiveDismissDisabled(changing != nil)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { selected = .current }
        }
        .alert("Could not change the icon", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again. Your current icon has been kept.")
        }
    }

    private func changeIcon(to icon: AppIconChoice) {
        guard changing == nil, icon != .current, UIApplication.shared.supportsAlternateIcons else { return }
        changing = icon
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(icon.alternateName)
            } catch {
                showsError = true
            }
            selected = .current
            changing = nil
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
                .buttonStyle(PetPrimaryButtonStyle()).controlSize(.large)
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
