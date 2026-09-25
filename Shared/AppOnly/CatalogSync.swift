import Foundation
import WatchConnectivity
import AppIntents
import os
import SayoneCore

/// One-way catalog sync, iPhone -> watch, through the application context (newest revision wins).
/// The delegate callbacks arrive on a background queue, so nothing here is main-actor isolated; the model
/// is only touched through `Task { @MainActor in … }`.
final class CatalogSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared: CatalogSync = CatalogSync()

    private let stateLock = NSLock()
    private var activationRequested = false

    private override init() {
        super.init()
    }

    /// Idempotent. Called from `App.init()` of both apps.
    func activate() {
        guard WCSession.isSupported() else { return }
        stateLock.lock()
        let alreadyRequested = activationRequested
        activationRequested = true
        stateLock.unlock()
        guard !alreadyRequested else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate (both platforms)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            let reason = String(describing: error)
            AppLog.sync.error("Session activation failed: \(reason, privacy: .public)")
        }
        guard activationState == .activated else { return }
        #if os(iOS)
        push(AppGroup.catalog.load())
        #else
        apply(session.receivedApplicationContext)
        #endif
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        #if os(watchOS)
        apply(applicationContext)
        #endif
        // The phone never applies anything it receives.
    }

    // MARK: - iPhone

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // The user switched watches: activate again for the new one.
        WCSession.default.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        // Covers "watch app installed after the last edit".
        guard session.activationState == .activated else { return }
        push(AppGroup.catalog.load())
    }

    func push(_ catalog: Catalog) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        do {
            let payload = try CatalogSyncPayload.encode(catalog)
            try session.updateApplicationContext(payload)
            let revision = String(catalog.revision)
            AppLog.sync.info("Pushed catalog revision \(revision, privacy: .public)")
        } catch {
            let reason = String(describing: error)
            AppLog.sync.error("Catalog push failed: \(reason, privacy: .public)")
        }
    }

    var watchAppInstalled: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }
    #endif

    // MARK: - Watch

    #if os(watchOS)
    private func apply(_ payload: [String: Any]) {
        guard !payload.isEmpty else { return }
        guard let received = CatalogSyncPayload.decode(payload) else {
            AppLog.sync.error("Received catalog could not be decoded")
            return
        }
        let current = AppGroup.catalog.load()
        guard CatalogSyncPayload.shouldApply(received: received, current: current) else { return }
        do {
            try AppGroup.catalog.save(received)
        } catch {
            let reason = String(describing: error)
            AppLog.sync.error("Received catalog could not be saved: \(reason, privacy: .public)")
        }
        WidgetRefresher.catalogDidChange()
        Task { @MainActor in
            AppModel.shared.applyReceivedCatalog(received)
            SayoneShortcuts.updateAppShortcutParameters()
        }
    }
    #endif
}
