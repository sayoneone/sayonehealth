import Foundation
import SwiftUI
import SayoneCore

/// One of today's drinks: symbol, name, time, device glyph, ⏳ while not yet in Health, volume.
struct WatchTodayRow: View {
    let row: TodayRow

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: row.symbol ?? "drop.fill")
                .foregroundStyle(.blue)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.drinkName)
                    .font(.footnote)
                    .lineLimit(1)
                detailLine
            }
            Spacer(minLength: 4)
            Text(verbatim: VolumeText.short(row.volumeML))
                .font(.footnote)
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailLine: some View {
        HStack(spacing: 3) {
            Text(verbatim: row.date.formatted(date: .omitted, time: .shortened))
            if let origin = row.origin {
                Image(systemName: origin == .watch ? "applewatch" : "iphone")
            }
            if row.isPendingHealth {
                Image(systemName: "hourglass")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
