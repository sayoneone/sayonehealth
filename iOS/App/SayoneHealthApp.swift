import SwiftUI
import AppIntents
import SayoneCore

@main
struct SayoneHealthApp: App {
    @StateObject private var model = AppModel.shared

    init() {
        CatalogSync.shared.activate()
        SayoneShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            TodayView()
                .environmentObject(model)
        }
    }
}
