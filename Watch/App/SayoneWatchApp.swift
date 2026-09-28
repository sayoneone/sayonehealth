import SwiftUI
import AppIntents
import SayoneCore

@main
struct SayoneWatchApp: App {
    @StateObject private var model = AppModel.shared
    init() {
        CatalogSync.shared.activate()
        SayoneShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
        }
    }
}
