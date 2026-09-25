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
    /// The entry the undo button deletes; nil once the widget undo window has passed at this entry's date.
    var undoEntryID: UUID? {
        guard let until = summary.undoAvailableUntil, until > date, let last = summary.lastLocal else { return nil }
        return last.id
    }

    /// The undo button is shown only while the newest local entry is still inside the widget undo window.
    var showsUndo: Bool {
        undoEntryID != nil
    }
}

/// Budget-free future states. The undo button disappearing and the midnight reset are pre-computed as extra
/// timeline entries, so they happen even when WidgetKit defers the next reload (daily reload budget).
enum WidgetFuture {
    static func states(now: Date, summary: TodaySummary) -> [(date: Date, summary: TodaySummary)] {
        var states: [(date: Date, summary: TodaySummary)] = [(date: now, summary: summary)]
        let midnight = TodayMath.nextDayStart(after: now)
        if let until = summary.undoAvailableUntil, until > now, until < midnight {
            states.append((date: until, summary: summary))
        }
        let reset = TodayMath.summary(snapshot: AppGroup.snapshot.load(),
                                      local: AppGroup.journal.all(),
                                      goalML: summary.goalML,
                                      now: midnight)
        states.append((date: midnight, summary: reset))
        return states
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
        let entries = WidgetFuture.states(now: now, summary: summary).map { state in
            QuickLogEntry(date: state.date, preset: preset, summary: state.summary, needsHealthAccess: needs)
        }
        let next = WidgetTimeline.nextRefresh(after: now, undoUntil: nil)
        return Timeline(entries: entries, policy: .after(next))
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
