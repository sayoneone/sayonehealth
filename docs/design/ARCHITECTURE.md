# SayoneHealth v1: final architecture and implementation spec

Status: **FINAL**. The contracts in §4 are frozen once the Stage A skeleton is green on CI (§5.0).
This document replaces proposals P1, P2 and P3. It starts from P1, the winner, adds the best ideas
from P2 and P3, and fixes every must-fix item the judges raised. Appendix A lists each fix.

Product: an iPhone and Apple Watch app. You tap to log a drink: water, Cola Zero, other built-in
drinks or your own. Every entry lands in Apple Health. Configurable widgets and complications log a
chosen preset with one tap, for example 500 ml of water. Siri works in Russian and English. The user
tests it tomorrow on a real iPhone, a real Apple Watch and the simulator.

How to read this document:
- **MUST** and **NEVER** are binding.
- A Swift block marked *interface* shows declarations without bodies. The owner writes the bodies,
  and the names, labels, types, access levels and constant values must match exactly.
- A block marked *verbatim* is copied as written.
- Nobody on the team has a Mac. Only CI compiles for Apple platforms, so every rule in §5.8 exists
  to avoid a wasted CI round-trip.

---

## 1. Decisions

| # | Topic | Decision | Why (one line) |
|---|---|---|---|
| D1 | Deployment targets | **iOS 18.0** (iPhone only) and **watchOS 11.0** | Interactive watch widgets, iOS Controls, `promptsForUserConfiguration`, `AccessoryWidgetGroup` and `handGestureShortcut` then need no `#available`. The only guarded branch is the watchOS 26 `recommendations()` one. |
| D2 | Pure-logic package | Local SwiftPM package **`SayoneCore`** at `Packages/SayoneCore`. `swift-tools-version: 5.9`, platforms `.iOS(.v17), .watchOS(.v10), .macOS(.v14)`. Imports **Foundation only**, plus Darwin or Glibc behind `canImport`. | It builds and tests on Linux Swift 6.4. Its minimums are no higher than the app targets. |
| D3 | Language mode | `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`, warnings are never errors, no `SWIFT_DEFAULT_ACTOR_ISOLATION` | Avoids Swift 6 strict-concurrency compile errors. |
| D4 | Toolchain | CI uses the newest `/Applications/Xcode_26*.app` on `macos-26`. An advisory `xcode-27` workflow runs separately. | Keeps us on SDKs we verified, with an early warning for the user's local Xcode 27. |
| D5 | Bundle IDs | `$(BUNDLE_ID_PREFIX)` = `com.sayoneone.sayonehealth`; `.widgets`; `.watchkitapp`; `.watchkitapp.widgets` | Each embedded ID MUST be prefixed by its parent's ID. The prefix is set in one place, the xcconfig. |
| D6 | App Group | `$(APP_GROUP_ID)` = `group.com.sayoneone.sayonehealth`. Code reads it from the Info.plist key `SayoneAppGroupID`. | Changing the prefix is a one-line xcconfig edit. |
| D7 | Capabilities | HealthKit (`healthkit=true`, `healthkit.access=[]`) and App Groups on all 4 targets. **Nothing else.** | A free Personal Team can sign it. App Intents need no Siri entitlement. |
| D8 | Source of truth | Each device keeps a **journal of its own taps** in its App Group. HealthKit supplies everything else. `Today = snapshot.externalWaterML + Σ visible local entries`. `externalWaterML` is today's HealthKit water minus every sample whose `SayoneEntryID` exists in the local journal. | Nothing is counted twice, reads while locked are safe, and there is no entry-sync protocol. This fixes the P1 TodayMath race. |
| D9 | Health writer | **Only the device that was tapped** writes or deletes an entry's samples. Deleting a row that belongs to the other device is attempted once; if nothing is deleted, the user is told honestly. | Avoids double writes and depending on unverified cross-source deletes. |
| D10 | Phone to watch | `WCSession.updateApplicationContext` sends only the **catalog** (drinks, presets, goal), one way from phone to watch. It carries an `Int64` revision and the newest revision wins. | The catalog is the only shared data that Health does not already carry. |
| D11 | Journal concurrency | One JSON file per entry. Every status change is a read-modify-write under an exclusive `flock` on `Journal/.lock`. The state machine never moves out of `pendingDelete` except to `deleted`. | App, widget and Siri processes run concurrently. This fixes the P1 lost-update and pending-delete must-fixes. |
| D12 | One-tap intent | `QuickLogIntent(drinkID:volumeML:drinkName:)`. Every parameter is a primitive with a default. It runs in the widget process. | Widgets never resolve parameters. An unknown drink is logged under its own name, not silently as water. |
| D13 | Per-instance config | `AppIntentConfiguration` + `SelectPresetIntent(preset: PresetEntity?)`. On watchOS 11–25, `recommendations()` returns one recommendation per preset (at most 12). On watchOS 26+ it returns `[]`. | Every complication, Smart Stack widget or Home Screen widget can hold a different preset. |
| D14 | Controls | One configurable iOS 18 Control. On watchOS 26 the system mirrors it to the watch, where it runs on the iPhone. A native watch Control is **deferred**. | Keeps limited-availability `WidgetBundleBuilder` paths out of v1. |
| D15 | Siri | App Intents + `AppShortcutsProvider` compiled into **both apps**, with 4 App Shortcuts and en+ru phrases in `AppShortcuts.xcstrings`. | No SiriKit, works on the watch, fits a free team. |
| D16 | Localization | English is the development language, with Russian. **Static UI text:** `Localizable.xcstrings` is generated from per-lane JSON fragments. **Composed runtime text** (volumes, drink names, Siri dialogs, toasts): `SayoneCore.Phrasebook`/`VolumeFormat`. **Siri phrases:** hand-written `AppShortcuts.xcstrings`. **Usage strings:** `InfoPlist.strings`. | No merge conflicts, no format specifiers inside the catalog, and runtime text can be tested on Linux. |
| D17 | Water accounting | Every built-in drink counts **100 %** of its volume as `dietaryWater`. The share is editable per drink from 10 to 100 %. | "All of it must land in Health"; the app makes no medical hydration claims. |
| D18 | Undo | Widget/in-app window 10 min (`UndoPolicy.widgetWindow`), voice window 3 h (`voiceWindow`), toast 5 s. | A stale widget undo button cannot delete an old drink. |
| D19 | Double taps | Taps from widgets and controls within 2 s with the same drink and volume are collapsed into one entry (`LogDedupe`). App taps are **not** collapsed. | Guards against the rapid-tap and reload lag of a widget without eating deliberate taps in the app. |
| D20 | CI | Linux job: lint + `swiftc -parse` + `swift test`. One `macos-26` job: xcodegen, then iOS scheme, watch scheme, App Intents metadata check and an unsigned device build (advisory). | Most errors are caught in about 1 min on Linux, and one macOS job shows every target's errors. |
| D21 | Generated project | The `SayoneHealth.xcodeproj`, plists and entitlements generated by XcodeGen 2.46.0 are **committed**. | The user can open the project tomorrow without installing XcodeGen. |
| D22 | Dependencies | No third-party dependencies. | |
| D23 | watchOS 11-only APIs | Isolated in `Watch/Widgets/WatchWidgetFeatures.swift` and `Watch/App/WatchAppFeatures.swift`. | Dropping the watch target to watchOS 10 for an old watch means editing 2 files plus `project.yml`. |

---

## 2. Targets

### 2.1 Target table

| Target | XcodeGen `type` / `platform` | Bundle ID | Sources (folders) | Dependencies | Embedded in |
|---|---|---|---|---|---|
| `SayoneHealth` | `application` / iOS | `$(BUNDLE_ID_PREFIX)` | `iOS/App`, `Shared/Core`, `Shared/Intents`, `Shared/AppOnly`, `Shared/Resources` | package `SayoneCore`, target `SayoneHealthWidgets`, target `SayoneHealthWatch` | — |
| `SayoneHealthWidgets` | `app-extension` / iOS | `$(BUNDLE_ID_PREFIX).widgets` | `iOS/Widgets`, `Shared/Core`, `Shared/Intents`, `Shared/WidgetUI`, `Shared/Resources` | package `SayoneCore` | iOS app → *Embed Foundation Extensions* (PlugIns) |
| `SayoneHealthWatch` | `application` / watchOS (single-target watch app; **never** `application.watchapp2`) | `$(BUNDLE_ID_PREFIX).watchkitapp` | `Watch/App`, `Shared/Core`, `Shared/Intents`, `Shared/AppOnly`, `Shared/Resources` | package `SayoneCore`, target `SayoneHealthWatchWidgets` | iOS app → *Embed Watch Content* (`$(CONTENTS_FOLDER_PATH)/Watch`, dstSubfolderSpec 16) |
| `SayoneHealthWatchWidgets` | `app-extension` / watchOS | `$(BUNDLE_ID_PREFIX).watchkitapp.widgets` | `Watch/Widgets`, `Shared/Core`, `Shared/Intents`, `Shared/WidgetUI`, `Shared/Resources` | package `SayoneCore` | watch app → *Embed Foundation Extensions* (PlugIns) |

- `SayoneCore` is linked statically into all four targets and never embedded.
- Shared schemes exist only for `SayoneHealth` and `SayoneHealthWatch` (`scheme: {}`).
- `ARCHS` is never set, so it stays `$(ARCHS_STANDARD)`; real watches build arm64 and arm64_32.

**Info.plist keys.** XcodeGen `info:` blocks write these files and they are committed.

| Key | iOS app | iOS widgets | watch app | watch widgets |
|---|:-:|:-:|:-:|:-:|
| `CFBundleDisplayName` = SayoneHealth | ✓ | ✓ | ✓ | ✓ |
| `CFBundleShortVersionString` = `$(MARKETING_VERSION)`, `CFBundleVersion` = `$(CURRENT_PROJECT_VERSION)` | ✓ | ✓ | ✓ | ✓ |
| `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` | ✓ | ✓ | ✓ | ✓ |
| `SayoneAppGroupID` = `$(APP_GROUP_ID)` | ✓ | ✓ | ✓ | ✓ |
| `LSRequiresIPhoneOS`, `UILaunchScreen {}`, `UIApplicationSceneManifest {UIApplicationSupportsMultipleScenes: false}`, portrait only | ✓ | | | |
| `CFBundleURLTypes` (scheme `sayonehealth`) | ✓ | | ✓ | |
| `INAlternativeAppNames` = Sayone, Сейон, Сейон Хелс | ✓ | | ✓ | |
| `WKApplication` = true, `WKCompanionAppBundleIdentifier` = `$(BUNDLE_ID_PREFIX)`, `WKRunsIndependentlyOfCompanionApp` = true | | | ✓ | |
| `NSExtension.NSExtensionPointIdentifier` = `com.apple.widgetkit-extension` | | ✓ | | ✓ |

`NSExtension` MUST NOT appear in either app plist; lint checks this. There are no `UIBackgroundModes`,
no `NSSiriUsageDescription` and no `NSSupportsLiveActivities`.

**Entitlements** are identical on all 4 targets: `com.apple.developer.healthkit = true`,
`com.apple.developer.healthkit.access = []`, `com.apple.security.application-groups = [$(APP_GROUP_ID)]`.
Nothing else. Lint forbids `com.apple.developer.siri`, `aps-environment`, anything containing `icloud`,
`com.apple.developer.associated-domains`, and `health-records`.

**Asset catalogs.**
- `iOS/App/Assets.xcassets/AppIcon.appiconset` and `Watch/App/Assets.xcassets/AppIcon.appiconset` each
  hold one 1024×1024 RGB PNG, with `"idiom":"universal"` and `"platform":"ios"` or `"watchos"`.
- Both catalogs are generated by `scripts/make_icons.py` and committed.
- The XcodeGen presets set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`, so the set must exist.
- No AccentColor asset is needed. The presets do not reference one.

### 2.2 `project.yml` (verbatim; generated cleanly by the Linux build of XcodeGen 2.46.0 during this design)

```yaml
name: SayoneHealth
options:
  minimumXcodeGenVersion: 2.44.1
  xcodeVersion: "26.0"
  developmentLanguage: en
  createIntermediateGroups: true
  deploymentTarget:
    iOS: "18.0"
    watchOS: "11.0"
configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig
settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
    SWIFT_EMIT_LOC_STRINGS: NO
    REGISTER_APP_GROUPS: YES
packages:
  SayoneCore:
    path: Packages/SayoneCore
targets:
  SayoneHealth:
    type: application
    platform: iOS
    sources:
      - path: iOS/App
        excludes: ["**/*.md"]
      - path: Shared/Core
        excludes: ["**/*.md"]
      - path: Shared/Intents
        excludes: ["**/*.md"]
      - path: Shared/AppOnly
        excludes: ["**/*.md"]
      - path: Shared/Resources
        excludes: ["**/*.md"]
    dependencies:
      - package: SayoneCore
      - target: SayoneHealthWidgets
      - target: SayoneHealthWatch
    info:
      path: iOS/App/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        CFBundleURLTypes:
          - CFBundleURLName: $(BUNDLE_ID_PREFIX)
            CFBundleURLSchemes: [sayonehealth]
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total from all your devices."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
        INAlternativeAppNames:
          - INAlternativeAppName: Sayone
          - INAlternativeAppName: Сейон
          - INAlternativeAppName: Сейон Хелс
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: iOS/App/SayoneHealth.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX)
        TARGETED_DEVICE_FAMILY: "1"
    scheme: {}
  SayoneHealthWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: iOS/Widgets
        excludes: ["**/*.md"]
      - path: Shared/Core
        excludes: ["**/*.md"]
      - path: Shared/Intents
        excludes: ["**/*.md"]
      - path: Shared/WidgetUI
        excludes: ["**/*.md"]
      - path: Shared/Resources
        excludes: ["**/*.md"]
    dependencies:
      - package: SayoneCore
    info:
      path: iOS/Widgets/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total from all your devices."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: iOS/Widgets/SayoneHealthWidgets.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).widgets
        TARGETED_DEVICE_FAMILY: "1"
        SKIP_INSTALL: YES
  SayoneHealthWatch:
    type: application
    platform: watchOS
    sources:
      - path: Watch/App
        excludes: ["**/*.md"]
      - path: Shared/Core
        excludes: ["**/*.md"]
      - path: Shared/Intents
        excludes: ["**/*.md"]
      - path: Shared/AppOnly
        excludes: ["**/*.md"]
      - path: Shared/Resources
        excludes: ["**/*.md"]
    dependencies:
      - package: SayoneCore
      - target: SayoneHealthWatchWidgets
    info:
      path: Watch/App/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        WKApplication: true
        WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX)
        WKRunsIndependentlyOfCompanionApp: true
        CFBundleURLTypes:
          - CFBundleURLName: $(BUNDLE_ID_PREFIX).watchkitapp
            CFBundleURLSchemes: [sayonehealth]
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total from all your devices."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
        INAlternativeAppNames:
          - INAlternativeAppName: Sayone
          - INAlternativeAppName: Сейон
          - INAlternativeAppName: Сейон Хелс
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: Watch/App/SayoneHealthWatch.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp
    scheme: {}
  SayoneHealthWatchWidgets:
    type: app-extension
    platform: watchOS
    sources:
      - path: Watch/Widgets
        excludes: ["**/*.md"]
      - path: Shared/Core
        excludes: ["**/*.md"]
      - path: Shared/Intents
        excludes: ["**/*.md"]
      - path: Shared/WidgetUI
        excludes: ["**/*.md"]
      - path: Shared/Resources
        excludes: ["**/*.md"]
    dependencies:
      - package: SayoneCore
    info:
      path: Watch/Widgets/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show today's total from all your devices."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
        SayoneAppGroupID: $(APP_GROUP_ID)
    entitlements:
      path: Watch/Widgets/SayoneHealthWatchWidgets.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp.widgets
```

Results from the validation run, which the §8 preflight re-checks:
- exactly **1** `Embed Watch Content` phase definition, with `dstSubfolderSpec = 16` and `dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"`
- exactly **2** `Embed Foundation Extensions` phase definitions
- shared schemes `SayoneHealth.xcscheme` and `SayoneHealthWatch.xcscheme`
- `knownRegions` containing `en` and `ru`
- deployment targets 18.0 and 11.0
- the Cyrillic `INAlternativeAppNames` serialized correctly

### 2.3 `Config/Base.xcconfig` (verbatim) and `Config/Local.xcconfig.example`

```
// Change BUNDLE_ID_PREFIX and APP_GROUP_ID together (e.g. in Local.xcconfig) if the ID is taken on your team.
BUNDLE_ID_PREFIX = com.sayoneone.sayonehealth
APP_GROUP_ID = group.com.sayoneone.sayonehealth
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM =
#include? "Local.xcconfig"
```

`Local.xcconfig.example` contains:

```
DEVELOPMENT_TEAM = ABCDE12345
// BUNDLE_ID_PREFIX = com.yourname.sayonehealth
// APP_GROUP_ID = group.com.yourname.sayonehealth
```

`Config/Local.xcconfig` is already in `.gitignore`.

### 2.4 `Packages/SayoneCore/Package.swift` (verbatim)

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

---

## 3. Repository file tree

The Swift files in each shared folder compile into the targets marked below. Codes:
**i** = SayoneHealth (iOS app), **iw** = SayoneHealthWidgets, **w** = SayoneHealthWatch,
**ww** = SayoneHealthWatchWidgets.

| Folder | i | iw | w | ww | Owner lane |
|---|:-:|:-:|:-:|:-:|---|
| `Packages/SayoneCore` (linked, static) | ✓ | ✓ | ✓ | ✓ | E2 |
| `Shared/Core` | ✓ | ✓ | ✓ | ✓ | E3 |
| `Shared/Intents` | ✓ | ✓ | ✓ | ✓ | E4 |
| `Shared/WidgetUI` | | ✓ | | ✓ | E4 |
| `Shared/AppOnly` (except `Siri/`) | ✓ | | ✓ | | E3 |
| `Shared/AppOnly/Siri` | ✓ | | ✓ | | E6 |
| `Shared/Resources` | ✓ | ✓ | ✓ | ✓ | E1 (generated) |
| `iOS/App` | ✓ | | | | E5 (Swift), E1 (assets, plist, lproj) |
| `iOS/Widgets` | | ✓ | | | E4 (Swift), E1 (plist, entitlements) |
| `Watch/App` | | | ✓ | | E6 (Swift), E1 (assets, plist, lproj) |
| `Watch/Widgets` | | | | ✓ | E4 (Swift), E1 (plist, entitlements) |

Every Swift file name MUST be unique across the whole repository, excluding `Packages/**/Tests`.
Lint checks this, because Xcode fails with "filename used twice" otherwise.

```
sayonehealth/
├─ project.yml                          E1  XcodeGen spec (§2.2)
├─ SayoneHealth.xcodeproj/              E1  GENERATED by xcodegen 2.46.0, committed
├─ Config/
│  ├─ Base.xcconfig                     E1  bundle prefix, group, versions, team include (§2.3)
│  └─ Local.xcconfig.example            E1  template for the tester's team ID
├─ README.md                            E1  Russian: what it is, how to build and run, link to TESTING
├─ docs/
│  ├─ TESTING.ru.md                     E1  device and simulator test checklist (§8.5)
│  └─ design/ARCHITECTURE.md, rubric.md     this file and the judging rubric
├─ .github/workflows/
│  ├─ ci.yml                            E1  Linux + macOS CI (§8.1)
│  ├─ xcode27.yml                       E1  advisory Xcode 27 build (workflow_dispatch + main)
│  └─ probe.yml                         (existing; leave untouched)
├─ scripts/
│  ├─ lint.py                           E1  repo lint (§5.8), stdlib-only Python 3
│  ├─ build_strings.py                  E1  Localization/*.json -> Shared/Resources/Localizable.xcstrings (--check)
│  ├─ check_appintents.py               E1  App Intents metadata gate on CI build logs and products
│  ├─ preflight.sh                      E1  local Linux pre-push checks (§8.2)
│  └─ make_icons.py                     E1  writes the two AppIcon PNGs + Contents.json (zlib, no PIL)
├─ Localization/                            per-lane string fragments (§6)
│  ├─ shared.json                       E3
│  ├─ widgets.json                      E4
│  ├─ ios.json                          E5
│  ├─ watch.json                        E6
│  └─ siri.json                         E6
├─ Packages/SayoneCore/                 E2  (i, iw, w, ww)
│  ├─ Package.swift
│  ├─ Sources/SayoneCore/
│  │  ├─ Models/Enums.swift             BuiltInDrink, DrinkTint, DeviceKind, HealthSyncStatus, HealthComponent, LogSource, AppLanguage, CatalogRole
│  │  ├─ Models/Nutrients.swift         NutrientsPer100ML, Nutrients
│  │  ├─ Models/Drink.swift             Drink (+ name/accusative/unknown)
│  │  ├─ Models/Preset.swift            Preset, ResolvedPreset, PresetDisplay
│  │  ├─ Models/UserSettings.swift      UserSettings
│  │  ├─ Models/Catalog.swift           Catalog (revision Int64, sanitize, presetDisplays)
│  │  ├─ Models/IntakeEntry.swift       IntakeEntry (one logged drink on THIS device)
│  │  ├─ Models/HealthSnapshot.swift    HealthSnapshot (cached external water for today)
│  │  ├─ Models/HealthWaterSample.swift HealthWaterSample (HK water sample as plain data)
│  │  ├─ Models/Summaries.swift         TodaySummary, DayTotal, TodayRow
│  │  ├─ Logic/BuiltInCatalog.swift     built-in drinks, default presets, custom symbol list
│  │  ├─ Logic/NutrientMath.swift       clamps + nutrient computation
│  │  ├─ Logic/DrinkResolver.swift      ResolvedDrink, DrinkResolver (catalog → built-in → unknown)
│  │  ├─ Logic/IntakeFactory.swift      builds an IntakeEntry snapshot
│  │  ├─ Logic/LogDedupe.swift          2-second widget/control double-tap guard
│  │  ├─ Logic/UndoPolicy.swift         undo windows + candidate selection
│  │  ├─ Logic/TodayMath.swift          snapshot + today summary + local daily totals (THE total rule)
│  │  ├─ Logic/TodayListMerger.swift    today rows = local visible + other-device HK samples
│  │  ├─ Logic/CatalogEditor.swift      every catalog mutation (bumps revision)
│  │  ├─ Logic/HealthSamplePlan.swift   HealthMetadata keys, MetadataValue, HealthSampleSpec, HealthSamplePlan
│  │  ├─ Logic/DeepLink.swift           sayonehealth:// URLs
│  │  ├─ Logic/WidgetTimeline.swift     next refresh date
│  │  ├─ Logic/CatalogSyncPayload.swift WCSession application-context codec + apply rule
│  │  ├─ Text/VolumeFormat.swift        "250 мл", "1,5 л", "1,2 из 2 л" (ru/en)
│  │  ├─ Text/Phrasebook.swift          drink names (nom/acc), Siri dialogs, toasts (ru/en)
│  │  ├─ Storage/CoreJSON.swift         shared JSONEncoder/Decoder
│  │  ├─ Storage/FileLock.swift         flock-based cross-process lock
│  │  ├─ Storage/JournalStore.swift     Journal/<UUID>.json state machine (+ result enums)
│  │  ├─ Storage/CatalogStore.swift     catalog.json with author/replica fallback
│  │  └─ Storage/SnapshotStore.swift    health-snapshot.json, save-if-newer
│  └─ Tests/SayoneCoreTests/            NutrientMathTests, DrinkResolverTests, LogDedupeTests, UndoPolicyTests,
│                                       TodayMathTests, TodayListMergerTests, CatalogEditorTests, CatalogCodecTests,
│                                       CatalogStoreTests, JournalStoreTests, SnapshotStoreTests, HealthSamplePlanTests,
│                                       DeepLinkTests, WidgetTimelineTests, CatalogSyncPayloadTests, VolumeFormatTests,
│                                       PhrasebookTests  (XCTest; fixtures as string literals)
├─ Shared/
│  ├─ Core/                             E3  (i, iw, w, ww)
│  │  ├─ AppGroup.swift                 container, store instances, fallback
│  │  ├─ ThisDevice.swift               ThisDevice, ProcessKind, AppLanguage.current
│  │  ├─ AppLog.swift                   os.Logger categories
│  │  ├─ HealthTypes.swift              HKDrinkTypes (type/unit table, share/read sets)
│  │  ├─ HealthGateway.swift            HealthWriteAuth, HealthGatewayError, HealthGateway (all HK I/O)
│  │  ├─ DrinkLogger.swift              LogOutcome, DeleteOutcome, UndoResult, DrinkLogger (log/flush/delete/undo)
│  │  ├─ TodayService.swift             TodayState, TodayService (snapshot refresh, summary, rows, history)
│  │  ├─ WidgetRefresher.swift          WidgetKinds, WidgetRefresher
│  │  ├─ PresetDisplays.swift           PresetDisplays + PresetDisplay.title / Drink.displayName conveniences
│  │  ├─ VolumeText.swift               VolumeText (VolumeFormat with AppLanguage.current)
│  │  ├─ SiriText.swift                 SiriText (Phrasebook with AppLanguage.current)
│  │  └─ TintPalette.swift              DrinkTint.color / .background (SwiftUI)
│  ├─ Intents/                          E4  (i, iw, w, ww)
│  │  ├─ PresetEntity.swift             PresetEntity + PresetQuery
│  │  ├─ SelectPresetIntent.swift       WidgetConfigurationIntent
│  │  ├─ QuickLogIntent.swift           one-tap log intent (widgets + control)
│  │  ├─ UndoLastIntent.swift           undo (widget button + App Shortcut)
│  │  └─ InAppProcess.swift             #if os(iOS) && INTENTS_IN_APP_PROCESS escape hatch
│  ├─ WidgetUI/                         E4  (iw, ww)
│  │  ├─ QuickLogProvider.swift         QuickLogEntry + QuickLogProvider (recommendations under #if os(watchOS))
│  │  ├─ QuickLogWidget.swift           QuickLogWidget (families per platform)
│  │  ├─ QuickLogViews.swift            QuickLogView + per-family subviews
│  │  ├─ FavoritesWidget.swift          FavoritesEntry + FavoritesProvider + FavoritesWidget
│  │  └─ FavoritesViews.swift           FavoritesView (+ iOS medium layout)
│  ├─ AppOnly/                          (i, w)
│  │  ├─ AppModel.swift                 E3  LogToast, ConfirmRequest, DiagnosticsInfo, AppModel
│  │  ├─ CatalogSync.swift              E3  WCSession delegate (phone push / watch receive)
│  │  ├─ HealthAuthorization.swift      E3  HealthGateway.requestAuthorization() (apps only!)
│  │  └─ Siri/                          E6
│  │     ├─ WaterAmount.swift           AppEnum glass/can/halfLiter/liter
│  │     ├─ DrinkEntity.swift           DrinkEntity + DrinkQuery (EntityStringQuery)
│  │     ├─ LogWaterIntent.swift
│  │     ├─ LogDrinkIntent.swift
│  │     ├─ TodayTotalIntent.swift
│  │     ├─ SayoneShortcuts.swift       AppShortcutsProvider (4 shortcuts)
│  │     └─ AppShortcuts.xcstrings      en + ru phrase sets (§7, verbatim)
│  └─ Resources/
│     └─ Localizable.xcstrings          GENERATED by scripts/build_strings.py (all 4 targets)
├─ iOS/
│  ├─ App/                              (i)
│  │  ├─ SayoneHealthApp.swift          E5  @main App
│  │  ├─ Views/TodayView.swift          E5  root screen
│  │  ├─ Views/ProgressCard.swift       E5  ring + "1,2 из 2 л" + pending badge
│  │  ├─ Views/PresetGrid.swift         E5  2-column one-tap buttons
│  │  ├─ Views/TodayListSection.swift   E5  today rows, swipe delete, device glyph
│  │  ├─ Views/LogDrinkSheet.swift      E5  "Другой напиток…" picker + volume
│  │  ├─ Views/HistoryView.swift        E5  7-day capsule bars
│  │  ├─ Views/SettingsView.swift       E5  goal, nutrients toggle, links, Siri, Health, Watch
│  │  ├─ Views/DrinksListView.swift     E5
│  │  ├─ Views/DrinkEditorView.swift    E5
│  │  ├─ Views/PresetsListView.swift    E5
│  │  ├─ Views/PresetEditorView.swift   E5
│  │  ├─ Views/OnboardingView.swift     E5  Health permission (write + READ water)
│  │  ├─ Views/ConfirmLogSheet.swift    E5  deep-link confirm (never auto-logs)
│  │  ├─ Views/ToastView.swift          E5  "Записано · … · Отменить"
│  │  ├─ Views/DiagnosticsView.swift    E5  App Group / pending / snapshot / auth status
│  │  ├─ Assets.xcassets/               E1  AppIcon (generated PNG)
│  │  ├─ en.lproj/InfoPlist.strings     E1
│  │  ├─ ru.lproj/InfoPlist.strings     E1
│  │  ├─ Info.plist                     GENERATED
│  │  └─ SayoneHealth.entitlements      GENERATED
│  └─ Widgets/                          (iw)
│     ├─ SayoneWidgetsBundle.swift      E4  @main WidgetBundle (QuickLog, Favorites, Control)
│     ├─ QuickLogControl.swift          E4  SelectPresetControlIntent + QuickLogControl
│     ├─ Info.plist                     GENERATED
│     └─ SayoneHealthWidgets.entitlements GENERATED
└─ Watch/
   ├─ App/                              (w)
   │  ├─ SayoneWatchApp.swift           E6  @main App
   │  ├─ WatchAppFeatures.swift         E6  watchOS-11-only helpers (double tap)
   │  ├─ Views/WatchRootView.swift      E6
   │  ├─ Views/TodayRingRow.swift       E6
   │  ├─ Views/LoggedBanner.swift       E6
   │  ├─ Views/PresetRow.swift          E6
   │  ├─ Views/WatchTodayRow.swift      E6
   │  ├─ Views/DrinkPickerView.swift    E6
   │  ├─ Views/VolumePickerView.swift   E6  Digital Crown
   │  ├─ Views/ConfirmLogView.swift     E6  deep-link confirm
   │  ├─ Views/WatchOnboardingView.swift E6
   │  ├─ Views/ComplicationHelpView.swift E6
   │  ├─ Assets.xcassets/               E1
   │  ├─ en.lproj/InfoPlist.strings     E1
   │  ├─ ru.lproj/InfoPlist.strings     E1
   │  ├─ Info.plist                     GENERATED
   │  └─ SayoneHealthWatch.entitlements GENERATED
   └─ Widgets/                          (ww)
      ├─ SayoneWatchWidgetsBundle.swift E4  @main WidgetBundle (QuickLog, Favorites)
      ├─ WatchWidgetFeatures.swift      E4  watchOS-11-only: sayonePrimaryAction(), WatchFavoritesGroup
      ├─ Info.plist                     GENERATED
      └─ SayoneHealthWatchWidgets.entitlements GENERATED
```

---

## 4. Shared contracts (frozen)

Type names avoid SDK collisions. NEVER declare our own types named `Settings`, `Entry`, `Label`, `Link`,
`Timeline`, `Image`, `Color`, `Text` or `Widget`.

### 4.0 Constants registry (single source of every magic string)

| Constant | Value | Declared in |
|---|---|---|
| URL scheme | `sayonehealth` | `DeepLink.scheme` |
| Deep links | `sayonehealth://today`, `sayonehealth://log?drink=<drinkID>&ml=<Int>`, `sayonehealth://health` | `DeepLink` |
| App Group fallback | `group.com.sayoneone.sayonehealth` | `AppGroup.identifier` |
| Info.plist key for the group | `SayoneAppGroupID` | `AppGroup` |
| Store root | `<group container>/SayoneHealth/` (fallback `<Application Support>/SayoneHealth/`) | `AppGroup.rootURL` |
| Journal | `<root>/Journal/<UUID.uuidString>.json`, lock `<root>/Journal/.lock` | `JournalStore` |
| Catalog | `<root>/catalog.json`; corrupt copy `<root>/catalog.json.bak` | `CatalogStore` |
| Snapshot | `<root>/health-snapshot.json`, lock `<root>/.snapshot.lock` | `SnapshotStore` |
| HK custom metadata | `SayoneEntryID`, `SayoneDrinkID`, `SayoneVolumeML`, `SayoneOrigin` | `HealthMetadata` |
| HK sync identifier | `"\(entryID.uuidString).\(component.rawValue)"`, e.g. `8C1E…9A.water`; sync version `1` | `HealthMetadata` |
| Widget kinds | `QuickLogWidget`, `FavoritesWidget`; control kind `QuickLogControl` | `WidgetKinds` |
| WC payload keys | `catalog` (Data, JSON), `revision` (NSNumber Int64) | `CatalogSyncPayload` |
| Logger subsystem | `com.sayoneone.sayonehealth`; categories `intake`, `health`, `widget`, `sync`, `store` | `AppLog` |
| Built-in preset IDs | `water-250`, `water-500`, `colaZero-330`, `coffee-200`, `tea-250` | `BuiltInCatalog` |
| User IDs | drinks `custom-<UUID>`, presets `preset-<UUID>` | `CatalogEditor` |

### 4.1 `SayoneCore` public API (*interface*; E2)

Every declaration is `public`. Every public struct declares its public `init` as shown, because Swift
does not synthesize public memberwise initializers. The constant values shown are normative.

```swift
import Foundation

// ===== Models/Enums.swift
public enum BuiltInDrink: String, Codable, CaseIterable, Sendable {
    case water, sparklingWater, colaZero, coffee, tea, juice, milk
}
public enum DrinkTint: String, Codable, CaseIterable, Sendable {
    case blue, teal, brown, red, orange, green, purple, gray
    public init(from decoder: Decoder) throws          // unknown raw value -> .blue (forward compatible)
}
public enum DeviceKind: String, Codable, CaseIterable, Sendable { case phone, watch }
public enum HealthSyncStatus: String, Codable, CaseIterable, Sendable {
    case pending        // journaled; not known to be in Health yet
    case saved          // this device saved its samples
    case pendingDelete  // user deleted; samples may still exist; hidden everywhere
    case deleted        // tombstone; samples removed or never existed; hidden; pruned after 8 days
}
public enum HealthComponent: String, Codable, CaseIterable, Sendable { case water, caffeine, energy, sugar } // write/delete order
public enum LogSource: String, Codable, CaseIterable, Sendable {
    case app, widget, siri, deepLink                     // controls use .widget
    public init(from decoder: Decoder) throws          // unknown -> .app
}
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case en, ru
    public init(preferredLocalizations: [String])      // first element hasPrefix("ru") -> .ru, otherwise .en
}
public enum CatalogRole: Sendable { case author, replica }   // phone = author, watch = replica

// ===== Models/Nutrients.swift
public struct NutrientsPer100ML: Codable, Hashable, Sendable {
    public var caffeineMG: Double
    public var energyKcal: Double
    public var sugarG: Double
    public init(caffeineMG: Double = 0, energyKcal: Double = 0, sugarG: Double = 0)
}
public struct Nutrients: Codable, Hashable, Sendable {
    public var waterML: Double
    public var caffeineMG: Double
    public var energyKcal: Double
    public var sugarG: Double
    public init(waterML: Double = 0, caffeineMG: Double = 0, energyKcal: Double = 0, sugarG: Double = 0)
    public func amount(of component: HealthComponent) -> Double
}

// ===== Models/Drink.swift
public struct Drink: Codable, Hashable, Identifiable, Sendable {
    public var id: String                   // built-in: BuiltInDrink.rawValue; user: "custom-<UUID>"
    public var builtIn: BuiltInDrink?
    public var customName: String?
    public var symbol: String               // SF Symbol name
    public var tint: DrinkTint
    public var hydrationFactor: Double      // share of volume written as dietaryWater (NutrientMath.hydrationRange)
    public var per100ML: NutrientsPer100ML
    public var defaultVolumeML: Int
    public var isArchived: Bool
    public init(id: String, builtIn: BuiltInDrink?, customName: String?, symbol: String, tint: DrinkTint,
                hydrationFactor: Double, per100ML: NutrientsPer100ML, defaultVolumeML: Int, isArchived: Bool = false)
    public func name(_ lang: AppLanguage) -> String        // non-empty trimmed customName ?? Phrasebook.drinkName(builtIn) ?? Phrasebook.genericDrink
    public func accusative(_ lang: AppLanguage) -> String  // customName ?? Phrasebook.drinkAccusative(builtIn) ?? genericDrink.lowercased()
    public static func unknown(id: String, name: String?) -> Drink
    // unknown: builtIn nil, customName = name if non-empty else nil, symbol "cup.and.saucer.fill", tint .gray,
    //          hydrationFactor 1.0, per100ML zero, defaultVolumeML 250, isArchived false
}

// ===== Models/Preset.swift
public struct Preset: Codable, Hashable, Identifiable, Sendable {
    public var id: String                   // built-in "water-250" …; user "preset-<UUID>"
    public var drinkID: String
    public var volumeML: Int
    public init(id: String, drinkID: String, volumeML: Int)
}
public struct ResolvedPreset: Hashable, Identifiable, Sendable {
    public let preset: Preset
    public let drink: Drink
    public var id: String { get }           // preset.id
    public init(preset: Preset, drink: Drink)
}
public struct PresetDisplay: Codable, Hashable, Identifiable, Sendable {
    public let id: String                   // preset id
    public let drinkID: String
    public let drinkName: String            // localized when built, e.g. "Кола без сахара"
    public let symbol: String
    public let tint: DrinkTint
    public let volumeML: Int
    public init(id: String, drinkID: String, drinkName: String, symbol: String, tint: DrinkTint, volumeML: Int)
    public init(_ resolved: ResolvedPreset, lang: AppLanguage)
    public func localizedTitle(_ lang: AppLanguage) -> String   // drinkName + " · " + VolumeFormat.short(volumeML, lang)
    public static func builtInFallback(_ lang: AppLanguage) -> PresetDisplay   // "water-250", water, 250 ml; no I/O
}

// ===== Models/UserSettings.swift
public struct UserSettings: Codable, Hashable, Sendable {
    public static let goalRange: ClosedRange<Int> = 500...6000
    public var dailyGoalML: Int             // default 2000
    public var writeNutrients: Bool         // default true (caffeine/energy/sugar samples)
    public init(dailyGoalML: Int = 2000, writeNutrients: Bool = true)
}

// ===== Models/Catalog.swift
public struct Catalog: Codable, Hashable, Sendable {
    public static let currentVersion: Int = 1
    public static let maxPresets: Int = 12
    public var version: Int
    public var revision: Int64              // Int64 on purpose: epoch-ms overflows Int on arm64_32 watches
    public var updatedAt: Date
    public var drinks: [Drink]
    public var presets: [Preset]            // array order = display order; first 4 = iPhone favorites, first 3 = watch
    public var settings: UserSettings
    public init(version: Int, revision: Int64, updatedAt: Date, drinks: [Drink], presets: [Preset], settings: UserSettings)
    public static func makeDefault(revision: Int64 = 0, now: Date = Date()) -> Catalog
    public static func nextRevision(after current: Int64, now: Date) -> Int64  // max(current + 1, Int64(now.timeIntervalSince1970 * 1000))
    public func drink(id: String) -> Drink?                 // includes archived
    public var activeDrinks: [Drink] { get }                // !isArchived, catalog order
    public func resolvedPresets() -> [ResolvedPreset]       // skips presets whose drink is missing
    public func presetDisplays(_ lang: AppLanguage) -> [PresetDisplay]
    public func sanitized() -> Catalog
}

// ===== Models/IntakeEntry.swift
public struct IntakeEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date                   // whole milliseconds (IntakeFactory rounds)
    public let drinkID: String
    public let drinkName: String            // localized at log time; HK FoodType
    public let symbol: String
    public let volumeML: Int                // poured volume
    public let nutrients: Nutrients         // computed at log time
    public let origin: DeviceKind
    public let source: LogSource
    public var health: HealthSyncStatus
    public var healthSavedAt: Date?
    public var deletedAt: Date?
    public init(id: UUID, date: Date, drinkID: String, drinkName: String, symbol: String, volumeML: Int,
                nutrients: Nutrients, origin: DeviceKind, source: LogSource,
                health: HealthSyncStatus = .pending, healthSavedAt: Date? = nil, deletedAt: Date? = nil)
    public var isVisible: Bool { get }      // health == .pending || health == .saved
}

// ===== Models/HealthSnapshot.swift
public struct HealthSnapshot: Codable, Hashable, Sendable {
    public var dayStart: Date
    public var externalWaterML: Double      // today's HK water NOT written by entries in this device's journal
    public var otherDeviceWaterML: Double   // part of external that carries SayoneEntryID (our app on the other device)
    public var readAt: Date                 // captured BEFORE the HK query was issued
    public init(dayStart: Date, externalWaterML: Double, otherDeviceWaterML: Double, readAt: Date)
}

// ===== Models/HealthWaterSample.swift
public struct HealthWaterSample: Hashable, Sendable {
    public let date: Date                   // sample startDate
    public let waterML: Double
    public let entryID: UUID?               // SayoneEntryID; nil for samples from other apps
    public let drinkID: String?             // SayoneDrinkID
    public let drinkName: String?           // HKMetadataKeyFoodType
    public let volumeML: Int?               // SayoneVolumeML
    public let origin: DeviceKind?          // SayoneOrigin
    public init(date: Date, waterML: Double, entryID: UUID?, drinkID: String?, drinkName: String?, volumeML: Int?, origin: DeviceKind?)
}

// ===== Models/Summaries.swift
public struct TodaySummary: Hashable, Sendable {
    public var waterML: Int                 // displayed total
    public var goalML: Int
    public var localWaterML: Int
    public var externalWaterML: Int
    public var otherDeviceWaterML: Int
    public var pendingCount: Int            // local entries with health == .pending (any day)
    public var lastLocal: IntakeEntry?      // newest visible local entry today
    public var undoAvailableUntil: Date?    // lastLocal.date + UndoPolicy.widgetWindow, only if > now
    public var healthReadAt: Date?          // snapshot.readAt if it is today's snapshot
    public var progress: Double { get }     // min(1, max(0, Double(waterML) / Double(max(goalML, 1))))
    public static let placeholder: TodaySummary   // waterML 1200, goalML 2000, rest zero/nil
    public init(waterML: Int, goalML: Int, localWaterML: Int, externalWaterML: Int, otherDeviceWaterML: Int,
                pendingCount: Int, lastLocal: IntakeEntry?, undoAvailableUntil: Date?, healthReadAt: Date?)
}
public struct DayTotal: Hashable, Identifiable, Sendable {
    public let dayStart: Date
    public let waterML: Int
    public var id: Date { get }             // dayStart
    public init(dayStart: Date, waterML: Int)
}
public struct TodayRow: Hashable, Identifiable, Sendable {
    public let id: UUID                     // entry id
    public let date: Date
    public let drinkName: String
    public let symbol: String?              // nil for other-device rows
    public let volumeML: Int
    public let waterML: Double
    public let origin: DeviceKind?
    public let isLocal: Bool                // true = in this device's journal
    public let isPendingHealth: Bool        // local && health == .pending
    public init(id: UUID, date: Date, drinkName: String, symbol: String?, volumeML: Int, waterML: Double,
                origin: DeviceKind?, isLocal: Bool, isPendingHealth: Bool)
}

// ===== Logic/BuiltInCatalog.swift
public enum BuiltInCatalog {
    public static let fallbackDrinkID: String = "water"
    public static let fallbackPresetID: String = "water-250"
    public static let customSymbols: [String]           // §5.1 list, 12 names
    public static func drink(_ kind: BuiltInDrink) -> Drink
    public static func drink(id: String) -> Drink?      // BuiltInDrink(rawValue: id).map(drink(_:))
    public static var allDrinks: [Drink] { get }         // BuiltInDrink.allCases order
    public static var defaultPresets: [Preset] { get }   // water-250, water-500, colaZero-330, coffee-200, tea-250
}

// ===== Logic/NutrientMath.swift
public enum NutrientMath {
    public static let volumeRange: ClosedRange<Int> = 10...5000
    public static let hydrationRange: ClosedRange<Double> = 0.1...1.0
    public static func clampVolume(_ ml: Int) -> Int
    public static func clampHydration(_ factor: Double) -> Double
    public static func nutrients(for drink: Drink, volumeML: Int) -> Nutrients
}

// ===== Logic/DrinkResolver.swift
public struct ResolvedDrink: Hashable, Sendable {
    public let drink: Drink
    public let isKnown: Bool                // false => Drink.unknown was used
    public init(drink: Drink, isKnown: Bool)
}
public enum DrinkResolver {
    /// catalog.drink(id:) (archived included) → BuiltInCatalog.drink(id:) → Drink.unknown(id:, name: fallbackName)
    public static func resolve(drinkID: String, in catalog: Catalog, fallbackName: String) -> ResolvedDrink
}

// ===== Logic/IntakeFactory.swift
public enum IntakeFactory {
    /// Clamps volume, rounds date to whole ms, computes nutrients, health = .pending.
    public static func make(drink: Drink, displayName: String, volumeML: Int, date: Date,
                            origin: DeviceKind, source: LogSource, id: UUID = UUID()) -> IntakeEntry
}

// ===== Logic/LogDedupe.swift
public enum LogDedupe {
    public static let window: TimeInterval = 2
    /// Only when candidate.source == .widget: returns a visible existing entry with source .widget, same drinkID,
    /// same volumeML and |date difference| <= window. Otherwise nil.
    public static func duplicate(of candidate: IntakeEntry, in existing: [IntakeEntry]) -> IntakeEntry?
}

// ===== Logic/UndoPolicy.swift
public enum UndoPolicy {
    public static let widgetWindow: TimeInterval = 600
    public static let voiceWindow: TimeInterval = 10_800
    public static let toastDuration: TimeInterval = 5
    /// Newest visible entry with now - date in 0...window, else nil.
    public static func candidate(in local: [IntakeEntry], now: Date, window: TimeInterval) -> IntakeEntry?
}

// ===== Logic/TodayMath.swift
public enum TodayMath {
    public static func day(containing date: Date, calendar: Calendar = .current) -> DateInterval
    public static func nextDayStart(after date: Date, calendar: Calendar = .current) -> Date
    public static func makeSnapshot(samples: [HealthWaterSample], localEntryIDs: Set<UUID>, now: Date, readAt: Date,
                                    calendar: Calendar = .current) -> HealthSnapshot
    public static func summary(snapshot: HealthSnapshot?, local: [IntakeEntry], goalML: Int, now: Date,
                               calendar: Calendar = .current) -> TodaySummary
    public static func localDailyTotals(_ entries: [IntakeEntry], days: Int, now: Date,
                                        calendar: Calendar = .current) -> [DayTotal]   // oldest first, visible only
}

// ===== Logic/TodayListMerger.swift
public enum TodayListMerger {
    public static func merge(local: [IntakeEntry], health: [HealthWaterSample], day: DateInterval) -> [TodayRow]
}

// ===== Logic/CatalogEditor.swift  (every mutation: revision = Catalog.nextRevision(after:now:), updatedAt = now, then sanitized())
public enum CatalogEditor {
    @discardableResult
    public static func addCustomDrink(to c: inout Catalog, name: String, symbol: String, tint: DrinkTint,
                                      hydrationFactor: Double, per100ML: NutrientsPer100ML, defaultVolumeML: Int,
                                      now: Date = Date()) -> Drink
    public static func updateDrink(in c: inout Catalog, _ drink: Drink, now: Date = Date())       // built-ins: name fields ignored
    public static func archiveDrink(in c: inout Catalog, id: String, now: Date = Date())          // built-ins cannot be archived (no-op); removes its presets
    @discardableResult
    public static func addPreset(to c: inout Catalog, drinkID: String, volumeML: Int, now: Date = Date()) -> Preset?  // nil at maxPresets
    public static func updatePreset(in c: inout Catalog, _ preset: Preset, now: Date = Date())
    public static func removePreset(from c: inout Catalog, id: String, now: Date = Date())
    public static func movePresets(in c: inout Catalog, from source: IndexSet, to destination: Int, now: Date = Date()) // SwiftUI onMove semantics, implemented manually
    public static func setDailyGoal(in c: inout Catalog, ml: Int, now: Date = Date())
    public static func setWriteNutrients(in c: inout Catalog, _ on: Bool, now: Date = Date())
}

// ===== Logic/HealthSamplePlan.swift
public enum HealthMetadata {
    public static let entryIDKey: String = "SayoneEntryID"
    public static let drinkIDKey: String = "SayoneDrinkID"
    public static let volumeKey: String = "SayoneVolumeML"
    public static let originKey: String = "SayoneOrigin"
    public static let syncVersion: Int = 1
    public static func syncIdentifier(entryID: UUID, component: HealthComponent) -> String  // "\(entryID.uuidString).\(component.rawValue)"
    public static func minimumAmount(_ component: HealthComponent) -> Double                 // water 1, caffeine 0.5, energy 0.5, sugar 0.1
}
public enum MetadataValue: Hashable, Sendable { case string(String), number(Double) }
public struct HealthSampleSpec: Hashable, Sendable {
    public let component: HealthComponent
    public let amount: Double               // canonical unit: mL | mg | kcal | g
    public let date: Date                   // start == end == entry.date
    public let syncIdentifier: String
    public let syncVersion: Int
    public let foodType: String             // entry.drinkName
    public let custom: [String: MetadataValue]   // SayoneEntryID (.string uuidString), SayoneDrinkID, SayoneVolumeML (.number), SayoneOrigin (.string rawValue)
    public init(component: HealthComponent, amount: Double, date: Date, syncIdentifier: String, syncVersion: Int,
                foodType: String, custom: [String: MetadataValue])
}
public enum HealthSamplePlan {
    /// Water always first (if >= minimum); nutrients only if includeNutrients and amount >= minimum. Order = HealthComponent.allCases.
    public static func components(for entry: IntakeEntry, includeNutrients: Bool) -> [HealthComponent]
    public static func specs(for entry: IntakeEntry, includeNutrients: Bool) -> [HealthSampleSpec]
}

// ===== Logic/DeepLink.swift
public enum DeepLink: Hashable, Sendable {
    case today
    case confirmLog(drinkID: String, volumeML: Int)
    case healthAccess
    public static let scheme: String = "sayonehealth"
    public init?(url: URL)                  // host "today" | "log" (needs drink + integer ml) | "health"; else nil
    public var url: URL { get }             // sayonehealth://today | sayonehealth://log?drink=<id>&ml=<n> | sayonehealth://health
}

// ===== Logic/WidgetTimeline.swift
public enum WidgetTimeline {
    public static let refreshInterval: TimeInterval = 1800
    /// min(now + refreshInterval, nextDayStart(after: now), undoUntil if undoUntil > now)
    public static func nextRefresh(after now: Date, undoUntil: Date?, calendar: Calendar = .current) -> Date
}

// ===== Logic/CatalogSyncPayload.swift
public enum CatalogSyncPayload {
    public static let catalogKey: String = "catalog"
    public static let revisionKey: String = "revision"
    public static func encode(_ catalog: Catalog) throws -> [String: Any]    // [catalogKey: Data(CoreJSON), revisionKey: NSNumber(value: catalog.revision)]
    public static func decode(_ payload: [String: Any]) -> Catalog?          // nil if missing/corrupt; result sanitized()
    public static func shouldApply(received: Catalog, current: Catalog) -> Bool   // received.revision > current.revision
}

// ===== Text/VolumeFormat.swift   (U+00A0 NO-BREAK SPACE between number and unit; ru decimal comma, en decimal point)
public enum VolumeFormat {
    public static func short(_ ml: Int, _ lang: AppLanguage) -> String            // <1000: "250 мл"/"250 ml"; >=1000: "1 л","1,5 л"/"1 L","1.5 L"
    public static func plus(_ ml: Int, _ lang: AppLanguage) -> String             // "+" + short
    public static func compact(_ ml: Int, _ lang: AppLanguage) -> String          // <1000: "500"; >=1000: "1,5 л"/"1.5 L"
    public static func liters(_ ml: Int, _ lang: AppLanguage) -> String           // always litres, 1 fraction digit max: "0,3 л", "2 л"
    public static func progress(_ waterML: Int, goalML: Int, _ lang: AppLanguage) -> String         // "1,2 из 2 л" / "1.2 of 2 L"
    public static func progressCompact(_ waterML: Int, goalML: Int, _ lang: AppLanguage) -> String  // "1,2 / 2 л" / "1.2 / 2 L"
}

// ===== Text/Phrasebook.swift   (exact texts in §6.4)
public enum Phrasebook {
    public static func drinkName(_ d: BuiltInDrink, _ lang: AppLanguage) -> String
    public static func drinkAccusative(_ d: BuiltInDrink, _ lang: AppLanguage) -> String
    public static func genericDrink(_ lang: AppLanguage) -> String
    public static func logged(drinkName: String, volumeML: Int, summary: TodaySummary, savedToHealth: Bool,
                              healthAuthorized: Bool, _ lang: AppLanguage) -> String
    public static func duplicateIgnored(_ lang: AppLanguage) -> String
    public static func storeFailed(_ lang: AppLanguage) -> String
    public static func today(_ s: TodaySummary, _ lang: AppLanguage) -> String
    public static func undone(drinkName: String, volumeML: Int, _ lang: AppLanguage) -> String
    public static func undoQueued(drinkName: String, volumeML: Int, _ lang: AppLanguage) -> String
    public static func nothingToUndo(_ lang: AppLanguage) -> String
    public static func notDeletableHere(_ lang: AppLanguage) -> String
    public static func healthAccessMissing(_ lang: AppLanguage) -> String
    public static func toast(drinkName: String, volumeML: Int, _ lang: AppLanguage) -> String
}

// ===== Storage/CoreJSON.swift
public enum CoreJSON {
    public static func encoder() -> JSONEncoder     // outputFormatting [.sortedKeys], dateEncodingStrategy .millisecondsSince1970
    public static func decoder() -> JSONDecoder     // dateDecodingStrategy .millisecondsSince1970
}

// ===== Storage/FileLock.swift  (verbatim implementation in §5.1)
public enum FileLockError: Error, Equatable { case open(Int32), lock(Int32) }
public enum FileLock {
    public static func withExclusiveLock<T>(at url: URL, _ body: () throws -> T) throws -> T
}

// ===== Storage/JournalStore.swift
public enum JournalError: Error, Equatable { case io(String) }
public enum CreateResult: Equatable, Sendable {
    case created(IntakeEntry)
    case existing(IntakeEntry)      // a file with the same id already exists (idempotent re-log, e.g. confirm sheet)
    case duplicate(IntakeEntry)     // LogDedupe hit; returns the earlier entry
}
public enum MarkSavedResult: Equatable, Sendable { case marked, alreadySaved, deletedMeanwhile, missing }
public enum BeginDeleteResult: Equatable, Sendable {
    case began(previous: HealthSyncStatus, entry: IntakeEntry)   // previous is .pending or .saved
    case alreadyDeleting(IntakeEntry)
    case alreadyDeleted
    case notFound
}
public struct JournalStore: Sendable {
    public static let retentionDays: Int = 8
    public let directory: URL
    public init(directory: URL)                                    // creates the directory lazily on first write
    public func create(_ entry: IntakeEntry) throws -> CreateResult          // under lock
    public func entry(id: UUID) -> IntakeEntry?                              // lock-free read
    public func all() -> [IntakeEntry]                                       // lock-free; skips dotfiles, non-.json, unreadable; sorted by date asc
    public func entries(in interval: DateInterval) -> [IntakeEntry]
    public func needingFlush() -> [IntakeEntry]                              // .pending + .pendingDelete, oldest first
    public func markSaved(id: UUID, at date: Date) throws -> MarkSavedResult // under lock
    public func beginDelete(id: UUID, at date: Date) throws -> BeginDeleteResult // under lock
    public func finishDelete(id: UUID, at date: Date) throws                 // under lock; -> .deleted (deletedAt = date); no-op if missing
    @discardableResult
    public func prune(now: Date, calendar: Calendar = .current) throws -> Int // under lock; removes .saved/.deleted older than retentionDays
}

// ===== Storage/CatalogStore.swift
public struct CatalogStore: Sendable {
    public let fileURL: URL
    public let role: CatalogRole
    public init(fileURL: URL, role: CatalogRole)
    public func load(now: Date = Date()) -> Catalog     // never throws; always sanitized(); fallback rules §5.1
    public func save(_ catalog: Catalog) throws         // atomic write of sanitized catalog
}

// ===== Storage/SnapshotStore.swift
public struct SnapshotStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL)
    public func load() -> HealthSnapshot?
    public func saveIfNewer(_ snapshot: HealthSnapshot) throws   // under lock "<dir>/.snapshot.lock"; skip if stored.readAt > snapshot.readAt
}
```

### 4.2 `Shared/Core` (*interface*; E3; internal; all 4 targets)

Each file imports only what it needs, one `import` per line: `Foundation`, `HealthKit`, `WidgetKit`, `SwiftUI`, `os`, `SayoneCore`.

```swift
// ===== AppGroup.swift
enum AppGroup {
    static let identifier: String      // Info.plist "SayoneAppGroupID" if non-empty and not containing "$(", else "group.com.sayoneone.sayonehealth"
    static let isShared: Bool          // FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:) != nil
    static let rootURL: URL            // <container>/SayoneHealth, else <Application Support>/SayoneHealth (AppLog.store.error); directory created
    static let journal: JournalStore   // rootURL/Journal
    static let catalog: CatalogStore   // rootURL/catalog.json, role: ThisDevice.kind == .phone ? .author : .replica
    static let snapshot: SnapshotStore // rootURL/health-snapshot.json
}

// ===== ThisDevice.swift
enum ProcessKind: Sendable { case app, widgetExtension }
enum ThisDevice {
    static let kind: DeviceKind        // #if os(watchOS) .watch #else .phone #endif
    static let process: ProcessKind    // Bundle.main.bundleURL.pathExtension == "appex" ? .widgetExtension : .app
}
extension AppLanguage {
    static var current: AppLanguage { get }   // AppLanguage(preferredLocalizations: Bundle.main.preferredLocalizations)
}

// ===== AppLog.swift
enum AppLog {
    static let intake: Logger          // Logger(subsystem: "com.sayoneone.sayonehealth", category: "intake")
    static let health: Logger
    static let widget: Logger
    static let sync: Logger
    static let store: Logger
}

// ===== HealthTypes.swift
enum HKDrinkTypes {
    static func type(_ c: HealthComponent) -> HKQuantityType   // exhaustive switch: .dietaryWater/.dietaryCaffeine/.dietaryEnergyConsumed/.dietarySugar
    static func unit(_ c: HealthComponent) -> HKUnit           // .literUnit(with: .milli) / .gramUnit(with: .milli) / .kilocalorie() / .gram()
    static let share: Set<HKSampleType>                         // all 4
    static let read: Set<HKObjectType>                          // dietaryWater only
}

// ===== HealthGateway.swift
enum HealthWriteAuth: Sendable, Equatable { case authorized, denied, notDetermined, unavailable }
enum HealthGatewayError: Error, Equatable { case unavailable, notAuthorized, locked, other(String) }
final class HealthGateway: @unchecked Sendable {
    static let shared: HealthGateway
    let store: HKHealthStore
    var isAvailable: Bool { get }                                   // HKHealthStore.isHealthDataAvailable()
    func writeAuth(_ c: HealthComponent) -> HealthWriteAuth
    func needsAuthorizationPrompt() async -> Bool                   // statusForAuthorizationRequest == .shouldRequest
    func save(_ entry: IntakeEntry, includeNutrients: Bool) async throws        // throws .notAuthorized unless water authorized
    func hasSamples(entryID: UUID) async throws -> Bool             // any water sample with SayoneEntryID == id
    func deleteSamples(entryID: UUID) async throws -> Int           // water first (errors propagate), nutrients best-effort
    func todayWaterSamples(now: Date) async throws -> [HealthWaterSample]       // all sources; .errorNoData -> []
    func dailyWater(days: Int, now: Date) async throws -> [DayTotal]            // all sources; oldest first
}

// ===== DrinkLogger.swift
struct LogOutcome: Sendable {
    let entry: IntakeEntry
    let isDuplicate: Bool         // .existing or .duplicate from JournalStore.create
    let stored: Bool              // false => journal write failed (e.g. before first unlock); nothing persisted
    let savedToHealth: Bool
    let healthAuth: HealthWriteAuth
    let summary: TodaySummary
}
enum DeleteOutcome: Sendable, Equatable { case deleted, queued, notDeletableHere, notFound, failed }
struct UndoResult: Sendable { let outcome: DeleteOutcome; let entry: IntakeEntry? }
enum DrinkLogger {
    static func log(drinkID: String, volumeML: Int, fallbackName: String = "", source: LogSource,
                    date: Date = Date(), entryID: UUID? = nil) async -> LogOutcome
    @discardableResult static func flush(limit: Int = 50) async -> Int
    static func delete(entryID: UUID, isLocal: Bool) async -> DeleteOutcome
    static func undoLast(window: TimeInterval) async -> UndoResult
}

// ===== TodayService.swift
struct TodayState: Sendable { let summary: TodaySummary; let rows: [TodayRow]; let healthSamples: [HealthWaterSample] }
enum TodayService {
    static func cachedSummary(now: Date = Date()) -> TodaySummary                 // no HK; snapshot + journal
    static func summary(readHealth: Bool, now: Date = Date()) async -> TodaySummary
    static func today(now: Date = Date()) async -> TodayState                     // one HK query for summary + rows
    static func rows(using samples: [HealthWaterSample], now: Date = Date()) -> [TodayRow]
    static func history(days: Int, now: Date = Date()) async -> [DayTotal]
    @discardableResult static func refreshSnapshot(now: Date = Date()) async -> [HealthWaterSample]?   // nil if HK unreadable
}

// ===== WidgetRefresher.swift
enum WidgetKinds {
    static let quickLog = "QuickLogWidget"
    static let favorites = "FavoritesWidget"
    static let quickLogControl = "QuickLogControl"
}
enum WidgetRefresher {
    static func reloadAll()            // WidgetCenter.shared.reloadAllTimelines()
    static func catalogDidChange()     // reloadAll(); #if os(watchOS) invalidateConfigurationRecommendations(); #if os(iOS) ControlCenter.shared.reloadAllControls()
}

// ===== PresetDisplays.swift
enum PresetDisplays {
    static func all() -> [PresetDisplay]                 // AppGroup.catalog.load().presetDisplays(.current)
    static func find(id: String) -> PresetDisplay?
    static func favorites(count: Int) -> [PresetDisplay] // Array(all().prefix(count))
    static var builtInFallback: PresetDisplay { get }    // PresetDisplay.builtInFallback(.current)
}
extension PresetDisplay { var title: String { get } }               // localizedTitle(.current)
extension Drink {
    var displayName: String { get }                                  // name(.current)
    var accusativeName: String { get }                               // accusative(.current)
}

// ===== VolumeText.swift  (VolumeFormat with AppLanguage.current)
enum VolumeText {
    static func short(_ ml: Int) -> String
    static func plus(_ ml: Int) -> String
    static func compact(_ ml: Int) -> String
    static func progress(_ s: TodaySummary) -> String
    static func progressCompact(_ s: TodaySummary) -> String
}

// ===== SiriText.swift  (Phrasebook with AppLanguage.current)
enum SiriText {
    static func logged(_ o: LogOutcome) -> String        // stored=false -> storeFailed; isDuplicate -> duplicateIgnored; else logged(...)
    static func today(_ s: TodaySummary) -> String
    static func undone(_ r: UndoResult) -> String        // deleted->undone, queued->undoQueued, notDeletableHere, notFound->nothingToUndo, failed->storeFailed
    static var healthAccessMissing: String { get }
}

// ===== TintPalette.swift
extension DrinkTint {
    var color: Color { get }           // blue .blue, teal .teal, brown .brown, red .red, orange .orange, green .green, purple .purple, gray .gray
    var background: Color { get }      // color.opacity(0.18)
}
```

### 4.3 `Shared/Intents` (*verbatim* shapes; E4; all 4 targets)

```swift
// ===== PresetEntity.swift
import AppIntents
import SayoneCore

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink Button")
    static let defaultQuery = PresetQuery()
    let id: String
    let drinkID: String
    let drinkName: String
    let symbol: String
    let tintRaw: String
    let volumeML: Int
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(drinkName)",
                              subtitle: "\(VolumeText.short(volumeML))",
                              image: DisplayRepresentation.Image(systemName: symbol))
    }
    init(_ p: PresetDisplay) {
        id = p.id; drinkID = p.drinkID; drinkName = p.drinkName; symbol = p.symbol; tintRaw = p.tint.rawValue; volumeML = p.volumeML
    }
    var display: PresetDisplay {
        PresetDisplay(id: id, drinkID: drinkID, drinkName: drinkName, symbol: symbol,
                      tint: DrinkTint(rawValue: tintRaw) ?? .blue, volumeML: volumeML)
    }
}

struct PresetQuery: EntityQuery {
    init() {}
    func entities(for identifiers: [PresetEntity.ID]) async throws -> [PresetEntity] {
        PresetDisplays.all().filter { identifiers.contains($0.id) }.map(PresetEntity.init)
    }
    func suggestedEntities() async throws -> [PresetEntity] {
        PresetDisplays.all().map(PresetEntity.init)
    }
    func defaultResult() async -> PresetEntity? {
        PresetDisplays.all().first.map(PresetEntity.init)
    }
}

// ===== SelectPresetIntent.swift
import AppIntents

struct SelectPresetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink") var preset: PresetEntity?
    init() {}
    init(preset: PresetEntity) { self.preset = preset }
}

// ===== QuickLogIntent.swift
import AppIntents
import SayoneCore

struct QuickLogIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Log"
    static let isDiscoverable: Bool = false
    @Parameter(title: "Drink ID", default: "water") var drinkID: String
    @Parameter(title: "Volume (ml)", default: 250) var volumeML: Int
    @Parameter(title: "Drink Name", default: "") var drinkName: String
    init() {}
    init(drinkID: String, volumeML: Int, drinkName: String) {
        self.drinkID = drinkID
        self.volumeML = volumeML
        self.drinkName = drinkName
    }
    init(_ p: PresetDisplay) { self.init(drinkID: p.drinkID, volumeML: p.volumeML, drinkName: p.drinkName) }
    func perform() async throws -> some IntentResult {
        _ = await DrinkLogger.log(drinkID: drinkID, volumeML: volumeML, fallbackName: drinkName, source: .widget)
        return .result()
    }
}

// ===== UndoLastIntent.swift
import AppIntents
import SayoneCore

struct UndoLastIntent: AppIntent {                      // discoverable: also an App Shortcut
    static let title: LocalizedStringResource = "Undo Last Drink"
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let window = ThisDevice.process == .widgetExtension ? UndoPolicy.widgetWindow : UndoPolicy.voiceWindow
        let r = await DrinkLogger.undoLast(window: window)
        let text = SiriText.undone(r)
        return .result(dialog: "\(text)")
    }
}

// ===== InAppProcess.swift
#if os(iOS) && INTENTS_IN_APP_PROCESS
import AppIntents
extension QuickLogIntent: LiveActivityIntent {}
extension UndoLastIntent: LiveActivityIntent {}
#endif
```

### 4.4 `Shared/WidgetUI` (*interface*; E4; both widget extensions)

```swift
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

// ===== QuickLogProvider.swift
struct QuickLogEntry: TimelineEntry {
    let date: Date
    let preset: PresetDisplay
    let summary: TodaySummary
    let needsHealthAccess: Bool          // HealthGateway.shared.writeAuth(.water) != .authorized (false in previews)
}
struct QuickLogProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry
    func snapshot(for configuration: SelectPresetIntent, in context: Context) async -> QuickLogEntry
    func timeline(for configuration: SelectPresetIntent, in context: Context) async -> Timeline<QuickLogEntry>
    #if os(watchOS)
    func recommendations() -> [AppIntentRecommendation<SelectPresetIntent>] {       // verbatim
        if #available(watchOS 26.0, *) { return [] }
        return PresetDisplays.all().prefix(Catalog.maxPresets).map { p in
            let text: String = p.title
            return AppIntentRecommendation(intent: SelectPresetIntent(preset: PresetEntity(p)), description: text)
        }
    }
    #endif
    static func resolve(_ configuration: SelectPresetIntent) -> PresetDisplay
    // configuration.preset.flatMap { PresetDisplays.find(id: $0.id) ?? $0.display } ?? PresetDisplays.all().first ?? PresetDisplays.builtInFallback
}

// ===== QuickLogWidget.swift  (verbatim)
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

// ===== QuickLogViews.swift
struct QuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family
    var body: some View        // content.containerBackground(for: .widget) { entry.preset.tint.background }.widgetURL(url)  — the ONLY widgetURL
}

// ===== FavoritesWidget.swift
struct FavoritesEntry: TimelineEntry {
    let date: Date
    let presets: [PresetDisplay]          // PresetDisplays.favorites(count: 4 on iOS / 3 on watchOS)
    let summary: TodaySummary
}
struct FavoritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavoritesEntry
    func getSnapshot(in context: Context, completion: @escaping (FavoritesEntry) -> Void)
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavoritesEntry>) -> Void)  // Task { … completion(…) }
}
struct FavoritesWidget: Widget {
    let kind: String = WidgetKinds.favorites
    var body: some WidgetConfiguration    // StaticConfiguration(kind:provider:content:), "Favorites", families below
    static var families: [WidgetFamily]   // #if os(watchOS) [.accessoryRectangular] #else [.systemMedium] #endif
}

// ===== FavoritesViews.swift
struct FavoritesView: View {
    let entry: FavoritesEntry
    var body: some View        // #if os(watchOS) WatchFavoritesGroup(entry: entry) #else MediumFavoritesView(entry: entry) #endif
                               // + .containerBackground(for: .widget) { Color.blue.opacity(0.12) } + .widgetURL(DeepLink.today.url)
}
struct MediumFavoritesView: View { let entry: FavoritesEntry; var body: some View }
```

### 4.5 `iOS/Widgets` and `Watch/Widgets` (E4)

```swift
// ===== iOS/Widgets/QuickLogControl.swift (verbatim)
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

struct SelectPresetControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink") var preset: PresetEntity?
    init() {}
}

struct QuickLogControl: ControlWidget {
    static let kind: String = WidgetKinds.quickLogControl
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: SelectPresetControlIntent.self) { configuration in
            let p = configuration.preset.flatMap { PresetDisplays.find(id: $0.id) ?? $0.display } ?? PresetDisplays.builtInFallback
            let title = p.title
            ControlWidgetButton(action: QuickLogIntent(p)) {
                Label(title, systemImage: p.symbol)
            }
        }
        .displayName("Log Drink")
        .description("Logs the chosen drink to Health with one tap.")
        .promptsForUserConfiguration()
    }
}

// ===== iOS/Widgets/SayoneWidgetsBundle.swift (verbatim)
import WidgetKit
import SwiftUI

@main
struct SayoneWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        FavoritesWidget()
        QuickLogControl()
    }
}

// ===== Watch/Widgets/SayoneWatchWidgetsBundle.swift (verbatim)
import WidgetKit
import SwiftUI

@main
struct SayoneWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        FavoritesWidget()
    }
}

// ===== Watch/Widgets/WatchWidgetFeatures.swift (interface) — the ONLY place for watchOS-11 widget APIs
import WidgetKit
import SwiftUI
import AppIntents
import SayoneCore

extension View {
    func sayonePrimaryAction() -> some View     // self.handGestureShortcut(.primaryAction)
}
struct WatchFavoritesGroup: View {
    let entry: FavoritesEntry
    var body: some View    // AccessoryWidgetGroup(label: { Text(VolumeText.progressCompact(entry.summary)) }) { slot(0); slot(1); slot(2) }
                           //   .accessoryWidgetGroupStyle(.circular)
}
```

### 4.6 `Shared/AppOnly` (*interface*; E3; both apps)

```swift
// ===== AppModel.swift
import SwiftUI
import SayoneCore

struct LogToast: Identifiable, Equatable { let id: UUID; let text: String; let entryID: UUID; let savedToHealth: Bool }
struct ConfirmRequest: Identifiable, Equatable {
    let id: UUID                  // also used as the entryID → a double tap on "Записать" stays one entry
    let drinkID: String
    let volumeML: Int
    let drinkName: String
    let symbol: String
}
struct DiagnosticsInfo: Equatable {
    let appGroupID: String
    let appGroupShared: Bool
    let device: DeviceKind
    let journalCount: Int
    let pendingCount: Int
    let pendingDeleteCount: Int
    let healthReadAt: Date?
    let catalogRevision: Int64
    let waterWriteAuth: HealthWriteAuth
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    @Published private(set) var catalog: Catalog
    @Published private(set) var summary: TodaySummary
    @Published private(set) var rows: [TodayRow]
    @Published private(set) var healthAuth: HealthWriteAuth
    @Published private(set) var needsHealthOnboarding: Bool
    @Published private(set) var logCounter: Int            // haptic trigger
    @Published var toast: LogToast?
    @Published var confirmRequest: ConfirmRequest?
    @Published var showHealthOnboarding: Bool
    @Published var alertMessage: String?
    var presets: [PresetDisplay] { get }                   // catalog.presetDisplays(.current)
    private init()                                          // sync: catalog load + TodayService.cachedSummary(); no HK
    func refresh() async
    func requestHealthAccess() async
    func log(drinkID: String, volumeML: Int) async
    func log(_ preset: PresetDisplay) async
    func confirm(_ request: ConfirmRequest) async
    func undo(entryID: UUID) async
    func delete(_ row: TodayRow) async
    func history(days: Int) async -> [DayTotal]
    func handle(url: URL)
    func edit(_ change: (inout Catalog) -> Void)           // phone only; see §5.3
    func applyReceivedCatalog(_ catalog: Catalog)          // watch; called ONLY via Task { @MainActor in … }
    func diagnostics() -> DiagnosticsInfo
}

// ===== CatalogSync.swift
import Foundation
import WatchConnectivity
import SayoneCore

final class CatalogSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared: CatalogSync
    func activate()                                        // idempotent; WCSession.isSupported() guard
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any])
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession)
    func sessionDidDeactivate(_ session: WCSession)        // calls WCSession.default.activate() again
    func push(_ catalog: Catalog)                          // updateApplicationContext if activated && isPaired && isWatchAppInstalled
    var watchAppInstalled: Bool { get }
    #endif
}

// ===== HealthAuthorization.swift  (apps only — extensions cannot compile a prompt)
import HealthKit
import SayoneCore
extension HealthGateway {
    func requestAuthorization() async throws    // try await store.requestAuthorization(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)
}
```

### 4.7 `Shared/AppOnly/Siri` (*verbatim* shapes; E6; both apps)

```swift
// ===== WaterAmount.swift
import AppIntents

enum WaterAmount: String, AppEnum, CaseIterable {
    case glass, can, halfLiter, liter
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Amount")
    static let caseDisplayRepresentations: [WaterAmount: DisplayRepresentation] = [
        .glass: DisplayRepresentation(title: "a glass", subtitle: nil, image: nil, synonyms: ["glass", "one glass"]),
        .can: DisplayRepresentation(title: "a can", subtitle: nil, image: nil, synonyms: ["can", "one can"]),
        .halfLiter: DisplayRepresentation(title: "half a liter", subtitle: nil, image: nil, synonyms: ["half a litre", "0.5 liters"]),
        .liter: DisplayRepresentation(title: "a liter", subtitle: nil, image: nil, synonyms: ["a litre", "one liter"])
    ]
    var milliliters: Int {
        switch self {
        case .glass: return 250
        case .can: return 330
        case .halfLiter: return 500
        case .liter: return 1000
        }
    }
}

// ===== DrinkEntity.swift
import AppIntents
import SayoneCore

struct DrinkEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Drink")
    static let defaultQuery = DrinkQuery()
    let id: String
    let name: String
    let accusative: String
    let symbol: String
    let defaultVolumeML: Int
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: nil,
                              image: DisplayRepresentation.Image(systemName: symbol),
                              synonyms: ["\(accusative)", "\(name.lowercased())"])
    }
    init(_ drink: Drink) {
        id = drink.id; name = drink.displayName; accusative = drink.accusativeName
        symbol = drink.symbol; defaultVolumeML = drink.defaultVolumeML
    }
}
struct DrinkQuery: EntityStringQuery {
    init() {}
    func entities(for identifiers: [DrinkEntity.ID]) async throws -> [DrinkEntity]   // catalog drinks incl. archived, by id
    func suggestedEntities() async throws -> [DrinkEntity]      // activeDrinks EXCEPT id "water" (avoids clash with LogWater phrases)
    func entities(matching string: String) async throws -> [DrinkEntity]   // case-insensitive contains on name/accusative, all active drinks incl. water
}

// ===== LogWaterIntent.swift / LogDrinkIntent.swift / TodayTotalIntent.swift
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    @Parameter(title: "Amount", default: .glass) var amount: WaterAmount
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let o = await DrinkLogger.log(drinkID: BuiltInDrink.water.rawValue, volumeML: amount.milliliters, source: .siri)
        let text = SiriText.logged(o)
        return .result(dialog: "\(text)")
    }
}
struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    @Parameter(title: "Drink") var drink: DrinkEntity
    @Parameter(title: "Volume (ml)") var volumeML: Int?
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ml = volumeML ?? drink.defaultVolumeML
        let o = await DrinkLogger.log(drinkID: drink.id, volumeML: ml, fallbackName: drink.name, source: .siri)
        let text = SiriText.logged(o)
        return .result(dialog: "\(text)")
    }
}
struct TodayTotalIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Water"
    init() {}
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let s = await TodayService.summary(readHealth: true)
        let text = SiriText.today(s)
        return .result(value: s.waterML, dialog: "\(text)")
    }
}

// ===== SayoneShortcuts.swift
import AppIntents

struct SayoneShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Log water in \(.applicationName)",
            "Add water in \(.applicationName)",
            "Log \(\.$amount) of water in \(.applicationName)",
            "I drank \(\.$amount) of water in \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: LogDrinkIntent(), phrases: [
            "Log \(\.$drink) in \(.applicationName)",
            "I drank \(\.$drink) in \(.applicationName)",
            "\(.applicationName) \(\.$drink)",
            "Log a drink in \(.applicationName)"
        ], shortTitle: "Log Drink", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: TodayTotalIntent(), phrases: [
            "How much did I drink in \(.applicationName)",
            "Today's water in \(.applicationName)"
        ], shortTitle: "Today's Water", systemImageName: "chart.bar.fill")
        AppShortcut(intent: UndoLastIntent(), phrases: [
            "Undo last drink in \(.applicationName)",
            "Delete last drink in \(.applicationName)"
        ], shortTitle: "Undo Last Drink", systemImageName: "arrow.uturn.backward")
    }
}
```

Every Siri file imports `AppIntents` and `SayoneCore` explicitly.

---

## 5. Per-module implementation notes

### 5.0 Lanes, staged bring-up and contract changes

| Lane | Owns (edits only these) | Needs |
|---|---|---|
| **E1 Infra** | `project.yml`, `Config/**`, `scripts/**`, `.github/workflows/ci.yml` and `xcode27.yml`, `Shared/Resources/Localizable.xcstrings` (generated only), asset catalogs, `*.lproj/InfoPlist.strings`, generated plists and entitlements, `SayoneHealth.xcodeproj`, `README.md`, `docs/TESTING.ru.md`, the Stage A stubs | — |
| **E2 Core** | `Packages/SayoneCore/**` | — |
| **E3 Services** | `Shared/Core/**`, `Shared/AppOnly/{AppModel,CatalogSync,HealthAuthorization}.swift`, `Localization/shared.json` | §4.1 |
| **E4 Widgets** | `Shared/Intents/**`, `Shared/WidgetUI/**`, `iOS/Widgets/*.swift`, `Watch/Widgets/*.swift`, `Localization/widgets.json` | §4.1–4.2 |
| **E5 iPhone** | `iOS/App/*.swift`, `iOS/App/Views/**`, `Localization/ios.json` | §4.2, §4.6 |
| **E6 Watch + Siri** | `Watch/App/*.swift`, `Watch/App/Views/**`, `Shared/AppOnly/Siri/**`, `Localization/watch.json`, `Localization/siri.json` | §4.2, §4.3, §4.6 |

With 5 engineers, E1 and E2 merge. With 4, E5 and E6 also merge.

1. **Stage A: skeleton, before any lane branches.**
   - E2 pushes `SayoneCore` with the complete §4.1 public API. Bodies may be simple but must be correct enough for `swift test` to compile.
   - E1 pushes the project, scripts, CI and a compiling stub for **every** Swift file in §3.
   - Stub bodies return neutral values: `[]`, `nil`, `.placeholder`, `.notFound`, or an entry from `IntakeFactory.make`. Stubs MUST NOT use `fatalError` or `preconditionFailure`; widget code runs in previews.
   - Siri stubs and the §4.3/§4.5/§4.7 files are verbatim already, so they are the real code.
   - Stage A is complete when the Linux jobs and the macOS `apple` job are all green on `main`.
2. **Stage B: parallel lanes.** Each lane works on branch `lane/<E#>-<name>` and runs `scripts/preflight.sh` before every push.
   - CI runs per branch. The free plan allows at most 5 concurrent macOS jobs, and lanes queue beyond that.
   - A lane merges into `main` only when green. Merges happen one at a time, and CI re-runs on `main` after each.
   - Suggested merge order: E3, E4, E6, E5.
3. **Contract changes.** Any change to §4 goes through E1/E2 as a stub update that is green on `main` first. Lanes then rebase.
   - Adding new *internal* helpers inside your own files is free.
   - Changing a §4 signature is not.

### 5.1 `SayoneCore` (E2)

**Built-in drinks.** Values are approximate and editable, and the UI says so. `hydrationFactor` is 1.0 for every built-in drink.

| id / BuiltInDrink | en | ru nominative | ru accusative | symbol | tint | caffeine mg/100 ml | kcal/100 ml | sugar g/100 ml | default ml |
|---|---|---|---|---|---|---|---|---|---|
| `water` | Water | Вода | воду | `drop.fill` | blue | 0 | 0 | 0 | 250 |
| `sparklingWater` | Sparkling Water | Газированная вода | газированную воду | `bubbles.and.sparkles.fill` | teal | 0 | 0 | 0 | 330 |
| `colaZero` | Cola Zero | Кола без сахара | колу без сахара | `takeoutbag.and.cup.and.straw.fill` | red | 9.6 | 0.3 | 0 | 330 |
| `coffee` | Coffee | Кофе | кофе | `cup.and.saucer.fill` | brown | 40 | 1 | 0 | 200 |
| `tea` | Tea | Чай | чай | `mug.fill` | green | 20 | 1 | 0 | 250 |
| `juice` | Juice | Сок | сок | `wineglass.fill` | orange | 0 | 45 | 9 | 250 |
| `milk` | Milk | Молоко | молоко | `waterbottle.fill` | gray | 0 | 52 | 4.7 | 250 |

- The English accusative is the lowercased English name. The generic drink name is "Drink" / «Напиток».
- **Default presets**, in this order: `water-250`, `water-500`, `colaZero-330`, `coffee-200`, `tea-250`. The watch favorites are therefore Water 250, Water 500 and Cola Zero 330.
- `BuiltInCatalog.customSymbols` = `["drop.fill", "cup.and.saucer.fill", "mug.fill", "wineglass.fill", "waterbottle.fill", "takeoutbag.and.cup.and.straw.fill", "bubbles.and.sparkles.fill", "leaf.fill", "flame.fill", "bolt.fill", "birthday.cake.fill", "star.fill"]`.

**NutrientMath.**
- `waterML = volume × hydrationFactor`.
- `caffeineMG = per100.caffeineMG × volume / 100`, and likewise for energy and sugar.
- Every value is rounded to 0.1 with `(x * 10).rounded() / 10`.
- Volume is clamped to `10...5000` and hydration to `0.1...1.0` first.
- Millilitres are `Int`, which is safe on arm64_32: daily sums are far below `Int32.max`. The only `Int64` is `Catalog.revision`.

**`Catalog.sanitized()`** does the following, in order:
1. Drop duplicate drink IDs, keeping the first.
2. Append any built-in drinks that are missing, in `BuiltInCatalog.allDrinks` order.
3. Clamp `hydrationFactor`, `defaultVolumeML` and preset volumes.
4. Clamp `dailyGoalML` to `UserSettings.goalRange`.
5. Drop presets with duplicate IDs, or whose drink is unknown or archived.
6. Truncate the presets to `maxPresets`.
7. Set `version = currentVersion`.

`makeDefault` returns the built-in drinks, the default presets, `UserSettings()`, `version 1`, the given `revision`, and `updatedAt = now`.

**`CatalogStore.load(now:)`**
- File missing → `makeDefault(revision: 0)`.
- File present but it fails to decode → rename it to `catalog.json.bak` (replacing any old .bak) and return `makeDefault`.
  - For the **author** role (phone), use `revision: Int64(now.timeIntervalSince1970 * 1000)`. This way the next push from the phone always wins on the watch.
  - For the **replica** role (watch), use `revision: 0`. This way any push from the phone is accepted.
- In every case the result goes through `sanitized()`.
- `load` never writes a file.

**`FileLock`** (*verbatim*). This was verified on the Linux Swift 6.4 toolchain with 200 concurrent writers.

```swift
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum FileLockError: Error, Equatable { case open(Int32), lock(Int32) }

public enum FileLock {
    /// Exclusive advisory lock held ONLY for the synchronous duration of `body`. Never `await` inside `body`.
    public static func withExclusiveLock<T>(at url: URL, _ body: () throws -> T) throws -> T {
        let fd = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw FileLockError.open(errno) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw FileLockError.lock(errno) }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }
}
```

**JournalStore state machine.** Every write goes through `FileLock` on `<dir>/.lock`, then reads the file, then atomically writes it (`Data.write(to:options: .atomic)`, default file protection) or removes it.

| Operation | File missing | `.pending` | `.saved` | `.pendingDelete` | `.deleted` |
|---|---|---|---|---|---|
| `create(e)` | dedupe check, then write → `.created(e)` | same id → `.existing` | `.existing` | `.existing` | `.existing` |
| `markSaved(id,at)` | `.missing` | → `.saved`, `healthSavedAt = at` → `.marked` | `.alreadySaved` | unchanged → `.deletedMeanwhile` | unchanged → `.deletedMeanwhile` |
| `beginDelete(id,at)` | `.notFound` | → `.pendingDelete`, `deletedAt = at` → `.began(previous: .pending)` | → `.pendingDelete` → `.began(previous: .saved)` | `.alreadyDeleting` | `.alreadyDeleted` |
| `finishDelete(id,at)` | no-op | → `.deleted` | → `.deleted` | → `.deleted` | no-op |

- No operation ever moves an entry out of `.pendingDelete` except to `.deleted`, and nothing leaves `.deleted`.
- `create`'s dedupe check reads all entries within ±`LogDedupe.window` while holding the lock. This keeps two widget processes from both appending the same tap.
- `prune` removes `.saved` and `.deleted` files whose `date` is older than `now − 8 days`. It never removes `.pending` or `.pendingDelete`.
- File names are `"\(id.uuidString).json"`.
- `all()` ignores names that start with "." and names that do not end in ".json".

**TodayMath**: the total rule. This is the fix for the P1 race, and its correctness is load-bearing.

```
makeSnapshot(samples, localEntryIDs, now, readAt):
    day      = day(containing: now)
    inDay    = samples where day.contains(sample.date)
    external = Σ waterML of inDay where entryID == nil || !localEntryIDs.contains(entryID!)
    other    = Σ waterML of inDay where entryID != nil && !localEntryIDs.contains(entryID!)
    return HealthSnapshot(dayStart: day.start, externalWaterML: external, otherDeviceWaterML: other, readAt: readAt)

summary(snapshot, local, goalML, now):
    day      = day(containing: now)
    ext      = snapshot.dayStart == day.start ? snapshot.externalWaterML : 0     (0 if snapshot nil)
    localSum = Σ nutrients.waterML of local where day.contains(date) && isVisible
    waterML  = Int((ext + localSum).rounded())
    pendingCount = count(local where health == .pending)
    lastLocal = newest (by date) visible local entry in day
    undoAvailableUntil = lastLocal.date + UndoPolicy.widgetWindow if that is > now, else nil
```

Why this cannot double-count:
- The caller (`TodayService.refreshSnapshot`) lists `localEntryIDs` **after** the HealthKit query returns.
- A journal file is always created **before** its HealthKit save.
- So every sample written by this device that appears in the query result is in `localEntryIDs`. That holds for pending, saved, pendingDelete and deleted entries, whether or not the process was killed between the save and `markSaved`. Such a sample is therefore subtracted from `external`, and it is counted at most once, through `localSum`.
- Tombstones (`.deleted`) stay in the journal for 8 days, so a stale snapshot never brings back a deleted drink.
- If the journal is wiped (app reinstall), those old samples become "external" and are still counted exactly once.

Required unit tests (use a fixed `Calendar` with `TimeZone(identifier: "Europe/Moscow")`):
1. A saved local entry whose sample is in HealthKit is counted once.
2. A pending local entry whose sample is already in HealthKit (process killed before `markSaved`) is counted once.
3. A `pendingDelete` entry with its sample still in HealthKit counts 0.
4. A `deleted` tombstone, with a snapshot taken while the sample still existed, counts 0.
5. A sample from the other device (`entryID` not local) is counted, and is also included in `otherDeviceWaterML`.
6. A sample from another app (`entryID == nil`) is counted.
7. A snapshot from yesterday gives `ext = 0`.
8. With an empty journal, own old samples are counted once.
9. `undoAvailableUntil` boundary cases.
10. A midnight rollover.

**TodayListMerger.merge.**
- Take the visible local entries in `day` as rows: `isLocal = true`, `isPendingHealth = health == .pending`, `symbol = entry.symbol`, `origin = entry.origin`.
- Add the HealthKit samples in `day` whose `entryID != nil` and is **not** among the IDs of *any* local entry, of any status. These rows get `isLocal = false`, `drinkName = sample.drinkName ?? Phrasebook.genericDrink`, `volumeML = sample.volumeML ?? Int(waterML)`, `symbol = nil`.
- Sort newest first.
- Samples without an `entryID` (other apps) are not rows. They appear only in the footnote total.

**HealthSamplePlan.specs.**
- Produce one spec per component from `components(for:includeNutrients:)`.
- `custom` = `[entryIDKey: .string(id.uuidString), drinkIDKey: .string(drinkID), volumeKey: .number(Double(volumeML)), originKey: .string(origin.rawValue)]`.
- `foodType = entry.drinkName`.

**VolumeFormat.**
- The separator between number and unit is U+00A0.
- Litres use `(Double(ml) / 100).rounded(.toNearestOrAwayFromZero) / 10`, formatted with at most one fraction digit, and a trailing `,0` / `.0` is dropped.
- Examples:
  - `short(250, .ru)` = "250 мл"
  - `short(1500, .ru)` = "1,5 л"
  - `short(1000, .en)` = "1 L"
  - `progress(1200, goalML: 2000, .ru)` = "1,2 из 2 л"
  - `progress(1250, goalML: 2000, .en)` = "1.3 of 2 L"
  - `compact(500, .ru)` = "500"
- Format by hand. Do not use `MeasurementFormatter`, so the output is identical on Linux.

**DeepLink.** Parse with `URLComponents`. The scheme must equal `sayonehealth`, compared case-insensitively. For host `log`, both query items `drink` (non-empty) and `ml` (`Int`) are required. `url` builds the exact formats in §4.0.

**CatalogSyncPayload.decode.** Use `payload[catalogKey] as? Data`, then `CoreJSON.decoder()`, then `sanitized()`. Return `nil` on any failure. Ignore `revisionKey`; it exists for logging only.

**Forward compatibility.** Any field added later MUST be Optional. `DrinkTint` and `LogSource` decode unknown raw values to their fallback.

**Tests.** Every file in §3's test list exists. `JournalStoreTests` MUST cover:
- every cell of the state-machine table
- `DispatchQueue.concurrentPerform` with 100 `create` calls with distinct ids → 100 files
- dedupe: 2 widget creates 1 s apart → 1 file
- that prune keeps pending entries

`CatalogCodecTests` MUST round-trip a revision of `1_758_800_000_123`.

### 5.2 `Shared/Core` (E3)

**AppGroup.**
- `identifier` reads `Bundle.main.object(forInfoDictionaryKey: "SayoneAppGroupID") as? String`.
- `rootURL` falls back to Application Support when the container is nil. That happens on an unsigned build or a signing mistake. The fallback logs an error. It never crashes.

**HealthGateway.** These are exactly the APIs to use.

- **Error mapping** (`map(_ error: Error) -> HealthGatewayError`). Do this with `catch let e as HKError` and switching on `e.code`, never by comparing error strings.

  | `HKError.Code` | `HealthGatewayError` |
  |---|---|
  | `.errorDatabaseInaccessible` | `.locked` |
  | `.errorAuthorizationDenied`, `.errorAuthorizationNotDetermined` | `.notAuthorized` |
  | `.errorHealthDataUnavailable` | `.unavailable` |
  | anything else | `.other(e.localizedDescription)` |
- **`writeAuth(c)`**:
  - `.unavailable` when `!isAvailable`.
  - Otherwise switch on `store.authorizationStatus(for: HKDrinkTypes.type(c))`: `.sharingAuthorized` → `.authorized`, `.sharingDenied` → `.denied`, `.notDetermined` → `.notDetermined`, `@unknown default` → `.notDetermined`.
- **`needsAuthorizationPrompt()`**: `(try? await store.statusForAuthorizationRequest(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)) == .shouldRequest`.
- **`save(entry, includeNutrients:)`**:
  1. Throw `.notAuthorized` unless `writeAuth(.water) == .authorized`.
  2. `specs = HealthSamplePlan.specs(for:includeNutrients:)`, filtered to components where `writeAuth(c) == .authorized`. `save` is all-or-nothing, so a denied caffeine permission must not drop the water sample.
  3. Map each spec to `HKQuantitySample(type: HKDrinkTypes.type(c), quantity: HKQuantity(unit: HKDrinkTypes.unit(c), doubleValue: spec.amount), start: spec.date, end: spec.date, metadata: md)`, where:
     - `md = [HKMetadataKeySyncIdentifier: spec.syncIdentifier, HKMetadataKeySyncVersion: NSNumber(value: spec.syncVersion), HKMetadataKeyFoodType: spec.foodType, HKMetadataKeyWasUserEntered: NSNumber(value: true)]`
     - plus every `custom` entry: `.string` becomes a `String`, `.number` becomes `NSNumber(value:)`.
  4. `try await store.save(objects)`. Never call it with an empty array.
- **`hasSamples(entryID:)`**:
  - `p = HKQuery.predicateForObjects(withMetadataKey: HealthMetadata.entryIDKey, allowedValues: [entryID.uuidString])`
  - `HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKDrinkTypes.type(.water), predicate: p)], sortDescriptors: [], limit: 1)`
  - return `!(try await d.result(for: store)).isEmpty`
- **`deleteSamples(entryID:)`**:
  1. Throw `.notAuthorized` unless water is authorized.
  2. `n = try await store.deleteObjects(of: HKDrinkTypes.type(.water), predicate: p)`. Errors are mapped and thrown.
  3. For caffeine, energy and sugar, only where `writeAuth(c) == .authorized`: `do { n += try await store.deleteObjects(of:predicate:) } catch { log }`. Nutrient failures never block the delete.
  4. Return `n`.
- **`todayWaterSamples(now:)`**:
  - `day = TodayMath.day(containing: now)`
  - predicate `HKQuery.predicateForSamples(withStart: day.start, end: day.end, options: .strictStartDate)`
  - `HKSampleQueryDescriptor(predicates: [.quantitySample(type: water, predicate:)], sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1000)`
  - Map each sample's metadata: `metadata?[HealthMetadata.entryIDKey] as? String` → `UUID(uuidString:)`; `HKMetadataKeyFoodType` as `String`; `volumeKey` as `NSNumber` → `.intValue`; `originKey` as `String` → `DeviceKind(rawValue:)`. `waterML = quantity.doubleValue(for: .literUnit(with: .milli))`.
  - `catch let e as HKError where e.code == .errorNoData` → `[]`.
- **`dailyWater(days:now:)`**:
  - `HKStatisticsCollectionQueryDescriptor(predicate: .quantitySample(type: water, predicate: HKQuery.predicateForSamples(withStart: from, end: to)), options: .cumulativeSum, anchorDate: todayStart, intervalComponents: DateComponents(day: 1))`
  - then `result(for:)`, then `enumerateStatistics(from:to:)`, with `sumQuantity()?.doubleValue(for: mL) ?? 0`.
- **Never**: `requestAuthorization`; that lives in `Shared/AppOnly`. Also never `handleAuthorizationForExtension`, `HKCorrelation`, HealthKitUI or `earliestAuthorizedSampleDate`.

**DrinkLogger.log** (process-agnostic, never throws, never prompts):

```
 1 lang = AppLanguage.current; catalog = AppGroup.catalog.load(); auth = HealthGateway.shared.writeAuth(.water)
 2 r = DrinkResolver.resolve(drinkID:, in: catalog, fallbackName:)   (if !r.isKnown → AppLog.intake.error "unknown drink <id>")
 3 entry = IntakeFactory.make(drink: r.drink, displayName: r.drink.name(lang), volumeML:, date:, origin: ThisDevice.kind,
                              source:, id: entryID ?? UUID())
 4 switch try AppGroup.journal.create(entry):
      .created(e)                → continue with e
      .existing(e), .duplicate(e) → return LogOutcome(entry: e, isDuplicate: true, stored: true, savedToHealth: e.health == .saved,
                                                     healthAuth: auth, summary: TodayService.cachedSummary())
   catch → return LogOutcome(entry:, isDuplicate: false, stored: false, savedToHealth: false, healthAuth: auth, summary: cachedSummary())
 5 saved = false
   if auth == .authorized:
       do { try await HealthGateway.shared.save(e, includeNutrients: catalog.settings.writeNutrients)
            switch try AppGroup.journal.markSaved(id: e.id, at: Date()):
              .marked, .alreadySaved       → saved = true
              .deletedMeanwhile, .missing  → _ = try? await HealthGateway.shared.deleteSamples(entryID: e.id)
                                             try? AppGroup.journal.finishDelete(id: e.id, at: Date())
       } catch { AppLog.health.error(...) }            // entry stays .pending → flushed later
 6 if ThisDevice.process == .app { await flush(limit: 5) }   // never in widget processes (keeps taps fast)
 7 summary = TodayService.cachedSummary()                     // widget reload does the HK read
 8 WidgetRefresher.reloadAll()
 9 return LogOutcome(entry: AppGroup.journal.entry(id: e.id) ?? e, isDuplicate: false, stored: true,
                     savedToHealth: saved, healthAuth: auth, summary: summary)
```

**DrinkLogger.flush(limit:)**. Return 0 unless water is authorized. Otherwise go through `journal.needingFlush().prefix(limit)`:
- `.pending`:
  1. `if try await !hasSamples(id) { try await save(e, …) }`. This avoids depending on what an equal-version re-save returns.
  2. Then `markSaved`. On `.deletedMeanwhile` or `.missing`: `deleteSamples`, then `finishDelete`.
- `.pendingDelete`:
  - `deleteSamples`, then `finishDelete`.
  - On `.notAuthorized` or `.unavailable`: `finishDelete` anyway.
- In either case:
  - `.locked` stops the loop.
  - Any other error means continue with the next entry.
  - A `pendingDelete` entry is **never** saved.
- Call `WidgetRefresher.reloadAll()` if anything changed.
- Return the number of entries processed.

**DrinkLogger.delete(entryID:isLocal:)**
- **Not local** (an other-device row): `n = try await deleteSamples`. `n > 0` → `.deleted` (then reload widgets). `n == 0` or an error → `.notDeletableHere`.
- **Local**: call `journal.beginDelete`. A thrown error → `.failed`.

  | `beginDelete` result | Outcome |
  |---|---|
  | `.notFound` | `.notFound` |
  | `.alreadyDeleted` | `.deleted` |
  | `.began(previous, _)` or `.alreadyDeleting` (treat `previous` as `.saved`) | see below |

  For the last row:
  1. `WidgetRefresher.reloadAll()`. The entry is already hidden.
  2. `try await deleteSamples`, then `finishDelete`, then `.deleted`.
  3. If that throws `.notAuthorized` or `.unavailable`: `finishDelete`. Return `previous == .saved ? .notDeletableHere : .deleted`.
  4. Any other error: `.queued`. The entry stays `pendingDelete`, is hidden, and flush finishes it later.

  A **pending** entry is deleted exactly like a saved one: its save may be in flight in another process. That process's `markSaved` sees `.deletedMeanwhile` and deletes the samples itself.

**DrinkLogger.undoLast(window:)**: `UndoPolicy.candidate(in: journal.all(), now: Date(), window:)`, then `delete(isLocal: true)`, then return an `UndoResult` with the candidate.

**TodayService.**
- **`refreshSnapshot`**:
  1. Return `nil` if `!isAvailable`.
  2. `readAt = Date()`.
  3. `samples = try await todayWaterSamples(now:)`.
  4. **Then** `ids = Set(AppGroup.journal.all().map(\.id))`. This ordering is load-bearing (§5.1).
  5. `snap = TodayMath.makeSnapshot(…)`, then `try? AppGroup.snapshot.saveIfNewer(snap)`, then return `samples`.
  6. Any error → log and return `nil`. The old snapshot stays in use (locked device or denied access).
- **`summary(readHealth:)`**: `if readHealth { await refreshSnapshot() }`, then `cachedSummary()`.
- **`today()`**: one `refreshSnapshot`, then summary + `rows(using: samples ?? [])`.
- **`history(days: 7)`**:
  - Take `dailyWater`, then replace the last element (today) with `cachedSummary().waterML`.
  - On failure, use `TodayMath.localDailyTotals(journal.all(), days:, now:)`. The UI labels this «Только записи с этого устройства».

### 5.3 `Shared/AppOnly` (E3)

**AppModel.**
- `private init()` loads the catalog and `TodayService.cachedSummary()` synchronously. It does not touch HealthKit.
- **`refresh()`**:
  1. `await DrinkLogger.flush()`
  2. `try? journal.prune(now:)`
  3. `catalog = AppGroup.catalog.load()`
  4. `healthAuth = writeAuth(.water)`
  5. `needsHealthOnboarding = isAvailable && await needsAuthorizationPrompt()`
  6. `let t = await TodayService.today()`. Set `summary`/`rows` and store `t.healthSamples` in a private `lastSamples`.
  7. `WidgetRefresher.reloadAll()`
  8. On iOS: `CatalogSync.shared.push(catalog)` when `catalog.revision != lastPushedRevision` (a private var) or on first refresh.
- **`log(drinkID:volumeML:)`** and **`log(_:)`**:
  1. `o = await DrinkLogger.log(…, source: .app)`
  2. If `o.stored && !o.isDuplicate`: set `toast = LogToast(id: UUID(), text: Phrasebook.toast(…, .current), entryID: o.entry.id, savedToHealth: o.savedToHealth)` and `logCounter += 1`.
  3. If `!o.stored`: `alertMessage = SiriText.logged(o)`.
  4. `summary = o.summary; rows = TodayService.rows(using: lastSamples)`.
  5. Auto-dismiss the toast after `UndoPolicy.toastDuration` with `Task.sleep`, only if its `id` is unchanged.
- **`confirm(_ r)`**: `DrinkLogger.log(drinkID: r.drinkID, volumeML: r.volumeML, fallbackName: r.drinkName, source: .deepLink, entryID: r.id)`. This is idempotent: tapping twice gives `.existing`. Then set `confirmRequest = nil`.
- **`undo(entryID:)`** and **`delete(_ row:)`**: call `DrinkLogger.delete(entryID:isLocal:)`.
  - `.notDeletableHere` → `alertMessage = Phrasebook.notDeletableHere(.current)`.
  - `.failed` → `alertMessage = Phrasebook.storeFailed(.current)`.
  - Then recompute `summary`/`rows` from the cache.
- **`handle(url:)`**:
  - `.confirmLog(id, ml)` → resolve the drink with `DrinkResolver` against the catalog, then set `confirmRequest` with a fresh `UUID()`.
  - `.healthAccess` → `showHealthOnboarding = true`.
  - `.today` → nothing.
  - It **never** logs.
- **`edit(_:)`**:
  1. `var c = catalog; change(&c); try? AppGroup.catalog.save(c)`
  2. `catalog = AppGroup.catalog.load()`
  3. `#if os(iOS) CatalogSync.shared.push(catalog) #endif`
  4. `WidgetRefresher.catalogDidChange()`, then `SayoneShortcuts.updateAppShortcutParameters()`.
  
  Callers discard results explicitly: `model.edit { _ = CatalogEditor.addPreset(to: &$0, drinkID: d, volumeML: v) }`.
- **`applyReceivedCatalog`** (watch): `catalog = c`, `summary = TodayService.cachedSummary()`.

**CatalogSync** runs in both apps and is activated in `App.init()`.
- **Phone**:
  - On `activationDidCompleteWith` with `.activated`, push the current `AppGroup.catalog.load()`.
  - `push` calls `try WCSession.default.updateApplicationContext(CatalogSyncPayload.encode(c))`, and only when `activationState == .activated && isPaired && isWatchAppInstalled`. Errors are logged.
- **Watch**:
  - On activation completion, apply `session.receivedApplicationContext`.
  - `didReceiveApplicationContext` applies the payload the same way. It is called on a background queue.
  - Applying (a private `apply(_:)`):
    1. `decode`
    2. `current = AppGroup.catalog.load()`
    3. `guard shouldApply(received:current:)`
    4. `try? AppGroup.catalog.save(c)`
    5. `WidgetRefresher.catalogDidChange()`
    6. `Task { @MainActor in AppModel.shared.applyReceivedCatalog(c); SayoneShortcuts.updateAppShortcutParameters() }`
  - Calling `AppModel` synchronously from the delegate is a **compile error**, even in Swift 5 mode (verified). Do not mark the delegate methods `@MainActor`.
- The watch never pushes, and the phone ignores anything it receives.

**HealthAuthorization.**
- `requestAuthorization()` guards `isAvailable`, then calls `try await store.requestAuthorization(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)`.
- After it returns, call `AppModel.refresh()` so that pending entries flush immediately.

### 5.4 Intents, widgets and control (E4)

- **Where intents run.** `QuickLogIntent.perform()` runs in the widget-extension process. `perform()` awaits `DrinkLogger.log` completely before returning, and WidgetKit then reloads that widget. `UndoLastIntent` behaves the same way.
- **Forbidden on intents.** No intent declares `openAppWhenRun`, `supportedModes`, `description`, `authenticationPolicy` (the default `.alwaysAllowed` is wanted) or `ForegroundContinuableIntent`.
- **QuickLogProvider.**
  - `placeholder`: `QuickLogEntry(date: Date(), preset: PresetDisplays.builtInFallback, summary: .placeholder, needsHealthAccess: false)`.
  - `snapshot`: if `context.isPreview`, return `resolve(configuration)` with `.placeholder`. Otherwise use `cachedSummary()`.
  - `timeline`:
    1. `now = Date()`, `preset = resolve(configuration)`
    2. `summary = await TodayService.summary(readHealth: true, now: now)`
    3. `needs = HealthGateway.shared.writeAuth(.water) != .authorized`
    4. return `Timeline(entries: [entry], policy: .after(WidgetTimeline.nextRefresh(after: now, undoUntil: summary.undoAvailableUntil)))`
- **QuickLogView root.**
  - Exactly one `.containerBackground(for: .widget) { entry.preset.tint.background }` and exactly one `.widgetURL(url)` on the root.
  - `url`:
    - `DeepLink.healthAccess.url` if `needsHealthAccess`
    - else `DeepLink.today.url` for `.accessoryInline`
    - else `DeepLink.confirmLog(drinkID: entry.preset.drinkID, volumeML: entry.preset.volumeML).url`
  - The `content` switch:

    ```swift
    switch family {
    #if os(iOS)
    case .systemSmall: SmallQuickLogView(entry: entry)
    #endif
    #if os(watchOS)
    case .accessoryCorner: CornerQuickLogView(entry: entry)
    #endif
    case .accessoryRectangular: RectangularQuickLogView(entry: entry)
    case .accessoryInline: InlineQuickLogView(entry: entry)
    default: CircularQuickLogView(entry: entry)
    }
    ```

    `SmallQuickLogView` is declared inside `#if os(iOS)` and `CornerQuickLogView` inside `#if os(watchOS)`, in the same file. `default:` is mandatory.
- **Per-family layouts.** Every number `Text` carries `.invalidatableContent()`. Every glyph, gauge and progress bar carries `.widgetAccentable()`. Text uses `lineLimit(1)` and `minimumScaleFactor(0.6)`.

  | Family | Layout |
  |---|---|
  | **systemSmall** (iOS) | See below. |
  | **accessoryCircular** (iOS Lock Screen, watch face, Smart Stack) | The whole view is `Button(intent: QuickLogIntent(entry.preset)) { Gauge(value: entry.summary.progress) { EmptyView() } currentValueLabel: { VStack(spacing: 0) { Image(systemName: symbol); Text(VolumeText.compact(ml)).font(.caption2) } }.gaugeStyle(.accessoryCircularCapacity) }.buttonStyle(.plain)`. **No `AccessoryWidgetBackground()` inside the label** (hit-test bug FB15151000). |
  | **accessoryCorner** (watch) | `Button(intent:) { Image(systemName: symbol).font(.title2).widgetAccentable() }.buttonStyle(.plain).widgetLabel(VolumeText.plus(ml))`. The argument is a `String` variable. |
  | **accessoryRectangular** | The whole view is one `Button(intent: QuickLogIntent(p))` whose label is an HStack. Left side: `VStack(alignment: .leading)` with `Label(p.drinkName, systemImage: p.symbol)`, `Text(VolumeText.progress(summary))` and `ProgressView(value: summary.progress)`. Right side: `Text(VolumeText.plus(ml)).font(.headline)`. Apply `.buttonStyle(.plain)`. On watch, append `#if os(watchOS) .sayonePrimaryAction() #endif` so a double tap in the Smart Stack logs. |
  | **accessoryInline** | `Label(VolumeText.progressCompact(summary), systemImage: "drop.fill")`, with no button. |

  **systemSmall** is a `ZStack(alignment: .topTrailing)` with two layers:
  1. A `VStack(alignment: .leading)` containing:
     - a header: `Image(systemName: symbol)`, `Text(drinkName).font(.caption)`, and `exclamationmark.triangle.fill` if `needsHealthAccess`
     - `Button(intent: QuickLogIntent(entry.preset)) { Text(VolumeText.plus(ml)).font(.title2.bold()).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(tint.color)`
     - `Spacer(minLength: 0)`
     - `Text(VolumeText.progress(summary)).font(.caption)`
     - `ProgressView(value: summary.progress)`
  2. **As a sibling layer, never inside the log button's label**: `if let u = summary.undoAvailableUntil, u > entry.date { Button(intent: UndoLastIntent()) { Image(systemName: "arrow.uturn.backward.circle.fill").font(.title3) }.buttonStyle(.plain) }`.
- **Favorites.**
  - iOS `MediumFavoritesView` is an `HStack`:
    - Left: `Text(VolumeText.progress(summary)).font(.headline)`, `ProgressView`, and the same sibling undo button when available.
    - Right: a `VStack` of two `HStack`s holding up to 4 `Button(intent: QuickLogIntent(p)) { VStack { Image(systemName: p.symbol); Text(VolumeText.plus(p.volumeML)).font(.caption2) }.frame(maxWidth: .infinity, maxHeight: .infinity) }.buttonStyle(.bordered).tint(p.tint.color)`.
    - No `LazyVGrid`.
  - Watch `WatchFavoritesGroup`: `AccessoryWidgetGroup(label: { Text(VolumeText.progressCompact(entry.summary)) }) { slot(0); slot(1); slot(2) }.accessoryWidgetGroupStyle(.circular)`, where:

    ```swift
    @ViewBuilder func slot(_ i: Int) -> some View {
        if i < entry.presets.count {
            let p = entry.presets[i]
            Button(intent: QuickLogIntent(p)) { VStack(spacing: 0) { Image(systemName: p.symbol); Text(VolumeText.compact(p.volumeML)).font(.system(size: 9)) } }
        } else {
            Image(systemName: "plus")
        }
    }
    ```
  - `FavoritesProvider`:
    - Timeline: `Task { let s = await TodayService.summary(readHealth: true); completion(Timeline(entries: [e], policy: .after(nextRefresh))) }`.
    - Snapshot and placeholder use `.placeholder` and the favorites.
    - Presets: `PresetDisplays.favorites(count: 4)` on iOS, `3` on watchOS (`#if os(watchOS)`).
- **Control.**
  - The content closure contains only `let` statements plus **one** `ControlWidgetButton`, because `ControlWidgetTemplateBuilder` has no `if`/`switch`.
  - `SelectPresetControlIntent.preset` is optional. The control is stateless, so there are no value providers.
  - It never foregrounds the app, so on watchOS 26 it also appears on the watch. The native watch control is deferred.
- **Imports.** Every file that uses `Button(intent:)` or `ControlWidgetButton` imports `AppIntents`, `WidgetKit`, `SwiftUI` and `SayoneCore`.

### 5.5 iPhone app (E5)

`SayoneHealthApp` (*verbatim* skeleton):

```swift
import SwiftUI
import SayoneCore

@main
struct SayoneHealthApp: App {
    @StateObject private var model = AppModel.shared
    init() {
        CatalogSync.shared.activate()
        SayoneShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup {
            TodayView()
                .environmentObject(model)
        }
    }
}
```

`TodayView` attaches:
- `.onOpenURL { model.handle(url: $0) }`
- `@Environment(\.scenePhase)` with `.onChange(of: scenePhase) { _, p in if p == .active { Task { await model.refresh() } } }`
- `.task { await model.refresh() }`
- `.sheet(item: $model.confirmRequest) { ConfirmLogSheet(request: $0) }`
- `.fullScreenCover(isPresented: onboardingBinding)`, where `onboardingBinding` = `model.showHealthOnboarding || (model.needsHealthOnboarding && !onboardingDismissed)`; `@AppStorage("onboardingDismissed")` is a per-device convenience
- `.alert` bound to `model.alertMessage`
- `.sensoryFeedback(.success, trigger: model.logCounter)`

| Screen | Contents |
|---|---|
| `TodayView` | `NavigationStack` + `List`. Toolbar: History, Settings. Pull to refresh (`.refreshable`). Content, in order: `ProgressCard`; `PresetGrid`; a «Другой напиток…» button (opens `LogDrinkSheet`); `SiriTipView(intent: LogWaterIntent())`; `TodayListSection`; the footnote. `ToastView` sits as a bottom overlay. |
| `ProgressCard` | A ring (`Gauge` or a trimmed `Circle`), `VolumeText.progress(summary)`, and an orange badge «Ожидают записи в «Здоровье»: N» when `pendingCount > 0`. |
| `PresetGrid` | `LazyVGrid` with 2 flexible columns (fine in the app). One tile per preset: symbol, drink name, `VolumeText.plus`. A tap calls `model.log(p)`. The context menu has «Изменить» and «Удалить». |
| `TodayListSection` | Header «Сегодня». Each row shows time (`date.formatted(date: .omitted, time: .shortened)`), symbol, name, volume, the `applewatch`/`iphone` glyph for `origin`, and `hourglass` if `isPendingHealth`. `.swipeActions` delete calls `model.delete(row)`. Footnote: «Другие приложения в «Здоровье»: X» when `summary.externalWaterML - summary.otherDeviceWaterML > 0`. |
| `LogDrinkSheet` | A grid of `activeDrinks`, volume chips 150/200/250/330/500/750/1000, `Stepper` ±10 (`10...5000`), and «Записать», which calls `model.log(drinkID:volumeML:)`. |
| `HistoryView` | 7 capsule bars from `model.history(days: 7)` against the goal line. No Swift Charts. The label «Только записи с этого устройства» appears in fallback mode. |
| `SettingsView` | Sections: «Цель на день» (Stepper 500–6000, step 100, via `setDailyGoal`); «Записывать кофеин, калории и сахар» (Toggle); «Напитки» → `DrinksListView`; «Кнопки быстрого ввода» → `PresetsListView`; «Здоровье» (status, «Разрешить доступ», plus the read-permission hint); «Apple Watch» (installed yes/no, «Отправить на часы» = `CatalogSync.shared.push`); «Siri» (`SiriTipView` for all 4 intents, `ShortcutsLink()`); «Диагностика» → `DiagnosticsView`; «О приложении» (version). |
| `DrinksListView` / `DrinkEditorView` | Built-ins can be edited except their name. Custom drinks get a name, a symbol grid from `customSymbols`, a tint picker, «Засчитывать в воду» (slider 10–100 %), caffeine mg / kcal / sugar g per 100 ml (`TextField` with `.keyboardType(.decimalPad)`), default volume, and «В архив». Footer: «Значения приблизительные, их можно изменить.» |
| `PresetsListView` / `PresetEditorView` | `.onMove` → `movePresets`, `.onDelete` → `removePreset`, an add button disabled at 12, and a picker of drink + volume. |
| `OnboardingView` | Explains the app. «Разрешить доступ к «Здоровью»» calls `model.requestHealthAccess()`. It tells the user to allow **both writing and reading Water**: reading is needed to see drinks logged on the watch. «Позже» sets `onboardingDismissed`. |
| `ConfirmLogSheet` | «Записать: {drinkName}, {volume}?» with [Записать] → `model.confirm(r)` and [Отмена]. |
| `ToastView` | «{toast.text} · Отменить». «Отменить» calls `model.undo(entryID:)`. |
| `DiagnosticsView` | Every `DiagnosticsInfo` field plus «Повторить запись в «Здоровье»» (`model.refresh()`). |

### 5.6 Watch app (E6)

- **`SayoneWatchApp`** follows the iPhone skeleton. The root is `WatchRootView()`. `init()` calls `CatalogSync.shared.activate()` and `SayoneShortcuts.updateAppShortcutParameters()`. The root view attaches the same `onOpenURL`, `scenePhase`, `.task`, `.sheet(item:)` → `ConfirmLogView` and `.sensoryFeedback(.success, trigger: model.logCounter)` modifiers.
- **`WatchRootView`**: a `NavigationStack` + `List` containing, in order:
  1. `TodayRingRow`: a circular `Gauge` with `.gaugeStyle(.accessoryCircularCapacity)` and `VolumeText.progress`.
  2. `LoggedBanner`, when `toast != nil`: «✓ {drink} {volume}» and an «Отменить» button.
  3. A Health row, when `needsHealthOnboarding`, linking to `WatchOnboardingView`.
  4. A `PresetRow` for each preset. The **first** one gets `.watchPrimaryAction()`, which is double tap on watchOS 11.
  5. A `NavigationLink` «Другой напиток…» → `DrinkPickerView` → `VolumePickerView(drink:)`.
  6. A «Сегодня» section of `WatchTodayRow`s with `.swipeActions` delete.
  7. A `NavigationLink` «Как добавить на циферблат» → `ComplicationHelpView`.
- **`VolumePickerView`** is pushed by navigation, so it is **not** inside the `List`.
  - `@State private var ml: Double = Double(drink.defaultVolumeML)`. The crown binding needs a `Double`.
  - Layout: `VStack { Image(systemName:), Text(VolumeText.short(Int(ml))).font(.title2).monospacedDigit().focusable().digitalCrownRotation($ml, from: 50, through: 2000, by: 50, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true), HStack { −50, +50 buttons }, Button("Log") }`.
  - The button calls `model.log(drinkID:volumeML: Int(ml))` and then pops.
- **`ConfirmLogView`**: the drink, its volume, «Записать» with `.watchPrimaryAction()`, and «Отмена». It never auto-logs.
- **`WatchOnboardingView`**: «Разрешите доступ к «Здоровью» на часах — это отдельное разрешение от iPhone», then `requestHealthAccess()`.
- **`ComplicationHelpView`**: static text. watchOS 11: edit the watch face, then complications, then SayoneHealth, then pick «Вода · 500 мл». watchOS 26: add «Быстрая запись», then pick the drink. After editing presets on the iPhone, open the watch app once.
- **`WatchAppFeatures.swift`**: `extension View { func watchPrimaryAction() -> some View { handGestureShortcut(.primaryAction) } }`.
- The watch never edits the catalog.

### 5.7 Siri (E6)

- `SayoneShortcuts`, the 4 intents, `DrinkEntity`/`DrinkQuery`, `WaterAmount` and `AppShortcuts.xcstrings` live only in `Shared/AppOnly/Siri`, so they are compiled into the **two apps only**.
- `UndoLastIntent` lives in `Shared/Intents` and is therefore also in the apps.
- Siri intents run in the app process in the background. On the watch they run in the watch app, using the watch's Health permission.
- `authenticationPolicy` keeps its default (`.alwaysAllowed`). Logging on a locked iPhone works: the journal is readable after first unlock, and HealthKit journals the write. Before the first unlock after a reboot, `stored == false` and Siri says `Phrasebook.storeFailed`.
- `DrinkQuery.suggestedEntities()` excludes `water`, so «Запиши воду» maps only to `LogWaterIntent`. `entities(matching:)` still finds water.
- Call `updateAppShortcutParameters()` in `App.init()` of both apps and after every catalog change (§5.3).
- No `requestValueDialog` is declared. Siri asks for the missing required `drink` using the localized parameter title, and this avoids an ambiguous-overload risk.

### 5.8 Build-safety rules. `scripts/lint.py` enforces the rules marked ●.

`lint.py` tracks `#if` / `#elseif` / `#else` / `#endif` nesting line by line. A symbol counts as "iOS-guarded" if an enclosing active branch is `#if os(iOS)` (or contains `os(iOS)` in a positive condition), or it sits in the `#else` of `#if os(watchOS)`, or the file is under `iOS/`. "watch-guarded" is defined the same way the other way round.

1. ● **iOS only** (iOS-guarded or under `iOS/`): `.systemSmall`, `.systemMedium`, `.systemLarge`, `promptsForUserConfiguration`, `ShortcutsLink`, `ControlWidget`, `ControlConfigurationIntent`, `ControlCenter`, `LiveActivityIntent`, `UIApplication`, `sessionDidBecomeInactive`, `sessionDidDeactivate`, `isWatchAppInstalled`, `isPaired`, `keyboardType`, `EditButton`, `fullScreenCover`.
2. ● **watchOS only** (watch-guarded or under `Watch/`): `.accessoryCorner`, `digitalCrownRotation`, `WKInterfaceDevice`, `WKApplication`, `invalidateConfigurationRecommendations`, `func recommendations(`.
   **Only in files under `Watch/`**: `AccessoryWidgetGroup`, `accessoryWidgetGroupStyle`, `handGestureShortcut`.
3. ● **Forbidden everywhere**: `openAppWhenRun`, `supportedModes`, `ForegroundContinuableIntent`, `allowedExecutionTargets`, `IntentExecutionTargets`, `earliestAuthorizedSampleDate`, `HKCorrelation`, `handleAuthorizationForExtension`, `healthDataAccessRequest`, `import HealthKitUI`, `AppIntentsPackage`, `IntentDescription(`, `requestConfirmation`, `fatalError(`, `SWIFT_DEFAULT_ACTOR_ISOLATION`, `AccessoryWidgetBackground`.
   Forbidden entitlements: `com.apple.developer.siri`, `aps-environment`, `icloud`, `associated-domains`, `health-records`.
4. ● `Shared/Core`, `Shared/Intents`, `Shared/WidgetUI`, `iOS/Widgets` and `Watch/Widgets` must not contain `requestAuthorization(`, `WCSession`, `WatchConnectivity`, `AppModel`, `CatalogSync` or `SayoneShortcuts`.
5. ● Every `switch family` / `switch context.family` / `switch widgetFamily` block contains `default:`.
   Every file in `Shared/WidgetUI` that declares `: View` and is named `*Views.swift` contains `containerBackground(for: .widget`.
   Each such root `View` has exactly one `widgetURL`.
6. Control content closures hold only `let` statements and one `ControlWidgetButton`. The `ControlConfigurationIntent` parameter is optional.
7. ● Intents:
   - In files that declare `: AppIntent`, `WidgetConfigurationIntent` or `ControlConfigurationIntent`, `static var title` is forbidden; use `static let`.
   - `TypeDisplayRepresentation` is always written as `TypeDisplayRepresentation(name:`, never `.init(`.
   - Widget and control intents take only primitive `@Parameter`s, each with `default:`.
   - Query type names are globally unique (`PresetQuery`, `DrinkQuery`).
8. ● App Shortcuts:
   - `AppShortcut(` appears at most 10 times.
   - Each Swift phrase contains `\(.applicationName)` exactly once and at most one `\(\.$…)`.
   - Every `AppShortcuts.xcstrings` key equals the first Swift phrase of its shortcut, with `\(.applicationName)` mapped to `${applicationName}` and `\(\.$x)` mapped to `${x}`.
   - The `en` stringSet equals the Swift phrase list.
   - Every `ru`/`en` value contains `${applicationName}` exactly once, and placeholders come only from {applicationName, amount, drink}.
9. HealthKit:
   - Metadata values are `String` or `NSNumber` only.
   - Units come only from `HKDrinkTypes.unit(_:)`.
   - Sets are typed `Set<HKSampleType>` / `Set<HKObjectType>`.
   - `HKError` is matched with `catch let e as HKError where e.code == …`.
10. ● `Packages/SayoneCore/Sources` imports only `Foundation`, plus `Darwin`/`Glibc` inside `#if canImport`. The Linux `swift test` job enforces this for real.
11. ● Every Swift file name is unique repo-wide, excluding `Packages/*/Tests`. `@main` appears exactly once in each of `iOS/App`, `Watch/App`, `iOS/Widgets` and `Watch/Widgets`, and never in `Shared/`.
12. ● Plists and entitlements:
    - Every `.plist`, `.entitlements` and `.xcstrings` file parses.
    - App plists have no `NSExtension`.
    - Widget plists have `NSExtension`.
    - The `PRODUCT_BUNDLE_IDENTIFIER` lines in `project.yml` are exactly the 4 values in §2.1.
13. ● Localization: every Localizable key has non-empty `en` and `ru` values with the same count of `%@` / `%1$@` specifiers. Fragments contain no other specifiers.
14. Every file explicitly imports what it uses. Never rely on a transitive import of `SayoneCore`, `AppIntents` or `WidgetKit`.
15. No `await` while a `FileLock` is held. `FileLock` bodies are synchronous closures, so the compiler enforces this.
16. ● `swiftc -parse` passes on every file under `Shared`, `iOS` and `Watch`.

---

## 6. Localization

### 6.1 Mechanism

- `developmentLanguage: en`, and `knownRegions` holds en and ru, detected from the `ru.lproj` folders and the catalogs.
- The device language decides. There is no in-app language switch.
- `Shared/Resources/Localizable.xcstrings` is compiled into all 4 targets. It is **generated**: `python3 scripts/build_strings.py` merges `Localization/{shared,widgets,ios,watch,siri}.json`.
- Fragment format: `{"English key": "Русский"}`. When the English display text differs from the key, use `{"key": {"en": "...", "ru": "..."}}`.
- The generator:
  - fails if the same key appears with **different** Russian values in two fragments; identical duplicates are fine
  - emits `sourceLanguage "en"`, `version "1.0"`, and for each key `extractionState "manual"` plus `stringUnit {state "translated", value}` for `en` and `ru`
  - sorts keys, uses `json.dumps(..., ensure_ascii=False, indent=2, sort_keys=True)` and ends with a trailing newline
  - `--check` exits 1 if the committed file differs
- On a merge conflict in the generated file, regenerate it and commit. Never hand-edit it.
- `SWIFT_EMIT_LOC_STRINGS = NO`, so Xcode never rewrites the catalogs.
- Rules for static text:
  - (a) Every user-visible literal is an English key.
  - (b) Only interpolate `String`s into `Text("…\(s)…")`. The key then contains `%@`. Never interpolate `Int` or `Double`; use `VolumeText` first.
  - (c) Already-localized runtime strings (drink names, volumes, `Phrasebook` output) render with `Text(verbatim:)` or `Text(stringVariable)`, which are not looked up.
  - (d) Put no plural-sensitive nouns next to numbers. Use unit abbreviations.
- **Composed runtime text** comes only from `Phrasebook` and `VolumeFormat` in `SayoneCore` (§6.4). These are Linux-tested and pick ru/en through `AppLanguage.current`.
- **Siri phrases**: `Shared/AppOnly/Siri/AppShortcuts.xcstrings`, hand-written, compiled into the apps only (§7).
- **InfoPlist.strings**: `iOS/App/{en,ru}.lproj/InfoPlist.strings` and `Watch/App/{en,ru}.lproj/InfoPlist.strings`. The ru versions contain:
  ```
  "CFBundleDisplayName" = "SayoneHealth";
  "NSHealthShareUsageDescription" = "SayoneHealth читает данные о воде, чтобы показывать итог за день со всех ваших устройств.";
  "NSHealthUpdateUsageDescription" = "SayoneHealth сохраняет выпитое (воду, кофеин, калории, сахар) в приложение «Здоровье».";
  ```
  The en versions repeat the `project.yml` strings. The widget extensions ship English usage strings only; they are never shown.

### 6.2 Seed keys. Each lane MUST include these in its fragment and may add more.

**`widgets.json` (E4)**

| Key | ru |
|---|---|
| Quick Log | Быстрая запись |
| One tap logs the chosen drink to Health. | Одно нажатие — и напиток записан в «Здоровье». |
| Favorites | Избранное |
| Your first drink buttons, one tap each. | Первые кнопки напитков — одним нажатием. |
| Choose Drink | Выберите напиток |
| Drink | Напиток |
| Drink Button | Кнопка напитка |
| Drink ID | ID напитка |
| Volume (ml) | Объём (мл) |
| Drink Name | Название напитка |
| Undo Last Drink | Отменить последний напиток |
| Log Drink | Записать напиток |
| Logs the chosen drink to Health with one tap. | Записывает выбранный напиток в «Здоровье» одним нажатием. |

**`siri.json` (E6)**

| Key | ru |
|---|---|
| Log Water | Записать воду |
| Amount | Количество |
| a glass | стакан |
| glass | стаканчик |
| one glass | один стакан |
| a can | банку |
| can | банка |
| one can | одну банку |
| half a liter | пол-литра |
| half a litre | поллитра |
| 0.5 liters | пол литра |
| a liter | литр |
| a litre | один литр |
| one liter | 1 литр |
| Log Drink | Записать напиток |
| Drink | Напиток |
| Volume (ml) | Объём (мл) |
| Today's Water | Вода за сегодня |
| Undo Last Drink | Отменить последний напиток |

**`ios.json` (E5) and `watch.json` (E6)** use the shared glossary. Each lane lists only the keys its own views use.

| Key | ru |
|---|---|
| Today | Сегодня |
| History | История |
| Settings | Настройки |
| Other drink… | Другой напиток… |
| Log | Записать |
| Undo | Отменить |
| Cancel | Отмена |
| Delete | Удалить |
| Edit | Изменить |
| Daily goal | Цель на день |
| Drinks | Напитки |
| Drink buttons | Кнопки быстрого ввода |
| Health | Здоровье |
| Allow Access to Health | Разрешить доступ к «Здоровью» |
| Later | Позже |
| Write caffeine, calories and sugar | Записывать кофеин, калории и сахар |
| Waiting for Health: %@ | Ожидают записи в «Здоровье»: %@ |
| Other apps in Health: %@ | Другие приложения в «Здоровье»: %@ |
| Only entries from this device | Только записи с этого устройства |
| Last 7 days | Последние 7 дней |
| Custom drink | Свой напиток |
| Name | Название |
| Symbol | Значок |
| Color | Цвет |
| Counts as water | Засчитывать в воду |
| Caffeine, mg per 100 ml | Кофеин, мг на 100 мл |
| Calories, kcal per 100 ml | Калории, ккал на 100 мл |
| Sugar, g per 100 ml | Сахар, г на 100 мл |
| Default volume | Объём по умолчанию |
| Archive | В архив |
| Add button | Добавить кнопку |
| Up to 12 buttons | Не больше 12 кнопок |
| Values are approximate and can be edited. | Значения приблизительные, их можно изменить. |
| Send to watch | Отправить на часы |
| Diagnostics | Диагностика |
| About | О приложении |
| Retry writing to Health | Повторить запись в «Здоровье» |
| Log this drink? | Записать этот напиток? |
| Allow both writing and reading Water. Reading lets the total include drinks logged on your other device. | Разрешите и запись, и чтение «Воды». Чтение нужно, чтобы итог учитывал напитки с другого устройства. |
| Health access on the watch is separate from the iPhone. | Доступ к «Здоровью» на часах разрешается отдельно от iPhone. |
| How to add to the watch face | Как добавить на циферблат |
| Open the watch app once after editing buttons on iPhone. | После изменения кнопок на iPhone откройте приложение на часах. |

Glossary: Сегодня, Цель, Выпито, Другой напиток, Записать, Отменить, Записано, Напитки, Кнопки быстрого ввода,
Быстрая запись, Избранное, Здоровье, Разрешить доступ, История, Настройки, Свой напиток, Гидратация, Кофеин, Калории, Сахар.

### 6.3 Drink names

Built-in drink names come from `Phrasebook` (§5.1 table), not from the catalog.

### 6.4 `Phrasebook` exact texts

`{name}` is the drink name as given, `{vol}` is `VolumeFormat.short`, `{progress}` is `VolumeFormat.progress`.

| Function | ru | en |
|---|---|---|
| `genericDrink` | Напиток | Drink |
| `logged` (saved) | Записано: {name}, {vol}. Сегодня {progress}. | Logged {name}, {vol}. Today: {progress}. |
| `logged` (not saved, not authorized) | … + « Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью».» | … + " Open SayoneHealth to allow access to Health." |
| `logged` (not saved, authorized) | … + « В «Здоровье» запишется позже.» | … + " It will be saved to Health later." |
| `duplicateIgnored` | Уже записано. | Already logged. |
| `storeFailed` | Не удалось записать. Разблокируйте устройство и повторите. | Couldn't log the drink. Unlock the device and try again. |
| `today` | Сегодня выпито {progress}. | Today you've had {progress}. |
| `undone` | Отменено: {name}, {vol}. | Undone: {name}, {vol}. |
| `undoQueued` | Отменено: {name}, {vol}. Из «Здоровья» удалится позже. | Undone: {name}, {vol}. It will be removed from Health later. |
| `nothingToUndo` | Нечего отменять. | Nothing to undo. |
| `notDeletableHere` | Эту запись нужно удалить на устройстве, где она сделана, или в приложении «Здоровье». | Delete this entry on the device where it was logged, or in the Health app. |
| `healthAccessMissing` | Откройте SayoneHealth, чтобы разрешить доступ к «Здоровью». | Open SayoneHealth to allow access to Health. |
| `toast` | Записано · {name}, {vol} | Logged · {name}, {vol} |

---

## 7. Siri phrases

| Shortcut (shortTitle, symbol) | English phrases (Swift = `en` stringSet) | Russian phrases (`ru` stringSet) |
|---|---|---|
| `LogWaterIntent` ("Log Water", `drop.fill`) | Log water in ${applicationName} · Add water in ${applicationName} · Log ${amount} of water in ${applicationName} · I drank ${amount} of water in ${applicationName} | Запиши воду в ${applicationName} · Добавь воду в ${applicationName} · Запиши ${amount} воды в ${applicationName} · Добавь ${amount} воды в ${applicationName} · Я выпил ${amount} воды в ${applicationName} · Я выпила ${amount} воды в ${applicationName} · Выпил воды в ${applicationName} · Выпила воды в ${applicationName} · ${applicationName} вода |
| `LogDrinkIntent` ("Log Drink", `cup.and.saucer.fill`) | Log ${drink} in ${applicationName} · I drank ${drink} in ${applicationName} · ${applicationName} ${drink} · Log a drink in ${applicationName} | Запиши ${drink} в ${applicationName} · Добавь ${drink} в ${applicationName} · Я выпил ${drink} в ${applicationName} · Я выпила ${drink} в ${applicationName} · ${applicationName} ${drink} · Запиши напиток в ${applicationName} |
| `TodayTotalIntent` ("Today's Water", `chart.bar.fill`) | How much did I drink in ${applicationName} · Today's water in ${applicationName} | Сколько я выпил в ${applicationName} · Сколько я выпила в ${applicationName} · Сколько воды сегодня в ${applicationName} · ${applicationName} итог за день |
| `UndoLastIntent` ("Undo Last Drink", `arrow.uturn.backward`) | Undo last drink in ${applicationName} · Delete last drink in ${applicationName} | Отмени последний напиток в ${applicationName} · Удали последний напиток в ${applicationName} · ${applicationName} отмена |

**Russian parameter values.**
- `WaterAmount` has ru titles стакан / банку / пол-литра / литр. The phrase «Запиши пол-литра воды в SayoneHealth» therefore matches literally, which matters on the watch, where matching must be exact.
- `DrinkEntity` titles are nominative («Кола без сахара»), with synonyms in the accusative («колу без сахара») and lowercased nominative. On the watch, the `${applicationName} ${drink}` form («SayoneHealth кола без сахара») matches the nominative exactly.
- App name synonyms for Russian Siri come from `INAlternativeAppNames`: Sayone, Сейон, Сейон Хелс.

`Shared/AppOnly/Siri/AppShortcuts.xcstrings` (*verbatim*):

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "How much did I drink in ${applicationName}" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringSet" : { "state" : "translated", "values" : [
          "How much did I drink in ${applicationName}",
          "Today's water in ${applicationName}"
        ] } },
        "ru" : { "stringSet" : { "state" : "translated", "values" : [
          "Сколько я выпил в ${applicationName}",
          "Сколько я выпила в ${applicationName}",
          "Сколько воды сегодня в ${applicationName}",
          "${applicationName} итог за день"
        ] } }
      }
    },
    "Log ${drink} in ${applicationName}" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringSet" : { "state" : "translated", "values" : [
          "Log ${drink} in ${applicationName}",
          "I drank ${drink} in ${applicationName}",
          "${applicationName} ${drink}",
          "Log a drink in ${applicationName}"
        ] } },
        "ru" : { "stringSet" : { "state" : "translated", "values" : [
          "Запиши ${drink} в ${applicationName}",
          "Добавь ${drink} в ${applicationName}",
          "Я выпил ${drink} в ${applicationName}",
          "Я выпила ${drink} в ${applicationName}",
          "${applicationName} ${drink}",
          "Запиши напиток в ${applicationName}"
        ] } }
      }
    },
    "Log water in ${applicationName}" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringSet" : { "state" : "translated", "values" : [
          "Log water in ${applicationName}",
          "Add water in ${applicationName}",
          "Log ${amount} of water in ${applicationName}",
          "I drank ${amount} of water in ${applicationName}"
        ] } },
        "ru" : { "stringSet" : { "state" : "translated", "values" : [
          "Запиши воду в ${applicationName}",
          "Добавь воду в ${applicationName}",
          "Запиши ${amount} воды в ${applicationName}",
          "Добавь ${amount} воды в ${applicationName}",
          "Я выпил ${amount} воды в ${applicationName}",
          "Я выпила ${amount} воды в ${applicationName}",
          "Выпил воды в ${applicationName}",
          "Выпила воды в ${applicationName}",
          "${applicationName} вода"
        ] } }
      }
    },
    "Undo last drink in ${applicationName}" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringSet" : { "state" : "translated", "values" : [
          "Undo last drink in ${applicationName}",
          "Delete last drink in ${applicationName}"
        ] } },
        "ru" : { "stringSet" : { "state" : "translated", "values" : [
          "Отмени последний напиток в ${applicationName}",
          "Удали последний напиток в ${applicationName}",
          "${applicationName} отмена"
        ] } }
      }
    }
  },
  "version" : "1.0"
}
```

---

## 8. CI plan and local development

### 8.1 `.github/workflows/ci.yml` (*verbatim*)

```yaml
name: CI
on:
  push:
    branches: [main, 'lane/**', 'claude/**']
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  linux:
    name: Linux (lint, parse, SayoneCore tests)
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v5
      - run: swift --version
      - name: Lint
        run: python3 scripts/lint.py
      - name: String catalog up to date
        run: python3 scripts/build_strings.py --check
      - name: Swift syntax (parse only, no SDK)
        run: find Shared iOS Watch -name '*.swift' -print0 | xargs -0 -n 40 swiftc -parse
      - name: SayoneCore tests
        run: swift test --package-path Packages/SayoneCore

  apple:
    name: macOS (xcodegen + xcodebuild, unsigned)
    runs-on: macos-26
    timeout-minutes: 60
    env:
      XCODEGEN_VERSION: "2.46.0"
    steps:
      - uses: actions/checkout@v5
      - name: Select newest Xcode 26
        run: |
          XC="$(ls -d /Applications/Xcode_26*.app | sort -V | tail -1)"
          sudo xcode-select -s "$XC"
          xcodebuild -version
          xcodebuild -showsdks | grep -E 'iphone|watch' || true
          xcrun simctl list runtimes || true
          defaults write com.apple.dt.Xcode IDEBuildingContinueBuildingAfterErrors -bool YES
      - name: Install XcodeGen (pinned release zip)
        run: |
          curl -fsSL -o "$RUNNER_TEMP/xg.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
          unzip -q "$RUNNER_TEMP/xg.zip" -d "$RUNNER_TEMP"
          echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
      - name: Generate project
        run: |
          xcodegen generate
          P=SayoneHealth.xcodeproj/project.pbxproj
          test "$(grep -cE '^[[:space:]]*[0-9A-F]{24} /\* Embed Watch Content \*/ = \{' $P)" = 1
          test "$(grep -cE '^[[:space:]]*[0-9A-F]{24} /\* Embed Foundation Extensions \*/ = \{' $P)" = 2
          git diff --stat -- SayoneHealth.xcodeproj iOS Watch || true
      - name: SayoneCore tests (macOS)
        run: swift test --package-path Packages/SayoneCore
      - name: Build iOS scheme (iOS app + iOS widgets + embedded watch app + watch widgets) for iOS Simulator
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -configuration Debug \
            -destination 'generic/platform=iOS Simulator' -derivedDataPath "$RUNNER_TEMP/dd" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            2>&1 | tee "$RUNNER_TEMP/ios.log" | xcbeautify --renderer github-actions
      - name: Build watch scheme standalone for watchOS Simulator
        if: ${{ !cancelled() }}
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealthWatch -configuration Debug \
            -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$RUNNER_TEMP/dd" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            2>&1 | tee "$RUNNER_TEMP/watch.log" | xcbeautify --renderer github-actions
      - name: App Intents metadata check
        if: ${{ !cancelled() }}
        run: python3 scripts/check_appintents.py "$RUNNER_TEMP/dd" "$RUNNER_TEMP/ios.log" "$RUNNER_TEMP/watch.log"
      - name: Device build, unsigned (arm64_32 watch + INTENTS_IN_APP_PROCESS escape hatch) — advisory
        if: ${{ !cancelled() }}
        continue-on-error: true
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -configuration Debug \
            -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/dd-dev" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG INTENTS_IN_APP_PROCESS' \
            2>&1 | tee "$RUNNER_TEMP/device.log" | xcbeautify --renderer github-actions
      - name: Error digest
        if: failure()
        run: grep -hE "error:|appintentsmetadataprocessor|No AppIntents metadata" "$RUNNER_TEMP"/*.log | sort -u | head -150 || true
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: build-logs
          path: ${{ runner.temp }}/*.log
```

`.github/workflows/xcode27.yml` is advisory and lives in a separate workflow file. A missing or queued runner label therefore never blocks CI.
- Triggers: `workflow_dispatch` and `push` to `main`.
- `runs-on: xcode-27` with `continue-on-error: true`.
- Steps: checkout, the pinned XcodeGen zip, `xcodegen generate`, and the same iOS-Simulator build of scheme `SayoneHealth`.

The repository is public, so macOS minutes are free. Use only standard runner labels, never `-large` or `-xlarge`.

### 8.2 Scripts (E1)

- **`scripts/preflight.sh`** is run by the agent on Linux before every push. It runs `set -euo pipefail` and uses `XCODEGEN` (default `xcodegen`) and `SWIFT_BIN` (optional PATH prefix). It runs, in order:
  1. `python3 scripts/lint.py`
  2. `python3 scripts/build_strings.py --check`
  3. `find Shared iOS Watch -name '*.swift' -print0 | xargs -0 -n 40 swiftc -parse`
  4. `swift test --package-path Packages/SayoneCore`
  5. `USER=${USER:-ci} LOGNAME=${LOGNAME:-ci} "$XCODEGEN" generate --spec project.yml --quiet`
  6. These greps, all verified on a real 2.46.0 generation:

     ```bash
     P=SayoneHealth.xcodeproj/project.pbxproj
     test "$(grep -cE '^[[:space:]]*[0-9A-F]{24} /\* Embed Watch Content \*/ = \{' "$P")" = 1
     test "$(grep -cE '^[[:space:]]*[0-9A-F]{24} /\* Embed Foundation Extensions \*/ = \{' "$P")" = 2
     grep -qF 'dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";' "$P"
     test -f SayoneHealth.xcodeproj/xcshareddata/xcschemes/SayoneHealth.xcscheme
     test -f SayoneHealth.xcodeproj/xcshareddata/xcschemes/SayoneHealthWatch.xcscheme
     grep -A4 'knownRegions = (' "$P" | grep -qE '^[[:space:]]+ru,$'
     ```

  The naive pattern `Embed Watch Content */ = {` also matches `PBXBuildFile` lines and gives 2 and 4. Never use it.

  Linux XcodeGen: build with `git clone --depth 1 --branch 2.46.0 https://github.com/yonaskolb/XcodeGen && swift build -c release --product xcodegen`. It needs `USER`/`LOGNAME`. Commit the regenerated `SayoneHealth.xcodeproj`, plists and entitlements.
- **`scripts/check_appintents.py <derivedData> <log>...`**:
  - **Exit 1** on any log line matching `appintentsmetadataprocessor.*(error|warning)` or `No AppIntents metadata have been exported`.
  - **Exit 1** if `Build/Products/Debug-iphonesimulator/SayoneHealth.app/Metadata.appintents/` is missing, or if `SayoneHealth.app/Watch/SayoneHealthWatch.app/Metadata.appintents/` is missing.
  - Then it reads every file under each `Metadata.appintents/`. For the apps, it asserts that the text mentions `LogWaterIntent`, `LogDrinkIntent`, `TodayTotalIntent` and `UndoLastIntent`, that it has `autoShortcuts`, and that there are at most 10 entries if the JSON parses. It asserts that the widget `.appex` metadata (`PlugIns/SayoneHealthWidgets.appex`) mentions `QuickLogIntent` and has no non-empty `autoShortcuts`.
  - The content assertions print `::warning::` unless `STRICT_APPINTENTS=1`. The metadata file name (`extract.actionsdata`) is only medium-confidence. Make the check strict after the first green run.
- **`scripts/build_strings.py [--check]`**: §6.1.
- **`scripts/make_icons.py`**: pure-Python PNG writer (zlib + struct). 1024×1024 RGB, a vertical blue gradient with a white drop, written to both `AppIcon.appiconset/AppIcon.png`. Also writes the `Contents.json` files:
  - `{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}`, with `watchos` for the watch
  - `{"info":{"author":"xcode","version":1}}` at the catalog root
- **`scripts/lint.py`**: §5.8. Python 3 stdlib only, and it prints `file:line: rule: message`.

### 8.3 CI failure triage

1. Read the "Error digest" step or the uploaded `build-logs` artifact.
2. Fix the error on the lane branch.
3. Run `scripts/preflight.sh` again.
4. Push.

Never push an untested speculative fix to `main`.

### 8.4 Local development (the user's Mac, tomorrow)

1. `git clone`, then open `SayoneHealth.xcodeproj`. It is committed, so XcodeGen is not required. If `project.yml` changes, run `brew install xcodegen && xcodegen generate`.
2. `cp Config/Local.xcconfig.example Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`. If `com.sayoneone.sayonehealth` is taken for your team, change `BUNDLE_ID_PREFIX` **and** `APP_GROUP_ID` there. Each prefix change uses 4 of the 10 App IDs a free team gets per week.
3. Turn on Developer Mode on the iPhone and the watch. Remove other sideloaded apps, because a free team may install only 3. Trust the profile in Settings → General → VPN & Device Management.
4. Run the `SayoneHealth` scheme on the iPhone. This installs the watch app too. Use the `SayoneHealthWatch` scheme to debug on the watch.
5. If Xcode 27 is required because the devices run iOS/watchOS 27, the project should still build. Check the advisory `xcode27` workflow first.
6. Free profiles expire after 7 days; rebuild after that.

### 8.5 `docs/TESTING.ru.md` checklist (E1 writes it in Russian from this list)

1. Open the app on **both** devices and grant Health access on each. **Allow reading Water as well as writing.** Settings → Diagnostics should show «App Group: общий».
2. iPhone:
   1. Tap each preset and check the toast and undo.
   2. Open Health → Water / Caffeine and check the source and FoodType «Кола без сахара».
   3. Add Quick Log (small) → Edit Widget → «Кола без сахара · 330 мл». Tap it and check that the total changes. Tap undo (↺) and check the sample disappears from Health.
   4. Double-tap the widget quickly: exactly one entry should appear.
   5. Add Lock Screen circular and rectangular widgets. Unlock before tapping.
   6. Add the Favorites medium widget.
   7. Add the Control to Control Center and the Action button. Tap it while **locked**, unlock, and check Health.
3. Watch:
   1. watchOS 11: face editor → complication «Вода · 500 мл» and a second one «Кола без сахара · 330 мл». watchOS 26: add «Быстрая запись» and pick the drink.
   2. Tap it: the ring updates without opening the app. If the app opens instead, the confirm screen must appear and must not log by itself.
   3. Smart Stack: the rectangular widget with a double tap (Series 9+ / Ultra 2), and the Favorites trio.
   4. Crown: «Другой напиток…» → volume.
   5. Edit presets on the iPhone, open the watch app, and check the complication options update.
4. Sync: log on the watch, then open the iPhone app. After Health syncs (seconds to minutes) the total includes it exactly once, and the row has a ⌚ glyph.
5. Siri, with Siri in Russian and then in English:
   - «Запиши пол-литра воды в SayoneHealth»
   - «Запиши колу без сахара в SayoneHealth»
   - «SayoneHealth кола без сахара»
   - «Сколько я выпил в SayoneHealth»
   - «Отмени последний напиток в SayoneHealth»

   Repeat on the watch with exact phrases. Try once with the iPhone locked. The Shortcuts app should list the 4 actions on both devices.
6. Simulator: layouts of every family, the app flows, and HealthKit on each simulator on its own. Sync between simulators and interactive-widget taps are checked on devices only. Turn on WidgetKit Developer Mode if it exists, to lift reload budgets.

---

## 9. Known risks and fallbacks

| # | Risk | Fallback / mitigation |
|---|---|---|
| R1 | `Button(intent:)` on a **watch-face** complication opens the app instead of running the intent. Reports conflict. | The `widgetURL` opens `ConfirmLogView` (two taps, never a double log). Smart Stack widgets and the Siri/Action-button shortcut still take one step. Circular and corner complications avoid `AccessoryWidgetBackground` in labels. |
| R2 | HealthKit save from a **widget extension** fails on device. This is expected to work but is undocumented. | The entry stays `.pending`: counted in totals, shown with ⏳, flushed when the app opens. On iOS, build with `INTENTS_IN_APP_PROCESS` (compiled in CI's device step) so intents run in the app process. On watchOS there is no equivalent; opening the watch app flushes. |
| R3 | A free team refuses the HealthKit entitlement on a widget extension. | Remove the HealthKit keys from that extension's `entitlements.properties` in `project.yml` and regenerate. Taps still journal and the app flushes them. |
| R4 | The user grants **write only** (no read) for Water. The other device's drinks then never appear in totals. | Onboarding text, README and TESTING stress read permission. Settings → Health shows the hint. Own-device totals stay correct. |
| R5 | Separate Health permission on the watch is never granted, so complication taps stay pending. | Watch onboarding on first launch, the widget "!" badge with a `health` deep link, and the watch pending count. |
| R6 | The user's watch cannot run watchOS 11 (Series 4/5, SE 1). | Set `watchOS: "10.0"` in `project.yml`. Wrap the bodies of the two `*Features.swift` files in `if #available(watchOS 11.0, *)`, and give `WatchFavoritesGroup` a static HStack fallback. On 10 a widget tap opens the confirm screen. |
| R7 | `flock` misbehaves or is unavailable on watchOS. It is standard BSD libc, expected to be fine. | If `FileLock` throws, `JournalStore` MUST proceed without the lock (log `store` error) rather than fail the tap. Dedupe and the race guards then degrade to best-effort. |
| R8 | `#include?` in the xcconfig is unsupported. | Delete the line and set `DEVELOPMENT_TEAM` in `Base.xcconfig` or in the Signing UI. |
| R9 | `$(APP_GROUP_ID)` is not expanded in entitlements during free-team signing. | Replace it with the literal `group.com.sayoneone.sayonehealth` in the 4 `entitlements.properties` and regenerate. |
| R10 | Russian Siri mis-hears "SayoneHealth". | `INAlternativeAppNames` (Сейон, Сейон Хелс), the `${applicationName} ${drink}` forms, and testing through the Shortcuts app and Spotlight. Watch Siri needs exact phrases. |
| R11 | An App Intents metadata problem (silent). | `check_appintents.py` log gate. `TypeDisplayRepresentation(name:)`, unique query names, `static let` metadata, no `description`. |
| R12 | The CI image moves to a new Xcode; the user uses Xcode 27. | Newest-`Xcode_26*` glob plus a diagnostics print. The advisory `xcode27` workflow. No iOS/watchOS 26/27-only API outside guards. |
| R13 | HealthKit phone↔watch sync latency. | Totals converge within minutes. Widgets refresh every 30 min and at midnight, and app foregrounding refreshes. This is documented in TESTING. |
| R14 | The rapid-tap forum report (a tap launches the app). | 2-second dedupe for widget/control sources. Undo everywhere. |
| R15 | `IDEBuildingContinueBuildingAfterErrors` is ignored by `xcodebuild`. | Harmless. The watch-scheme step still runs (`!cancelled()`), so the watch errors show anyway. |
| R16 | XcodeGen #1613 "must be embedded in PlugIns". | First check that no `NSExtension` leaked into `Watch/App/Info.plist` (lint rule 12). Do not apply its sed workaround. |
| R17 | Free-team limits: 7-day profiles, 3 apps, 10 App IDs per week. | README instructions. Choose the prefix once. |
| R18 | `extract.actionsdata` naming or format differs. | The metadata check is substring-based and warning-level until the first green run. |
| R19 | The iPhone control mirrored on watchOS 26 logs on the **phone**. | Intended: `origin = .phone`, and it reaches the watch total through HealthKit. |
| R20 | Deleting the other device's entry from here is unsupported by HealthKit (different source). | Try once, then show `notDeletableHere` honestly. The user deletes it on the logging device or in Health. |

---

## Appendix A: how each judge must-fix is resolved

| Must-fix (source) | Resolution |
|---|---|
| P1: `CatalogSync` calls `@MainActor AppModel` synchronously, a compile error | §5.3: `Task { @MainActor in AppModel.shared.applyReceivedCatalog(c) … }`. The delegate is `@unchecked Sendable` and not `@MainActor`. Parse-checked. |
| P1: preflight grep counts wrong (2/4) | §8.2 and §8.1 match only phase definitions (`^\s*<24 hex> /* Embed … */ = {`). Verified: 1 and 2. |
| P1: cross-process lost update after the HealthKit save | §5.1 `JournalStore` flock + state machine. `markSaved` returns `.deletedMeanwhile`/`.missing`, and the logger then deletes samples. `pendingDelete` is never downgraded. |
| P1: deleting a `.pending` entry only removed the file | §5.2: pending entries are deleted exactly like saved ones (`beginDelete` → `deleteSamples` → `finishDelete`). Tombstones are kept. Flush never re-saves `pendingDelete`. |
| P1: TodayMath races and a stale snapshot after delete | §5.1: `external` = HealthKit water minus every sample whose `SayoneEntryID` is in the journal (listed **after** the query). Tombstones are kept 8 days. 10 required tests. |
| P1: deleting unauthorized nutrient types blocks the delete forever | §5.2 `deleteSamples`: water first, nutrients only if authorized and best effort. `.notAuthorized` → `finishDelete` + honest outcome. |
| P1: a corrupt catalog resets the revision and the watch ignores it | §5.1 `CatalogStore` roles: the author falls back to an epoch-ms revision, the replica to 0. The revision is `Int64` (arm64_32-safe). |
| P1: an unknown `drinkID` is silently logged as water | `QuickLogIntent.drinkName`. `DrinkResolver` → `Drink.unknown(id:name:)` with its own name, logged as an error. |
| P1: cross-device totals need Health **read** permission | R4 plus onboarding, Settings, README and TESTING texts (§5.5, §6.2, §8.5). |
| P1 minor: history fallback vs 3-day prune | Journal retention is 8 days (`JournalStore.retentionDays`). The fallback is labelled. |
| P1 caution: flush inside the widget `perform()` adds latency | `DrinkLogger.log` flushes only when `ThisDevice.process == .app`. |
| P1 C5: the «Какой напиток?» prompt | Siri auto-prompts for the required `drink` using the localized title. `requestValueDialog` is omitted on purpose (overload risk, §5.7). |
| P2: `SelectPresetControlIntent` must not be compiled for the watch | It lives in `iOS/Widgets/QuickLogControl.swift` (iOS widget target only). |
| P2: deprecated `.backgroundTask(.appRefresh)` | Not used. |
| P2: `water-750` preset missing | Not referenced. The recommendations come from the real catalog. |
| P2: empty metric set / `save([])` | `hydrationFactor >= 0.1` means water is always ≥ 1 ml. `HealthGateway.save` never calls `save` with an empty array. |
| P3: helper used in the watch widget but defined in the watch app | Watch widget helpers live in `Watch/Widgets/WatchWidgetFeatures.swift`, app helpers in `Watch/App/WatchAppFeatures.swift`. Unique names. |
| P3: lint whitelist conflict for `#if os` | The lint allows `#if os(...)` anywhere and checks symbols by guard context (§5.8). |
| P3: undo/save race, import `modifiedAt`, prune of pending, app dedupe | The state machine plus `.deletedMeanwhile` covers the race. There is no import merge in this design. Prune never removes `pending`/`pendingDelete`. Dedupe applies only to `.widget`. |
| P3: undo button nested inside the log button | §5.4: the undo button is a **sibling** ZStack layer, never inside the log button's label. |
| P3: watchOS 26 Favorites configurability | Favorites is a `StaticConfiguration` (no config, no recommendations). Per-instance config exists only on Quick Log. |

Ideas taken from runners-up:
- **From P2:** the `Int64`-safe persistence mindset, the confirm-sheet idempotency key (`ConfirmRequest.id` used as `entryID`), the "!" attention badge, Diagnostics, and the `${applicationName} ${drink}` watch phrase.
- **From P3:** the pure `HealthSamplePlan`, `hasSamples` before re-save, `Phrasebook`/`VolumeFormat` in the package, the widget-only 2-second dedupe, the sibling undo layer, 100 % water for built-ins, the explicit "APIs outside the digest" discipline, and CI that shows every target's errors in one round-trip.

APIs used that are not in the research digest. All are long-available, and none gates a core flow:
- WatchConnectivity (`updateApplicationContext`, `receivedApplicationContext`, `isPaired`, `isWatchAppInstalled`, iOS-only inactive/deactivate delegates)
- POSIX `open`/`flock` (verified on Linux)
- `os.Logger`
- `URLComponents`
- `TimelineProviderContext.isPreview`
- SwiftUI `onChange(of:initial:)` with two parameters (iOS 17 / watchOS 10), `.sensoryFeedback`, `.swipeActions`, `.refreshable`, `LazyVGrid` (app only)
- xcconfig `#include?` (R8)
- the `IDEBuildingContinueBuildingAfterErrors` user default (R15)
