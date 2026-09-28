import Foundation

public enum JournalError: Error, Equatable { case io(String) }

public enum CreateResult: Equatable, Sendable {
    case created(IntakeEntry)
    /// A file with the same id already exists (idempotent re-log, e.g. confirm sheet).
    case existing(IntakeEntry)
    /// LogDedupe hit; returns the earlier entry.
    case duplicate(IntakeEntry)
}

public enum MarkSavedResult: Equatable, Sendable { case marked, alreadySaved, deletedMeanwhile, missing }

public enum BeginDeleteResult: Equatable, Sendable {
    /// `previous` is .pending or .saved; `entry` is the updated (.pendingDelete) entry.
    case began(previous: HealthSyncStatus, entry: IntakeEntry)
    case alreadyDeleting(IntakeEntry)
    case alreadyDeleted
    case notFound
}

/// One JSON file per entry (`<directory>/<UUID>.json`). Every status change is a read-modify-write under an
/// exclusive `flock` on `<directory>/.lock`, so the app, widget and Siri processes can write concurrently.
///
/// State machine (§5.1): nothing leaves `.pendingDelete` except to `.deleted`, and nothing leaves `.deleted`.
public struct JournalStore: Sendable {
    public static let retentionDays: Int = 8

    public let directory: URL

    /// No I/O here: the directory is created lazily on the first write.
    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: - Writes (under the lock)

    public func create(_ entry: IntakeEntry) throws -> CreateResult {
        try locked {
            if let existing = read(fileURL(for: entry.id)) {
                return .existing(existing)
            }
            if entry.source == .widget {
                let nearby = all().filter { abs($0.date.timeIntervalSince(entry.date)) <= LogDedupe.window }
                if let duplicate = LogDedupe.duplicate(of: entry, in: nearby) {
                    return .duplicate(duplicate)
                }
            }
            try write(entry)
            return .created(entry)
        }
    }

    public func markSaved(id: UUID, at date: Date) throws -> MarkSavedResult {
        try locked {
            guard var entry = read(fileURL(for: id)) else { return .missing }
            switch entry.health {
            case .pending:
                entry.health = .saved
                entry.healthSavedAt = date
                try write(entry)
                return .marked
            case .saved:
                return .alreadySaved
            case .pendingDelete, .deleted:
                return .deletedMeanwhile
            }
        }
    }

    public func beginDelete(id: UUID, at date: Date) throws -> BeginDeleteResult {
        try locked {
            guard var entry = read(fileURL(for: id)) else { return .notFound }
            switch entry.health {
            case .pending, .saved:
                let previous = entry.health
                entry.health = .pendingDelete
                entry.deletedAt = date
                try write(entry)
                return .began(previous: previous, entry: entry)
            case .pendingDelete:
                return .alreadyDeleting(entry)
            case .deleted:
                return .alreadyDeleted
            }
        }
    }

    /// Any live status → `.deleted` with `deletedAt = date`. No-op when the file is missing or already deleted.
    public func finishDelete(id: UUID, at date: Date) throws {
        try locked {
            guard var entry = read(fileURL(for: id)), entry.health != .deleted else { return }
            entry.health = .deleted
            entry.deletedAt = date
            try write(entry)
        }
    }

    /// Removes `.saved` and `.deleted` files whose `date` is older than `now − retentionDays` days.
    /// Never removes `.pending` or `.pendingDelete`. Returns the number of files removed.
    @discardableResult
    public func prune(now: Date, calendar: Calendar = .current) throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        let cutoff = calendar.date(byAdding: .day, value: -JournalStore.retentionDays, to: now)
            ?? now.addingTimeInterval(-Double(JournalStore.retentionDays) * 86_400)
        return try locked {
            var removed = 0
            for (url, entry) in allFiles() where (entry.health == .saved || entry.health == .deleted) && entry.date < cutoff {
                if (try? FileManager.default.removeItem(at: url)) != nil {
                    removed += 1
                }
            }
            return removed
        }
    }

    // MARK: - Reads (lock-free; files are replaced atomically)

    public func entry(id: UUID) -> IntakeEntry? {
        read(fileURL(for: id))
    }

    /// Skips dotfiles, non-.json names and unreadable files; sorted by date, oldest first.
    public func all() -> [IntakeEntry] {
        allFiles().map { $0.1 }
    }

    /// Entries with `interval.start <= date < interval.end`.
    public func entries(in interval: DateInterval) -> [IntakeEntry] {
        all().filter { interval.sayoneContains($0.date) }
    }

    /// `.pending` and `.pendingDelete` entries, oldest first.
    public func needingFlush() -> [IntakeEntry] {
        all().filter { $0.health == .pending || $0.health == .pendingDelete }
    }

    // MARK: - Helpers

    var lockURL: URL {
        directory.appendingPathComponent(".lock")
    }

    func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    func allFiles() -> [(URL, IntakeEntry)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        var result: [(URL, IntakeEntry)] = []
        for name in names where !name.hasPrefix(".") && name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            if let entry = read(url) {
                result.append((url, entry))
            }
        }
        result.sort { lhs, rhs in
            if lhs.1.date != rhs.1.date { return lhs.1.date < rhs.1.date }
            return lhs.1.id.uuidString < rhs.1.id.uuidString
        }
        return result
    }

    func read(_ url: URL) -> IntakeEntry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? CoreJSON.decoder().decode(IntakeEntry.self, from: data)
    }

    func write(_ entry: IntakeEntry) throws {
        do {
            let data = try CoreJSON.encoder().encode(entry)
            try data.write(to: fileURL(for: entry.id), options: .atomic)
        } catch {
            throw JournalError.io(String(describing: error))
        }
    }

    func ensureDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw JournalError.io(String(describing: error))
        }
    }

    func locked<T>(_ body: () throws -> T) throws -> T {
        try ensureDirectory()
        return try FileLock.bestEffort(at: lockURL, body)
    }
}

extension FileLock {
    /// R7: when the lock itself cannot be taken, run `body` without it rather than failing the tap.
    /// Errors thrown by `body` always propagate unchanged, and `body` never runs twice.
    static func bestEffort<T>(at url: URL, _ body: () throws -> T) throws -> T {
        var bodyStarted = false
        do {
            return try withExclusiveLock(at: url) { () throws -> T in
                bodyStarted = true
                return try body()
            }
        } catch is FileLockError where !bodyStarted {
            return try body()
        }
    }
}
