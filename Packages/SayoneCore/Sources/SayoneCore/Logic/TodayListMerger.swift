import Foundation

public enum TodayListMerger {
    /// Today's rows: visible local entries in `day`, plus HealthKit samples in `day` that our app wrote on the
    /// other device (their SayoneEntryID is not in the local journal in any status). Newest first.
    /// Samples without an entry id (other apps) are not rows; they only appear in the footnote total.
    public static func merge(local: [IntakeEntry], health: [HealthWaterSample], day: DateInterval) -> [TodayRow] {
        var rows: [TodayRow] = []
        var allLocalIDs = Set<UUID>()
        for entry in local {
            allLocalIDs.insert(entry.id)
        }

        var seenRowIDs = Set<UUID>()
        for entry in local where entry.isVisible && day.sayoneContains(entry.date) {
            guard seenRowIDs.insert(entry.id).inserted else { continue }
            rows.append(TodayRow(id: entry.id,
                                 date: entry.date,
                                 drinkName: entry.drinkName,
                                 symbol: entry.symbol,
                                 volumeML: entry.volumeML,
                                 waterML: entry.nutrients.waterML,
                                 origin: entry.origin,
                                 isLocal: true,
                                 isPendingHealth: entry.health == .pending))
        }

        let genericName = Phrasebook.genericDrink(AppLanguage.bundleDefault)
        for sample in health {
            guard let entryID = sample.entryID,
                  !allLocalIDs.contains(entryID),
                  day.sayoneContains(sample.date),
                  seenRowIDs.insert(entryID).inserted else { continue }
            let name = sample.drinkName.flatMap { $0.isEmpty ? nil : $0 } ?? genericName
            rows.append(TodayRow(id: entryID,
                                 date: sample.date,
                                 drinkName: name,
                                 symbol: nil,
                                 volumeML: sample.volumeML ?? NutrientMath.safeInt(sample.waterML),
                                 waterML: sample.waterML,
                                 origin: sample.origin,
                                 isLocal: false,
                                 isPendingHealth: false))
        }

        rows.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return rows
    }
}
