import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

// The ONLY place for watchOS 11 widget APIs (decision D23). Compiled into the watch widget
// extension only; shared widget code calls these helpers only in its watch-guarded branches.

extension View {
    /// Double tap (watchOS 11) activates this button in the Smart Stack.
    func sayonePrimaryAction() -> some View {
        self.handGestureShortcut(.primaryAction)
    }
}

/// Watch Favorites: one rectangular group with the first 3 drink buttons as circular slots.
struct WatchFavoritesGroup: View {
    let entry: FavoritesEntry

    var body: some View {
        AccessoryWidgetGroup(label: {
            Text(VolumeText.progressCompact(entry.summary))
                .sayoneOneLine()
                .invalidatableContent()
        }) {
            slot(0)
            slot(1)
            slot(2)
        }
        .accessoryWidgetGroupStyle(.circular)
    }

    @ViewBuilder func slot(_ i: Int) -> some View {
        if i < entry.presets.count {
            let p = entry.presets[i]
            Button(intent: QuickLogIntent(p)) {
                VStack(spacing: 0) {
                    Image(systemName: p.symbol)
                        .widgetAccentable()
                    Text(VolumeText.compact(p.volumeML))
                        .font(.system(size: 9))
                        .sayoneOneLine()
                        .invalidatableContent()
                }
            }
        } else {
            Image(systemName: "plus")
                .widgetAccentable()
        }
    }
}
