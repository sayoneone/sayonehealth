import AppIntents
import SayoneCore

/// Undo of the newest local entry. Used by the widget undo button (10-minute window) and, being
/// discoverable, by the "Undo Last Drink" App Shortcut in the apps (3-hour voice window).
struct UndoLastIntent: AppIntent {                      // discoverable: also an App Shortcut
    static let title: LocalizedStringResource = "Undo Last Drink"
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let window = ThisDevice.process == .widgetExtension ? UndoPolicy.widgetWindow : UndoPolicy.voiceWindow
        let r = await DrinkLogger.undoLast(window: window)
        let text = SiriText.undone(r)
        return .result(dialog: "\(text)")
    }
}
