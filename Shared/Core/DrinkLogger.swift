import Foundation
import os
import SayoneCore

struct LogOutcome: Sendable {
    let entry: IntakeEntry
    let isDuplicate: Bool         // .existing or .duplicate from JournalStore.create
    let stored: Bool              // false => journal write failed (e.g. before first unlock); nothing persisted
    let savedToHealth: Bool
    let healthAuth: HealthWriteAuth
    let summary: TodaySummary
}

enum DeleteOutcome: Sendable, Equatable {
    case deleted, queued, notDeletableHere, notFound, failed
}

struct UndoResult: Sendable {
    let outcome: DeleteOutcome
    let entry: IntakeEntry?
}

/// Logging, flushing, deleting and undoing drinks. Process-agnostic (apps, widgets, controls, Siri):
/// never throws, never prompts, and always journals before touching HealthKit.
enum DrinkLogger {

    // MARK: - Log

    static func log(drinkID: String, volumeML: Int, fallbackName: String = "", source: LogSource,
                    date: Date = Date(), entryID: UUID? = nil) async -> LogOutcome {
        let lang = AppLanguage.current
        let catalog = AppGroup.catalog.load()
        let gateway = HealthGateway.shared
        let journal = AppGroup.journal
        let auth = gateway.writeAuth(.water)

        let resolved = DrinkResolver.resolve(drinkID: drinkID, in: catalog, fallbackName: fallbackName)
        if !resolved.isKnown {
            AppLog.intake.error("Unknown drink \(drinkID, privacy: .public); logging it under its own name")
        }
        let candidate = IntakeFactory.make(drink: resolved.drink,
                                           displayName: resolved.drink.name(lang),
                                           volumeML: volumeML,
                                           date: date,
                                           origin: ThisDevice.kind,
                                           source: source,
                                           id: entryID ?? UUID())

        // 1. Journal first. A tap is never lost once this succeeds.
        let entry: IntakeEntry
        do {
            switch try journal.create(candidate) {
            case .created(let created):
                entry = created
            case .existing(let earlier), .duplicate(let earlier):
                return LogOutcome(entry: earlier, isDuplicate: true, stored: true,
                                  savedToHealth: earlier.health == .saved, healthAuth: auth,
                                  summary: TodayService.cachedSummary())
            }
        } catch {
            let reason = String(describing: error)
            AppLog.intake.error("Journal write failed: \(reason, privacy: .public)")
            return LogOutcome(entry: candidate, isDuplicate: false, stored: false, savedToHealth: false,
                              healthAuth: auth, summary: TodayService.cachedSummary())
        }

        // 2. HealthKit. On failure the entry stays .pending and is flushed later by the app.
        var saved = false
        if auth == .authorized {
            do {
                try await gateway.save(entry, includeNutrients: catalog.settings.writeNutrients)
                switch try journal.markSaved(id: entry.id, at: Date()) {
                case .marked, .alreadySaved:
                    saved = true
                case .deletedMeanwhile, .missing:
                    // Undone while the save was in flight: this process owns the samples, so remove them.
                    _ = try? await gateway.deleteSamples(entryID: entry.id)
                    _ = try? journal.finishDelete(id: entry.id, at: Date())
                }
            } catch {
                let id = entry.id.uuidString
                let reason = String(describing: error)
                AppLog.health.error("Health save deferred for \(id, privacy: .public): \(reason, privacy: .public)")
            }
        }

        // 3. Only the app flushes older pending work; widget taps stay fast.
        if ThisDevice.process == .app {
            await flush(limit: 5)
        }

        let summary = TodayService.cachedSummary()
        WidgetRefresher.reloadAll()
        return LogOutcome(entry: journal.entry(id: entry.id) ?? entry, isDuplicate: false, stored: true,
                          savedToHealth: saved, healthAuth: auth, summary: summary)
    }

    // MARK: - Flush

    /// Retries pending saves and pending deletes, oldest first. Returns the number of entries completed.
    @discardableResult
    static func flush(limit: Int = 50) async -> Int {
        let gateway = HealthGateway.shared
        guard gateway.writeAuth(.water) == .authorized else { return 0 }
        let journal = AppGroup.journal
        let queue = Array(journal.needingFlush().prefix(max(limit, 0)))
        guard !queue.isEmpty else { return 0 }
        let includeNutrients = AppGroup.catalog.load().settings.writeNutrients

        var completed = 0
        entries: for entry in queue {
            do {
                switch entry.health {
                case .pending:
                    let alreadyInHealth = try await gateway.hasSamples(entryID: entry.id)
                    if !alreadyInHealth {
                        try await gateway.save(entry, includeNutrients: includeNutrients)
                    }
                    switch try journal.markSaved(id: entry.id, at: Date()) {
                    case .marked, .alreadySaved:
                        break
                    case .deletedMeanwhile, .missing:
                        _ = try await gateway.deleteSamples(entryID: entry.id)
                        try journal.finishDelete(id: entry.id, at: Date())
                    }
                case .pendingDelete:
                    // Never saved again. Without write access there is nothing we can delete: finish anyway.
                    do {
                        _ = try await gateway.deleteSamples(entryID: entry.id)
                    } catch let e as HealthGatewayError where e == .notAuthorized || e == .unavailable {
                        let id = entry.id.uuidString
                        AppLog.health.notice("Finishing delete of \(id, privacy: .public) without Health access")
                    }
                    try journal.finishDelete(id: entry.id, at: Date())
                case .saved, .deleted:
                    continue entries
                }
                completed += 1
            } catch {
                let mapped = HealthGateway.map(error)
                let id = entry.id.uuidString
                let reason = String(describing: mapped)
                AppLog.health.error("Flush failed for \(id, privacy: .public): \(reason, privacy: .public)")
                if mapped == .locked {
                    break entries
                }
            }
        }
        if completed > 0 {
            WidgetRefresher.reloadAll()
        }
        return completed
    }

    // MARK: - Delete

    static func delete(entryID: UUID, isLocal: Bool) async -> DeleteOutcome {
        let gateway = HealthGateway.shared

        // A row logged on the other device: HealthKit may refuse (different source). Try once, be honest.
        guard isLocal else {
            do {
                let removed = try await gateway.deleteSamples(entryID: entryID)
                guard removed > 0 else { return .notDeletableHere }
                WidgetRefresher.reloadAll()
                return .deleted
            } catch {
                let reason = String(describing: error)
                AppLog.health.error("Other-device delete failed: \(reason, privacy: .public)")
                return .notDeletableHere
            }
        }

        let journal = AppGroup.journal
        let previous: HealthSyncStatus
        do {
            switch try journal.beginDelete(id: entryID, at: Date()) {
            case .notFound:
                return .notFound
            case .alreadyDeleted:
                return .deleted
            case .began(previous: let status, entry: _):
                previous = status
            case .alreadyDeleting(_):
                previous = .saved
            }
        } catch {
            let reason = String(describing: error)
            AppLog.intake.error("beginDelete failed: \(reason, privacy: .public)")
            return .failed
        }

        // The entry is hidden from now on, whatever HealthKit says.
        WidgetRefresher.reloadAll()
        do {
            _ = try await gateway.deleteSamples(entryID: entryID)
            try journal.finishDelete(id: entryID, at: Date())
            return .deleted
        } catch let e as HealthGatewayError where e == .notAuthorized || e == .unavailable {
            if previous == .saved && ThisDevice.process == .widgetExtension {
                // The widget extension may lack the Health access the app has (risk R2/R3). Keep the entry
                // pendingDelete (hidden, not counted) so the app's flush removes the samples later.
                AppLog.health.notice("Widget undo without Health access: delete queued for the app")
                return .queued
            }
            _ = try? journal.finishDelete(id: entryID, at: Date())
            return previous == .saved ? .notDeletableHere : .deleted
        } catch {
            let reason = String(describing: error)
            AppLog.health.error("Delete queued: \(reason, privacy: .public)")
            return .queued
        }
    }

    // MARK: - Undo

    static func undoLast(window: TimeInterval) async -> UndoResult {
        let now = Date()
        guard let candidate = UndoPolicy.candidate(in: AppGroup.journal.all(), now: now, window: window) else {
            return UndoResult(outcome: .notFound, entry: nil)
        }
        let outcome = await delete(entryID: candidate.id, isLocal: true)
        return UndoResult(outcome: outcome, entry: candidate)
    }
}
