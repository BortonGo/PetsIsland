import SwiftUI

struct PetWardrobeView: View {
    @ObservedObject var controller: PetSessionController
    let petID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @PetReduceMotion private var reduceMotion
    @State private var selection: PetAccessory?
    @State private var pose: PetPose = .idle
    @State private var previewStart = Date.now
    @State private var isVisible = false
    @State private var previewIsInViewport = false
    @State private var saveError: String?

    init(controller: PetSessionController, petID: UUID, tryingOn: PetAccessory? = nil) {
        self.controller = controller
        self.petID = petID
        _selection = State(initialValue: tryingOn ?? controller.pets.first { $0.id == petID }?.outfit?.headwear)
    }

    private var pet: PetProfile? { controller.pets.first { $0.id == petID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let pet {
                    VStack(spacing: 20) {
                        preview(pet)
                        Text("Buy once and dress any of your pets. The same accessory can be worn by several friends.")
                            .font(.caption).foregroundStyle(PetDesign.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 240 : 140))], spacing: 12) {
                            tile(nil, pet: pet)
                            ForEach(PetAccessory.allCases) { item in tile(item, pet: pet) }
                        }
                        if dynamicTypeSize.isAccessibilitySize { purchaseControls(pet) }
                    }
                    .padding(20)
                } else {
                    ContentUnavailableView("Pet not found", systemImage: "pawprint")
                }
            }
            .petPage()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let pet, !dynamicTypeSize.isAccessibilitySize {
                    purchaseControls(pet)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(PetDesign.background)
                        .overlay(alignment: .top) { Divider().overlay(PetDesign.separator) }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("wardrobe.pinnedControls")
                }
            }
            .navigationTitle("Wardrobe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .alert("Could not save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func purchaseControls(_ pet: PetProfile) -> some View {
        VStack(spacing: 10) {
            Label("\(controller.arcadeProgress.coins) coins", systemImage: "dollarsign.circle")
                .font(.caption.monospacedDigit())
                .foregroundStyle(PetDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel("\(controller.arcadeProgress.coins) coins")
                .accessibilityIdentifier("wardrobe.balance")
            availabilityMessage(pet)
            action(pet)
        }
        .frame(maxWidth: .infinity)
    }

    private func preview(_ pet: PetProfile) -> some View {
        VStack(spacing: 12) {
            Text(pet.name).font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Some approved run frames last 80 ms; a 12 Hz clock skips them.
            // The equatable sprite resolves only the frames that actually change.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isVisible || !previewIsInViewport || reduceMotion || scenePhase != .active || pose == .idle || pose == .sleep)) { context in
                let clip = PetAnimationLibrary.naturalClip(for: pet.species, breed: pet.resolvedBreed, pose: pose)
                PetArtwork(
                    species: pet.species, coat: pet.coat, customColor: pet.customColor,
                    breed: pet.resolvedBreed, pose: pose,
                    step: reduceMotion ? 0 : clip.frameIndex(at: context.date.timeIntervalSince(previewStart)),
                    animatesMotion: false, usesNaturalGait: true, accessory: selection
                )
                .frame(width: 220, height: 176)
            }
            .accessibilityHidden(true)
            .onPetViewportVisibilityChange { previewIsInViewport = $0 }
            Text(selection == pet.outfit?.headwear ? "Wearing now" : "Trying on")
                .font(.caption).foregroundStyle(PetDesign.secondary)
            Picker("Preview movement", selection: $pose) {
                Text("Standing").tag(PetPose.idle)
                Text("Walking").tag(PetPose.walk)
                Text("Running").tag(PetPose.run)
                Text("Resting").tag(PetPose.sleep)
            }
            .pickerStyle(.menu)
            .frame(minHeight: 44)
            .accessibilityIdentifier("wardrobe.movement")
            .onChange(of: pose) { _, _ in previewStart = .now }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .petSurface(radius: 24)
    }

    private func tile(_ item: PetAccessory?, pet: PetProfile) -> some View {
        let owned = item.map { controller.arcadeProgress.ownedAccessories.contains($0) } ?? true
        let selected = selection == item
        return Button { selection = item } label: {
            VStack(spacing: 10) {
                Group {
                    if let item { PetAccessoryIcon(accessory: item) }
                    else { Image(systemName: "pawprint").font(.title2).foregroundStyle(PetDesign.secondary) }
                }
                .frame(height: 44)
                Text(item?.title ?? String(localized: "No accessory"))
                    .font(.subheadline.weight(.semibold))
                if item == pet.outfit?.headwear {
                    Label("Wearing now", systemImage: "checkmark.circle.fill").font(.caption)
                } else if owned {
                    Text("In wardrobe").font(.caption).foregroundStyle(PetDesign.secondary)
                } else if let item {
                    Label("\(item.price)", systemImage: "dollarsign.circle").font(.caption.monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity).padding(14).petSurface(radius: 20)
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? PetDesign.accent : .clear, lineWidth: 2) }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy)
        .accessibilityLabel(item?.title ?? String(localized: "No accessory"))
        .accessibilityValue(item == pet.outfit?.headwear ? String(localized: "Wearing now")
            : owned ? String(localized: "In wardrobe") : String(localized: "\(item?.price ?? 0) coins"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("wardrobe.select.\(item?.rawValue ?? "none")")
    }

    @ViewBuilder
    private func action(_ pet: PetProfile) -> some View {
        if let item = selection, !controller.arcadeProgress.ownedAccessories.contains(item) {
            let missing = max(item.price - controller.arcadeProgress.coins, 0)
            Button {
                Task {
                    if !(await controller.purchaseAccessory(item)), !controller.arcadeProgress.ownedAccessories.contains(item) {
                        showSaveError()
                    }
                }
            } label: {
                Label("Buy for \(item.price) coins", systemImage: "dollarsign.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .disabled(controller.isBusy || missing > 0)
            .accessibilityIdentifier("wardrobe.buy")
        } else {
            let away = controller.isPetOnDiscoveryWalk(pet.id)
            let wearing = selection == pet.outfit?.headwear
            Button {
                let chosen = selection
                Task { if !(await controller.equipAccessory(chosen, for: pet.id)) { showSaveError() } }
            } label: {
                Label(wearing ? "Wearing now" : selection == nil ? "Remove accessory" : "Wear accessory",
                      systemImage: wearing ? "checkmark.circle.fill" : "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PetPrimaryButtonStyle())
            .disabled(controller.isBusy || away || wearing)
            .accessibilityIdentifier("wardrobe.apply")
        }
    }

    @ViewBuilder
    private func availabilityMessage(_ pet: PetProfile) -> some View {
        if let item = selection, !controller.arcadeProgress.ownedAccessories.contains(item) {
            let missing = max(item.price - controller.arcadeProgress.coins, 0)
            if missing > 0 {
                Text("\(missing) more coins needed. Earn coins in arcade games.")
                    .font(.caption).foregroundStyle(PetDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("wardrobe.availability")
            }
        } else if controller.isPetOnDiscoveryWalk(pet.id) {
            Text("Outfits can be changed when this pet returns.")
                .font(.caption).foregroundStyle(PetDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("wardrobe.availability")
        }
    }

    private func showSaveError() {
        saveError = controller.alertMessage ?? String(localized: "Your changes could not be saved. Please try again.")
        controller.alertMessage = nil
    }
}

struct PetAccessoryIcon: View {
    let accessory: PetAccessory
    var body: some View {
        let pattern = PetAccessoryAssets.catalog?.art[accessory.rawValue]
        PetAccessoryArtwork(accessory: accessory)
            .frame(width: 60, height: 60 * CGFloat(pattern?.rows.count ?? 16) / CGFloat(pattern?.width ?? 24))
    }
}

struct PetAccessoryShopSection: View {
    @ObservedObject var controller: PetSessionController
    let pet: PetProfile
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var tryingOn: PetAccessory?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessories", systemImage: "sparkles").font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Try it on before buying. One purchase for all your pets.")
                .font(.caption).foregroundStyle(PetDesign.secondary)
            ForEach(PetAccessory.allCases) { item in
                Button { tryingOn = item } label: {
                    (dynamicTypeSize.isAccessibilitySize
                     ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                     : AnyLayout(HStackLayout(spacing: 14))) {
                        PetAccessoryIcon(accessory: item).frame(width: 68, height: 48)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline)
                            if controller.arcadeProgress.ownedAccessories.contains(item) {
                                Label("In wardrobe", systemImage: "checkmark.circle.fill").font(.caption)
                            } else {
                                Label("\(item.price)", systemImage: "dollarsign.circle").font(.caption.monospacedDigit())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Label("Try on", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16).petSurface(radius: 20).contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(controller.arcadeProgress.ownedAccessories.contains(item)
                    ? String(localized: "In wardrobe") : String(localized: "\(item.price) coins"))
                .accessibilityHint("Try on")
                .accessibilityIdentifier("accessories.shop.\(item.rawValue)")
            }
        }
        .sheet(item: $tryingOn) { item in
            PetWardrobeView(controller: controller, petID: pet.id, tryingOn: item)
        }
    }
}
