import Foundation
import SwiftUI
import SayoneCore

/// "Записано · Вода, 250 мл · Отменить" at the bottom of the Today screen.
struct ToastView: View {
    @EnvironmentObject private var model: AppModel
    let toast: LogToast

    init(toast: LogToast) {
        self.toast = toast
    }

    private var iconName: String {
        toast.savedToHealth ? "checkmark.circle.fill" : "hourglass.circle.fill"
    }

    private var iconColor: Color {
        toast.savedToHealth ? Color.green : Color.orange
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
            Text(verbatim: toast.text)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                undo()
            } label: {
                Text("Undo")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func undo() {
        let id = toast.entryID
        model.toast = nil
        Task { await model.undo(entryID: id) }
    }
}
