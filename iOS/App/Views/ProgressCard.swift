import Foundation
import SwiftUI
import SayoneCore

/// Ring + "1,2 из 2 л" + remaining / goal reached + pending badge.
struct ProgressCard: View {
    let summary: TodaySummary

    init(summary: TodaySummary) {
        self.summary = summary
    }

    var body: some View {
        HStack(spacing: 18) {
            ProgressCardRing(progress: summary.progress, label: percentText, reached: goalReached)
                .frame(width: 92, height: 92)
            details
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var goalReached: Bool {
        summary.waterML >= summary.goalML
    }

    private var percentText: String {
        let ratio: Double = Double(summary.waterML) / Double(max(summary.goalML, 1))
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }

    private var leftText: String {
        VolumeText.short(max(summary.goalML - summary.waterML, 0))
    }

    private var pendingText: String {
        String(summary.pendingCount)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: VolumeText.progress(summary))
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            remainingLine
            if summary.pendingCount > 0 {
                pendingBadge
            }
        }
    }

    @ViewBuilder
    private var remainingLine: some View {
        if goalReached {
            Label("Goal reached", systemImage: "checkmark.seal.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        } else {
            Text("Left: \(leftText)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var pendingBadge: some View {
        Label {
            Text("Waiting for Health: \(pendingText)")
        } icon: {
            Image(systemName: "hourglass")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.orange.opacity(0.15), in: Capsule())
    }
}

private struct ProgressCardRing: View {
    let progress: Double
    let label: String
    let reached: Bool

    private var ringColor: Color {
        reached ? Color.green : Color.blue
    }

    private var clamped: CGFloat {
        CGFloat(min(max(progress, 0), 1))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.18), lineWidth: 12)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(verbatim: label)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 14)
        }
        .animation(.easeOut(duration: 0.4), value: progress)
    }
}
