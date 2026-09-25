import Foundation
import Combine
import SwiftUI
import AppIntents
import os
import SayoneCore

struct LogToast: Identifiable, Equatable {
    let id: UUID
    let text: String
    let entryID: UUID
    let savedToHealth: Bool
}

struct ConfirmRequest: Identifiable, Equatable {
    let id: UUID                  // also used as the entryID -> a double tap on "Записать" stays one entry
    let drinkID: String
    let volumeML: Int
    let drinkName: String
    let symbol: String
}

struct DiagnosticsInfo: Equatable {
    let appGroupID: String
    let appGroupShared: Bool
    let device: DeviceKind
    let journalCount: Int
    let pendingCount: Int
    let pendingDeleteCount: Int
    let healthReadAt: Date?
    let catalogRevision: Int64
    let waterWriteAuth: HealthWriteAuth
}

/// The state behind both apps' UI. iPhone-only parts (catalog push to the watch) are behind `#if os(iOS)`.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var catalog: Catalog
    @Published private(set) var summary: TodaySummary
    @Published private(set) var rows: [TodayRow]
    @Published private(set) var healthAuth: HealthWriteAuth
    @Published private(set) var needsHealthOnboarding: Bool = false
    @Published private(set) var logCounter: Int = 0            // haptic trigger
    @Published var toast: LogToast? = nil
    @Published var confirmRequest: ConfirmRequest? = nil
    @Published var showHealthOnboarding: Bool = false
    @Published var alertMessage: String? = nil

    /// Today's HealthKit water samples from the last successful read (other-device rows).
    private var lastSamples: [HealthWaterSample] = []
    private var isRefreshing: Bool = false
    private var refreshRequested: Bool = false
    #if os(iOS)
    private var lastPushedRevision: Int64? = nil
    #endif

    var presets: [PresetDisplay] {
        catalog.presetDisplays(.current)
    }

    /// Synchronous and cheap: catalog + cached summary from the App Group. No HealthKit query.
    private init() {
        catalog = AppGroup.catalog.load()
        summary = TodayService.cachedSummary()
        rows = TodayService.rows(using: [])
        healthAuth = HealthGateway.shared.writeAuth(.water)
    }

    // MARK: - Refresh

    /// Flush, prune, reload, read Health. Concurrent calls (scene activation, .task, after a permission
    /// prompt) are coalesced into one extra pass instead of running two flushes side by side.
    func refresh() async {
        if isRefreshing {
            refreshRequested = true
            return
        }
        isRefreshing = true
        repeat {
            refreshRequested = false
            await performRefresh()
        } while refreshRequested
        isRefreshing = false
    }

    private func performRefresh() async {
        await DrinkLogger.flush()
        do {
            _ = try AppGroup.journal.prune(now: Date())
        } catch {
            let reason = String(describing: error)
            AppLog.store.error("Journal prune failed: \(reason, privacy: .public)")
        }
        catalog = AppGroup.catalog.load()
        let gateway = HealthGateway.shared
        healthAuth = gateway.writeAuth(.water)
        if gateway.isAvailable {
            needsHealthOnboarding = await gateway.needsAuthorizationPrompt()
        } else {
            needsHealthOnboarding = false
        }
        let state = await TodayService.today()
        summary = state.summary
        rows = state.rows
        lastSamples = state.healthSamples
        WidgetRefresher.reloadAll()
        #if os(iOS)
        if lastPushedRevision != catalog.revision {
            CatalogSync.shared.push(catalog)
            lastPushedRevision = catalog.revision
        }
        #endif
    }

    func requestHealthAccess() async {
        do {
            // Refreshes the model itself once the sheet is answered, so pending entries flush right away.
            try await HealthGateway.shared.requestAuthorization()
        } catch {
            let reason = String(describing: error)
            AppLog.health.error("Health authorization failed: \(reason, privacy: .public)")
            await refresh()
        }
        showHealthOnboarding = false
    }

    // MARK: - Logging

    func log(drinkID: String, volumeML: Int) async {
        let outcome = await DrinkLogger.log(drinkID: drinkID, volumeML: volumeML, source: .app)
        present(outcome)
    }

    func log(_ preset: PresetDisplay) async {
        let outcome = await DrinkLogger.log(drinkID: preset.drinkID, volumeML: preset.volumeML,
                                            fallbackName: preset.drinkName, source: .app)
        present(outcome)
    }

    /// Deep-link confirmation. Idempotent: the request id is the entry id, so a second tap is `.existing`.
    func confirm(_ request: ConfirmRequest) async {
        let outcome = await DrinkLogger.log(drinkID: request.drinkID, volumeML: request.volumeML,
                                            fallbackName: request.drinkName, source: .deepLink,
                                            entryID: request.id)
        if confirmRequest?.id == request.id {
            confirmRequest = nil
        }
        present(outcome)
    }

    private func present(_ outcome: LogOutcome) {
        if outcome.stored && !outcome.isDuplicate {
            let text = Phrasebook.toast(drinkName: outcome.entry.drinkName,
                                        volumeML: outcome.entry.volumeML,
                                        .current)
            let newToast = LogToast(id: UUID(), text: text, entryID: outcome.entry.id,
                                    savedToHealth: outcome.savedToHealth)
            toast = newToast
            logCounter += 1
            scheduleToastDismissal(id: newToast.id)
        }
        if !outcome.stored {
            alertMessage = SiriText.logged(outcome)
        }
        healthAuth = outcome.healthAuth
        summary = outcome.summary
        rows = TodayService.rows(using: lastSamples)
    }

    private func scheduleToastDismissal(id: UUID) {
        let nanoseconds = UInt64(max(UndoPolicy.toastDuration, 0) * 1_000_000_000)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard let self = self else { return }
            if self.toast?.id == id {
                self.toast = nil
            }
        }
    }

    // MARK: - Undo and delete

    func undo(entryID: UUID) async {
        if toast?.entryID == entryID {
            toast = nil
        }
        let outcome = await DrinkLogger.delete(entryID: entryID, isLocal: true)
        report(outcome)
        summary = TodayService.cachedSummary()
        rows = TodayService.rows(using: lastSamples)
    }

    func delete(_ row: TodayRow) async {
        let outcome = await DrinkLogger.delete(entryID: row.id, isLocal: row.isLocal)
        report(outcome)
        if !row.isLocal && outcome == .deleted {
            // The other device's sample is gone from Health: re-read so the external total drops too.
            let rowID = row.id
            if let samples = await TodayService.refreshSnapshot() {
                lastSamples = samples
            } else {
                lastSamples.removeAll(where: { $0.entryID == rowID })
            }
        }
        summary = TodayService.cachedSummary()
        rows = TodayService.rows(using: lastSamples)
    }

    private func report(_ outcome: DeleteOutcome) {
        switch outcome {
        case .notDeletableHere:
            alertMessage = Phrasebook.notDeletableHere(.current)
        case .failed:
            alertMessage = Phrasebook.storeFailed(.current)
        case .deleted, .queued, .notFound:
            break
        }
    }

    // MARK: - History

    func history(days: Int) async -> [DayTotal] {
        await TodayService.history(days: days)
    }

    // MARK: - Deep links (never log)

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else {
            let text = url.absoluteString
            AppLog.intake.notice("Ignored URL \(text, privacy: .public)")
            return
        }
        switch link {
        case .today:
            break
        case .healthAccess:
            showHealthOnboarding = true
        case .confirmLog(let drinkID, let volumeML):
            let current = AppGroup.catalog.load()
            let drink = DrinkResolver.resolve(drinkID: drinkID, in: current, fallbackName: "").drink
            confirmRequest = ConfirmRequest(id: UUID(),
                                            drinkID: drinkID,
                                            volumeML: NutrientMath.clampVolume(volumeML),
                                            drinkName: drink.displayName,
                                            symbol: drink.symbol)
        }
    }

    // MARK: - Catalog

    /// iPhone only (the watch never edits). Usage: `model.edit { _ = CatalogEditor.addPreset(to: &$0, …) }`.
    func edit(_ change: (inout Catalog) -> Void) {
        var updated = catalog
        change(&updated)
        do {
            try AppGroup.catalog.save(updated)
        } catch {
            let reason = String(describing: error)
            AppLog.store.error("Catalog save failed: \(reason, privacy: .public)")
        }
        catalog = AppGroup.catalog.load()
        summary = TodayService.cachedSummary()
        #if os(iOS)
        CatalogSync.shared.push(catalog)
        lastPushedRevision = catalog.revision
        #endif
        WidgetRefresher.catalogDidChange()
        SayoneShortcuts.updateAppShortcutParameters()
    }

    /// Watch: a newer catalog arrived from the iPhone (already saved by the sync delegate).
    func applyReceivedCatalog(_ catalog: Catalog) {
        self.catalog = catalog
        summary = TodayService.cachedSummary()
    }

    // MARK: - Diagnostics

    func diagnostics() -> DiagnosticsInfo {
        let entries = AppGroup.journal.all()
        let pending = entries.filter { $0.health == .pending }.count
        let pendingDelete = entries.filter { $0.health == .pendingDelete }.count
        return DiagnosticsInfo(appGroupID: AppGroup.identifier,
                               appGroupShared: AppGroup.isShared,
                               device: ThisDevice.kind,
                               journalCount: entries.count,
                               pendingCount: pending,
                               pendingDeleteCount: pendingDelete,
                               healthReadAt: AppGroup.snapshot.load()?.readAt,
                               catalogRevision: catalog.revision,
                               waterWriteAuth: HealthGateway.shared.writeAuth(.water))
    }
}
