import Foundation
import SwiftUI
import SayoneCore

/// "Today" section: local + other-device rows, swipe to delete, footnote for other apps' water.
struct TodayListSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            if model.rows.isEmpty {
                Text("No drinks yet today")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.rows) { row in
                    TodayEntryRow(row: row)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(row)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        } header: {
            Text("Today")
        } footer: {
            footer
        }
    }

    private var otherAppsML: Int {
        model.summary.externalWaterML - model.summary.otherDeviceWaterML
    }

    private var otherAppsText: String {
        VolumeText.short(otherAppsML)
    }

    @ViewBuilder
    private var footer: some View {
        if otherAppsML > 0 {
            Text("Other apps in Health: \(otherAppsText)")
        }
    }

    private func delete(_ row: TodayRow) {
        Task { await model.delete(row) }
    }
}

private struct TodayEntryRow: View {
    let row: TodayRow

    private var timeText: String {
        row.date.formatted(date: .omitted, time: .shortened)
    }

    private var originGlyph: String? {
        guard let origin = row.origin else { return nil }
        return origin == .watch ? "applewatch" : "iphone"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol ?? "cup.and.saucer.fill")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.drinkName)
                    .lineLimit(1)
                Text(verbatim: timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            statusGlyphs
            Text(verbatim: VolumeText.short(row.volumeML))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusGlyphs: some View {
        if row.isPendingHealth {
            Image(systemName: "hourglass")
                .foregroundStyle(.orange)
                .accessibilityLabel(Text("Waiting for Health"))
        }
        if let glyph = originGlyph {
            Image(systemName: glyph)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
