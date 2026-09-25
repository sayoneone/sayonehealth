import Foundation

/// `health-snapshot.json`: the last HealthKit water read, shared by the app, widgets and Siri.
public struct SnapshotStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> HealthSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? CoreJSON.decoder().decode(HealthSnapshot.self, from: data)
    }

    /// Under the lock "<dir>/.snapshot.lock": skipped when the stored snapshot's readAt is later than this one's,
    /// so a slow reader never overwrites a fresher result.
    public func saveIfNewer(_ snapshot: HealthSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileLock.bestEffort(at: lockURL) {
            if let stored = load(), stored.readAt > snapshot.readAt { return }
            let data = try CoreJSON.encoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        }
    }

    var lockURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent(".snapshot.lock")
    }
}
