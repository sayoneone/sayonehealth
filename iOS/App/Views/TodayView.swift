import Foundation
import SwiftUI
import AppIntents
import SayoneCore

/// Root screen: progress card, one-tap preset grid, "Other drink…", Siri tip, today's list, undo toast.
struct TodayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingDismissed") private var onboardingDismissed: Bool = false
    @AppStorage("siriTipVisible") private var siriTipVisible: Bool = true
    @State private var showLogSheet: Bool = false
    @State private var editingPreset: Preset? = nil

    var body: some View {
        NavigationStack {
            todayList
                .navigationTitle(Text(verbatim: "SayoneHealth"))
                .toolbar { toolbarItems }
                .sheet(isPresented: $showLogSheet) {
                    LogDrinkSheet()
                        .environmentObject(model)
                }
                .sheet(item: $editingPreset) { preset in
                    presetEditorSheet(preset)
                }
        }
        .overlay(alignment: .bottom) { toastOverlay }
        .animation(.snappy, value: model.toast)
        .onOpenURL { model.handle(url: $0) }
        .onChange(of: scenePhase) { _, p in
            if p == .active { Task { await model.refresh() } }
        }
        .task { await model.refresh() }
        .sheet(item: $model.confirmRequest) { request in
            ConfirmLogSheet(request: request)
                .environmentObject(model)
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            OnboardingView()
                .environmentObject(model)
        }
        .alert(Text(verbatim: "SayoneHealth"), isPresented: alertBinding) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(verbatim: model.alertMessage ?? "")
        }
        .sensoryFeedback(.success, trigger: model.logCounter)
    }

    // MARK: - List

    private var todayList: some View {
        List {
            Section {
                ProgressCard(summary: model.summary)
                healthRow
            }
            Section {
                PresetGrid(onEdit: { beginEditing($0) })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                Button {
                    showLogSheet = true
                } label: {
                    Label("Other drink…", systemImage: "plus.circle.fill")
                }
            }
            siriTipSection
            TodayListSection()
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var siriTipSection: some View {
        if siriTipVisible {
            Section {
                SiriTipView(intent: LogWaterIntent(), isVisible: $siriTipVisible)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var healthRow: some View {
        if model.healthAuth == .notDetermined {
            Button {
                model.showHealthOnboarding = true
            } label: {
                Label("Allow Access to Health", systemImage: "heart.fill")
            }
        } else if model.healthAuth == .denied {
            Label("No access to Health. Drinks are kept on this device only.", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            NavigationLink {
                HistoryView()
            } label: {
                Label("History", systemImage: "chart.bar.fill")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = model.toast {
            ToastView(toast: toast)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Preset editing from the grid's context menu

    private func beginEditing(_ display: PresetDisplay) {
        editingPreset = model.catalog.presets.first(where: { $0.id == display.id })
    }

    private func presetEditorSheet(_ preset: Preset) -> some View {
        NavigationStack {
            PresetEditorView(preset: preset)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingPreset = nil }
                    }
                }
        }
        .environmentObject(model)
    }

    // MARK: - Bindings

    /// Shown when requested by a deep link / button, or on first launch until the user taps "Later".
    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { model.showHealthOnboarding || (model.needsHealthOnboarding && !onboardingDismissed) },
            set: { isPresented in
                if !isPresented {
                    model.showHealthOnboarding = false
                    onboardingDismissed = true
                }
            }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { isPresented in
                if !isPresented { model.alertMessage = nil }
            }
        )
    }
}
