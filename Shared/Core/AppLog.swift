import os

/// Unified-logging categories. Subsystem and category names are fixed by the constants registry.
/// Only interpolate `String` and `Int` values, with an explicit privacy where it matters.
enum AppLog {
    static let subsystem: String = "com.sayoneone.sayonehealth"

    static let intake: Logger = Logger(subsystem: "com.sayoneone.sayonehealth", category: "intake")
    static let health: Logger = Logger(subsystem: "com.sayoneone.sayonehealth", category: "health")
    static let widget: Logger = Logger(subsystem: "com.sayoneone.sayonehealth", category: "widget")
    static let sync: Logger = Logger(subsystem: "com.sayoneone.sayonehealth", category: "sync")
    static let store: Logger = Logger(subsystem: "com.sayoneone.sayonehealth", category: "store")
}
