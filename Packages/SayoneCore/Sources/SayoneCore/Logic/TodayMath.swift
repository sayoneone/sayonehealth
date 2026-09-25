import Foundation

/// THE total rule (§5.1): `Today = snapshot.externalWaterML + Σ visible local entries`.
///
/// `externalWaterML` is today's HealthKit water minus every sample whose SayoneEntryID is in this device's
/// journal (listed after the HealthKit query returned), so nothing is counted twice.
public enum TodayMath {
    /// The calendar day containing `date`, as [start of day, start of next day).
    public static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        if let interval = calendar.dateInterval(of: .day, for: date), interval.duration > 0 {
            return interval
        }
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(1)))
    }

    /// The start of the calendar day after the one containing `date` (always later than `date`).
    public static func nextDayStart(after date: Date, calendar: Calendar = .current) -> Date {
        day(containing: date, calendar: calendar).end
    }

    public static func makeSnapshot(samples: [HealthWaterSample], localEntryIDs: Set<UUID>, now: Date, readAt: Date,
                                    calendar: Calendar = .current) -> HealthSnapshot {
        let today = day(containing: now, calendar: calendar)
        var external = 0.0
        var other = 0.0
        // A foreign entry counts once even if its water sample exists twice (e.g. a re-save from another
        // process); TodayListMerger shows it as one row, so the total must agree.
        var countedForeign = Set<UUID>()
        for sample in samples where today.sayoneContains(sample.date) && sample.waterML.isFinite {
            if let entryID = sample.entryID {
                if !localEntryIDs.contains(entryID) && countedForeign.insert(entryID).inserted {
                    external += sample.waterML
                    other += sample.waterML
                }
            } else {
                external += sample.waterML
            }
        }
        return HealthSnapshot(dayStart: today.start, externalWaterML: external, otherDeviceWaterML: other, readAt: readAt)
    }

    public static func summary(snapshot: HealthSnapshot?, local: [IntakeEntry], goalML: Int, now: Date,
                               calendar: Calendar = .current) -> TodaySummary {
        let today = day(containing: now, calendar: calendar)

        var external = 0.0
        var other = 0.0
        var healthReadAt: Date?
        if let snapshot = snapshot, isSameInstant(snapshot.dayStart, today.start) {
            external = snapshot.externalWaterML.isFinite ? snapshot.externalWaterML : 0
            other = snapshot.otherDeviceWaterML.isFinite ? snapshot.otherDeviceWaterML : 0
            healthReadAt = snapshot.readAt
        }

        var localSum = 0.0
        var pendingCount = 0
        var lastLocal: IntakeEntry?
        for entry in local {
            if entry.health == .pending { pendingCount += 1 }
            guard entry.isVisible, today.sayoneContains(entry.date) else { continue }
            if entry.nutrients.waterML.isFinite { localSum += entry.nutrients.waterML }
            if let current = lastLocal, current.date >= entry.date { continue }
            lastLocal = entry
        }

        var undoUntil: Date?
        if let last = lastLocal {
            let until = last.date.addingTimeInterval(UndoPolicy.widgetWindow)
            if until > now { undoUntil = until }
        }

        return TodaySummary(waterML: NutrientMath.safeInt(external + localSum),
                            goalML: goalML,
                            localWaterML: NutrientMath.safeInt(localSum),
                            externalWaterML: NutrientMath.safeInt(external),
                            otherDeviceWaterML: NutrientMath.safeInt(other),
                            pendingCount: pendingCount,
                            lastLocal: lastLocal,
                            undoAvailableUntil: undoUntil,
                            healthReadAt: healthReadAt)
    }

    /// Water per day from this device's journal only; `days` days ending today, oldest first, visible entries only.
    public static func localDailyTotals(_ entries: [IntakeEntry], days: Int, now: Date,
                                        calendar: Calendar = .current) -> [DayTotal] {
        guard days > 0 else { return [] }
        let todayStart = day(containing: now, calendar: calendar).start
        var intervals: [DateInterval] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            let anchor = calendar.date(byAdding: .day, value: -offset, to: todayStart)
                ?? todayStart.addingTimeInterval(-86_400 * Double(offset))
            intervals.append(day(containing: anchor, calendar: calendar))
        }
        var sums = [Double](repeating: 0, count: intervals.count)
        for entry in entries where entry.isVisible && entry.nutrients.waterML.isFinite {
            if let index = intervals.firstIndex(where: { $0.sayoneContains(entry.date) }) {
                sums[index] += entry.nutrients.waterML
            }
        }
        return zip(intervals, sums).map { DayTotal(dayStart: $0.0.start, waterML: NutrientMath.safeInt($0.1)) }
    }

    /// Day starts are whole seconds; a sub-second tolerance keeps the comparison immune to JSON round trips.
    static func isSameInstant(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 0.5
    }
}

extension DateInterval {
    /// Half-open containment [start, end): an instant at midnight belongs to the new day only.
    /// (Foundation's `contains` includes `end`.) A zero-length interval contains only its start.
    func sayoneContains(_ date: Date) -> Bool {
        if duration <= 0 { return date == start }
        return date >= start && date < end
    }
}
