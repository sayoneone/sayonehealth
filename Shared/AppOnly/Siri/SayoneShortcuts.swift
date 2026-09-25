import AppIntents
import SayoneCore

/// The 4 App Shortcuts. The Swift phrases are the `en` stringSet of AppShortcuts.xcstrings; the first
/// phrase of each shortcut is its catalog key. Keep both files in sync (lint rule 8).
struct SayoneShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)",
            "Add water in \(.applicationName)",
            "Log \(\.$amount) of water in \(.applicationName)",
            "I drank \(\.$amount) of water in \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: LogDrinkIntent(), phrases: [
            "Log \(\.$drink) in \(.applicationName)",
            "I drank \(\.$drink) in \(.applicationName)",
            "\(.applicationName) \(\.$drink)",
            "Log a drink in \(.applicationName)"
        ], shortTitle: "Log Drink", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: TodayTotalIntent(), phrases: [
            "How much did I drink in \(.applicationName)",
            "Today's water in \(.applicationName)"
        ], shortTitle: "Today's Water", systemImageName: "chart.bar.fill")
        AppShortcut(intent: UndoLastIntent(), phrases: [
            "Undo last drink in \(.applicationName)",
            "Delete last drink in \(.applicationName)"
        ], shortTitle: "Undo Last Drink", systemImageName: "arrow.uturn.backward")
    }
}
