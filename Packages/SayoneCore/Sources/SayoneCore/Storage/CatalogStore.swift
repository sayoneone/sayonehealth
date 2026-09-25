import Foundation

/// `catalog.json` with role-dependent fallbacks (§5.1). A corrupt file is kept as `catalog.json.bak`.
public struct CatalogStore: Sendable {
    public let fileURL: URL
    public let role: CatalogRole

    public init(fileURL: URL, role: CatalogRole) {
        self.fileURL = fileURL
        self.role = role
    }

    /// Never throws; always sanitized(); never writes the catalog file.
    /// - missing (or present but unreadable, e.g. before first unlock) → `makeDefault(revision: 0)`, file untouched
    /// - present but undecodable → renamed to `.bak`; author → revision = epoch ms of `now`, replica → revision 0
    public func load(now: Date = Date()) -> Catalog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Catalog.makeDefault(revision: 0, now: now).sanitized()
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return Catalog.makeDefault(revision: 0, now: now).sanitized()
        }
        if let catalog = try? CoreJSON.decoder().decode(Catalog.self, from: data) {
            return catalog.sanitized()
        }
        moveCorruptFileAside()
        let revision: Int64
        switch role {
        case .author: revision = Catalog.epochMilliseconds(now)
        case .replica: revision = 0
        }
        return Catalog.makeDefault(revision: revision, now: now).sanitized()
    }

    /// Atomic write of the sanitized catalog; creates the parent directory if needed.
    public func save(_ catalog: Catalog) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try CoreJSON.encoder().encode(catalog.sanitized())
        try data.write(to: fileURL, options: .atomic)
    }

    var backupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(fileURL.lastPathComponent + ".bak")
    }

    func moveCorruptFileAside() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        try? fileManager.moveItem(at: fileURL, to: backupURL)
    }
}
