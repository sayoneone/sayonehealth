import Foundation
import os
import SayoneCore

/// The shared container and the three stores that live in it. Never crashes: when the App Group
/// container is unavailable (unsigned build, signing mistake) it falls back to Application Support and
/// logs an error. Data is then private to this process's container, but taps are still journaled.
enum AppGroup {
    static let fallbackIdentifier: String = "group.com.sayoneone.sayonehealth"
    static let infoPlistKey: String = "SayoneAppGroupID"

    /// Info.plist `SayoneAppGroupID` if it is non-empty and was expanded by the build, else the fallback.
    static let identifier: String = AppGroup.resolveIdentifier()

    /// True when the system returned a container for `identifier`, i.e. the data is really shared.
    static let isShared: Bool = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) != nil

    /// `<container>/SayoneHealth`, else `<Application Support>/SayoneHealth`. The directory is created.
    static let rootURL: URL = AppGroup.makeRootURL()

    static let journal: JournalStore = JournalStore(
        directory: AppGroup.rootURL.appendingPathComponent("Journal", isDirectory: true))

    static let catalog: CatalogStore = CatalogStore(
        fileURL: AppGroup.rootURL.appendingPathComponent("catalog.json", isDirectory: false),
        role: ThisDevice.kind == .phone ? .author : .replica)

    static let snapshot: SnapshotStore = SnapshotStore(
        fileURL: AppGroup.rootURL.appendingPathComponent("health-snapshot.json", isDirectory: false))

    // MARK: - Private

    private static func resolveIdentifier() -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: AppGroup.infoPlistKey) as? String else {
            return AppGroup.fallbackIdentifier
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty || value.contains("$(") {
            return AppGroup.fallbackIdentifier
        }
        return value
    }

    private static func makeRootURL() -> URL {
        let fileManager = FileManager.default
        let groupID = AppGroup.identifier
        let base: URL
        if let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            base = container
        } else {
            AppLog.store.error("App Group container unavailable for \(groupID, privacy: .public); falling back to Application Support")
            base = AppGroup.applicationSupportURL(fileManager)
        }
        let root = base.appendingPathComponent("SayoneHealth", isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)
        } catch {
            let reason = String(describing: error)
            AppLog.store.error("Cannot create store root: \(reason, privacy: .public)")
        }
        return root
    }

    private static func applicationSupportURL(_ fileManager: FileManager) -> URL {
        if let url = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                          appropriateFor: nil, create: true) {
            return url
        }
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url
        }
        return fileManager.temporaryDirectory
    }
}
