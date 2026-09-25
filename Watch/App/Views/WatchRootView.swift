import SwiftUI
import SayoneCore

/// Screens pushed on the watch's navigation stack.
enum WatchRoute: Hashable {
    case otherDrink
    case volume(Drink)
    case health
    case complicationHelp
}

struct WatchRootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [WatchRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WatchHomeList()
                .navigationTitle(Text(verbatim: "SayoneHealth"))
                .navigationDestination(for: WatchRoute.self) { route in
                    destination(for: route)
                }
        }
        .onOpenURL { url in
            path.removeAll()
            model.handle(url: url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .onChange(of: model.showHealthOnboarding, initial: true) { _, show in
            if show {
                path = [.health]
                model.showHealthOnboarding = false
            }
        }
        .task { await model.refresh() }
        .sheet(item: $model.confirmRequest) { request in
            ConfirmLogView(request: request)
                .environmentObject(model)
        }
        .alert(Text(verbatim: model.alertMessage ?? ""), isPresented: $model.alertMessage.watchIsPresent) {}
        .sensoryFeedback(.success, trigger: model.logCounter)
    }

    @ViewBuilder
    private func destination(for route: WatchRoute) -> some View {
        switch route {
        case .otherDrink:
            DrinkPickerView()
        case .volume(let drink):
            VolumePickerView(drink: drink, onLogged: { path.removeAll() })
        case .health:
            WatchOnboardingView()
        case .complicationHelp:
            ComplicationHelpView()
        }
    }
}

/// The root list: ring, banner, Health row, presets, other drink, today, help.
private struct WatchHomeList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            // The "logged" banner replaces the ring inside the ring row's own slot, so no row above the
            // presets changes height: a quick second tap on a preset logs again instead of hitting Undo.
            TodayRingRow(summary: model.summary)
                .opacity(model.toast == nil ? 1 : 0)
                .overlay {
                    if let toast = model.toast {
                        LoggedBanner(toast: toast) { undo(toast) }
                    }
                }
            presetRows
            // Below the presets: it appears only after the first refresh and must not move them.
            if model.needsHealthOnboarding {
                NavigationLink(value: WatchRoute.health) {
                    WatchHealthRow()
                }
            }
            NavigationLink(value: WatchRoute.otherDrink) {
                Label("Other drink…", systemImage: "ellipsis.circle")
            }
            todaySection
            NavigationLink(value: WatchRoute.complicationHelp) {
                Label("How to add to the watch face", systemImage: "applewatch.watchface")
            }
        }
        .animation(.default, value: model.toast)
    }

    @ViewBuilder
    private var presetRows: some View {
        let presets = model.presets
        let primaryID = presets.first?.id
        ForEach(presets) { preset in
            PresetRow(preset: preset, isPrimary: preset.id == primaryID) {
                Task { await model.log(preset) }
            }
        }
    }

    private var todaySection: some View {
        Section {
            if model.rows.isEmpty {
                Text("No drinks yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in
                WatchTodayRow(row: row)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await model.delete(row) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
            otherAppsFootnote
        } header: {
            Text("Today")
        }
    }

    @ViewBuilder
    private var otherAppsFootnote: some View {
        let otherAppsML = model.summary.externalWaterML - model.summary.otherDeviceWaterML
        if otherAppsML > 0 {
            Text("Other apps in Health: \(VolumeText.short(otherAppsML))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func undo(_ toast: LogToast) {
        model.toast = nil
        Task { await model.undo(entryID: toast.entryID) }
    }
}

private extension Binding where Value == String? {
    /// True while the message is set; setting false (alert dismissed) clears it.
    var watchIsPresent: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { shown in
                if !shown { wrappedValue = nil }
            }
        )
    }
}

/// Shown while Health access has not been requested on this watch.
private struct WatchHealthRow: View {
    var body: some View {
        Label {
            Text("Allow Access to Health")
                .font(.footnote)
        } icon: {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
        }
    }
}
