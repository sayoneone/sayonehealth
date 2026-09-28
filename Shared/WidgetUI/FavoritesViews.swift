import Foundation
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct FavoritesView: View {
    let entry: FavoritesEntry

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.blue.opacity(0.12) }
            .widgetURL(DeepLink.today.url)
    }

    @ViewBuilder private var content: some View {
        #if os(watchOS)
        WatchFavoritesGroup(entry: entry)
        #else
        MediumFavoritesView(entry: entry)
        #endif
    }
}

// MARK: - Medium Home Screen widget (iOS): progress on the left, up to 4 drink buttons on the right

struct MediumFavoritesView: View {
    let entry: FavoritesEntry

    var body: some View {
        HStack(spacing: 12) {
            FavoritesProgressColumn(entry: entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            FavoritesButtonGrid(presets: entry.presets)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FavoritesProgressColumn: View {
    let entry: FavoritesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "drop.fill")
                .font(.title3)
                .widgetAccentable()
            Text(VolumeText.progress(entry.summary))
                .font(.headline)
                .sayoneOneLine()
                .invalidatableContent()
            ProgressView(value: entry.summary.progress)
                .widgetAccentable()
            Spacer(minLength: 0)
            if let undoID = entry.undoEntryID {
                WidgetUndoButton(entryID: undoID)
            }
        }
    }
}

/// A VStack of two HStacks (no lazy grid in widgets). Missing presets leave an empty cell.
struct FavoritesButtonGrid: View {
    let presets: [PresetDisplay]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                FavoritesSlot(preset: preset(at: 0))
                FavoritesSlot(preset: preset(at: 1))
            }
            HStack(spacing: 6) {
                FavoritesSlot(preset: preset(at: 2))
                FavoritesSlot(preset: preset(at: 3))
            }
        }
    }

    private func preset(at index: Int) -> PresetDisplay? {
        if index < presets.count {
            return presets[index]
        }
        return nil
    }
}

struct FavoritesSlot: View {
    let preset: PresetDisplay?

    var body: some View {
        if let p = preset {
            FavoritesPresetButton(preset: p)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct FavoritesPresetButton: View {
    let preset: PresetDisplay

    var body: some View {
        Button(intent: QuickLogIntent(preset)) {
            VStack(spacing: 2) {
                Image(systemName: preset.symbol)
                    .widgetAccentable()
                Text(VolumeText.plus(preset.volumeML))
                    .font(.caption2)
                    .sayoneOneLine()
                    .invalidatableContent()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(preset.tint.color)
    }
}
