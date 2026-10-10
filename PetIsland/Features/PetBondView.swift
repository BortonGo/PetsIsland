import SwiftUI

/// Uses the card's existing, visibility-gated refresh. No additional clock or
/// animation is started for friendship, and the pet artwork remains untouched.
struct PetBondView: View {
    @ObservedObject var controller: PetSessionController
    let overview: PetProfileOverview
    let date: Date
    @State private var isSharing = false
    @State private var feedback: String?
    @State private var errorMessage: String?

    private var bond: PetBond { controller.bond(for: overview.pet.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your friendship", systemImage: "heart")
                .font(PetDesign.title(.title3)).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                Text(bond.stage.title).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("profile.bond.stage")
                ProgressView(value: bond.stageProgress).tint(PetDesign.accent)
                    .accessibilityLabel(Text("Your friendship"))
                    .accessibilityValue(Text(bond.stage.title))
                Text(bond.stage.detail).font(.caption).foregroundStyle(PetDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                guard !isSharing else { return }
                isSharing = true
                Task {
                    defer { isSharing = false }
                    if await controller.sharePetMoment(with: overview.pet.id) {
                        feedback = String(localized: "\(overview.pet.name) is happy to have you close.")
                    } else if let error = controller.alertMessage {
                        errorMessage = error
                        controller.alertMessage = nil
                    }
                }
            } label: {
                Label(bond.canShare(.attention, at: date) ? "Spend time together" : "A little moment together", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PetQuietButtonStyle())
            .disabled(isSharing || !controller.canSharePetMoment(with: overview.pet.id, at: date))
            .accessibilityIdentifier("profile.bond.attention")

            if let feedback {
                Text(feedback).font(.caption).foregroundStyle(PetDesign.secondary)
                    .accessibilityIdentifier("profile.bond.feedback")
            } else if overview.location == .walking {
                Text("A quiet moment will be waiting after the walk.")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    let route = PetBond.familiarRoute(in: overview.memories)
                    if bond.familiarCare == nil && bond.familiarGame == nil && route == nil {
                        Text("Shared favourites appear as you spend time together.")
                            .foregroundStyle(PetDesign.secondary)
                    }
                    if let care = bond.familiarCare {
                        habit("A familiar ritual", value: care.title, symbol: care.symbol)
                    }
                    if let game = bond.familiarGame {
                        habit("Often played together", value: game.friendshipTitle, symbol: "gamecontroller")
                    }
                    if let route {
                        habit("A familiar path", value: route.discoveryTitle, symbol: "safari")
                    }
                    Text("Attention, useful care and finishing a game with points each bring you closer once a day. Time away never reduces your friendship.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                        .accessibilityIdentifier("profile.bond.explanation")
                    Text("Rituals and games count your first shared choice of the day. A favourite appears after at least three repeats; equal favourites stay undecided.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                }.font(.subheadline).padding(.top, 12)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text("Little habits").font(.subheadline.weight(.medium))
            }
            .accessibilityIdentifier("profile.bond.habits")
        }
        .padding(18).petSurface(radius: 22)
        .alert("Could not save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func habit(_ title: LocalizedStringKey, value: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(PetDesign.secondary)
                Text(value).font(.subheadline.weight(.medium))
            }
        } icon: { Image(systemName: symbol).foregroundStyle(PetDesign.secondary) }
        .accessibilityElement(children: .combine)
    }
}

extension PetBond.Stage {
    var title: String {
        switch self {
        case .meeting: String(localized: "Getting acquainted")
        case .familiar: String(localized: "Growing closer")
        case .trusting: String(localized: "Trusted friend")
        case .inseparable: String(localized: "Inseparable")
        }
    }
    var detail: String {
        switch self {
        case .meeting: String(localized: "Every little moment helps you get to know each other.")
        case .familiar: String(localized: "Your shared moments are becoming a lovely habit.")
        case .trusting: String(localized: "There is comfort in your company.")
        case .inseparable: String(localized: "A familiar friend, always happy to see you.")
        }
    }
}

private extension MiniGameKind {
    var friendshipTitle: String {
        switch self {
        case .skyHop: String(localized: "Sky Hop")
        case .skyPaws: String(localized: "Sky Paws")
        case .petsDash: String(localized: "Pets Dash")
        case .bubblePaws: String(localized: "Bubble Paws")
        }
    }
}
