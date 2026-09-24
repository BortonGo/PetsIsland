import Foundation

protocol PetStore: Sendable {
    func load() async throws -> PersistedAppState
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

    func load() async throws -> PersistedAppState {
        try DurableJSON.load(PersistedAppState.self, from: fileURL, decoder: decoder) ?? PersistedAppState()
    }

    func save(_ state: PersistedAppState) async throws {
        try DurableJSON.save(state, to: fileURL, encoder: encoder, decoder: decoder)
    }
}

/// Keeps the last decodable snapshot when a damaged primary file is replaced.
/// Both collection and arcade use the same atomic persistence rules.
enum DurableJSON {
    static func load<Value: Decodable>(_ type: Value.Type, from url: URL, decoder: JSONDecoder) throws -> Value? {
        for candidate in [url, url.appendingPathExtension("backup")] {
            if let data = try? Data(contentsOf: candidate),
               let value = try? decoder.decode(type, from: data) { return value }
        }
        let candidates = [url, url.appendingPathExtension("backup")]
        if candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            throw CocoaError(.fileReadCorruptFile)
        }
        return nil
    }

    static func save<Value: Codable>(
        _ value: Value, to url: URL, encoder: JSONEncoder, decoder: JSONDecoder
    ) throws {
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = try? Data(contentsOf: url),
           (try? decoder.decode(Value.self, from: previous)) != nil {
            try previous.write(to: url.appendingPathExtension("backup"), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}

actor InMemoryPetStore: PetStore {
    private var value: PersistedAppState
    init(_ value: PersistedAppState = PersistedAppState()) { self.value = value }
    func load() async -> PersistedAppState { value }
    func save(_ state: PersistedAppState) async throws { value = state }
}
