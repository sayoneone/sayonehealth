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
    /// - missing after such a recovery (author) → revision = epoch ms of the `.bak` file's modification date, so
    ///   every later load returns the same, newer-than-before revision and the watch accepts the pushed default.
    public func load(now: Date = Date()) -> Catalog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Catalog.makeDefault(revision: recoveredRevision() ?? 0, now: now).sanitized()
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return Catalog.makeDefault(revision: 0, now: now).sanitized()
        }
        if let catalog = try? CoreJSON.decoder().decode(Catalog.self, from: data) {
            return catalog.sanitized()
        }
        moveCorruptFileAside(now: now)
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

    /// Author only: the stable revision of a catalog recovered from a corrupt file (see `load`).
    func recoveredRevision() -> Int64? {
        guard role == .author,
              let attributes = try? FileManager.default.attributesOfItem(atPath: backupURL.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Catalog.epochMilliseconds(modified)
    }

    var backupURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(fileURL.lastPathComponent + ".bak")
    }

    /// The `.bak` gets `now` as its modification date: it is the stable "recovered at" revision source.
    func moveCorruptFileAside(now: Date) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }
        try? fileManager.moveItem(at: fileURL, to: backupURL)
        try? fileManager.setAttributes([.modificationDate: now], ofItemAtPath: backupURL.path)
    }
}
