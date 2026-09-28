import WidgetKit

enum WidgetKinds {
    static let quickLog = "QuickLogWidget"
    static let favorites = "FavoritesWidget"
    static let quickLogControl = "QuickLogControl"
}

enum WidgetRefresher {
    /// After any intake change. Free while the app is in the foreground; also fine from an intent.
    static func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After the drinks, presets or goal change: timelines, watch recommendations and iOS controls.
    static func catalogDidChange() {
        reloadAll()
        #if os(watchOS)
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        #endif
        #if os(iOS)
        ControlCenter.shared.reloadAllControls()
        #endif
    }
}
