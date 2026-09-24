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
            VStack(spacing: 16) {
                TabView(selection: $page) {
                    welcome.tag(0)
                    choosePet.tag(1)
                    firstSession.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? nil : .easeInOut, value: page)

                HStack(spacing: 7) {
                    ForEach(0..<3) { index in
                        Capsule().fill(index == page ? PetDesign.accent : PetDesign.separator)
                            .frame(width: index == page ? 22 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)

                Button {
                    if page < 2 { page += 1 }
                    else {
                        isSaving = true
                        Task {
                            if !(await controller.completeOnboarding(profile: draft)) {
                                controller.alertMessage = nil
                                saveFailed = true
                            }
                            isSaving = false
                        }
                    }
                } label: {
                    Text(page == 2 ? String(localized: "Meet my pet") : String(localized: "Continue"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(PetPrimaryButtonStyle())
                .controlSize(.large)
                .disabled(isSaving)
            }
            .padding(20)
            .petPage()
        }
        .interactiveDismissDisabled()
        .alert("Your pet could not be saved", isPresented: $saveFailed) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your draft is still here. Please try saving again.")
        }
    }

    private var welcome: some View {
        OnboardingPage(
            title: "Meet your pet",
            message: "Give your pet a home on the island. Stroke them, play together, and choose a favorite landscape."
        ) {
            HabitatEditorCanvas(theme: .meadow, pets: [draft], vitalsByPetID: [:], petScale: 1.4)
                .frame(height: 270)
        }
    }

    private var choosePet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose your first pet").font(PetDesign.title(.title2))
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
        OnboardingPage(
            title: "Take your pet with you",
            message: "Your pet can join you on the Lock Screen and Dynamic Island on supported iPhones. You can bring them home whenever you like."
        ) {
            VStack(spacing: 18) {
                PetPortraitArtwork(
                    species: draft.species,
                    coat: draft.coat,
                    customColor: draft.customColor,
                    breed: draft.resolvedBreed,
                    pose: .sleep
                )
                    .frame(width: 190, height: 150)
                Label("Your pets · works offline", systemImage: "pawprint.fill")
                    .font(.headline)
                    .padding(12)
                    .background(.thinMaterial, in: Capsule())
            }
        }
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
                Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer(minLength: 36)
            }
        }
    }
}
