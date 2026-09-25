import Foundation
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let preset: PresetDisplay
    let summary: TodaySummary
    let needsHealthAccess: Bool          // HealthGateway.shared.writeAuth(.water) != .authorized (false in previews)
}

extension QuickLogEntry {
    /// The undo button is shown only while the newest local entry is still inside the widget undo window.
    var showsUndo: Bool {
        guard let until = summary.undoAvailableUntil else { return false }
        return until > date
    }
}

struct QuickLogProvider: AppIntentTimelineProvider {
    typealias Entry = QuickLogEntry
    typealias Intent = SelectPresetIntent

    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: Date(), preset: PresetDisplays.builtInFallback, summary: .placeholder, needsHealthAccess: false)
    }

    func snapshot(for configuration: SelectPresetIntent, in context: Context) async -> QuickLogEntry {
        let preset = Self.resolve(configuration)
        if context.isPreview {
            return QuickLogEntry(date: Date(), preset: preset, summary: .placeholder, needsHealthAccess: false)
        }
        let now = Date()
        let summary = TodayService.cachedSummary(now: now)
        let needs = HealthGateway.shared.writeAuth(.water) != .authorized
        return QuickLogEntry(date: now, preset: preset, summary: summary, needsHealthAccess: needs)
    }

    func timeline(for configuration: SelectPresetIntent, in context: Context) async -> Timeline<QuickLogEntry> {
        let now = Date()
        let preset = Self.resolve(configuration)
        let summary = await TodayService.summary(readHealth: true, now: now)
        let needs = HealthGateway.shared.writeAuth(.water) != .authorized
        let entry = QuickLogEntry(date: now, preset: preset, summary: summary, needsHealthAccess: needs)
        let next = WidgetTimeline.nextRefresh(after: now, undoUntil: summary.undoAvailableUntil)
        return Timeline(entries: [entry], policy: .after(next))
    }

    #if os(watchOS)
    func recommendations() -> [AppIntentRecommendation<SelectPresetIntent>] {       // verbatim
        if #available(watchOS 26.0, *) { return [] }
        return PresetDisplays.all().prefix(Catalog.maxPresets).map { p in
            let text: String = p.title
            return AppIntentRecommendation(intent: SelectPresetIntent(preset: PresetEntity(p)), description: text)
        }
    }
    #endif

    /// The configured preset, refreshed from the catalog when it still exists; otherwise the entity's own
    /// copy; with no configuration, the first catalog preset; finally the built-in Water 250 ml.
    static func resolve(_ configuration: SelectPresetIntent) -> PresetDisplay {
        if let chosen = configuration.preset {
            return PresetDisplays.find(id: chosen.id) ?? chosen.display
        }
        return PresetDisplays.all().first ?? PresetDisplays.builtInFallback
    }
}
