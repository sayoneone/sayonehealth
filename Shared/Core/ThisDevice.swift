import Foundation
import SayoneCore

/// Which kind of process is running this code: a full app or a widget extension (widgets, controls,
/// complications and the intents they run).
enum ProcessKind: Sendable {
    case app, widgetExtension
}

enum ThisDevice {
    #if os(watchOS)
    static let kind: DeviceKind = .watch
    #else
    static let kind: DeviceKind = .phone
    #endif

    static let process: ProcessKind = Bundle.main.bundleURL.pathExtension == "appex" ? .widgetExtension : .app
}

extension AppLanguage {
    /// The language this bundle resolved to (device language, limited to en/ru). Never cached, so a
    /// language change is picked up by the next call.
    static var current: AppLanguage {
        AppLanguage(preferredLocalizations: Bundle.main.preferredLocalizations)
    }
}
