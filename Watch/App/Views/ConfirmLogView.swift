import SwiftUI
import SayoneCore

/// Deep-link confirm (complication tap that opened the app). It NEVER logs by itself:
/// only «Записать» logs, and ConfirmRequest.id is the entry id, so a second tap stays one entry.
struct ConfirmLogView: View {
    let request: ConfirmRequest
    @EnvironmentObject private var model: AppModel
    @State private var isLogging = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Log this drink?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                drinkSummary
                Button("Log") { confirm() }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(isLogging)
                    .watchPrimaryAction()
                Button("Cancel", role: .cancel) { model.confirmRequest = nil }
            }
        }
    }

    private var drinkSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: request.symbol)
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: request.drinkName)
                    .font(.footnote)
                    .lineLimit(2)
                Text(verbatim: VolumeText.short(request.volumeML))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private func confirm() {
        guard !isLogging else { return }
        isLogging = true
        let appModel = model
        let r = request
        Task { await appModel.confirm(r) }   // AppModel clears confirmRequest → the sheet closes
    }
}
