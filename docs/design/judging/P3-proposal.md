<!-- angle: ONE-TAP UX FIRST: maximise one-tap logging surfaces (watch face complications, Smart Stack, iPhone Home/Lock Screen widgets, Controls/Action button, Siri) and design every interaction flow (confirmation, undo, Digital Crown custom volume), while staying buildable. -->

# SayoneHealth v1: Architecture

An iPhone and Apple Watch drink logger. Every drink (water, Coke Zero, or anything else) goes to Apple Health. One tap logs from the watch face, the Smart Stack, Home and Lock Screen widgets, Controls, the Action button and Siri, in Russian and English.

---

## 0. Decisions at a glance

| Topic | Decision |
|---|---|
| Deployment targets | **iOS 18.0** and **watchOS 10.0**. The SayoneCore package is tools 5.9 with iOS 17 / watchOS 10 / macOS 14 and also builds on Linux. Anything newer than the floor is gated: watchOS 11 (interactivity, AccessoryWidgetGroup, double tap) and watchOS 26 (configurable complications, watch Controls). |
| Targets | 4 Xcode targets (iOS app, iOS widget extension, single-target watch app, watch widget extension) plus 1 local Swift package. Generated with XcodeGen 2.46.0. |
| Capabilities | Only HealthKit and App Groups, on all 4 targets. No Siri entitlement, iCloud, Push or Associated Domains, so a free Personal Team can sign it. |
| Source of truth | A JSON store per device in the App Group container. Writers take an `flock` lock and write atomically. Every UI, widget, Siri answer and complication reads this store, never a HealthKit query. |
| HealthKit | Flat quantity samples: dietaryWater (mL), dietaryCaffeine (mg), dietaryEnergyConsumed (kcal), dietarySugar (g). Each carries a `SyncIdentifier` of `<entryUUID>.<kind>` and `SyncVersion` 1. **Only the device that logged an entry writes or deletes its samples.** An entry is journaled locally first, then saved to Health, and retried by the app if the save fails. |
| Sync | WatchConnectivity is the fast path for deltas, tombstones and the catalog. A HealthKit import of our own samples (`SayoneEntryID` metadata) is the slow, guaranteed path. Entries merge by UUID, last writer wins. |
| One-tap logging | All widget, complication and control buttons run a single non-discoverable `QuickLogIntent` whose parameters are all pre-filled. Feedback: the widget re-renders with a check mark. Undo: an undo button on the widget for 10 minutes, a toast and swipe in the apps, and a Siri phrase. Duplicate taps within 2 s are ignored. |
| Siri | App Intents plus `AppShortcutsProvider` in **both** apps. 6 App Shortcuts with ru and en phrases, parameterised by preset (AppEntity) or drink (AppEntity), plus a today's-total query. |
| Build safety | Linux package tests; XcodeGen preflight on Linux; a repo lint that forbids platform-illegal APIs per folder; a CI matrix with one leg per target so every target's errors show up in the same round-trip; an App Intents metadata assertion. |

---

## 1. Deployment targets and toolchain

| Item | Value | Why |
|---|---|---|
| iOS app and iOS widget extension | **18.0** | Interactive widgets need iOS 17. iOS 18 adds Controls, `ControlCenter` and `promptsForUserConfiguration()` with no `#available` checks, and lets the WidgetBundle list the control directly. From memory, iOS 18 supports the same hardware as iOS 17 (XS/XR and later), so the higher floor costs no devices. |
| Watch app and watch widget extension | **10.0** | Every watch that can run watchOS 10 can install the app. At runtime watchOS 10 renders `Button(intent:)` but a tap opens the app; the `widgetURL` then routes to a confirm screen. On watchOS 11+ widgets are interactive. On 26+, complications are configurable per instance and watch Controls are available. If both test devices turn out to be on watchOS ≥ 11, change `WATCHOS_DEPLOYMENT_TARGET` to 11.0 in one place. The code compiles either way; the only cost is warnings about redundant availability checks. |
| SayoneCore package | `swift-tools-version: 5.9`, `.iOS(.v17), .watchOS(.v10), .macOS(.v14)` | Stays in Swift 5 mode. Minimums are ≤ the app targets. Verified on the Linux Swift 6.4 toolchain. |
| Language mode | `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`. `SWIFT_DEFAULT_ACTOR_ISOLATION` is not set. | Avoids Swift 6 strict-concurrency errors. |
| Xcode (CI) | `macos-26` runner, newest `/Applications/Xcode_26*.app` picked by glob (26.6 today, watchOS/iOS SDK 26.5). Optional `xcode-27` job with `continue-on-error`. | Watch-26 APIs compile; no hard-coded patch paths. |
| Code that must never appear | iOS/watchOS 26-only App Intents APIs (`supportedModes`, `continueInForeground`), 27-only APIs (`allowedExecutionTargets`, `earliestAuthorizedSampleDate`), `openAppWhenRun`, HealthKitUI, `AppIntentsPackage`. | They either aren't available at our targets or add risk. |

---

## 2. Xcode targets, bundle IDs and capabilities

`Config/Base.xcconfig` holds `BUNDLE_ID_PREFIX = com.sayoneone.sayonehealth` and `APP_GROUP_ID = group.$(BUNDLE_ID_PREFIX)`, so the default group is `group.com.sayoneone.sayonehealth`.

| Target | XcodeGen type / platform | Bundle ID | Embedded in | Entitlements | Compile condition |
|---|---|---|---|---|---|
| `SayoneHealth` | `application` / iOS | `$(BUNDLE_ID_PREFIX)` | — | healthkit=true, healthkit.access=[], app-groups=[$(APP_GROUP_ID)] | `SAYONE_APP` |
| `SayoneHealthWidgets` | `app-extension` / iOS | `$(BUNDLE_ID_PREFIX).widgets` | iOS app → Embed Foundation Extensions (PlugIns) | same | `SAYONE_WIDGET_EXT` |
| `SayoneHealthWatch` | `application` / watchOS (single target, **not** watchapp2) | `$(BUNDLE_ID_PREFIX).watchkitapp` | iOS app → "Embed Watch Content" `$(CONTENTS_FOLDER_PATH)/Watch` | same | `SAYONE_APP` |
| `SayoneHealthWatchWidgets` | `app-extension` / watchOS | `$(BUNDLE_ID_PREFIX).watchkitapp.widgets` | watch app → PlugIns | same | `SAYONE_WIDGET_EXT` |
| `SayoneCore` | local SwiftPM package, static, linked (not embedded) into all 4 | — | — | — | — |

- Watch app Info.plist: `WKApplication = YES`, `WKCompanionAppBundleIdentifier = $(BUNDLE_ID_PREFIX)` (must equal the iOS bundle ID), `WKRunsIndependentlyOfCompanionApp = YES`. **No `NSExtension` key in either app plist.**
- Both widget plists: `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`.
- All 4 plists: `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` (localized), `SHAppGroupIdentifier = $(APP_GROUP_ID)` (read at runtime), `CFBundleShortVersionString = $(MARKETING_VERSION)`, `CFBundleVersion = $(CURRENT_PROJECT_VERSION)`.
- Both app plists: `CFBundleURLTypes` with the scheme `sayonehealth`, and `INAlternativeAppNames` = `Sayone`, `Сейон`, `Сэйон` (3 entries, not localized, so no InfoPlist.strings tricks are needed).
- iOS plist only: `UILaunchScreen = {}`, `UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes = NO`, portrait orientation.
- Free Personal Team: 4 App IDs plus 1 group. From forum reports, the iOS app and its watch app count as one sideloaded app. Choose the prefix once; each change uses 4 of the 10 App IDs allowed per week.

---

## 3. Module boundaries

```
                    ┌────────────────────────────────────────────┐
                    │ Packages/SayoneCore  (Foundation only;     │
                    │ builds + tests on Linux and on Xcode)      │
                    │ models · catalog · nutrient math · day     │
                    │ aggregation · LogPlanner (dedupe/undo) ·   │
                    │ FileDrinkStore (flock + atomic JSON) ·     │
                    │ SyncMerge · HealthSamplePlanner · import   │
                    │ assembler · VolumeFormatter · Phrasebook   │
                    │ (ru/en runtime sentences) · WidgetSnapshot │
                    │ Builder · DeepLink · WidgetKinds           │
                    └───────────────▲────────────────────────────┘
                                    │ import SayoneCore
  ┌─────────────────────────────────┴───────────────────────────────────┐
  │ Shared/Platform   (all 4 targets) AppGroup, StoreProvider,          │
  │   HealthService (HealthKit), DrinkLogger (single log/undo/flush     │
  │   path), WidgetRefresher, PresetResolver, Log (os.Logger)           │
  │ Shared/Components (all 4) ProgressRing, BeverageGlyph, Tint→Color   │
  │ Shared/Intents/Core (all 4) DrinkPresetEntity/Query, Beverage-      │
  │   Entity/Query, QuickLogIntent, UndoEntryIntent, SelectPreset-      │
  │   Intent, FavoritesConfigIntent, SelectPresetControlIntent          │
  │ Shared/Resources  (all 4) Localizable.xcstrings, InfoPlist.xcstrings│
  └───────▲──────────────────────────────────────────────▲──────────────┘
          │                                              │
  ┌───────┴──────────────────────┐        ┌──────────────┴───────────────────┐
  │ WidgetShared (both widget    │        │ Shared/Intents/Siri (both apps)  │
  │ exts): QuickLogWidget +      │        │   6 Siri intents, SayoneShortcuts│
  │ Provider, FavoritesWidget +  │        │   AppShortcuts.xcstrings         │
  │ Provider, entries,           │        │ Shared/AppCore (both apps)       │
  │ QuickLogControl              │        │   AppModel, PeerSync (WC),       │
  └───▲───────────────▲──────────┘        │   HealthImporter, DeepLinkRouter │
      │               │                   └──────▲──────────────▲──────────┘
  iOS/Widgets   watchOS/Widgets               iOS/App        watchOS/App
  (bundle, views, (bundle, views,             (screens)      (screens, crown)
  PlatformWidget  PlatformWidgetConfig)
  Config)
```

Rules:
1. **No `#if os()` in shared folders.** Platform differences are expressed as *same-named types defined in each platform folder*: `PlatformWidgetConfig`, `QuickLogView`, `FavoritesView`, and `WidgetConfiguration.platformPrompt()`. Each widget extension compiles only its own copy. The only permitted exceptions, which the lint enforces by whitelist:
   - `DeviceOrigin.current` (`#if os(watchOS)`)
   - `WidgetRefresher` (`#if os(watchOS)` around `invalidateConfigurationRecommendations()`)
   - `PeerSync` (`#if os(iOS)` around the iOS-only WCSessionDelegate methods)
   - `SelectPresetControlIntent` and `QuickLogControl` (`#if compiler(>=6.2)`)
2. `SAYONE_APP`-only code: `HealthService.requestAuthorization()` and the call to `PeerSync` from `DrinkLogger`. Extensions therefore **cannot compile** a HealthKit authorization request.
3. **AppIntents code never lives in the package.** HealthKit, SwiftUI and WidgetKit never appear in the package.
4. New files are picked up by folder globs, so nobody except the infra owner edits `project.yml`.

---

## 4. Core data model (SayoneCore)

### 4.1 Beverages (built-in catalog; nutrient values are approximate, user-editable, and not medical advice)

| id | kind | ru / en name | SF Symbol | tint | caffeine mg/100 mL | kcal/100 mL | sugar g/100 mL | water % | default mL |
|---|---|---|---|---|---|---|---|---|---|
| `water` | water | Вода / Water | drop.fill | blue | 0 | 0 | 0 | 100 | 250 |
| `sparkling` | sparklingWater | Газированная вода / Sparkling water | bubbles.and.sparkles.fill | cyan | 0 | 0 | 0 | 100 | 330 |
| `cola-zero` | colaZero | Кола без сахара / Cola Zero | takeoutbag.and.cup.and.straw.fill | graphite | 9.6 (EU label 32 mg/330 mL; verify) | 0.3 | 0 | 100 | 330 |
| `cola` | cola | Кола / Cola | takeoutbag.and.cup.and.straw.fill | red | 9.6 | 42 | 10.6 | 100 | 330 |
| `coffee` | coffee | Кофе / Coffee | cup.and.saucer.fill | brown | 40 | 1 | 0 | 100 | 200 |
| `tea` | tea | Чай / Tea | mug.fill | amber | 20 | 1 | 0 | 100 | 250 |
| `juice` | juice | Сок / Juice | wineglass.fill | orange | 0 | 45 | 9 | 100 | 200 |
| `milk` | milk | Молоко / Milk | mug.fill | gray | 0 | 52 | 4.7 | 100 | 200 |
| `custom-<uuid>` | custom | user name | user choice from ~12 symbols | user | user | user | user | user | user |

`waterPercent` sets how much of the volume counts toward the goal and is written as dietaryWater. Every built-in defaults to 100%, so the app makes no hydration claims. The user can edit it (Settings wording: "Засчитывать в воду, %").

### 4.2 Presets (seeded with identical IDs on both devices; `modifiedAt = 1970` so any user edit wins)

Order and favourites: `water-500` ⭐ (primary), `water-250` ⭐, `cola-zero-330` ⭐, `coffee-200` ⭐, `cola-zero-500`, `tea-250`.
- The first favourite is the **primary** preset: the big watch button and the default for any unconfigured widget or control.
- The first 3 favourites form the watch "trio". The first 4 fill the iPhone medium widget.
- `customTitle` lets the user rename a preset for voice, e.g. «пол-литра воды». Without it the title is `Phrasebook.presetTitle`, e.g. «Вода 500 мл».

### 4.3 Entry (append-only; deletions are tombstones)

`id: UUID`, `date`, `beverageID`, `beverageKind`, `beverageName` (localized snapshot at log time, also used as HealthKit FoodType), `symbolName`, `volumeML: Int`, `amounts: NutrientAmounts` (a snapshot of waterML, caffeineMG, kcal, sugarG), `presetID?`, `origin: phone|watch`, `source: app|widget|control|siri|deepLink|imported`, `health: HealthSyncState`, `healthVersion` (always 1 in v1), `isDeleted`, `modifiedAt`, `lastHealthError?`.

`HealthSyncState` values:
- `pending`: not yet in Health
- `saved`
- `pendingDelete`: tombstoned; its samples must still be deleted
- `deleted`
- `remote`: another device owns the samples
- `skipped`: nothing to write, or Health unavailable

There is no in-place edit in v1. "Изменить" means undo plus a new entry with the same timestamp, so there are no sync-version bumps and no cross-device edit races.

### 4.4 Settings

| Setting | Default | Notes |
|---|---|---|
| `dailyGoalML` | 2000 | Labelled as the user's own goal, not a medical recommendation. |
| `writeNutrientsToHealth` | true | |
| `watchTapMode` | `instant` | Alternative is `confirm`: complications render without a button, so a tap opens the Confirm screen. This is accidental-tap protection. |
| `crownStepML` | 50 | 10, 25 or 50. |
| `lastCustomVolumeML` | 300 | |
| `lastCustomBeverageID` | "water" | |
| `siriWaterVolumeML` | 500 | |
| `modifiedAt` | | Settings are synced last-writer-wins. |

### 4.5 Policies (`LoggingPolicy`)

| Policy | Value |
|---|---|
| Duplicate-tap window | 2 s (same beverage, volume and source) |
| Widget undo window | 600 s |
| App undo toast | 6 s |
| Siri "undo last" window | 3 h |
| Allowed volume | 10…3000 mL |
| Local retention | 60 days |
| Tombstone retention | 7 days |
| HealthKit import window | 2 days |

Millilitres are stored as `Int`. The largest sum is well under 2³¹, which matters because `Int` is 32-bit on arm64_32 watches.

---

## 5. Storage and data flow

### 5.1 Store

- **Location:** `<AppGroup container>/SayoneStore/sayone-store-v1.json` plus the lock file `store.lock`. On each device the app and its widget extension share the file. App Groups are **not** shared between iPhone and Watch.
- **Writes:** `FileDrinkStore.mutate { inout StoreState }` runs this sequence:
  1. `open(lock, O_CREAT|O_RDWR)` then `flock(LOCK_EX)`
  2. read and decode the file (tolerant decoding: `decodeIfPresent` with defaults)
  3. apply the closure
  4. run `StoreMaintenance.prune`
  5. `Data.write(.atomic)`
  6. unlock

  This is safe when the app process, the widget process and an intent process write at the same moment, and it is unit-tested on Linux with concurrent writers.
- **Encoding:** `JSONEncoder` with `.sortedKeys` and `.secondsSince1970` dates. The file stays small (about 60 days × 15 entries, under 400 KB).
- **File protection:** the default class (available after first unlock). Never `.complete`, because Controls and Siri run while the phone is locked.
- **Corrupt file:** rename it to `*.corrupt-<ts>.json`, reseed, and log a fault. The Diagnostics screen shows this.
- **Missing App Group** (for example, a signing mistake): fall back to Application Support and set `AppGroup.isShared = false`, which Diagnostics shows as a red flag. Widgets would then show seed data only.
- **Apps observe changes** by reloading on `scenePhase == .active` and polling `modificationDate()` every 2 s while active. This is plain Foundation with no Darwin-notification APIs.

### 5.2 The single write path, used by every surface

```
Surface (widget button / control / Siri / app tap / crown / deep-link confirm)
   │  LogRequest(presetID?, beverageID, volumeML, date, source)
   ▼
DrinkLogger.log(request)                      ← Shared/Platform, runs in whichever process
 1. decision = store.mutate { LogPlanner.apply(request, &state, origin: .current, language: .current) }
      • resolves preset → beverage (current values), clamps volume, dedupes (2 s), snapshots name+amounts
      • appends entry with health = .pending               ← the tap is now durable
 2. if duplicate → return (no Health write)
 3. specs = HealthSamplePlanner.specs(entry, includeNutrients: settings.writeNutrientsToHealth)
      specs empty / Health unavailable → mark .skipped
      accessStatus != .authorized       → stay .pending (lastHealthError = "not-authorized")
      else try await HealthService.save(specs) → mark .saved   (catch → stay .pending + error)
 4. WidgetRefresher.reloadAll()                 (free: intent-triggered / foreground)
 5. #if SAYONE_APP && !SAYONE_NO_WC  PeerSync.shared.pushChanges()  #endif
 6. return LogOutcome (entry, today summary, spoken confirmation)
```

**Pending entries are flushed** by `DrinkLogger.flushPendingHealth()`. It runs on app launch, on every `scenePhase .active`, right after Health authorization is granted, and after a WatchConnectivity merge that requested deletes. See §6.4.

### 5.3 Read paths

| Consumer | Reads | Never |
|---|---|---|
| Widget providers, controls, entity queries | `StoreProvider.shared.read()`, turned into `WidgetSnapshot`/`PresetSnapshot` by `WidgetSnapshotBuilder` | HealthKit queries (reads fail while locked; also latency) |
| Siri dialogs | local store (`Aggregator.today`) | HealthKit |
| Apps | `AppModel.state` (the store) | — |
| Cross-device catch-up | `HealthImporter` reads *our own* samples by the `SayoneEntryID` metadata key | — |

---

## 6. HealthKit strategy

### 6.1 Types, units and metadata

| `HealthQuantityKind` | HK identifier | Unit | Written when |
|---|---|---|---|
| water | `.dietaryWater` | `HKUnit.literUnit(with: .milli)` | `amounts.waterML ≥ 1` |
| caffeine | `.dietaryCaffeine` | `HKUnit.gramUnit(with: .milli)` | ≥ 0.5 mg and nutrients enabled |
| energy | `.dietaryEnergyConsumed` | `HKUnit.kilocalorie()` | ≥ 0.5 kcal and nutrients enabled |
| sugar | `.dietarySugar` | `HKUnit.gram()` | ≥ 0.1 g and nutrients enabled |

- One constant table maps each kind to its type and unit. Before building a sample, `HealthService` guards with `quantityType.is(compatibleWith: unit)` and skips the sample instead of hitting the uncatchable ObjC exception.
- Samples use `HKQuantitySample(type:quantity:start:end:metadata:)` with `start == end == entry.date`. There is no `HKCorrelation`, which removes a crash risk.

Metadata on every sample (NSString or NSNumber values only):

| Key | Value |
|---|---|
| `HKMetadataKeySyncIdentifier` | `"<entryUUID>.<kind>"` (unique per type) |
| `HKMetadataKeySyncVersion` | `NSNumber(1)` (always together with the identifier) |
| `HKMetadataKeyFoodType` | localized drink name, e.g. «Кола без сахара» |
| `HKMetadataKeyWasUserEntered` | `NSNumber(true)` |
| `SayoneEntryID` | uuid string |
| `SayoneBeverageID` | string |
| `SayoneBeverageKind` | string |
| `SayoneOrigin` | `phone` or `watch` |
| `SayoneVolumeML` | NSNumber |

Custom keys never start with "HK". `HealthSamplePlanner` in the package produces these as pure `HealthSampleSpec` values, unit-tested on Linux. The Apple layer only maps specs to `HKQuantitySample`.

### 6.2 Authorization

- Share and read the same 4 types; nothing else is requested.
- Requested **only** from the foreground iOS app and, separately, the foreground watch app: during onboarding, from the "Подключить Здоровье" buttons, and from the watch's first launch. Use `try await store.requestAuthorization(toShare:read:)`, compiled only under `SAYONE_APP`. The two devices keep separate permission state; the README tells the tester to grant both.
- Extensions and intents only call `authorizationStatus(for: water) == .sharingAuthorized` (and per-kind `canWrite`). `handleAuthorizationForExtension` is never used; it is iOS-only and cannot be called from extensions.
- `save([...])` is all-or-nothing, so specs are filtered to kinds that are `.sharingAuthorized` before saving. A denied caffeine permission therefore never drops the water sample.

### 6.3 Idempotency and double-count prevention

- **Single writer:** only `entry.origin == DeviceOrigin.current` ever saves or deletes that entry's samples. Entries received from the peer are `.remote` and never written. Health's own iPhone⇄Watch sync then carries the samples.
- **Retries:** the same sync ID and the same version mean HealthKit ignores a re-save (WWDC20). To avoid relying on the undocumented success/error result of an equal-version re-save, the flush first runs `hasSamples(entryID:)` (an `HKSampleQueryDescriptor` with `predicateForObjects(withMetadataKey: "SayoneEntryID", allowedValues: [id])`, limit 1). If samples exist it marks the entry saved; otherwise it saves.
- **Rapid double taps:** `LogPlanner` rejects an identical request from the same source within 2 s, inside the locked mutate, so two processes cannot both append.

### 6.4 Flush, delete and undo

```
flushPendingHealth():                                  (origin == local only)
  guard accessStatus() == .authorized else return
  for e in pending (oldest first):
     do { if try await hasSamples(e.id) { mark .saved } else { try await save(specs(e)); mark .saved } }
     catch HKError.errorDatabaseInaccessible { stop — device locked, retry on next active }
     catch { keep .pending, record error }
  for e in pendingDelete:
     do { _ = try await deleteSamples(entryID: e.id); mark .deleted }   // 0 deleted is OK (never saved)
     catch { keep .pendingDelete }
```

- `deleteSamples` runs `deleteObjects(of: type, predicate: SayoneEntryID == id)` for each writable kind.
- **Undo** (`LogPlanner.undo`):
  - Local entry in `pending` or `saved`: tombstone it, set `pendingDelete`, then delete immediately. Treating `pending` as `pendingDelete` also covers a save racing in another process.
  - Local `skipped` entry: tombstone it and mark it deleted.
  - Remote entry: tombstone it and push the tombstone over WatchConnectivity. The **origin device** deletes the samples when it merges the tombstone. If the tombstone cannot reach it, the entry disappears from both UIs once WC delivers (`transferUserInfo` is queued), and the Health sample stays until then.
- Not relied on: deleting another device's samples. Apple documents only "objects this app saved"; the sources differ by bundle ID.

### 6.5 Locked device and extensions

- Writes while locked are cached by HealthKit and merged after unlock (documented). Controls and Siri use the default `authenticationPolicy` `.alwaysAllowed`, so they log while the phone is locked: the store file is readable after first unlock and the Health write is cached.
- Reads while locked throw `errorDatabaseInaccessible`. Only the flush and `HealthImporter` read, and both stop quietly.
- Widget and control intents run in the **widget extension** by default. Both extensions carry the HealthKit entitlement and usage strings. If a save from the extension fails, the entry stays `pending` (it is journaled) and the app flushes it next time it runs, so no tap is lost.
- The iOS kill-switch `SAYONE_IOS_INTENT_IN_APP` (off by default) adds `extension QuickLogIntent: LiveActivityIntent {}` under `#if os(iOS)`, which moves iPhone widget and control taps into the app process. watchOS has no equivalent, so the pending-queue flush in the watch app is the only fallback there.

### 6.6 HealthImporter (apps only)

1. On app activation, fetch our own samples from the last 2 days for the 4 kinds (`HKSampleQueryDescriptor`, predicate = date ≥ since AND metadata key `SayoneEntryID` exists).
2. Convert them to `ImportedSampleFields`.
3. `HealthImportAssembler.assemble` groups them by entry ID and rebuilds each entry from the metadata.
4. `SyncMerge.applyImported` inserts only unknown IDs and never resurrects a tombstone (the 2-day window is shorter than the 7-day tombstone retention). Remote-origin entries become `.remote`; local-origin entries (for example after a reinstall) become `.saved`.
5. `.errorNoData` and `.errorDatabaseInaccessible` mean "nothing to import now".

---

## 7. Watch ⇄ phone sync

| Channel | When | Payload |
|---|---|---|
| `sendMessage` (reachable) or `transferUserInfo` (queued, guaranteed) | after every mutation made in an **app** process; on app activation for anything changed since `peerCursor` | `SyncEnvelope` JSON `Data` under key `"e"`: changed entries including tombstones, changed beverages, presets, settings |
| `updateApplicationContext` | on each app activation | full recent snapshot: the last 3 days of entries plus the whole catalog (latest wins) |
| HealthKit import | on app activation | our own samples from the last 2 days (§6.6) |

Merge rules (`SyncMerge.apply`, pure and unit-tested):
- **Entries**, keyed by UUID:
  - An unknown ID is inserted. Its `health` is `.remote` if `origin != local`. If the entry is ours but echoed back, the local state is kept.
  - For a known ID, the newer `modifiedAt` wins for payload fields. `health` is always kept locally.
  - A newer tombstone on a local-origin entry that is `saved` or `pending` sets `pendingDelete` and reports the entry in `healthDeletesNeeded`. The receiver then calls `flushPendingHealth()`.
- **Beverages, presets, settings:** each item is last-writer-wins by `modifiedAt`. Preset deletion is a tombstone (`isDeleted`). If a merge changes the catalog, the watch calls `WidgetCenter.shared.invalidateConfigurationRecommendations()`; both sides reload widgets and call `SayoneShortcuts.updateAppShortcutParameters()`.

Why totals converge, and why they are never double-counted:
1. Every entry exists once, keyed by UUID, on both devices.
2. Each device's total is computed from its local store of live entries.
3. Health holds each entry exactly once: one writer plus sync IDs.

When the peer app never runs, WatchConnectivity queues the envelope and the HealthKit import backfills entries once Health's iPhone⇄Watch sync delivers them. That delay is minutes, sometimes longer.

WatchConnectivity lives in a single file, `Shared/AppCore/PeerSync.swift`, and can be compiled out with `SAYONE_NO_WC`. The app still works, but cross-device undo is lost in that mode.

Known limitation: entries logged by a **widget extension** reach the peer only when the owning app next runs (extensions do not use WCSession) or through the HealthKit import. Waking the watch in the background (`transferCurrentComplicationUserInfo` / `.backgroundTask(.watchConnectivity)`) is deliberately left out of v1 (§19).

---

## 8. One-tap surfaces and interaction design

### 8.1 Surface matrix

| # | Surface | Runtime OS | Taps | `perform()` runs in | Per-instance choice of drink | Feedback | Undo |
|---|---|---|---|---|---|---|---|
| 1 | Watch face complication (circular, corner, rectangular) | watchOS 11+ (on 10 the tap opens the Confirm screen) | 1 | watch widget ext | < 26: pick a recommendation per slot ("Вода 500 мл", "Кола без сахара 330 мл", …); ≥ 26: edit the parameter in the face editor | ring and total re-render, ✓ | Smart Stack rectangular, app, Siri |
| 2 | Smart Stack: QuickLog rectangular | watchOS 11+ | 1, or **double tap** (Series 9/Ultra 2; `.handGestureShortcut(.primaryAction)`) | watch widget ext | same as #1 | ✓ + time | undo button for 10 min |
| 3 | Smart Stack: Favorites trio (`AccessoryWidgetGroup`, 3 buttons) | watchOS 11+ | 1 | watch widget ext | < 26: "Избранное" (app favourites); ≥ 26: 3 slots | ✓ in label | app |
| 4 | Watch Control Center, Smart Stack and Ultra Action button: native control | watchOS 26+ | 1 | watch widget ext | configurable control | system | app / Siri |
| 5 | iPhone control shown on the watch | watchOS 26 + iOS 18 | 1 | iPhone widget ext | per control | — | iPhone |
| 6 | Watch app main screen | 10+ | 1 (big primary button; double tap on 11+) | watch app | — | haptic `.success` + overlay | overlay 4 s, list swipe |
| 7 | Watch Siri / Shortcuts / Ultra Action button → App Shortcut | 10+ | voice or 1 press | watch app | preset entity | spoken dialog | "Отмени последний напиток в …" |
| 8 | iPhone Home: QuickLog `systemSmall` (also StandBy) | iOS 18 | 1 | iOS widget ext | Edit Widget → preset; prompts when added | ✓ + total | small ↶ for 10 min |
| 9 | iPhone Home: Favorites `systemMedium` (4 buttons) | iOS 18 | 1 | iOS widget ext | 4 slots | ✓ + total | ↶ button |
| 10 | iPhone Lock Screen: QuickLog circular or rectangular | iOS 18 (needs unlock) | 1 | iOS widget ext | Lock Screen editor | ✓ | rectangular ↶ |
| 11 | iPhone Control Center, Lock Screen control, Action button | iOS 18 (works while locked) | 1 | iOS widget ext | control configuration | control glyph | widget / app / Siri |
| 12 | iPhone Siri / Spotlight / Shortcuts | iOS 18 | voice | app process (background) | preset or drink entity | dialog with today's total | Siri undo |
| 13 | iPhone app Today grid | iOS 18 | 1 | app | — | haptic + toast | toast 6 s, swipe |

### 8.2 Flows

- **A. Watch complication tap on watchOS 11+.**
  1. The tap goes to `QuickLogIntent(presetID, beverageID, volumeML, source: .widget)`, all pre-filled, which calls `DrinkLogger.log`.
  2. The store append happens first; the dedupe check runs inside the lock.
  3. HealthKit save (if authorized).
  4. `reloadAllTimelines`, then return. WidgetKit reloads, and `.invalidatableContent()` dims the total until it does.
  5. The new entry shows the ring advanced, the new total, and a ✓ badge.
  6. The next time the watch app opens, it flushes anything still pending and pushes to the phone.
- **B. watchOS 10, missed hit target, or `watchTapMode = confirm`.** The root view has one `widgetURL(sayonehealth://confirm?preset=ID)`, which opens `ConfirmLogView` with the preset and its volume. The Digital Crown adjusts the volume before confirming; **Записать** logs it (double tap on 11+). Opening the URL never logs automatically, so no double entries.
- **C. iPhone Home or Lock Screen button.** Same as A, running in the iOS extension. On the Lock Screen the phone must be unlocked first (system rule).
- **D. Control, Action button, or iPhone control on the watch.** A `ControlWidgetButton(action: QuickLogIntent(...))` works while locked. Controls are stateless, so no `ControlCenter` reloads are needed. Widgets reload from `perform()`.
- **E. Siri** «Запиши воду в Сейон». `LogWaterIntent` runs in the app process and logs `siriWaterVolumeML` of water. It answers «Записано: вода 500 мл. Сегодня 1,5 л из 2 л.». Without Health permission it still logs locally and says «…Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью».».
- **F. Custom volume on the watch.** Today → «Другой объём». `CrownVolumeView` shows the beverage chip (tap to cycle, or pick from a list) and a large number bound to a `Double`: `.focusable().digitalCrownRotation($ml, from: 10, through: 2000, by: step, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)`. Small −/+ buttons sit beside it. **Добавить** logs, remembers the last volume and beverage, and plays `.sensoryFeedback(.success)`. The view is never inside a List or ScrollView.
- **G. Undo.**
  - App: a toast with **Отменить** (6 s) and swipe-to-delete in the lists.
  - Widgets: `UndoEntryIntent(entryID)` is visible for 10 min after a log; a timeline entry at `lastLog + 600 s` hides it.
  - Siri: `UndoLastDrinkIntent` covers the last 3 hours.
  - Every path runs `DrinkLogger.undo`, which deletes the Health samples on the origin device (§6.4).

### 8.3 Visual rules for tidy widgets

- Every root view has `.containerBackground(for: .widget) { tint.opacity(0.25) }` (the watch face removes it; the Smart Stack shows it).
- The glyph and ring use `.widgetAccentable()` so tinted, clear and watch-face modes look right.
- Text uses `lineLimit(1)` and `minimumScaleFactor(0.6)`.
- Totals use `VolumeFormatter` (for example «1,2 / 2 л») and carry `.invalidatableContent()`.
- SF Symbols only. There is no `AccessoryWidgetBackground` inside a `.plain` button label (hit-test bug FB15151000); the circular button uses `Gauge(.accessoryCircularCapacity)` as its label.
- One `widgetURL` per view hierarchy, at the root.

---

## 9. iPhone widgets (`SayoneHealthWidgets`)

Bundle: `QuickLogWidget()`, `FavoritesWidget()`, `QuickLogControl()` listed directly (iOS 18 floor).

| Widget (kind) | Configuration | Families | Layout |
|---|---|---|---|
| `QuickLogWidget` (`SayoneQuickLog`) | `AppIntentConfiguration(intent: SelectPresetIntent.self)` with `DrinkPresetEntity?`; `nil` means the primary preset. Uses `.promptsForUserConfiguration()` via `platformPrompt()`. | `systemSmall`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline` | **small:** the whole tile is one `Button(intent:)` showing glyph, title «Вода 0,5 л», a ring for today's progress and «1,2 / 2 л»; a small ↶ button at top right appears when `lastLog` is under 10 min old. **circular:** a button with a capacity gauge and the glyph. **rectangular:** a log button (title, total, progress bar) plus ↶ when fresh. **inline:** «💧 1,2 / 2 л» as text only, with widgetURL `today`. |
| `FavoritesWidget` (`SayoneFavorites`) | `AppIntentConfiguration(intent: FavoritesConfigIntent.self)` with `slot1…slot4: DrinkPresetEntity?`; empty slots fill from favourites in order | `systemMedium` | Left: ring, total, caffeine and sugar line, ↶ when fresh. Right: a 2×2 grid of preset buttons (glyph plus «+500»). |

Timeline: `[now, lastLog + 600 s (if in the future), start of next day]` with `.atEnd`. The builder computes each entry "as of" its date, so the midnight entry shows 0 and the +600 s entry hides ↶.

---

## 10. Watch complications and Smart Stack (`SayoneHealthWatchWidgets`)

Bundle:

```swift
@main struct SayoneWatchWidgetBundle: WidgetBundle {
  var body: some Widget {
    QuickLogWidget()
    FavoritesWidget()
    #if compiler(>=6.2) && !SAYONE_NO_WATCH_CONTROLS
    if #available(watchOS 26.0, *) { QuickLogControl() }   // buildLimitedAvailability(some ControlWidget)
    #endif
  }
}
```

| Widget | Families | Layout |
|---|---|---|
| `QuickLogWidget` | `accessoryCircular`, `accessoryCorner`, `accessoryRectangular`, `accessoryInline` | **corner:** `Button(intent:)` with the glyph (`.title2`, accentable), and `.widgetLabel(VolumeFormatter.delta)` shows «+500». **circular:** a button whose label is `Gauge(value: progress) { glyph }.gaugeStyle(.accessoryCircularCapacity)` under `.buttonStyle(.plain)` with no AccessoryWidgetBackground; `.widgetLabel` shows the total on faces that support it. **rectangular (Smart Stack):** an HStack with the log button (glyph, title, «1,2 / 2 л», progress bar; `primaryHandGesture()` on watchOS 11+) and a ↶ `UndoEntryIntent` button when fresh. **inline:** text with the total. |
| `FavoritesWidget` | `accessoryRectangular` | watchOS 11+: `AccessoryWidgetGroup(label: { Label(totalText, systemImage: "drop.fill") }) { slot(0); slot(1); slot(2) }.accessoryWidgetGroupStyle(.circular)`. Each slot is a `Button(intent: QuickLogIntent)` with glyph and «500»; a missing slot is a `Link` to the app. watchOS 10: a static row of 3 glyphs plus a widgetURL. |

- **`recommendations()`** is mandatory on watchOS and lives in the shared provider, which delegates to `PlatformWidgetConfig`.
  - watchOS: `if #available(watchOS 26.0, *) { return [] }`. Otherwise return up to 12 presets, each `AppIntentRecommendation(intent: SelectPresetIntent(preset:), description: name)` where `name: String` is a plain String variable.
  - Favorites returns one recommendation: `Phrasebook.favoritesRecommendation` («Избранное»).
  - The iOS copy returns `[]`. The watch `#available` check lives only in the watch folder, because on iOS `#available(watchOS 26, *)` evaluates to true through the `*`.
- `watchTapMode == .confirm` renders the same layouts without `Button`; the root `widgetURL` then opens Confirm.
- The totals come from the watch store. That includes phone entries once they have arrived over WatchConnectivity or the HealthKit import.

---

## 11. Controls

- **Type:** a single `QuickLogControl` in `WidgetShared`, marked `@available(iOS 18.0, watchOS 26.0, *)` and wrapped in `#if compiler(>=6.2)`.

  ```swift
  AppIntentControlConfiguration(kind: WidgetKinds.logControl, intent: SelectPresetControlIntent.self) { configuration in
      let preset = PresetResolver.snapshot(presetID: configuration.preset?.id)   // `let` only, no if/switch
      ControlWidgetButton(action: QuickLogIntent(preset: preset, source: .control)) {
          Label(preset.title, systemImage: preset.symbolName)
      }
  }
  .displayName("Log drink")
  .description("Logs the chosen drink with one tap.")
  .promptsForUserConfiguration()
  ```
- **`SelectPresetControlIntent: ControlConfigurationIntent`** has `@Parameter var preset: DrinkPresetEntity?`. The parameter is optional so the control can be previewed; `nil` means the primary preset.
- **iPhone:** Control Center, the Lock Screen and the Action button. Several instances can each have a different preset. The intent never brings the app forward, so on watchOS 26 the control also appears on the watch and runs on the iPhone.
- **Watch (26+):** a native copy for Control Center, the Smart Stack and the Ultra Action button. It runs on the watch.
- **Ultra on watchOS 10/11:** the Action button can run the watch App Shortcut «Записать воду».

---

## 12. App Intents and Siri

### 12.1 Intents

| Intent | Targets | Discoverable | Parameters | Result |
|---|---|---|---|---|
| `QuickLogIntent` | all 4 | **false** | `presetID: String = "water-500"`, `beverageID: String = "water"`, `volumeML: Int = 500`, `sourceRaw: String = "widget"`; all have defaults and are always pre-filled | `.result()` |
| `UndoEntryIntent` | all 4 | false | `entryID: String = ""` | `.result()` |
| `SelectPresetIntent: WidgetConfigurationIntent` | all 4 | — | `preset: DrinkPresetEntity?` | — |
| `FavoritesConfigIntent: WidgetConfigurationIntent` | all 4 | — | `slot1…slot4: DrinkPresetEntity?` | — |
| `SelectPresetControlIntent: ControlConfigurationIntent` (iOS 18 / watchOS 26) | all 4 | — | `preset: DrinkPresetEntity?` | — |
| `LogWaterIntent` | apps | true | none; uses `siriWaterVolumeML` | dialog |
| `LogPresetIntent` | apps | true | `preset: DrinkPresetEntity` (required) | dialog |
| `LogBeverageIntent` | apps | true | `beverage: BeverageEntity` (required), `amountML: Int?` (10…3000; `nil` means the beverage's default volume) | dialog |
| `LogAmountIntent` | apps | true | `amountML: Int` (required, `requestValueDialog` «Сколько миллилитров?»), `beverage: BeverageEntity?` (`nil` means water) | dialog |
| `UndoLastDrinkIntent` | apps | true | none | dialog |
| `TodayTotalIntent` | apps | true | none | `ReturnsValue<Int>` (water mL) & dialog |

Rules:
- No intent declares `openAppWhenRun` or `supportedModes`, so all run without UI.
- Titles use `static let title: LocalizedStringResource = "…"`. Only the Siri-facing intents get a `description`, written in Apple's sample form.
- Entity and query type names are globally unique: `DrinkPresetQuery`, `BeverageQuery`. `typeDisplayRepresentation` is written as `TypeDisplayRepresentation(name:)`.
- Queries implement `entities(for:)`, `suggestedEntities()` (needed for parameterised phrases and for widget configuration), `entities(matching:)` and `defaultResult()`.
- After any catalog change, the app calls `SayoneShortcuts.updateAppShortcutParameters()`. It is also called in `App.init()` on both platforms.

### 12.2 App Shortcuts (6 of the 10 allowed; `SayoneShortcuts` in iOS app **and** watch app)

The key is the first English phrase. Every phrase contains `${applicationName}` exactly once and at most one parameter.

| Intent (shortTitle, symbol) | English phrases | Russian phrases |
|---|---|---|
| `LogWaterIntent` ("Log water"/«Записать воду», drop.fill) | Log water in ${applicationName} · Add water in ${applicationName} · ${applicationName} water | Запиши воду в ${applicationName} · Добавь воду в ${applicationName} · ${applicationName} запиши воду · ${applicationName} вода · Я выпил воды в ${applicationName} · Я выпила воды в ${applicationName} |
| `LogPresetIntent` ("Log preset"/«Записать пресет», star.fill) | Log ${preset} in ${applicationName} · Add ${preset} in ${applicationName} · ${applicationName} ${preset} | Запиши ${preset} в ${applicationName} · Добавь ${preset} в ${applicationName} · ${applicationName} ${preset} · ${applicationName} запиши ${preset} |
| `LogBeverageIntent` ("Log drink"/«Записать напиток», cup.and.saucer.fill) | Log a drink of ${beverage} in ${applicationName} · I drank ${beverage} with ${applicationName} | Запиши напиток ${beverage} в ${applicationName} · Выпил напиток ${beverage} в ${applicationName} · Выпила напиток ${beverage} в ${applicationName} |
| `LogAmountIntent` ("Custom amount"/«Свой объём», slider.horizontal.3) | Log a custom amount in ${applicationName} · Log a drink in ${applicationName} | Запиши объём в ${applicationName} · Запиши напиток в ${applicationName} · Добавь свой объём в ${applicationName} |
| `UndoLastDrinkIntent` ("Undo last"/«Отменить последнее», arrow.uturn.backward) | Undo last drink in ${applicationName} · Remove last drink in ${applicationName} | Отмени последний напиток в ${applicationName} · Удали последнюю запись в ${applicationName} · ${applicationName} отмена |
| `TodayTotalIntent` ("Today's total"/«Итог за день», chart.bar.fill) | How much did I drink today in ${applicationName} · ${applicationName} today's total | Сколько я выпил сегодня в ${applicationName} · Сколько я выпила сегодня в ${applicationName} · ${applicationName} сколько выпито · Итог за день в ${applicationName} |

- **Watch Siri:** there is no flexible matching on the watch, so the list includes the literal gendered forms. Presets can be renamed for voice (for example «пол-литра воды»), which makes «Запиши пол-литра воды в Сейон» an exact phrase.
- **Dialogs:** built at runtime by `Phrasebook` (ru/en, unit-tested) and returned as `.result(dialog: "\(message)")`. Examples:
  - «Записано: кола без сахара 330 мл. Сегодня 1,5 л из 2 л.»
  - «Отменено: вода 500 мл.»
  - «Нечего отменять.»
  - «Сегодня выпито 1,5 л из 2 л (75 %). Кофеин 95 мг.»
- **Discoverability:** `SiriTipView(intent: LogWaterIntent())` on both apps' Today screens. `ShortcutsLink()` only in the iOS Settings screen, which is an iOS-only folder.
- **No SiriKit:** no `com.apple.developer.siri`, no `NSSiriUsageDescription`, no Intents extension.

---

## 13. UI screens

### iPhone (`TabView`: Сегодня · История · Напитки · Настройки)

1. **Onboarding** (first run, 4 pages): welcome; «Подключить Здоровье» (request authorization; shows the result); «Дневная цель» (stepper 1000–5000, default 2000, with the note «цель задаёте вы»); «Виджеты и часы» (how to add the Home, Lock Screen and Control widgets, and a reminder to open the watch app and grant Health there too).
2. **Сегодня:**
   - A header ring (water vs goal), «1,2 л из 2 л», and a line with caffeine, sugar and kcal.
   - A **grid of preset tiles**, favourites first. A tap logs with `.sensoryFeedback(.success)` and shows the undo toast. A long-press context menu offers «Другой объём…», «Изменить пресет» and «В избранное / убрать».
   - A «Другое…» tile opens the Custom sheet.
   - Today's entries: time, glyph, name, volume, and an ⌚/📱 origin badge. Swipe deletes; «Изменить» means undo plus a new entry.
   - A Health banner when access is missing or entries are pending («3 записи ждут отправки в Здоровье · Повторить»).
   - `SiriTipView`.
3. **Custom log sheet:** a grid of beverages (built-in plus custom); a large volume value with a slider (10–1500, step 10) and chips 150/200/250/330/500/750/1000; a `DatePicker` (≤ now); toggles «Сохранить как пресет» and «в избранное»; a **Записать** button.
4. **История:** 30-day bars drawn with plain SwiftUI shapes (no Charts dependency). Tapping a day shows its entries (deletable).
5. **Напитки:**
   - Presets: a reorderable list with the ⭐ favourite toggle. The editor has beverage, volume, and a custom title with the hint «как вы будете называть его Siri».
   - Beverages: built-ins with editable nutrients and water %, plus custom beverages (name, symbol from about 12 options, tint, caffeine/kcal/sugar per 100 mL, water %, default volume, archive).
6. **Настройки:**
   - Goal.
   - Health: status, connect button, and the «Записывать кофеин/калории/сахар» toggle.
   - Часы: tap mode «Сразу / С подтверждением» and crown step.
   - Siri: the phrase list, `SiriTipView` and `ShortcutsLink`.
   - Widgets: a how-to.
   - **Диагностика:** App Group OK or fallback, pending count, last peer sync, last Health import, «Повторить синхронизацию», version.

### Watch (`NavigationStack` + `List`)

1. **First launch:** «Разрешить доступ к Здоровью» (request) with a «Позже» option.
2. **Today (root):**
   - Ring and «1,2 / 2 л».
   - A **big primary button** «+ Вода 0,5 л» (the first favourite), with `primaryHandGesture()` on watchOS 11+.
   - One-tap rows for the other presets.
   - «Другой объём» opens CrownVolumeView.
   - «Сегодня» opens the log list.
   - «Настройки».
   - After any log: a 4-second overlay «✓ +500 мл · Вода» with **Отменить**, plus `.sensoryFeedback(.success, trigger:)` and a reload of widget timelines.
3. **CrownVolumeView** (§8.2 F), presented as a `.sheet` so the List does not take the crown.
4. **ConfirmLogView** (from a deep link): glyph, title, crown-adjustable volume, **Записать** (primary, double tap) and «Отмена».
5. **LogListView:** today's entries with swipe-to-delete.
6. **Settings:** goal (crown), tap mode, Health status and button, sync status.

Watch presets are edited on the iPhone and synced. The watch has no text entry.

---

## 14. Localization

- `developmentLanguage: en`. `knownRegions` are en and ru, detected from the catalogs. The device language decides; Russian users get Russian and everyone else gets English.
- **String catalogs are generated from TSV**, so parallel engineers never hand-edit JSON:
  - `Localization/ui.tsv` (key, en, ru, comment) → `Shared/Resources/Localizable.xcstrings`, in all 4 targets.
  - `Localization/infoplist.tsv` → `Shared/Resources/InfoPlist.xcstrings`: `CFBundleDisplayName` (SayoneHealth in both languages) and the Health usage strings (ru: «SayoneHealth сохраняет выпитое (воду, кофеин, калории, сахар) в «Здоровье».» / «…читает ваши записи о напитках, чтобы показывать итоги дня.»).
  - `Localization/shortcuts.tsv` → `Shared/Intents/Siri/AppShortcuts.xcstrings`, in the apps only, using `stringSet` values per locale.

  `scripts/gen_strings.py --check` fails CI if a committed catalog differs from its TSV.
- **Static UI text** such as `Text("Today")`, intent titles, parameter titles, `requestValueDialog` and widget display names comes from the catalog. **Composed runtime text** comes from `SayoneCore.Phrasebook` and `VolumeFormatter`: dialogs, preset titles, built-in beverage names, volumes («1,5 л» vs «1.5 L»), accessibility labels, and the HealthKit FoodType. It is shown with `Text(verbatim:)`. This avoids format-specifier keys in catalogs and is testable on Linux.
- `AppLanguage.current` is `ru` if `Bundle.main.preferredLocalizations.first` starts with "ru", otherwise `en`. That holds in each process, including extensions, because every target carries both localizations.

---

## 15. Project generation, CI and build safety

### 15.1 `Config/Base.xcconfig`

```
BUNDLE_ID_PREFIX = com.sayoneone.sayonehealth
APP_GROUP_ID = group.$(BUNDLE_ID_PREFIX)
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
DEVELOPMENT_TEAM =
CODE_SIGN_STYLE = Automatic
SAYONE_EXTRA_FLAGS =            // e.g. SAYONE_NO_WC SAYONE_NO_WATCH_CONTROLS SAYONE_IOS_INTENT_IN_APP
#include? "Local.xcconfig"      // git-ignored: DEVELOPMENT_TEAM / prefix overrides for the tester
```

### 15.2 `project.yml` (abridged, follows the structure validated with XcodeGen 2.46.0)

```yaml
name: SayoneHealth
options:
  minimumXcodeGenVersion: 2.46.0
  xcodeVersion: "26.0"
  developmentLanguage: en
  createIntermediateGroups: true
  deploymentTarget: { iOS: "18.0", watchOS: "10.0" }
configFiles: { Debug: Config/Base.xcconfig, Release: Config/Base.xcconfig }
settings:
  base: { SWIFT_VERSION: "5.0", SWIFT_STRICT_CONCURRENCY: minimal }
packages:
  SayoneCore: { path: Packages/SayoneCore }
targets:
  SayoneHealth:
    type: application
    platform: iOS
    sources:
      - { path: iOS/App, excludes: ["**/*.md"] }
      - Shared/Platform
      - Shared/Components
      - Shared/Intents            # Core + Siri (+ AppShortcuts.xcstrings)
      - Shared/AppCore
      - Shared/Resources
    dependencies:
      - package: SayoneCore
      - target: SayoneHealthWidgets      # → Embed Foundation Extensions
      - target: SayoneHealthWatch        # → Embed Watch Content ($(CONTENTS_FOLDER_PATH)/Watch)
    info:
      path: Config/Plists/App-Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: false }
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        CFBundleURLTypes: [{ CFBundleURLName: $(BUNDLE_ID_PREFIX), CFBundleURLSchemes: [sayonehealth] }]
        INAlternativeAppNames: [{ INAlternativeAppName: Sayone }, { INAlternativeAppName: Сейон }, { INAlternativeAppName: Сэйон }]
        NSHealthShareUsageDescription: "SayoneHealth reads your drink records to show daily totals."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
        SHAppGroupIdentifier: $(APP_GROUP_ID)
    entitlements:
      path: Config/Entitlements/App.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX)
        TARGETED_DEVICE_FAMILY: "1"
        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) SAYONE_APP $(SAYONE_EXTRA_FLAGS)"
    scheme: {}
  SayoneHealthWidgets:
    type: app-extension
    platform: iOS
    sources: [iOS/Widgets, WidgetShared, Shared/Platform, Shared/Components, Shared/Intents/Core, Shared/Resources]
    dependencies: [{ package: SayoneCore }]
    info: { path: Config/Plists/Widgets-Info.plist, properties: { NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }, ...same version/Health/SHAppGroupIdentifier keys } }
    entitlements: { path: Config/Entitlements/Widgets.entitlements, properties: { ...same 3 keys } }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).widgets, TARGETED_DEVICE_FAMILY: "1", SKIP_INSTALL: YES,
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) SAYONE_WIDGET_EXT $(SAYONE_EXTRA_FLAGS)" } }
    scheme: {}
  SayoneHealthWatch:
    type: application
    platform: watchOS
    sources: [watchOS/App, Shared/Platform, Shared/Components, Shared/Intents, Shared/AppCore, Shared/Resources]
    dependencies: [{ package: SayoneCore }, { target: SayoneHealthWatchWidgets }]
    info:
      path: Config/Plists/Watch-Info.plist
      properties:
        WKApplication: true
        WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX)
        WKRunsIndependentlyOfCompanionApp: true
        # plus: display name, versions, URL types, INAlternativeAppNames, Health strings, SHAppGroupIdentifier; NO NSExtension
    entitlements: { path: Config/Entitlements/Watch.entitlements, properties: { ...same 3 keys } }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp,
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) SAYONE_APP $(SAYONE_EXTRA_FLAGS)" } }
    scheme: {}
  SayoneHealthWatchWidgets:
    type: app-extension
    platform: watchOS
    sources: [watchOS/Widgets, WidgetShared, Shared/Platform, Shared/Components, Shared/Intents/Core, Shared/Resources]
    dependencies: [{ package: SayoneCore }]
    info: { path: Config/Plists/WatchWidgets-Info.plist, properties: { NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }, ... } }
    entitlements: { path: Config/Entitlements/WatchWidgets.entitlements, properties: { ...same 3 keys } }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp.widgets,
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) SAYONE_WIDGET_EXT $(SAYONE_EXTRA_FLAGS)" } }
    scheme: {}
```

- Both apps have an `Assets.xcassets` with a single-size 1024 `AppIcon` (`"platform": "ios"` or `"watchos"`). The PNG is generated by the stdlib-only `scripts/make_icon.py` (zlib PNG writer, drop glyph) and committed, because the XcodeGen presets set `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` and the icon set must exist.
- `ARCHS` is never set.
- The generated `SayoneHealth.xcodeproj`, plists and entitlements are **committed**, so the tester can open the project without XcodeGen. CI regenerates and runs `git diff --stat`, reported as a warning only.

### 15.3 CI (`.github/workflows/ci.yml`; public repo, standard runners only)

```yaml
on: { push: { branches: [main, 'claude/**'] }, pull_request: {}, workflow_dispatch: {} }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  linux:                                  # ~1 min, no macOS minutes
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v5
      - run: python3 scripts/gen_strings.py --check && python3 scripts/lint_repo.py
      - run: swift test --package-path Packages/SayoneCore
  apple:                                  # one leg per target → every target's errors in ONE round-trip
    runs-on: macos-26
    timeout-minutes: 45
    strategy:
      fail-fast: false
      matrix:
        include:
          - { scheme: SayoneHealth,             dest: 'generic/platform=iOS Simulator' }      # also builds embedded watch app
          - { scheme: SayoneHealthWatch,        dest: 'generic/platform=watchOS Simulator' }
          - { scheme: SayoneHealthWidgets,      dest: 'generic/platform=iOS Simulator' }
          - { scheme: SayoneHealthWatchWidgets, dest: 'generic/platform=watchOS Simulator' }
    steps:
      - uses: actions/checkout@v5
      - run: |   # newest Xcode 26.x by glob, print diagnostics
          X=$(ls -d /Applications/Xcode_26*.app | sort -V | tail -1); sudo xcode-select -s "$X"
          xcodebuild -version; xcodebuild -showsdks | grep -E 'iphone|watch'
      - run: |   # pinned XcodeGen release zip
          curl -fsSL -o $RUNNER_TEMP/xg.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
          unzip -q $RUNNER_TEMP/xg.zip -d $RUNNER_TEMP && $RUNNER_TEMP/xcodegen/bin/xcodegen generate
          git diff --stat -- SayoneHealth.xcodeproj || true
      - run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme ${{ matrix.scheme }} -configuration Debug \
            -destination '${{ matrix.dest }}' -derivedDataPath $RUNNER_TEMP/dd \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            2>&1 | tee build.log | xcbeautify --renderer github-actions
      - if: matrix.scheme == 'SayoneHealth'
        run: python3 scripts/check_appintents.py build.log $RUNNER_TEMP/dd   # fails on 'No AppIntents metadata have been exported',
                                                                            # metadataprocessor warnings; asserts 6 autoShortcuts in app
      - if: failure()
        uses: actions/upload-artifact@v4
        with: { name: log-${{ matrix.scheme }}, path: build.log }
  device-unsigned:                        # arm64_32 / device-only issues; non-blocking until first green
    runs-on: macos-26
    continue-on-error: true
    steps: [ ...same setup..., xcodebuild -scheme SayoneHealth -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO ... ]
  xcode27:                                # user devices may need Xcode 27 locally
    runs-on: xcode-27
    continue-on-error: true
    steps: [ ...same setup, SayoneHealth scheme, iOS Simulator... ]
```

`scripts/check_appintents.py` asserts:
- `SayoneHealth.app/Metadata.appintents/extract.actionsdata` and `…/Watch/SayoneHealthWatch.app/Metadata.appintents/extract.actionsdata` each have `autoShortcuts` covering the 6 intents, with at most 10;
- the widget `.appex` files have no `autoShortcuts`.

### 15.4 Build-safety program

1. **Linux preflight before every push** (the agent's local loop):
   - `swift test` for SayoneCore;
   - generate the project with the Linux-built XcodeGen 2.46.0 (`USER=ci`);
   - grep the pbxproj for exactly one "Embed Watch Content" (`dstSubfolderSpec = 16`) and two "Embed Foundation Extensions" phases, and check 4 shared schemes;
   - `plistlib` load of every plist and entitlements file;
   - `gen_strings --check`;
   - `lint_repo.py`.
2. **`lint_repo.py` forbidden patterns** (path-scoped regex):
   - In `watchOS/**`, `WidgetShared/**`, `Shared/**`: `.systemSmall|.systemMedium|.systemLarge`, `promptsForUserConfiguration` (except `iOS/Widgets` and the control file), `ShortcutsLink`, `LiveActivityIntent` outside `#if os(iOS)`, `handleAuthorizationForExtension`.
   - In `iOS/**`, `WidgetShared/**`, `Shared/**`: `.accessoryCorner`, `digitalCrownRotation`, `AccessoryWidgetGroup`, `handGestureShortcut`, `#available(watchOS`.
   - Everywhere: `openAppWhenRun`, `supportedModes`, `allowedExecutionTargets`, `earliestAuthorizedSampleDate`, `healthDataAccessRequest`, `HKCorrelation`, `AppIntentsPackage`, `com.apple.developer.siri`, `aps-environment`, `icloud`, `SWIFT_DEFAULT_ACTOR_ISOLATION`, `requestConfirmation`.
   - `requestAuthorization(` only inside `HealthService.swift`.
   - `#if os(` only in whitelisted files.
   - Every `switch family` must contain `default:`.
   - Each AppIntentTimelineProvider must declare `recommendations()`.
   - Entitlements may contain only the 3 allowed keys.
3. **Skeleton first:** the first macOS push is a hello-world for all 4 targets plus the package plus one intent. Features then land in small green increments (§18).
4. **Compile-hazard checklist** (reviewed on every PR):
   - `default:` in family switches;
   - `recommendations()` in the watch provider;
   - no `.promptsForUserConfiguration()` on watch widgets;
   - control closures contain only `let` plus one `ControlWidgetButton`;
   - watch controls wrapped in `#if compiler(>=6.2)` and `@available(iOS 18.0, watchOS 26.0, *)`;
   - `if #available(watchOS 11.0, *)` around `AccessoryWidgetGroup` and `handGestureShortcut`;
   - `import AppIntents` in every file that uses `Button(intent:)` or `ControlWidgetButton`;
   - `static let` for intent metadata;
   - explicit `TypeDisplayRepresentation(name:)`;
   - unique query names;
   - `Double` binding for the crown;
   - `Set<HKSampleType>` / `Set<HKObjectType>` spelled out;
   - `catch let e as HKError where e.code == .errorNoData`;
   - WCSession iOS-only methods inside `#if os(iOS)`;
   - no Swift features newer than 5.9 in the package (it must compile with Swift 6.2 in Xcode 26 and 6.4 on Linux).

---

## 16. File tree

```
sayonehealth/
├── project.yml
├── SayoneHealth.xcodeproj/                 (generated, committed)
├── Config/
│   ├── Base.xcconfig        (Local.xcconfig git-ignored)
│   ├── Plists/  App-Info.plist · Widgets-Info.plist · Watch-Info.plist · WatchWidgets-Info.plist   (generated)
│   └── Entitlements/  App · Widgets · Watch · WatchWidgets .entitlements                          (generated)
├── Packages/SayoneCore/
│   ├── Package.swift
│   ├── Sources/SayoneCore/
│   │   ├── Models/      Enums.swift · Beverage.swift · DrinkPreset.swift · DrinkEntry.swift · AppSettings.swift · StoreState.swift
│   │   ├── Catalog/     BuiltinCatalog.swift
│   │   ├── Logic/       NutrientMath.swift · DayMath.swift · Aggregator.swift · LoggingPolicy.swift · LogPlanner.swift
│   │   ├── Health/      HealthSamplePlanner.swift · HealthImportAssembler.swift
│   │   ├── Sync/        SyncEnvelope.swift · SyncMerge.swift
│   │   ├── Store/       FileDrinkStore.swift · FileLock.swift · StoreMaintenance.swift
│   │   └── Presentation/ VolumeFormatter.swift · Phrasebook.swift · WidgetSnapshot.swift · DeepLink.swift · WidgetKinds.swift
│   └── Tests/SayoneCoreTests/  (math, aggregation, planner/dedupe/undo, merge, import assembly, sample specs, formatter ru/en,
│                                deep links, store round-trip + concurrent flock writers, tolerant decoding, prune)
├── Shared/
│   ├── Platform/    AppEnvironment.swift · HealthKitTypes.swift · HealthService.swift · DrinkLogger.swift ·
│   │                WidgetRefresher.swift · PresetResolver.swift · Log.swift
│   ├── Components/  ProgressRing.swift · BeverageGlyph.swift · BeverageTint+Color.swift
│   ├── Intents/
│   │   ├── Core/    DrinkPresetEntity.swift · BeverageEntity.swift · QuickLogIntent.swift · UndoEntryIntent.swift ·
│   │   │            SelectPresetIntent.swift · FavoritesConfigIntent.swift · SelectPresetControlIntent.swift
│   │   └── Siri/    LogWaterIntent.swift · LogPresetIntent.swift · LogBeverageIntent.swift · LogAmountIntent.swift ·
│   │                UndoLastDrinkIntent.swift · TodayTotalIntent.swift · SayoneShortcuts.swift · AppShortcuts.xcstrings (gen)
│   ├── AppCore/     AppModel.swift · PeerSync.swift · HealthImporter.swift · DeepLinkRouter.swift
│   └── Resources/   Localizable.xcstrings (gen) · InfoPlist.xcstrings (gen)
├── WidgetShared/    WidgetEntries.swift · QuickLogProvider.swift · QuickLogWidget.swift · FavoritesProvider.swift ·
│                    FavoritesWidget.swift · QuickLogControl.swift
├── iOS/
│   ├── App/         SayoneHealthApp.swift · RootView.swift · Today/(TodayView, PresetTile, EntryRow, UndoToast, HealthBanner) ·
│   │                Log/CustomLogSheet.swift · History/HistoryView.swift · Drinks/(DrinksView, PresetEditor, BeverageEditor) ·
│   │                Settings/(SettingsView, SiriSection, DiagnosticsView) · Onboarding/OnboardingView.swift · Assets.xcassets
│   └── Widgets/     SayoneWidgetBundle.swift · PlatformWidgetConfig.swift · QuickLogView.swift · FavoritesView.swift
├── watchOS/
│   ├── App/         SayoneWatchApp.swift · WatchTodayView.swift · CrownVolumeView.swift · ConfirmLogView.swift ·
│   │                LogListView.swift · WatchSettingsView.swift · UndoOverlay.swift · HandGesture.swift ·
│   │                WatchOnboardingView.swift · Assets.xcassets
│   └── Widgets/     SayoneWatchWidgetBundle.swift · PlatformWidgetConfig.swift · QuickLogView.swift · FavoritesView.swift
├── Localization/    ui.tsv · infoplist.tsv · shortcuts.tsv
├── scripts/         preflight.sh · lint_repo.py · gen_strings.py · check_appintents.py · make_icon.py
├── docs/            design/rubric.md · TESTING.ru.md (tomorrow's checklist) · ARCHITECTURE.md
└── .github/workflows/ ci.yml · probe.yml
```

---

## 17. Shared Swift type contracts (frozen interfaces for parallel work)

### 17.1 SayoneCore (public API; bodies are the package owner's job)

```swift
// swift-tools-version: 5.9   — Package.swift
import PackageDescription
let package = Package(
    name: "SayoneCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "SayoneCore", targets: ["SayoneCore"])],
    targets: [.target(name: "SayoneCore"),
              .testTarget(name: "SayoneCoreTests", dependencies: ["SayoneCore"])])
```

```swift
import Foundation

// MARK: Enums
public enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case en, ru
    public init(preferredLocalizations: [String])
}
public enum BeverageKind: String, Codable, Sendable, CaseIterable {
    case water, sparklingWater, colaZero, cola, coffee, tea, juice, milk, custom
}
public enum BeverageTint: String, Codable, Sendable, CaseIterable {
    case blue, cyan, graphite, red, brown, amber, orange, green, purple, gray
}
public enum DeviceOrigin: String, Codable, Sendable { case phone, watch }
public enum LogSource: String, Codable, Sendable { case app, widget, control, siri, deepLink, imported }
public enum HealthSyncState: String, Codable, Sendable { case pending, saved, pendingDelete, deleted, remote, skipped }
public enum WatchTapMode: String, Codable, Sendable, CaseIterable { case instant, confirm }

// MARK: Models (all with tolerant Decodable: decodeIfPresent + defaults)
public struct NutrientProfile: Codable, Hashable, Sendable {
    public var caffeineMGPer100ML: Double
    public var kcalPer100ML: Double
    public var sugarGPer100ML: Double
    public init(caffeineMGPer100ML: Double = 0, kcalPer100ML: Double = 0, sugarGPer100ML: Double = 0)
}
public struct NutrientAmounts: Codable, Hashable, Sendable {
    public var waterML: Double
    public var caffeineMG: Double
    public var kcal: Double
    public var sugarG: Double
    public init(waterML: Double = 0, caffeineMG: Double = 0, kcal: Double = 0, sugarG: Double = 0)
    public static let zero: NutrientAmounts
    public static func + (lhs: NutrientAmounts, rhs: NutrientAmounts) -> NutrientAmounts
}
public struct Beverage: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: BeverageKind
    public var customName: String?
    public var symbolName: String
    public var tint: BeverageTint
    public var nutrients: NutrientProfile
    public var waterPercent: Int
    public var defaultVolumeML: Int
    public var isArchived: Bool
    public var modifiedAt: Date
    public init(id: String, kind: BeverageKind, customName: String? = nil, symbolName: String, tint: BeverageTint,
                nutrients: NutrientProfile = NutrientProfile(), waterPercent: Int = 100, defaultVolumeML: Int = 250,
                isArchived: Bool = false, modifiedAt: Date = Date(timeIntervalSince1970: 0))
    public func displayName(_ language: AppLanguage) -> String
}
public struct DrinkPreset: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var beverageID: String
    public var volumeML: Int
    public var customTitle: String?
    public var isFavorite: Bool
    public var sortIndex: Int
    public var isDeleted: Bool
    public var modifiedAt: Date
    public init(id: String, beverageID: String, volumeML: Int, customTitle: String? = nil, isFavorite: Bool = false,
                sortIndex: Int, isDeleted: Bool = false, modifiedAt: Date = Date(timeIntervalSince1970: 0))
}
public struct DrinkEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var beverageID: String
    public var beverageKind: BeverageKind
    public var beverageName: String
    public var symbolName: String
    public var volumeML: Int
    public var amounts: NutrientAmounts
    public var presetID: String?
    public var origin: DeviceOrigin
    public var source: LogSource
    public var health: HealthSyncState
    public var healthVersion: Int
    public var isDeleted: Bool
    public var modifiedAt: Date
    public var lastHealthError: String?
}
public struct AppSettings: Codable, Hashable, Sendable {
    public var dailyGoalML: Int                 // 2000
    public var writeNutrientsToHealth: Bool     // true
    public var watchTapMode: WatchTapMode       // .instant
    public var crownStepML: Int                 // 50
    public var lastCustomVolumeML: Int          // 300
    public var lastCustomBeverageID: String     // "water"
    public var siriWaterVolumeML: Int           // 500
    public var modifiedAt: Date
    public init()
}
public struct StoreState: Codable, Equatable, Sendable {
    public static let currentSchema: Int        // 1
    public var schemaVersion: Int
    public var beverages: [Beverage]
    public var presets: [DrinkPreset]
    public var settings: AppSettings
    public var entries: [DrinkEntry]
    public var peerCursor: Date?
    public var lastHealthImportAt: Date?
    public var lastPeerReceiveAt: Date?
    public static func seeded() -> StoreState
    public func beverage(id: String) -> Beverage?
    public func preset(id: String) -> DrinkPreset?
    public var activeBeverages: [Beverage] { get }      // !isArchived
    public var activePresets: [DrinkPreset] { get }     // !isDeleted, by sortIndex
    public var favoritePresets: [DrinkPreset] { get }   // active && isFavorite, by sortIndex
    public var primaryPreset: DrinkPreset { get }       // first favourite → first active → builtin water-500
    public func liveEntries(in interval: DateInterval) -> [DrinkEntry]   // !isDeleted, newest first
    public var pendingHealthCount: Int { get }
}
public enum BuiltinCatalog {
    public static let beverages: [Beverage]
    public static let presets: [DrinkPreset]
    public static let fallbackBeverageID: String   // "water"
    public static let fallbackPresetID: String     // "water-500"
}

// MARK: Logic
public enum NutrientMath {
    public static func amounts(for beverage: Beverage, volumeML: Int) -> NutrientAmounts
}
public enum DayMath {
    public static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval
    public static func startOfNextDay(after date: Date, calendar: Calendar = .current) -> Date
}
public struct BeverageTotal: Equatable, Sendable {
    public let beverageID: String
    public let name: String
    public let symbolName: String
    public let tint: BeverageTint
    public let volumeML: Int
    public let count: Int
}
public struct DaySummary: Equatable, Sendable {
    public let interval: DateInterval
    public let entryCount: Int
    public let volumeML: Int
    public let waterML: Int
    public let caffeineMG: Double
    public let kcal: Double
    public let sugarG: Double
    public let byBeverage: [BeverageTotal]
    public func progress(goalML: Int) -> Double          // 0...1, clamped
}
public enum Aggregator {
    public static func summary(of entries: [DrinkEntry], in interval: DateInterval) -> DaySummary
    public static func today(_ state: StoreState, now: Date = Date(), calendar: Calendar = .current) -> DaySummary
    public static func lastDays(_ count: Int, state: StoreState, now: Date = Date(), calendar: Calendar = .current) -> [DaySummary]
}
public enum LoggingPolicy {
    public static let duplicateTapWindow: TimeInterval      // 2
    public static let widgetUndoWindow: TimeInterval        // 600
    public static let appUndoToastDuration: TimeInterval    // 6
    public static let siriUndoWindow: TimeInterval          // 10_800
    public static let volumeRangeML: ClosedRange<Int>       // 10...3000
    public static let retentionDays: Int                    // 60
    public static let tombstoneRetentionDays: Int           // 7
    public static let healthImportDays: Int                 // 2
    public static let maxWatchRecommendations: Int          // 12
}
public struct LogRequest: Equatable, Sendable {
    public var presetID: String?
    public var beverageID: String
    public var volumeML: Int
    public var date: Date
    public var source: LogSource
    public init(presetID: String?, beverageID: String, volumeML: Int, date: Date = Date(), source: LogSource)
}
public enum LogDecision: Equatable, Sendable { case appended(DrinkEntry), duplicateOf(DrinkEntry) }
public enum UndoDecision: Equatable, Sendable {
    case notFound
    case deletedNoHealthWork(DrinkEntry)
    case needsHealthDelete(DrinkEntry)
    case tombstonedRemote(DrinkEntry)
}
public enum LogPlanner {
    /// Resolves preset → current beverage/volume (falls back to request values), clamps, dedupes, snapshots, appends (.pending).
    public static func apply(_ request: LogRequest, to state: inout StoreState, origin: DeviceOrigin,
                             language: AppLanguage, newID: UUID = UUID()) -> LogDecision
    public static func undo(entryID: UUID, in state: inout StoreState, localOrigin: DeviceOrigin, now: Date = Date()) -> UndoDecision
    public static func lastUndoable(in state: StoreState, now: Date = Date(), within window: TimeInterval) -> DrinkEntry?
    public static func markHealth(_ entryID: UUID, _ newState: HealthSyncState, error: String?,
                                  in state: inout StoreState, now: Date = Date())
}
public enum StoreMaintenance {
    public static func prune(_ state: inout StoreState, now: Date = Date())
}

// MARK: Health planning (pure)
public enum HealthQuantityKind: String, Codable, Sendable, CaseIterable { case water, caffeine, energy, sugar } // mL, mg, kcal, g
public enum HealthMetadataKeys {
    public static let entryID: String        // "SayoneEntryID"
    public static let beverageID: String     // "SayoneBeverageID"
    public static let beverageKind: String   // "SayoneBeverageKind"
    public static let origin: String         // "SayoneOrigin"
    public static let volumeML: String       // "SayoneVolumeML"
}
public struct HealthSampleSpec: Equatable, Sendable {
    public var kind: HealthQuantityKind
    public var value: Double
    public var date: Date
    public var syncIdentifier: String         // "<uuid>.<kind>"
    public var syncVersion: Int
    public var foodType: String
    public var stringMetadata: [String: String]
    public var numberMetadata: [String: Double]
}
public enum HealthSamplePlanner {
    public static func specs(for entry: DrinkEntry, includeNutrients: Bool) -> [HealthSampleSpec]
    public static func syncIdentifier(entryID: UUID, kind: HealthQuantityKind) -> String
}
public struct ImportedSampleFields: Equatable, Sendable {
    public var kind: HealthQuantityKind
    public var value: Double
    public var date: Date
    public var strings: [String: String]
    public var numbers: [String: Double]
    public init(kind: HealthQuantityKind, value: Double, date: Date, strings: [String: String], numbers: [String: Double])
}
public struct ImportedHealthEntry: Equatable, Sendable {
    public var entryID: UUID
    public var date: Date
    public var origin: DeviceOrigin
    public var beverageID: String
    public var beverageKind: BeverageKind
    public var beverageName: String
    public var volumeML: Int
    public var amounts: NutrientAmounts
}
public enum HealthImportAssembler {
    public static func assemble(_ samples: [ImportedSampleFields]) -> [ImportedHealthEntry]
}

// MARK: Sync (pure)
public struct SyncEnvelope: Codable, Equatable, Sendable {
    public static let currentSchema: Int      // 1
    public var schemaVersion: Int
    public var sender: DeviceOrigin
    public var sentAt: Date
    public var entries: [DrinkEntry]
    public var beverages: [Beverage]
    public var presets: [DrinkPreset]
    public var settings: AppSettings?
    public init(sender: DeviceOrigin, sentAt: Date, entries: [DrinkEntry], beverages: [Beverage],
                presets: [DrinkPreset], settings: AppSettings?)
    public func encoded() throws -> Data
    public static func decoded(from data: Data) throws -> SyncEnvelope
}
public struct MergeReport: Equatable, Sendable {
    public var entriesInserted: Int
    public var entriesUpdated: Int
    public var catalogChanged: Bool
    public var settingsChanged: Bool
    public var healthDeletesNeeded: [UUID]
    public var isEmpty: Bool { get }
}
public enum SyncMerge {
    public static func outgoing(from state: StoreState, sender: DeviceOrigin, changedSince cursor: Date?, now: Date = Date()) -> SyncEnvelope
    public static func fullRecent(from state: StoreState, sender: DeviceOrigin, days: Int = 3, now: Date = Date()) -> SyncEnvelope
    public static func apply(_ envelope: SyncEnvelope, to state: inout StoreState, localOrigin: DeviceOrigin) -> MergeReport
    public static func applyImported(_ imported: [ImportedHealthEntry], to state: inout StoreState, localOrigin: DeviceOrigin) -> MergeReport
}

// MARK: Store
public enum StoreError: Error, Equatable { case lockUnavailable(String), writeFailed(String) }
public final class FileDrinkStore {
    public let fileURL: URL
    public init(directory: URL, fileName: String = "sayone-store-v1.json")
    public func read() -> StoreState                      // never throws; seeds on missing/corrupt
    @discardableResult
    public func mutate<T>(_ body: (inout StoreState) throws -> T) throws -> T   // flock(LOCK_EX) + prune + atomic write
    public func modificationDate() -> Date?
}

// MARK: Presentation (pure)
public enum VolumeFormatter {
    public static func full(_ ml: Int, _ language: AppLanguage) -> String                 // "500 мл" · "1,5 л" / "500 ml" · "1.5 L"
    public static func compact(_ ml: Int, _ language: AppLanguage) -> String              // "500" · "1,5 л"
    public static func delta(_ ml: Int, _ language: AppLanguage) -> String                // "+500"
    public static func progress(_ ml: Int, goalML: Int, _ language: AppLanguage) -> String // "1,2 / 2 л"
}
public enum Phrasebook {
    public static func beverageName(_ kind: BeverageKind, _ language: AppLanguage) -> String
    public static func presetTitle(beverageName: String, volumeML: Int, _ language: AppLanguage) -> String
    public static func logged(name: String, volumeML: Int, todayWaterML: Int, goalML: Int, healthOK: Bool, _ language: AppLanguage) -> String
    public static func duplicateIgnored(_ language: AppLanguage) -> String
    public static func undone(name: String, volumeML: Int, _ language: AppLanguage) -> String
    public static func nothingToUndo(_ language: AppLanguage) -> String
    public static func todayTotal(_ summary: DaySummary, goalML: Int, _ language: AppLanguage) -> String
    public static func favoritesRecommendation(_ language: AppLanguage) -> String
    public static func logButtonAccessibility(title: String, _ language: AppLanguage) -> String
}
public struct PresetSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var beverageID: String
    public var title: String
    public var volumeML: Int
    public var symbolName: String
    public var tint: BeverageTint
    public init(id: String, beverageID: String, title: String, volumeML: Int, symbolName: String, tint: BeverageTint)
}
public struct LastLogSnapshot: Equatable, Sendable {
    public var entryID: UUID
    public var title: String
    public var volumeML: Int
    public var date: Date
    public var isLocal: Bool
}
public struct WidgetSnapshot: Equatable, Sendable {
    public var date: Date
    public var todayWaterML: Int
    public var goalML: Int
    public var progress: Double
    public var caffeineMG: Double
    public var lastLog: LastLogSnapshot?        // nil when older than widgetUndoWindow at `date`
    public var tapMode: WatchTapMode
    public var needsHealthAccess: Bool
    public var language: AppLanguage
}
public enum WidgetSnapshotBuilder {
    public static func preset(id: String?, in state: StoreState, _ language: AppLanguage) -> PresetSnapshot   // nil/unknown → primary
    public static func presets(_ state: StoreState, _ language: AppLanguage) -> [PresetSnapshot]
    public static func favorites(slotIDs: [String?], in state: StoreState, count: Int, _ language: AppLanguage) -> [PresetSnapshot]
    public static func snapshot(of state: StoreState, at date: Date, needsHealthAccess: Bool,
                                _ language: AppLanguage, calendar: Calendar = .current) -> WidgetSnapshot
    public static func timelineDates(now: Date, lastLogDate: Date?, calendar: Calendar = .current) -> [Date]
}
public enum DeepLink: Equatable, Sendable {
    case today
    case confirm(presetID: String)
    case custom(beverageID: String?)
    case history
    public static let scheme: String            // "sayonehealth"
    public init?(url: URL)
    public var url: URL { get }
}
public enum WidgetKinds {
    public static let quickLog: String          // "SayoneQuickLog"
    public static let favorites: String         // "SayoneFavorites"
    public static let logControl: String        // "SayoneLogControl"
}
```

### 17.2 Shared/Platform (Apple; all 4 targets)

```swift
import Foundation
import HealthKit
import WidgetKit
import os
import SayoneCore

enum AppGroup {
    static var identifier: String { get }        // Info.plist SHAppGroupIdentifier ?? "group.com.sayoneone.sayonehealth"
    static var containerURL: URL { get }         // .../SayoneStore ; falls back to Application Support
    static var isShared: Bool { get }
}
enum StoreProvider { static let shared: FileDrinkStore }
extension DeviceOrigin { static var current: DeviceOrigin { get } }     // #if os(watchOS) .watch #else .phone
extension AppLanguage { static var current: AppLanguage { get } }        // Bundle.main.preferredLocalizations

extension HealthQuantityKind {
    var quantityType: HKQuantityType { get }     // HKQuantityType(.dietaryWater) …
    var unit: HKUnit { get }                     // .literUnit(with: .milli), .gramUnit(with: .milli), .kilocalorie(), .gram()
}
enum HealthTypes {
    static let share: Set<HKSampleType>
    static let read: Set<HKObjectType>
}
enum HealthAccessStatus: Equatable { case unavailable, notDetermined, denied, authorized }   // based on water sharing status
enum HealthWriteResult: Equatable { case saved([HealthQuantityKind]), nothingToWrite, notAuthorized }

final class HealthService {
    static let shared: HealthService
    let store: HKHealthStore
    func accessStatus() -> HealthAccessStatus
    func canWrite(_ kind: HealthQuantityKind) -> Bool
    #if SAYONE_APP
    func requestAuthorization() async throws
    #endif
    func save(_ specs: [HealthSampleSpec]) async throws -> HealthWriteResult        // filters by canWrite; one save([..])
    func deleteSamples(entryID: UUID) async throws -> Int
    func hasSamples(entryID: UUID) async throws -> Bool
    func fetchOwnSamples(since: Date) async throws -> [ImportedSampleFields]
}

struct LogOutcome {
    let entry: DrinkEntry
    let wasDuplicate: Bool
    let today: DaySummary
    let goalML: Int
    let spokenConfirmation: String               // Phrasebook.logged / duplicateIgnored
}
enum UndoOutcome: Equatable { case undone(DrinkEntry), nothingToUndo, storeFailed }
struct FlushReport: Equatable {
    var saved: Int = 0
    var deleted: Int = 0
    var stillPending: Int = 0
    var stoppedBecauseLocked: Bool = false
}
enum DrinkLogger {
    static func log(_ request: LogRequest) async -> LogOutcome?       // nil only when the store write failed
    static func logPreset(id presetID: String, fallbackBeverageID: String, fallbackVolumeML: Int,
                          source: LogSource) async -> LogOutcome?
    static func undo(entryID: UUID) async -> UndoOutcome
    static func undoLast(within window: TimeInterval) async -> UndoOutcome
    static func flushPendingHealth() async -> FlushReport
    static func today() -> (summary: DaySummary, goalML: Int)
}
enum WidgetRefresher {
    static func reloadAll()          // WidgetCenter.shared.reloadAllTimelines()
    static func catalogChanged()     // reloadAll() + (watchOS) invalidateConfigurationRecommendations()
}
enum PresetResolver {
    static func snapshot(presetID: String?) -> PresetSnapshot
    static func all() -> [PresetSnapshot]
    static func favorites(slotIDs: [String?], count: Int) -> [PresetSnapshot]
    static func widgetSnapshot(at date: Date) -> WidgetSnapshot
}
enum Log {
    static let store: Logger
    static let health: Logger
    static let intents: Logger
    static let widgets: Logger
    static let sync: Logger
}
```

### 17.3 Shared/Intents/Core (all 4 targets)

```swift
import AppIntents
import SayoneCore

struct DrinkPresetEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink preset")
    static let defaultQuery = DrinkPresetQuery()
    let id: String
    let title: String
    let beverageID: String
    let volumeML: Int
    let symbolName: String
    let tintRaw: String
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: DisplayRepresentation.Image(systemName: symbolName))
    }
    init(_ snapshot: PresetSnapshot)
    var snapshot: PresetSnapshot { get }
}
struct DrinkPresetQuery: EntityStringQuery {
    func entities(for identifiers: [DrinkPresetEntity.ID]) async throws -> [DrinkPresetEntity]
    func suggestedEntities() async throws -> [DrinkPresetEntity]
    func entities(matching string: String) async throws -> [DrinkPresetEntity]
    func defaultResult() async -> DrinkPresetEntity?            // primary preset
}
struct BeverageEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink")
    static let defaultQuery = BeverageQuery()
    let id: String
    let name: String
    let symbolName: String
    let defaultVolumeML: Int
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(systemName: symbolName))
    }
}
struct BeverageQuery: EntityStringQuery {
    func entities(for identifiers: [BeverageEntity.ID]) async throws -> [BeverageEntity]
    func suggestedEntities() async throws -> [BeverageEntity]
    func entities(matching string: String) async throws -> [BeverageEntity]
    func defaultResult() async -> BeverageEntity?               // water
}

struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick log drink"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Preset ID", default: "water-500") var presetID: String
    @Parameter(title: "Drink ID", default: "water") var beverageID: String
    @Parameter(title: "Volume (ml)", default: 500) var volumeML: Int
    @Parameter(title: "Source", default: "widget") var sourceRaw: String
    init() {}
    init(preset: PresetSnapshot, source: LogSource)
    func perform() async throws -> some IntentResult             // DrinkLogger.logPreset(...) then .result()
}
struct UndoEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo drink"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Entry ID", default: "") var entryID: String
    init() {}
    init(entryID: UUID)
    func perform() async throws -> some IntentResult
}
struct SelectPresetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose drink"
    @Parameter(title: "Drink") var preset: DrinkPresetEntity?
    init() {}
    init(preset: DrinkPresetEntity?)
}
struct FavoritesConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose favourites"
    @Parameter(title: "Button 1") var slot1: DrinkPresetEntity?
    @Parameter(title: "Button 2") var slot2: DrinkPresetEntity?
    @Parameter(title: "Button 3") var slot3: DrinkPresetEntity?
    @Parameter(title: "Button 4") var slot4: DrinkPresetEntity?
    init() {}
    var slotIDs: [String?] { get }
}
#if compiler(>=6.2)
@available(iOS 18.0, watchOS 26.0, *)
struct SelectPresetControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose drink"
    @Parameter(title: "Drink") var preset: DrinkPresetEntity?
    init() {}
}
#endif
#if os(iOS) && SAYONE_IOS_INTENT_IN_APP
extension QuickLogIntent: LiveActivityIntent {}                  // kill-switch, off by default
#endif
```

### 17.4 Shared/Intents/Siri (both apps)

```swift
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription("Logs your usual amount of water to Apple Health.")
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct LogPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log drink preset"
    static let description = IntentDescription("Logs one of your presets to Apple Health.")
    @Parameter(title: "Preset") var preset: DrinkPresetEntity
    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$preset)") }
    init() {}
    init(preset: DrinkPresetEntity)
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct LogBeverageIntent: AppIntent {
    static let title: LocalizedStringResource = "Log drink"
    @Parameter(title: "Drink") var beverage: BeverageEntity
    @Parameter(title: "Amount (ml)", inclusiveRange: (10, 3000)) var amountML: Int?
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct LogAmountIntent: AppIntent {
    static let title: LocalizedStringResource = "Log custom amount"
    @Parameter(title: "Amount (ml)", inclusiveRange: (10, 3000),
               requestValueDialog: IntentDialog("How many millilitres?")) var amountML: Int
    @Parameter(title: "Drink") var beverage: BeverageEntity?
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct UndoLastDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo last drink"
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct TodayTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's total"
    init() {}
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog
}
struct SayoneShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(),
                    phrases: ["Log water in \(.applicationName)", "Add water in \(.applicationName)", "\(.applicationName) water"],
                    shortTitle: "Log water", systemImageName: "drop.fill")
        AppShortcut(intent: LogPresetIntent(),
                    phrases: ["Log \(\.$preset) in \(.applicationName)", "Add \(\.$preset) in \(.applicationName)",
                              "\(.applicationName) \(\.$preset)"],
                    shortTitle: "Log preset", systemImageName: "star.fill")
        // LogBeverageIntent, LogAmountIntent, UndoLastDrinkIntent, TodayTotalIntent — phrases per §12.2
    }
}
```

### 17.5 WidgetShared (both widget extensions) and per-platform counterparts

```swift
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let preset: PresetSnapshot
    let snapshot: WidgetSnapshot
}
struct FavoritesEntry: TimelineEntry {
    let date: Date
    let presets: [PresetSnapshot]
    let snapshot: WidgetSnapshot
}
struct QuickLogProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry
    func snapshot(for configuration: SelectPresetIntent, in context: Context) async -> QuickLogEntry
    func timeline(for configuration: SelectPresetIntent, in context: Context) async -> Timeline<QuickLogEntry>   // .atEnd
    func recommendations() -> [AppIntentRecommendation<SelectPresetIntent>]    // PlatformWidgetConfig.quickLogRecommendations()
}
struct FavoritesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry
    func snapshot(for configuration: FavoritesConfigIntent, in context: Context) async -> FavoritesEntry
    func timeline(for configuration: FavoritesConfigIntent, in context: Context) async -> Timeline<FavoritesEntry>
    func recommendations() -> [AppIntentRecommendation<FavoritesConfigIntent>]
}
struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKinds.quickLog, intent: SelectPresetIntent.self,
                               provider: QuickLogProvider()) { entry in QuickLogView(entry: entry) }
            .configurationDisplayName("Quick log")
            .description("One tap logs your drink.")
            .supportedFamilies(PlatformWidgetConfig.quickLogFamilies)
            .platformPrompt()
    }
}
struct FavoritesWidget: Widget { /* same shape; kind WidgetKinds.favorites; FavoritesView */ }
#if compiler(>=6.2)
@available(iOS 18.0, watchOS 26.0, *)
struct QuickLogControl: ControlWidget { /* §11 */ }
#endif

// Defined ONCE PER PLATFORM FOLDER (iOS/Widgets and watchOS/Widgets), identical signatures:
enum PlatformWidgetConfig {
    static var quickLogFamilies: [WidgetFamily] { get }       // iOS: systemSmall, accessoryCircular/Rectangular/Inline
                                                              // watch: accessoryCircular, Corner, Rectangular, Inline
    static var favoritesFamilies: [WidgetFamily] { get }      // iOS: systemMedium ; watch: accessoryRectangular
    static func quickLogRecommendations() -> [AppIntentRecommendation<SelectPresetIntent>]      // iOS: []
    static func favoritesRecommendations() -> [AppIntentRecommendation<FavoritesConfigIntent>]  // iOS: []
}
extension WidgetConfiguration {
    func platformPrompt() -> some WidgetConfiguration         // iOS: promptsForUserConfiguration() ; watch: self
}
struct QuickLogView: View { let entry: QuickLogEntry; var body: some View }     // switch family … default:
struct FavoritesView: View { let entry: FavoritesEntry; var body: some View }
```

### 17.6 Shared/AppCore (both apps)

```swift
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: StoreState
    @Published private(set) var today: DaySummary
    @Published private(set) var health: HealthAccessStatus
    @Published var toast: LastLogSnapshot?
    @Published var route: DeepLink?
    init(store: FileDrinkStore = StoreProvider.shared)
    func reloadIfChanged()
    func sceneDidBecomeActive() async        // reload → flush → HealthImporter → PeerSync.pushFullContext → reload widgets
    func log(presetID: String, source: LogSource) async
    func log(beverageID: String, volumeML: Int, date: Date, source: LogSource) async
    func undo(entryID: UUID) async
    func requestHealthAccess() async
    func savePreset(_ preset: DrinkPreset)
    func deletePreset(id: String)
    func movePresets(fromOffsets: IndexSet, toOffset: Int)
    func saveBeverage(_ beverage: Beverage)
    func archiveBeverage(id: String)
    func updateSettings(_ change: (inout AppSettings) -> Void)
    func handle(url: URL)
}
// Every catalog mutation → WidgetRefresher.catalogChanged() + SayoneShortcuts.updateAppShortcutParameters() + PeerSync.pushChanges()

import WatchConnectivity
final class PeerSync: NSObject, WCSessionDelegate {
    static let shared: PeerSync
    func activate()                          // called in App.init and lazily by DrinkLogger
    func pushChanges()                       // SyncMerge.outgoing(since peerCursor) → sendMessage | transferUserInfo
    func pushFullContext()                   // updateApplicationContext(fullRecent)
    // WCSessionDelegate: activationDidComplete, didReceiveMessage, didReceiveUserInfo, didReceiveApplicationContext
    // #if os(iOS): sessionDidBecomeInactive, sessionDidDeactivate (→ activate again)
    // on receive: store.mutate { SyncMerge.apply } → flush if healthDeletesNeeded → WidgetRefresher → publish to AppModel
}
enum HealthImporter {
    static func importRecent(days: Int = LoggingPolicy.healthImportDays) async -> MergeReport?
}
```

---

## 18. Parallel work plan and milestones

| Engineer | Owns (exclusive folders) | Depends on | First deliverable |
|---|---|---|---|
| E1 Core | `Packages/SayoneCore/**`, the `linux` CI job | — | the public API above, stubbed and compiling, within the first hour; then the implementations plus tests |
| E2 Platform & Sync | `Shared/Platform/**`, `Shared/AppCore/PeerSync.swift`, `HealthImporter.swift` | E1 API | `DrinkLogger`, `HealthService`, flush, import, WatchConnectivity |
| E3 Intents & Siri | `Shared/Intents/**`, `WidgetShared/QuickLogControl.swift`, `Localization/shortcuts.tsv` | E1, E2 signatures | entities, queries, all intents, `SayoneShortcuts`, controls |
| E4 Widgets | `WidgetShared/**` (except the control), `iOS/Widgets/**`, `watchOS/Widgets/**` | E1, E3 (`QuickLogIntent`, config intents) | providers, platform views, bundles |
| E5 iPhone app | `iOS/App/**`, `Shared/Components/**`, `Shared/AppCore/AppModel.swift`, `DeepLinkRouter.swift` | E1, E2 | screens (§13) |
| E6 Watch app & infra | `watchOS/App/**`, `project.yml`, `Config/**`, `scripts/**`, `.github/**`, `Localization/ui.tsv`, `infoplist.tsv`, assets | all (integration) | skeleton plus CI on day 0; watch screens |

String keys are added as TSV lines in each module's section of `ui.tsv`. The file is append-only, so merges stay conflict-free, and `gen_strings.py` regenerates the catalogs.

Milestones (each one ends with green CI):
- **M0** Skeleton: package plus 4 targets with trivial views, one `QuickLogIntent`, an empty widget in each extension. This proves embedding, schemes, entitlements and signing-free builds.
- **M1** Package complete, with Linux tests.
- **M2** Platform, the core intents, and the QuickLog widget on both platforms.
- **M3** Both apps' UI, plus the Favorites widget and Controls.
- **M4** Siri intents and shortcuts, localization, the metadata check.
- **M5** WatchConnectivity, HealthKit import, diagnostics, and the test README (ru).

---

## 19. APIs used that are not in the research digest

| API | Where | Why acceptable / containment |
|---|---|---|
| WatchConnectivity (`WCSession.default`, `activate`, `sendMessage(_:replyHandler:errorHandler:)`, `transferUserInfo`, `updateApplicationContext`, `isReachable`, delegate callbacks, iOS-only `sessionDidBecomeInactive` / `sessionDidDeactivate`) | `Shared/AppCore/PeerSync.swift` only | A stable API since watchOS 2 / iOS 9. It sits on a non-critical path: logging, Health and single-device totals work without it. It can be compiled out with `SAYONE_NO_WC`, in which case only cross-device undo degrades. |
| POSIX `open` / `flock` / `close` | `SayoneCore/Store/FileLock.swift` | Compiled and concurrency-tested on Linux; the Darwin signatures are the same. Imports use `#if canImport(Darwin) … #elseif canImport(Glibc)`. |
| `#include? "Local.xcconfig"` | `Config/Base.xcconfig` | Optional include (Xcode 10+, from memory). If it causes trouble, delete the line and set the team in Xcode's Signing UI. |
| `CFBundleURLTypes` in the watch plist | watch app | Harmless. Widget-URL delivery via `onOpenURL` itself is in the digest. |
| Baseline SwiftUI/Foundation well below our floors | apps | `NavigationStack`, `List`, `.sheet`, `.swipeActions`, `.contextMenu`, `DatePicker` (iOS only), `TabView`, `onChange(of:)` (two-parameter, iOS 17 / watchOS 10), `.task`, `ProgressView(value:)`, `Link`, `URLComponents`, `os.Logger`, `Bundle.preferredLocalizations`. |

Deliberately **not** used in v1:
- `.backgroundTask(.watchConnectivity)` and `transferCurrentComplicationUserInfo`, which would add background watch wake-ups;
- `WidgetRelevance`/`relevance()`;
- Swift Charts, SwiftData, the Observation macro, HealthKitUI;
- Darwin notify / `CFNotificationCenter`;
- `requestConfirmation`.

---

## 20. Test plan for tomorrow (goes into `docs/TESTING.ru.md`)

1. **Setup:**
   - Put your team ID in `Config/Local.xcconfig` (`DEVELOPMENT_TEAM = XXXX`). If the IDs are taken, change `BUNDLE_ID_PREFIX` there.
   - Turn on Developer Mode on the iPhone and the Watch.
   - Remove other sideloaded apps (3-app limit).
   - Run the `SayoneHealth` scheme on the iPhone; this installs the watch app. Trust the profile.
   - Use the `SayoneHealthWatch` scheme to debug on the watch.
   - Turn on WidgetKit Developer Mode, if present, to bypass reload budgets.
2. **Health:** go through onboarding on the iPhone and grant access, then open the watch app and grant access **separately**. Check that Diagnostics shows "App Group: shared".
3. **iPhone:**
   - Tap presets in the app; check the toast and undo, and that samples appear in Health → Water/Caffeine with the right source and FoodType.
   - Add a small QuickLog widget, choose Edit → «Кола без сахара 330 мл», tap it, and check the ✓, the total and Health. Tap twice quickly: only 1 entry should be logged (2 s window).
   - Add the Favorites medium widget and tap ↶.
   - Add the Lock Screen circular widget (unlock first).
   - Add the Control to Control Center and the Action button. Tap it **while locked**, then unlock and check Health.
4. **Watch:**
   - Add the QuickLog corner and circular complications. Before watchOS 26 pick the "Вода 500 мл" and "Кола без сахара 330 мл" recommendations; on 26+ configure them in the face editor.
   - Tap each and check that it logs without opening the app (watchOS 11+).
   - Add the Smart Stack rectangular widget: tap, then undo, then double tap on a Series 9 or later.
   - Use the Favorites trio.
   - In the app, use the Crown for a custom volume.
   - On watchOS 26, add the watch Control and the iPhone control.
   - Set tap mode to "С подтверждением" and check that a tap now opens Confirm.
5. **Sync:**
   - Log on the watch, open the iPhone app, and check the total within seconds (WatchConnectivity) or within minutes (HealthKit).
   - Undo a watch entry from the iPhone, then open the watch app: the Health sample should be gone.
   - Check that Health never shows duplicates.
6. **Siri** (iPhone with Siri in Russian, then English; then on the watch, with exact phrases):
   - «Запиши воду в Сейон»
   - «Добавь Кола без сахара 330 мл в Сейон»
   - «Запиши объём в Сейон» → «триста»
   - «Отмени последний напиток в Сейон»
   - «Сколько я выпил сегодня в Сейон»

   Then check the Shortcuts app lists the actions on both devices.
7. **Simulator:** layout of all widget families, app flows, and Health writes on each simulator separately (no sim-to-sim Health sync expected). Taps on interactive widgets and Siri are verified only on devices.

---

## 21. Risks, fallbacks and kill-switches

| Risk | Fallback / switch |
|---|---|
| HealthKit save from a widget extension fails on device | The entry stays `pending` and the app flushes it (both platforms). iPhone: `SAYONE_IOS_INTENT_IN_APP` moves widget and control taps into the app process. |
| A free team refuses HealthKit on a widget extension | Remove the key from that extension's entitlements. Taps still log locally and the app flushes them to Health. |
| Complication taps open the app instead of running the intent | `widgetURL` → Confirm (2 taps). Smart Stack widgets and Controls remain 1 tap. |
| Watch control in the WidgetBundle breaks the bundle on older watchOS | `SAYONE_NO_WATCH_CONTROLS`. The iPhone control still appears on watchOS 26. |
| WatchConnectivity misbehaves | `SAYONE_NO_WC`. The HealthKit import still converges totals. |
| Russian Siri does not match «SayoneHealth» | `INAlternativeAppNames` «Сейон»/«Сэйон»; rename presets for voice; test via the Shortcuts app and Spotlight. |
