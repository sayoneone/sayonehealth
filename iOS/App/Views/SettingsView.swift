import Foundation
import SwiftUI
import AppIntents
import SayoneCore

/// Goal, nutrients, drinks, buttons, Health, Apple Watch, Siri, diagnostics, about.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var sentToWatch: Bool = false

    var body: some View {
        Form {
            goalSection
            nutrientsSection
            catalogSection
            healthSection
            watchSection
            siriSection
            diagnosticsSection
            aboutSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - Goal and nutrients

    private var goalBinding: Binding<Int> {
        Binding(
            get: { model.catalog.settings.dailyGoalML },
            set: { newValue in
                model.edit { CatalogEditor.setDailyGoal(in: &$0, ml: newValue) }
            }
        )
    }

    private var nutrientsBinding: Binding<Bool> {
        Binding(
            get: { model.catalog.settings.writeNutrients },
            set: { newValue in
                model.edit { CatalogEditor.setWriteNutrients(in: &$0, newValue) }
            }
        )
    }

    private var goalSection: some View {
        Section {
            Stepper(value: goalBinding, in: UserSettings.goalRange, step: 100) {
                Text(verbatim: VolumeText.short(model.catalog.settings.dailyGoalML))
                    .font(.headline)
                    .monospacedDigit()
            }
        } header: {
            Text("Daily goal")
        }
    }

    private var nutrientsSection: some View {
        Section {
            Toggle("Write caffeine, calories and sugar", isOn: nutrientsBinding)
        } footer: {
            Text("Caffeine, calories and sugar are saved to Health along with water.")
        }
    }

    // MARK: - Catalog

    private var catalogSection: some View {
        Section {
            NavigationLink {
                DrinksListView()
            } label: {
                Label("Drinks", systemImage: "cup.and.saucer.fill")
            }
            NavigationLink {
                PresetsListView()
            } label: {
                Label("Drink buttons", systemImage: "square.grid.2x2.fill")
            }
        }
    }

    // MARK: - Health

    private var canRequestHealth: Bool {
        model.healthAuth == .notDetermined
    }

    private var healthSection: some View {
        Section {
            LabeledContent {
                Text(SettingsText.healthStatus(model.healthAuth))
            } label: {
                Text("Writing water")
            }
            if canRequestHealth {
                Button("Allow Access to Health") {
                    Task { await model.requestHealthAccess() }
                }
            }
            Button("Open the Health app") {
                openHealthApp()
            }
        } header: {
            Text("Health")
        } footer: {
            healthFooter
        }
    }

    private var healthFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Allow both writing and reading Water. Reading lets the total include drinks logged on your other device.")
            if model.healthAuth == .denied {
                Text("If access is denied, allow it in Settings → Privacy & Security → Health → SayoneHealth.")
            }
        }
    }

    private func openHealthApp() {
        if let url = URL(string: "x-apple-health://") {
            openURL(url)
        }
    }

    // MARK: - Apple Watch

    private var watchSection: some View {
        Section {
            LabeledContent {
                Text(SettingsText.installed(CatalogSync.shared.watchAppInstalled))
            } label: {
                Text("Watch app")
            }
            Button {
                sendToWatch()
            } label: {
                HStack {
                    Text("Send to watch")
                    Spacer()
                    if sentToWatch {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
            }
        } header: {
            Text(verbatim: "Apple Watch")
        } footer: {
            Text("Open the watch app once after editing buttons on iPhone.")
        }
    }

    private func sendToWatch() {
        CatalogSync.shared.push(model.catalog)
        sentToWatch = CatalogSync.shared.watchAppInstalled
    }

    // MARK: - Siri

    private var siriSection: some View {
        Section {
            SiriTipView(intent: LogWaterIntent())
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            SiriTipView(intent: LogDrinkIntent())
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            SiriTipView(intent: TodayTotalIntent())
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            SiriTipView(intent: UndoLastIntent())
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
            ShortcutsLink()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } header: {
            Text(verbatim: "Siri")
        } footer: {
            Text("Siri understands Russian and English. All actions are also in the Shortcuts app.")
        }
    }

    // MARK: - Diagnostics and about

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                DiagnosticsView()
            } label: {
                Label("Diagnostics", systemImage: "stethoscope")
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return version + " (" + build + ")"
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(verbatim: versionText)
                    .monospacedDigit()
            } label: {
                Text("Version")
            }
        } header: {
            Text("About")
        }
    }
}

/// Localized labels for status values shared by Settings and Diagnostics.
enum SettingsText {
    static func healthStatus(_ auth: HealthWriteAuth) -> LocalizedStringKey {
        switch auth {
        case .authorized: return "Access allowed"
        case .denied: return "Access denied"
        case .notDetermined: return "Not requested yet"
        case .unavailable: return "Unavailable on this device"
        }
    }

    static func installed(_ isInstalled: Bool) -> LocalizedStringKey {
        isInstalled ? "Installed" : "Not installed"
    }

    static func shared(_ isShared: Bool) -> LocalizedStringKey {
        isShared ? "shared" : "not shared"
    }
}
