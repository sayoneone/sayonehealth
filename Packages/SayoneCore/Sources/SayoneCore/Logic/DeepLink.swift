import Foundation

/// `sayonehealth://` URLs: today, log confirmation (never auto-logs) and the Health access screen.
public enum DeepLink: Hashable, Sendable {
    case today
    case confirmLog(drinkID: String, volumeML: Int)
    case healthAccess

    public static let scheme: String = "sayonehealth"

    static let todayHost = "today"
    static let logHost = "log"
    static let healthHost = "health"
    static let drinkQueryName = "drink"
    static let volumeQueryName = "ml"
    static let todayURL: URL = URL(string: "sayonehealth://today")!

    /// Host "today" | "log" (needs a non-empty `drink` and an integer `ml`) | "health"; anything else is nil.
    /// Scheme and host are compared case-insensitively.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme, scheme.lowercased() == DeepLink.scheme,
              let host = components.host?.lowercased() else { return nil }
        switch host {
        case DeepLink.todayHost:
            self = .today
        case DeepLink.healthHost:
            self = .healthAccess
        case DeepLink.logHost:
            let items = components.queryItems ?? []
            guard let drink = items.first(where: { $0.name == DeepLink.drinkQueryName })?.value, !drink.isEmpty,
                  let mlText = items.first(where: { $0.name == DeepLink.volumeQueryName })?.value,
                  let ml = Int(mlText.trimmingCharacters(in: .whitespaces)) else { return nil }
            self = .confirmLog(drinkID: drink, volumeML: ml)
        default:
            return nil
        }
    }

    /// sayonehealth://today | sayonehealth://log?drink=<id>&ml=<n> | sayonehealth://health
    public var url: URL {
        let text: String
        switch self {
        case .today:
            text = "\(DeepLink.scheme)://\(DeepLink.todayHost)"
        case .healthAccess:
            text = "\(DeepLink.scheme)://\(DeepLink.healthHost)"
        case let .confirmLog(drinkID, volumeML):
            text = "\(DeepLink.scheme)://\(DeepLink.logHost)?\(DeepLink.drinkQueryName)=\(DeepLink.encodeQueryValue(drinkID))"
                + "&\(DeepLink.volumeQueryName)=\(volumeML)"
        }
        // Every component above is ASCII and percent-encoded, so URL(string:) cannot fail.
        return URL(string: text) ?? DeepLink.todayURL
    }

    /// Percent-encodes everything except RFC 3986 unreserved characters, so '&', '=', '+' and spaces survive.
    static func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
