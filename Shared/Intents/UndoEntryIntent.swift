import Foundation
import AppIntents
import SayoneCore

/// The widget undo button. It targets the entry the widget was showing, so a double tap (or a tap after
/// the timeline went stale) never deletes a second, older drink. Not discoverable: Siri and Shortcuts use
/// UndoLastIntent instead.
struct UndoEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Drink"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Entry ID", default: "") var entryID: String
    init() {}
    init(entryID: UUID) {
        self.entryID = entryID.uuidString
    }
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: entryID),
              let entry = AppGroup.journal.entry(id: id),
              entry.isVisible,
              Date().timeIntervalSince(entry.date) <= UndoPolicy.widgetWindow else {
            WidgetRefresher.reloadAll()
            return .result()
        }
        _ = await DrinkLogger.delete(entryID: id, isLocal: true)
        return .result()
    }
}
