import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: PetSessionController
    @State private var page = 0
    @PetReduceMotion private var reduceMotion
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var draft = PetProfile(
        id: UUID(),
        name: "Pixel",
        species: .dog,
        coat: .sunrise,
        createdAt: .now
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch page {
                    case 0: welcome
                    case 1: choosePet
                    default: firstSession
                    }
                }
                .id(page)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .disabled(isSaving)

                Button {
                    if page < 2 { move(to: page + 1) }
                    else { savePet() }
                } label: {
                    HStack {
                        if isSaving { ProgressView().tint(PetDesign.onAccent) }
                        Text(isSaving ? String(localized: "Saving your pet…") : nextTitle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .padding(.vertical, 7)
                }
                .buttonStyle(PetPrimaryButtonStyle())
                .controlSize(.large)
                .disabled(isSaving)
                .accessibilityIdentifier("onboarding.next")
                .padding(20)
            }
            .petPage()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if page > 0 {
                        Button { move(to: page - 1) } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .accessibilityIdentifier("onboarding.back")
                        .disabled(isSaving)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Step \(page + 1) of 3")
                        .font(.subheadline)
                        .foregroundStyle(PetDesign.secondary)
                        .accessibilityIdentifier("onboarding.step")
                }
            }
        }
        .interactiveDismissDisabled()
        .alert("Your pet could not be saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your draft is still here. Please try saving again.")
        }
    }

    private var nextTitle: String {
        switch page {
        case 0: String(localized: "Choose a pet")
        case 1: String(localized: "Continue")
        default: String(localized: "Go to the island")
        }
    }

    private func move(to nextPage: Int) {
        // Review the exact name that will be saved, including the default for
        // an empty field. The draft stays here when the user goes back.
        if page == 1 { draft.normalizeName() }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page = nextPage }
    }

    private func savePet() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            if !(await controller.completeOnboarding(profile: draft)) {
                controller.alertMessage = nil
                saveFailed = true
            }
            isSaving = false
        }
    }

    private var welcome: some View {
        OnboardingPage(
            title: "Meet your pet",
            message: "Give your pet a home on the island. Stroke them, play together, and choose a favorite landscape."
        ) {
            HabitatEditorCanvas(theme: .meadow, pets: [draft], vitalsByPetID: [:], petScale: 1.4)
                .frame(height: 270)
                .accessibilityHidden(true)
        }
    }

    private var choosePet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your first pet").font(PetDesign.title(.title2))
                    .accessibilityAddTraits(.isHeader)
                Text("Give your new friend a name, then choose an animal and appearance.")
                    .foregroundStyle(.secondary)
                PetPicker(profile: $draft, allowedSpecies: PetSpecies.selectableCases)
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private var firstSession: some View {
        ScrollView {
            VStack(spacing: 20) {
                PetPortraitArtwork(
                    species: draft.species,
                    coat: draft.coat,
                    customColor: draft.customColor,
                    breed: draft.resolvedBreed,
                    pose: .sleep
                )
                .frame(width: 190, height: 150)
                .accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(verbatim: draft.name)
                        .font(PetDesign.title(.title2))
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("onboarding.petName")
                    Text("Your pet starts in the enclosure. You can explore the island together at your own pace.")
                        .foregroundStyle(PetDesign.secondary)
                }
                .multilineTextAlignment(.center)
                PetGettingStartedGuide(includesCustomization: false)
            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }
}

#if DEBUG
#Preview("Знакомство с питомцем") {
    OnboardingView(
        controller: PetSessionController(store: InMemoryPetStore())
    )
}
#endif

private struct OnboardingPage<Content: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 10)
                content
                Text(title).font(PetDesign.title()).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer(minLength: 36)
            }
        }
    }
}

/// The same short explanations are available again in Settings, without
/// adding permanent cards or a second tutorial to the main island.
struct PetGettingStartedGuide: View {
    var includesCustomization = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            tip("Walks", symbol: "safari",
                message: "Open the compass on the Island tab to choose a route. Your pet explores and brings back a find. While away, they cannot join you on the Lock Screen.",
                id: "walks")
            tip("Take with you", symbol: "iphone",
                message: "Use Take with you on the Island tab for company on the Lock Screen and, on supported iPhones, Dynamic Island. The same button brings your pet home.",
                id: "companion")
            if includesCustomization {
                tip("Care and wardrobe", symbol: "pawprint",
                    message: "Open Pets and tap a pet’s card for care and Wardrobe. Supplies and accessories are in Arcade → Shop.",
                    id: "wardrobe")
                tip("Furniture", symbol: "sofa",
                    message: "On Island, tap the palette, then Furniture to place your items. Buy new ones in Arcade → Shop → Furniture.",
                    id: "furniture")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tip(_ title: LocalizedStringKey, symbol: String, message: LocalizedStringKey, id: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(PetDesign.accent).accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text(message).font(.footnote).foregroundStyle(PetDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guide.\(id)")
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Isolated first-launch fixture. It never reads or replaces the app's save.
struct PetOnboardingDebugHostView: View {
    @StateObject private var controller = PetSessionController(
        store: OnboardingPreviewStore(), arcadeStore: InMemoryArcadeStore()
    )

    var body: some View {
        Group {
            if controller.operation == .loading { ProgressView() }
            else { HomeView(controller: controller) }
        }
        .task { await controller.bootstrap() }
        .fullScreenCover(isPresented: Binding(
            get: { controller.operation != .loading && !controller.completedOnboarding },
            set: { _ in }
        )) { OnboardingView(controller: controller) }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-onboarding-light") ? .light : .dark)
        .environment(\.petMinimizeMotion, true)
    }
}

private actor OnboardingPreviewStore: PetStore {
    private var state = PersistedAppState()
    private var failed = false
    func load() -> PersistedAppState { state }
    func save(_ candidate: PersistedAppState) throws {
        if candidate.completedOnboarding, !failed,
           ProcessInfo.processInfo.arguments.contains("-onboarding-fail-save") {
            failed = true
            throw CocoaError(.fileWriteOutOfSpace)
        }
        state = candidate
    }
}
#endif
