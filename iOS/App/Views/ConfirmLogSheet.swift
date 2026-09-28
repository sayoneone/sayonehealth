import Foundation
import SwiftUI
import SayoneCore

/// Deep-link confirmation ("sayonehealth://log?..."). Never logs by itself.
struct ConfirmLogSheet: View {
    @EnvironmentObject private var model: AppModel
    let request: ConfirmRequest
    @State private var isLogging: Bool = false

    init(request: ConfirmRequest) {
        self.request = request
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: request.symbol)
                .font(.system(size: 48))
                .foregroundStyle(tintColor)
                .frame(width: 96, height: 96)
                .background(tintColor.opacity(0.15), in: Circle())
            Text("Log: \(drinkName), \(volumeText)?")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var drinkName: String {
        request.drinkName
    }

    private var volumeText: String {
        VolumeText.short(request.volumeML)
    }

    private var tintColor: Color {
        model.catalog.drink(id: request.drinkID)?.tint.color ?? Color.blue
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                confirm()
            } label: {
                Text("Log")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isLogging)
            Button(role: .cancel) {
                model.confirmRequest = nil
            } label: {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func confirm() {
        isLogging = true
        let r = request
        Task {
            await model.confirm(r)
            isLogging = false
        }
    }
}
