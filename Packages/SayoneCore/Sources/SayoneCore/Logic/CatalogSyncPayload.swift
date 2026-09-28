import Foundation

/// WCSession application-context codec for the catalog (phone → watch), and the newest-revision-wins rule.
public enum CatalogSyncPayload {
    public static let catalogKey: String = "catalog"
    public static let revisionKey: String = "revision"

    /// [catalogKey: Data (CoreJSON), revisionKey: NSNumber(value: catalog.revision)]
    public static func encode(_ catalog: Catalog) throws -> [String: Any] {
        let data = try CoreJSON.encoder().encode(catalog)
        return [catalogKey: data, revisionKey: NSNumber(value: catalog.revision)]
    }

    /// nil if the catalog is missing or corrupt; the result is sanitized(). `revisionKey` is ignored (logging only).
    public static func decode(_ payload: [String: Any]) -> Catalog? {
        guard let data = payload[catalogKey] as? Data,
              let catalog = try? CoreJSON.decoder().decode(Catalog.self, from: data) else { return nil }
        return catalog.sanitized()
    }

    /// received.revision > current.revision
    public static func shouldApply(received: Catalog, current: Catalog) -> Bool {
        received.revision > current.revision
    }
}
