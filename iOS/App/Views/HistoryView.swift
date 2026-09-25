import Foundation
import SwiftUI
import SayoneCore

/// Last 7 days as capsule bars against the daily goal (no Swift Charts).
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var days: [DayTotal] = []
    @State private var isLoading: Bool = true

    var body: some View {
        List {
            chartSection
            if !days.isEmpty {
                daysSection
            }
        }
        .navigationTitle("History")
        .task { await load() }
        .refreshable { await load() }
    }

    private var goalML: Int {
        model.catalog.settings.dailyGoalML
    }

    private var goalText: String {
        VolumeText.short(goalML)
    }

    /// `AppModel.history` has no fallback flag. `TodayService.history` falls back to local journal
    /// totals when the Health query fails, which happens when Health is unavailable or access was
    /// never requested; mirror that here to show the label.
    private var isFallback: Bool {
        model.healthAuth == .unavailable || model.healthAuth == .notDetermined
    }

    private var chartSection: some View {
        Section {
            if isLoading && days.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                HistoryBarsChart(days: days, goalML: goalML)
            }
        } header: {
            Text("Last 7 days")
        } footer: {
            chartFooter
        }
    }

    private var chartFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Goal: \(goalText)")
            if isFallback {
                Text("Only entries from this device")
            }
        }
    }

    private var daysSection: some View {
        Section {
            ForEach(Array(days.reversed())) { day in
                HistoryDayRow(day: day, goalML: goalML)
            }
        }
    }

    private func load() async {
        let result = await model.history(days: 7)
        days = result
        isLoading = false
    }
}

private struct HistoryDayRow: View {
    let day: DayTotal
    let goalML: Int

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.dayStart)
    }

    private var dayText: String {
        day.dayStart.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        HStack {
            if isToday {
                Text("Today")
            } else {
                Text(verbatim: dayText)
            }
            Spacer()
            Text(verbatim: VolumeText.short(day.waterML))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if day.waterML >= goalML {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryBarsChart: View {
    let days: [DayTotal]
    let goalML: Int

    private let barAreaHeight: CGFloat = 150

    private var scaleML: Int {
        max(goalML, days.map { $0.waterML }.max() ?? 0, 1)
    }

    private func height(for ml: Int) -> CGFloat {
        let ratio: CGFloat = CGFloat(ml) / CGFloat(scaleML)
        return max(6, barAreaHeight * ratio)
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                goalLine
                bars
            }
            .frame(height: barAreaHeight, alignment: .bottom)
            labels
        }
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    private var goalLine: some View {
        HistoryGoalLine()
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(height: 1)
            .offset(y: -height(for: goalML))
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(days) { day in
                Capsule()
                    .fill(barColor(day))
                    .frame(maxWidth: .infinity)
                    .frame(height: height(for: day.waterML))
            }
        }
    }

    private var labels: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(days) { day in
                HistoryBarLabel(day: day)
            }
        }
    }

    private func barColor(_ day: DayTotal) -> Color {
        day.waterML >= goalML ? Color.blue : Color.blue.opacity(0.45)
    }
}

private struct HistoryBarLabel: View {
    let day: DayTotal

    private var isToday: Bool {
        Calendar.current.isDateInToday(day.dayStart)
    }

    private var weekday: String {
        day.dayStart.formatted(.dateTime.weekday(.abbreviated))
    }

    private var litres: String {
        VolumeFormat.liters(day.waterML, AppLanguage.current)
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: weekday)
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.primary : Color.secondary)
            Text(verbatim: litres)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
    }
}

private struct HistoryGoalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
