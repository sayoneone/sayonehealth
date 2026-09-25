import SwiftUI
import SayoneCore

/// «✓ Записано · Вода, 250 мл» + «Отменить». The whole row is the undo button (one big target).
/// AppModel clears the toast after UndoPolicy.toastDuration.
struct LoggedBanner: View {
    let toast: LogToast
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(verbatim: toast.text)
                        .font(.footnote)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if !toast.savedToHealth {
                        Image(systemName: "hourglass")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.vertical, 2)
        }
    }
}
