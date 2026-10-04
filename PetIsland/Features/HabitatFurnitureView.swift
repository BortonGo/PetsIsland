import SwiftUI

struct HabitatFurnitureView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsShop = false
    @State private var placementError: String?
    @State private var placingItem: HabitatItemKind?
    @State private var sheetHeight: PresentationDetent = .large

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Two ground places and one upper perch. Keep the middle free for walking.")
                        .font(.subheadline)
                        .foregroundStyle(PetDesign.secondary)
                    HStack(spacing: 8) {
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
                                    .font(.caption2.weight(.medium)).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity).padding(8).petSurface(radius: 14)
                        }
                    }
                    Text("One bulky item at a time: a box or a leaf nest. Everything else stays in your collection.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
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
        .alert("Could not save", isPresented: Binding(
            get: { placementError != nil },
            set: { if !$0 { placementError = nil } }
        )) {
            Button("OK", role: .cancel) { placementError = nil }
        } message: {
            Text(placementError ?? "")
        }
    }

    private func itemTile(_ item: HabitatItemKind) -> some View {
        let owned = controller.arcadeProgress.ownedHabitatItems.contains(item)
        let placed = owned && controller.habitat.configuration.furniture.contains { $0.item == item }
        return Button {
            if owned {
                if !placed {
                    placingItem = item
                } else if !controller.setHabitatItem(item, placed: false) {
                    placementError = controller.alertMessage
                        ?? String(localized: "The enclosure could not be saved.")
                    controller.alertMessage = nil
                }
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
                    Text(placed ? "In enclosure" : "Place item")
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
        .contextMenu {
            if placed {
                Button("Move item", systemImage: "arrow.left.arrow.right") { placingItem = item }
            }
        }
        .disabled(controller.isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(placed ? .isSelected : [])
        .accessibilityValue(owned ? (placed ? Text("In enclosure") : Text("Purchased")) : Text("Locked"))
        .accessibilityHint(owned ? (placed ? Text("Remove item") : Text("Place item")) : Text("Open shop"))
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    HabitatFurnitureArtwork(item: item).frame(width: 120, height: 90)
                    Text(item.detail).font(.subheadline).foregroundStyle(PetDesign.secondary)
                    Text("Choose a place").font(.headline)
                    ForEach(item.slots) { slot in
                        let conflicts = controller.habitat.configuration.furnitureConflicts(for: item, in: slot)
                        Button {
                            if conflicts.isEmpty { place(in: slot, replacing: false) }
                            else { replacement = slot }
                        } label: {
                            HStack {
                                Image(systemName: slot == .perch ? "bird" : "square.dashed")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(slot.title).font(.headline)
                                    Text(conflicts.isEmpty ? String(localized: "Free place")
                                         : conflicts.map { $0.item.title }.joined(separator: ", "))
                                        .font(.caption).foregroundStyle(PetDesign.secondary)
                                }
                                Spacer()
                                Image(systemName: conflicts.isEmpty ? "plus.circle" : "arrow.triangle.2.circlepath")
                            }
                            .padding(16).petSurface(radius: 18)
                        }
                        .buttonStyle(.plain).disabled(controller.isBusy)
                        .accessibilityIdentifier("furniture.place.\(slot.rawValue)")
                    }
                    Text("Replaced items return to your collection. You never need to buy them again.")
                        .font(.caption).foregroundStyle(PetDesign.secondary)
                }.padding(20)
            }
            .petPage().navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        .confirmationDialog("Replace placed items?", isPresented: Binding(
            get: { replacement != nil }, set: { if !$0 { replacement = nil } }
        ), titleVisibility: .visible) {
            if let slot = replacement {
                Button("Replace") { place(in: slot, replacing: true) }
            }
        } message: {
            Text("Replaced items return to your collection. You never need to buy them again.")
        }
        .alert("Could not save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(error ?? "") }
    }

    private func place(in slot: HabitatFurnitureSlot, replacing: Bool) {
        if controller.placeHabitatItem(item, in: slot, replacing: replacing) { dismiss() }
        else {
            error = controller.alertMessage ?? String(localized: "The enclosure could not be saved.")
            controller.alertMessage = nil
        }
    }
}
