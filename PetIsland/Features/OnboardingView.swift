import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: PetSessionController
    @State private var page = 0
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
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut, value: page)

                Button {
                    if page < 2 { page += 1 }
                    else { Task { await controller.completeOnboarding(profile: draft) } }
                } label: {
                    Text(page == 2 ? "Meet my pet" : "Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
            .background(Color(.systemGroupedBackground))
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        OnboardingPage(
            title: "A small companion with a life of its own",
            message: "Pixel lives in the enclosure widget. When you want company, take him with you to Dynamic Island."
        ) {
            PetHabitatView(profile: draft, snapshot: .init(pose: .jump, position: 0.5, direction: .right, revision: 1, generatedAt: .now))
                .frame(height: 270)
        }
    }

    private var choosePet: some View {
        OnboardingPage(
            title: "Meet your dog",
            message: "Choose a name and coat for the first Pet Island resident. More animals will arrive in future versions."
        ) {
            PetPicker(profile: $draft, allowedSpecies: [.dog])
        }
    }

    private var firstSession: some View {
        OnboardingPage(
            title: "Home or Dynamic Island",
            message: "Move Pixel between the enclosure and Dynamic Island whenever you like. Throw the ball from the widget and watch his mood change."
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
                Label("No timer · works offline", systemImage: "pawprint.fill")
                    .font(.headline)
                    .padding(12)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            content
            Text(title).font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer(minLength: 36)
        }
    }
}
