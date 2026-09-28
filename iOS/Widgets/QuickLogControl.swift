import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct SelectPresetControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink") var preset: PresetEntity?
    init() {}
}

struct QuickLogControl: ControlWidget {
    static let kind: String = WidgetKinds.quickLogControl
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: SelectPresetControlIntent.self) { configuration in
            let p = configuration.preset.flatMap { PresetDisplays.find(id: $0.id) ?? $0.display } ?? PresetDisplays.builtInFallback
            let title = p.title
            ControlWidgetButton(action: QuickLogIntent(p)) {
                Label(title, systemImage: p.symbol)
            }
        }
        .displayName("Log Drink")
        .description("Logs the chosen drink to Health with one tap.")
        .promptsForUserConfiguration()
    }
}
