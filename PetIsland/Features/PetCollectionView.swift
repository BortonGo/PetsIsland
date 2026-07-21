import SwiftUI

struct PetCollectionView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var editorRoute: PetEditorRoute?
    @State private var pendingRemoval: PetProfile?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    partyHeader
                    partyPreview
                    collection
                    addButton
                }
                .padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("My pets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            PetProfileEditor(
                initialProfile: route.profile,
                isNew: route.isNew,
                sessionIsActive: controller.session != nil
            ) { profile in
                if route.isNew {
                    _ = await controller.addPet(profile)
                } else {
                    _ = await controller.updatePet(profile)
                }
            }
        }
        .confirmationDialog(
            "Remove this pet?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { pet in
            Button("Remove \(pet.name)", role: .destructive) {
                Task { _ = await controller.removePet(id: pet.id) }
            }
        } message: { _ in
            Text("Session history will stay on this device.")
        }
    }

    private var partyHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Dynamic Island party", systemImage: "person.3.fill")
                    .font(.title3.bold())
                Spacer()
                Text("\(controller.activeParty.count)/3")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
            }
            Text("The lead pet appears in compact mode. Expand the activity to see the whole party.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if controller.session != nil {
                Label("The party is locked until the current session ends.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partyPreview: some View {
        HStack(alignment: .bottom, spacing: -10) {
            ForEach(Array(controller.activeParty.enumerated()), id: \.element.id) { index, pet in
                VStack(spacing: 5) {
                    ZStack(alignment: .topTrailing) {
                        PetArtwork(
                            species: pet.species,
                            coat: pet.coat,
                            customColor: pet.customColor,
                            breed: pet.resolvedBreed,
                            pose: pet.species == .parrot ? .fly : .idle,
                            direction: index.isMultiple(of: 2) ? .right : .left,
                            step: index,
                            animatesMotion: false
                        )
                        .frame(width: 82, height: 70)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Color.white.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(alignment: .bottom) {
                            Capsule()
                                .fill(.black.opacity(0.18))
                                .frame(width: 62, height: 4)
                                .padding(.bottom, 7)
                                .zIndex(-1)
                        }
                        if index == 0 {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                    }
                    Text(pet.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                }
                .zIndex(Double(controller.activeParty.count - index))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .center)
        .padding(.horizontal, 12)
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.38), .cyan.opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(.black.opacity(0.18))
                .frame(height: 6)
                .padding(.horizontal, 34)
                .padding(.bottom, 34)
                .zIndex(-1)
        }
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collection")
                .font(.headline)

            ForEach(controller.pets) { pet in
                petRow(pet)
            }
        }
    }

    private func petRow(_ pet: PetProfile) -> some View {
        let partyIndex = controller.activePetIDs.firstIndex(of: pet.id)
        let isActive = partyIndex != nil
        let isLead = partyIndex == 0

        return HStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                let colors = PetColors.resolve(
                    species: pet.species,
                    coat: pet.coat,
                    customColor: pet.customColor
                )

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                colors.secondary.opacity(0.28),
                                colors.primary.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Capsule()
                    .fill(colors.detail.opacity(0.14))
                    .frame(width: 46, height: 4)
                    .padding(.bottom, 7)

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
                .frame(width: 58, height: 50)
                .padding(.bottom, pet.species == .parrot ? 1 : 3)
            }
            .frame(width: 70, height: 62)

            VStack(alignment: .leading, spacing: 3) {
                Text(pet.name).font(.headline).lineLimit(1)
                Text(pet.species.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLead {
                    Label("Lead pet", systemImage: "crown.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                } else if isActive {
                    Text("On the island")
                        .font(.caption2.bold())
                        .foregroundStyle(.tint)
                }
            }

            Spacer(minLength: 4)

            Menu {
                if !isLead {
                    Button {
                        Task { _ = await controller.makeLeadPet(id: pet.id) }
                    } label: {
                        Label("Make lead", systemImage: "crown")
                    }
                }
                Button {
                    Task { _ = await controller.togglePetActive(id: pet.id) }
                } label: {
                    Label(
                        isActive ? "Remove from island" : "Add to island",
                        systemImage: isActive ? "minus.circle" : "plus.circle"
                    )
                }
                .disabled((isActive && controller.activeParty.count == 1) || (!isActive && controller.activeParty.count == 3))

                Button {
                    editorRoute = PetEditorRoute(profile: pet, isNew: false)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }

                if controller.pets.count > 1 {
                    Button(role: .destructive) {
                        pendingRemoval = pet
                    } label: {
                        Label("Remove pet", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(controller.session != nil)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private var addButton: some View {
        Button {
            let species = PetSpecies.selectableCases[
                controller.pets.count % PetSpecies.selectableCases.count
            ]
            let profile = PetProfile(
                id: UUID(),
                name: String(localized: "New friend"),
                species: species,
                coat: .sunrise,
                createdAt: .now
            )
            editorRoute = PetEditorRoute(profile: profile, isNew: true)
        } label: {
            Label("Add a pet", systemImage: "plus.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(controller.session != nil || controller.pets.count >= 12)
    }
}

private struct PetEditorRoute: Identifiable {
    let id = UUID()
    let profile: PetProfile
    let isNew: Bool
}

private struct PetProfileEditor: View {
    let isNew: Bool
    let sessionIsActive: Bool
    let onSave: (PetProfile) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PetProfile
    @State private var isSaving = false

    init(
        initialProfile: PetProfile,
        isNew: Bool,
        sessionIsActive: Bool,
        onSave: @escaping (PetProfile) async -> Void
    ) {
        self.isNew = isNew
        self.sessionIsActive = sessionIsActive
        self.onSave = onSave
        _draft = State(initialValue: initialProfile)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PetHabitatView(
                        profile: draft,
                        snapshot: .init(
                            pose: draft.species == .parrot ? .fly : .idle,
                            position: 0.5,
                            direction: .right,
                            revision: 0,
                            generatedAt: .now
                        )
                    )
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets())
                }

                Section("Your pet") {
                    PetPicker(profile: $draft)
                }
            }
            .navigationTitle(isNew ? "New pet" : "Edit pet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            await onSave(draft)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(isSaving || sessionIsActive)
                }
            }
        }
    }
}
