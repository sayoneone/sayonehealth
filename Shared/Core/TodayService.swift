import Foundation
import os
import SayoneCore

struct TodayState: Sendable {
    let summary: TodaySummary
    let rows: [TodayRow]
    let healthSamples: [HealthWaterSample]
}

/// Today's total, rows and history. The total rule lives in SayoneCore.TodayMath; this type only feeds it.
enum TodayService {

    /// No HealthKit: cached snapshot + local journal. Safe in any process, locked or not.
    static func cachedSummary(now: Date = Date()) -> TodaySummary {
        let goal = AppGroup.catalog.load(now: now).settings.dailyGoalML
        return TodayMath.summary(snapshot: AppGroup.snapshot.load(),
                                 local: AppGroup.journal.all(),
                                 goalML: goal,
                                 now: now)
    }

    static func summary(readHealth: Bool, now: Date = Date()) async -> TodaySummary {
        if readHealth {
            await refreshSnapshot(now: now)
        }
        return cachedSummary(now: now)
    }

    /// One HealthKit query feeds both the summary and the rows.
    static func today(now: Date = Date()) async -> TodayState {
        let samples = await refreshSnapshot(now: now) ?? []
        let summary = cachedSummary(now: now)
        return TodayState(summary: summary, rows: rows(using: samples, now: now), healthSamples: samples)
    }

    static func rows(using samples: [HealthWaterSample], now: Date = Date()) -> [TodayRow] {
        let day = TodayMath.day(containing: now)
        return TodayListMerger.merge(local: AppGroup.journal.all(), health: samples, day: day)
    }

    /// Last `days` days including today, oldest first. HealthKit totals (all sources) with today replaced
    /// by the cached summary; if HealthKit cannot be read, this device's journal only.
    static func history(days: Int, now: Date = Date()) async -> [DayTotal] {
        let count = max(days, 1)
        do {
            var totals = try await HealthGateway.shared.dailyWater(days: count, now: now)
            let todayStart = TodayMath.day(containing: now).start
            if let last = totals.last, last.dayStart == todayStart {
                totals[totals.count - 1] = DayTotal(dayStart: todayStart, waterML: cachedSummary(now: now).waterML)
            }
            return totals
        } catch {
            let reason = String(describing: error)
            AppLog.health.notice("History from journal only: \(reason, privacy: .public)")
            return TodayMath.localDailyTotals(AppGroup.journal.all(), days: count, now: now)
        }
    }

    /// Reads today's water samples, then (and only then) lists the journal IDs, and stores the snapshot.
    /// Returns nil when HealthKit cannot be read (unavailable, locked, denied); the old snapshot stays.
    @discardableResult
    static func refreshSnapshot(now: Date = Date()) async -> [HealthWaterSample]? {
        let gateway = HealthGateway.shared
        guard gateway.isAvailable else { return nil }
        let readAt = Date()
        let samples: [HealthWaterSample]
        do {
            samples = try await gateway.todayWaterSamples(now: now)
        } catch {
            let reason = String(describing: HealthGateway.map(error))
            AppLog.health.notice("Health read skipped: \(reason, privacy: .public)")
            return nil
        }
        // Load-bearing order: journal IDs are listed AFTER the query returned (see TodayMath).
        let localIDs = Set(AppGroup.journal.all().map { $0.id })
        let snapshot = TodayMath.makeSnapshot(samples: samples, localEntryIDs: localIDs, now: now, readAt: readAt)
        do {
            try AppGroup.snapshot.saveIfNewer(snapshot)
        } catch {
            let reason = String(describing: error)
            AppLog.store.error("Snapshot save failed: \(reason, privacy: .public)")
        }
        return samples
    }
}
