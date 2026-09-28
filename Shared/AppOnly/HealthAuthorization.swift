import HealthKit
import SayoneCore

// Apps only: extensions cannot show the Health permission sheet, so this lives outside Shared/Core.
extension HealthGateway {
    /// Shows the Health permission sheet (share: water, caffeine, energy, sugar; read: water), then
    /// refreshes the app model so pending entries flush immediately.
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        try await store.requestAuthorization(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)
        await AppModel.shared.refresh()
    }
}
