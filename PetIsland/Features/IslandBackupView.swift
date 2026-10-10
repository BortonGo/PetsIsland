import SwiftUI
import UniformTypeIdentifiers

struct IslandBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw IslandBackupError.invalid }
        _ = try IslandBackupCodec.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct IslandBackupView: View {
    @ObservedObject var controller: PetSessionController
    @Environment(\.dismiss) private var dismiss
    @State private var document: IslandBackupDocument?
    @State private var exportsFile = false
    @State private var importsFile = false
    @State private var isWorking = false
    @State private var preview: Preview?
    @State private var recovery: Data?
    @State private var message: String?
    @State private var errorMessage: String?

    private struct Preview: Identifiable {
        let id = UUID()
        let data: Data
        let backup: IslandBackup
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .font(.largeTitle).foregroundStyle(PetDesign.secondary)
                        Text("Keep your island safe").font(PetDesign.title(.title2))
                        Text("Save your pets, outfits, coins, supplies, furniture, finds and games in one file. Keep it in Files or on another device.")
                            .font(.subheadline).foregroundStyle(PetDesign.secondary)
                    }
                    .padding(20).petSurface()

                    Button { exportBackup() } label: {
                        Label("Save a backup", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PetPrimaryButtonStyle())
                    .disabled(isWorking || controller.isBusy)
                    .accessibilityIdentifier("backup.export")

                    VStack(alignment: .leading, spacing: 12) {
                        Button { importsFile = true } label: {
                            Label("Open a backup", systemImage: "folder")
                        }
                        .buttonStyle(PetQuietButtonStyle())
                        .disabled(isWorking || !controller.canRestoreIsland)
                        .accessibilityIdentifier("backup.import")
                        Text(controller.canRestoreIsland
                             ? "You can review the file before replacing anything. A copy of your current island is kept automatically before restoring."
                             : "Bring your Dynamic Island pet home before restoring a backup." as LocalizedStringKey)
                            .font(.footnote).foregroundStyle(PetDesign.secondary)
                    }

                    if let recovery {
                        Button {
                            do { preview = Preview(data: recovery, backup: try IslandBackupCodec.decode(recovery)) }
                            catch { errorMessage = error.localizedDescription }
                        } label: {
                            Label("Island before last restore", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(PetQuietButtonStyle())
                        .disabled(isWorking || !controller.canRestoreIsland)
                        .accessibilityIdentifier("backup.recovery")
                    }
                    if isWorking { ProgressView().frame(maxWidth: .infinity) }
                    if let message {
                        Label(message, systemImage: "checkmark.circle")
                            .font(.subheadline).accessibilityIdentifier("backup.feedback")
                    }
                    Text("Backups stay where you save them. Pet Island does not upload them to a server. Live Activities and the app icon stay on this device.")
                        .font(.footnote).foregroundStyle(PetDesign.secondary)
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .petPage()
            .navigationTitle("Island backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(isWorking) } }
        }
        .interactiveDismissDisabled(isWorking)
        .fileExporter(isPresented: $exportsFile, document: document, contentType: .json,
                      defaultFilename: "Pet-Island-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            switch result {
            case .success: message = String(localized: "Backup saved.")
            case .failure(let error): errorMessage = error.localizedDescription
            }
            document = nil
        }
        .fileImporter(isPresented: $importsFile, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): openBackup(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $preview) { selection in
            IslandBackupPreview(backup: selection.backup) {
                try await controller.restoreIslandBackup(selection.data)
                preview = nil
                message = String(localized: "Your island has been restored.")
                recovery = try? await controller.islandRecoveryBackup()
            }
        }
        .alert("Island backup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task { recovery = try? await controller.islandRecoveryBackup() }
    }

    private func exportBackup() {
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do {
                document = IslandBackupDocument(data: try await controller.exportIslandBackup())
                exportsFile = true
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func openBackup(_ url: URL) {
        isWorking = true
        message = nil
        Task {
            defer { isWorking = false }
            do {
                let selection = try await Task.detached(priority: .userInitiated) {
                    let data = try IslandBackupCodec.read(from: url)
                    return Preview(data: data, backup: try IslandBackupCodec.decode(data))
                }.value
                preview = selection
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

struct IslandBackupPreview: View {
    let backup: IslandBackup
    let restore: () async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsRestore = false
    @State private var isRestoring = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline).foregroundStyle(PetDesign.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(backup.app.pets) { pet in
                            HStack(spacing: 14) {
                                PetArtwork(species: pet.species, coat: pet.coat, customColor: pet.customColor,
                                           breed: pet.resolvedBreed, pose: .idle, animatesMotion: false,
                                           accessory: pet.outfit?.headwear)
                                    .frame(width: 60, height: 48).accessibilityHidden(true)
                                Text(pet.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16).petSurface()
                    VStack(spacing: 12) {
                        LabeledContent("Coins", value: "\(backup.arcade.progress.coins)")
                        LabeledContent("Finds", value: "\(backup.app.discoveries.memories.count)")
                        LabeledContent("Accessories", value: "\(backup.arcade.progress.ownedAccessories.count)")
                        LabeledContent("Enclosure items", value: "\(backup.arcade.progress.ownedHabitatItems.count)")
                        ForEach(ArcadeItemKind.allCases) { item in
                            LabeledContent(item.title, value: "\(backup.arcade.progress.inventory[item])")
                        }
                        LabeledContent("Saved games", value: "\(backup.arcade.bubblePawsRuns.count)")
                    }.font(.subheadline).padding(18).petSurface()
                    Text("This replaces your current island, including pets and coins. The two islands are not combined. You can return to the automatic copy afterwards.")
                        .font(.footnote).foregroundStyle(PetDesign.secondary)
                    if backup.app.discoveries.activeWalk != nil {
                        Label("The saved walk keeps its original return time.", systemImage: "pawprint")
                            .font(.footnote).foregroundStyle(PetDesign.secondary)
                    }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button { confirmsRestore = true } label: {
                    if isRestoring { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Restore this island").frame(maxWidth: .infinity) }
                }
                .buttonStyle(PetPrimaryButtonStyle()).disabled(isRestoring)
                .accessibilityIdentifier("backup.restore")
                .padding(20).background(PetDesign.background)
            }
            .petPage()
            .navigationTitle("Backup contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isRestoring) } }
        }
        .interactiveDismissDisabled(isRestoring)
        .confirmationDialog("Replace your current island?", isPresented: $confirmsRestore, titleVisibility: .visible) {
            Button("Restore this island", role: .destructive) {
                isRestoring = true
                Task {
                    defer { isRestoring = false }
                    do { try await restore() }
                    catch { errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("An automatic copy of your current island will be kept before anything is replaced.")
        }
        .alert("Island backup", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}
