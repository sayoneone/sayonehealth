import SwiftUI
import SayoneCore

/// «✓ Записано · Вода, 250 мл» with a small «Отменить» button. Only the button undoes, so a tap on the
/// banner text never deletes the drink by accident. AppModel clears the toast after UndoPolicy.toastDuration.
struct LoggedBanner: View {
    let toast: LogToast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(verbatim: toast.text)
                .font(.footnote)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if !toast.savedToHealth {
                Image(systemName: "hourglass")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .frame(width: 44)
            .accessibilityLabel(Text("Undo"))
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
