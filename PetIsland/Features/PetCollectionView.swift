import SwiftUI

struct PetCollectionView: View {
    @ObservedObject var controller: PetSessionController
    var showsDismissButton = true
    @Environment(\.dismiss) private var dismiss
    @State private var editorRoute: PetEditorRoute?
    @State private var pendingRemoval: PetProfile?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    partyHeader
                    collection
                    addButton
                }
                .padding(24)
            }
            .petPage()
            .navigationTitle(showsDismissButton ? "My pets" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(showsDismissButton ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                if showsDismissButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            PetProfileEditor(
                initialProfile: route.profile,
                isNew: route.isNew,
                sessionIsActive: controller.session?.petID == route.profile.id && !route.isNew
            ) { profile in
                if route.isNew {
                    return await controller.addPet(profile)
                } else {
                    return await controller.updatePet(profile)
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
            partyHeadingLayout {
                PetScreenHeading(title: "Pets")
                Text("\(controller.pets.count)/12")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            DisclosureGroup("Where pets appear") {
                Text("Only the lead pet appears on Dynamic Island. Choose enclosure residents on the Island tab.")
                    .padding(.top, 6)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if controller.session != nil {
                Label("Bring your travelling pet home before editing it.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var partyHeadingLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout())
    }

    private var collection: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 145), spacing: 14)], spacing: 14) {
            ForEach(controller.pets) { pet in petRow(pet) }
        }
    }

    private func petRow(_ pet: PetProfile) -> some View {
        let partyIndex = controller.activePetIDs.firstIndex(of: pet.id)
        let isLead = partyIndex == 0

        return VStack(alignment: .leading, spacing: 0) {
            Button { editorRoute = PetEditorRoute(profile: pet, isNew: false) } label: {
                VStack(alignment: .leading, spacing: 8) {
                    PetArtwork(
                        species: pet.species, coat: pet.coat, customColor: pet.customColor,
                        breed: pet.resolvedBreed, pose: pet.species == .parrot ? .fly : .idle,
                        animatesMotion: false
                    )
                    .frame(height: 105)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 15)
                    Text(pet.name).font(.headline).lineLimit(1)
                    Text(pet.resolvedBreed?.displayName ?? pet.species.displayName)
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .disabled(controller.isBusy)
            HStack {
                Group {
                    if isLead { Label("Lead pet", systemImage: "crown") }
                    else if controller.habitat.configuration.residentPetIDs.contains(pet.id) { Text("In the enclosure") }
                    else if controller.habitat.configuration.leadDynamicIslandPetID == pet.id { Text("On Dynamic Island") }
                    else { Text("At home") }
                }
                .font(.caption2)
                .foregroundStyle(PetDesign.secondary)
                .padding(.leading, 16)
                Spacer(minLength: 0)
            Menu {
                if !isLead {
                    Button {
                        Task { _ = await controller.makeLeadPet(id: pet.id) }
                    } label: {
                        Label("Make lead", systemImage: "crown")
                    }
                    .disabled(controller.session != nil)
                }
                Button {
                    editorRoute = PetEditorRoute(profile: pet, isNew: false)
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .disabled(controller.session?.petID == pet.id)

                if controller.pets.count > 1 {
                    Button(role: .destructive) {
                        pendingRemoval = pet
                    } label: {
                        Label("Remove pet", systemImage: "trash")
                    }
                    .disabled(controller.session?.petID == pet.id)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(controller.isBusy)
            .accessibilityLabel("Actions for \(pet.name)")
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 5)
        .petSurface()
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isLead ? PetDesign.separator : .clear, lineWidth: 1)
        }
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
        .buttonStyle(PetQuietButtonStyle())
        .disabled(controller.isBusy || controller.pets.count >= 12)
    }
}

#if DEBUG
private struct PetCollectionViewPreview: View {
    @StateObject private var controller = PetSessionController(store: InMemoryPetStore())

    var body: some View {
        PetCollectionView(controller: controller)
            .task { await controller.bootstrap() }
    }
}

#Preview("Коллекция питомцев") {
    PetCollectionViewPreview()
}
#endif

private struct PetEditorRoute: Identifiable {
    let id = UUID()
    let profile: PetProfile
    let isNew: Bool
}

private struct PetProfileEditor: View {
    let isNew: Bool
    let sessionIsActive: Bool
    let onSave: (PetProfile) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PetProfile
    @State private var isSaving = false
    @State private var saveFailed = false

    init(
        initialProfile: PetProfile,
        isNew: Bool,
        sessionIsActive: Bool,
        onSave: @escaping (PetProfile) async -> Bool
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
                    HabitatEditorCanvas(theme: .meadow, pets: [draft], vitalsByPetID: [:], petScale: 1.25)
                    .frame(height: 190)
                    .listRowInsets(EdgeInsets())
                }

                Section("Your pet") {
                    PetPicker(profile: $draft)
                }
            }
            .scrollContentBackground(.hidden)
            .petPage()
            .alert("Could not save", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your draft is safe. Please try saving again.")
            }
            .interactiveDismissDisabled(isSaving)
            .navigationTitle(isNew ? String(localized: "New friend") : String(localized: "Pet details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            let saved = await onSave(draft)
                            isSaving = false
                            if saved { dismiss() } else { saveFailed = true }
                        }
                    }
                    .disabled(isSaving || sessionIsActive)
                }
            }
        }
    }
}
