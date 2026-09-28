import Foundation
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct FavoritesEntry: TimelineEntry {
    let date: Date
    let presets: [PresetDisplay]          // PresetDisplays.favorites(count: 4 on iOS / 3 on watchOS)
    let summary: TodaySummary
}

extension FavoritesEntry {
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

struct FavoritesProvider: TimelineProvider {
    typealias Entry = FavoritesEntry

    func placeholder(in context: Context) -> FavoritesEntry {
        FavoritesEntry(date: Date(), presets: Self.favorites(), summary: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void) {
        completion(FavoritesEntry(date: Date(), presets: Self.favorites(), summary: .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void) {
        let presets = Self.favorites()
        Task {
            let now = Date()
            let s = await TodayService.summary(readHealth: true, now: now)
            let entries = WidgetFuture.states(now: now, summary: s).map { state in
                FavoritesEntry(date: state.date, presets: presets, summary: state.summary)
            }
            let nextRefresh = WidgetTimeline.nextRefresh(after: now, undoUntil: nil)
            completion(Timeline(entries: entries, policy: .after(nextRefresh)))
        }
    }

    /// First 4 presets on iPhone (2 x 2 grid), first 3 on the watch (one group of 3 slots).
    static var favoriteCount: Int {
        #if os(watchOS)
        return 3
        #else
        return 4
        #endif
    }

    static func favorites() -> [PresetDisplay] {
        PresetDisplays.favorites(count: favoriteCount)
    }
}

struct FavoritesWidget: Widget {
    let kind: String = WidgetKinds.favorites
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FavoritesProvider()) { entry in
            FavoritesView(entry: entry)
        }
        .configurationDisplayName("Favorites")
        .description("Your first drink buttons, one tap each.")
        .supportedFamilies(Self.families)
    }
    static var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryRectangular]
        #else
        return [.systemMedium]
        #endif
    }
}
