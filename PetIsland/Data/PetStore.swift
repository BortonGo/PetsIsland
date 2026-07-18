import Foundation

protocol PetStore: Sendable {
    func load() async -> PersistedAppState
    func save(_ state: PersistedAppState) async throws
}

actor FilePetStore: PetStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = fileURL ?? base.appending(path: "PetIsland/state.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() async -> PersistedAppState {
        do {
            let data = try Data(contentsOf: fileURL)
            let state = try decoder.decode(PersistedAppState.self, from: data)
            guard state.schemaVersion == PersistedAppState.schemaVersion else { return PersistedAppState() }
            return state
        } catch {
            return PersistedAppState()
        }
    }

    func save(_ state: PersistedAppState) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

actor InMemoryPetStore: PetStore {
    private var value: PersistedAppState
    init(_ value: PersistedAppState = PersistedAppState()) { self.value = value }
    func load() async -> PersistedAppState { value }
    func save(_ state: PersistedAppState) async throws { value = state }
}
