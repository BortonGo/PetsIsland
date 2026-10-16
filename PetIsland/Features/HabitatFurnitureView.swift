import SwiftUI

struct HabitatFurnitureView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsShop = false
    @State private var placingItem: HabitatItemKind?
    @State private var sheetHeight: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Two ground places and one upper perch. Keep the middle free for walking.")
                        .font(.subheadline)
                        .foregroundStyle(PetDesign.secondary)
                    (dynamicTypeSize.isAccessibilitySize
                     ? AnyLayout(VStackLayout(spacing: 8))
                     : AnyLayout(HStackLayout(spacing: 8))) {
                        ForEach(HabitatFurnitureSlot.allCases) { slot in
                            VStack(spacing: 6) {
                                let item = controller.habitat.configuration.furniture.first { $0.slot == slot }?.item
                                if let item {
                                    HabitatFurnitureArtwork(item: item).frame(height: 42)
                                } else {
                                    Image(systemName: slot == .perch ? "bird" : "plus")
                                        .foregroundStyle(PetDesign.secondary).frame(height: 42)
                                }
                                Text(slot.title).font(.caption2)
                                Text(item?.title ?? String(localized: "Free place"))
                                    .font(.caption2.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity).padding(8).petSurface(radius: 14)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("furniture.slot.\(slot.rawValue)")
                        }
                    }
                    Text("One bulky item at a time: a box or a leaf nest. Everything else stays in your collection.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                    Text("Tap an item to place, move or remove it. Changes save immediately.")
                        .font(.subheadline).foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 260 : 140))], spacing: 12) {
                        ForEach(HabitatItemKind.allCases) { item in
                            itemTile(item)
                        }
                    }
                    Button { showsShop = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "storefront")
                            Text("Open shop").font(.subheadline.weight(.semibold))
                            Spacer()
                            Label("\(controller.arcadeProgress.coins)", systemImage: "dollarsign.circle")
                                .font(.caption.monospacedDigit())
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .padding(16)
                        .petSurface(radius: 18)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("furniture.shop")
                }
                .padding(20)
            }
            .petPage()
            .navigationTitle("Furniture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showsShop) {
                HabitatFurnitureShopView(controller: controller)
            }
        }
        .presentationDetents([.medium, .large], selection: $sheetHeight)
        .presentationDragIndicator(.visible)
        .sheet(item: $placingItem) { item in
            HabitatItemPlacementView(controller: controller, item: item)
        }
    }

    private func itemTile(_ item: HabitatItemKind) -> some View {
        let owned = controller.arcadeProgress.ownedHabitatItems.contains(item)
        let slot = owned ? controller.habitat.configuration.furniture.first { $0.item == item }?.slot : nil
        let placed = slot != nil
        return Button {
            if owned {
                placingItem = item
            } else {
                showsShop = true
            }
        } label: {
            VStack(spacing: 10) {
                HabitatFurnitureArtwork(item: item)
                    .frame(width: 92, height: 66)
                    .saturation(owned ? 1 : 0)
                    .opacity(owned ? 1 : 0.45)
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .overlay(alignment: .topTrailing) {
                        if !owned || placed {
                            Image(systemName: owned ? "checkmark.circle.fill" : "lock.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(PetDesign.accent)
                                .padding(5)
                                .background(PetDesign.surface, in: Circle())
                        }
                    }
                Text(item.title).font(.subheadline.weight(.semibold))
                if owned {
                    if let slot {
                        Text(slot.title)
                            .font(.caption).foregroundStyle(PetDesign.secondary)
                    }
                    Text(placed ? "Move or remove" : "Place item")
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                } else {
                    Label("\(item.price)", systemImage: "dollarsign.circle")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(PetDesign.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .petSurface(radius: 20)
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(placed ? PetDesign.accent : .clear, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(controller.isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(placed ? .isSelected : [])
        .accessibilityValue(owned ? (slot.map { Text($0.title) } ?? Text("Purchased")) : Text("Locked"))
        .accessibilityHint(owned ? (placed ? Text("Move or remove") : Text("Place item")) : Text("Open shop"))
        .accessibilityIdentifier("furniture.\(item.rawValue)")
    }
}

/// The same permanent-item section is available in Arcade's shop and from the editor.
struct HabitatFurnitureShopSection: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var purchaseError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Furniture", systemImage: "shippingbox")
                .font(.title3.weight(.semibold))
            Text("Buy once. Place and remove whenever you like.")
                .font(.caption)
                .foregroundStyle(PetDesign.secondary)
            ForEach(HabitatItemKind.allCases) { item in
                shopItem(item)
            }
        }
        .alert("Could not save", isPresented: Binding(
            get: { purchaseError != nil },
            set: { if !$0 { purchaseError = nil } }
        )) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: {
            Text(purchaseError ?? "")
        }
    }

    private func shopItem(_ item: HabitatItemKind) -> some View {
        let owned = controller.arcadeProgress.ownedHabitatItems.contains(item)
        let missing = max(item.price - controller.arcadeProgress.coins, 0)
        return VStack(alignment: .leading, spacing: 12) {
            (dynamicTypeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
             : AnyLayout(HStackLayout(alignment: .center, spacing: 14))) {
                HabitatFurnitureArtwork(item: item)
                    .frame(width: 80, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.headline)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if owned {
                Label("Purchased", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                Text("Choose it in Enclosure → Furniture.")
                    .font(.caption)
                    .foregroundStyle(PetDesign.secondary)
            } else {
                Button {
                    Task {
                        if !(await controller.purchaseHabitatItem(item)),
                           !controller.arcadeProgress.ownedHabitatItems.contains(item),
                           controller.arcadeProgress.coins >= item.price {
                            purchaseError = controller.alertMessage
                                ?? String(localized: "Arcade progress could not be saved. Please try again.")
                            controller.alertMessage = nil
                        }
                    }
                } label: {
                    Label("Buy for \(item.price) coins", systemImage: "dollarsign.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PetPrimaryButtonStyle())
                .disabled(controller.isBusy || missing > 0)
                .accessibilityIdentifier("furniture.buy.\(item.rawValue)")
                if missing > 0 {
                    Text("\(missing) more coins needed. Earn coins in arcade games.")
                        .font(.caption)
                        .foregroundStyle(PetDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .petSurface(radius: 20)
    }
}

private struct HabitatFurnitureShopView: View {
    @ObservedObject var controller: PetSessionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("\(controller.arcadeProgress.coins) coins", systemImage: "dollarsign.circle")
                    .font(.headline.monospacedDigit())
                HabitatFurnitureShopSection(controller: controller)
            }
            .padding(20)
        }
        .petPage()
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HabitatFurnitureArtwork: View {
    let item: HabitatItemKind

    var body: some View {
        switch item {
        case .cozyBox:
            ZStack {
                HabitatCozyBoxArtwork(layer: .back)
                HabitatCozyBoxArtwork(layer: .front)
            }
        default:
            HabitatItemArtwork(item: item, layer: .complete)
        }
    }
}

private struct HabitatItemPlacementView: View {
    @ObservedObject var controller: PetSessionController
    let item: HabitatItemKind
    @Environment(\.dismiss) private var dismiss
    @State private var replacement: HabitatFurnitureSlot?
    @State private var error: String?

    private var currentSlot: HabitatFurnitureSlot? {
        controller.habitat.configuration.furniture.first { $0.item == item }?.slot
    }

    private func replacementSummary(for slot: HabitatFurnitureSlot) -> String {
        let items = controller.habitat.configuration.furnitureConflicts(for: item, in: slot)
            .map { "\($0.item.title) (\($0.slot.title))" }.joined(separator: ", ")
        return String(localized: "Returns to collection: \(items)")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HabitatFurnitureArtwork(item: item).frame(width: 120, height: 90)
                    Text(item.detail).font(.subheadline).foregroundStyle(PetDesign.secondary)
                    Text(currentSlot == nil ? "Choose a place" : "Move item").font(.headline)
                    ForEach(item.slots) { slot in
                        let conflicts = controller.habitat.configuration.furnitureConflicts(for: item, in: slot)
                        let selected = currentSlot == slot
                        Button {
                            if conflicts.isEmpty { place(in: slot, replacing: false) }
                            else { replacement = slot }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(slot.title).font(.headline)
                                    Text(selected ? String(localized: "Current place")
                                         : conflicts.isEmpty ? String(localized: "Free place")
                                         : replacementSummary(for: slot))
                                        .font(.caption).foregroundStyle(PetDesign.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill"
                                      : conflicts.isEmpty ? "plus.circle" : "arrow.triangle.2.circlepath")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(selected ? PetDesign.accent : PetDesign.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(16).petSurface(radius: 18)
                        }
                        .buttonStyle(.plain).disabled(controller.isBusy || selected)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("furniture.place.\(slot.rawValue)")
                    }
                    if item.isBulky, controller.habitat.configuration.furniture.contains(where: { $0.item.isBulky && $0.item != item }) {
                        Text("The box and leaf nest share one large-item space.")
                            .font(.caption).foregroundStyle(PetDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if currentSlot != nil {
                        Button {
                            if controller.setHabitatItem(item, placed: false) { dismiss() }
                            else { showSaveError() }
                        } label: {
                            Text("Remove from enclosure")
                                .font(.subheadline.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(12).petSurface(radius: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(controller.isBusy)
                        .accessibilityIdentifier("furniture.remove")
                    }
                    Text("Replaced items return to your collection. You never need to buy them again.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                }.padding(20)
            }
            .petPage().navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .alert("Replace placed items?", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), presenting: replacement) { slot in
            Button("Replace") { place(in: slot, replacing: true) }
            Button("Cancel", role: .cancel) { replacement = nil }
        } message: { slot in
            Text(replacementSummary(for: slot))
        }
        .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(error ?? "") }
    }

    private func place(in slot: HabitatFurnitureSlot, replacing: Bool) {
        if controller.placeHabitatItem(item, in: slot, replacing: replacing) { dismiss() }
        else { showSaveError() }
    }

    private func showSaveError() {
        error = controller.alertMessage ?? String(localized: "The enclosure could not be saved.")
        controller.alertMessage = nil
    }
}

#if DEBUG && targetEnvironment(simulator)
/// UI tests use a disposable simulator and in-memory wallets, never device saves.
struct HabitatFurnitureDebugHostView: View {
    @StateObject private var controller: PetSessionController
    @State private var showsFurniture = false

    init() {
        var state = PersistedAppState()
        state.completedOnboarding = true
        state.pets = [
            PetProfile(id: UUID(uuidString: "CF000000-0000-0000-0000-000000000001")!, name: "Pixel",
                       species: .dog, coat: .sunrise, createdAt: .distantPast, breed: .corgi),
            PetProfile(id: UUID(uuidString: "CF000000-0000-0000-0000-000000000002")!, name: "Luna",
                       species: .cat, coat: .cloud, createdAt: .distantPast, breed: .britishShorthair)
        ]
        state.activePetIDs = [state.pets[0].id]
        _controller = StateObject(wrappedValue: PetSessionController(
            store: InMemoryPetStore(state),
            arcadeStore: InMemoryArcadeStore(ArcadeState(progress: ArcadeProgress(
                coins: 120, ownedHabitatItems: [.cozyBox, .softBed, .leafNest, .birdPerch]
            )))
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            Button("Furniture") { showsFurniture = true }.accessibilityIdentifier("furniture.fixture.open")
            Text("\(controller.arcadeProgress.coins)").accessibilityIdentifier("furniture.fixture.coins")
            Text(controller.pets.map(\.name).joined(separator: ",")).accessibilityIdentifier("furniture.fixture.pets")
            Text("\(controller.habitat.configuration.revision)").accessibilityIdentifier("furniture.fixture.revision")
            Text(controller.habitat.configuration.furniture.map { "\($0.item.rawValue):\($0.slot.rawValue)" }.sorted().joined(separator: ","))
                .accessibilityIdentifier("furniture.fixture.layout")
        }
        .sheet(isPresented: $showsFurniture) { HabitatFurnitureView(controller: controller) }
        .task {
            guard controller.operation == .loading else { return }
            try? PetHabitatStore.save(SharedPetHabitat(configuration: PetHabitatState(furniture: [
                .init(item: .cozyBox, slot: .left), .init(item: .softBed, slot: .right), .init(item: .birdPerch, slot: .perch)
            ]), residents: []))
            await controller.bootstrap()
            showsFurniture = true
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-furniture-light") ? .light : .dark)
    }
}
#endif
