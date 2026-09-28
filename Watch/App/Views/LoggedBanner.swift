import SwiftUI
import SayoneCore

/// «✓ Записано · Вода, 250 мл · Отменить», drawn over the ring row's slot (WatchRootView) so it never
/// changes any row height. The whole banner is the undo target: nobody taps the ring slot by accident.
/// AppModel clears the toast after UndoPolicy.toastDuration.
struct LoggedBanner: View {
    let toast: LogToast
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: toast.text)
                        .font(.footnote)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                if !toast.savedToHealth {
                    Image(systemName: "hourglass")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
