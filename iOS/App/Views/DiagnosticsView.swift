import Foundation
import SwiftUI
import SayoneCore

/// Every DiagnosticsInfo field plus "Retry writing to Health".
struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var info: DiagnosticsInfo? = nil
    @State private var isRetrying: Bool = false

    var body: some View {
        List {
            if let info = info {
                storageSection(info)
                healthSection(info)
                catalogSection(info)
            }
            Section {
                Button {
                    retry()
                } label: {
                    HStack {
                        Text("Retry writing to Health")
                        Spacer()
                        if isRetrying {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRetrying)
            }
        }
        .navigationTitle("Diagnostics")
        .onAppear { info = model.diagnostics() }
    }

    private func storageSection(_ info: DiagnosticsInfo) -> some View {
        Section {
            keyRow("App Group", SettingsText.shared(info.appGroupShared))
            valueRow("App Group ID", info.appGroupID)
            valueRow("Device", info.device == .watch ? "Apple Watch" : "iPhone")
            valueRow("Journal entries", String(info.journalCount))
        } header: {
            Text("Storage")
        }
    }

    private func healthSection(_ info: DiagnosticsInfo) -> some View {
        Section {
            keyRow("Writing water", SettingsText.healthStatus(info.waterWriteAuth))
            valueRow("Waiting for Health", String(info.pendingCount))
            valueRow("Waiting for deletion", String(info.pendingDeleteCount))
            readAtRow(info.healthReadAt)
        } header: {
            Text("Health")
        }
    }

    private func catalogSection(_ info: DiagnosticsInfo) -> some View {
        Section {
            valueRow("Catalog revision", String(info.catalogRevision))
        } header: {
            Text("Catalog")
        }
    }

    private func valueRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        LabeledContent {
            Text(verbatim: value)
                .monospacedDigit()
                .textSelection(.enabled)
        } label: {
            Text(title)
        }
    }

    private func keyRow(_ title: LocalizedStringKey, _ value: LocalizedStringKey) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Text(title)
        }
    }

    @ViewBuilder
    private func readAtRow(_ date: Date?) -> some View {
        if let date = date {
            valueRow("Last read from Health", date.formatted(date: .abbreviated, time: .standard))
        } else {
            keyRow("Last read from Health", "never")
        }
    }

    private func retry() {
        isRetrying = true
        Task {
            await model.refresh()
            info = model.diagnostics()
            isRetrying = false
        }
    }
}
