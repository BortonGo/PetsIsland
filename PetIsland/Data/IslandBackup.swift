import CryptoKit
import Foundation

enum IslandBackupError: Error, LocalizedError, Equatable {
    case invalid, newerVersion, tooLarge, busy, travelling, saveFailed, recoveryRequired

    var errorDescription: String? {
        switch self {
        case .invalid: String(localized: "This is not a valid Pet Island backup. Your island has not been replaced.")
        case .newerVersion: String(localized: "This backup needs a newer version of Pet Island.")
        case .tooLarge: String(localized: "This backup is too large to open safely.")
        case .busy: String(localized: "Please wait for your island to finish saving, then try again.")
        case .travelling: String(localized: "Bring your Dynamic Island pet home before restoring a backup.")
        case .saveFailed: String(localized: "The backup could not be restored. Your previous island is still in place.")
        case .recoveryRequired: String(localized: "Restoring was interrupted. Your previous island is saved. Reopen the app to finish recovery.")
        }
    }
}

/// A portable save contains durable choices, not frame positions or a device's
/// ActivityKit session. The original movement engine recreates the shared views.
struct IslandBackup: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var createdAt = Date.now
    var app: PersistedAppState
    var arcade: ArcadeState
    var habitat: PetHabitatState

    func validate() throws {
        let ids = Set(app.pets.map(\.id))
        let limit = 1_000_000_000_000
        func amount(_ value: Int) -> Bool { (0...limit).contains(value) }
        func date(_ value: Date) -> Bool {
            value.timeIntervalSinceReferenceDate.isFinite && abs(value.timeIntervalSinceReferenceDate) < 100_000_000_000
        }
        func color(_ value: PetColorSelection?) -> Bool {
            guard let value else { return true }
            return [value.red, value.green, value.blue].allSatisfy { $0.isFinite && (0...1).contains($0) }
        }
        func pet(_ value: PetProfile) -> Bool {
            !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.name.count <= 64
                && date(value.createdAt)
                && (value.breed == nil || PetBreed.available(for: value.species).contains(value.breed!))
                && color(value.customColor)
        }
        guard date(createdAt), date(habitat.simulationEpoch), amount(habitat.revision),
              app.schemaVersion == PersistedAppState.schemaVersion,
              arcade.schemaVersion == ArcadeState.schemaVersion,
              habitat.schemaVersion == PetHabitatState.currentSchemaVersion,
              (1...12).contains(app.pets.count), ids.count == app.pets.count,
              app.pets.allSatisfy(pet), app.completedOnboarding,
              app.activeSession == nil, app.dismissedActivitySessionID == nil,
              !app.activePetIDs.isEmpty, app.activePetIDs.count <= PersistedAppState.maximumActivePets,
              Set(app.activePetIDs).count == app.activePetIDs.count,
              Set(app.activePetIDs).isSubset(of: ids),
              app.history.totalSeconds.isFinite, (0...Double(limit)).contains(app.history.totalSeconds),
              amount(app.history.completedSessions), color(app.settings.liveActivityBackgroundColor),
              amount(arcade.progress.coins), amount(arcade.progress.totalScore), amount(arcade.progress.gamesPlayed),
              arcade.progress.highScores.values.allSatisfy(amount),
              arcade.progress.inventory.quantities.values.allSatisfy(amount),
              arcade.vitalsUpdatedAtByPetID.values.allSatisfy(date),
              arcade.pendingCareEvents.isEmpty, arcade.completedRuns.count <= 128,
              Set(arcade.completedRuns.map(\.id)).count == arcade.completedRuns.count,
              arcade.completedRuns.allSatisfy({ amount($0.payout.score) && amount($0.payout.coinsEarned) }),
              arcade.bubblePawsRuns.count <= 12,
              Set(arcade.bubblePawsRuns.map(\.petID)).count == arcade.bubblePawsRuns.count
        else { throw IslandBackupError.invalid }
        for run in arcade.bubblePawsRuns {
            guard run.isValid, ids.contains(run.petID), !arcade.completedRuns.contains(where: { $0.id == run.runID }) else {
                throw IslandBackupError.invalid
            }
        }
        guard Set(arcade.vitalsByPetID.keys).isSubset(of: ids),
              Set(arcade.bondsByPetID.keys).isSubset(of: ids),
              arcade.bondsByPetID.values.allSatisfy(\.isValid),
              Set(arcade.vitalsUpdatedAtByPetID.keys).isSubset(of: ids),
              arcade.vitalsByPetID.values.allSatisfy({ [$0.fullness, $0.happiness, $0.energy].allSatisfy { $0.isFinite && (0...1).contains($0) } }),
              habitat.leadDynamicIslandPetID == nil,
              Set(habitat.residentPetIDs).isSubset(of: ids),
              habitat.furniture.allSatisfy({ arcade.progress.ownedHabitatItems.contains($0.item) }),
              app.pets.allSatisfy({ $0.outfit?.headwear.map { arcade.progress.ownedAccessories.contains($0) } ?? true }),
              app.discoveries.memories.allSatisfy({ pet($0.pet) && date($0.foundAt) }),
              app.discoveries.activeWalk.map({ ids.contains($0.pet.id) && pet($0.pet)
                  && date($0.startedAt) && date($0.endsAt) && $0.endsAt.timeIntervalSince($0.startedAt) <= 604_800 }) ?? true
        else { throw IslandBackupError.invalid }
    }

    var sharedHabitat: SharedPetHabitat {
        SharedPetHabitat(configuration: habitat, residents: habitat.residentPetIDs.compactMap { id in
            app.pets.first { $0.id == id }.map {
                SharedHabitatResident(profile: $0, vitals: arcade.vitalsByPetID[id] ?? PetVitals(),
                                      vitalsUpdatedAt: arcade.vitalsUpdatedAtByPetID[id] ?? .distantPast)
            }
        }, discoveryWalk: app.discoveries.activeWalk)
    }

    var sharedLife: PetLifeState {
        PetLifeState(profile: app.profile, placement: .enclosure,
                     vitals: arcade.vitalsByPetID[app.profile.id] ?? PetVitals(),
                     vitalsUpdatedAt: arcade.vitalsUpdatedAtByPetID[app.profile.id] ?? .distantPast)
    }
}

enum IslandBackupCodec {
    static let maximumBytes = 12 * 1_024 * 1_024
    private struct Envelope: Codable {
        var format = "org.bortongo.pet-island.backup"
        var version = 3
        let payload: Data
        let checksum: String
    }

    static func encode(_ backup: IslandBackup) throws -> Data {
        try backup.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(backup)
        let data = try encoder.encode(Envelope(payload: payload, checksum: digest(payload)))
        guard data.count <= maximumBytes else { throw IslandBackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> IslandBackup {
        guard data.count <= maximumBytes else { throw IslandBackupError.tooLarge }
        do {
            let decoder = JSONDecoder()
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.format == "org.bortongo.pet-island.backup" else { throw IslandBackupError.invalid }
            guard (1...3).contains(envelope.version) else { throw IslandBackupError.newerVersion }
            guard envelope.checksum == digest(envelope.payload) else { throw IslandBackupError.invalid }
            // App decoders deliberately repair old internal saves. An imported
            // file must instead be complete: never silently replace missing pets.
            guard let raw = try JSONSerialization.jsonObject(with: envelope.payload) as? [String: Any],
                  let app = raw["app"] as? [String: Any], let arcade = raw["arcade"] as? [String: Any],
                  let habitat = raw["habitat"] as? [String: Any],
                  let pets = app["pets"] as? [[String: Any]],
                  app["settings"] is [String: Any], app["history"] is [String: Any],
                  app["discoveries"] is [String: Any], let progress = arcade["progress"] as? [String: Any],
                  arcade["vitalsByPetID"] != nil, arcade["vitalsUpdatedAtByPetID"] != nil,
                  let runs = arcade["bubblePawsRuns"] as? [Any],
                  let activeIDs = app["activePetIDs"] as? [String],
                  let residents = habitat["residentPetIDs"] as? [String],
                  let furniture = habitat["furniture"] as? [String: String],
                  let accessories = progress["ownedAccessories"] as? [String],
                  let items = progress["ownedHabitatItems"] as? [String],
                  let theme = habitat["theme"] as? String, HabitatTheme(rawValue: theme) != nil
            else { throw IslandBackupError.invalid }
            guard ["coins", "totalScore", "gamesPlayed"].allSatisfy({ key in
                (progress[key] as? Int).map { (0...1_000_000_000_000).contains($0) } ?? false
            }), progress["inventory"] is [String: Any], progress["highScores"] != nil,
                  arcade["pendingCareEvents"] != nil, arcade["completedRuns"] != nil,
                  habitat["simulationEpoch"] != nil, habitat["behaviorSeed"] != nil, habitat["revision"] != nil,
                  accessories.allSatisfy({ PetAccessory(rawValue: $0) != nil }),
                  items.allSatisfy({ HabitatItemKind(rawValue: $0) != nil })
            else { throw IslandBackupError.invalid }
            guard app["schemaVersion"] as? Int == PersistedAppState.schemaVersion,
                  arcade["schemaVersion"] as? Int == ArcadeState.schemaVersion,
                  habitat["schemaVersion"] as? Int == PetHabitatState.currentSchemaVersion
            else { throw IslandBackupError.newerVersion }
            let result = try decoder.decode(IslandBackup.self, from: envelope.payload)
            if envelope.version >= 2, arcade["bondsByPetID"] == nil { throw IslandBackupError.invalid }
            guard result.app.pets.count == pets.count, result.app.activePetIDs.count == activeIDs.count,
                  result.arcade.bubblePawsRuns.count == runs.count,
                  result.habitat.residentPetIDs.count == residents.count,
                  result.habitat.furniture.count == furniture.count else { throw IslandBackupError.invalid }
            try result.validate()
            return result
        } catch let error as IslandBackupError { throw error }
        catch { throw IslandBackupError.invalid }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Bounded, coordinated reads also work for files downloaded by iCloud Drive.
    static func read(from url: URL) throws -> Data {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var coordinatorError: NSError?
        var result: Result<Data, Error> = .failure(IslandBackupError.invalid)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinated in
            result = Result {
                let handle = try FileHandle(forReadingFrom: coordinated)
                defer { try? handle.close() }
                var data = Data()
                while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                    guard data.count + chunk.count <= maximumBytes else { throw IslandBackupError.tooLarge }
                    data.append(chunk)
                }
                return data
            }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }
}

protocol IslandBackupStore: Sendable {
    func pendingRestore() async throws -> Data?
    func recoveryBackup() async throws -> Data?
    func beginRestore(previous: Data) async throws
    func finishRestore() async throws
}

/// The journal is written before touching any of the four save locations. Its
/// removal is the commit point. A process interrupted earlier rolls back on boot.
actor FileIslandBackupStore: IslandBackupStore {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "PetIsland/Backups")
    }
    private var journal: URL { directory.appending(path: "pending-restore.json") }
    private var recovery: URL { directory.appending(path: "before-restore.json") }
    private func read(_ url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try IslandBackupCodec.read(from: url)
    }
    func pendingRestore() throws -> Data? { try read(journal) }
    func recoveryBackup() throws -> Data? { try read(recovery) }
    func beginRestore(previous: Data) throws {
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw IslandBackupError.recoveryRequired }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try previous.write(to: recovery, options: .atomic)
        try previous.write(to: journal, options: .atomic)
    }
    func finishRestore() throws { try FileManager.default.removeItem(at: journal) }
}

actor InMemoryIslandBackupStore: IslandBackupStore {
    private var pending: Data?
    private var recovery: Data?
    init(recovery: Data? = nil) { self.recovery = recovery }
    func pendingRestore() -> Data? { pending }
    func recoveryBackup() -> Data? { recovery }
    func beginRestore(previous: Data) throws {
        guard pending == nil else { throw IslandBackupError.recoveryRequired }
        recovery = previous; pending = previous
    }
    func finishRestore() { pending = nil }
}
