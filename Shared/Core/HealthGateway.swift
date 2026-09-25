import Foundation
import HealthKit
import os
import SayoneCore

enum HealthWriteAuth: Sendable, Equatable {
    case authorized, denied, notDetermined, unavailable
}

enum HealthGatewayError: Error, Equatable {
    case unavailable, notAuthorized, locked, other(String)
}

/// All HealthKit I/O. Process-agnostic: compiled into both apps and both widget extensions, so it never
/// prompts for authorization (the apps add that in Shared/AppOnly/HealthAuthorization.swift).
final class HealthGateway: @unchecked Sendable {
    static let shared: HealthGateway = HealthGateway()

    let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Authorization state (no prompt)

    func writeAuth(_ c: HealthComponent) -> HealthWriteAuth {
        guard isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: HKDrinkTypes.type(c)) {
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    /// True when the system would still show the permission sheet for our share/read sets.
    func needsAuthorizationPrompt() async -> Bool {
        guard isAvailable else { return false }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: HKDrinkTypes.share,
                                                                       read: HKDrinkTypes.read)
            return status == .shouldRequest
        } catch {
            return false
        }
    }

    // MARK: - Write

    /// Saves the entry's samples in one all-or-nothing call. Components whose write permission is not
    /// granted are skipped, so a denied caffeine permission never drops the water sample.
    func save(_ entry: IntakeEntry, includeNutrients: Bool) async throws {
        try requireWaterWriteAccess()
        let specs = HealthSamplePlan.specs(for: entry, includeNutrients: includeNutrients)
        var objects: [HKObject] = []
        for spec in specs where self.writeAuth(spec.component) == .authorized {
            objects.append(HealthGateway.makeSample(spec))
        }
        guard !objects.isEmpty else { return }
        do {
            try await store.save(objects)
        } catch {
            throw HealthGateway.map(error)
        }
    }

    // MARK: - Lookup and delete by SayoneEntryID

    /// True if any water sample carries `SayoneEntryID == entryID` (any source this app can see).
    func hasSamples(entryID: UUID) async throws -> Bool {
        guard isAvailable else { throw HealthGatewayError.unavailable }
        let predicate = HealthGateway.entryPredicate(entryID)
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [.quantitySample(type: HKDrinkTypes.type(.water), predicate: predicate)],
            sortDescriptors: [],
            limit: 1)
        do {
            let found = try await descriptor.result(for: store)
            return !found.isEmpty
        } catch let e as HKError where e.code == .errorNoData {
            return false
        } catch {
            throw HealthGateway.map(error)
        }
    }

    /// Deletes this entry's samples. Water first (its errors propagate), then the nutrient types this app
    /// may write, best effort. Returns the number of objects HealthKit deleted.
    func deleteSamples(entryID: UUID) async throws -> Int {
        try requireWaterWriteAccess()
        let predicate = HealthGateway.entryPredicate(entryID)
        var deleted: Int
        do {
            deleted = try await store.deleteObjects(of: HKDrinkTypes.type(.water), predicate: predicate)
        } catch let e as HKError where e.code == .errorNoData {
            deleted = 0
        } catch {
            throw HealthGateway.map(error)
        }
        for component in HealthComponent.allCases where component != .water {
            guard self.writeAuth(component) == .authorized else { continue }
            do {
                let removed = try await store.deleteObjects(of: HKDrinkTypes.type(component), predicate: predicate)
                deleted += removed
            } catch {
                let name = component.rawValue
                let reason = String(describing: error)
                AppLog.health.error("Nutrient delete failed (\(name, privacy: .public)): \(reason, privacy: .public)")
            }
        }
        return deleted
    }

    // MARK: - Read

    /// Today's water samples from every source, newest first. No data gives `[]`.
    func todayWaterSamples(now: Date) async throws -> [HealthWaterSample] {
        guard isAvailable else { throw HealthGatewayError.unavailable }
        let day = TodayMath.day(containing: now)
        let predicate = HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: .strictStartDate)
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [.quantitySample(type: HKDrinkTypes.type(.water), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1000)
        let samples: [HKQuantitySample]
        do {
            samples = try await descriptor.result(for: store)
        } catch let e as HKError where e.code == .errorNoData {
            return []
        } catch {
            throw HealthGateway.map(error)
        }
        var result: [HealthWaterSample] = []
        result.reserveCapacity(samples.count)
        for sample in samples {
            result.append(HealthGateway.waterSample(from: sample))
        }
        return result
    }

    /// Daily water totals from every source for the last `days` days including today, oldest first.
    /// Always returns exactly `max(days, 1)` elements; days without data are 0.
    func dailyWater(days: Int, now: Date) async throws -> [DayTotal] {
        guard isAvailable else { throw HealthGatewayError.unavailable }
        let count = max(days, 1)
        let calendar = Calendar.current
        let today = TodayMath.day(containing: now, calendar: calendar)
        let todayStart = today.start
        guard let from = calendar.date(byAdding: .day, value: -(count - 1), to: todayStart) else { return [] }
        let to = today.end
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKDrinkTypes.type(.water),
                                       predicate: HKQuery.predicateForSamples(withStart: from, end: to, options: [])),
            options: .cumulativeSum,
            anchorDate: todayStart,
            intervalComponents: DateComponents(day: 1))
        let collection: HKStatisticsCollection?
        do {
            collection = try await descriptor.result(for: store)
        } catch let e as HKError where e.code == .errorNoData {
            collection = nil
        } catch {
            throw HealthGateway.map(error)
        }
        let unit = HKDrinkTypes.unit(.water)
        var totals: [DayTotal] = []
        var dayStart = from
        for _ in 0..<count {
            let statistics = collection?.statistics(for: dayStart)
            let ml = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
            totals.append(DayTotal(dayStart: dayStart, waterML: Int(ml.rounded())))
            guard let next = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            dayStart = next
        }
        return totals
    }

    // MARK: - Error mapping

    static func map(_ error: Error) -> HealthGatewayError {
        if let mapped = error as? HealthGatewayError {
            return mapped
        }
        if let e = error as? HKError {
            switch e.code {
            case .errorDatabaseInaccessible:
                return .locked
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
                return .notAuthorized
            case .errorHealthDataUnavailable:
                return .unavailable
            default:
                return .other(e.localizedDescription)
            }
        }
        return .other(error.localizedDescription)
    }

    // MARK: - Private helpers

    private func requireWaterWriteAccess() throws {
        switch writeAuth(.water) {
        case .authorized:
            return
        case .unavailable:
            throw HealthGatewayError.unavailable
        case .denied, .notDetermined:
            throw HealthGatewayError.notAuthorized
        }
    }

    private static func entryPredicate(_ entryID: UUID) -> NSPredicate {
        HKQuery.predicateForObjects(withMetadataKey: HealthMetadata.entryIDKey,
                                    allowedValues: [entryID.uuidString])
    }

    private static func makeSample(_ spec: HealthSampleSpec) -> HKQuantitySample {
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: spec.syncIdentifier,
            HKMetadataKeySyncVersion: NSNumber(value: spec.syncVersion),
            HKMetadataKeyFoodType: spec.foodType,
            HKMetadataKeyWasUserEntered: NSNumber(value: true)
        ]
        for (key, value) in spec.custom {
            switch value {
            case .string(let text):
                metadata[key] = text
            case .number(let number):
                metadata[key] = NSNumber(value: number)
            }
        }
        let quantity = HKQuantity(unit: HKDrinkTypes.unit(spec.component), doubleValue: spec.amount)
        return HKQuantitySample(type: HKDrinkTypes.type(spec.component),
                                quantity: quantity,
                                start: spec.date,
                                end: spec.date,
                                metadata: metadata)
    }

    private static func waterSample(from sample: HKQuantitySample) -> HealthWaterSample {
        let metadata: [String: Any] = sample.metadata ?? [:]
        var entryID: UUID? = nil
        if let raw = metadata[HealthMetadata.entryIDKey] as? String {
            entryID = UUID(uuidString: raw)
        }
        let drinkID = metadata[HealthMetadata.drinkIDKey] as? String
        let drinkName = metadata[HKMetadataKeyFoodType] as? String
        var volumeML: Int? = nil
        if let number = metadata[HealthMetadata.volumeKey] as? NSNumber {
            volumeML = number.intValue
        }
        var origin: DeviceKind? = nil
        if let raw = metadata[HealthMetadata.originKey] as? String {
            origin = DeviceKind(rawValue: raw)
        }
        return HealthWaterSample(date: sample.startDate,
                                 waterML: sample.quantity.doubleValue(for: HKDrinkTypes.unit(.water)),
                                 entryID: entryID,
                                 drinkID: drinkID,
                                 drinkName: drinkName,
                                 volumeML: volumeML,
                                 origin: origin)
    }
}
