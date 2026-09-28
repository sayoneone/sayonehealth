import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct QuickLogWidget: Widget {
    let kind: String = WidgetKinds.quickLog
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectPresetIntent.self, provider: QuickLogProvider()) { entry in
            QuickLogView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("One tap logs the chosen drink to Health.")
        .supportedFamilies(Self.families)
        #if os(iOS)
        .promptsForUserConfiguration()
        #endif
    }
    static var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}
