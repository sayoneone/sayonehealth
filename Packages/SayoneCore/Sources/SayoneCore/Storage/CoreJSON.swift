import Foundation

/// The one JSON configuration every store and the WatchConnectivity payload use.
public enum CoreJSON {
    /// outputFormatting [.sortedKeys], dateEncodingStrategy .millisecondsSince1970
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    /// dateDecodingStrategy .millisecondsSince1970
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
