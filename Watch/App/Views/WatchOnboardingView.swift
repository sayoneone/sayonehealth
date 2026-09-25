import SwiftUI
import SayoneCore

/// Health permission on the watch (separate from the iPhone's).
struct WatchOnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                Text("Health access on the watch is separate from the iPhone.")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Allow both writing and reading Water. Reading lets the total include drinks logged on your other device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Access to Health") { request() }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(isRequesting)
                Button("Later") { dismiss() }
            }
        }
        .navigationTitle("Health")
    }

    private func request() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            await model.requestHealthAccess()
            isRequesting = false
            dismiss()
        }
    }
}
