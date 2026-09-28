<!-- angle: RELIABILITY / OFFLINE-FIRST: a local App Group log as source of truth for UI/widgets, HealthKit mirrored idempotently with a pending-write queue (locked device, extension failures), explicit watch<->phone sync (WatchConnectivity) for presets and entries, deterministic dedup. -->

# SayoneHealth v1: Architecture Proposal

A drink logger for iPhone and Apple Watch. Every drink is written to Apple Health. The app has one-tap widgets, complications and controls, and Siri support in Russian and English.

---

## 0. Design invariants

Every component below follows these eight rules. Most of the test plan checks them.

| # | Invariant | Mechanism |
|---|---|---|
| I1 | **A tap is committed before anything else happens.** The drink is stored durably before HealthKit, WatchConnectivity or widget reloads are touched. | Coordinated, atomic write of the entry into the App Group store (§5) is always step 1 of `LogPipeline.log`. |
| I2 | **One logical drink has one ID for life.** | `EntryID` is a UUID created once, by the process that received the tap. Replays, sync and HealthKit all key on it. |
| I3 | **Exactly one device writes or deletes an entry's HealthKit samples.** | `DrinkEntry.owner` is the device that was tapped. The other device never writes HealthKit for that entry. |
| I4 | **HealthKit writes are idempotent.** | Each sample has sync ID `sayone.<entryID>.<metric>`. The sync version is chosen *write-ahead*: persisted before `save`, and reused on retry (§6.4). |
| I5 | **Every number shown comes from the local store.** This covers the app, widgets, complications and Siri dialogs. | HealthKit is written, not read, for totals. It is never added to store totals, so nothing is counted twice. It also works while the device is locked. |
| I6 | **Replication converges regardless of message loss, duplication or reordering.** | Records are merged as whole states: last-writer-wins, and a delete always wins, keyed by ID. Periodic digests repair any gaps (§7). |
| I7 | **Nothing is silently pending.** | Pending HealthKit writes and entries the peer has not acknowledged appear in the UI and in the widget attention badge. They are retried with backoff and flushed by *every* process that touches the store. |
| I8 | **Only the apps request permissions or use WatchConnectivity.** Extensions touch only the store and HealthKit. | The compile condition `SAYONE_APP` gates `requestAuthorization`. `Shared/Sync` is compiled into the two apps only. |

---

## 1. Deployment targets and toolchain

| Item | Value | Why |
|---|---|---|
| iOS app + iOS widget extension | **iOS 18.0** | Controls, `ControlCenter` and `promptsForUserConfiguration()` then need no `#available`. Button(intent:) is interactive on this target. |
| watch app + watch widget extension | **watchOS 11.0** | Watch widgets and complications are interactive only from watchOS 11. `AccessoryWidgetGroup` and `.handGestureShortcut` are then usable without guards. |
| watchOS 26-only features | gated with `if #available(watchOS 26.0, *)` (plus `#if compiler(>=6.2)` for control types) | Watch controls. `recommendations()` returns `[]` so each complication instance can be configured separately. `ControlCenter` reloads. |
| `HydrationCore` package | `swift-tools-version: 5.9`, platforms `.iOS(.v17), .watchOS(.v10), .macOS(.v14)` | Stays in Swift 5 mode. The package minimums are at or below the app targets. Builds on the Linux Swift 6.4 toolchain. |
| Language mode | `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`, no `SWIFT_DEFAULT_ACTOR_ISOLATION` | Avoids Swift 6 strict-concurrency errors. |
| Xcode | 26.x (CI: `macos-26` default, currently 26.6 with SDK 26.5). A non-blocking `xcode-27` job also runs. | Fixed constraint. No iOS/watchOS 27-only API is used. |

Devices older than Apple Watch Series 6 / SE 2 cannot run watchOS 11. If the user's watch turns out to be one of them, lower the watch target to 10.0 in `project.yml`. The code still compiles, because every watchOS 11 API sits behind a single helper, `WatchFeatures`, that can be switched to `#available`. On watchOS 10, taps open the app's confirm screen instead of logging directly.

---

## 2. Xcode targets, bundle IDs, capabilities

| Target | Type / platform | Bundle ID | Embedded in |
|---|---|---|---|
| `SayoneHealth` | application / iOS | `$(BUNDLE_ID_PREFIX)` = `com.sayoneone.sayonehealth` | – |
| `SayoneHealthWidgets` | app-extension / iOS | `$(BUNDLE_ID_PREFIX).widgets` | iOS app → *Embed Foundation Extensions* |
| `SayoneHealthWatch` | application / watchOS (single-target watch app, **not** `watchapp2`) | `$(BUNDLE_ID_PREFIX).watchkitapp` | iOS app → *Embed Watch Content* (`$(CONTENTS_FOLDER_PATH)/Watch`) |
| `SayoneHealthWatchWidgets` | app-extension / watchOS | `$(BUNDLE_ID_PREFIX).watchkitapp.widgets` | watch app → *Embed Foundation Extensions* |
| `SayoneHealthAppleTests` (P1) | bundle.unit-test / iOS, no host app | – | – |

**Entitlements, identical on all four product targets:** `com.apple.developer.healthkit = true`, `com.apple.developer.healthkit.access = []`, `com.apple.security.application-groups = [$(APP_GROUP_ID)]` (`group.com.sayoneone.sayonehealth`). There is **no** Siri, Push, iCloud or Associated Domains entitlement, so everything signs on a free Personal Team.

**Info.plist** is written by the XcodeGen `info:` blocks and committed.
- All four targets: `CFBundleShortVersionString = $(MARKETING_VERSION)`, `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`, `SHAppGroupIdentifier = $(APP_GROUP_ID)`, `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`. The widget extensions include the Health strings too, based on forum evidence.
- iOS app adds: `CFBundleDisplayName = SayoneHealth`, `UILaunchScreen = {}`, `UISupportedInterfaceOrientations = [Portrait]`, `LSRequiresIPhoneOS`, `CFBundleURLTypes` (scheme `sayonehealth`), and `INAlternativeAppNames` = [Sayone, Сейон, Сэйон Хелс].
- Watch app adds: `WKApplication = true`, `WKCompanionAppBundleIdentifier = $(BUNDLE_ID_PREFIX)`, `WKRunsIndependentlyOfCompanionApp = true`, `CFBundleURLTypes`, and the same `INAlternativeAppNames`.
- Widget plists add only `NSExtension → NSExtensionPointIdentifier = com.apple.widgetkit-extension`. `NSExtension` must never appear in an app plist.
- No `UIBackgroundModes` are needed.

**`Config/Base.xcconfig`:** `BUNDLE_ID_PREFIX`, `APP_GROUP_ID`, `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`, `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM =`, then `#include? "Local.xcconfig"`. `Local.xcconfig` is git-ignored, so the user's team ID and an optional prefix override never get committed. Changing the prefix means changing `BUNDLE_ID_PREFIX` and `APP_GROUP_ID` together.

**Compile conditions:** the two apps get `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) SAYONE_APP`. The two widget extensions get `$(inherited) SAYONE_WIDGET`.

---

## 3. Module boundaries

Code is placed in one of three layers:

1. **`Packages/HydrationCore`** holds pure logic and imports only Foundation. It builds and tests on Linux and contains every decision that can be expressed as data: the model, catalog, merge, store (behind a storage protocol), HealthKit *planning*, peer-sync *planning*, aggregation, deep links and the JSON/WatchConnectivity codecs. It has no localized strings; display names come from an injected `DrinkNaming`.
2. **`Shared/*` folders** hold Apple-framework adapters. They are compiled directly into the targets listed below through XcodeGen `sources`, not as frameworks or packages. App Intents code stays out of the package so that metadata extraction keeps working.
3. **Per-target folders** hold only the entry points and target-specific UI.

| Folder | iOS app | iOS widgets | watch app | watch widgets | Contents |
|---|:-:|:-:|:-:|:-:|---|
| `Packages/HydrationCore` (linked, static) | ✓ | ✓ | ✓ | ✓ | model, merge, store, planners, aggregation, codecs |
| `Shared/Platform` | ✓ | ✓ | ✓ | ✓ | App Group paths, `CoordinatedFileBackend`, `StoreProvider`, `ChangeNotifier`, `SurfaceRefresher`, `LocalizedDrinkNaming`, formatting |
| `Shared/Health` | ✓ | ✓ | ✓ | ✓ | HealthKit type table, sample factory, `HealthKitMirror` executor. `HealthAuthorization` is compiled only under `#if SAYONE_APP`. |
| `Shared/Intents` | ✓ | ✓ | ✓ | ✓ | `DrinkPresetEntity`/`DrinkEntity` + queries, `QuickLogIntent`, `UndoEntryIntent`, `SelectPresetIntent`, `SelectTrioIntent`, `LogPipeline` |
| `Shared/WidgetKit` | – | ✓ | – | ✓ | widgets, providers, views (per-family `#if os`), controls |
| `Shared/Sync` | ✓ | – | ✓ | – | `WatchSyncService` (WCSession adapter) |
| `Shared/Siri` | ✓ | – | ✓ | – | Siri intents, `SayoneShortcuts` (AppShortcutsProvider), `AppShortcuts.xcstrings` |
| `Shared/UI` | ✓ | – | ✓ | – | cross-platform SwiftUI pieces: progress ring, drink icon, entry row, health status glyph |
| `Shared/Resources` | ✓ | ✓ | ✓ | ✓ | `Localizable.xcstrings`, `InfoPlist.xcstrings` |
| `App/`, `Watch/`, `Widgets/iOS/`, `Widgets/Watch/` | own | own | own | own | `@main` entry points, screens, bundles, assets |

Dependency direction is one way: per-target code → `Shared/*` → `HydrationCore`. `Shared/Platform` and `Shared/Health` never import `Shared/Intents` or `Shared/Sync`.

---

## 4. Core data model (`HydrationCore`)

### 4.1 Drinks and nutrition
- `DrinkKind` is a replicated record: `id`, a built-in flag, a localization key or custom name, an SF Symbol, a tint, a default volume and a `NutrientProfile` per 100 ml. The profile holds `hydrationFactor` (0…1), `caffeineMGPer100ML`, `energyKcalPer100ML` and `sugarGPer100ML`.
- `Nutrients` holds the amounts for one entry: `waterML = volume × hydrationFactor`, plus caffeine mg, kcal and sugar g.

**Built-in catalog.** IDs are stable and seeded identically on both devices. Values are approximate label data, editable in the app, and labelled as approximate. The app makes no medical claims.

| DrinkID | ru / en name | symbol | default ml | hydration | caffeine mg/100 | kcal/100 | sugar g/100 |
|---|---|---|---|---|---|---|---|
| `water` | Вода / Water | drop.fill | 250 | 1.0 | 0 | 0 | 0 |
| `sparkling-water` | Газированная вода / Sparkling water | bubbles.and.sparkles.fill | 330 | 1.0 | 0 | 0 | 0 |
| `cola-zero` | Кола без сахара / Coke Zero | takeoutbag.and.cup.and.straw.fill | 330 | 1.0 | 9.6 | 0.2 | 0 |
| `coffee` | Кофе / Coffee | cup.and.saucer.fill | 200 | 1.0 | 40 | 2 | 0 |
| `tea` | Чай / Tea | mug.fill | 250 | 1.0 | 20 | 1 | 0 |
| `juice` | Сок / Juice | wineglass.fill | 200 | 0.9 | 0 | 45 | 8.4 |
| `milk` | Молоко / Milk | cup.and.heat.waves.fill | 200 | 0.9 | 0 | 52 | 4.7 |
| `other` | Другой напиток / Other drink | drop.circle.fill | 250 | 1.0 | 0 | 0 | 0 |
| `d-<uuid>` | user custom ("что-то ещё") | curated symbol list | user | user | user | user | user |

**Default presets.** IDs are stable, which matters because widget and control configurations store preset IDs.
- `water-250`, shown on watch
- `water-500`, shown on watch
- `cola-zero-330`, shown on watch
- `cola-zero-500`
- `coffee-200`, shown on watch
- `tea-250`

A preset title is `customTitle` or else "<localized drink name> · <volume>", for example «Вода · 500 мл».

### 4.2 Entries
`DrinkEntry` holds:
- `id`, `consumedAt`
- `drinkID`, plus `drinkName` and `symbolName` captured at log time (used for custom drinks and the Health FoodType)
- `volumeML`, and a `profile` snapshot, so later edits to a drink never rewrite history
- `presetID?`, `source: LogSource`, `owner: DeviceKind`, `meta: RecordMeta`

`nutrients` is computed from these fields, not stored.

### 4.3 Replication metadata
`RecordMeta` holds `revision: Int`, `modifiedAt: Date`, `modifiedBy: DeviceKind` and `deletedAt: Date?`.

The merge rule is a pure function in `Merge.winner`:
1. A tombstone beats any live version. Deletion is terminal, and re-logging creates a new ID.
2. Otherwise the larger tuple `(revision, modifiedAt, modifiedBy == .phone)` wins.
3. On an exact tie the local copy is kept.

Seeded records use revision 0 and `distantPast`. Shadow entries imported from HealthKit (P1) use revision 0 and are never sent to the peer.

### 4.4 Settings
`HydrationSettings` is replicated as one last-writer-wins register inside the catalog:
- `dailyGoalML` (default 2000)
- `writeExtraNutrients` (default true: caffeine, energy and sugar go to Health too)
- `siriWaterPresetID` (default `water-250`)
- `undoWindowSeconds` (default 300)

**Single writer.** The catalog (drinks, presets, settings) is edited only on the iPhone. The watch holds a read-only replica, plus the seeded defaults while the phone has never synced. This removes catalog conflicts entirely.

### 4.5 Persistence rules
- JSON via one `JSONCoding.encoder` (`.sortedKeys`, `.millisecondsSince1970`). The store clock rounds `now` to whole milliseconds, so dates survive a round trip bit-for-bit.
- Every persisted dictionary is keyed by `String`. The ID types are `String` typealiases, so no Codable dictionary ever turns into an array.
- Every file carries `schema: Int`. A reader never overwrites a file with a newer schema; it reports "update the other device".
- Enums that are persisted or synced and may grow (`LogSource`, `DrinkTint`, `HealthFailure`) implement `init(from:)` explicitly and decode unknown raw values to `.unknown`. An older watch therefore never fails to decode a newer phone's data.
- Fingerprints use FNV-1a 64 over sorted-key JSON, never `hashValue`, because `Hasher` is randomised per process.

---

## 5. Storage and data flow

### 5.1 Files
All files live in `<App Group container>/Library/Application Support/SayoneHealth/v1/`, one set per device.

| File | Content | Replicated | Written by |
|---|---|---|---|
| `catalog.json` | `CatalogDocument` (drinks, presets, settings) | phone → watch | iPhone app; watch app only through `applyRemote` |
| `entries-YYYY-MM.json` | `EntryShard`: entries and tombstones, sharded by UTC month of `consumedAt` | both ways | all four processes |
| `health-mirror.json` | `[EntryID: HealthMirrorRecord]`: device-local HealthKit progress | no | all four |
| `health-lease.json` | single-flusher lease (`holder`, `expiresAt`) | no | all four |
| `peer-sync.json` | `PeerSyncState`: acks, queued revisions, peer digest | no | apps |
| `diagnostics.json` | ring buffer of the last 300 `DiagnosticEvent`s | no | all four |

The entries file is the source of truth. The HealthKit mirror and peer-sync files are **progress caches**: deleting them causes only idempotent re-work (HealthKit re-saves are deduplicated by sync ID, and re-sent entries are merged by ID). This makes crash recovery trivial.

Month shards keep what the widget extension decodes small: at most two shards, about 100 KB, even after a year of use.

### 5.2 Cross-process coordination
The App Group is shared by the app and its widget extension, and on iOS also by Siri running in the background.
- `CoordinatedFileBackend.update(name, transform)` performs a read-modify-write inside one `NSFileCoordinator.coordinate(writingItemAt:options:error:byAccessor:)` block. It writes with `.atomic` and `.completeFileProtectionUntilFirstUserAuthentication`.
- An `NSLock` serialises callers within one process.
- The `transform` closure is pure and must never call back into the store, so there is no nesting and no deadlock.
- No file presenters are used, and no lock is held across `await`, so there is no 0xdead10cc risk.
- An edit that moves an entry across months writes the new shard first and then removes the entry from the old one. Readers deduplicate by ID, keeping the highest revision.

**Change signal.** Every writer posts the Darwin notification `com.sayoneone.sayonehealth.store-changed` (`CFNotificationCenterGetDarwinNotifyCenter`). An app in the foreground reloads its view model and pushes to the peer. As a backstop, apps also reload on `scenePhase == .active`.

**No App Group (signing hiccup).** If `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil, `StoreProvider` falls back to the process's own Application Support folder and records a diagnostic. The app shows «Виджеты не видят данные: App Group недоступна». Logging still works.

### 5.3 Write path: one tap on a watch complication (watchOS 11+)
```
QuickLogIntent.perform()  [watch widget-extension process]
 └ LogPipeline.log(LogRequest(.preset(id, fallback: drinkID+volume), source: .watchWidget))
    1. store.log(...)                       → entries-2026-09.json (coordinated, atomic)       [I1]
    2. HealthKitMirror.flush(.afterLog, 4s) → take lease → plan → persist inFlight version →
                                              HKHealthStore.save([samples]) → mark written       [I3, I4]
       (failure ⇒ record stays pending with reason + nextAttemptAt; the tap is never lost)
    3. ChangeNotifier.post()                → watch app, if alive, pushes to phone via WC
    4. SurfaceRefresher.reloadAll()         → WidgetCenter.reloadAllTimelines (+ ControlCenter on 26)
    5. return .result()                     → WidgetKit reloads this widget; the total comes from the store [I5]
later: watch app (active / WC wake / app refresh) → WatchSyncService.syncNow → phone merges by ID
```
Taps on iPhone widgets, iPhone controls and Siri (on either device) go through the same `LogPipeline`. Only `source` and `owner` differ.

### 5.4 Read path
- Widget timelines, Siri dialogs and app screens call `store.daySummary(for:)`, which is a pure `Aggregator` over live entries of the local day. Only the store is read, never HealthKit.
- Timelines add an entry when the undo window ends and another at local midnight, with policy `.atEnd`.

### 5.5 Compaction
Compaction runs only in the apps, on launch, at most once a day.
- Tombstones older than 30 days are purged once the peer has acknowledged them (or no peer exists) and their HealthKit state is settled.
- The watch drops shards older than 3 months once every entry in them is acknowledged and settled.
- The iPhone keeps full history.

---

## 6. HealthKit strategy

### 6.1 Types and units
The table below is the only place units are defined. A unit mismatch raises an Objective-C exception that Swift cannot catch.

| `HealthMetric` | HK type | unit | written when |
|---|---|---|---|
| `.water` | `HKQuantityType(.dietaryWater)` | `.literUnit(with: .milli)` | `waterML ≥ 1` (always for a normal drink) |
| `.caffeine` | `.dietaryCaffeine` | `.gramUnit(with: .milli)` | `writeExtraNutrients` and `≥ 0.5 mg` |
| `.energy` | `.dietaryEnergyConsumed` | `.kilocalorie()` | same, `≥ 0.5 kcal` |
| `.sugar` | `.dietarySugar` | `.gram()` | same, `≥ 0.1 g` |

- Share and read sets contain these four types only. **No `HKCorrelationType`**, because it causes an uncatchable exception in `requestAuthorization`.
- Samples are flat `HKQuantitySample`s with `start == end == consumedAt`.

### 6.2 Metadata on every sample
Values are only `NSString` or `NSNumber`, and custom keys never start with "HK".
- `HKMetadataKeySyncIdentifier = "sayone.<entryID>.<metric>"`
- `HKMetadataKeySyncVersion = NSNumber(version)`
- `HKMetadataKeyFoodType = <localized drink name>`, for example «Кола без сахара»
- `HKMetadataKeyWasUserEntered = NSNumber(true)`
- Custom: `SayoneEntryID`, `SayoneDrinkID`, `SayoneOrigin` (`phone`/`watch`), `SayoneVolumeML` (beverage volume), `SayoneSchema = 1`

### 6.3 Ownership
- `owner` is the device that handled the tap. A watch complication, watch app, watch Siri or watch control gives `.watch`.
- An iPhone widget, iPhone app, iPhone Siri or iPhone control gives `.phone`. This includes the iPhone control when it is run from the watch Control Center on watchOS 26, because it executes on the iPhone.
- Only the owner's processes run HealthKit operations for an entry. The other device only replicates the record.

### 6.4 Idempotent mirroring (planner + executor)
`HealthPlanner.plan(...)` is pure and tested on Linux. For each entry this device owns, it compares the entry's fingerprint (content plus the metric set to write, i.e. the entry's metrics ∩ authorized types ∩ settings) with the mirror record:

| State | Operation |
|---|---|
| live, `writtenFingerprint == fp` | nothing |
| live, `inFlightFingerprint == fp` (a crashed or failed attempt) | `write(version: inFlightVersion)`: **same version**, so HealthKit ignores a duplicate |
| live, anything else (new entry, edit, newly authorized metric) | `write(version: max(written, inFlight) + 1)`: a higher version **replaces** the samples, so an edit needs no delete |
| tombstone, never attempted | `forget`: mark settled with no HealthKit call |
| tombstone, attempted or written, not yet deleted | `delete` |
| `nextAttemptAt > now` and not forced | skipped (backoff 15 s, 1 min, 5 min, 30 min, 1 h, then 6 h) |

`HealthKitMirror.flush` is the executor in `Shared/Health`.
1. **Lease.** It takes `health-lease.json` (30 s, renewed per operation) through a coordinated update. If another process holds the lease it returns `skippedLease`, and the holder will pick up the new entry. This stops a delete racing a save in two processes.
2. **Write-ahead.** It persists `inFlightVersion` and `inFlightFingerprint`, then calls `try await store.save(samples)`. The call is all-or-nothing, so samples are pre-filtered by `authorizationStatus(for:) == .sharingAuthorized`. Water must be authorized, otherwise the entry stays pending with `.notDetermined` or `.denied`.
3. **Success.** It records `written = (version, fp)` and clears the in-flight fields.
4. **Error mapping.**
   - `errorAuthorizationNotDetermined` → `.notDetermined`; `errorAuthorizationDenied` → `.denied`. Neither counts toward backoff; both are retried when authorization changes.
   - `errorDatabaseInaccessible` → `.locked`, retried on the next active or unlock.
   - `errorHealthDataUnavailable` → `.unavailable`.
   - `errorInvalidArgument` → **verify**: an `HKSampleQueryDescriptor` finds the water sample by `HKMetadataKeySyncIdentifier`. If it exists with version ≥ the attempted one, the entry is written. This covers an equal-version re-save being reported as an error.
   - Anything else → `.transient` with backoff.
5. **Re-plan.** After every operation it plans again, until nothing is left or the deadline passes. The deadline is 4 s in an extension, 20 s in the foreground app and 15 s in a background task.

**Who flushes.** Every process that touches the store:
- after each log, in any process
- app launch and `scenePhase == .active`
- after a Health authorization prompt
- after merging remote tombstones
- watch `.backgroundTask(.appRefresh)` and `.watchConnectivity`
- the «Повторить» button

### 6.5 Undo, delete, edit
- **Undo or delete** sets a tombstone (revision + 1). The owner deletes with `deleteObjects(of: type, predicate: HKQuery.predicateForObjects(withMetadataKey: "SayoneEntryID", allowedValues: [id]))` for each authorized type. A result of 0 counts as success.
- It then **verifies** with a sample query on the same predicate. If the samples are still present, it retries from the other process kind (app versus extension). If that fails too, the entry is marked `deleteBlocked` and the UI says «Удалите запись вручную в приложении Здоровье».
- The non-owner's tombstone reaches the owner through WatchConnectivity (§7), and the owner then deletes. While that is pending, the phone shows «⌚︎ удалится на часах».
- **Edit** (volume or time only; changing the drink means delete plus re-log) bumps the revision. The owner re-saves with version + 1 and HealthKit replaces the samples.

### 6.6 Locked device
- HealthKit *writes* while locked are journaled by HealthKit. App Group files use `completeUntilFirstUserAuthentication`, so Siri and Controls can log on a locked iPhone (`authenticationPolicy` stays at its default `.alwaysAllowed`), and the Siri dialog total comes from the store.
- Lock Screen widget buttons act only after unlock; that is system behaviour.
- **Before first unlock after a reboot**, the store is unreadable. `LogPipeline` throws `StoreError.protectedDataUnavailable`, and Siri or the control reports «Разблокируйте устройство и повторите». The failure is visible, never silent.

### 6.7 Authorization
- Only the foreground apps call `HealthAuthorization.request()` (`#if SAYONE_APP`), during onboarding and from the Health status row. Watch and iPhone permissions are separate, and both onboarding flows state this.
- Extensions and intents check `authorizationStatus(for:)` only. When the status is `.notDetermined` the entry stays pending and the widget shows the «!» attention badge that deep-links to onboarding.
- `handleAuthorizationForExtension`, `healthDataAccessRequest` (HealthKitUI) and iOS 27-only APIs are never used.

### 6.8 (P1) Health reconciliation import
This gives a second route to convergence when WatchConnectivity is idle, for example when the watch app is never opened after complication taps. The apps query water samples from the last 48 h that have the `SayoneEntryID` key.
- An ID that is not in the store becomes a **shadow entry**: revision 0, `source .healthImport`, `owner` from `SayoneOrigin`, never sent to the peer and never mirrored.
- The real record replaces the shadow when it arrives by merge.
- A shadow whose sample has disappeared, confirmed by a successful query, is removed.
- It requires read permission and is not required for tomorrow's build.

---

## 7. Watch ↔ phone sync (WatchConnectivity)

The WatchConnectivity API used here is not in the research digest. I checked the declarations against Apple's docs JSON:
- `WCSession.default` / `activate()` / `isReachable` / `activationState` / `hasContentPending`
- `transferUserInfo(_:) -> WCSessionUserInfoTransfer` (queued, FIFO, continues after suspend)
- `updateApplicationContext(_:) throws` (latest state wins)
- `sendMessage(_:replyHandler:errorHandler:)`. Sent from the watch app, this **wakes the iOS app in the background**; sent from iOS it does not wake the watch.
- Delegate methods: `session(_:activationDidCompleteWith:error:)`, the iOS-only `sessionDidBecomeInactive` and `sessionDidDeactivate`, `session(_:didReceiveUserInfo:)`, `session(_:didReceiveApplicationContext:)`, `session(_:didReceiveMessage:replyHandler:)`
- iOS-only `isPaired` and `isWatchAppInstalled`; watchOS-only `isCompanionAppInstalled`
- SwiftUI `.backgroundTask(.watchConnectivity)` (watchOS 9) and `.backgroundTask(.appRefresh)` (watchOS 9), with `WKApplication.scheduleBackgroundRefresh(withPreferredDate:userInfo:scheduledCompletion:)` (watchOS 7)

### 7.1 Envelope
Every payload is `["env": Data]`, where `Data` is the JSON of `SyncEnvelope { schema, sender, sentAt, body }`.

| `SyncBody` | Direction | Channel | Purpose |
|---|---|---|---|
| `.entries([DrinkEntry])` | both | `sendMessage` when reachable (reply = `.ack`), otherwise `transferUserInfo` | upserts and tombstones, at most 100 per message |
| `.context(catalog: CatalogDocument?, digest: SyncDigest)` | phone → watch with catalog, watch → phone with `catalog: nil` | `updateApplicationContext` | catalog replica plus anti-entropy digest; the digest doubles as a batch acknowledgement |
| `.hello(digest:)` | watch → phone | `sendMessage` (wakes the iPhone app) | on watch activation: "here is what I have". The reply is an `.entries` envelope with what the watch lacks, including taps from iPhone widgets. |
| `.ack([EntryID: Int])` | both | message reply | lets the sender mark acknowledged revisions |

`SyncDigest` contains:
- `windowStart` (14 days)
- `revisions: [EntryID: Int]`, tombstones included
- `catalogFingerprint`
- `healthPending: [EntryID]`: the owner's entries not yet in Health, so the other side can show «ждёт записи в Здоровье на часах»

### 7.2 Algorithms
All of these are pure and live in `PeerSyncPlanner`.
- **Outbound**: entries in the window with `revision > ackedRevisions[id]`, excluding revision-0 shadows. An entry already queued at the same revision is skipped unless `outstandingUserInfoTransfers` is empty and 10 minutes have passed.
- **Inbound entries**: `store.applyRemote(entries:)` merges by ID (§4.3). If anything changed: flush HealthKit (owned tombstones), `SurfaceRefresher.reloadAll()`, refresh the UI, and reply with an ack.
- **Inbound digest**: mark acknowledged every ID where `peer.revision ≥ local.revision`, then push any entry where `local.revision > peer.revision` or the peer lacks the ID. Anything a lost message dropped is therefore repaired on the next context exchange.
- **Inbound catalog** (watch only): `applyRemote(catalog:)`. If it changed: `WidgetCenter.shared.invalidateConfigurationRecommendations()`, `SayoneShortcuts.updateAppShortcutParameters()`, reload widgets.

### 7.3 Triggers
**iPhone app**
- `WatchSyncService.shared.activate()` in `App.init`, so a background launch for WatchConnectivity or Siri still has a delegate.
- `.active` → `syncNow(.becameActive)`.
- In-process store change, or a Darwin notification from the widget extension while the app is alive → debounced `syncNow(.localChange)` (1 s).
- Handles inactive/deactivate by calling `activate()` again, for multi-watch support.

**Watch app**
- Same activation in `App.init`.
- `.active` → `hello` plus push.
- `.backgroundTask(.watchConnectivity)` → drain while `hasContentPending`, up to 20 s, then flush HealthKit and reload complications.
- `.backgroundTask(.appRefresh)` → flush HealthKit, push, and reschedule for about 30 min ahead. Apps with a complication on the active face get a larger refresh budget.

**Widget extensions** never use WatchConnectivity (I8). Their entries leave the device the next time the app runs. Until then, the other device learns about them through the digest, or through the P1 HealthKit import.

### 7.4 Guarantees and edge cases
- Duplicate, late or reordered messages cannot double-count, because merging is idempotent and delete wins.
- Totals converge because both devices end up with the same set of entries, and the total is a pure function of that set.
- **Standalone watch (no iPhone nearby):** everything works locally, and sync resumes later.
- **Watch app deleted:** the phone keeps watch-owned tombstones pending. After 24 h it shows the manual-delete hint.
- **Payload size:** messages are capped at 100 entries (about 35 KB). The `sendMessage` size limit of about 64 KB is from memory.

---

## 8. iPhone widgets

Both widgets use `AppIntentConfiguration`, and every root view has `.containerBackground(for: .widget)`. Totals carry `.invalidatableContent()`, and icons and progress carry `.widgetAccentable()`.

| Widget (kind) | Config intent | Families | Content |
|---|---|---|---|
| **Quick Log** (`QuickLog`) | `SelectPresetIntent` (`preset: DrinkPresetEntity?`) | `.systemSmall`, `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline` | Small: drink icon, preset title, a big «+500 мл» `Button(intent: QuickLogIntent)`, today's bar, and «Отменить» (`UndoEntryIntent`) for 5 min after a log. Circular: capacity gauge with the button. Rectangular: title, total/goal, button. Inline: «💧 1,2 из 2 л» (not interactive). |
| **Three Drinks** (`Trio`) | `SelectTrioIntent` (`first/second/third: DrinkPresetEntity?`) | `.systemMedium` | Progress ring, three preset buttons, undo chip, pending/permission badge. |

- Configuration uses *Edit Widget*, and `.promptsForUserConfiguration()` runs on add (inside `#if os(iOS)`).
- The button intents carry a complete payload (`presetID`, `drinkID`, `volumeML`), so a tap never depends on parameter resolution. If the preset has since been deleted, the tap still logs exactly what the button showed.
- `widgetURL(sayonehealth://confirm?preset=ID)` covers taps outside the button. It opens a confirm sheet and never logs automatically.
- Lock Screen buttons work only after unlock (system rule); the test plan says so.

---

## 9. Watch complications and Smart Stack

These widgets share code with §8. The families come from a computed `families` property with `#if os(watchOS)`, and every `switch family` has a `default:` branch.

| Widget | Family | Layout (tidy by design: one idea per slot) |
|---|---|---|
| Quick Log | `.accessoryCircular` | The whole view is `Button(intent: QuickLogIntent)`. Inside: `Gauge(.accessoryCircularCapacity)` for today/goal, a drop icon and «500». |
| Quick Log | `.accessoryCorner` | Button with the drop icon, and `.widgetLabel { Gauge(...) }` showing progress. |
| Quick Log | `.accessoryRectangular` (Smart Stack) | Left: preset title, «1,2 / 2 л», a linear gauge and the last-log time. Right: a round «+» button with `.handGestureShortcut(.primaryAction)`, so a double tap logs. Shows «!» when Health permission is missing on the watch. |
| Quick Log | `.accessoryInline` | «💧 1,2 / 2 л». Opens the app. |
| Three Drinks | `.accessoryRectangular` | `AccessoryWidgetGroup("1,2 / 2 л", systemImage: "drop.fill") { three Button(intent:) }` with `.accessoryWidgetGroupStyle(.circular)`. |

**Per-instance configuration**
- `recommendations()` is always implemented, because watchOS has no default.
- watchOS 11 to 25: it returns one `AppIntentRecommendation(intent: SelectPresetIntent(preset:), description: title)` per watch-visible preset, at most 12, using a plain `String` description. Trio gets «Избранное» (the first three) plus «Вода 250/500/750».
- watchOS 26 and later: it returns `[]`, and the user picks a preset per complication in the face editor. The entity query reads the watch's App Group; seeded defaults exist even before the phone has synced.

**Hit targets.** No `AccessoryWidgetBackground()` inside a `.plain`-styled button label (FB15151000); use `Color.primary.opacity(0.15)`.

**Fallback.** `widgetURL(sayonehealth://confirm?preset=ID)` opens `ConfirmLogView` for missed hits, or when the watch-face complication launches the app instead of running the intent.

---

## 10. Controls

- **`QuickLogControl`** lives in `Shared/WidgetKit/QuickLogControl.swift`. It is compiled into both widget extensions, annotated `@available(iOS 18.0, watchOS 26.0, *)`, and the file is wrapped in `#if os(iOS) || compiler(>=6.2)`.
- It uses `AppIntentControlConfiguration(kind: "com.sayoneone.sayonehealth.QuickLogControl", intent: SelectPresetControlIntent.self)`.
- The builder closure contains only `let` statements followed by **one** `ControlWidgetButton(action: QuickLogIntent(...)) { Label(title, systemImage: symbol) }`, then `.displayName`, `.description` and `.promptsForUserConfiguration()`.
- `SelectPresetControlIntent: ControlConfigurationIntent` has an optional `preset` and falls back to `water-500`.
- **iOS 18:** available in Control Center, the Lock Screen and the Action button. It runs while the phone is locked, and it also appears on watchOS 26 automatically, running on the iPhone (it never opens the app).
- **watchOS 26:** the bundle has `if #available(watchOS 26.0, *) { QuickLogControl() }`. It is available in watch Control Center, the Smart Stack and the Ultra Action button, and runs on the watch.
- After any log, `SurfaceRefresher` calls `ControlCenter.shared.reloadAllControls()`. This is unguarded on iOS 18 and inside `if #available(watchOS 26.0, *)` on the watch.

---

## 11. App Intents and Siri

### 11.1 Intents

| Type | Targets | Discoverable | Parameters | Result |
|---|---|---|---|---|
| `QuickLogIntent` | all 4 | no | `presetID: String` (default `"water-500"`), `drinkID: String` (default `"water"`), `volumeML: Int` (default 500), `surface: String` (default `"widget"`) | `.result()` |
| `UndoEntryIntent` | all 4 | no | `entryID: String` (default `""` = the last entry within the undo window) | `.result()` |
| `SelectPresetIntent`, `SelectTrioIntent` | all 4 | – | `DrinkPresetEntity?` ×1 or ×3 | widget configuration |
| `LogPresetIntent` | apps | yes | `preset: DrinkPresetEntity` | `ProvidesDialog` «Записал: Вода · 500 мл. Сегодня 1,2 из 2 л.» |
| `LogDrinkIntent` | apps | yes | `drink: DrinkEntity` (built-in and custom drinks), `amountML: Int?` with `inclusiveRange: (10, 3000)`; nil means the drink's default volume, so «Запиши колу» logs 330 ml without a follow-up question | dialog |
| `LogWaterIntent` | apps | yes | none; logs `settings.siriWaterPresetID` | dialog |
| `TodayTotalIntent` | apps | yes | none | `ReturnsValue<Int> & ProvidesDialog`, read from the store, so it works while locked |
| `UndoLastDrinkIntent` | apps | yes | none | dialog |

Rules:
- No `openAppWhenRun`, `supportedModes`, `ForegroundContinuableIntent`, `LiveActivityIntent` or `allowedExecutionTargets`.
- `static let` metadata throughout, and `TypeDisplayRepresentation(name:)` written out explicitly.
- Query type names are unique: `DrinkPresetQuery`, `DrinkEntityQuery` (both `EntityStringQuery` with `suggestedEntities()` and `defaultResult()`).
- `SayoneShortcuts` (AppShortcutsProvider) and `AppShortcuts.xcstrings` are compiled into the **iOS app and watch app only**, so Siri works on the watch and runs in the watch app process with the watch's Health permission.
- `updateAppShortcutParameters()` is called in `App.init` on both apps and after every catalog change.
- No SiriKit entitlement and no `NSSiriUsageDescription`.

### 11.2 App Shortcuts: 5 of the 10 allowed
The key is the first English phrase. Every phrase contains `${applicationName}` exactly once, which CI lints.

| Intent | English phrases | Russian phrases (`ru` stringSet) |
|---|---|---|
| LogPreset | Log ${preset} in ${applicationName} · Add ${preset} to ${applicationName} · ${applicationName} ${preset} | Запиши ${preset} в ${applicationName} · Добавь ${preset} в ${applicationName} · ${applicationName} ${preset} · ${preset} в ${applicationName} |
| LogWater | Log water in ${applicationName} · Add water to ${applicationName} · I drank water in ${applicationName} | Запиши воду в ${applicationName} · Добавь воду в ${applicationName} · ${applicationName} вода · Я выпил воды в ${applicationName} · Я выпила воды в ${applicationName} |
| LogDrink | Log ${drink} in ${applicationName} · I drank ${drink} in ${applicationName} · Log a drink in ${applicationName} | Запиши ${drink} в ${applicationName} · Я выпил ${drink} в ${applicationName} · Я выпила ${drink} в ${applicationName} · Запиши напиток в ${applicationName} |
| TodayTotal | How much did I drink today in ${applicationName} · My water today in ${applicationName} | Сколько я выпил сегодня в ${applicationName} · Сколько я выпила сегодня в ${applicationName} · Сколько воды в ${applicationName} · Итог за день в ${applicationName} |
| UndoLast | Undo last drink in ${applicationName} · Delete last drink in ${applicationName} | Отмени последний напиток в ${applicationName} · Удали последнюю запись в ${applicationName} |

- Entity titles are nominative («Кола без сахара»). `DisplayRepresentation(synonyms:)` adds accusative and short forms («колу», «колу без сахара», «воду», «кофе»), which help flexible matching on the iPhone.
- On the watch phrases must match exactly, so the `${applicationName} ${preset}` form is the one to recommend there.
- App name synonyms are in `INAlternativeAppNames` (Sayone / Сейон / Сэйон Хелс), non-localized, in both app plists.
- Intent `perform()` builds the localized sentence with `String(localized:)` and returns `.result(dialog: "\(message)")`.

---

## 12. UI screens

### iPhone (TabView: Сегодня · История · Напитки · Настройки)
1. **Onboarding** (first launch). A welcome screen, then an Apple Health screen that explains the four types and has «Разрешить доступ к Здоровью», then a done screen with how to add the widget and a `SiriTipView(intent: LogWaterIntent())`.
2. **Сегодня.**
   - A status banner, shown only when needed: Health permission missing, N pending writes with «Повторить», or the watch not synced for more than 24 h.
   - A progress ring (water/goal) with small caffeine, kcal and sugar figures.
   - A 2-column preset grid. One tap logs, with `.sensoryFeedback(.success)` and a 5-second toast «✓ Вода · 500 мл — Отменить».
   - «＋ Другое» opens a sheet: drink picker, volume slider and stepper (10 ml steps), time picker.
   - Today's list: time, icon, name, volume, and a Health glyph (✓ saved · ⏳ pending (reason) · ⌚︎ on watch). Swipe deletes; a tap opens the edit sheet for volume and time.
3. **История.** A Swift Charts bar chart for 7 or 30 days with a goal rule line, then a day list with a day detail screen.
4. **Напитки.**
   - Presets: reorder, «На часах» toggle (at most 12), add or edit (drink, volume, optional title), swipe delete.
   - Drinks: built-ins with editable nutrition (for example the user's cola label), and custom drinks with name, symbol from a curated list, colour, hydration %, caffeine/kcal/sugar per 100 ml and default volume.
5. **Настройки.**
   - Daily goal (500–5000 in steps of 250), «Записывать кофеин, калории и сахар», the Siri water preset.
   - Siri: `SiriTipView`s plus `ShortcutsLink` (under `#if os(iOS)`).
   - Apple Health: status per type.
   - Apple Watch: paired, installed, reachable, last sync, unacknowledged count.
   - **Диагностика**: event log, pending lists, «Повторить всё», JSON export through `ShareLink`. This screen is for tomorrow's testing.
6. **ConfirmLogSheet** (deep link). Shows the preset and «Записать». Its `LogRequest.entryID` is created when the sheet appears, so a double tap on «Записать» stays one entry.

### Watch (NavigationStack)
1. **Onboarding.** «Разрешите запись в Здоровье на часах» calls `requestAuthorization`, with an explanation that this permission is separate from the iPhone's.
2. **Главный.** A ring with total/goal, then big preset buttons (the watch-visible presets). A tap logs, gives a haptic through `.sensoryFeedback(.success, trigger:)`, and shows an overlay «✓ +500 мл · Отменить» for 5 s. Below: «Другое…» and «Сегодня».
3. **Другое количество.** A drink picker, then a large number bound to the Digital Crown: `.focusable().digitalCrownRotation($ml, from: 50, through: 2000, by: 10, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)`. It is not inside a List or ScrollView. Plus −/+ buttons and «Записать».
4. **Сегодня.** Entries with swipe-to-delete and the Health glyph.
5. **Статус.** Health permission, pending writes, phone sync status, «Синхронизировать», and a `SiriTipView`.
6. **ConfirmLogView.** The target of the complication `widgetURL`.

---

## 13. Localization

- The development language is English, with a `ru` translation for everything. Language follows the system; there is no in-app switcher.
- `Shared/Resources/Localizable.xcstrings` is in all four targets. It holds UI text, intent titles, parameter titles, dialogs and drink names (`drink.water` → «Вода»), with plural variations for «запись/записи/записей».
- `Shared/Resources/InfoPlist.xcstrings` is in all four targets and holds `CFBundleDisplayName` and the NSHealth strings.
  - ru: «SayoneHealth сохраняет выпитое (воду, кофеин, калории, сахар) в приложение Здоровье.» and «SayoneHealth читает ваши напитки из Здоровья, чтобы сверять записи.»
- `Shared/Siri/AppShortcuts.xcstrings` is in the apps only. It is hand-written as `stringSet` entries (`extractionState: manual`) for `en` and `ru`.
- Volumes are formatted with `Measurement<UnitVolume>`, localized by the system: «500 мл», «1,25 л». The package never formats text.
- `scripts/lint.py` fails CI if any key lacks `ru`, if a phrase breaks the `${applicationName}` rule, or if a catalog is not valid JSON. `ru` must appear in the generated `knownRegions`; the Linux preflight greps for it.

---

## 14. Project generation and CI

### 14.1 `project.yml`
This extends the XcodeGen 2.46.0 spec from the research digest.
```yaml
name: SayoneHealth
options:
  minimumXcodeGenVersion: 2.44.1
  xcodeVersion: "26.0"
  developmentLanguage: en
  deploymentTarget: { iOS: "18.0", watchOS: "11.0" }
  createIntermediateGroups: true
configFiles: { Debug: Config/Base.xcconfig, Release: Config/Base.xcconfig }
settings:
  base: { SWIFT_VERSION: "5.0", SWIFT_STRICT_CONCURRENCY: minimal }
packages:
  HydrationCore: { path: Packages/HydrationCore }
targets:
  SayoneHealth:
    type: application
    platform: iOS
    sources: [App, Shared/Platform, Shared/Health, Shared/Intents, Shared/Sync, Shared/Siri, Shared/UI, Shared/Resources]
    dependencies:
      - package: HydrationCore
      - target: SayoneHealthWidgets        # Embed Foundation Extensions
      - target: SayoneHealthWatch          # Embed Watch Content
    info: { path: App/Info.plist, properties: { ... see §2 ... } }
    entitlements:
      path: App/SayoneHealth.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: ["$(APP_GROUP_ID)"]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX)
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) SAYONE_APP
    scheme: {}
  SayoneHealthWidgets:
    type: app-extension
    platform: iOS
    sources: [Widgets/iOS, Shared/Platform, Shared/Health, Shared/Intents, Shared/WidgetKit, Shared/Resources]
    dependencies: [{ package: HydrationCore }]
    info: { path: Widgets/iOS/Info.plist, properties: { NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }, ... } }
    entitlements: { path: Widgets/iOS/SayoneHealthWidgets.entitlements, properties: { same three keys } }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).widgets, TARGETED_DEVICE_FAMILY: "1", SKIP_INSTALL: YES,
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) SAYONE_WIDGET } }
  SayoneHealthWatch:
    type: application                     # NOT application.watchapp2
    platform: watchOS
    sources: [Watch, Shared/Platform, Shared/Health, Shared/Intents, Shared/Sync, Shared/Siri, Shared/UI, Shared/Resources]
    dependencies: [{ package: HydrationCore }, { target: SayoneHealthWatchWidgets }]
    info: { path: Watch/Info.plist, properties: { WKApplication: true, WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX),
                                                 WKRunsIndependentlyOfCompanionApp: true, ... } }
    entitlements: { path: Watch/SayoneHealthWatch.entitlements, properties: { same three keys } }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp,
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) SAYONE_APP } }
    scheme: {}
  SayoneHealthWatchWidgets:
    type: app-extension
    platform: watchOS
    sources: [Widgets/Watch, Shared/Platform, Shared/Health, Shared/Intents, Shared/WidgetKit, Shared/Resources]
    dependencies: [{ package: HydrationCore }]
    info: { path: Widgets/Watch/Info.plist, properties: { NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }, ... } }
    entitlements: { path: Widgets/Watch/SayoneHealthWatchWidgets.entitlements, properties: { same three keys } }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp.widgets,
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) SAYONE_WIDGET } }
```
- Every source path excludes `**/*.md`.
- `ARCHS` is not hard-coded.
- The generated `SayoneHealth.xcodeproj`, plists and entitlements are **committed**, so the user can open the project tomorrow without XcodeGen. CI regenerates the project and runs `git diff --stat`, which only warns if the result differs.

### 14.2 Linux preflight
This runs as `scripts/preflight.sh` and as the `linux` CI job, and catches most mistakes before a macOS run.
1. `swift test --package-path Packages/HydrationCore`: model, merge, planners, codecs, aggregation.
2. `swiftc -parse $(git ls-files '*.swift' ':!Packages')`: a syntax check of all Apple-only files without an SDK. I checked locally that it also parses inactive `#if os(iOS)` branches and reports errors in them.
3. `scripts/lint.py`, a small scanner that is aware of `#if os(...)` / `#else` / `#endif`:
   - forbids `.systemSmall/.systemMedium`, `ShortcutsLink` and a widget `.promptsForUserConfiguration()` outside iOS branches in `Shared/`
   - forbids `.accessoryCorner`, `AccessoryWidgetGroup`, `digitalCrownRotation`, `WKApplication` and `.handGestureShortcut` outside watchOS branches
   - forbids `LiveActivityIntent`, `handleAuthorizationForExtension`, `openAppWhenRun`, `supportedModes`, `allowedExecutionTargets`, `earliestAuthorizedSampleDate` and `HKCorrelationType` anywhere
   - allows `requestAuthorization(` only inside `#if SAYONE_APP`
   - forbids Siri, aps, iCloud and associated-domains entitlements
   - validates the xcstrings files and phrase tokens (≤ 10 shortcuts)
   - parses every plist and entitlements file with `plistlib`
4. Builds XcodeGen 2.46.0 from source (cached, with `USER=ci`), runs `xcodegen generate`, and greps the pbxproj for:
   - exactly one `Embed Watch Content` phase with `dstSubfolderSpec = 16`
   - two `Embed Foundation Extensions` phases
   - both schemes
   - `ru` in `knownRegions`

### 14.3 `.github/workflows/ci.yml`
The repo is public, so macOS minutes are free. Only standard runner labels are used.
```yaml
name: CI
on: { push: { branches: [main, 'claude/**'] }, pull_request: {}, workflow_dispatch: {} }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  linux:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v5
      - run: swift test --package-path Packages/HydrationCore
      - run: swiftc -parse $(git ls-files '*.swift' ':!Packages')
      - run: python3 scripts/lint.py
      - uses: actions/cache@v4
        with: { path: ~/xcodegen-2.46.0, key: xcodegen-2.46.0-linux }
      - run: USER=ci scripts/preflight-xcodegen.sh     # build (if not cached) + generate + pbxproj greps
  apple:
    runs-on: macos-26
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5
      - run: xcodebuild -version && xcodebuild -showsdks && xcrun simctl list runtimes
      - run: |   # pinned XcodeGen release zip, no brew
          curl -fsSL -o "$RUNNER_TEMP/xg.zip" https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
          unzip -q "$RUNNER_TEMP/xg.zip" -d "$RUNNER_TEMP" && echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
      - run: xcodegen generate && (git diff --stat --exit-code SayoneHealth.xcodeproj || echo "::warning::committed project differs")
      - run: swift test --package-path Packages/HydrationCore
      - name: iOS app + iOS widgets + embedded watch app + watch widgets (Simulator)
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$RUNNER_TEMP/dd" CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee build-ios.log | xcbeautify --renderer github-actions
      - name: Watch scheme (watchOS Simulator)
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealthWatch -destination 'generic/platform=watchOS Simulator' \
            -derivedDataPath "$RUNNER_TEMP/dd" CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee build-watch.log | xcbeautify --renderer github-actions
      - name: App Intents metadata gate
        run: python3 scripts/check_intents_metadata.py build-ios.log build-watch.log "$RUNNER_TEMP/dd"
        # fails on 'appintentsmetadataprocessor' warnings/errors or 'No AppIntents metadata have been exported';
        # asserts both SayoneHealth.app and Watch/SayoneHealthWatch.app extract.actionsdata list the 5 autoShortcuts
      - name: Device build, unsigned (arm64_32 watch slices)
        continue-on-error: true
        run: xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/dd-dev" CODE_SIGNING_ALLOWED=NO
      - if: always()
        uses: actions/upload-artifact@v4
        with: { name: build-logs, path: "*.log" }
  apple-xcode27:
    runs-on: xcode-27
    continue-on-error: true
    steps: [ same generate + iOS-simulator build ]
```
The P1 step `xcodebuild test` on `SayoneHealthAppleTests` covers `CoordinatedFileBackend` and `HealthSampleFactory` unit and metadata checks without HealthKit authorization. It picks the first available iPhone simulator via `simctl` and is non-blocking.

---

## 15. File tree
```
sayonehealth/
├─ project.yml   SayoneHealth.xcodeproj/ (generated, committed)
├─ Config/ Base.xcconfig  Local.xcconfig.example
├─ Packages/HydrationCore/
│  ├─ Package.swift
│  ├─ Sources/HydrationCore/
│  │  ├─ Model/        Identifiers.swift DeviceKind.swift LogSource.swift Nutrients.swift DrinkKind.swift
│  │  │                Preset.swift DrinkEntry.swift HydrationSettings.swift RecordMeta.swift CatalogDocument.swift
│  │  ├─ Catalog/      BuiltInCatalog.swift
│  │  ├─ Merge/        Replicated.swift Merge.swift
│  │  ├─ Store/        StorageBackend.swift InMemoryBackend.swift DirectoryBackend.swift StoreFiles.swift
│  │  │                HydrationStore.swift LogRequest.swift StoreError.swift DrinkNaming.swift
│  │  ├─ Health/       HealthMetric.swift HealthSampleSpec.swift HealthMirrorRecord.swift HealthPlanner.swift RetryPolicy.swift
│  │  ├─ Sync/         SyncEnvelope.swift SyncDigest.swift PeerSyncState.swift PeerSyncPlanner.swift WCPayloadCodec.swift
│  │  ├─ Aggregation/  DaySummary.swift Aggregator.swift
│  │  └─ Support/      JSONCoding.swift StableHash.swift DeepLink.swift DiagnosticEvent.swift
│  └─ Tests/HydrationCoreTests/  MergeTests StoreTests HealthPlannerTests PeerSyncTests AggregatorTests CodecTests DeepLinkTests
├─ Shared/
│  ├─ Platform/   AppEnvironment.swift CoordinatedFileBackend.swift StoreProvider.swift ChangeNotifier.swift
│  │              SurfaceRefresher.swift LocalizedDrinkNaming.swift VolumeFormat.swift PresetPresentation.swift
│  ├─ Health/     HealthTypes.swift HealthSampleFactory.swift HealthKitMirror.swift HealthAuthorization.swift HealthReconciler.swift(P1)
│  ├─ Intents/    DrinkPresetEntity.swift DrinkEntity.swift QuickLogIntent.swift UndoEntryIntent.swift
│  │              WidgetConfigIntents.swift LogPipeline.swift
│  ├─ WidgetKit/  HydrationTimelineProvider.swift QuickLogWidget.swift TrioWidget.swift QuickLogViews.swift
│  │              TrioViews.swift QuickLogControl.swift WidgetAttentionView.swift
│  ├─ Sync/       WatchSyncService.swift
│  ├─ Siri/       SiriIntents.swift SayoneShortcuts.swift AppShortcuts.xcstrings
│  ├─ UI/         ProgressRing.swift DrinkIcon.swift EntryRow.swift HealthGlyph.swift UndoToast.swift
│  └─ Resources/  Localizable.xcstrings InfoPlist.xcstrings
├─ App/          Info.plist SayoneHealth.entitlements Assets.xcassets
│  └─ Sources/   SayoneHealthApp.swift AppModel.swift Today/ History/ Drinks/ Settings/ Onboarding/ ConfirmLogSheet.swift
├─ Watch/        Info.plist SayoneHealthWatch.entitlements Assets.xcassets
│  └─ Sources/   SayoneWatchApp.swift WatchModel.swift MainView.swift CustomAmountView.swift TodayListView.swift
│                StatusView.swift OnboardingView.swift ConfirmLogView.swift
├─ Widgets/iOS/   Info.plist SayoneHealthWidgets.entitlements Sources/SayoneWidgetsBundle.swift
├─ Widgets/Watch/ Info.plist SayoneHealthWatchWidgets.entitlements Sources/SayoneWatchWidgetsBundle.swift
├─ Tests/AppleUnitTests/ (P1)
├─ scripts/  preflight.sh preflight-xcodegen.sh lint.py check_intents_metadata.py make_icons.py
├─ .github/workflows/ ci.yml probe.yml
└─ docs/  design/rubric.md  TESTING.md (ru device checklist)  ARCHITECTURE.md
```
App icons are 1024-px single-size `AppIcon.appiconset`s generated by `scripts/make_icons.py` (pure-Python PNG writer) and committed, because the preset sets `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`.

---

## 16. Shared Swift contracts

These are frozen before any parallel work starts. `HydrationCore` members are `public`. Bodies are elided (`{ … }`).

### 16.1 HydrationCore: model
```swift
import Foundation

public typealias EntryID = String    // lowercase UUID, created once at the tap
public typealias PresetID = String   // "water-500" (built-in) | "p-<uuid>"
public typealias DrinkID = String    // "water", "cola-zero" (built-in) | "d-<uuid>"

public enum IDs {
    public static func newEntryID() -> EntryID
    public static func newPresetID() -> PresetID
    public static func newDrinkID() -> DrinkID
}

public enum DeviceKind: String, Codable, Sendable, CaseIterable { case phone, watch }

public enum LogSource: String, Codable, Sendable, CaseIterable {
    case phoneApp, phoneWidget, phoneControl, phoneSiri
    case watchApp, watchWidget, watchControl, watchSiri
    case healthImport, unknown
    public init(from decoder: Decoder) throws        // unknown raw value -> .unknown
    public var device: DeviceKind? { … }
}

public enum HealthMetric: String, Codable, Sendable, CaseIterable { case water, caffeine, energy, sugar }

public enum DrinkTint: String, Codable, Sendable, CaseIterable {
    case blue, teal, cyan, brown, red, orange, green, purple, gray, unknown
    public init(from decoder: Decoder) throws
}

public struct Nutrients: Codable, Hashable, Sendable {
    public var waterML: Double, caffeineMG: Double, energyKcal: Double, sugarG: Double
    public init(waterML: Double, caffeineMG: Double, energyKcal: Double, sugarG: Double)
    public static let zero: Nutrients
    public func amount(of metric: HealthMetric) -> Double
    public func metricsAboveThreshold() -> Set<HealthMetric>   // thresholds in §6.1
    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients
}

public struct NutrientProfile: Codable, Hashable, Sendable {
    public var hydrationFactor: Double          // 0...1
    public var caffeineMGPer100ML: Double
    public var energyKcalPer100ML: Double
    public var sugarGPer100ML: Double
    public init(hydrationFactor: Double, caffeineMGPer100ML: Double, energyKcalPer100ML: Double, sugarGPer100ML: Double)
    public func nutrients(forVolumeML volumeML: Double) -> Nutrients
}

public struct RecordMeta: Codable, Hashable, Sendable {
    public var revision: Int
    public var modifiedAt: Date
    public var modifiedBy: DeviceKind
    public var deletedAt: Date?
    public var isDeleted: Bool { deletedAt != nil }
    public init(revision: Int, modifiedAt: Date, modifiedBy: DeviceKind, deletedAt: Date? = nil)
    public static let seed: RecordMeta                               // rev 0, .distantPast, .phone
    public func bumped(by device: DeviceKind, at date: Date) -> RecordMeta
    public func tombstoned(by device: DeviceKind, at date: Date) -> RecordMeta
}

public protocol Replicated: Codable, Sendable {
    var id: String { get }
    var meta: RecordMeta { get set }
}

public struct DrinkKind: Replicated, Hashable, Identifiable {
    public var id: DrinkID
    public var isBuiltIn: Bool
    public var nameKey: String?          // "drink.water" for built-ins
    public var customName: String?       // user drinks
    public var symbolName: String
    public var tint: DrinkTint
    public var defaultVolumeML: Double
    public var profile: NutrientProfile
    public var meta: RecordMeta
}

public struct Preset: Replicated, Hashable, Identifiable {
    public var id: PresetID
    public var drinkID: DrinkID
    public var volumeML: Double
    public var customTitle: String?
    public var sortIndex: Int
    public var showOnWatch: Bool
    public var meta: RecordMeta
}

public struct HydrationSettings: Codable, Hashable, Sendable {
    public var dailyGoalML: Double            // 2000
    public var writeExtraNutrients: Bool      // true
    public var siriWaterPresetID: PresetID    // "water-250"
    public var undoWindowSeconds: Double      // 300
    public var meta: RecordMeta
    public static let defaults: HydrationSettings
}

public struct CatalogDocument: Codable, Hashable, Sendable {
    public static let currentSchema = 1
    public var schema: Int
    public var drinks: [DrinkKind]
    public var presets: [Preset]              // tombstones included
    public var settings: HydrationSettings
    public var livePresets: [Preset] { … }    // !deleted, sorted by sortIndex
    public func drink(_ id: DrinkID) -> DrinkKind?
    public func resolve(presetID: PresetID) -> ResolvedPreset?   // nil if unknown; tombstoned presets resolve with isDeleted = true
    public var fingerprint: String { … }      // StableHash of sorted-key JSON
}

public struct ResolvedPreset: Hashable, Sendable {
    public var preset: Preset
    public var drink: DrinkKind
    public var isDeleted: Bool
}

public struct DrinkEntry: Replicated, Hashable, Identifiable {
    public var id: EntryID
    public var consumedAt: Date
    public var drinkID: DrinkID
    public var drinkName: String              // localized at log time
    public var symbolName: String
    public var volumeML: Double
    public var profile: NutrientProfile       // snapshot at log time
    public var presetID: PresetID?
    public var source: LogSource
    public var owner: DeviceKind              // sole HealthKit writer (I3)
    public var meta: RecordMeta
    public var nutrients: Nutrients { profile.nutrients(forVolumeML: volumeML) }
}

public enum BuiltInCatalog {
    public static let drinks: [DrinkKind]
    public static let presets: [Preset]
    public static func seedDocument() -> CatalogDocument    // deterministic, identical on both devices
    public static let fallbackPresetID: PresetID = "water-500"
}
```

### 16.2 HydrationCore: merge, store, requests
```swift
public struct MergeOutcome<T: Replicated>: Sendable {
    public var merged: [T]
    public var changedIDs: Set<String>
}
public enum Merge {
    public static func winner<T: Replicated>(_ local: T, _ remote: T) -> T    // delete-wins, then (rev, modifiedAt, phone>watch), tie -> local
    public static func merge<T: Replicated>(local: [T], remote: [T]) -> MergeOutcome<T>
}

public protocol StorageBackend: AnyObject, Sendable {
    func read(_ name: String) throws -> Data?
    /// Cross-process coordinated read-modify-write. Return nil to leave the file unchanged. `transform` must be pure.
    func update(_ name: String, _ transform: (Data?) throws -> Data?) throws
    func names(withPrefix prefix: String) throws -> [String]
}
public final class InMemoryBackend: StorageBackend, @unchecked Sendable { public init() }
public final class DirectoryBackend: StorageBackend, @unchecked Sendable { public init(directory: URL) }   // Linux tests, fallback

public enum StoreFiles {
    public static let catalog = "catalog.json"
    public static let healthMirror = "health-mirror.json"
    public static let healthLease = "health-lease.json"
    public static let peerSync = "peer-sync.json"
    public static let diagnostics = "diagnostics.json"
    public static func entriesShard(for date: Date) -> String   // "entries-2026-09.json" (UTC month)
}

public enum StoreError: Error, Equatable, Sendable {
    case protectedDataUnavailable            // before first unlock
    case newerSchema(file: String, found: Int)
    case corrupt(file: String)
    case notFound(id: String)
    case invalidVolume(Double)
}

public protocol DrinkNaming: Sendable { func displayName(for drink: DrinkKind) -> String }
public struct RawDrinkNaming: DrinkNaming { public init() }  // customName ?? nameKey ?? id

public struct PresetFallback: Codable, Hashable, Sendable {
    public var drinkID: DrinkID
    public var volumeML: Double
    public init(drinkID: DrinkID, volumeML: Double)
}

public struct LogRequest: Hashable, Sendable {
    public enum What: Hashable, Sendable {
        case preset(PresetID, fallback: PresetFallback?)
        case drink(DrinkID, volumeML: Double?)          // nil volume -> drink.defaultVolumeML
    }
    public var what: What
    public var source: LogSource
    public var consumedAt: Date?                       // nil -> now
    public var entryID: EntryID?                       // idempotency key; existing ID -> returns existing entry
    public init(_ what: What, source: LogSource, consumedAt: Date? = nil, entryID: EntryID? = nil)
}

public final class HydrationStore: @unchecked Sendable {
    public init(backend: StorageBackend, device: DeviceKind, naming: DrinkNaming,
                calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() })
    public let device: DeviceKind

    // Catalog (phone authors; watch receives)
    public func catalog() throws -> CatalogDocument                            // seeds if missing
    @discardableResult public func upsertPreset(_ preset: Preset) throws -> Preset
    public func deletePreset(id: PresetID) throws
    public func reorderPresets(_ ids: [PresetID]) throws
    @discardableResult public func upsertDrink(_ drink: DrinkKind) throws -> DrinkKind
    public func deleteDrink(id: DrinkID) throws
    @discardableResult public func updateSettings(_ mutate: (inout HydrationSettings) -> Void) throws -> HydrationSettings

    // Entries
    @discardableResult public func log(_ request: LogRequest) throws -> DrinkEntry
    @discardableResult public func updateEntry(id: EntryID, volumeML: Double?, consumedAt: Date?) throws -> DrinkEntry
    @discardableResult public func deleteEntry(id: EntryID) throws -> DrinkEntry          // tombstone
    public func undoLast(within seconds: TimeInterval) throws -> DrinkEntry?               // newest live entry created on this device
    public func entry(id: EntryID) throws -> DrinkEntry?
    public func entries(from start: Date, to end: Date, includeDeleted: Bool = false) throws -> [DrinkEntry]
    public func daySummary(for day: Date) throws -> DaySummary
    public func history(days: Int, endingOn day: Date) throws -> [DaySummary]

    // Replication
    public func applyRemote(entries: [DrinkEntry]) throws -> MergeOutcome<DrinkEntry>
    public func applyRemote(catalog: CatalogDocument) throws -> Bool                      // true if changed
    public func digest(windowDays: Int = 14, healthPending: [EntryID]) throws -> SyncDigest
    public func peerState() throws -> PeerSyncState
    public func updatePeerState(_ mutate: (inout PeerSyncState) -> Void) throws

    // Health bookkeeping (device-local)
    public func healthMirror() throws -> [EntryID: HealthMirrorRecord]
    public func updateHealthMirror(_ entryID: EntryID, _ mutate: (inout HealthMirrorRecord) -> Void) throws
    public func acquireLease(holder: String, duration: TimeInterval) throws -> Bool
    public func releaseLease(holder: String) throws

    // Maintenance / diagnostics
    public func compact(now: Date) throws
    public func record(_ event: DiagnosticEvent)                                         // never throws
    public func diagnostics(limit: Int) throws -> [DiagnosticEvent]
}
```

### 16.3 HydrationCore: aggregation, health planning, sync, deep links
```swift
public struct DrinkTotal: Hashable, Sendable { public var drinkID: DrinkID; public var name: String; public var volumeML: Double; public var count: Int }
public struct DaySummary: Hashable, Sendable {
    public var dayStart: Date
    public var goalML: Double
    public var volumeML: Double            // beverage volume
    public var nutrients: Nutrients        // waterML drives progress
    public var progress: Double            // nutrients.waterML / goalML, unclamped
    public var byDrink: [DrinkTotal]       // sorted by volume desc
    public var entryCount: Int
    public var lastEntry: DrinkEntry?
    public static func empty(dayStart: Date, goalML: Double) -> DaySummary
}
public enum Aggregator {
    public static func summary(of entries: [DrinkEntry], day: Date, goalML: Double, calendar: Calendar) -> DaySummary
    public static func history(of entries: [DrinkEntry], days: Int, endingOn day: Date, goalML: Double, calendar: Calendar) -> [DaySummary]
}

public enum MetadataValue: Hashable, Sendable { case string(String), number(Double) }
public enum HealthKeys {
    public static let entryID = "SayoneEntryID", drinkID = "SayoneDrinkID", origin = "SayoneOrigin",
                      volumeML = "SayoneVolumeML", schema = "SayoneSchema"
    public static func syncIdentifier(entryID: EntryID, metric: HealthMetric) -> String   // "sayone.<id>.<metric>"
}
public struct HealthSampleSpec: Hashable, Sendable {
    public var metric: HealthMetric
    public var amount: Double              // canonical unit: mL | mg | kcal | g
    public var date: Date
    public var syncIdentifier: String
    public var syncVersion: Int
    public var foodType: String
    public var custom: [String: MetadataValue]
}
public enum HealthFailure: String, Codable, Sendable {
    case notDetermined, denied, unavailable, locked, invalid, transient, deleteBlocked, unknown
    public init(from decoder: Decoder) throws
}
public struct HealthMirrorRecord: Codable, Hashable, Sendable {
    public var entryID: EntryID
    public var writtenVersion: Int?
    public var writtenFingerprint: String?
    public var inFlightVersion: Int?
    public var inFlightFingerprint: String?
    public var deleted: Bool
    public var deleteTriedInApp: Bool
    public var deleteTriedInExtension: Bool
    public var attempts: Int
    public var lastAttemptAt: Date?
    public var lastError: HealthFailure?
    public var nextAttemptAt: Date?
    public init(entryID: EntryID)
}
public enum HealthOp: Hashable, Sendable {
    case write(entryID: EntryID, version: Int, fingerprint: String, samples: [HealthSampleSpec])
    case delete(entryID: EntryID)
    case forget(entryID: EntryID)
}
public struct RetryPolicy: Sendable {
    public var delays: [TimeInterval]
    public static let standard: RetryPolicy               // [15, 60, 300, 1800, 3600, 21600]
    public func nextAttempt(afterAttempts attempts: Int, from date: Date) -> Date
}
public enum EntryHealthStatus: Hashable, Sendable {
    case saved, pending(HealthFailure?), deleting, onPeer(pending: Bool), notApplicable
}
public enum HealthPlanner {
    public static func plan(entries: [DrinkEntry], mirror: [EntryID: HealthMirrorRecord], device: DeviceKind,
                            authorized: Set<HealthMetric>, writeExtras: Bool, now: Date, force: Bool,
                            retry: RetryPolicy = .standard, limit: Int = 50) -> [HealthOp]
    public static func samples(for entry: DrinkEntry, version: Int, metrics: Set<HealthMetric>) -> [HealthSampleSpec]
    public static func desiredMetrics(for entry: DrinkEntry, authorized: Set<HealthMetric>, writeExtras: Bool) -> Set<HealthMetric>
    public static func fingerprint(of entry: DrinkEntry, metrics: Set<HealthMetric>) -> String
    public static func status(of entry: DrinkEntry, mirror: HealthMirrorRecord?, device: DeviceKind,
                              peerPending: Set<EntryID>) -> EntryHealthStatus
}

public struct SyncDigest: Codable, Hashable, Sendable {
    public var windowStart: Date
    public var revisions: [EntryID: Int]
    public var catalogFingerprint: String
    public var healthPending: [EntryID]
}
public struct PeerSyncState: Codable, Hashable, Sendable {
    public var ackedRevisions: [EntryID: Int]
    public var queuedRevisions: [EntryID: Int]
    public var queuedAt: Date?
    public var peerHealthPending: [EntryID]
    public var peerCatalogFingerprint: String?
    public var lastSentAt: Date?
    public var lastReceivedAt: Date?
    public init()
}
public enum SyncBody: Codable, Sendable {
    case entries([DrinkEntry])
    case context(catalog: CatalogDocument?, digest: SyncDigest)
    case hello(digest: SyncDigest)
    case ack([EntryID: Int])
}
public struct SyncEnvelope: Codable, Sendable {
    public static let currentSchema = 1
    public var schema: Int
    public var sender: DeviceKind
    public var sentAt: Date
    public var body: SyncBody
    public init(sender: DeviceKind, sentAt: Date, body: SyncBody)
}
public enum WCPayloadCodec {
    public static let key = "env"
    public static func dictionary(for envelope: SyncEnvelope) throws -> [String: Any]   // ["env": Data]
    public static func envelope(from dictionary: [String: Any]) throws -> SyncEnvelope
}
public enum PeerSyncPlanner {
    public static func outbound(entries: [DrinkEntry], state: PeerSyncState, windowStart: Date,
                                queueIsEmpty: Bool, now: Date, limit: Int = 100) -> [DrinkEntry]
    public static func entriesPeerLacks(local: [DrinkEntry], peer: SyncDigest, limit: Int = 100) -> [DrinkEntry]
    public static func acknowledge(_ state: inout PeerSyncState, digest: SyncDigest, local: [DrinkEntry])
    public static func acknowledge(_ state: inout PeerSyncState, acks: [EntryID: Int])
    public static func markQueued(_ state: inout PeerSyncState, entries: [DrinkEntry], at date: Date)
}

public enum DeepLink: Hashable, Sendable {
    case today, customAmount
    case confirmLog(presetID: PresetID)
    case entry(EntryID)
    case healthOnboarding
    public static let scheme = "sayonehealth"
    public init?(url: URL)
    public var url: URL { … }
}

public struct DiagnosticEvent: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case log, health, sync, store, widget, unknown }
    public var at: Date
    public var kind: Kind
    public var process: String          // "app", "widget", "siri"
    public var message: String
    public var entryID: EntryID?
}
```

### 16.4 Apple shared layer (`Shared/*`)
```swift
// Shared/Platform
enum AppEnvironment {
    static let appGroupID: String                    // Info.plist SHAppGroupIdentifier ?? "group.com.sayoneone.sayonehealth"
    static let device: DeviceKind                    // #if os(watchOS) .watch #else .phone
    static let processKind: String                   // "app" | "widget" (from SAYONE_APP / SAYONE_WIDGET)
    static func storeDirectory() -> (url: URL, isAppGroup: Bool)
}
final class CoordinatedFileBackend: StorageBackend, @unchecked Sendable {
    init(directory: URL)                             // NSFileCoordinator + .atomic + .completeFileProtectionUntilFirstUserAuthentication
}
enum StoreProvider {
    static let shared: HydrationStore                // CoordinatedFileBackend + LocalizedDrinkNaming
    static var isUsingAppGroup: Bool { get }
}
struct LocalizedDrinkNaming: DrinkNaming {}          // Bundle.main.localizedString(forKey:value:table:)
enum ChangeNotifier {
    static let darwinName = "com.sayoneone.sayonehealth.store-changed"
    static let inProcess = Notification.Name("SayoneStoreChanged")
    static func post()                               // Darwin + NotificationCenter
    static func startObservingDarwin()               // apps only: re-posts `inProcess` on the main queue
}
enum SurfaceRefresher {
    static func reloadAll()                          // WidgetCenter.reloadAllTimelines + ControlCenter (iOS 18 / #available watchOS 26)
    static func catalogChanged()                     // + invalidateConfigurationRecommendations (#if os(watchOS))
}
enum VolumeFormat { static func string(ml: Double) -> String }          // Measurement<UnitVolume>
enum PresetPresentation {
    static func title(_ r: ResolvedPreset) -> String
    static func snapshot(_ r: ResolvedPreset) -> PresetSnapshot
}
struct PresetSnapshot: Hashable, Sendable {
    let presetID: PresetID; let drinkID: DrinkID; let volumeML: Double
    let title: String; let symbolName: String; let tint: DrinkTint; let isDeleted: Bool
}

// Shared/Health
import HealthKit
enum HealthTypes {
    static func type(_ m: HealthMetric) -> HKQuantityType
    static func unit(_ m: HealthMetric) -> HKUnit
    static let share: Set<HKSampleType>
    static let read: Set<HKObjectType>
    static func authorizedMetrics(_ store: HKHealthStore) -> Set<HealthMetric>   // sharingAuthorized only
}
enum HealthSampleFactory { static func make(_ spec: HealthSampleSpec) -> HKQuantitySample }
enum HealthAccessStatus: Equatable, Sendable { case unavailable, notDetermined, denied, partial(Set<HealthMetric>), authorized }
final class HealthKitMirror: @unchecked Sendable {
    static let shared: HealthKitMirror
    let healthStore: HKHealthStore
    enum Reason: String, Sendable { case afterLog, appActive, background, authorizationChanged, remoteMerge, userRetry }
    struct Report: Sendable { var written = 0, deleted = 0, failed = 0, remaining = 0; var skippedLease = false }
    func flush(_ store: HydrationStore, reason: Reason, budget: TimeInterval) async -> Report
    func accessStatus() -> HealthAccessStatus
    func pendingCount(_ store: HydrationStore) -> Int
}
#if SAYONE_APP
enum HealthAuthorization {
    static func request() async -> HealthAccessStatus        // requestAuthorization(toShare:read:), then accessStatus()
}
#endif

// Shared/Intents
struct LogOutcome: Sendable { let entry: DrinkEntry; let summary: DaySummary; let health: EntryHealthStatus }
enum LogPipeline {
    static func log(_ request: LogRequest) async throws -> LogOutcome    // store → HK flush(4s ext / 20s app) → notify → reload
    static func undo(entryID: EntryID?) async throws -> DrinkEntry?      // nil = last within undo window
    static func delete(entryID: EntryID) async throws
}
struct DrinkPresetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink preset")
    static let defaultQuery = DrinkPresetQuery()
    let id: String; let title: String; let drinkID: String; let volumeML: Double; let symbolName: String
    var displayRepresentation: DisplayRepresentation { … }
    init(_ snapshot: PresetSnapshot)
}
struct DrinkPresetQuery: EntityStringQuery { /* entities(for:), suggestedEntities(), entities(matching:), defaultResult() */ }
struct DrinkEntity: AppEntity { /* id, name, symbolName, defaultVolumeML; defaultQuery = DrinkEntityQuery() */ }
struct DrinkEntityQuery: EntityStringQuery { … }
struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Log"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Preset ID", default: "water-500") var presetID: String
    @Parameter(title: "Drink ID", default: "water") var drinkID: String
    @Parameter(title: "Volume (ml)", default: 500) var volumeML: Int
    @Parameter(title: "Surface", default: "widget") var surface: String     // "widget" | "control"
    init()
    init(snapshot: PresetSnapshot, surface: String)
    func perform() async throws -> some IntentResult
}
struct UndoEntryIntent: AppIntent { /* isDiscoverable = false; @Parameter(title: "Entry ID", default: "") var entryID: String */ }
struct SelectPresetIntent: WidgetConfigurationIntent { @Parameter(title: "Drink") var preset: DrinkPresetEntity?; init(); init(preset: DrinkPresetEntity) }
struct SelectTrioIntent: WidgetConfigurationIntent { /* first, second, third: DrinkPresetEntity? */ }

// Shared/WidgetKit
struct HydrationWidgetEntry: TimelineEntry {
    let date: Date
    let presets: [PresetSnapshot]        // 1 (Quick Log) or ≤3 (Trio); resolved from the store by ID
    let summary: DaySummary
    let lastEntry: DrinkEntry?
    let showUndo: Bool
    let attention: WidgetAttention?
}
enum WidgetAttention: Hashable { case healthPermission, healthPending(Int), noAppGroup }
enum WidgetTimeline {
    static func entry(presetIDs: [PresetID?], at date: Date) -> HydrationWidgetEntry      // never throws
    static func timeline(presetIDs: [PresetID?], now: Date) -> Timeline<HydrationWidgetEntry>  // now, undo-expiry, midnight; .atEnd
}

// Shared/Sync (apps only)
import WatchConnectivity
struct SyncStatus: Equatable, Sendable {
    var supported = false, activated = false, reachable = false
    var counterpartInstalled: Bool? = nil, paired: Bool? = nil
    var outstandingTransfers = 0, unacked = 0
    var lastSent: Date? = nil, lastReceived: Date? = nil
}
enum SyncReason: String, Sendable { case launch, becameActive, localChange, remoteRequest, background, userRequest }
final class WatchSyncService: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared: WatchSyncService
    static let statusChanged = Notification.Name("SayoneSyncStatusChanged")
    func activate()                                   // idempotent
    func syncNow(_ reason: SyncReason)
    var status: SyncStatus { get }
    #if os(watchOS)
    func drainBackgroundDelivery() async              // waits while hasContentPending (≤ 20 s)
    #endif
    // WCSessionDelegate: activationDidCompleteWith, didReceiveUserInfo, didReceiveApplicationContext,
    // didReceiveMessage(_:replyHandler:), sessionReachabilityDidChange; iOS: sessionDidBecomeInactive/Deactivate
}
```

---

## 17. Parallel work plan (6 engineers)

Contracts from §16 land first as compiling stubs. Each engineer owns separate folders, so there are no merge conflicts.

| # | Owner scope | Folders | Depends on | Done when |
|---|---|---|---|---|
| E1 | Core package | `Packages/HydrationCore/**` | – | `swift test` green on Linux; merge, planner, digest and codec property tests (duplicate, reorder and drop messages all converge) |
| E2 | Platform + HealthKit | `Shared/Platform`, `Shared/Health`, `Tests/AppleUnitTests` | E1 stubs | lease, write-ahead, error mapping, verify, delete-verify; unit tests for the sample factory and metadata |
| E3 | Sync + project/CI | `Shared/Sync`, `project.yml`, `Config/`, `scripts/`, `.github/` | E1 stubs | Linux preflight green; macOS CI green; WatchConnectivity envelope round-trip |
| E4 | Widgets, controls, widget intents | `Shared/Intents`, `Shared/WidgetKit`, `Widgets/**` | E1, E2 | both widget extensions compile; families guarded; recommendations implemented |
| E5 | iPhone app + Siri + localization | `App/**`, `Shared/Siri`, `Shared/UI`, `Shared/Resources` | E1–E4 APIs | screens from §12; catalogs pass lint; App Intents metadata gate passes |
| E6 | Watch app | `Watch/**` | E1–E4 APIs | watch screens, Crown picker, onboarding, background tasks |

Integration order: E1 → (E2, E3 in parallel) → E4 → (E5, E6). Every push runs the Linux preflight before macOS.

---

## 18. Tomorrow's test plan (docs/TESTING.md, in Russian)

**Setup**
1. `open SayoneHealth.xcodeproj`, or run `xcodegen generate` first.
2. Put the Personal Team in `Config/Local.xcconfig`.
3. Enable Developer Mode on the iPhone and the Watch, and remove other sideloaded apps (3-app limit).
4. Run the `SayoneHealth` scheme on the iPhone; this also installs the watch app.

**Checks**
1. iPhone onboarding → allow Health. Watch onboarding → allow Health *on the watch*.
2. Add the Quick Log complication on the watch (choose «Кола без сахара · 330 мл»). Tap it and confirm: the total updates, then Health (on the watch, later on the iPhone) shows water 330 ml and caffeine about 32 mg.
3. **Airplane mode on the iPhone**: tap the watch complication 3 times, then turn airplane mode off and open the watch app. The phone total gains exactly 3 entries. Diagnostics shows the acknowledgements.
4. Delete a watch-logged entry on the iPhone. The watch receives the tombstone and the Health sample disappears.
5. Lock the iPhone and say «Запиши воду в SayoneHealth». After unlock, Health has the sample and the total is correct.
6. Home Screen widget: Edit Widget → Coke Zero → tap → Undo. The Health sample is removed.
7. iPhone Control Center control. On watchOS 26 also the watch control, and the iPhone control from the watch.
8. Force-quit the app right after a tap. On relaunch the pending entry is flushed, and there is no duplicate in Health.
9. Try Siri in Russian and in English, on the iPhone and on the watch (watch needs exact phrases).

**Simulator:** layout, the confirm flow, and HealthKit on each simulator separately. Interactive taps and Health sync between simulators are not expected to work.

Turn on WidgetKit Developer Mode to lift reload limits.

---

## 19. Things not in the research digest (flagged)

- **Checked against Apple docs JSON during this proposal:**
  - WatchConnectivity declarations and behaviour (§7), including that `sendMessage` from the watch wakes the iOS app and that `transferUserInfo` is queued FIFO
  - `.backgroundTask(.watchConnectivity)` / `.backgroundTask(.appRefresh)` (watchOS 9) and `WKApplication.scheduleBackgroundRefresh(...)` (watchOS 7)
  - `NSFileCoordinator.coordinate(writingItemAt:options:error:byAccessor:)` and `.completeFileProtectionUntilFirstUserAuthentication`
  - `CFNotificationCenterGetDarwinNotifyCenter`
  - `invalidateConfigurationRecommendations()` (iOS 16 / watchOS 9)
  - `updateAppShortcutParameters()` (iOS 16 / watchOS 9)
  - `.handGestureShortcut` (iOS 18 / watchOS 11)
- **Checked locally:** `swiftc -parse` on Linux as a syntax check that includes inactive `#if` branches.
- **From memory:**
  - the ~64 KB `sendMessage` size limit
  - WatchConnectivity being unreliable in simulators
  - `#include?` in xcconfig
  - Codable dictionaries with non-String keys encoding as arrays
  - `Hasher` being randomised per process
  - 0xdead10cc
  - how SwiftUI `.appRefresh` maps to `scheduleBackgroundRefresh`
  - the nutrition values in §4.1

---

## 20. Risks and mitigations

See `key_risks`. Each risk has a fallback that keeps taps durable: the pending queue, the confirm-screen `widgetURL`, digest repair, and diagnostics.
