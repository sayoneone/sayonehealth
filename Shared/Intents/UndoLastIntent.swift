import AppIntents
import SayoneCore

/// Undo of the newest local entry, for Siri, the "Undo Last Drink" App Shortcut and the Shortcuts app
/// (3-hour voice window, whichever process runs it). Widget buttons use UndoEntryIntent instead.
struct UndoLastIntent: AppIntent {                      // discoverable: also an App Shortcut
    static let title: LocalizedStringResource = "Undo Last Drink"
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let window = UndoPolicy.voiceWindow
        let r = await DrinkLogger.undoLast(window: window)
        let text = SiriText.undone(r)
        return .result(dialog: "\(text)")
    }
}
