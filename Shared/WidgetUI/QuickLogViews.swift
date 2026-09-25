import Foundation
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

// Layouts of the Quick Log widget, one small view per family (§5.4). Every log button is a
// Button(intent: QuickLogIntent(...)); the undo button is always a sibling layer, never inside it.

struct QuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { entry.preset.tint.background }
            .widgetURL(url)
    }

    /// Fallback when a tap misses the buttons (or a watch face opens the app): Health onboarding,
    /// the Today screen for the inline family, otherwise the confirm-and-log screen (never auto-logs).
    private var url: URL {
        if entry.needsHealthAccess {
            return DeepLink.healthAccess.url
        }
        if family == .accessoryInline {
            return DeepLink.today.url
        }
        return DeepLink.confirmLog(drinkID: entry.preset.drinkID, volumeML: entry.preset.volumeML).url
    }

    @ViewBuilder private var content: some View {
        switch family {
        #if os(iOS)
        case .systemSmall: SmallQuickLogView(entry: entry)
        #endif
        #if os(watchOS)
        case .accessoryCorner: CornerQuickLogView(entry: entry)
        #endif
        case .accessoryRectangular: RectangularQuickLogView(entry: entry)
        case .accessoryInline: InlineQuickLogView(entry: entry)
        default: CircularQuickLogView(entry: entry)
        }
    }
}

// MARK: - Shared helpers

extension View {
    /// Widget text rule: one line, shrinking down to 60 % before truncating.
    func sayoneOneLine() -> some View {
        lineLimit(1).minimumScaleFactor(0.6)
    }
}

/// Undo of the entry the widget shows (10-minute widget window). Placed as a sibling of the log button.
struct WidgetUndoButton: View {
    let entryID: UUID

    var body: some View {
        Button(intent: UndoEntryIntent(entryID: entryID)) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title3)
                .widgetAccentable()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Circular (iOS Lock Screen, watch face, Smart Stack)

struct CircularQuickLogView: View {
    let entry: QuickLogEntry

    var body: some View {
        Button(intent: QuickLogIntent(entry.preset)) {
            Gauge(value: entry.summary.progress) {
                EmptyView()
            } currentValueLabel: {
                CircularQuickLogLabel(preset: entry.preset)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        }
        .buttonStyle(.plain)
    }
}

struct CircularQuickLogLabel: View {
    let preset: PresetDisplay

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: preset.symbol)
                .widgetAccentable()
            Text(VolumeText.compact(preset.volumeML))
                .font(.caption2)
                .sayoneOneLine()
                .invalidatableContent()
        }
    }
}

#if os(watchOS)
// MARK: - Corner complication (watch face only)

struct CornerQuickLogView: View {
    let entry: QuickLogEntry

    private var cornerLabel: String {
        VolumeText.plus(entry.preset.volumeML)
    }

    var body: some View {
        Button(intent: QuickLogIntent(entry.preset)) {
            Image(systemName: entry.preset.symbol)
                .font(.title2)
                .widgetAccentable()
        }
        .buttonStyle(.plain)
        .widgetLabel(cornerLabel)
    }
}
#endif

// MARK: - Rectangular (iOS Lock Screen, watch face, Smart Stack)

struct RectangularQuickLogView: View {
    let entry: QuickLogEntry

    var body: some View {
        Button(intent: QuickLogIntent(entry.preset)) {
            RectangularQuickLogLabel(entry: entry)
        }
        .buttonStyle(.plain)
        #if os(watchOS)
        .sayonePrimaryAction()
        #endif
    }
}

struct RectangularQuickLogLabel: View {
    let entry: QuickLogEntry

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Label(entry.preset.drinkName, systemImage: entry.preset.symbol)
                    .sayoneOneLine()
                    .widgetAccentable()
                Text(VolumeText.progress(entry.summary))
                    .font(.caption)
                    .sayoneOneLine()
                    .invalidatableContent()
                ProgressView(value: entry.summary.progress)
                    .widgetAccentable()
            }
            Spacer(minLength: 0)
            Text(VolumeText.plus(entry.preset.volumeML))
                .font(.headline)
                .sayoneOneLine()
                .invalidatableContent()
        }
    }
}

// MARK: - Inline (not interactive)

struct InlineQuickLogView: View {
    let entry: QuickLogEntry

    var body: some View {
        Label(VolumeText.progressCompact(entry.summary), systemImage: "drop.fill")
            .widgetAccentable()
            .invalidatableContent()
    }
}

#if os(iOS)
// MARK: - Small Home Screen widget (iOS)

struct SmallQuickLogView: View {
    let entry: QuickLogEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SmallQuickLogContent(entry: entry, leavesRoomForUndo: entry.showsUndo)
            if let undoID = entry.undoEntryID {
                WidgetUndoButton(entryID: undoID)
            }
        }
    }
}

struct SmallQuickLogContent: View {
    let entry: QuickLogEntry
    let leavesRoomForUndo: Bool

    private var headerTrailingInset: CGFloat {
        leavesRoomForUndo ? 26 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SmallQuickLogHeader(entry: entry)
                .padding(.trailing, headerTrailingInset)
            Button(intent: QuickLogIntent(entry.preset)) {
                Text(VolumeText.plus(entry.preset.volumeML))
                    .font(.title2.bold())
                    .sayoneOneLine()
                    .invalidatableContent()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(entry.preset.tint.color)
            Spacer(minLength: 0)
            Text(VolumeText.progress(entry.summary))
                .font(.caption)
                .sayoneOneLine()
                .invalidatableContent()
            ProgressView(value: entry.summary.progress)
                .tint(entry.preset.tint.color)
                .widgetAccentable()
        }
    }
}

struct SmallQuickLogHeader: View {
    let entry: QuickLogEntry

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: entry.preset.symbol)
                .widgetAccentable()
            Text(entry.preset.drinkName)
                .font(.caption)
                .sayoneOneLine()
            if entry.needsHealthAccess {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                    .widgetAccentable()
            }
        }
    }
}
#endif
