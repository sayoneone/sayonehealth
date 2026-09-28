<!-- angle: BUILD-SAFETY & SIMPLICITY FIRST: the fewest moving parts that satisfy every requirement; prefer verified, long-available APIs; HealthKit as the single source of truth for cross-device totals where it simplifies things. -->

# SayoneHealth v1: architecture

An iPhone and Apple Watch app for logging drinks (water, Cola Zero, other built-in drinks, custom drinks). Every entry is written to Apple Health. The app includes:
- configurable one-tap widgets and complications
- an iOS Control
- Siri App Shortcuts in Russian and English

Goals: it must compile on the first CI runs without a Mac, have few moving parts, and let 4–6 engineers work in parallel against the fixed contracts in §16.

---

## 0. Key decisions at a glance

| Topic | Decision | Why |
|---|---|---|
| Minimum OS | **iOS 18.0, watchOS 11.0** | Interactive watch widgets, iOS Controls, `promptsForUserConfiguration`, `AccessoryWidgetGroup` and `handGestureShortcut` need **no** `#available` checks. Only two `watchOS 26` branches remain. |
| Cross-device totals | **HealthKit is the source of truth for totals.** A device's "today" = HealthKit `dietaryWater` sum (all sources) + this device's entries that HealthKit does not have yet | Entries need no sync protocol. Each entry is written to Health by exactly one device (the one that was tapped), so double counting cannot happen. |
| Local persistence | **One JSON file per entry** in the App Group (`Journal/<uuid>.json`), plus `catalog.json` and `health-snapshot.json` | App, widget extension and Siri processes write different files. No lost updates and no file coordination. |
| Phone → watch config | `WCSession.updateApplicationContext` **one way (phone → watch)** for the catalog only (drinks, presets, goal) | This is the only shared data that is not in Health. Latest value wins; roughly 60 lines of code. |
| One-tap widget | `Button(intent: QuickLogIntent(drinkID:volumeML:))` with fully pre-filled primitive parameters | Widgets never resolve parameters. The intent stays valid even if presets change. |
| Per-instance configuration | `AppIntentConfiguration` + `SelectPresetIntent(preset: PresetEntity?)` | Watch before 26: one recommendation per preset. Watch 26+: `[]`, and the user edits the parameter. iOS: Edit Widget. |
| Siri | App Intents + `AppShortcutsProvider` compiled into **both** apps, phrases in `AppShortcuts.xcstrings` (en + ru) | No SiriKit entitlement, so it works on a free Personal Team. Works on the watch. |
| Controls | One configurable iOS 18 control. On watchOS 26 it also appears on the watch automatically and runs on the iPhone | A watch-native control needs watchOS 26 guards and a WidgetBundle `if #available`. It is deferred to phase 2. |
| Project | XcodeGen 2.46.0 `project.yml`, 4 targets + 1 local package `SayoneCore`, generated `.xcodeproj` committed | Reproducible. The user can open the project tomorrow without installing XcodeGen. |
| CI | ubuntu: lint + `swiftc -parse` + `swift test`. macos-26: 3 xcodebuilds + App Intents metadata check. xcode-27: advisory | Most errors are caught on Linux in about a minute, before spending a macOS run. |
| Third-party dependencies | **None** | |

---

## 1. Deployment targets and toolchain

| Item | Value |
|---|---|
| iOS app + iOS widget extension | iOS **18.0**, iPhone only (`TARGETED_DEVICE_FAMILY = 1`) |
| watch app + watch widget extension | watchOS **11.0** (arm64 / arm64_32 via `$(ARCHS_STANDARD)`; `ARCHS` is never hard-coded) |
| `SayoneCore` package | `swift-tools-version: 5.9`, `platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)]`. These are at or below the app targets. The package builds and tests on Linux Swift 6.4. |
| Language mode | Swift 5 (`SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`). Warnings are never treated as errors. `SWIFT_DEFAULT_ACTOR_ISOLATION` and `SWIFT_APPROACHABLE_CONCURRENCY` are not set. |
| Xcode | 26.x. CI uses the newest `Xcode_26*.app` on `macos-26`. An advisory job runs on the `xcode-27` preview image. If the user's devices already run iOS/watchOS 27, they need Xcode 27 locally. |

Fallback if the user's watch cannot run watchOS 11 (Series 4/5, SE 1st gen): set watchOS to 10.0. Then guard `AccessoryWidgetGroup` and `handGestureShortcut` with `if #available(watchOS 11.0, *)`. Widgets are non-interactive on 10, so a tap opens the confirm screen through `widgetURL`. The lint script (§14) flags the places that would need guards.

---

## 2. Xcode targets, bundle IDs, capabilities

| Target | XcodeGen type / platform | Bundle ID | Embedded in |
|---|---|---|---|
| `SayoneHealth` | `application` / iOS | `$(BUNDLE_ID_PREFIX)` = `com.sayoneone.sayonehealth` | – |
| `SayoneHealthWidgets` | `app-extension` / iOS | `$(BUNDLE_ID_PREFIX).widgets` | iOS app, *Embed Foundation Extensions* |
| `SayoneHealthWatch` | `application` / watchOS (single-target watch app; **not** `watchapp2`) | `$(BUNDLE_ID_PREFIX).watchkitapp` | iOS app, *Embed Watch Content* (`$(CONTENTS_FOLDER_PATH)/Watch`) |
| `SayoneHealthWatchWidgets` | `app-extension` / watchOS | `$(BUNDLE_ID_PREFIX).watchkitapp.widgets` | watch app, *Embed Foundation Extensions* |

- App Group: `$(APP_GROUP_ID)` = `group.com.sayoneone.sayonehealth`. `Config/Base.xcconfig` defines both variables. `Config/Local.xcconfig` (gitignored, optional include) holds `DEVELOPMENT_TEAM` and prefix overrides.
- **Entitlements, identical on all 4 targets:** `com.apple.developer.healthkit = true`, `com.apple.developer.healthkit.access = []`, `com.apple.security.application-groups = [$(APP_GROUP_ID)]`. Nothing else: no Siri, push, iCloud or associated domains (none are allowed on a free team).
- **Info.plist keys** (via XcodeGen `info:`):
  - iOS app: `CFBundleDisplayName`, version keys = `$(MARKETING_VERSION)` / `$(CURRENT_PROJECT_VERSION)`, `LSRequiresIPhoneOS`, `UILaunchScreen {}`, `UIApplicationSceneManifest {UIApplicationSupportsMultipleScenes: false}`, portrait only, `CFBundleURLTypes` (scheme `sayonehealth`), `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `INAlternativeAppNames` (`Sayone`, `Сейон`, `Сейон Хелс`), `SayoneAppGroupID = $(APP_GROUP_ID)`.
  - watch app: `WKApplication = true`, `WKCompanionAppBundleIdentifier = $(BUNDLE_ID_PREFIX)`, `WKRunsIndependentlyOfCompanionApp = true`, Health usage strings, the same `INAlternativeAppNames` (the watch does not inherit them), `SayoneAppGroupID`. **No `NSExtension` key.**
  - both widget extensions: `NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension`, Health usage strings (English only, never shown to the user), `SayoneAppGroupID`, version keys.
- Health usage strings and the display name are localized through `en.lproj/ru.lproj/InfoPlist.strings` in both app targets. The `ru.lproj` folder also makes XcodeGen add `ru` to `knownRegions`.
- Asset catalogs: `iOS/App/Assets.xcassets` and `Watch/App/Assets.xcassets`, each with an `AppIcon.appiconset` holding one 1024×1024 PNG (universal, platform ios / watchos). `scripts/make_icons.py` generates the PNGs with pure-Python zlib, and they are committed. XcodeGen's application preset sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, and a missing set fails `actool`.
- Free-team budget: 4 App IDs + 1 group. Pick the prefix once, because each change uses 4 of the 10 App IDs allowed per week.

---

## 3. Module boundaries

```
Packages/SayoneCore  (pure Swift + Foundation; Linux-testable; no HealthKit/SwiftUI/WidgetKit/AppIntents/os)
        ▲
Shared/Core          (Apple frameworks: HealthKit, WidgetKit, os.Logger; process-agnostic services)
        ▲
Shared/Intents       (AppIntents used by widgets/controls AND apps: QuickLogIntent, UndoLastIntent, PresetEntity, SelectPresetIntent)
        ▲                                  ▲
Shared/WidgetUI (both widget exts)     Shared/AppOnly (both apps: AppModel, CatalogSync, HealthAuthorization, Siri intents + AppShortcutsProvider)
        ▲                                  ▲
iOS/Widgets   Watch/Widgets            iOS/App     Watch/App
```

**Target membership matrix** (XcodeGen `sources:`):

| Folder | iOS app | iOS widgets | watch app | watch widgets |
|---|:-:|:-:|:-:|:-:|
| `Shared/Core` | ✓ | ✓ | ✓ | ✓ |
| `Shared/Intents` | ✓ | ✓ | ✓ | ✓ |
| `Shared/Resources` (`Localizable.xcstrings`) | ✓ | ✓ | ✓ | ✓ |
| `Shared/WidgetUI` | | ✓ | | ✓ |
| `Shared/AppOnly` (incl. `Siri/AppShortcuts.xcstrings`) | ✓ | | ✓ | |
| `iOS/App` | ✓ | | | |
| `iOS/Widgets` | | ✓ | | |
| `Watch/App` | | | ✓ | |
| `Watch/Widgets` | | | | ✓ |
| package `SayoneCore` (static, not embedded) | ✓ | ✓ | ✓ | ✓ |

Dependency rules, enforced by `scripts/lint.py`:
- `Shared/Core`, `Shared/Intents` and `Shared/WidgetUI` never reference `AppModel`, `CatalogSync`, `SayoneShortcuts`, `WCSession` or `requestAuthorization(`. HealthKit authorization lives in `Shared/AppOnly/HealthAuthorization.swift`, so extensions **cannot** compile a prompt call.
- `AppShortcutsProvider` and `AppShortcuts.xcstrings` go only in app targets. App Intents code is never put in the package: no `AppIntentsPackage`, no frameworks.
- Platform-specific APIs in shared folders must sit inside `#if os(iOS)` / `#if os(watchOS)` (list in §18).

---

## 4. Core data model (in `SayoneCore`)

- **Drink**: a kind of beverage. Built-in drinks have a fixed id and localized names. Custom drinks have id `custom-<UUID>` and a user-supplied name. Drinks are **never deleted, only archived**, so any id that ever existed on a device still resolves there.
- **Preset**: drink + volume. This is the one-tap unit used by widgets, complications, controls and the preset grid. At most 12. Array order is display order; the first 4 (iPhone) or 3 (watch) are the "favorites".
- **UserSettings**: `dailyGoalML` (default 2000), `writeNutrients` (default true).
- **Catalog**: drinks + presets + settings + `revision`. This is the single document synced phone → watch.
- **IntakeEntry**: one logged drink on *this* device. It keeps a snapshot of the name and computed nutrients, so later edits to a drink do not rewrite history. `health` is one of `pending | saved | pendingDelete`.
- **HealthSnapshot**: the last successful HealthKit read of today's water. It is a cache for locked or unauthorized reads.
- **TodaySummary**, **TodayRow**, **DayTotal**: derived values for the UI and widgets.

Built-in drinks. Nutrient values are approximate and editable, and the UI makes no medical claims.

| id | en / ru (nom.) | ru (acc., Siri) | SF Symbol | tint | hydration | caffeine mg/100 ml | kcal/100 ml | sugar g/100 ml | default ml |
|---|---|---|---|---|---|---|---|---|---|
| `water` | Water / Вода | воду | `drop.fill` | blue | 1.0 | 0 | 0 | 0 | 250 |
| `sparklingWater` | Sparkling Water / Газированная вода | газированную воду | `bubbles.and.sparkles.fill` | teal | 1.0 | 0 | 0 | 0 | 330 |
| `colaZero` | Cola Zero / Кола без сахара | колу без сахара | `takeoutbag.and.cup.and.straw.fill` | red | 1.0 | 9.6 | 0.3 | 0 | 330 |
| `coffee` | Coffee / Кофе | кофе | `cup.and.saucer.fill` | brown | 1.0 | 40 | 1 | 0 | 200 |
| `tea` | Tea / Чай | чай | `mug.fill` | green | 1.0 | 20 | 1 | 0 | 250 |
| `juice` | Juice / Сок | сок | `wineglass.fill` | orange | 0.9 | 0 | 45 | 9 | 250 |
| `milk` | Milk / Молоко | молоко | `waterbottle.fill` | gray | 0.9 | 0 | 52 | 4.7 | 250 |

Default presets, in order: `water-250`, `water-500`, `colaZero-330`, `coffee-200`, `tea-250`. The watch favorites (the first 3) are therefore Water 250, Water 500 and Cola Zero 330, which covers the user's "half a litre of water" and "Coke Zero" examples. SF Symbol names only matter at runtime: a missing symbol renders empty and never breaks the build.

Nutrient math: `waterML = volume × hydrationFactor`, `x = per100ML.x × volume / 100`, rounded to 0.1. Volumes are clamped to `10...5000` ml and hydration to `0.1...1.0`. `Int` is used for millilitres: daily sums are far below the 32-bit limit on arm64_32.

---

## 5. Storage and data flow

### 5.1 App Group layout (per device; the iPhone and watch containers are separate)

```
<group container>/
  catalog.json            Catalog (drinks, presets, settings, revision). Written only by the foreground app / WC delegate.
  health-snapshot.json    HealthSnapshot cache. Last writer wins.
  Journal/<UUID>.json     one IntakeEntry per file. Created by whoever logs; status updates rewrite the same file atomically.
```
- All writes use `Data.write(to:options: .atomic)`. The file-protection class is left at the container default (complete until first user authentication), so Siri and Controls work on a locked device after first unlock. `.completeFileProtection` is never used.
- `AppGroup.containerURL` falls back to Application Support with an error log if the entitlement is missing (for example, an unsigned build). It never crashes. Settings shows a warning when `AppGroup.isShared == false`.
- Pruning: files with `health == .saved` and `date` older than 3 days are removed whenever the app becomes active. `pending` and `pendingDelete` entries are kept until flushed.
- Catalog decoding: if the file is missing or corrupt, `Catalog.makeDefault()` is used and the corrupt file is kept as `.bak`. New fields in future versions must be optional.

### 5.2 Logging flow (one path for every surface)

`DrinkLogger.log(drinkID:volumeML:)` is used by the app UI, `QuickLogIntent` (widgets and control), Siri intents and the watch app. It is process-agnostic, never throws and never prompts:

```
1 catalog = CatalogStore.load(); drink = catalog.drink(id) ?? BuiltInCatalog.drink(.water)
2 entry = IntakeFactory.make(drink, displayName: drink.displayName, volume, now, ThisDevice.kind)   // health = .pending
3 JournalStore.save(entry)                               // durable before anything can fail
4 if HealthGateway.writeAuth(.water) == .authorized:
      try await HealthGateway.save(entry, includeNutrients: settings.writeNutrients)
      entry.health = .saved; entry.healthSavedAt = now; JournalStore.save(entry)
      await flush(limit: 10)                             // HK reachable → drain older pendings opportunistically
  (any error → entry stays .pending; logged via os.Logger)
5 summary = TodayService.summary(readHealth: false)      // fast; the widget reload does the HK read
6 WidgetRefresher.reloadAll()
7 return LogOutcome(entry, savedToHealth, summary)
```

Where it runs:
- A widget or control tap runs `QuickLogIntent.perform()` in the widget extension. `perform()` awaits the whole flow before returning, so WidgetKit's post-perform reload sees the new total.
- Siri runs in the app process in the background.
- The app UI runs in the app process.

### 5.3 Flush and delete

- `DrinkLogger.flush(limit:)` runs when either app becomes active, and opportunistically after a successful save. It processes the oldest entries first:
  - `pending` → save to Health, then mark `saved`.
  - `pendingDelete` → if the entry was never saved, remove the file. Otherwise call `deleteSamples(entryID:)` and then remove the file (also when 0 samples were deleted).
  - Retries are idempotent through sync identifiers (§6).
- `DrinkLogger.delete(entryID:isLocal:)`:
  - Local entry that was never saved → remove the file.
  - Local entry that was saved → set `.pendingDelete` (hidden from totals and lists immediately), try the HealthKit delete, then remove the file. If HealthKit throws (locked or unavailable), return `.queued` and let flush finish it.
  - Row from the other device → try `deleteObjects` with the `SayoneEntryID` predicate. If 0 samples are deleted, return `.notDeletableHere` and the UI says «Удалите на устройстве, где записано, или в приложении «Здоровье»».
- **Undo**: `DrinkLogger.undoLast()` deletes the newest local entry that is not `pendingDelete` and was logged within `UndoPolicy.window` (30 min). It is reachable from the in-app toast, the iOS widget undo button and Siri («Отмени последний напиток»).

### 5.4 Today total (pure rule, unit-tested on Linux)

```
day    = calendar day containing now
base   = snapshot.waterML            if snapshot?.dayStart == day.start, else 0
cutoff = snapshot.readAt             if base is used, else -∞
add    = Σ waterML of local entries in day with health == .pending
       + Σ waterML of local entries in day with health == .saved && healthSavedAt > cutoff
sub    = Σ waterML of local entries in day with health == .pendingDelete && healthSavedAt != nil && healthSavedAt <= cutoff
total  = max(0, round(base + add − sub))
```

- `TodayService.summary(readHealth: true)` first tries the HealthKit statistics query. `readAt` is captured just before the query is issued. On success it saves a new snapshot, then applies the rule. When the device is locked, access was denied, or there is no data yet, it uses the cached snapshot.
- Result: no double counting and no drop-outs while locked. The other device's drinks arrive through HealthKit sync.

### 5.5 Today list

`TodayListMerger.merge(local:health:day:)`:
- Takes the union of HealthKit samples that carry `SayoneEntryID` (from either device) and local entries, keyed by entry id. The local entry wins, because it carries status and pending state.
- Removes `pendingDelete` entries and their HealthKit twins.
- Sorts newest first.
- The UI may add a footnote «Другие источники в «Здоровье»: N мл», where N = HealthKit total − sum of rows.

---

## 6. HealthKit strategy

| Component | Type | Unit | Written when |
|---|---|---|---|
| water | `HKQuantityType(.dietaryWater)` | `HKUnit.literUnit(with: .milli)` | always (volume × hydration) if water is authorized |
| caffeine | `.dietaryCaffeine` | `HKUnit.gramUnit(with: .milli)` | value > 0, `writeNutrients`, type authorized |
| energy | `.dietaryEnergyConsumed` | `HKUnit.kilocalorie()` | same |
| sugar | `.dietarySugar` | `HKUnit.gram()` | same |

- **Share set:** the 4 types above. **Read set:** `dietaryWater` only. Only the types the app actually uses are requested. No `HKCorrelation(.food)`, because a correlation type in an authorization set raises an uncatchable exception.
- The type/unit table is a single exhaustive `switch` over `HealthComponent`. Units are never built ad hoc; an incompatible unit raises an ObjC exception.
- **Samples:** one flat `HKQuantitySample` per component, with start = end = log time, saved with `store.save([HKObject])` after filtering by `authorizationStatus(for:) == .sharingAuthorized`. `save` is all-or-nothing, so a denied caffeine permission must not block the water sample.
- **Metadata:** values are String or NSNumber only; no custom key starts with `HK`.

  | Key | Value |
  |---|---|
  | `HKMetadataKeySyncIdentifier` | `"<UUID>.<component>"` |
  | `HKMetadataKeySyncVersion` | `NSNumber(value: 1)` (always present together with the identifier) |
  | `HKMetadataKeyFoodType` | localized drink name, e.g. «Кола без сахара» |
  | `HKMetadataKeyWasUserEntered` | `NSNumber(value: true)` |
  | `SayoneEntryID` | UUID string |
  | `SayoneDrinkID` | drink id |
  | `SayoneVolumeML` | NSNumber (poured volume) |
  | `SayoneOrigin` | `"phone"` / `"watch"` |

- **Idempotency:** a retry or a double flush writes the same sync id and version, and HealthKit ignores the duplicate. Both "success" and an error on re-save count as saved.
- **Authorization:** requested only from the foreground iOS app and, separately, the foreground watch app, through the onboarding screens using `try await store.requestAuthorization(toShare:read:)`. Before prompting, `statusForAuthorizationRequest` is checked. Extensions and intents only read `authorizationStatus(for:)`. If water is not authorized, they journal the entry, and Siri says «Записано в приложении. Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью»». `handleAuthorizationForExtension` and HealthKitUI are never used.
- **Reads:**
  - today's water uses `HKStatisticsQueryDescriptor` (`.cumulativeSum`, strictStartDate predicate for today, all sources)
  - today's rows use `HKSampleQueryDescriptor` over `dietaryWater` with `predicateForObjects(withMetadataKey: "SayoneEntryID")` (limit 200)
  - history uses `HKStatisticsCollectionQueryDescriptor` (7 daily buckets)
  - `.errorNoData` or nil means 0. `.errorDatabaseInaccessible` or an authorization error means "use the cache". All reads are wrapped in do/catch.
- **Deletion:** `deleteObjects(of: type, predicate: SayoneEntryID == id)` for each component type the app may write. It is routed to the device that wrote the entry (§5.3). Edits are not offered in v1 (delete + log again). A later edit would re-save with the same sync id and version + 1.
- **Locked device:** saves still succeed because HealthKit journals them until unlock, and reads fall back to the snapshot. Siri and Controls keep the default `authenticationPolicy` (`.alwaysAllowed`). Lock Screen widget buttons act only after the user unlocks.
- **Extensions:**
  - Widget and control intents save from the extension process. The HealthKit entitlement and usage strings are on the extension, and authorization comes from the host app. This is expected to work but is not explicitly documented. If it fails, the entry stays `pending` and is flushed on the next app open.
  - iOS escape hatch: define `INTENTS_IN_APP_PROCESS`. `#if os(iOS) && INTENTS_IN_APP_PROCESS` then adds `extension QuickLogIntent: LiveActivityIntent {}` and the same for `UndoLastIntent`, which makes the intent run in the app process. CI compiles this flag in the device build step, so the escape hatch is known to build.

---

## 7. Watch ↔ phone sync

| Data | Mechanism | Direction | Expected latency |
|---|---|---|---|
| Drink entries | HealthKit: each device writes only its own taps | both | Apple-controlled; seconds to minutes, sometimes longer |
| Today total and list | Derived from HealthKit + own journal (§5.4–5.5) | – | Appears after HealthKit sync. The app refreshes on foreground; widgets refresh at most every 30 min and at midnight. |
| Catalog (drinks, presets, goal) | `WCSession.updateApplicationContext(["catalog": Data, "revision": Int])` | phone → watch only | Delivered when the watch app's session is active (open the watch app once after editing presets). Latest wins; a lower `revision` is ignored. |
| Health authorization | none (independent per device) | – | The user grants access on both devices |
| Pending queue | local only | – | Flushed by the device that owns it |

Watch side of `CatalogSync`:
- On activation it applies `session.receivedApplicationContext` (this persists across launches).
- On `didReceiveApplicationContext` it does: save catalog → `AppModel.applyReceivedCatalog` → `WidgetRefresher.catalogDidChange()` (which calls `invalidateConfigurationRecommendations()` on the watch) → `SayoneShortcuts.updateAppShortcutParameters()`.

The watch never edits the catalog. It can still log any drink with any volume using the Digital Crown.

The phone pushes the catalog after every edit and on activation, when `isPaired && isWatchAppInstalled`.

---

## 8. iPhone widgets (iOS widget extension)

| Widget | Configuration | Families | Content |
|---|---|---|---|
| **QuickLog** («Быстрая запись») | `AppIntentConfiguration(kind: "QuickLogWidget", intent: SelectPresetIntent.self, provider: QuickLogProvider())`, `.promptsForUserConfiguration()` (inside `#if os(iOS)`) | `systemSmall`, `accessoryCircular`, `accessoryRectangular`, `accessoryInline` | See layouts below |
| **Favorites** («Избранное») | `StaticConfiguration(kind: "FavoritesWidget")` | `systemMedium` | header «1,2 из 2 л» + ProgressView; 4 buttons for the first 4 presets (symbol + «+330»), each a `Button(intent: QuickLogIntent(p))`; undo button when available |

QuickLog layouts:
- **systemSmall:** drink symbol and name at the top; a large `Button(intent: QuickLogIntent(preset))` labelled «+500 мл» in the drink tint; «1,2 из 2 л» and a ProgressView at the bottom. A small `Button(intent: UndoLastIntent())` («↺») sits in the top right while an undo is available.
- **Lock Screen circular / rectangular:** the whole view is a single `Button(intent:)`. Circular shows a `Gauge(.accessoryCircularCapacity)` with the symbol and «+500». Rectangular shows name, «+500 мл» and «1,2 из 2 л».
- **Inline:** text only.

Shared rules:
- Every root view has `.containerBackground(for: .widget) { tint.opacity(0.18) }` and one `.widgetURL(sayonehealth://log?preset=<id>)`. The URL opens a confirm sheet and never logs automatically.
- The total `Text` uses `.invalidatableContent()`; icons and gauges use `.widgetAccentable()`.
- Timeline: one entry at now, `policy: .after(min(now + 30 min, next midnight, undo expiry))`.
- Preset resolution:
  1. `configuration.preset` is re-resolved through `PresetDisplays.find(id:)`
  2. otherwise the entity's own fields
  3. otherwise the first preset
  4. otherwise the built-in Water 250 fallback
- Budget: button taps and foreground-app reloads do not count against the widget refresh budget.

---

## 9. Apple Watch complications and Smart Stack (watch widget extension)

The same `QuickLogWidget` and `FavoritesWidget` sources are compiled with `#if os(watchOS)` family lists.

| Family | Surface | Layout (the whole view is one `Button(intent:)` unless noted) |
|---|---|---|
| `accessoryCircular` | face + Smart Stack | `Gauge(value: progress)` with `.accessoryCircularCapacity`; center shows the drink symbol + «500». `.buttonStyle(.plain)` **without** `AccessoryWidgetBackground` in the label (known hit-test bug). |
| `accessoryCorner` | face | `Image(systemName: symbol)` button, `.widgetLabel("+500 мл")` with a String argument. |
| `accessoryRectangular` | face + Smart Stack | Row 1: symbol + drink name + «+500 мл». Row 2: «1,2 из 2 л». Row 3: linear ProgressView. Row 4 (small): «последняя 12:04». `.handGestureShortcut(.primaryAction)`, so a double tap logs the drink in the Smart Stack. |
| `accessoryInline` | face | `Label("1,2 / 2 л", systemImage: "drop.fill")`. No button. |
| Favorites `accessoryRectangular` | Smart Stack | `AccessoryWidgetGroup(label: { Text("1,2 из 2 л") }) { 3× Button(intent: QuickLogIntent(p)) }` with `.accessoryWidgetGroupStyle(.circular)` |

- **Per-instance configuration:** `recommendations()` is implemented **only under `#if os(watchOS)`**. It is mandatory there, because watchOS has no default implementation.
  - On watchOS 26+ it returns `[]`: the user adds «Быстрая запись» and edits the «Напиток» parameter in the face editor or Smart Stack. The options come from `PresetQuery.suggestedEntities()`.
  - Before 26 it returns up to 12 `AppIntentRecommendation(intent: SelectPresetIntent(preset:), description: <String var>)`. «Вода · 500 мл» and «Кола без сахара · 330 мл» then appear as separate complication options.
- **Confirmation:** after `perform()` returns, WidgetKit reloads the timeline, so the ring and the total visibly change. Undo is available in the watch app (top banner) or by voice.
- **Fallback:** a missed hit target or an interactivity failure opens the watch app on `ConfirmLogView` through `widgetURL`.
- **Refresh:** timeline policy `.after(min(now+30m, midnight))`. The watch app reloads widgets on every log and whenever it becomes active.
- **Ultra Action button (no code):** Settings → Action Button → Shortcut → «Записать воду» (the App Shortcut exposed by the watch app).

---

## 10. Controls

- **iOS 18 `QuickLogControl`** in the iOS widget extension:
  - `AppIntentControlConfiguration(kind: "QuickLogControl", intent: SelectPresetControlIntent.self)`, with `.displayName("Log Drink")`, `.description(...)` and `.promptsForUserConfiguration()`.
  - The content closure contains only `let` statements and **one** `ControlWidgetButton(action: QuickLogIntent(p)) { Label(title, systemImage: p.symbol) }`, because the builder has no if/else.
  - `SelectPresetControlIntent.preset` is **optional**. The fallback is the built-in Water 250.
  - It is stateless, so no `ControlCenter` reloads are needed.
  - Available in Control Center, on the Lock Screen and on the iPhone Action button.
- **On watchOS 26+** the iPhone control appears in the watch's Control Center, Smart Stack and Ultra Action button, and runs on the iPhone. This works because its intent never foregrounds the app.
- **Deferred (phase 2):** a watch-native control inside `#if compiler(>=6.2)` and `@available(watchOS 26.0, *)`, added to the watch bundle through `if #available(watchOS 26.0, *) { WatchQuickLogControl() }`. Excluded from v1 to keep the watch bundle free of limited-availability builder paths.

---

## 11. App Intents and Siri

### 11.1 Intent inventory

| Type | Folder (targets) | Discoverable | Parameters | Result |
|---|---|---|---|---|
| `QuickLogIntent` | Shared/Intents (4) | **no** | `drinkID: String` (default "water"), `volumeML: Int` (default 250) | `.result()` |
| `UndoLastIntent` | Shared/Intents (4) | yes (App Shortcut) | – | dialog |
| `SelectPresetIntent: WidgetConfigurationIntent` | Shared/Intents (4) | – | `preset: PresetEntity?` | – |
| `PresetEntity` / `PresetQuery: EntityQuery` | Shared/Intents (4) | – | – | – |
| `SelectPresetControlIntent: ControlConfigurationIntent` | iOS/Widgets | – | `preset: PresetEntity?` | – |
| `LogWaterIntent` | Shared/AppOnly/Siri (2 apps) | yes | `amount: WaterAmount` (AppEnum, default `.glass`) | dialog |
| `LogDrinkIntent` | Shared/AppOnly/Siri | yes | `drink: DrinkEntity` (required; Siri asks «Какой напиток?»), `volumeML: Int?` (nil → drink default) | dialog |
| `TodayTotalIntent` | Shared/AppOnly/Siri | yes | – | dialog «Сегодня 1,2 л из 2 л.» |
| `DrinkEntity` / `DrinkQuery: EntityStringQuery` | Shared/AppOnly/Siri | – | synonyms = Russian accusative («колу без сахара») | – |
| `WaterAmount: AppEnum` | Shared/AppOnly/Siri | – | glass 250, can 330, halfLiter 500, liter 1000 | – |
| `SayoneShortcuts: AppShortcutsProvider` | Shared/AppOnly/Siri | – | 4 App Shortcuts | – |

Metadata rules:
- `static let title: LocalizedStringResource`.
- `TypeDisplayRepresentation(name:)` is always written explicitly.
- Query names are unique (`PresetQuery`, `DrinkQuery`).
- **No `description` declarations on intents**, which avoids witness-type ambiguity.
- Never use `openAppWhenRun`, `supportedModes`, `ForegroundContinuableIntent` or `allowedExecutionTargets`.
- No `Int` or `Measurement` values in phrases; only one parameter per phrase.
- Both apps call `SayoneShortcuts.updateAppShortcutParameters()` in `App.init()` and after every catalog change.

### 11.2 Phrases (`Shared/AppOnly/Siri/AppShortcuts.xcstrings`; key = first English phrase)

| Shortcut (shortTitle / symbol) | English phrases (identical in Swift and in the `en` stringSet) | Russian phrases (`ru` stringSet) |
|---|---|---|
| LogWaterIntent («Log Water», `drop.fill`) | `Log water in ${applicationName}` · `Add water in ${applicationName}` · `Log ${amount} of water in ${applicationName}` · `I drank ${amount} of water in ${applicationName}` | `Запиши воду в ${applicationName}` · `Добавь воду в ${applicationName}` · `Запиши ${amount} воды в ${applicationName}` · `Добавь ${amount} воды в ${applicationName}` · `Я выпил ${amount} воды в ${applicationName}` · `Я выпила ${amount} воды в ${applicationName}` · `Выпил воды в ${applicationName}` · `Выпила воды в ${applicationName}` |
| LogDrinkIntent («Log Drink», `cup.and.saucer.fill`) | `Log ${drink} in ${applicationName}` · `I drank ${drink} in ${applicationName}` · `Log a drink in ${applicationName}` | `Запиши ${drink} в ${applicationName}` · `Добавь ${drink} в ${applicationName}` · `Я выпил ${drink} в ${applicationName}` · `Я выпила ${drink} в ${applicationName}` · `Запиши напиток в ${applicationName}` |
| TodayTotalIntent («Today's Water», `chart.bar.fill`) | `How much did I drink in ${applicationName}` · `Today's water in ${applicationName}` | `Сколько я выпил в ${applicationName}` · `Сколько я выпила в ${applicationName}` · `Сколько воды сегодня в ${applicationName}` |
| UndoLastIntent («Undo Last Drink», `arrow.uturn.backward`) | `Undo last drink in ${applicationName}` | `Отмени последний напиток в ${applicationName}` · `Удали последний напиток в ${applicationName}` |

`WaterAmount` case titles and synonyms (in Localizable.xcstrings):

| Case | en title | en synonyms | ru title | ru synonyms |
|---|---|---|---|---|
| glass | a glass | glass, one glass | стакан | стаканчик, один стакан |
| can | a can | can, one can | банку | банка, одну банку |
| halfLiter | half a liter | half a litre, 0.5 liters | пол-литра | поллитра, пол литра |
| liter | a liter | a litre, one liter | литр | один литр, литр воды |

The user's example then works as spoken: «Привет, Siri, запиши пол-литра воды в SayoneHealth». On the watch, flexible matching is off, so phrases must be said exactly; they are kept short.

Sample xcstrings entry:

```json
{ "sourceLanguage": "en", "version": "1.0", "strings": {
  "Log water in ${applicationName}": { "extractionState": "manual", "localizations": {
    "en": { "stringSet": { "state": "translated", "values": ["Log water in ${applicationName}", "Add water in ${applicationName}", "Log ${amount} of water in ${applicationName}", "I drank ${amount} of water in ${applicationName}"] } },
    "ru": { "stringSet": { "state": "translated", "values": ["Запиши воду в ${applicationName}", "Добавь воду в ${applicationName}", "Запиши ${amount} воды в ${applicationName}", "Добавь ${amount} воды в ${applicationName}", "Я выпил ${amount} воды в ${applicationName}", "Я выпила ${amount} воды в ${applicationName}", "Выпил воды в ${applicationName}", "Выпила воды в ${applicationName}"] } } } } } }
```

App name for Russian Siri: `INAlternativeAppNames` = «Sayone», «Сейон», «Сейон Хелс» (3 entries, not localized) in both apps. Discoverability: `SiriTipView(intent: LogWaterIntent())` on the iPhone Today screen and in Settings; `ShortcutsLink()` only inside `#if os(iOS)`.

---

## 12. UI screens

UI is SwiftUI with `ObservableObject` + `@Published` (long-available; no Observation macro), in a native, restrained style: SF Symbols, system fonts, one tint per drink.

### iPhone (`iOS/App/Views`)

| Screen | Contents |
|---|---|
| `TodayView` (root, `NavigationStack` + `List`) | `ProgressCard` (ring + «1,2 л из 2 л» + «N ожидают записи в «Здоровье»» badge); `PresetGrid` (2-column grid, tap = log, success haptic, toast «Записано · Отменить» for 5 s); «Другой напиток…» → `LogDrinkSheet`; `SiriTipView`; «Сегодня» section of `TodayRow`s with swipe-to-delete and a device glyph (⌚/📱); optional other-sources footnote. Toolbar: History, Settings. Pull to refresh. |
| `LogDrinkSheet` | grid of active drinks, volume chips 150/200/250/330/500/750/1000, `Stepper` ±10, «Записать» button |
| `HistoryView` | last 7 days from `HealthGateway.dailyWater` (local fallback), simple capsule bars against the goal. Swift Charts is not used. |
| `SettingsView` | goal stepper (500–6000, step 100); «Записывать кофеин, калории и сахар» toggle; «Напитки» → `DrinksListView` → `DrinkEditorView`; «Кнопки быстрого ввода» → `PresetsListView` (reorder, delete, max 12) → `PresetEditorView`; «Здоровье» status + «Разрешить доступ»; «Apple Watch» (installed? «Отправить на часы»); «Siri» (tips + `ShortcutsLink`); «О приложении» (version, App Group shared yes/no) |
| `DrinkEditorView` | custom name, symbol grid (`BuiltInCatalog.customSymbols`), tint, hydration slider 10–100 %, caffeine mg / kcal / sugar g per 100 ml (decimal fields), default volume, «Архивировать» |
| `OnboardingView` | shown when `needsHealthOnboarding`: explanation + «Разрешить доступ к «Здоровью»» + «Позже» |
| `ConfirmLogSheet` | from the deep link: «Записать: Вода 500 мл?» [Записать] [Отмена] |

### Watch (`Watch/App/Views`)

| Screen | Contents |
|---|---|
| `WatchRootView` (`NavigationStack` + `List`) | `TodayRingRow` (circular `Gauge` + «1,2 из 2 л»); `LoggedBanner` («✓ Вода 500 мл · Отменить»); Health permission row when needed; `PresetRow`s (tap = log + `.sensoryFeedback(.success, trigger:)`); «Другой напиток…» → `DrinkPickerView` → `VolumePickerView`; «Сегодня» rows with swipe delete; «Как добавить на циферблат» → `ComplicationHelpView` |
| `VolumePickerView` | outside any List: big «250 мл» `Text` with `.focusable().digitalCrownRotation($ml, from: 50, through: 2000, by: 50, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)` (`ml` is a `Double`), drink symbol, «Записать» |
| `ConfirmLogView` | the watch deep-link target (confirm, never auto-log) |
| `WatchOnboardingView` | Health permission on first launch |

---

## 13. Localization

- `developmentLanguage: en`; `knownRegions` en and ru. English is the source and fallback language; Russian is fully translated.
- `Shared/Resources/Localizable.xcstrings` (all 4 targets) is **generated** by `scripts/build_strings.py` from per-lane fragments `Localization/{core,widgets,ios,watch,siri}.json`. The fragment format is `{"English key": "Русский"}` or `{"key": {"en": "...", "ru": "..."}}`. Each engineer owns one fragment, so there are no merge conflicts. CI checks that the generated file matches the committed one, and the generator fails on duplicate keys with conflicting values.
- `AppShortcuts.xcstrings` is hand-written by the Siri lane.
- `InfoPlist.strings` lives in `en.lproj/ru.lproj` of both apps.
- `SWIFT_EMIT_LOC_STRINGS = NO` so Xcode builds do not rewrite the hand-managed catalogs.
- Rules:
  - (a) Every user-visible literal is an English key.
  - (b) Numbers are pre-formatted into Strings (`VolumeText`), and only `%@` is interpolated. Russian values may use positional `%1$@`.
  - (c) No plural-sensitive nouns next to numbers; abbreviations are used instead (мл, л, мг, ккал, г).
  - (d) Already-localized runtime strings render with `Text(verbatim:)` or `Text(stringVar)`.
  - (e) Built-in drink names come from `String(localized: "Water")` and similar literals in `DrinkLocalization.swift`.
- Volume formatting uses `MeasurementFormatter` (`.providedUnit`, `.medium`, max 1 fraction digit): «250 мл», «1,5 л» (at 1000 ml and above).
- Glossary: Сегодня, Цель, Выпито, Другой напиток, Записать, Отменить, Записано, Напитки, Кнопки быстрого ввода, Быстрая запись, Избранное, Здоровье, Разрешить доступ, История, Настройки, Вода, Газированная вода, Кола без сахара, Кофе, Чай, Сок, Молоко, Свой напиток, Гидратация, Кофеин, Калории, Сахар.

---

## 14. Project generation and CI

### 14.1 `Config/Base.xcconfig`
```
BUNDLE_ID_PREFIX = com.sayoneone.sayonehealth
APP_GROUP_ID = group.com.sayoneone.sayonehealth
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM =
#include? "Local.xcconfig"
```
If `#include?` turns out to be unsupported, the skeleton CI run shows it immediately. The fallback is to delete that line and have the user set the team in `Base.xcconfig`.

### 14.2 `project.yml`
```yaml
name: SayoneHealth
options:
  minimumXcodeGenVersion: 2.44.1
  xcodeVersion: "26.0"
  developmentLanguage: en
  createIntermediateGroups: true
  deploymentTarget: { iOS: "18.0", watchOS: "11.0" }
configFiles: { Debug: Config/Base.xcconfig, Release: Config/Base.xcconfig }
settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    SWIFT_EMIT_LOC_STRINGS: NO
    REGISTER_APP_GROUPS: YES
packages:
  SayoneCore: { path: Packages/SayoneCore }
targets:
  SayoneHealth:
    type: application
    platform: iOS
    sources:
      - iOS/App
      - { path: Shared/Core, excludes: ["**/*.md"] }
      - { path: Shared/Intents, excludes: ["**/*.md"] }
      - { path: Shared/AppOnly, excludes: ["**/*.md"] }
      - Shared/Resources
    dependencies:
      - package: SayoneCore
      - target: SayoneHealthWidgets          # -> Embed Foundation Extensions
      - target: SayoneHealthWatch            # -> Embed Watch Content ($(CONTENTS_FOLDER_PATH)/Watch)
    info:
      path: iOS/App/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UIApplicationSceneManifest: { UIApplicationSupportsMultipleScenes: false }
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        CFBundleURLTypes: [{ CFBundleURLName: $(BUNDLE_ID_PREFIX), CFBundleURLSchemes: [sayonehealth] }]
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
        INAlternativeAppNames: [{ INAlternativeAppName: Sayone }, { INAlternativeAppName: Сейон }, { INAlternativeAppName: Сейон Хелс }]
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: iOS/App/SayoneHealth.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX), TARGETED_DEVICE_FAMILY: "1" } }
    scheme: {}
  SayoneHealthWidgets:
    type: app-extension
    platform: iOS
    sources: [iOS/Widgets, Shared/Core, Shared/Intents, Shared/WidgetUI, Shared/Resources]
    dependencies: [{ package: SayoneCore }]
    info:
      path: iOS/Widgets/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log to Apple Health."
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: iOS/Widgets/SayoneHealthWidgets.entitlements
      properties: { com.apple.developer.healthkit: true, com.apple.developer.healthkit.access: [], com.apple.security.application-groups: [$(APP_GROUP_ID)] }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).widgets, TARGETED_DEVICE_FAMILY: "1", SKIP_INSTALL: YES } }
  SayoneHealthWatch:
    type: application
    platform: watchOS
    sources: [Watch/App, Shared/Core, Shared/Intents, Shared/AppOnly, Shared/Resources]
    dependencies:
      - package: SayoneCore
      - target: SayoneHealthWatchWidgets     # -> Embed Foundation Extensions (PlugIns)
    info:
      path: Watch/App/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        WKApplication: true
        WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX)
        WKRunsIndependentlyOfCompanionApp: true
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log to Apple Health."
        INAlternativeAppNames: [{ INAlternativeAppName: Sayone }, { INAlternativeAppName: Сейон }, { INAlternativeAppName: Сейон Хелс }]
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: Watch/App/SayoneHealthWatch.entitlements
      properties: { com.apple.developer.healthkit: true, com.apple.developer.healthkit.access: [], com.apple.security.application-groups: [$(APP_GROUP_ID)] }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp } }
    scheme: {}
  SayoneHealthWatchWidgets:
    type: app-extension
    platform: watchOS
    sources: [Watch/Widgets, Shared/Core, Shared/Intents, Shared/WidgetUI, Shared/Resources]
    dependencies: [{ package: SayoneCore }]
    info:
      path: Watch/Widgets/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension: { NSExtensionPointIdentifier: com.apple.widgetkit-extension }
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log to Apple Health."
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: Watch/Widgets/SayoneHealthWatchWidgets.entitlements
      properties: { com.apple.developer.healthkit: true, com.apple.developer.healthkit.access: [], com.apple.security.application-groups: [$(APP_GROUP_ID)] }
    settings: { base: { PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp.widgets } }
```

### 14.3 `Packages/SayoneCore/Package.swift`
```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SayoneCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "SayoneCore", targets: ["SayoneCore"])],
    targets: [
        .target(name: "SayoneCore"),
        .testTarget(name: "SayoneCoreTests", dependencies: ["SayoneCore"])
    ]
)
```
Tests use XCTest. Fixtures are string literals, so no test resources are needed on Linux.

### 14.4 `.github/workflows/ci.yml`
```yaml
name: CI
on:
  push: { branches: [main, 'lane/**', 'claude/**'] }
  pull_request:
  workflow_dispatch:
permissions: { contents: read }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  lint:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v5
      - run: python3 scripts/lint.py
      - run: python3 scripts/build_strings.py --check
      - name: Swift syntax (parse-only, no SDK needed)
        run: find Shared iOS Watch -name '*.swift' -print0 | xargs -0 swiftc -parse
  core:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
      - run: swift test --package-path Packages/SayoneCore
  apple:
    runs-on: macos-26
    timeout-minutes: 60
    env: { XCODEGEN_VERSION: "2.46.0" }
    steps:
      - uses: actions/checkout@v5
      - name: Select newest Xcode 26
        run: |
          sudo xcode-select -s "$(ls -d /Applications/Xcode_26*.app | sort -V | tail -1)"
          xcodebuild -version; xcodebuild -showsdks | grep -E 'iphone|watch'; xcrun simctl list runtimes
      - name: Install XcodeGen (pinned zip)
        run: |
          curl -fsSL -o "$RUNNER_TEMP/xg.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
          unzip -q "$RUNNER_TEMP/xg.zip" -d "$RUNNER_TEMP" && echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
      - name: Generate
        run: |
          xcodegen generate
          grep -q 'Embed Watch Content' SayoneHealth.xcodeproj/project.pbxproj
          git diff --stat -- SayoneHealth.xcodeproj || true
      - name: Build iOS scheme (app + widgets + embedded watch app + watch widgets), Simulator
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -configuration Debug \
            -destination 'generic/platform=iOS Simulator' -derivedDataPath "$RUNNER_TEMP/dd" \
            CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$RUNNER_TEMP/ios.log" | xcbeautify --renderer github-actions
      - name: Build watch scheme standalone, watchOS Simulator
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealthWatch -configuration Debug \
            -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$RUNNER_TEMP/dd" \
            CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | tee "$RUNNER_TEMP/watch.log" | xcbeautify --renderer github-actions
      - name: App Intents metadata check
        run: python3 scripts/check_appintents.py "$RUNNER_TEMP/dd" "$RUNNER_TEMP/ios.log" "$RUNNER_TEMP/watch.log"
      - name: Device build, unsigned (arm64_32 watch; compiles INTENTS_IN_APP_PROCESS escape hatch)
        continue-on-error: true
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -configuration Debug \
            -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/dd-dev" \
            CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO \
            SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG INTENTS_IN_APP_PROCESS' \
            2>&1 | tee "$RUNNER_TEMP/device.log" | xcbeautify --renderer github-actions
      - name: Error digest
        if: failure()
        run: grep -hE "error:|appintentsmetadataprocessor" "$RUNNER_TEMP"/*.log | sort -u | head -100
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: build-logs, path: "${{ runner.temp }}/*.log" }
  apple-xcode27:
    runs-on: xcode-27
    continue-on-error: true
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5
      - run: |
          curl -fsSL -o "$RUNNER_TEMP/xg.zip" https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
          unzip -q "$RUNNER_TEMP/xg.zip" -d "$RUNNER_TEMP" && "$RUNNER_TEMP/xcodegen/bin/xcodegen" generate
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -destination 'generic/platform=iOS Simulator' \
            CODE_SIGNING_ALLOWED=NO | xcbeautify --renderer github-actions
```
The repo is public, so macOS minutes are free. Only standard runner labels are used.

### 14.5 Scripts
- `scripts/lint.py` (Python stdlib only; runs on Ubuntu in seconds):
  - parses every `.xcstrings` / `.plist` / `.entitlements` file
  - every Localizable key has a non-empty `ru` value with the same count of format specifiers
  - AppShortcuts: every phrase in `en`/`ru` contains `${applicationName}` **exactly once**; placeholders are limited to {applicationName, amount, drink}; every key equals the first Swift phrase of an `AppShortcut` in `SayoneShortcuts.swift` (`\(.applicationName)` maps to `${applicationName}`, `\(\.$x)` to `${x}`); at most 10 `AppShortcut(` entries
  - forbidden entitlements (`com.apple.developer.siri`, `aps-environment`, `icloud`, `associated-domains`)
  - bundle IDs are prefixed by their parent's bundle ID
  - no `NSExtension` key in the app plists
  - a small `#if` state tracker enforces the platform-gating table in §18
  - forbidden-symbol lists per folder (§3 and §18)
  - every file in `Shared/WidgetUI` that declares a `Widget` also mentions `containerBackground`
- `scripts/build_strings.py [--check]`: builds `Localizable.xcstrings` from the fragments, with `extractionState: manual` and sorted keys.
- `scripts/check_appintents.py`:
  - fails on `No AppIntents metadata have been exported` and on `appintentsmetadataprocessor` warnings or errors
  - asserts that `SayoneHealth.app/Metadata.appintents/extract.actionsdata` and `SayoneHealth.app/Watch/SayoneHealthWatch.app/Metadata.appintents/extract.actionsdata` each contain 4 `autoShortcuts` whose JSON mentions `LogWaterIntent`, `LogDrinkIntent`, `TodayTotalIntent` and `UndoLastIntent` (substring match, which tolerates identifier-format differences)
  - asserts that the widget `.appex` metadata has `QuickLogIntent` and no `autoShortcuts`
- `scripts/preflight.sh` (the agent's Linux box, before every push): `USER=ci xcodegen generate` (Linux build of 2.46.0), grep that the pbxproj has 1× *Embed Watch Content* and 2× *Embed Foundation Extensions* and that both schemes exist, then `lint.py`, `swiftc -parse`, `swift test`. The generated `SayoneHealth.xcodeproj`, plists and entitlements are committed.
- `scripts/make_icons.py`: writes the 1024 px PNG app icons with zlib (no PIL).

### 14.6 Staged bring-up (keeps macOS round-trips few and cheap)
1. **Package + scripts:** Linux jobs green.
2. **Skeleton:** all 4 targets, all §16 contract files as compiling stubs (trivial bodies, no `fatalError`), one trivial widget per bundle, the 4 App Shortcuts. The macOS job must go green. This validates embedding, Info.plists, entitlements, the xcconfig include, App Intents metadata and the watch build.
3. **Parallel lanes:** each lane pushes `lane/<name>`. CI runs per branch (up to 5 concurrent macOS jobs on the free plan). Only green lanes are merged, one at a time, re-running CI on `main`.

---

## 15. File tree

```
sayonehealth/
├─ project.yml · Config/Base.xcconfig · SayoneHealth.xcodeproj/ (generated, committed) · README.md (ru, device test guide)
├─ .github/workflows/ci.yml
├─ scripts/ lint.py · build_strings.py · check_appintents.py · preflight.sh · make_icons.py
├─ Localization/ core.json · widgets.json · ios.json · watch.json · siri.json
├─ Packages/SayoneCore/
│  ├─ Package.swift
│  ├─ Sources/SayoneCore/
│  │  ├─ Models/ Drink.swift · BuiltInCatalog.swift · Preset.swift · UserSettings.swift · Catalog.swift · Nutrients.swift · IntakeEntry.swift · HealthSnapshot.swift · Summaries.swift · PresetDisplay.swift
│  │  ├─ Logic/ NutrientMath.swift · IntakeFactory.swift · TodayMath.swift · TodayListMerger.swift · UndoPolicy.swift · CatalogEditor.swift · HealthMetadata.swift · DeepLink.swift · WidgetTimeline.swift
│  │  └─ Storage/ CoreJSON.swift · JournalStore.swift · CatalogStore.swift · SnapshotStore.swift
│  └─ Tests/SayoneCoreTests/ NutrientMathTests · TodayMathTests · MergerTests · UndoPolicyTests · CatalogEditorTests · CatalogCodecTests · JournalStoreTests · DeepLinkTests · HealthMetadataTests · WidgetTimelineTests
├─ Shared/
│  ├─ Core/ AppGroup.swift · ThisDevice.swift · AppLog.swift · HealthTypes.swift · HealthGateway.swift · DrinkLogger.swift · TodayService.swift · WidgetRefresher.swift · DrinkLocalization.swift · VolumeText.swift · PresetDisplays.swift · SiriText.swift
│  ├─ Intents/ QuickLogIntent.swift · UndoLastIntent.swift · PresetEntity.swift · SelectPresetIntent.swift · InAppProcess.swift (#if os(iOS) && INTENTS_IN_APP_PROCESS)
│  ├─ WidgetUI/ QuickLogProvider.swift · QuickLogWidget.swift · QuickLogViews.swift · FavoritesWidget.swift · FavoritesViews.swift · WidgetStyle.swift
│  ├─ AppOnly/ AppModel.swift · CatalogSync.swift · HealthAuthorization.swift
│  │  └─ Siri/ LogWaterIntent.swift · LogDrinkIntent.swift · TodayTotalIntent.swift · DrinkEntity.swift · WaterAmount.swift · SayoneShortcuts.swift · AppShortcuts.xcstrings
│  └─ Resources/ Localizable.xcstrings (generated)
├─ iOS/
│  ├─ App/ SayoneHealthApp.swift · Views/{TodayView, ProgressCard, PresetGrid, TodayListSection, LogDrinkSheet, HistoryView, SettingsView, DrinksListView, DrinkEditorView, PresetsListView, PresetEditorView, OnboardingView, ConfirmLogSheet, ToastView}.swift · Assets.xcassets · Info.plist · SayoneHealth.entitlements · en.lproj/InfoPlist.strings · ru.lproj/InfoPlist.strings
│  └─ Widgets/ SayoneWidgetsBundle.swift · QuickLogControl.swift · Info.plist · SayoneHealthWidgets.entitlements
└─ Watch/
   ├─ App/ SayoneWatchApp.swift · Views/{WatchRootView, TodayRingRow, LoggedBanner, PresetRow, DrinkPickerView, VolumePickerView, ConfirmLogView, WatchOnboardingView, ComplicationHelpView}.swift · Assets.xcassets · Info.plist · SayoneHealthWatch.entitlements · en.lproj/InfoPlist.strings · ru.lproj/InfoPlist.strings
   └─ Widgets/ SayoneWatchWidgetsBundle.swift · Info.plist · SayoneHealthWatchWidgets.entitlements
```

---

## 16. Shared type contracts (exact signatures; frozen after the skeleton stage)

Type names avoid SDK collisions: `UserSettings`, not `Settings` (SwiftUI); `IntakeEntry`, not `Entry` (the `TimelineProvider.Entry` associated type).

### 16.1 `SayoneCore` (public API)
```swift
import Foundation

public enum BuiltInDrink: String, Codable, CaseIterable, Sendable { case water, sparklingWater, colaZero, coffee, tea, juice, milk }
public enum DrinkTint: String, Codable, CaseIterable, Sendable { case blue, teal, brown, red, orange, green, purple, gray }
public enum DeviceKind: String, Codable, Sendable { case phone, watch }
public enum HealthSyncStatus: String, Codable, Sendable { case pending, saved, pendingDelete }
public enum HealthComponent: String, CaseIterable, Sendable { case water, caffeine, energy, sugar }

public struct NutrientsPer100ML: Codable, Hashable, Sendable {
    public var caffeineMG: Double; public var energyKcal: Double; public var sugarG: Double
    public init(caffeineMG: Double = 0, energyKcal: Double = 0, sugarG: Double = 0)
}
public struct Nutrients: Codable, Hashable, Sendable {
    public var waterML: Double; public var caffeineMG: Double; public var energyKcal: Double; public var sugarG: Double
    public init(waterML: Double = 0, caffeineMG: Double = 0, energyKcal: Double = 0, sugarG: Double = 0)
}
public struct Drink: Codable, Hashable, Identifiable, Sendable {
    public var id: String; public var builtIn: BuiltInDrink?; public var customName: String?
    public var symbol: String; public var tint: DrinkTint; public var hydrationFactor: Double
    public var per100ML: NutrientsPer100ML; public var defaultVolumeML: Int; public var isArchived: Bool
    public init(id: String, builtIn: BuiltInDrink?, customName: String?, symbol: String, tint: DrinkTint,
                hydrationFactor: Double, per100ML: NutrientsPer100ML, defaultVolumeML: Int, isArchived: Bool = false)
}
public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: String; public var drinkID: String; public var volumeML: Int
    public init(id: String, drinkID: String, volumeML: Int)
}
public struct UserSettings: Codable, Hashable, Sendable {
    public var dailyGoalML: Int; public var writeNutrients: Bool
    public init(dailyGoalML: Int = 2000, writeNutrients: Bool = true)
}
public struct ResolvedPreset: Hashable, Identifiable, Sendable {
    public let preset: Preset; public let drink: Drink
    public var id: String { get }
    public init(preset: Preset, drink: Drink)
}
public struct Catalog: Codable, Hashable, Sendable {
    public static let currentVersion: Int          // 1
    public static let maxPresets: Int              // 12
    public var version: Int; public var revision: Int; public var updatedAt: Date
    public var drinks: [Drink]; public var presets: [Preset]; public var settings: UserSettings
    public init(version: Int, revision: Int, updatedAt: Date, drinks: [Drink], presets: [Preset], settings: UserSettings)
    public static func makeDefault(now: Date = Date()) -> Catalog
    public func drink(id: String) -> Drink?        // includes archived
    public var activeDrinks: [Drink] { get }
    public func resolvedPresets() -> [ResolvedPreset]
    public func sanitized() -> Catalog
}
public enum BuiltInCatalog {
    public static let fallbackDrinkID: String      // "water"
    public static let customSymbols: [String]
    public static func drink(_ kind: BuiltInDrink) -> Drink
    public static var allDrinks: [Drink] { get }
    public static var defaultPresets: [Preset] { get }
}
public enum NutrientMath {
    public static let volumeRange: ClosedRange<Int>          // 10...5000
    public static let hydrationRange: ClosedRange<Double>    // 0.1...1.0
    public static func clampVolume(_ ml: Int) -> Int
    public static func nutrients(for drink: Drink, volumeML: Int) -> Nutrients
}
public struct IntakeEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID; public let date: Date; public let drinkID: String; public let drinkName: String
    public let symbol: String; public let volumeML: Int; public let nutrients: Nutrients; public let origin: DeviceKind
    public var health: HealthSyncStatus; public var healthSavedAt: Date?
    public init(id: UUID, date: Date, drinkID: String, drinkName: String, symbol: String, volumeML: Int,
                nutrients: Nutrients, origin: DeviceKind, health: HealthSyncStatus = .pending, healthSavedAt: Date? = nil)
}
public enum IntakeFactory {
    public static func make(drink: Drink, displayName: String, volumeML: Int, date: Date,
                            origin: DeviceKind, id: UUID = UUID()) -> IntakeEntry
}
public struct HealthSnapshot: Codable, Hashable, Sendable {
    public var dayStart: Date; public var waterML: Double; public var readAt: Date
    public init(dayStart: Date, waterML: Double, readAt: Date)
}
public struct TodaySummary: Hashable, Sendable {
    public var waterML: Int; public var goalML: Int
    public var lastLocal: IntakeEntry?; public var undoAvailableUntil: Date?; public var pendingCount: Int
    public var progress: Double { get }            // clamped 0...1
    public static let placeholder: TodaySummary    // 1200 / 2000
    public init(waterML: Int, goalML: Int, lastLocal: IntakeEntry?, undoAvailableUntil: Date?, pendingCount: Int)
}
public struct DayTotal: Hashable, Identifiable, Sendable {
    public let dayStart: Date; public let waterML: Int
    public var id: Date { get }
    public init(dayStart: Date, waterML: Int)
}
public struct HealthIntakeRecord: Hashable, Sendable {
    public let entryID: UUID; public let date: Date; public let drinkID: String?; public let drinkName: String
    public let volumeML: Int?; public let waterML: Double; public let origin: DeviceKind?
    public init(entryID: UUID, date: Date, drinkID: String?, drinkName: String, volumeML: Int?, waterML: Double, origin: DeviceKind?)
}
public struct TodayRow: Hashable, Identifiable, Sendable {
    public let id: UUID; public let date: Date; public let drinkName: String; public let symbol: String?
    public let volumeML: Int; public let waterML: Double; public let origin: DeviceKind?
    public let isLocal: Bool; public let isPendingHealth: Bool
    public init(id: UUID, date: Date, drinkName: String, symbol: String?, volumeML: Int, waterML: Double,
                origin: DeviceKind?, isLocal: Bool, isPendingHealth: Bool)
}
public enum TodayMath {
    public static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval
    public static func nextDayStart(after date: Date, calendar: Calendar = .current) -> Date
    public static func displayWaterML(snapshot: HealthSnapshot?, local: [IntakeEntry], now: Date, calendar: Calendar = .current) -> Int
    public static func summary(snapshot: HealthSnapshot?, local: [IntakeEntry], goalML: Int, now: Date, calendar: Calendar = .current) -> TodaySummary
    public static func localDailyTotals(_ entries: [IntakeEntry], days: Int, now: Date, calendar: Calendar = .current) -> [DayTotal]
}
public enum TodayListMerger {
    public static func merge(local: [IntakeEntry], health: [HealthIntakeRecord], day: DateInterval) -> [TodayRow]
}
public enum UndoPolicy {
    public static let window: TimeInterval         // 1800
    public static func candidate(in local: [IntakeEntry], now: Date) -> IntakeEntry?
}
public enum HealthMetadata {
    public static let entryIDKey: String           // "SayoneEntryID"
    public static let drinkIDKey: String           // "SayoneDrinkID"
    public static let volumeKey: String            // "SayoneVolumeML"
    public static let originKey: String            // "SayoneOrigin"
    public static let syncVersion: Int             // 1
    public static func syncIdentifier(entryID: UUID, component: HealthComponent) -> String   // "<UUID>.<component>"
    public static func amount(of component: HealthComponent, in nutrients: Nutrients) -> Double
}
public struct PresetDisplay: Codable, Hashable, Identifiable, Sendable {
    public let id: String; public let drinkID: String; public let title: String
    public let symbol: String; public let tint: DrinkTint; public let volumeML: Int
    public init(id: String, drinkID: String, title: String, symbol: String, tint: DrinkTint, volumeML: Int)
}
public enum DeepLink: Hashable, Sendable {
    case today
    case logPreset(id: String)
    public static let scheme: String               // "sayonehealth"
    public init?(url: URL)
    public var url: URL { get }
}
public enum WidgetTimeline {
    public static let refreshInterval: TimeInterval   // 1800
    public static func nextRefresh(after now: Date, undoUntil: Date?, calendar: Calendar = .current) -> Date
}
public enum CatalogEditor {   // every mutation bumps revision and sets updatedAt = now
    @discardableResult public static func addCustomDrink(to c: inout Catalog, name: String, symbol: String, tint: DrinkTint,
        hydrationFactor: Double, per100ML: NutrientsPer100ML, defaultVolumeML: Int, now: Date = Date()) -> Drink
    public static func updateDrink(in c: inout Catalog, _ drink: Drink, now: Date = Date())
    public static func archiveDrink(in c: inout Catalog, id: String, now: Date = Date())   // also removes its presets
    @discardableResult public static func addPreset(to c: inout Catalog, drinkID: String, volumeML: Int, now: Date = Date()) -> Preset?  // nil at max
    public static func updatePreset(in c: inout Catalog, _ preset: Preset, now: Date = Date())
    public static func removePreset(from c: inout Catalog, id: String, now: Date = Date())
    public static func movePresets(in c: inout Catalog, from source: IndexSet, to destination: Int, now: Date = Date())  // SwiftUI onMove semantics, no SwiftUI import
    public static func setDailyGoal(in c: inout Catalog, ml: Int, now: Date = Date())
    public static func setWriteNutrients(in c: inout Catalog, _ on: Bool, now: Date = Date())
}
public enum CoreJSON {
    public static func encoder() -> JSONEncoder    // .sortedKeys, dates .millisecondsSince1970
    public static func decoder() -> JSONDecoder
}
public struct JournalStore: Sendable {
    public let directory: URL
    public init(directory: URL)
    public func save(_ entry: IntakeEntry) throws                  // atomic write of <uuid>.json (create or replace)
    public func remove(id: UUID) throws
    public func entry(id: UUID) -> IntakeEntry?
    public func all() -> [IntakeEntry]                             // skips unreadable files
    public func entries(in interval: DateInterval) -> [IntakeEntry]
    public func needingFlush() -> [IntakeEntry]                    // .pending + .pendingDelete, oldest first
    @discardableResult public func prune(savedBefore cutoff: Date) -> Int
}
public struct CatalogStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL)
    public func load() -> Catalog                                  // default + .bak on missing/corrupt; always sanitized
    public func save(_ catalog: Catalog) throws
}
public struct SnapshotStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL)
    public func load() -> HealthSnapshot?
    public func save(_ snapshot: HealthSnapshot) throws
}
```

### 16.2 `Shared/Core` (internal; all 4 targets)
```swift
import Foundation, HealthKit, WidgetKit, os, SayoneCore   // one import per line in real files

enum AppGroup {
    static let identifier: String        // Info.plist "SayoneAppGroupID" ?? "group.com.sayoneone.sayonehealth"
    static let containerURL: URL
    static var isShared: Bool { get }
    static let journal: JournalStore     // <container>/Journal
    static let catalog: CatalogStore     // <container>/catalog.json
    static let snapshot: SnapshotStore   // <container>/health-snapshot.json
}
enum ThisDevice { static let kind: DeviceKind }            // #if os(watchOS) .watch #else .phone
enum AppLog { static let intake: Logger; static let health: Logger; static let widget: Logger; static let sync: Logger }

enum HealthWriteAuth: Sendable { case authorized, denied, notDetermined, unavailable }
enum HKDrinkTypes {
    static func type(_ c: HealthComponent) -> HKQuantityType   // exhaustive switch
    static func unit(_ c: HealthComponent) -> HKUnit
    static let share: Set<HKSampleType>                         // 4 types
    static let read: Set<HKObjectType>                          // dietaryWater only
}
final class HealthGateway {
    static let shared: HealthGateway
    let store: HKHealthStore
    var isAvailable: Bool { get }                               // HKHealthStore.isHealthDataAvailable()
    func writeAuth(_ c: HealthComponent) -> HealthWriteAuth
    func needsAuthorizationPrompt() async -> Bool               // statusForAuthorizationRequest == .shouldRequest
    func save(_ entry: IntakeEntry, includeNutrients: Bool) async throws
    func deleteSamples(entryID: UUID) async throws -> Int
    func todayWaterML(now: Date) async throws -> Double
    func todayRecords(now: Date) async throws -> [HealthIntakeRecord]
    func dailyWater(days: Int, now: Date) async throws -> [DayTotal]
}

struct LogOutcome: Sendable { let entry: IntakeEntry; let savedToHealth: Bool; let summary: TodaySummary }
enum DeleteOutcome: Sendable { case deleted, queued, notDeletableHere, notFound }
struct UndoResult: Sendable { let outcome: DeleteOutcome; let entry: IntakeEntry? }
enum DrinkLogger {
    static func log(drinkID: String, volumeML: Int, date: Date = Date()) async -> LogOutcome
    @discardableResult static func flush(limit: Int = 50) async -> Int
    static func delete(entryID: UUID, isLocal: Bool) async -> DeleteOutcome
    static func undoLast() async -> UndoResult
}
enum TodayService {
    static func summary(readHealth: Bool, now: Date = Date()) async -> TodaySummary
    static func rows(now: Date = Date()) async -> [TodayRow]
    static func history(days: Int, now: Date = Date()) async -> [DayTotal]
}
enum WidgetKinds { static let quickLog = "QuickLogWidget"; static let favorites = "FavoritesWidget"; static let quickLogControl = "QuickLogControl" }
enum WidgetRefresher {
    static func reloadAll()               // WidgetCenter.shared.reloadAllTimelines()
    static func catalogDidChange()        // reloadAll(); #if os(watchOS) invalidateConfigurationRecommendations()
}
extension BuiltInDrink { var localizedName: String { get }; var localizedAccusative: String { get } }
extension Drink { var displayName: String { get }; var accusativeName: String { get } }
extension ResolvedPreset { var display: PresetDisplay { get } }
enum PresetDisplays {
    static func all() -> [PresetDisplay]
    static func find(id: String) -> PresetDisplay?
    static var builtInFallback: PresetDisplay { get }          // Water 250, no I/O
}
enum VolumeText {
    static func short(_ ml: Int) -> String                      // "250 мл" / "1,5 л"
    static func plus(_ ml: Int) -> String                       // "+500 мл"
    static func progress(_ s: TodaySummary) -> String           // "1,2 из 2 л"
}
enum SiriText {
    static func logged(_ o: LogOutcome) -> String
    static func today(_ s: TodaySummary) -> String
    static func undone(_ r: UndoResult) -> String
    static var healthAccessMissing: String { get }
}
```

### 16.3 `Shared/Intents` (all 4 targets)
```swift
import AppIntents
import SayoneCore

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink Button")
    static let defaultQuery = PresetQuery()
    let id: String; let drinkID: String; let title: String; let symbol: String; let tintRaw: String; let volumeML: Int
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(VolumeText.short(volumeML))", image: DisplayRepresentation.Image(systemName: symbol))
    }
    init(_ p: PresetDisplay)
    var display: PresetDisplay { get }
}
struct PresetQuery: EntityQuery {
    init() {}
    func entities(for identifiers: [String]) async throws -> [PresetEntity]   // App Group catalog; drops unknown ids
    func suggestedEntities() async throws -> [PresetEntity]
}
struct SelectPresetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink") var preset: PresetEntity?
    init() {}
    init(preset: PresetEntity) { self.preset = preset }
}
struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Log"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Drink ID", default: "water") var drinkID: String
    @Parameter(title: "Volume (ml)", default: 250) var volumeML: Int
    init() {}
    init(drinkID: String, volumeML: Int) { self.drinkID = drinkID; self.volumeML = volumeML }
    init(_ p: PresetDisplay) { self.init(drinkID: p.drinkID, volumeML: p.volumeML) }
    func perform() async throws -> some IntentResult { _ = await DrinkLogger.log(drinkID: drinkID, volumeML: volumeML); return .result() }
}
struct UndoLastIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Drink"
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let r = await DrinkLogger.undoLast(); WidgetRefresher.reloadAll()
        let text = SiriText.undone(r); return .result(dialog: "\(text)")
    }
}
// InAppProcess.swift
#if os(iOS) && INTENTS_IN_APP_PROCESS
extension QuickLogIntent: LiveActivityIntent {}
extension UndoLastIntent: LiveActivityIntent {}
#endif
```

### 16.4 `Shared/WidgetUI` (both widget extensions)
```swift
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct QuickLogEntry: TimelineEntry { let date: Date; let preset: PresetDisplay; let summary: TodaySummary }
struct QuickLogProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry
    func snapshot(for configuration: SelectPresetIntent, in context: Context) async -> QuickLogEntry
    func timeline(for configuration: SelectPresetIntent, in context: Context) async -> Timeline<QuickLogEntry>
    #if os(watchOS)
    func recommendations() -> [AppIntentRecommendation<SelectPresetIntent>] {
        if #available(watchOS 26.0, *) { return [] }
        return PresetDisplays.all().prefix(Catalog.maxPresets).map { p in
            let text: String = p.title + " · " + VolumeText.short(p.volumeML)
            return AppIntentRecommendation(intent: SelectPresetIntent(preset: PresetEntity(p)), description: text)
        }
    }
    #endif
}
struct QuickLogWidget: Widget {
    let kind: String = WidgetKinds.quickLog
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectPresetIntent.self, provider: QuickLogProvider()) { entry in
            QuickLogView(entry: entry)
        }
        .configurationDisplayName("Quick Log")
        .description("One tap logs the chosen drink to Health.")
        .supportedFamilies(Self.families)
        #if os(iOS)
        .promptsForUserConfiguration()
        #endif
    }
    static var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}
struct QuickLogView: View {               // switch family { #if os(watchOS) case .accessoryCorner #endif; #if os(iOS) case .systemSmall #endif; case .accessoryInline; case .accessoryRectangular; default: circular }
    let entry: QuickLogEntry
    var body: some View                   // content.containerBackground(for: .widget) { ... }.widgetURL(DeepLink.logPreset(id: entry.preset.id).url)
}
struct FavoritesEntry: TimelineEntry { let date: Date; let presets: [PresetDisplay]; let summary: TodaySummary }
struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry
    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void)
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void)   // Task { ... completion(...) }
}
struct FavoritesWidget: Widget {          // StaticConfiguration; iOS [.systemMedium] / watchOS [.accessoryRectangular] via #if
    let kind: String = WidgetKinds.favorites
    var body: some WidgetConfiguration
}
enum WidgetStyle { static func color(_ t: DrinkTint) -> Color; static func background(_ t: DrinkTint) -> Color }
```

### 16.5 iOS/Widgets and Watch/Widgets
```swift
// iOS/Widgets/QuickLogControl.swift
struct SelectPresetControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink") var preset: PresetEntity?
    init() {}
}
struct QuickLogControl: ControlWidget {
    static let kind = WidgetKinds.quickLogControl
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: SelectPresetControlIntent.self) { configuration in
            let p = configuration.preset?.display ?? PresetDisplays.builtInFallback
            let title = p.title + " " + VolumeText.short(p.volumeML)
            ControlWidgetButton(action: QuickLogIntent(p)) { Label(title, systemImage: p.symbol) }
        }
        .displayName("Log Drink")
        .description("Logs the chosen drink to Health with one tap.")
        .promptsForUserConfiguration()
    }
}
// iOS/Widgets/SayoneWidgetsBundle.swift
@main struct SayoneWidgetsBundle: WidgetBundle { var body: some Widget { QuickLogWidget(); FavoritesWidget(); QuickLogControl() } }
// Watch/Widgets/SayoneWatchWidgetsBundle.swift
@main struct SayoneWatchWidgetsBundle: WidgetBundle { var body: some Widget { QuickLogWidget(); FavoritesWidget() } }
```

### 16.6 `Shared/AppOnly` (both apps)
```swift
import SwiftUI
import WatchConnectivity
import AppIntents
import SayoneCore

struct LogToast: Identifiable, Equatable { let id: UUID; let text: String; let entryID: UUID; let savedToHealth: Bool }

@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var catalog: Catalog
    @Published private(set) var summary: TodaySummary
    @Published private(set) var rows: [TodayRow]
    @Published private(set) var healthAuth: HealthWriteAuth
    @Published private(set) var needsHealthOnboarding: Bool
    @Published var toast: LogToast?
    @Published var confirmPreset: PresetDisplay?          // set by deep link, drives the confirm sheet
    func refresh() async                                   // flush, prune, HK reads, reload widgets
    func requestHealthAccess() async
    func log(drinkID: String, volumeML: Int) async
    func log(_ preset: PresetDisplay) async
    func undo() async
    func delete(_ row: TodayRow) async
    func history(days: Int) async -> [DayTotal]
    func handle(url: URL)
    func edit(_ change: (inout Catalog) -> Void)           // save → (iOS) CatalogSync.push → WidgetRefresher.catalogDidChange → SayoneShortcuts.updateAppShortcutParameters()
    func applyReceivedCatalog(_ catalog: Catalog)          // watch
}
final class CatalogSync: NSObject, WCSessionDelegate {
    static let shared = CatalogSync()
    func activate()
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any])
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession)
    func sessionDidDeactivate(_ session: WCSession)        // re-activate
    func push(_ catalog: Catalog)
    var watchAppInstalled: Bool { get }
    #endif
}
extension HealthGateway { func requestAuthorization() async throws }   // HealthAuthorization.swift: requestAuthorization(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)

// Siri/
enum WaterAmount: String, AppEnum, CaseIterable {
    case glass, can, halfLiter, liter
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Amount")
    static let caseDisplayRepresentations: [WaterAmount: DisplayRepresentation] = [
        .glass: DisplayRepresentation(title: "a glass", subtitle: nil, image: nil, synonyms: ["glass", "one glass"]),
        .can: DisplayRepresentation(title: "a can", subtitle: nil, image: nil, synonyms: ["can", "one can"]),
        .halfLiter: DisplayRepresentation(title: "half a liter", subtitle: nil, image: nil, synonyms: ["half a litre", "0.5 liters"]),
        .liter: DisplayRepresentation(title: "a liter", subtitle: nil, image: nil, synonyms: ["a litre", "one liter"])
    ]
    var milliliters: Int { get }                            // 250 / 330 / 500 / 1000
}
struct DrinkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink")
    static let defaultQuery = DrinkQuery()
    let id: String; let name: String; let accusative: String; let symbol: String; let defaultVolumeML: Int
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: nil, image: DisplayRepresentation.Image(systemName: symbol), synonyms: ["\(accusative)"])
    }
    init(_ drink: Drink)
}
struct DrinkQuery: EntityStringQuery {
    init() {}
    func entities(for identifiers: [String]) async throws -> [DrinkEntity]
    func suggestedEntities() async throws -> [DrinkEntity]           // active drinks
    func entities(matching string: String) async throws -> [DrinkEntity]
}
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    @Parameter(title: "Amount", default: .glass) var amount: WaterAmount
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    @Parameter(title: "Drink") var drink: DrinkEntity
    @Parameter(title: "Volume (ml)") var volumeML: Int?
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct TodayTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Water"
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog
}
struct SayoneShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)", "Add water in \(.applicationName)",
            "Log \(\.$amount) of water in \(.applicationName)", "I drank \(\.$amount) of water in \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: LogDrinkIntent(), phrases: [
            "Log \(\.$drink) in \(.applicationName)", "I drank \(\.$drink) in \(.applicationName)", "Log a drink in \(.applicationName)"
        ], shortTitle: "Log Drink", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: TodayTotalIntent(), phrases: [
            "How much did I drink in \(.applicationName)", "Today's water in \(.applicationName)"
        ], shortTitle: "Today's Water", systemImageName: "chart.bar.fill")
        AppShortcut(intent: UndoLastIntent(), phrases: [
            "Undo last drink in \(.applicationName)"
        ], shortTitle: "Undo Last Drink", systemImageName: "arrow.uturn.backward")
    }
}
```
App entry points: `SayoneHealthApp` and `SayoneWatchApp` each hold `@StateObject private var model = AppModel.shared`. `init()` calls `CatalogSync.shared.activate()` and `SayoneShortcuts.updateAppShortcutParameters()`. Views use `.onOpenURL { model.handle(url: $0) }`, and `scenePhase == .active` triggers `Task { await model.refresh() }`.

---

## 17. Parallel work plan

| Lane | Owner scope (only files it may edit) | Depends on |
|---|---|---|
| **E1 Infra + Core package** | `project.yml`, `Config/`, all plists/entitlements, `scripts/`, CI, `Packages/SayoneCore/**`, the §16 skeleton stubs (stage 2) | – (goes first; the skeleton must be green before the other lanes branch) |
| **E2 Apple services** | `Shared/Core/**`, `Localization/core.json` | §16.1 contracts |
| **E3 Widgets + Control** | `Shared/Intents/**`, `Shared/WidgetUI/**`, `iOS/Widgets/**`, `Watch/Widgets/**`, `Localization/widgets.json` | §16.1–16.2 |
| **E4 iPhone app** | `iOS/App/**`, `Shared/AppOnly/AppModel.swift`, `CatalogSync.swift`, `HealthAuthorization.swift`, `Localization/ios.json` | §16.2 |
| **E5 Watch app** | `Watch/App/**`, `Localization/watch.json` | `AppModel` contract (§16.6) |
| **E6 Siri + localization** | `Shared/AppOnly/Siri/**`, `AppShortcuts.xcstrings`, `Localization/siri.json`, `InfoPlist.strings` files | §16.2 |

With 4 engineers, merge E2 into E1 and E6 into E3. Merge order after the skeleton is flexible, because every contract exists as a compiling stub. The recommended order is E1 → E2 → E3 → E6 → E4 → E5. Contract changes go through E1 as a stub update that is green on CI before the lanes rebase.

---

## 18. Build-safety rules (lint-enforced where marked ●)

1. ● Allowed only inside `#if os(iOS)` (or in files under `iOS/`): `.systemSmall`, `.systemMedium`, `promptsForUserConfiguration`, `ShortcutsLink`, `EditButton`, `ControlWidget*`, `ControlConfigurationIntent`, `LiveActivityIntent`, `UIApplication`, `sessionDidBecomeInactive`, `sessionDidDeactivate`, `isWatchAppInstalled`.
2. ● Allowed only inside `#if os(watchOS)` (or in files under `Watch/`): `.accessoryCorner`, `AccessoryWidgetGroup`, `accessoryWidgetGroupStyle`, `handGestureShortcut`, `digitalCrownRotation`, `WKInterfaceDevice`, `invalidateConfigurationRecommendations`, `func recommendations()`.
3. ● Forbidden everywhere: `openAppWhenRun`, `supportedModes`, `ForegroundContinuableIntent`, `allowedExecutionTargets`, `earliestAuthorizedSampleDate`, `HKCorrelation`, `handleAuthorizationForExtension`, `import HealthKitUI`, `AppIntentsPackage`, and the entitlements `com.apple.developer.siri`, `aps-environment`, iCloud and associated domains.
4. ● `Shared/Core`, `Shared/Intents` and `Shared/WidgetUI` must not use `requestAuthorization(`, `WCSession`, `AppModel` or `SayoneShortcuts`.
5. Every `switch` over `WidgetFamily` has a `default:`. Every widget root view has `.containerBackground(for: .widget)` (● heuristic check). There is exactly one `widgetURL` per view hierarchy.
6. Control content closures contain only `let` statements and one `ControlWidgetButton`. The `ControlConfigurationIntent` parameter is optional.
7. Widget and control intents take only pre-filled primitive `@Parameter`s, each with a default.
8. App Intents metadata: use `static let title: LocalizedStringResource`, explicit `TypeDisplayRepresentation(name:)`, literal `caseDisplayRepresentations`, unique query type names, no `description` on intents, at most one parameter per phrase, AppEnum or AppEntity parameters only (● phrase checks).
9. HealthKit metadata values are String or NSNumber only. Units come only from `HKDrinkTypes.unit(_:)`. Authorization sets are typed `Set<HKSampleType>` / `Set<HKObjectType>`. Errors are caught as `catch let e as HKError where e.code == .errorNoData`.
10. Every file explicitly imports what it uses (`AppIntents`, `WidgetKit`, `SwiftUI`, `SayoneCore`). The package never imports Apple-only frameworks (● `core` job builds on Linux).
11. Do not use SwiftUI's `Array.move` or `IndexSet` helpers in the package; implement them manually. Watch amounts use `Int`; the Digital Crown binding uses `Double`.
12. Avoid type-name collisions: no `Settings`, `Entry`, `Label`, `Link` or `Timeline` types of our own.
13. ● `swiftc -parse` on every Apple-side file, plus `xcodegen generate` and the pbxproj phase grep, run before every push.

---

## 19. Device test plan (README, in Russian)

1. Set `DEVELOPMENT_TEAM` in `Config/Local.xcconfig`. If the bundle ID is already taken, change `BUNDLE_ID_PREFIX` and `APP_GROUP_ID` together.
2. Enable Developer Mode on the iPhone and the watch. Run the `SayoneHealth` scheme on the iPhone (this also installs the watch app), then the `SayoneHealthWatch` scheme for watch debugging.
3. Open the app on **both** devices and grant Health access on each; the permissions are independent. Log a drink in each app and check it in Health → Water, Caffeine and so on.
4. **iPhone:**
   - add Quick Log (systemSmall) and choose «Кола без сахара 330»; tap, check that the total changes, then undo
   - add a Lock Screen circular widget (unlock the phone before tapping)
   - add the Favorites medium widget
   - add the control to Control Center and the Action button
5. **Watch:**
   - watchOS 11: in the face editor pick «Вода · 500 мл» as a complication
   - watchOS 26+: add «Быстрая запись» and choose the drink in the editor
   - also check the Smart Stack rectangular widget and double tap
   - tap it and check that the ring updates without opening the app. If a tap opens the app instead, the confirm screen appears.
   - edit presets on the iPhone, open the watch app, and check that the complication options update
6. **Siri** (with Siri in Russian, then in English): «Запиши пол-литра воды в SayoneHealth», «Запиши колу без сахара в SayoneHealth», «Сколько я выпил в SayoneHealth», «Отмени последний напиток в SayoneHealth». Repeat on the watch with exact phrases. Also test with the iPhone locked.
7. **Simulator:** checks UI, widgets and HealthKit per device. Watch ↔ iPhone Health sync is checked only on real devices. Turn on WidgetKit Developer Mode to lift reload budgets.

---

## 20. APIs used that are not in the research digest

All of these are long-available, and none gates a core flow:
- `MeasurementFormatter`, iOS 10 / watchOS 3
- WatchConnectivity `WCSession.updateApplicationContext` / `receivedApplicationContext` / `isWatchAppInstalled`, iOS 9 / watchOS 2. Delegate methods follow the documented split: the inactive/deactivate methods exist on iOS only.
- `os.Logger`, iOS 14 / watchOS 7
- `NavigationStack`, `.swipeActions`, `Stepper`, `ScenePhase`, `@StateObject`
- `TimelineProviderContext.isPreview`
- SF Symbol names (runtime only)
- xcconfig `#include?` (medium confidence; validated in the skeleton CI run)
- `swiftc -parse` on Linux: verified locally, including `#if` inside switch cases and modifier chains, the `\(.applicationName)` interpolations and a `let` inside the control builder.
