import AppIntents
import SayoneCore

struct TodayTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Water"
    init() {}
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let s = await TodayService.summary(readHealth: true)
        let text = SiriText.today(s)
        return .result(value: s.waterML, dialog: "\(text)")
    }
}
