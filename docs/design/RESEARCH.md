# Verified platform facts (research digest)

## watchOS WidgetKit, complications, controls and watch app facts for SayoneHealth (one-tap drink logging to HealthKit)

- **[high]** The accessory widget families: WidgetFamily.accessoryCircular, .accessoryRectangular and .accessoryInline are available on iOS 16.0+ and watchOS 9.0+. WidgetFamily.accessoryCorner is watchOS 9.0+ only; the docs list no iOS availability for it.  
  _src_: https://developer.apple.com/documentation/widgetkit/widgetfamily/accessorycorner (docs JSON), .../accessorycircular, .../accessoryrectangular, .../accessoryinline  
  _implication_: Referencing .accessoryCorner in iOS-compiled code is a compile error, so wrap it in #if os(watchOS). Put the family list in a computed `families` property with #if os() branches, as Apple's Backyard Birds sample does.
- **[high]** WidgetFamily.systemSmall, .systemMedium and .systemLarge have no watchOS availability (systemSmall: iOS 14, macOS 11, visionOS 26 only).  
  _src_: https://developer.apple.com/documentation/widgetkit/widgetfamily/systemsmall (docs JSON)  
  _implication_: A widget file shared between the iOS and watch extensions must not reference .system* families outside #if os(iOS). WidgetFamily is a non-frozen enum, so every `switch family` needs a `default:` branch or the build fails.
- **[high]** On Apple Watch, accessoryCircular and accessoryRectangular appear as complications and in the Smart Stack. accessoryCorner and accessoryInline appear only as watch-face complications. From watchOS 10, the rectangular layout is shown as a Smart Stack widget and needs .containerBackground(for: .widget) (watchOS 10.0+). The Smart Stack shows the background; on a watch face it is removed (check the showsWidgetContainerBackground environment value).  
  _src_: HIG Widgets + Complications (developer.apple.com/design/human-interface-guidelines/widgets, /complications); https://developer.apple.com/documentation/swiftui/view/containerbackground(for:alignment:content:)  
  _implication_: Use .containerBackground(for: .widget) { ... } on every watch widget view. Without it, the Smart Stack shows an 'adopt containerBackground' placeholder at runtime. This is not a compile error, so CI will not catch it.
- **[high]** The widget configuration APIs are available on watchOS 10.0+: AppIntentConfiguration, AppIntentTimelineProvider, AppIntentRecommendation and WidgetConfigurationIntent. The exact AppIntentConfiguration initializer is `init<Provider>(kind: String, intent: Intent.Type = Intent.self, provider: Provider, @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Intent == Provider.Intent, Provider: AppIntentTimelineProvider`. The provider requirements are `placeholder(in:) -> Entry`, `snapshot(for: Intent, in: Context) async -> Entry`, `timeline(for: Intent, in: Context) async -> Timeline<Entry>` and `recommendations() -> [AppIntentRecommendation<Intent>]`. There is also `relevance() async -> WidgetRelevance<Intent>` (watchOS 11.0+, default returns empty).  
  _src_: https://developer.apple.com/documentation/widgetkit/appintentconfiguration ; .../appintenttimelineprovider (docs JSON)  
  _implication_: A deployment target of watchOS 10.0 or later lets the app use AppIntentConfiguration without SiriKit .intentdefinition files and without the Siri entitlement.
- **[high]** The default implementation of AppIntentTimelineProvider.recommendations() is available only on iOS 17, macOS 14 and visionOS 26, not on watchOS. On watchOS the method is a hard requirement.  
  _src_: https://developer.apple.com/documentation/widgetkit/appintenttimelineprovider/recommendations() (defaultImplementations section lists no watchOS)  
  _implication_: The watch widget's provider must implement recommendations(), or the watch extension fails with 'does not conform to AppIntentTimelineProvider'. If one provider is shared with iOS, implement the method unconditionally or inside #if os(watchOS).
- **[high]** watchOS 11 and earlier have no UI for configuring widgets. The face editor and the Smart Stack add sheet list each AppIntentRecommendation as its own preconfigured option, with its description shown under the option. From watchOS 26, recommendations() can return [], and people then configure each widget or complication instance in the watch face editor or the Smart Stack, as on iOS. Apple's pattern is `if #available(watchOS 26, *) { return [] } else { return recommended }`. After the data behind the recommendations changes, call WidgetCenter.shared.invalidateConfigurationRecommendations() (watchOS 9.0+).  
  _src_: WWDC25 'What's new in watchOS 26' (https://developer.apple.com/videos/play/wwdc2025/334/); https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget  
  _implication_: Per-complication presets work on every version. Before 26, the user picks one recommendation per slot (for example 'Water 500 ml' or 'Coke Zero 330 ml'); from 26, the user edits the intent parameter. Build the recommendations from the user's presets in the App Group, and invalidate them when the watch app edits presets. There are unconfirmed reports that only about 16 recommendations are displayed (forums thread 737915), so keep the list at 12 or fewer.
- **[high]** AppIntentRecommendation initializers (watchOS 10.0+): `init(intent: Intent, description: LocalizedStringKey)`, `init(intent: Intent, description: Text)`, `init(intent: Intent, description: some StringProtocol)` and `init(intent: Intent, description: LocalizedStringResource)`.  
  _src_: https://developer.apple.com/documentation/widgetkit/appintentrecommendation  
  _implication_: For names built at runtime, pass a plain `String` variable, which resolves to the StringProtocol overload and avoids ambiguity. An older blog reported a silent watch extension crash when an interpolated literal was passed as the description to the SiriKit IntentRecommendation; building the string first avoids that.
- **[high]** WidgetConfiguration.promptsForUserConfiguration() is available on iOS 18, macOS 15 and visionOS 26 only, not watchOS. ControlWidgetConfiguration.promptsForUserConfiguration() is available on watchOS 26.0+.  
  _src_: https://developer.apple.com/documentation/swiftui/widgetconfiguration/promptsforuserconfiguration() ; .../controlwidgetconfiguration/promptsforuserconfiguration()  
  _implication_: Calling .promptsForUserConfiguration() on a widget in the watch target is a compile error. Use it only on controls, or guard it with #if os(iOS).
- **[high]** The initializers `Button.init<I: AppIntent>(intent: I, @ViewBuilder label: () -> Label)` and `Toggle.init<I: AppIntent>(isOn: Bool, intent: I, @ViewBuilder label: () -> Label)` are available on iOS 17.0+ and watchOS 10.0+. However, watchOS widgets only became interactive in watchOS 11: 'You can now bring your interactive widget to watchOS too... All watchOS widget families support interactivity!' On watchOS 10, tapping such a widget launches the app.  
  _src_: docs JSON swiftui/button/init(intent:label:); WWDC24 'What's new in watchOS 11' transcript (https://developer.apple.com/videos/play/wwdc2024/10205/)  
  _implication_: Code with Button(intent:) compiles against a watchOS 10 deployment target with no #available checks. One-tap logging without opening the app needs watchOS 11+ on the device. On watchOS 10 the same tap opens the app, so give the app a matching widgetURL fallback.
- **[medium]** Apple states that interactivity applies to all watchOS widget families, which includes watch-face complications as well as the Smart Stack. Developer reports are mixed. A 2023 forum post (watchOS 10 era) got only app launches. A 2024 post found that Button(intent:) worked in the Smart Stack but not as a complication inside AccessoryWidgetGroup. Apple DTS traced that case to `.buttonStyle(.plain)` combined with `AccessoryWidgetBackground()` inside the button label, which made the whole group the hit target. The workarounds are to remove .plain, use `Color.primary.opacity(0.15)` instead of AccessoryWidgetBackground, or make the targets bigger (FB15151000).  
  _src_: https://developer.apple.com/forums/thread/765061 ; https://developer.apple.com/forums/thread/734855 ; WWDC24 10205  
  _implication_: Make the whole circular or corner complication a single Button(intent:). Do not put AccessoryWidgetBackground inside a .plain-styled button label. Plan device testing for the watch-face case and keep the widgetURL fallback.
- **[high]** AccessoryWidgetGroup (watchOS 11.0+ only) is an accessoryRectangular template with a label and up to 3 content views. Each view can be a Button(intent:) or a Link. Initializers include `init(_ title: LocalizedStringKey, systemImage: String, content: () -> Content)` and `init(label: () -> Label, content: () -> Content)`. Style with `.accessoryWidgetGroupStyle(.circular | .roundedSquare)` (watchOS 11). Empty slots launch the app when tapped.  
  _src_: https://developer.apple.com/documentation/widgetkit/accessorywidgetgroup ; WWDC24 10205  
  _implication_: This fits a rectangular 'three favourite drinks' widget. It needs `if #available(watchOS 11.0, *)` when the deployment target is lower, and it must not appear in iOS code.
- **[high]** Tapping a widget outside any Button or Toggle launches the containing app. With `.widgetURL(_ url: URL?)` (watchOS 9.0+), the URL goes to `onOpenURL(perform:)` (watchOS 7.0+). A view hierarchy with more than one widgetURL has undefined behavior. Link controls add extra targets in rectangular widgets. With no URL, the app receives an NSUserActivity, and `NSUserActivity.widgetConfigurationIntent(of:)` (watchOS 10.0+) returns the widget's configuration intent.  
  _src_: https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity  
  _implication_: Use one widgetURL such as `sayonehealth://log?preset=<id>` per widget, and route it in the watch app to a 'confirm and log' screen. That screen should not log automatically, so a tap on watchOS 10 or a missed button hit cannot record a drink twice.
- **[high]** By default, an interactive widget's AppIntent.perform() runs in the widget extension's process. It runs in the app's process instead if `openAppWhenRun` is true (watchOS 9.0+, deprecated 26.0) or if the intent conforms to AudioPlaybackIntent, ForegroundContinuableIntent (deprecated 26.0), LiveActivityIntent or PushToTalkTransmissionIntent. When perform() returns, WidgetKit reloads that widget's timeline, and a Button or Toggle interaction always guarantees a reload. Apple says to add the intent to both the widget extension target and the app target. The modern way to set this is `static var supportedModes: IntentModes` (watchOS 26.0+).  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities ; docs JSON appintents/appintent/openappwhenrun, /supportedmodes; WWDC24 says the same principles apply on watchOS  
  _implication_: LogDrinkIntent.perform() runs in the watch widget extension. That extension therefore needs the App Group and HealthKit entitlements, the shared store code and the HealthKit writer. Finish all writes before returning so the reloaded timeline sees the new total.
- **[high]** HealthKit in widget extensions: an Apple engineer confirmed that widgets can read health data if the host app already has permission. Widgets cannot request authorization; requestAuthorization from an extension fails with HealthKit error 111. `HKHealthStore.handleAuthorizationForExtension()` is available on iOS, macOS and visionOS only, not watchOS. On watchOS the widget extension itself needs the `com.apple.developer.healthkit` entitlement. A developer reported 'Missing com.apple.developer.healthkit entitlement' until the project was moved to a single-target watch app.  
  _src_: https://developer.apple.com/forums/thread/653814 ; https://developer.apple.com/forums/thread/719434 ; docs JSON healthkit/hkhealthstore/handleauthorizationforextension(completion:)  
  _implication_: Never call requestAuthorization from widget or intent code, and never call handleAuthorizationForExtension in watch code, which would not compile. Check `authorizationStatus(for: HKQuantityType(.dietaryWater)) == .sharingAuthorized` before saving. The watch app must request authorization on its first launch.
- **[medium]** Apple does not explicitly document writing HealthKit samples (HKHealthStore.save) from a watchOS widget extension. Given the entitlement plus the inherited app authorization, it is expected to work. HealthKit docs say that when the device is locked an app can still write (HealthKit caches the data) but may not be able to read. `HKError.Code.errorDatabaseInaccessible` means the data is protected because the device is locked.  
  _src_: memory + https://developer.apple.com/documentation/healthkit/setting-up-healthkit (Access encrypted data) + docs JSON hkerror/code/errordatabaseinaccessible  
  _implication_: Design perform() so a tap is never lost: (1) append the drink to the App Group JSON store as pending, (2) try `try await HKHealthStore().save(sample)`, (3) mark it synced on success, (4) have the watch app flush pending entries when it launches or becomes active. Use HKMetadataKeySyncIdentifier and HKMetadataKeySyncVersion (watchOS 4.0+) so a retry does not create a duplicate sample.
- **[medium]** With single-target watch apps (Xcode 14+), developers report that the watch app and the iPhone app show separate HealthKit permission dialogs and keep independent permission state. Permissions granted on the iPhone do not carry over.  
  _src_: https://developer.apple.com/forums/thread/715238  
  _implication_: For tomorrow's device test, the user must open the watch app once and grant Health write access on the watch before the complication can write. Add an onboarding 'Allow Health' button in the watch app using `.healthDataAccessRequest` or `requestAuthorization`.
- **[high]** Capabilities for a free Apple Developer (Personal Team) account, iOS and watchOS: App Groups, HealthKit, Background Modes, Data Protection, Keychain Sharing and HomeKit are available. Siri, Push Notifications, iCloud (CloudKit, KVS, documents), Associated Domains, Sign in with Apple and WeatherKit are not.  
  _src_: https://developer.apple.com/help/account/reference/supported-capabilities-ios ; https://developer.apple.com/help/account/reference/supported-capabilities-watchos  
  _implication_: App Group sharing between the watch app and the watch widget extension works on a free team. Widget push updates (watchOS 26) need the Push capability, so skip them. App Shortcuts through AppShortcutsProvider do not need the SiriKit entitlement.
- **[high]** The App Group container on Apple Watch is separate from the one on iPhone; it is not synced between devices. On the watch, the watch app and its widget extension share `FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:)` and `UserDefaults(suiteName:)`.  
  _src_: memory (behavior since watchOS 2)  
  _implication_: The watch widget's 'today total' must come either from the watch's own App Group store plus a HealthKit statistics query (Health syncs iPhone and Watch samples, with some delay) or from WatchConnectivity. It cannot come from the iPhone's App Group.
- **[high]** Controls on watchOS require watchOS 26.0+. This covers ControlWidget (the SwiftUI protocol), ControlWidgetButton, ControlWidgetToggle, StaticControlConfiguration, AppIntentControlConfiguration, AppIntentControlValueProvider, ControlValueProvider, ControlConfigurationIntent and ControlCenter; on iOS they are 18.0+. Controls appear in three places on the watch: Control Center (opened with the side button), the Smart Stack, and the Action button on Apple Watch Ultra. They do not appear on the watch face. iPhone controls can also be added on the watch and run on the iPhone, unless their action foregrounds the iPhone app, in which case they are hidden. A control in the watch app's widget extension runs on the watch.  
  _src_: docs JSON (swiftui/controlwidget, widgetkit/controlwidgetbutton, appintentcontrolconfiguration, controlcenter); WWDC25 sessions 334 and 278  
  _implication_: A watchOS 26 'log 500 ml' control is a good extra for one-press logging from the Action button on Ultra. It must be @available(watchOS 26.0, *) and live in the watch widget extension. An iOS 18 control with a background (non-foregrounding) intent also shows up on the watch for free and writes Health data on the iPhone.
- **[high]** Exact control signatures: `ControlWidgetButton.init(action: Action, @ViewBuilder label: @escaping () -> Label) where ActionLabel == ControlWidgetButtonDefaultActionLabel, Action: AppIntent`; `StaticControlConfiguration.init(kind: String, @ControlWidgetTemplateBuilder content: @escaping () -> Content)`; `AppIntentControlConfiguration.init(kind: String, intent: Configuration.Type = Configuration.self, @ControlWidgetTemplateBuilder content: @escaping (Configuration) -> Content)`. The configuration modifiers are `.displayName(LocalizedStringResource)`, `.description(LocalizedStringResource)` and `.promptsForUserConfiguration()`. ControlCenter.shared.reloadAllControls() and reloadControls(ofKind:) are watchOS 26.0+.  
  _src_: docs JSON widgetkit/controlwidgetbutton/init(action:label:), staticcontrolconfiguration/init(kind:content:), appintentcontrolconfiguration/init(kind:intent:content:), swiftui/controlwidgetconfiguration  
  _implication_: Use these exact labels; any mismatch costs a CI round-trip.
- **[medium]** `WidgetBundleBuilder.buildLimitedAvailability(_ widget: some ControlWidget)` is iOS 18.0+ and watchOS 26.0+, and `buildOptional` is watchOS 9.0+. Together they allow `if #available(watchOS 26.0, *) { MyControl() }` inside a WidgetBundle body. On iOS 17 this pattern once crashed ('WidgetBundleBuilder includes an unknown OS version'); Apple fixed it in Xcode 16.1 beta 3. SDKs before 26 mark ControlWidget as unavailable on watchOS, where #available does not help.  
  _src_: docs JSON swiftui/widgetbundlebuilder/buildlimitedavailability(_:); https://developer.apple.com/forums/thread/762688  
  _implication_: Wrap the watch control types and the bundle line in `#if compiler(>=6.2)` (Xcode 26 ships Swift 6.2 or later), and mark the types `@available(iOS 18.0, watchOS 26.0, *)`. Also use `if #available(watchOS 26.0, *)` in the bundle when the deployment target is below 26.
- **[high]** The macos-26 arm64 GitHub runner image has Xcode 26.0.1, 26.1.1, 26.2, 26.3, 26.4.1, 26.5 and 26.6 (26.6 is the default), watchOS SDKs 26.0 to 26.5, and watchOS simulator runtimes 26.2, 26.4 and 26.5 (Apple Watch SE 3, Series 11, Ultra 3). The macos-15 image defaults to Xcode 16.4, which has no watchOS 26 SDK, although Xcode 26.0 to 26.3 are installed there. An Xcode 27 public preview has been announced on the runners.  
  _src_: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md and macos-15-arm64-Readme.md  
  _implication_: Use `runs-on: macos-26` and pin the Xcode version, for example `sudo xcode-select -s /Applications/Xcode_26.6.app`, so APIs gated to watchOS 26 compile. XcodeGen does not appear in the image readme, so install it with brew. Build with 'generic/platform=watchOS Simulator' for the watch scheme.
- **[high]** The single-target watch app setup in Apple's Backyard Birds sample is as follows. The watch target has productType com.apple.product-type.application, SDKROOT = watchos, TARGETED_DEVICE_FAMILY = 4, SKIP_INSTALL = YES, GENERATE_INFOPLIST_FILE = YES, INFOPLIST_KEY_WKCompanionAppBundleIdentifier = <iOS bundle id> and INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES, with bundle id <iOS id>.watch. The iOS app embeds it through a copy phase named 'Embed Watch Content' (dstSubfolderSpec 16, dstPath $(CONTENTS_FOLDER_PATH)/Watch). The watch app embeds its widget extension through 'Embed Foundation Extensions' (dstSubfolderSpec 13, PlugIns). The watch widget extension's bundle id is prefixed with the watch app's id (<iOS id>.watch.Widgets). Its Info.plist contains only NSExtension → NSExtensionPointIdentifier = com.apple.widgetkit-extension. The sample does not set WKApplication explicitly.  
  _src_: https://github.com/apple/sample-backyard-birds (Backyard Birds.xcodeproj/project.pbxproj, Widgets/Info.plist)  
  _implication_: Mirror this in project.yml: watch app id com.sayoneone.sayonehealth.watchkitapp and watch widget id com.sayoneone.sayonehealth.watchkitapp.widgets. A WKCompanionAppBundleIdentifier that does not match the iOS id, or an embedded bundle id without the parent's prefix, fails the embedded-binary validation step. INFOPLIST_KEY_WKApplication = YES is optional and harmless.
- **[high]** In XcodeGen's PBXProjGenerator, when an app depends on a target with `type: application` and `platform: watchOS`, the dependency goes into an 'Embed Watch Content' phase (dstPath $(CONTENTS_FOLDER_PATH)/Watch). A dependency of type `app-extension` goes into the extensions embed phase. XcodeGen's watchOS preset sets SDKROOT watchos, SKIP_INSTALL YES and TARGETED_DEVICE_FAMILY 4. The every-time project reports that the legacy `application.watchapp2` type fails on Xcode 26 with 'Multiple commands produce ...'.  
  _src_: https://github.com/yonaskolb/XcodeGen/blob/master/Sources/XcodeGenKit/PBXProjGenerator.swift ; SettingPresets/Platforms/watchOS.yml ; https://github.com/solomonxie/every-time  
  _implication_: Use `type: application, platform: watchOS` for the watch app, listed as a dependency of the iOS app, and `type: app-extension, platform: watchOS` for the watch widgets, listed as a dependency of the watch app. Do not use watchapp2 or watchkit2-extension. The widget extension needs an explicit Info.plist, or the XcodeGen `info:` block, containing the NSExtension dictionary.
- **[high]** `WidgetCenter.shared.reloadAllTimelines()` and `reloadTimelines(ofKind: String)` are watchOS 9.0+. They reload only the calling app's widgets on the same device. `currentConfigurations() async throws -> [WidgetInfo]` is watchOS 11.0+ and `getCurrentConfigurations(_:)` is watchOS 9.0+. A frequently viewed widget typically gets 40 to 70 refreshes a day, and timeline entries should be at least about 5 minutes apart. Reloads while the containing app is in the foreground, and reloads caused by a widget performing an app intent, do not count against the budget.  
  _src_: docs JSON widgetkit/widgetcenter/*; https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date  
  _implication_: After logging a drink in the watch app, call WidgetCenter.shared.reloadTimelines(ofKind:), which costs nothing while the app is in the foreground. On watchOS 26, also call ControlCenter.shared.reloadAllControls() behind a version check. The iOS app's reload calls do not refresh watch complications. Add a timeline entry at midnight so the daily total resets.
- **[high]** `requestConfirmation(conditions: ConfirmationConditions = [], actionName: ConfirmationActionName = .continue, dialog: IntentDialog) async throws` is watchOS 11.0+. `.handGestureShortcut(_ shortcut: HandGestureShortcut, isEnabled: Bool = true)` with `.primaryAction` is also watchOS 11.0+; per WWDC24 it lets double tap activate a button or toggle in a Smart Stack widget.  
  _src_: docs JSON; WWDC24 10205  
  _implication_: Optional polish: mark the Smart Stack button with .handGestureShortcut(.primaryAction) so a double tap logs the preset. This needs `if #available(watchOS 11.0, *)` when the deployment target is below 11.
- **[high]** Digital Crown: `digitalCrownRotation<V: BinaryFloatingPoint>(_ binding: Binding<V>, from: V, through: V, by stride: V.Stride? = nil, sensitivity: DigitalCrownRotationalSensitivity = .high, isContinuous: Bool = false, isHapticFeedbackEnabled: Bool = true) -> some View` is watchOS 6.0+. `digitalCrownRotation(detent:from:through:by:sensitivity:isContinuous:isHapticFeedbackEnabled:onChange:onIdle:)` and the onChange/onIdle variants are watchOS 9.0+. Apple's examples apply `.focusable()` first. With isContinuous: true the value wraps around at the bounds.  
  _src_: docs JSON swiftui/view/digitalcrownrotation(...)  
  _implication_: Bind a Double, not an Int. Use isContinuous: false for a clamped 50 to 2000 ml picker, add .focusable(), and keep it out of a List or ScrollView, which also consume crown input. It is watchOS-only API, so shared code needs #if os(watchOS).
- **[high]** Haptics: `View.sensoryFeedback<T: Equatable>(_ feedback: SensoryFeedback, trigger: T)` and `SensoryFeedback.success` are watchOS 10.0+. `WKInterfaceDevice.current().play(_ type: WKHapticType)` with `.success` is watchOS 2.0+ and requires `import WatchKit`.  
  _src_: docs JSON swiftui/view/sensoryfeedback(_:trigger:), watchkit/wkinterfacedevice/play(_:)  
  _implication_: In the watch app, prefer `.sensoryFeedback(.success, trigger: logCounter)`. Do not rely on haptics from the widget extension's perform().
- **[high]** Other widget view APIs: `.widgetLabel(_:)` (LocalizedStringKey, StringProtocol or LocalizedStringResource) and `.widgetLabel(label:)` are iOS 16 and watchOS 9 (use them for corner and circular labels); `.widgetCurvesContent()` is watchOS 10; `.widgetAccentable()` is watchOS 9; the `widgetRenderingMode` environment value is watchOS 9; `Image.widgetAccentedRenderingMode(_:)` is watchOS 11; Gauge styles `.accessoryCircularCapacity` and `.accessoryLinearCapacity` are watchOS 9.  
  _src_: docs JSON  
  _implication_: The corner complication can use a drop icon with .widgetLabel { Gauge(...) } or a text label. The circular complication can use Gauge(.accessoryCircularCapacity) for progress toward the daily goal, with the whole view as the button label.
- **[high]** In watchOS 26, Apple Watch Series 9 and later and Apple Watch Ultra 2 run the arm64 architecture. Apple says to use the Standard Architectures build setting.  
  _src_: WWDC25 334 transcript  
  _implication_: Do not hard-code ARCHS in project.yml; XcodeGen's default of $(ARCHS_STANDARD) is correct.
- **[high]** `AppShortcutsProvider` and `AppShortcut` are watchOS 9.0+. `AppIntent.isDiscoverable` is watchOS 10.0+. `WidgetConfigurationIntent` is watchOS 10.0+. `SetValueIntent` is watchOS 11.0+. `AppIntent.description` has the type `IntentDescription?`.  
  _src_: docs JSON appintents/*  
  _implication_: The Siri-facing intents and the widget button intent can share code. The widget-only variant can set isDiscoverable = false so it does not appear in Shortcuts. Keep AppShortcutsProvider in the app targets only.

### Snippets

```
// ===== Shared/LogDrinkIntent.swift  (member of: watch app, watch widget ext, iOS app, iOS widget ext)
import AppIntents
import HealthKit
import WidgetKit

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log drink"
    static let isDiscoverable: Bool = false          // widget/control-only variant

    @Parameter(title: "Preset ID")
    var presetID: String

    init() {}
    init(presetID: String) { self.presetID = presetID }

    func perform() async throws -> some IntentResult {
        // Runs in the WIDGET EXTENSION process when tapped in a widget/complication/control.
        let pending = SharedStore.appendPending(presetID: presetID)   // 1) App Group first: never lose a tap
        do {
            try await HealthWriter.save(pending)                      // 2) best effort HealthKit
            SharedStore.markSynced(pending.id)
        } catch {
            // keep as pending; the watch app flushes pending entries on launch/scenePhase .active
        }
        return .result()   // WidgetKit reloads this widget's timeline after return
    }
}

enum HealthWriter {
    static let store = HKHealthStore()
    static func save(_ e: PendingDrink) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.dietaryWater)                     // iOS 15 / watchOS 8
        guard store.authorizationStatus(for: type) == .sharingAuthorized else {
            throw HKError(.errorAuthorizationNotDetermined)
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: Double(e.milliliters)),
            start: e.date, end: e.date,
            metadata: [HKMetadataKeyFoodType: e.drinkName,
                       HKMetadataKeySyncIdentifier: e.id.uuidString,
                       HKMetadataKeySyncVersion: 1])
        try await store.save(sample)                                  // async throws, watchOS 8+
    }
}
// NOTE: never call requestAuthorization / handleAuthorizationForExtension (iOS-only) from extension code.
```
```
// ===== WatchWidgets/QuickLogWidget.swift (watch widget ext; iOS parts guarded)
import WidgetKit
import SwiftUI
import AppIntents

struct QuickLogConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Quick log"
    static let description = IntentDescription("Log a drink with one tap.")
    @Parameter(title: "Preset")
    var preset: DrinkPresetEntity?          // AppEntity + EntityQuery reading App Group presets
    init() {}
    init(preset: DrinkPresetEntity) { self.preset = preset }
}

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let preset: DrinkPresetEntity
    let todayML: Int
}

struct QuickLogProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: .now, preset: .defaultWater, todayML: 0)
    }
    func snapshot(for configuration: QuickLogConfigIntent, in context: Context) async -> QuickLogEntry {
        QuickLogEntry(date: .now, preset: configuration.preset ?? .defaultWater, todayML: SharedStore.todayTotalML())
    }
    func timeline(for configuration: QuickLogConfigIntent, in context: Context) async -> Timeline<QuickLogEntry> {
        let p = configuration.preset ?? .defaultWater
        let now = QuickLogEntry(date: .now, preset: p, todayML: SharedStore.todayTotalML())
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        let reset = QuickLogEntry(date: midnight, preset: p, todayML: 0)
        return Timeline(entries: [now, reset], policy: .atEnd)
    }
    // REQUIRED on watchOS (no default implementation there)
    func recommendations() -> [AppIntentRecommendation<QuickLogConfigIntent>] {
        #if os(watchOS)
        if #available(watchOS 26.0, *) { return [] }   // user configures per instance in face editor / Smart Stack
        #endif
        return SharedStore.presetEntities().prefix(12).map { p in
            let name: String = p.title                  // plain String -> StringProtocol overload
            return AppIntentRecommendation(intent: QuickLogConfigIntent(preset: p), description: name)
        }
    }
}

struct QuickLogWidget: Widget {
    static let kind = "QuickLogWidget"
    private var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline]
        #else
        return [.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: QuickLogConfigIntent.self, provider: QuickLogProvider()) { entry in
            QuickLogView(entry: entry)
        }
        .configurationDisplayName("Quick log")
        .description("One tap logs your drink.")
        .supportedFamilies(families)
        // NO .promptsForUserConfiguration() here: unavailable on watchOS
    }
}

struct QuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.blue.opacity(0.3) }
            .widgetURL(URL(string: "sayonehealth://log?preset=\(entry.preset.id)"))   // fallback: watchOS 10 / missed hit
    }

    @ViewBuilder private var content: some View {
        switch family {
        #if os(watchOS)
        case .accessoryCorner:
            Button(intent: LogDrinkIntent(presetID: entry.preset.id)) {
                Image(systemName: "drop.fill").font(.title2)
            }
            .widgetLabel("\(entry.todayML) ml")
        #endif
        case .accessoryInline:
            Text("\(entry.todayML) ml")
        default:   // circular / rectangular (+ systemSmall on iOS); `default` is REQUIRED (non-frozen enum)
            Button(intent: LogDrinkIntent(presetID: entry.preset.id)) {
                VStack(spacing: 0) {
                    Image(systemName: "drop.fill")
                    Text("+\(entry.preset.milliliters)").font(.caption2)
                }
                // avoid AccessoryWidgetBackground() inside a .plain-styled Button label (hit-test bug FB15151000)
            }
        }
    }
}
```
```
// ===== WatchWidgets/Bundle.swift + watchOS 26 control
import WidgetKit
import SwiftUI
import AppIntents

#if compiler(>=6.2)
@available(iOS 18.0, watchOS 26.0, *)
struct QuickLogControl: ControlWidget {
    static let kind = "com.sayoneone.sayonehealth.QuickLogControl"
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: LogDrinkIntent(presetID: "water-500")) {
                Label("Water 0.5 L", systemImage: "drop.fill")
            }
        }
        .displayName("Log water")
        .description("Adds 500 ml of water to Health.")
    }
}
#endif

@main
struct SayoneWatchWidgets: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        #if compiler(>=6.2)
        if #available(watchOS 26.0, *) {   // uses WidgetBundleBuilder.buildLimitedAvailability(some ControlWidget)
            QuickLogControl()
        }
        #endif
    }
}

// Configurable control variant (watchOS 26 / iOS 18):
// @available(iOS 18.0, watchOS 26.0, *)
// struct QuickLogControlConfig: ControlConfigurationIntent {
//     static let title: LocalizedStringResource = "Drink preset"
//     @Parameter(title: "Preset") var preset: DrinkPresetEntity?
//     init() {}
//     func perform() async throws -> some IntentResult { .result() }
// }
// AppIntentControlConfiguration(kind: kind, intent: QuickLogControlConfig.self) { cfg in
//     ControlWidgetButton(action: LogDrinkIntent(presetID: cfg.preset?.id ?? "water-500")) {
//         Label(cfg.preset?.title ?? "Water 0.5 L", systemImage: "drop.fill")
//     }
// }.displayName("Quick drink").promptsForUserConfiguration()
```
```
# ===== project.yml fragment (XcodeGen) — modern single-target watch app
targets:
  SayoneHealth:
    type: application
    platform: iOS
    dependencies:
      - target: SayoneHealthWidgets            # iOS widget ext -> Embed Foundation Extensions
      - target: SayoneHealthWatch              # watchOS app  -> "Embed Watch Content" $(CONTENTS_FOLDER_PATH)/Watch
  SayoneHealthWatch:
    type: application                          # NOT application.watchapp2 (breaks on Xcode 26)
    platform: watchOS
    deploymentTarget: "10.0"
    sources: [Watch, Shared]
    dependencies:
      - target: SayoneHealthWatchWidgets       # -> Embed Foundation Extensions (PlugIns)
      - package: SayoneCore
    entitlements:
      path: Watch/SayoneHealthWatch.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.security.application-groups: [group.com.sayoneone.sayonehealth]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX)   # must equal iOS CFBundleIdentifier
        INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp: YES
        INFOPLIST_KEY_WKApplication: YES                                   # optional (Xcode template omits)
        INFOPLIST_KEY_CFBundleDisplayName: SayoneHealth
        INFOPLIST_KEY_NSHealthShareUsageDescription: "Reads your drink history"
        INFOPLIST_KEY_NSHealthUpdateUsageDescription: "Saves your drinks to Health"
        SWIFT_VERSION: "5.0"
  SayoneHealthWatchWidgets:
    type: app-extension
    platform: watchOS
    deploymentTarget: "10.0"
    sources: [WatchWidgets, Shared]
    dependencies:
      - package: SayoneCore
    info:
      path: WatchWidgets/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: WatchWidgets/SayoneHealthWatchWidgets.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.security.application-groups: [group.com.sayoneone.sayonehealth]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp.widgets   # must be prefixed by watch app id
        SWIFT_VERSION: "5.0"
# CI: runs-on: macos-26 ; sudo xcode-select -s /Applications/Xcode_26.6.app
# xcodebuild build -scheme SayoneHealthWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO
```
```
// ===== Watch app: crown volume picker + haptic + widget reload
import SwiftUI
import WidgetKit

struct VolumePickerView: View {
    @State private var ml: Double = 250          // must be BinaryFloatingPoint
    @State private var logCount = 0
    var body: some View {
        VStack {
            Text("\(Int(ml)) ml").font(.title2).monospacedDigit()
                .focusable()
                .digitalCrownRotation($ml, from: 50, through: 2000, by: 50,
                                      sensitivity: .medium, isContinuous: false,
                                      isHapticFeedbackEnabled: true)
            Button("Add") {
                Task {
                    await DrinkLogger.log(ml: Int(ml))          // App Group + HealthKit in-process
                    logCount += 1
                    WidgetCenter.shared.reloadTimelines(ofKind: "QuickLogWidget")  // free while foreground
                    #if compiler(>=6.2)
                    if #available(watchOS 26.0, *) { ControlCenter.shared.reloadAllControls() }
                    #endif
                }
            }
        }
        .sensoryFeedback(.success, trigger: logCount)   // watchOS 10+
        // alt: import WatchKit; WKInterfaceDevice.current().play(.success)
    }
}
```

### Recommendations
- Set the deployment targets to watchOS 10.0 and iOS 17.0. That covers AppIntentConfiguration, Button(intent:), containerBackground and sensoryFeedback with no availability checks. Gate these with #available: AccessoryWidgetGroup and handGestureShortcut (watchOS 11), `recommendations() -> []` and controls (watchOS 26). If the user's watch is known to run watchOS 11 or later, raise the target to 11.0/18.0 to remove most checks.
- The watch face is the primary surface. Use a single QuickLogWidget built on AppIntentConfiguration (families: circular, corner, rectangular, inline) whose whole view is a Button(intent: LogDrinkIntent(presetID:)). recommendations() returns the user's presets before watchOS 26 and [] on 26 and later, so each complication instance gets its own preset.
- Always implement recommendations() in the watch provider, because watchOS has no default implementation and the build fails without it. Never call .promptsForUserConfiguration() on a WidgetConfiguration in the watch target.
- Write perform() to survive failures: append a pending entry to the App Group JSON first, then save to HealthKit with a sync identifier, and have the watch app flush pending entries when it becomes active. Do not rely on undocumented behavior for HealthKit writes from the extension.
- Add a widgetURL (`sayonehealth://log?preset=ID`) that opens a confirm-and-log screen in the watch app. It covers watchOS 10 (no interactivity) and taps the button misses on the watch face. Do not log automatically from the URL, or a single tap could record the drink twice.
- Put the HealthKit and App Group entitlements on both the watch app and the watch widget extension. Add NSHealthShare and NSHealthUpdate usage descriptions to the watch app, and request authorization in the watch app on first launch. Tell the user to grant Health access on the watch separately from the iPhone.
- Add the watchOS 26 QuickLogControl (a static ControlWidgetButton, or AppIntentControlConfiguration for a configurable version) inside `#if compiler(>=6.2)` and `if #available(watchOS 26.0, *)`. It gives one-press logging from Control Center, the Smart Stack and the Ultra Action button. An iOS 18 control with a non-foregrounding intent also appears on the watch automatically.
- Compute the watch widget's today total from the watch's own App Group store, optionally merged with an HKStatisticsQuery on dietaryWater that is wrapped in a do/catch for errorDatabaseInaccessible. The iPhone and watch App Groups are not shared.
- In CI, use runs-on: macos-26 and pin the Xcode version with xcode-select. Build the watch scheme separately with -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO, so watch-only compile errors show up clearly.
- Import AppIntents explicitly in every file that uses Button(intent:), Toggle(intent:) or ControlWidgetButton, and import WidgetKit in widget files. Use `static let title: LocalizedStringResource = "..."` for intent metadata, which also stays clean under a Swift 6 compiler in Swift 5 mode.
- Use AppEntity with EntityQuery (suggestedEntities from App Group presets), or AppEnum, for the configurable preset parameter rather than raw Int or Double volume parameters, which may be awkward in the watchOS 26 configuration UI. Compile the entity and query into both the watch app and the watch widget extension.
- During device testing, turn on WidgetKit Developer Mode (Settings > Developer) to bypass reload budgets. WWDC25 mentions this setting; it is available on iOS and probably on watchOS.

### Open risks
- Whether interactive Button(intent:) works on watch-face complications (not just the Smart Stack) is inconsistent in developer reports. Apple says all families are interactive on watchOS 11 and later, but forum threads report taps that only launch the app. This must be checked on the real watch tomorrow.
- Writing HealthKit samples from the watchOS widget extension's perform() is expected to work, based on the entitlement and inherited authorization, but Apple does not document it explicitly. If it fails, drinks stay pending in the App Group until the watch app opens.
- HealthKit permissions for a single-target watch app are separate from the iPhone app's, according to developer reports. If the user never opens the watch app and grants access, the complication cannot write to Health.
- The watchOS version on the user's watch is unknown. On watchOS 10 widgets are not interactive (a tap opens the app). Configurable widgets and controls need watchOS 26. Devices older than Series 6 or SE 2 cannot run watchOS 11 or later.
- Using `if #available(watchOS 26.0, *)` inside a WidgetBundle body relies on the WidgetBundleBuilder fix from Xcode 16.1b3. It has not been tested on watchOS older than 26 at runtime. If the widgets disappear on an older watch, switch to top-level @WidgetBundleBuilder helper properties per availability.
- GitHub runners now offer an Xcode 27 preview. If the default Xcode on macos-26 changes, new SDK deprecations or signature changes (for example, EntityQuery.suggestedEntities is now documented as returning Self.Result) could produce warnings or errors, so pin the Xcode version.
- Up to about 16 recommendations may be shown on watchOS before 26 (unanswered forum report). An older SiriKit-era report described a watch extension crash when an interpolated string was used as the recommendation description.
- App Group data does not sync between iPhone and Watch. Cross-device totals depend on HealthKit sync latency, or on WatchConnectivity, whose complication-transfer API (transferCurrentComplicationUserInfo) is iOS-side only, limited to about 50 transfers a day, and not supported in the Simulator.
- Free Personal Team: provisioning profiles expire after 7 days, and the number of App IDs per week is limited (from memory; the app plus extensions use 4 App IDs). There is no Push capability, so widget push updates are not possible.
- Interactive widgets and HealthKit behave differently in the watch simulator. The simulator can confirm compilation and layout, but tap-to-intent and Health writes need the real device.

## iOS/watchOS WidgetKit interactive widgets (Button(intent:)), AppIntentConfiguration + AppEntity config, Controls (iOS 18 / watchOS 26), WidgetBundle availability syntax, container background/accent/families, reload budget. Verified against Apple DocC JSON (developer.apple.com/tutorials/data/documentation/...), WWDC24/25 transcripts and Apple Developer Forums on 2026-09-25. Current docs already show iOS/watchOS 27.0 APIs.

- **[high]** Where a widget Button/Toggle intent runs: 'By default, the system runs the app intent in the same process as the widget extension. However, if the app intent's openAppWhenRun property is true, or if the intent conforms to AudioPlaybackIntent, ForegroundContinuableIntent, LiveActivityIntent, or PushToTalkTransmissionIntent, the system performs the app intent in the app's process.'  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities  
  _implication_: A plain AppIntent's perform() runs in the widget extension by default. HealthKit writes, the App Group store and the WidgetCenter calls must all work from inside the extension. Treat the App Group JSON store as the only source of truth, because in-memory app state is not visible there.
- **[high]** Target membership: 'If you adopt the AppIntent protocol, add your custom app intent to your widget extension target and your app target.' For LiveActivityIntent/AudioPlaybackIntent: 'the system runs the app intent in the app's process. Make sure to add your custom app intent to your app target.' The widget target always has to compile the type anyway, because Button(intent:) references it. For controls that open the app with an OpenIntent: 'The system requires the Target Membership of the app intent to be set to both the app and the widget extension to open the app.'  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities ; https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system  
  _implication_: In XcodeGen, put the intents and entities in a shared source folder (e.g. Shared/Intents) listed under the sources of the app, the iOS widget extension, the watch app and the watch widget extension. Do not put them in the Linux Swift package, because it cannot import AppIntents.
- **[medium]** Empirical (not in Apple docs): when an AppIntent is compiled into both the app and the widget, it runs in the app process if the app is running and not suspended, and otherwise in the widget process. The same rules apply when it runs from Shortcuts. A forum report (thread 732771) says that with the app alive in the background, perform() did not appear to be called in the widget process.  
  _src_: https://zachwaugh.com/posts/forcing-appintent-to-run-in-main-app-process ; https://developer.apple.com/forums/thread/732771  
  _implication_: perform() must be process-agnostic: read and write the App Group file, then reload. Log with os.Logger in both processes when debugging tomorrow.
- **[high]** perform() return triggers a timeline reload: 'When you return from the perform() function, the system reloads the widget's timeline using its timeline provider... Make sure any code that's necessary for the timeline update runs before you return from perform().' Also: 'Interactions with a toggle or button always guarantee a timeline reload.'  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities  
  _implication_: Await the store write (and ideally the HealthKit save) before `return .result()`. Also call WidgetCenter.shared.reloadAllTimelines() so the app's other widgets (for example a Lock Screen progress widget of a different kind) refresh as well.
- **[high]** Parameters of intents used by widget buttons are never resolved: 'Make sure input parameters have assigned values because, unlike app intents you define for system functionality like Siri, widgets don't resolve parameters for app intents.' A ControlWidgetButton whose intent has an unset parameter with requestValueDialog silently never calls perform() (forum 789371).  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities ; https://developer.apple.com/forums/thread/789371  
  _implication_: The widget and control LogDrink intent must be built with all values (e.g. init(presetID:volumeML:beverageRaw:)). Give each @Parameter a default so the required empty init() cannot leave an unset non-optional parameter. Keep the Siri intent (which may prompt) as a separate type.
- **[high]** openAppWhenRun (static var openAppWhenRun: Bool) is deprecated as of iOS/watchOS 26.0 in favor of supportedModes. 'Setting this property to true generates an error if the app intent runs in an app extension.'  
  _src_: https://developer.apple.com/documentation/appintents/appintent/openappwhenrun  
  _implication_: Never set openAppWhenRun on the widget/control intent: it produces a deprecation warning and a runtime error in the extension, and it would launch the app on every tap.
- **[high]** `static var supportedModes: IntentModes { get }` and `struct IntentModes` (OptionSet: .background, .foreground, .foreground(_ : IntentModes.ForegroundMode) with .immediate/.dynamic/.deferred) are available ONLY on iOS/iPadOS/macOS/tvOS/visionOS/watchOS 26.0+. Related API: systemContext.currentMode and continueInForeground(_:alwaysConfirm:).  
  _src_: https://developer.apple.com/documentation/appintents/appintent/supportedmodes ; https://developer.apple.com/documentation/appintents/intentmodes ; https://developer.apple.com/videos/play/wwdc2025/275/  
  _implication_: With a deployment target below 26, any supportedModes witness needs @available(iOS 26.0, watchOS 26.0, *). Recommendation: do not declare supportedModes on the logging intent at all, because the default background behaviour is what we want.
- **[medium]** ForegroundContinuableIntent (iOS 16.4) is deprecated in iOS/watchOS 26.0 ('include .foreground(.dynamic) in supportedModes instead'). In practice developers must write `@available(iOSApplicationExtension, unavailable) extension X: ForegroundContinuableIntent {}` because it is not usable in extensions.  
  _src_: https://developer.apple.com/documentation/appintents/foregroundcontinuableintent ; https://developer.apple.com/forums/thread/789371 ; https://zachwaugh.com/posts/forcing-appintent-to-run-in-main-app-process  
  _implication_: Do not use it for the widget/control intent.
- **[high]** LiveActivityIntent is available on iOS/iPadOS/Mac Catalyst 17.0 only. It does NOT exist on watchOS or macOS. AudioPlaybackIntent is iOS 17 / watchOS 10 / macOS 14.  
  _src_: https://developer.apple.com/documentation/appintents/liveactivityintent ; https://developer.apple.com/documentation/appintents/audioplaybackintent  
  _implication_: If we ever want to force the app process (the fallback when a HealthKit write from the extension fails), use `#if os(iOS) extension LogDrinkIntent: LiveActivityIntent {} #endif`. Unguarded, it breaks the watch targets with a compile error.
- **[high]** iOS 27.0+ only: `static var allowedExecutionTargets: IntentExecutionTargets` on AppIntent and EntityQuery, with options .main, .appIntentsExtension, .widgetKitExtension and .default. The docs state: 'the system may perform your AppIntent or EntityQuery from the app or App Intents extension'.  
  _src_: https://developer.apple.com/documentation/appintents/intentexecutiontargets ; https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets  
  _implication_: This requires the Xcode 27 SDK and @available(iOS 27.0, *). Avoid it, since CI may only have Xcode 26. It also confirms that EntityQuery can run in either process, so the store must live in the App Group container.
- **[high]** Button intent initializers (SwiftUI): `init(_ titleKey: LocalizedStringKey, intent: some AppIntent)` and `init<I>(intent: I, @ViewBuilder label: () -> Label) where I : AppIntent`. `Toggle init<I>(isOn: Bool, intent: I, @ViewBuilder label: () -> Label) where I : AppIntent`. All are iOS 17.0 / watchOS 10.0 / macOS 14.0.  
  _src_: https://developer.apple.com/documentation/swiftui/button/init(intent:label:) ; https://developer.apple.com/documentation/swiftui/toggle/init(isOn:intent:label:)  
  _implication_: iOS deployment must be at least 17 (we recommend 18). These initializers compile on watchOS 10+, but watch interactivity only works at runtime from watchOS 11.
- **[high]** Interactive widget families on iOS: systemSmall/Medium/Large/ExtraLarge/ExtraLargePortrait plus accessoryCircular and accessoryRectangular 'on iPhone and iPad' (accessoryInline is not listed). 'On a locked device, buttons and toggles are inactive and the system doesn't perform actions unless a person authenticates and unlocks their device.'  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities  
  _implication_: The Lock Screen quick-log button needs accessoryCircular or accessoryRectangular. Tomorrow's testers must unlock the phone before a Lock Screen widget button works.
- **[medium]** watchOS 11 made widgets interactive: 'buttons and toggles will be available to make your watchOS widget interactive... All watchOS widget families support interactivity!' There is also a forum report of Button(intent:) only opening the app in watch-face complications (as opposed to the Smart Stack) on watchOS 10.  
  _src_: https://developer.apple.com/videos/play/wwdc2024/10205/ ; https://developer.apple.com/forums/thread/734855  
  _implication_: Set the watch deployment target to watchOS 11.0 or later for one-tap logging from the Smart Stack and complications. Verify on the device that a tap on the complication runs the intent rather than launching the app.
- **[high]** AppIntentConfiguration: `@MainActor @preconcurrency struct AppIntentConfiguration<Intent, Content> where Intent : WidgetConfigurationIntent, Content : View`; `init<Provider>(kind: String, intent: Intent.Type, provider: Provider, content: (Provider.Entry) -> Content)`. iOS 17.0 / watchOS 10.0 / macOS 14.0. `protocol WidgetConfigurationIntent : AppIntent` is iOS 17 / watchOS 10 and does not need perform().  
  _src_: https://developer.apple.com/documentation/widgetkit/appintentconfiguration ; https://developer.apple.com/documentation/appintents/widgetconfigurationintent  
  _implication_: The configurable 'one tap logs X' widget uses AppIntentConfiguration with a SelectPresetIntent: WidgetConfigurationIntent whose parameter is a DrinkPresetEntity.
- **[high]** AppIntentTimelineProvider (iOS 17 / watchOS 10): `func placeholder(in: Context) -> Entry` (sync), `func snapshot(for: Intent, in: Context) async -> Entry`, `func timeline(for: Intent, in: Context) async -> Timeline<Entry>`, `func recommendations() -> [AppIntentRecommendation<Intent>]` (sync), `func relevance() async -> WidgetRelevance<Intent>`. The DEFAULT implementation of recommendations() exists only on iOS/iPadOS/Mac Catalyst/macOS/visionOS. It is NOT available on watchOS.  
  _src_: https://developer.apple.com/documentation/widgetkit/appintenttimelineprovider ; https://developer.apple.com/documentation/widgetkit/appintenttimelineprovider/recommendations()-5xfj5  
  _implication_: COMPILE BLOCKER: a provider compiled for watchOS without recommendations() fails with 'does not conform to protocol'. Implement it under #if os(watchOS), or unconditionally. It is synchronous, so read the store synchronously.
- **[high]** On watchOS: 'watchOS 11 and older don't have an interface for configuring widgets or complications.' From watchOS 26, returning [] from recommendations() lets people configure the widget themselves. Apple's pattern: `if #available(watchOS 26, *) { return [] } else { return recommended }`. `AppIntentRecommendation(intent:description:)` accepts LocalizedStringKey, Text, some StringProtocol or LocalizedStringResource.  
  _src_: https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget ; https://developer.apple.com/videos/play/wwdc2025/334/ ; https://developer.apple.com/documentation/widgetkit/appintentrecommendation  
  _implication_: On the watch, return one recommendation per preset (Water 500 ml, Coke Zero 330 ml, ...) for watchOS 11, and [] on watchOS 26+.
- **[high]** Dynamic options for a widget parameter come from the AppEntity's `static var defaultQuery`. The EntityQuery needs `func entities(for identifiers: [Entity.ID]) async throws -> [Entity]`. 'When a person edits a widget ... the system invokes the query object's suggestedEntities() method' (`func suggestedEntities() async throws -> Result`). A non-optional entity parameter needs a default, which can come from `func defaultResult() async -> DefaultValue?` (declared on DynamicOptionsProvider, which EntityQuery inherits). The parameter order in the intent sets the order in the edit UI.  
  _src_: https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget ; https://developer.apple.com/documentation/appintents/entityquery ; https://developer.apple.com/documentation/appintents/dynamicoptionsprovider  
  _implication_: DrinkPresetQuery reads the presets JSON from the App Group container in both entities(for:) and suggestedEntities(). entities(for:) omits deleted IDs, and defaultResult() returns the first preset.
- **[high]** The AppEntity protocol (iOS 16 / watchOS 9) requires `static var defaultQuery`, `static var typeDisplayRepresentation: TypeDisplayRepresentation` (string-literal expressible), `var displayRepresentation: DisplayRepresentation` and `var id` whose ID conforms to EntityIdentifierConvertible & Sendable (String works). In the iOS 26+ SDK it also inherits AppValue.  
  _src_: https://developer.apple.com/documentation/appintents/appentity ; https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget  
  _implication_: Use `let id: String` plus plain stored properties. @Property is not needed.
- **[high]** AppIntent metadata: `static var title: LocalizedStringResource`, `static var description: IntentDescription? { get }` (Apple samples use `static var description = IntentDescription("...")`), `static var isDiscoverable: Bool` (iOS 17 / watchOS 10; false means 'you can run the intent from your app's interface or from a widget, but system features can't access it'; App Shortcuts require true), and `static var authenticationPolicy: IntentAuthenticationPolicy` (default .alwaysAllowed, which runs even when the device is locked; other cases are .requiresAuthentication and .requiresLocalDeviceAuthentication).  
  _src_: https://developer.apple.com/documentation/appintents/appintent ; https://developer.apple.com/documentation/appintents/appintent/isdiscoverable ; https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy  
  _implication_: The widget/control LogDrinkIntent can set isDiscoverable = false to keep Shortcuts tidy. The Siri/App Shortcut intent must be a separate discoverable intent. Use `static let` rather than `static var` so the code stays Swift-6-clean.
- **[medium]** Widget configuration UX: on the Home Screen, long-press the widget and choose Edit Widget. On the Lock Screen, edit the widget during Lock Screen customization. The UI is generated automatically from the @Parameter types. `WidgetConfiguration.promptsForUserConfiguration()` (iOS 18.0 / macOS 15; NOT watchOS) opens the config UI automatically after the widget is added.  
  _src_: memory (UX flow); https://developer.apple.com/documentation/swiftui/widgetconfiguration/promptsforuserconfiguration() (availability verified)  
  _implication_: If widget code is shared with the watch target, wrap promptsForUserConfiguration() in #if !os(watchOS).
- **[high]** Controls (iOS/iPadOS/Mac Catalyst 18.0, macOS 26.0, watchOS 26.0): `@MainActor @preconcurrency protocol ControlWidget { associatedtype Body: ControlWidgetConfiguration; var body: Body }`. `StaticControlConfiguration.init(kind: String, @ControlWidgetTemplateBuilder content: @escaping () -> Content)` and `init<Provider>(kind:provider:content: (Provider.Value) -> Content)` with Provider: ControlValueProvider. `AppIntentControlConfiguration.init(kind: String, intent: Configuration.Type = Configuration.self, @ControlWidgetTemplateBuilder content: @escaping (Configuration) -> Content)` and `init<Provider>(kind:provider:content:)` where Provider: AppIntentControlValueProvider. The ControlWidgetConfiguration modifiers are displayName(LocalizedStringResource), description(LocalizedStringResource), promptsForUserConfiguration() and pushHandler(_:).  
  _src_: https://developer.apple.com/documentation/widgetkit/staticcontrolconfiguration ; https://developer.apple.com/documentation/widgetkit/appintentcontrolconfiguration ; https://developer.apple.com/documentation/swiftui/controlwidget ; https://developer.apple.com/documentation/swiftui/controlwidgetconfiguration  
  _implication_: A configurable one-tap control can use AppIntentControlConfiguration(kind:intent:) with no value provider, because the content closure receives the configuration intent directly.
- **[high]** ControlWidgetButton (iOS 18 / watchOS 26): `init(action: Action, @ViewBuilder label: @escaping () -> Label) where ActionLabel == ControlWidgetButtonDefaultActionLabel, Action : AppIntent`; an overload with `Action : OpenIntent` launches the app; `init(action:label:actionLabel: @escaping (Bool) -> ActionLabel) where Action : AppIntent`; and `init(_ title: LocalizedStringResource | LocalizedStringKey | some StringProtocol, action:actionLabel:)`. Apple describes it as 'Buttons don't have state; use them for fire-and-forget actions.'  
  _src_: https://developer.apple.com/documentation/widgetkit/controlwidgetbutton ; https://developer.apple.com/documentation/widgetkit/controlwidgetbutton/init(action:label:)-77p8j  
  _implication_: `ControlWidgetButton(action: LogDrinkIntent(...)) { Label(name, systemImage: "drop.fill") }`. Use an SF Symbol, because controls render only symbol, text and tint.
- **[high]** ControlWidgetTemplateBuilder only has `buildBlock<Content>(Content) -> some ControlWidgetTemplate` (a single child) and `buildExpression`. It has NO buildEither or buildOptional. `let` statements before the single template are allowed.  
  _src_: https://developer.apple.com/documentation/swiftui/controlwidgettemplatebuilder  
  _implication_: COMPILE SAFETY: no if/else or switch inside a control content closure. Compute values with `let` (e.g. `let id = config.preset?.id ?? "water-500"`) and emit exactly one ControlWidgetButton.
- **[high]** `protocol ControlConfigurationIntent : AppIntent` (iOS 18 / watchOS 26) does not need perform(). 'If you don't provide a default value for the intent parameter, the parameter's value must be optional, to allow the system to preview the control before someone configures it.'  
  _src_: https://developer.apple.com/documentation/appintents/controlconfigurationintent  
  _implication_: Declare `@Parameter(title: "Drink") var preset: DrinkPresetEntity?` (optional) and fall back to a built-in default preset in the content closure. Use a separate type from the WidgetConfigurationIntent.
- **[high]** `class ControlCenter` (iOS 18 / watchOS 26): `static let shared`, `func reloadAllControls()`, `func reloadControls(ofKind: String)` and `func currentControls() async throws -> [ControlInfo]`. 'The system queries for the state of a control when perform() returns.'  
  _src_: https://developer.apple.com/documentation/widgetkit/controlcenter ; https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system  
  _implication_: A stateless button control needs no reload. If a control shows today's total, call ControlCenter.shared.reloadAllControls() after logging (behind #available(iOS 18.0, watchOS 26.0, *) if the deployment target is lower).
- **[high]** Controls appear in Control Center, on the Lock Screen and on the Action button (iPhone). A configurable control can be configured by long press, in Control Center edit mode, on the Lock Screen, and when assigning it to the Action button. On watchOS 26, 'People can add the controls from your iPhone app to system spaces on Apple Watch, even if you don't have a Watch app. When the control is tapped on the Apple Watch, the action is performed on the companion iPhone. ... controls whose actions foreground the iPhone app will not appear on Apple Watch.'  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-refinements-and-configuration-to-controls ; https://developer.apple.com/videos/play/wwdc2025/334/  
  _implication_: An iOS 'Log 500 ml water' control gives the watch a one-tap action for free on watchOS 26, provided its intent never foregrounds the app.
- **[high]** WidgetBundleBuilder: `buildExpression<Content>(_:) -> some Widget where Content : ControlWidget` is iOS 18 / watchOS 26. `buildLimitedAvailability(_ widget: some ControlWidget) -> any Widget & _LimitedAvailabilityWidgetMarker` is iOS 18 / watchOS 26. `buildLimitedAvailability(_ widget: some Widget)` is iOS 16.1 / watchOS 9.1. `buildOptional((any Widget & _LimitedAvailabilityWidgetMarker)?)` is also available. `buildBlock<each C>` is variadic. Conditionals may use only `if #available` with no else branch.  
  _src_: https://developer.apple.com/documentation/swiftui/widgetbundlebuilder ; https://developer.apple.com/documentation/swiftui/widgetbundlebuilder/buildlimitedavailability(_:) ; https://developer.apple.com/documentation/swiftui/widgetbundlebuilder/buildoptional(_:)  
  _implication_: With an iOS 17 deployment target, `if #available(iOS 18.0, *) { QuickLogControl() }` inside the bundle body is the supported syntax, and the control type needs @available(iOS 18.0, *). With iOS 18 as the minimum, list the control directly with no check.
- **[high]** The bug where WidgetBundleBuilder crashes on iOS 17 with an `if #available(iOS 18.0, *)` control check ('includes an unknown OS version'; no widgets on iOS 17) was 'fixed in Xcode 16.1 beta 3 with the updated SDKs' (Apple engineer). The older workaround used two @WidgetBundleBuilder computed properties (one @available(iOSApplicationExtension 18.0, *)) returned from `if #available ... return a else return b`. That compiles because of SE-0360 limited-availability opaque types, but only as a single if/else, not else-if.  
  _src_: https://developer.apple.com/forums/thread/762688 ; https://developer.apple.com/forums/thread/759670  
  _implication_: With Xcode 26 on CI the simple builder syntax is fine. Simplest and safest: set IPHONEOS_DEPLOYMENT_TARGET to 18.0 and avoid the question entirely.
- **[high]** `func containerBackground<V: View>(for container: ContainerBackgroundPlacement, alignment: Alignment = .center, @ContentBuilder content: () -> V) -> some View` is iOS 17 / watchOS 10. The shape-style variant is containerBackground(_:for:). ContainerBackgroundPlacement.widget is iOS 17 / watchOS 10. Without it, 'the system displays a warning message that overlays the widget during development'. Opt out with WidgetConfiguration.containerBackgroundRemovable(false), which excludes the widget from the iPad Lock Screen and StandBy.  
  _src_: https://developer.apple.com/documentation/swiftui/view/containerbackground(for:alignment:content:) ; https://developer.apple.com/documentation/widgetkit/displaying-the-right-widget-background  
  _implication_: Every widget root view, including the accessory families and the watch families, gets `.containerBackground(for: .widget) { ... }` or `.containerBackground(.fill.tertiary, for: .widget)`.
- **[high]** `func invalidatableContent(_ invalidatable: Bool = true) -> some View` (iOS 17 / watchOS 10): 'In an interactive widget a view is invalidated from the moment the user interacts with a control on the widget to the moment when a new timeline update has been presented.' `widgetAccentable(_ accentable: Bool = true)` is iOS 16 / watchOS 9. `Image.widgetAccentedRenderingMode(_:)` is iOS 18 / watchOS 11. `@Environment(\.widgetRenderingMode)` (.fullColor/.accented/.vibrant) is iOS 16 / watchOS 9. `\.showsWidgetContainerBackground` and `AccessoryWidgetBackground()` (iOS 16 / watchOS 9) are also available.  
  _src_: https://developer.apple.com/documentation/swiftui/view/invalidatablecontent(_:) ; https://developer.apple.com/documentation/swiftui/view/widgetaccentable(_:) ; https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances  
  _implication_: Mark the 'today total' Text with .invalidatableContent(). Put the drop icon and progress in .widgetAccentable() so tinted/clear (accented) Home Screen modes and watch faces look right.
- **[high]** `func contentMarginsDisabled() -> some WidgetConfiguration` takes effect from iOS 17 / watchOS 10 / macOS 14. With it, you are responsible for padding (use the \.widgetContentMargins environment value).  
  _src_: https://developer.apple.com/documentation/swiftui/widgetconfiguration/contentmarginsdisabled()  
  _implication_: This is optional. Leave margins enabled for simplicity.
- **[high]** WidgetFamily availability: systemSmall/Medium/Large are iOS/macOS/visionOS ONLY (unavailable on watchOS). accessoryCorner is watchOS ONLY. accessoryCircular and accessoryRectangular are iOS 16 / watchOS 9. accessoryInline is iOS 16 / watchOS 9. Rendering modes: accessoryCircular, accessoryCorner and accessoryInline get only accented/vibrant (not fullColor).  
  _src_: https://developer.apple.com/documentation/widgetkit/widgetfamily ; https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances  
  _implication_: COMPILE SAFETY: referencing .systemSmall in watch code or .accessoryCorner in iOS code is an 'unavailable' error. Split supportedFamilies and any `switch family` cases with #if os(watchOS), and always include a `default:` branch.
- **[high]** Reload budget: a widget the user views frequently typically gets 40 to 70 refreshes per day (about every 15 to 60 minutes), and timeline entries should be at least about 5 minutes apart. Reloads do NOT count against the budget when the containing app is in the foreground, 'The widget performs an app intent, such as when the user taps a button or toggles a switch', the widget animates, or the locale or accessibility settings change. `WidgetCenter.shared.reloadAllTimelines()` and `reloadTimelines(ofKind:)` are iOS 14 / watchOS 9.  
  _src_: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date  
  _implication_: Call WidgetCenter.shared.reloadAllTimelines() freely from the foreground app after each log and from the widget intent. The timeline can use `.after(startOfNextDay)` so the daily total resets at midnight.
- **[medium]** HealthKit on a locked device: 'the device encrypts the HealthKit store when the user locks the device... your app may not be able to read data... However, your app can still write to the store, even when the phone is locked. HealthKit temporarily caches the data and saves it to the encrypted store as soon as the user unlocks the phone.' Widgets cannot request HealthKit authorization. They use the containing app's grant, and the HealthKit entitlement must also be on the extension target (forum guidance).  
  _src_: https://developer.apple.com/documentation/healthkit/protecting-user-privacy ; https://developer.apple.com/forums/thread/653814  
  _implication_: Controls run on a locked device by default (authenticationPolicy .alwaysAllowed). Writes are fine, but the timeline must read today's total from the App Group store, not from a HealthKit query. Add com.apple.developer.healthkit to the widget extension entitlements too.
- **[high]** Since WWDC25 (Xcode 26), App Intents can live in Swift Packages and static libraries via `AppIntentsPackage` (protocol iOS 17 / watchOS 10; `static var includedPackages: [any AppIntentsPackage.Type]`).  
  _src_: https://developer.apple.com/videos/play/wwdc2025/275/ ; https://developer.apple.com/documentation/appintents/appintentspackage  
  _implication_: This is possible but adds risk (metadata extraction across packages). For build safety, compile the intent sources directly into each target via shared XcodeGen source paths instead.

### Snippets

```
// Shared/Intents/LogDrinkIntent.swift  -- member of: iOS app, iOS widget ext, watch app, watch widget ext
import AppIntents
import WidgetKit

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    static let description = IntentDescription("Logs a drink preset with one tap.")
    static let isDiscoverable: Bool = false          // widget/control only; Siri uses a separate discoverable intent

    @Parameter(title: "Preset ID", default: "water-500") var presetID: String
    @Parameter(title: "Volume (ml)", default: 500) var volumeML: Double
    @Parameter(title: "Beverage", default: "water") var beverageRaw: String

    init() {}
    init(presetID: String, volumeML: Double, beverageRaw: String) {
        self.presetID = presetID
        self.volumeML = volumeML
        self.beverageRaw = beverageRaw
    }

    func perform() async throws -> some IntentResult {
        // 1) append entry to App Group JSON store (await completion BEFORE returning)
        // 2) try HealthKit save; on failure mark entry as pendingHealthSync (app retries on launch)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        #endif
        return .result()
    }
}
// Optional: force app process on iPhone only (LiveActivityIntent does not exist on watchOS):
// #if os(iOS)
// extension LogDrinkIntent: LiveActivityIntent {}
// #endif
```
```
// Shared/Intents/DrinkPresetEntity.swift
import AppIntents

struct DrinkPresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Drink preset"
    static let defaultQuery = DrinkPresetQuery()

    let id: String
    let name: String
    let volumeML: Double
    let beverageRaw: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Int(volumeML)) ml")
    }
}

struct DrinkPresetQuery: EntityQuery {
    func entities(for identifiers: [DrinkPresetEntity.ID]) async throws -> [DrinkPresetEntity] {
        PresetRepository.loadAll().filter { identifiers.contains($0.id) }   // App Group JSON
    }
    func suggestedEntities() async throws -> [DrinkPresetEntity] {
        PresetRepository.loadAll()
    }
    func defaultResult() async -> DrinkPresetEntity? {
        PresetRepository.loadAll().first
    }
}

struct SelectPresetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    static let description = IntentDescription("One tap logs this drink.")

    @Parameter(title: "Drink")
    var preset: DrinkPresetEntity?

    init() {}
    init(preset: DrinkPresetEntity) { self.preset = preset }
}
```
```
// Widget provider (shared iOS + watchOS widget extensions)
import WidgetKit
import SwiftUI
import AppIntents

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let preset: DrinkPresetEntity
    let todayTotalML: Double
}

struct QuickLogProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: Date(), preset: PresetRepository.fallback, todayTotalML: 0)
    }
    func snapshot(for configuration: SelectPresetIntent, in context: Context) async -> QuickLogEntry {
        makeEntry(configuration)
    }
    func timeline(for configuration: SelectPresetIntent, in context: Context) async -> Timeline<QuickLogEntry> {
        let next = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return Timeline(entries: [makeEntry(configuration)], policy: .after(next))
    }
    #if os(watchOS)
    // REQUIRED on watchOS: no default implementation exists there.
    func recommendations() -> [AppIntentRecommendation<SelectPresetIntent>] {
        if #available(watchOS 26.0, *) { return [] }   // user-configurable on watchOS 26+
        return PresetRepository.loadAll().map {
            AppIntentRecommendation(intent: SelectPresetIntent(preset: $0), description: Text($0.name))
        }
    }
    #endif
    private func makeEntry(_ c: SelectPresetIntent) -> QuickLogEntry {
        QuickLogEntry(date: Date(), preset: c.preset ?? PresetRepository.fallback,
                      todayTotalML: TodayTotals.loadML())   // from App Group store, NOT HealthKit
    }
}

struct QuickLogWidget: Widget {
    static let kind = "QuickLogWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectPresetIntent.self, provider: QuickLogProvider()) { entry in
            QuickLogView(entry: entry)
                .containerBackground(for: .widget) { Color.blue.opacity(0.15) }
        }
        .configurationDisplayName("Quick log")
        .description("One tap logs your drink.")
        .supportedFamilies(Self.families)
    }
    private static var families: [WidgetFamily] {
        #if os(watchOS)
        return [.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner]
        #else
        return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]
        #endif
    }
}

struct QuickLogView: View {
    let entry: QuickLogEntry
    var body: some View {
        VStack(spacing: 4) {
            Text("\(Int(entry.todayTotalML)) ml").invalidatableContent()
            Button(intent: LogDrinkIntent(presetID: entry.preset.id,
                                          volumeML: entry.preset.volumeML,
                                          beverageRaw: entry.preset.beverageRaw)) {
                Label("+\(Int(entry.preset.volumeML))", systemImage: "drop.fill")
            }
            .widgetAccentable()
        }
    }
}
```
```
// iOS widget extension only: Control (iOS 18+)
import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 18.0, *)   // redundant (harmless) if IPHONEOS_DEPLOYMENT_TARGET >= 18.0
struct SelectPresetControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink")
    var preset: DrinkPresetEntity?        // must be optional (no literal default possible for an entity)
    init() {}
}

@available(iOS 18.0, *)
struct QuickLogControl: ControlWidget {
    static let kind = "QuickLogControl"
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, intent: SelectPresetControlIntent.self) { config in
            // ControlWidgetTemplateBuilder: NO if/else allowed -- use lets, then ONE template
            let p = config.preset ?? PresetRepository.fallback
            ControlWidgetButton(action: LogDrinkIntent(presetID: p.id, volumeML: p.volumeML, beverageRaw: p.beverageRaw)) {
                Label(p.name, systemImage: "drop.fill")
            }
        }
        .displayName("Log drink")
        .description("Logs the chosen drink with one tap.")
        .promptsForUserConfiguration()
    }
}
```
```
// iOS widget extension bundle
import WidgetKit
import SwiftUI

@main
struct SayoneHealthWidgets: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        if #available(iOS 18.0, *) {   // required only if deployment target < 18; supported via buildLimitedAvailability(some ControlWidget)
            QuickLogControl()
        }
    }
}

// watch widget extension bundle (separate file, separate target)
@main
struct SayoneHealthWatchWidgets: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        // Native watch controls need watchOS 26: if #available(watchOS 26.0, *) { WatchQuickLogControl() }
        // iPhone controls already appear on watchOS 26 automatically (action runs on iPhone).
    }
}
```
```
# project.yml fragment (XcodeGen) -- share intent sources across 4 targets
targets:
  SayoneHealthWidgets:
    type: app-extension
    platform: iOS
    deploymentTarget: "18.0"
    sources:
      - path: Widgets/iOS
      - path: Shared/Intents
      - path: Shared/Store
    info:
      path: Widgets/iOS/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Widgets/iOS/Widgets.entitlements
      properties:
        com.apple.security.application-groups: [group.com.sayoneone.sayonehealth]
        com.apple.developer.healthkit: true
```

### Recommendations
- Set IPHONEOS_DEPLOYMENT_TARGET = 18.0. Then Controls, ControlCenter and promptsForUserConfiguration need no #available checks, and the WidgetBundle simply lists the control. Keep Control sources in an iOS-only folder so the watch targets never compile ControlWidget, which needs watchOS 26.
- Set WATCHOS_DEPLOYMENT_TARGET = 11.0. That is the minimum for widgets whose Button(intent:) actually runs on the watch. Implement recommendations() in the watch provider (it is mandatory there): return presets on watchOS 11 and [] on watchOS 26+.
- Use two intent types. (a) LogDrinkIntent (isDiscoverable = false) for widget buttons and controls, with fully pre-filled primitive parameters, each with a default. (b) A separate discoverable Siri/App Shortcut intent with an AppEnum/AppEntity parameter and Russian/English phrases. Never rely on parameter resolution from widgets or controls.
- Compile the intent, entity and query sources directly into all 4 targets (iOS app, iOS widget ext, watch app, watch widget ext) via shared XcodeGen source paths. Keep AppShortcutsProvider in the app targets only (memory: one provider per bundle). Do not use the Linux package for AppIntents code.
- Keep perform() process-agnostic. Write the entry to the App Group JSON store first and await it. Then attempt the HKHealthStore save; on failure, set a pendingHealthSync flag that the app flushes on next launch or foreground. Then call WidgetCenter.shared.reloadAllTimelines() (and ControlCenter.shared.reloadAllControls() on iOS 18+), then return .result().
- Add com.apple.developer.healthkit and the App Group entitlement to the iOS widget extension, as well as to the app. If on-device testing shows HealthKit saves failing from the extension, add `#if os(iOS) extension LogDrinkIntent: LiveActivityIntent {} #endif` to force the app process (iOS only, since it breaks watchOS if unguarded).
- Timeline and entity queries must read today's totals and presets from the App Group store, never from a HealthKit query. HealthKit reads fail while the device is locked, and controls run while locked by default (.alwaysAllowed). Write App Group files with the default protection or .completeFileProtectionUntilFirstUserAuthentication, not .complete.
- In widget code shared across platforms, never reference .systemSmall/.systemMedium on watchOS or .accessoryCorner on iOS. Build supportedFamilies in a #if os(watchOS) helper and include `default:` in any `switch family`. Wrap promptsForUserConfiguration() in #if !os(watchOS).
- Inside control content closures use only `let` statements and one ControlWidgetButton: the builder has no buildEither or buildOptional. Make the ControlConfigurationIntent's entity parameter optional and fall back to a built-in default preset.
- Every widget root view gets .containerBackground(for: .widget) { ... }. Mark the daily total with .invalidatableContent() and the icon/progress with .widgetAccentable(). Use SF Symbols (drop.fill, cup.and.saucer.fill, takeoutbag.and.cup.and.straw.fill) so controls and accented modes render correctly.
- Use `static let` for title, description, typeDisplayRepresentation and defaultQuery, and string literals for titles. This is Swift-6-clean and friendly to App Intents metadata extraction. Do not use openAppWhenRun, ForegroundContinuableIntent, supportedModes (iOS 26+) or allowedExecutionTargets (iOS 27+).
- Test plan for tomorrow: add the systemSmall widget, then Edit Widget and choose Coke Zero 330 ml, tap, and check that the total updates and Health shows the sample. Add a Lock Screen accessoryCircular widget (device must be unlocked for the tap to act). Add the control to Control Center, Lock Screen and Action button. On watchOS 26, check that the iPhone control appears in the watch's Control Center. Check the watch Smart Stack widget tap.

### Open risks
- HealthKit writes from inside the widget-extension process (the default for widget and control intents) are not explicitly documented by Apple. Authorization belongs to the app, and extensions cannot request it. If saves fail on device, fall back to the pending queue or the LiveActivityIntent app-process trick (iOS only).
- Empirical, undocumented behaviour: an intent compiled into both app and widget may run in the app process while the app is alive. Forum reports describe perform() apparently not running in the widget in that case. The mitigation is App Group persistence plus reloads from whichever process runs it; verify with logging on device.
- A forum report (thread 739243, no answer) says rapidly tapping an interactive widget button can bypass the intent and launch the host app instead. It is unverified and has no known workaround.
- Watch complications on the watch face (as opposed to Smart Stack widgets) have forum reports of Button(intent:) just opening the app on watchOS 10. WWDC24 says all watchOS 11 families support interactivity. Needs on-device confirmation.
- Lock Screen interactive widgets act only when the device is unlocked. Controls run while locked unless authenticationPolicy is changed, which is why the App Group file protection class matters.
- iPhone controls surfaced on watchOS 26 run on the iPhone. The watch-native widget logs on the watch. The two stores need syncing (WatchConnectivity or HealthKit), and WidgetCenter reloads on the other device do not happen automatically.
- The CI Xcode version is uncertain: GitHub macOS runner images may ship Xcode 26.x while docs already show iOS 27 APIs. Anything marked 27.0 (allowedExecutionTargets, IntentExecutionTargets) must be avoided or it will fail to compile.
- The WidgetBundleBuilder `if #available` crash was fixed only in Xcode 16.1+ SDKs, which is fine for Xcode 26. It is moot if the iOS deployment target is 18.0.
- Localization of AppIntent titles and parameter titles probably has to be present in each target bundle that runs the intent (app plus extension string catalogs/Localizable.strings). Not verified.
- Free Personal Team: HealthKit and App Groups are generally available to free teams, but not verified here. Controls, widgets and App Intents need no special entitlement. A free team's 7-day provisioning and 3-app-ID limit may bite with 4 targets (app, widget, watch app, watch widget).
- It is not verified whether interactive widgets and controls fully execute intents in the iOS Simulator. Widgets generally do; the Control Center gallery in the Simulator can be flaky.

## HealthKit facts for logging drinks (water, Coke Zero, other) from the iOS app, iOS widget, watchOS app, watch widget and Siri/App Intents. Checked against Apple's documentation JSON (developer.apple.com/tutorials/data/documentation/...), the iOS 18 SDK HealthKit headers, Apple Developer Forums replies from Apple staff, the WWDC20 session 10184 transcript, and Apple's capability tables.

- **[high]** The identifiers are HKQuantityTypeIdentifier.dietaryWater (iOS 9.0 / watchOS 2.0), .dietaryCaffeine, .dietaryEnergyConsumed and .dietarySugar (all three iOS 8.0 / watchOS 2.0). All four are cumulative. Canonical units from the SDK header comments: water is mL (volume), caffeine is g (mass), energy is kcal (energy), sugar is g (mass).  
  _src_: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietarywater (plus /dietarycaffeine, /dietaryenergyconsumed, /dietarysugar); HKTypeIdentifiers.h in the iPhoneOS18.0 SDK  
  _implication_: Use cumulativeSum statistics for all four. Every one of them can be written and read on watchOS.
- **[high]** Units: HKUnit.literUnit(with: .milli) gives mL, HKUnit.gramUnit(with: .milli) gives mg, HKUnit.kilocalorie() gives kcal, HKUnit.gram() gives g. HKUnit.largeCalorie() (iOS 11 / watchOS 4) equals the kilocalorie. Swift declarations are `class func literUnit(with prefix: HKMetricPrefix) -> Self`, `class func gramUnit(with prefix: HKMetricPrefix) -> Self`, `class func kilocalorie() -> Self` and `class func gram() -> Self`. You can check a unit with `quantityType.is(compatibleWith: unit)`.  
  _src_: https://developer.apple.com/documentation/healthkit/hkunit/literunit(with:) ; /gramunit(with:) ; /kilocalorie() ; /gram() ; /hkquantitytype/is(compatiblewith:)  
  _implication_: Water in mL, caffeine in mg, energy in kcal, sugar in g. If the unit does not match the type, the HKQuantitySample initializer throws an ObjC invalidArgumentException, which Swift cannot catch and which crashes the app. Keep the unit for each type in one constant table.
- **[high]** The modern type initializer `convenience init(_ identifier: HKQuantityTypeIdentifier)` on HKQuantityType, e.g. HKQuantityType(.dietaryWater), needs iOS 15.0 / watchOS 8.0 / macOS 13. It returns a non-optional value. The legacy form is HKObjectType.quantityType(forIdentifier:) -> HKQuantityType? (iOS 8 / watchOS 2). HKCorrelationType(.food) also exists and needs iOS 15 / watchOS 8.  
  _src_: https://developer.apple.com/documentation/healthkit/hkquantitytype/init(_:) ; /hkcorrelationtype/init(_:)  
  _implication_: This is safe with any deployment target of iOS 17+ and watchOS 10+.
- **[high]** The sample initializer is `convenience init(type quantityType: HKQuantityType, quantity: HKQuantity, start startDate: Date, end endDate: Date, metadata: [String : Any]?)` (iOS 8 / watchOS 2), and the quantity initializer is `HKQuantity(unit: HKUnit, doubleValue: Double)`. It throws invalidArgumentException if the unit is incompatible or if start > end. Setting start == end is allowed.  
  _src_: https://developer.apple.com/documentation/healthkit/hkquantitysample/init(type:quantity:start:end:metadata:)  
  _implication_: Use start = end = the tap time for an instant drink.
- **[high]** HKObject.metadata keys must be NSString. Values must be NSString, NSNumber, NSDate or HKQuantity. Apple explicitly encourages custom keys: 'you are also encouraged to create your own, custom keys as needed'.  
  _src_: HKObject.h (iOS 18 SDK) metadata property doc; https://developer.apple.com/documentation/healthkit/hkquantitysample/init(type:quantity:start:end:metadata:)  
  _implication_: Custom string keys such as "SayoneEntryID" and "SayoneDrinkKind" are fine. Never put Bool, UUID, Int8 or other non-bridging values in the dictionary. Use String, NSNumber or Date. I could not verify online whether HealthKit also reserves the 'HK' prefix for its own keys, so do not start custom keys with 'HK'.
- **[high]** HKMetadataKeySyncIdentifier (iOS 11 / watchOS 4) takes a String. HKMetadataKeySyncVersion (iOS 11 / watchOS 4) takes an NSNumber. They must be used together. The header says 'HKMetadataKeySyncVersion must be provided if HKMetadataKeySyncIdentifier is provided' and 'HKMetadataKeySyncVersion may not be provided if HKMetadataKeySyncIdentifier is not provided'. If the new object has a greater version, it replaces the existing object with the same sync identifier, including inside workouts and correlations.  
  _src_: https://developer.apple.com/documentation/healthkit/hkmetadatakeysyncidentifier ; /hkmetadatakeysyncversion ; HKMetadata.h (iOS 18 SDK)  
  _implication_: Write NSNumber(value: 1) as the version on every drink sample. An edit is a save with the same sync id and version + 1, which replaces the old sample with no delete step.
- **[medium]** In WWDC20 session 10184 Apple says a sync identifier 'allows us to recognize a sample anywhere in the health ecosystem across any of the user's devices'. It also says that if the same sample, with an equal version, is saved again from your app on Apple Watch, 'HealthKit would see that the sample already exists and ignore it', and that sync-identifier operations are transaction safe.  
  _src_: https://developer.apple.com/videos/play/wwdc2020/10184/ (transcript)  
  _implication_: Retries and flushes of a pending queue are idempotent, including across iPhone and Watch, as long as every sample of one logical entry has a deterministic sync id. The docs do not say whether an equal-version re-save returns success or an error. Treat both outcomes as 'already saved'. The docs also do not say whether sync ids are scoped per sample type, so make them unique per type (e.g. "<uuid>.water" and "<uuid>.caffeine").
- **[high]** HKMetadataKeyFoodType (iOS 8 / watchOS 2) takes a String, 'a short string representing the type of food, such as Banana'. HKMetadataKeyWasUserEntered (iOS 8 / watchOS 2) is a Bool NSNumber.  
  _src_: https://developer.apple.com/documentation/healthkit/hkmetadatakeyfoodtype ; /hkmetadatakeywasuserentered ; HKMetadata.h  
  _implication_: Put the localized drink name ("Вода" or "Кола без сахара") in FoodType on every sample, plus WasUserEntered = true.
- **[high]** Metadata predicates: `class func predicateForObjects(withMetadataKey key: String, allowedValues: [Any]) -> NSPredicate`, where the values must be NSString, NSNumber or NSDate and custom keys are explicitly supported. There is also `predicateForObjects(withMetadataKey:)` (key exists), `predicateForObjects(withMetadataKey:operatorType:value:)`, `predicateForObjects(from: HKSource)`, `predicateForObjects(from: Set<HKSource>)`, `predicateForObjects(with: Set<UUID>)`, and `predicateForSamples(withStart: Date?, end: Date?, options: HKQueryOptions = [])`. `HKSource.default()` returns the current app's source (iOS 8 / watchOS 2).  
  _src_: https://developer.apple.com/documentation/healthkit/hkquery/predicateforobjects(withmetadatakey:allowedvalues:) and the other HKQuery predicate pages (declarations fetched)  
  _implication_: To find or delete one entry, use predicateForObjects(withMetadataKey: "SayoneEntryID", allowedValues: [id.uuidString]). predicateForObjects(withMetadataKey: "SayoneEntryID") matches this app's samples from both the iPhone source and the Watch source, which HKSource.default() does not.
- **[medium]** You must not put a correlation type (HKCorrelationType(.food) or .bloodPressure) in requestAuthorization's toShare set. HealthKit raises NSInvalidArgumentException 'Authorization to share the following types is disallowed: HKCorrelationTypeIdentifier…'. You authorize the component quantity types, and after that saving the HKCorrelation works.  
  _src_: https://github.com/OpenMinis/OpenMinis/issues/393 ; https://github.com/EddyVerbruggen/HealthKit/issues/106 (same exception family); https://developer.apple.com/documentation/healthkit/hkcorrelation/init(type:start:end:objects:metadata:)  
  _implication_: Swift cannot catch an ObjC exception, so this crashes at runtime. Do not use HKCorrelation(.food): it adds a crash risk and more complex deletion, and it gives nothing a user of this app would see. Save flat quantity samples tied together by a shared custom 'SayoneEntryID'.
- **[high]** Async save and delete (Swift concurrency versions of the completion-handler APIs): `func save(_ object: HKObject) async throws`, `func save(_ objects: [HKObject]) async throws` ('if any object cannot be saved, none of them are saved'), `func delete(_ object: HKObject) async throws`, `func delete(_ objects: [HKObject]) async throws` (an empty array gives errorInvalidArgument), and `func deleteObjects(of objectType: HKObjectType, predicate: NSPredicate) async throws -> Int` ('Deletes objects saved by this application'; all or none). Errors are errorAuthorizationNotDetermined or errorAuthorizationDenied when share permission is missing. Saving an object whose UUID already exists gives errorInvalidArgument.  
  _src_: https://developer.apple.com/documentation/healthkit/hkhealthstore/save(_:withcompletion:)-47iwb ; /deleteobjects(of:predicate:withcompletion:) ; /delete(_:withcompletion:)-17hzm  
  _implication_: The user can grant water but deny caffeine. A multi-sample save of water + caffeine + kcal then fails completely. Filter the samples by authorizationStatus(for:) == .sharingAuthorized before calling save([...]), or save water separately.
- **[low]** Apple's delete docs say 'Your app can delete only those objects that it has previously saved to the HealthKit store', and WWDC20 says 'You can't delete data you didn't explicitly save yourself'. I found no primary source on whether the iPhone app can delete a sample saved by its own watchOS app. That sample's HKSource is the watch app bundle, a different bundle id.  
  _src_: https://developer.apple.com/documentation/healthkit/hkhealthstore/delete(_:withcompletion:)-78l1m ; WWDC20 10184; cross-device delete: memory/unverified  
  _implication_: Do not rely on deleting across devices. Record the originating device on each entry. Send undo/delete to the device that wrote the entry (WatchConnectivity), or delete locally when the entry is local. Treat deleteObjects returning 0 or throwing as 'not deletable here' and tell the user to delete it in the Health app.
- **[high]** `func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws` is available on iOS 15.0 / watchOS 8.0 / macOS 13 and takes non-optional sets. The completion form `requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?, completion: @escaping @Sendable (Bool, (any Error)?) -> Void)` is iOS 8 / watchOS 2. Success does NOT mean access was granted. On watchOS 6 and later the permission sheet appears on the Watch itself. Missing usage-description keys crash the app ('You must set the usage keys, or your app will crash').  
  _src_: https://developer.apple.com/documentation/healthkit/hkhealthstore/requestauthorization(toshare:read:) ; HKHealthStore.h (NS_REFINED_FOR_SWIFT_ASYNC)  
  _implication_: Call it from the foreground iOS app and the foreground watch app, each once. After that, check write access with authorizationStatus(for:) -> HKAuthorizationStatus (.sharingAuthorized). Read permission can never be detected.
- **[high]** `func statusForAuthorizationRequest(toShare: Set<HKSampleType>, read: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus` is the async name of getRequestStatusForAuthorization(toShare:read:completion:) (iOS 12 / watchOS 5). `func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus` is iOS 8 / watchOS 2 and applies to sharing (write) only. `class func isHealthDataAvailable() -> Bool` is iOS 8 / watchOS 2.  
  _src_: https://developer.apple.com/documentation/healthkit/hkhealthstore/getrequeststatusforauthorization(toshare:read:completion:) ; /authorizationstatus(for:) ; /ishealthdataavailable()  
  _implication_: Widgets and intents should use these to decide between 'log' and 'open the app to grant access'.
- **[high]** Extensions: an Apple Frameworks Engineer said 'Widgets can get access to health data if the host app has permission. However, it doesn't have the ability to request authorization'. Calling requestAuthorization from a widget gives HealthKit error Code=111 'Unable to prompt for authorization using this type of extension'. An Apple DTS engineer confirmed that a watch widget can access the Health store directly once the main app is authorized. The widget extension also needed its own NSHealth*UsageDescription Info.plist keys.  
  _src_: https://developer.apple.com/forums/thread/653814 (accepted Apple answer); https://developer.apple.com/forums/thread/780673 (DTS answer)  
  _implication_: Authorization is shared from the containing app. Extensions must never call requestAuthorization. They should check the status and fall back to 'open the app'.
- **[medium]** An extension process that uses HKHealthStore needs com.apple.developer.healthkit in its own entitlements. Logs show healthd checking 'containerAppExtensionEntitlements', and the error is 'Missing com.apple.developer.healthkit entitlement' (Code=4). One 2021 forum report says Xcode would not add HealthKit to a watchOS Intents extension. Nobody answered it.  
  _src_: https://developer.apple.com/forums/thread/24892 ; https://developer.apple.com/forums/thread/674148 ; memory  
  _implication_: Give the iOS widget extension and the watch widget extension the HealthKit entitlement plus the usage strings. Also keep a fallback: if the save throws in an extension, append to an App Group pending queue that the app flushes later. This is idempotent thanks to the sync ids.
- **[high]** `handleAuthorizationForExtension() async throws` and the completion form are iOS 9+ only. They are API_UNAVAILABLE(watchos) and NS_EXTENSION_UNAVAILABLE('Not available to extensions'). The host app calls them from UIApplicationDelegate.applicationShouldRequestHealthAuthorization(_:) (iOS 9; no watchOS).  
  _src_: HKHealthStore.h (iOS 18 SDK); https://developer.apple.com/documentation/healthkit/hkhealthstore/handleauthorizationforextension(completion:) ; https://developer.apple.com/documentation/uikit/uiapplicationdelegate/applicationshouldrequesthealthauthorization(_:)  
  _implication_: Widgets cannot trigger this flow anyway (code 111), so leave it out. If you add it, wrap it in #if os(iOS) and put it only in the app target. Shared code that also compiles for watchOS or for extensions will not build.
- **[high]** Where interactive widget intents run: 'By default, the system runs the app intent in the same process as the widget extension'. If openAppWhenRun is true, or the intent conforms to AudioPlaybackIntent, ForegroundContinuableIntent, LiveActivityIntent or PushToTalkTransmissionIntent, it runs in the app's process instead. LiveActivityIntent is iOS 17+ and not on watchOS. Also, 'On a locked device, buttons and toggles are inactive and the system doesn't perform actions unless a person authenticates and unlocks their device.'  
  _src_: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities ; https://developer.apple.com/documentation/appintents/liveactivityintent  
  _implication_: A plain AppIntent button runs in the widget process, so it needs the HealthKit entitlement there. On iOS only, conforming the log intent to LiveActivityIntent under #if os(iOS) runs it in the app process with the app's entitlement. Lock Screen buttons only run after the user unlocks, so HealthKit is readable by then.
- **[high]** While the device is locked, HealthKit reads fail with HKError.Code.errorDatabaseInaccessible (iOS 8 / watchOS 2). Saves still succeed: 'This data is saved into a temporary file, which is merged with HealthKit's data when the user unlocks their device.' An Apple DTS engineer repeated this in May 2026. One regression was reported (iOS 26.4): HKWorkoutBuilder.finishWorkout on a locked device returned nil/nil. That is for workouts only.  
  _src_: https://developer.apple.com/documentation/healthkit/hkerror/code/errordatabaseinaccessible ; https://developer.apple.com/documentation/healthkit/protecting-user-privacy ; https://developer.apple.com/forums/thread/824819  
  _implication_: Siri logging while locked works. Its spoken 'today total' and every widget timeline must come from the app's own App Group JSON store, never from a HealthKit query. Catch .errorDatabaseInaccessible in every read path.
- **[high]** The App Intents authenticationPolicy (`static var authenticationPolicy: IntentAuthenticationPolicy`, iOS 16 / watchOS 9) defaults to .alwaysAllowed, which runs the intent even when the device is locked. The other values are .requiresAuthentication and .requiresLocalDeviceAuthentication.  
  _src_: https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy  
  _implication_: Keep the default so 'Hey Siri, log half a litre of water' works on a locked phone. The HealthKit write is journaled. The App Group file must be readable after first unlock, so do not write it with .completeFileProtection.
- **[high]** iPhone, Apple Watch and visionOS each have their own HealthKit store, and HealthKit syncs them automatically. Old data is purged from the Watch periodically; earliestPermittedSampleDate() gives the limit. An Apple DTS engineer said the Watch keeps HealthKit data for 'about a week'. DTS also said Watch–iPhone sync 'is not real-time, and there is no API that can speed up the pace', and that foregrounding a HealthKit app may trigger a sync. For near-real-time, DTS recommends WatchConnectivity.  
  _src_: https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework ; https://developer.apple.com/forums/thread/732468 ; https://developer.apple.com/forums/thread/774953 ; https://developer.apple.com/forums/thread/823473  
  _implication_: A drink logged on the Watch shows up in the iPhone's HealthKit minutes later, sometimes much later. The app/widget UI totals must sync through WatchConnectivity and the local stores, not through HealthKit. Each HealthKit sample must be written by exactly one device, the one that was tapped.
- **[high]** Entitlements and Info.plist: com.apple.developer.healthkit is a Boolean (true). com.apple.developer.healthkit.access is an array of strings whose only documented value is 'health-records', for clinical records. Xcode's HealthKit capability writes it as an empty array. NSHealthShareUsageDescription (read) and NSHealthUpdateUsageDescription (write) are both required. When you enable HealthKit on an iOS app, Xcode adds 'healthkit' to UIRequiredDeviceCapabilities; that entry is optional and 'isn't used by watchOS apps'.  
  _src_: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit ; /com.apple.developer.healthkit.access ; /information-property-list/nshealthshareusagedescription ; https://developer.apple.com/documentation/healthkit/setting-up-healthkit  
  _implication_: Put healthkit=true on the iOS app, the iOS widget, the watch app and the watch widget. An empty access array or no access key are both valid; never add health-records. Put the usage strings in every target that touches HKHealthStore, and localize them through ru.lproj/InfoPlist.strings.
- **[high]** On Apple's capability tables, free 'Apple Developer' accounts (no paid program) get HealthKit, App Groups, Background modes, Data protection and Keychain sharing on both iOS and watchOS. Siri (the SiriKit entitlement), Push notifications, iCloud (CloudKit, documents, KVS), Associated domains and Time Sensitive Notifications are NOT available to them.  
  _src_: https://developer.apple.com/help/account/reference/supported-capabilities-ios ; https://developer.apple.com/help/account/reference/supported-capabilities-watchos (raw HTML table checked)  
  _implication_: HealthKit + App Groups + App Intents (no com.apple.developer.siri entitlement) will sign on a Personal Team. Never add the Siri capability, iCloud or push.
- **[medium]** Simulator: HealthKit reads and writes work in the iOS Simulator and the watchOS Simulator. Xcode's run-locally signing embeds the entitlements, and without them HealthKit reports the missing-entitlement error. Health sync between a paired iPhone simulator and watch simulator broke in Xcode 14; an Apple engineer said it 'should be fixed in iOS 16.1/watchOS 9.1'. It is still not something to rely on.  
  _src_: https://developer.apple.com/forums/thread/716613 ; memory for the entitlement behaviour  
  _implication_: For tomorrow, test iPhone-sim HealthKit and watch-sim HealthKit separately. Test the Watch-to-iPhone Health sync only on real devices. CI builds with CODE_SIGNING_ALLOWED=NO compile fine; entitlements only matter at runtime.
- **[high]** `struct HKStatisticsQueryDescriptor` has `init(predicate: HKSamplePredicate<HKQuantitySample>, options: HKStatisticsOptions)` and `func result(for healthStore: HKHealthStore) async throws -> HKStatistics?`. `struct HKStatisticsCollectionQueryDescriptor` has `init(predicate:options:anchorDate: Date, intervalComponents: DateComponents)`, `result(for:) async throws -> HKStatisticsCollection` and `results(for:) -> Results` (an AsyncSequence). `struct HKSampleQueryDescriptor<Sample: HKSample>` has `init(predicates: [HKSamplePredicate<Sample>], sortDescriptors: [SortDescriptor<Sample>], limit: Int? = nil)` and `result(for:) async throws -> [Sample]`. `HKSamplePredicate.quantitySample(type: HKQuantityType, predicate: NSPredicate? = nil)`. HKAnchoredObjectQueryDescriptor is also available. ALL of these need iOS 15.4 / watchOS 8.5 / macOS 13.  
  _src_: https://developer.apple.com/documentation/healthkit/hkstatisticsquerydescriptor ; /hkstatisticscollectionquerydescriptor ; /hksamplequerydescriptor ; /hksamplepredicate/quantitysample(type:predicate:)  
  _implication_: This is safe with an iOS 17 / watchOS 10 deployment target and removes all completion-handler code.
- **[high]** The legacy queries are `HKStatisticsQuery(quantityType:quantitySamplePredicate: NSPredicate?, options: HKStatisticsOptions = [], completionHandler: @escaping @Sendable (HKStatisticsQuery, HKStatistics?, (any Error)?) -> Void)` and `HKStatisticsCollectionQuery(quantityType:quantitySamplePredicate:options:anchorDate:intervalComponents:)`. HKStatistics.sumQuantity() -> HKQuantity? is non-nil only with .cumulativeSum. HKStatisticsCollection has statistics(), statistics(for:) and enumerateStatistics(from:to:with: (HKStatistics, UnsafeMutablePointer<ObjCBool>) -> Void). HKError.Code.errorNoData (iOS 14 / watchOS 7) is what 'HKStatisticsQuery queries return' when no data matches.  
  _src_: https://developer.apple.com/documentation/healthkit/hkstatisticsquery/init(quantitytype:quantitysamplepredicate:options:completionhandler:) ; /hkerror/code/errornodata ; /hkstatisticscollection  
  _implication_: Wrap statistics reads so that both a nil result and a thrown .errorNoData become 0. .errorDatabaseInaccessible (locked) means 'use the cached total'.
- **[high]** `earliestAuthorizedSampleDate(for:) async throws -> [HKObjectType: Date]` is new in iOS 27.0 / watchOS 27.0 (limited-history authorization). The docs' authorization article now describes a second 'how much history' screen.  
  _src_: https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestauthorizedsampledate(for:)  
  _implication_: Do NOT use it. CI's Xcode may be 26.x, and the call would not compile. Writes are unaffected by the new feature; reads of older days may be restricted on iOS 27.
- **[high]** `healthDataAccessRequest(store:shareTypes:readTypes:trigger:completion:)` is a SwiftUI modifier that requires importing both SwiftUI and HealthKitUI. It needs iOS 17 / watchOS 10.2.  
  _src_: https://developer.apple.com/documentation/swiftui/view/healthdataaccessrequest(store:sharetypes:readtypes:trigger:completion:) ; https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data  
  _implication_: It is optional. Calling try await store.requestAuthorization from a button or .task is simpler and does not import HealthKitUI, which lowers the compile risk.
- **[high]** Adding a correlation or a limited read window changes nothing for writes. For dietary types, HealthKit hides other sources' data when read permission is denied, and the app still sees its own samples ('If your app is given share permission but not read permission, you see only the data that your app has written').  
  _src_: https://developer.apple.com/documentation/healthkit/hkhealthstore/authorizationstatus(for:)  
  _implication_: If the user denies read, the HealthKit total silently shows only our own entries. That is one more reason to present totals from the local store.

### Snippets

```
// HealthKit type table (iOS 17+/watchOS 10+ targets; HKQuantityType(_:) is iOS 15/watchOS 8)
import HealthKit

enum HKDrinkTypes {
    static let water    = HKQuantityType(.dietaryWater)          // unit: mL
    static let caffeine = HKQuantityType(.dietaryCaffeine)       // unit: mg
    static let energy   = HKQuantityType(.dietaryEnergyConsumed) // unit: kcal
    static let sugar    = HKQuantityType(.dietarySugar)          // unit: g

    static let mL   = HKUnit.literUnit(with: .milli)
    static let mg   = HKUnit.gramUnit(with: .milli)
    static let kcal = HKUnit.kilocalorie()
    static let g    = HKUnit.gram()

    // NEVER put HKCorrelationType(.food) in these sets -> uncatchable NSInvalidArgumentException
    static let share: Set<HKSampleType> = [water, caffeine, energy, sugar]
    static let read:  Set<HKObjectType> = [water, caffeine, energy, sugar]

    static let entryIDKey   = "SayoneEntryID"   // custom metadata keys (String values only)
    static let drinkKindKey = "SayoneDrinkKind"
}
```
```
// Authorization: call ONLY from the foreground app (iOS app and watch app separately). Never from widgets/intents.
final class HealthService {
    let store = HKHealthStore()   // create once, keep it

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        // iOS 15.0 / watchOS 8.0; success != granted
        try await store.requestAuthorization(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)
    }

    func canWrite(_ type: HKQuantityType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // Safe in extensions: tells whether a prompt would still be needed
    func needsPrompt() async -> Bool {
        let s = try? await store.statusForAuthorizationRequest(toShare: HKDrinkTypes.share, read: HKDrinkTypes.read)
        return s == .shouldRequest
    }
}
```
```
// Save one logical drink entry as flat quantity samples, idempotent via sync identifiers.
extension HealthService {
    func save(entryID: UUID, kind: String, displayName: String, date: Date,
              waterML: Double, caffeineMG: Double, kcal: Double, sugarG: Double) async throws {
        func meta(_ suffix: String) -> [String: Any] {
            [HKMetadataKeySyncIdentifier: "\(entryID.uuidString).\(suffix)",   // String, unique per type
             HKMetadataKeySyncVersion: NSNumber(value: 1),                    // NSNumber, REQUIRED with sync id
             HKMetadataKeyFoodType: displayName,                               // e.g. "Кола без сахара"
             HKMetadataKeyWasUserEntered: NSNumber(value: true),
             HKDrinkTypes.entryIDKey: entryID.uuidString,
             HKDrinkTypes.drinkKindKey: kind]
        }
        func sample(_ t: HKQuantityType, _ u: HKUnit, _ v: Double, _ s: String) -> HKQuantitySample {
            HKQuantitySample(type: t, quantity: HKQuantity(unit: u, doubleValue: v),
                             start: date, end: date, metadata: meta(s))
        }
        var objects: [HKObject] = []
        if waterML > 0,    canWrite(HKDrinkTypes.water)    { objects.append(sample(HKDrinkTypes.water, HKDrinkTypes.mL, waterML, "water")) }
        if caffeineMG > 0, canWrite(HKDrinkTypes.caffeine) { objects.append(sample(HKDrinkTypes.caffeine, HKDrinkTypes.mg, caffeineMG, "caffeine")) }
        if kcal > 0,       canWrite(HKDrinkTypes.energy)   { objects.append(sample(HKDrinkTypes.energy, HKDrinkTypes.kcal, kcal, "energy")) }
        if sugarG > 0,     canWrite(HKDrinkTypes.sugar)    { objects.append(sample(HKDrinkTypes.sugar, HKDrinkTypes.g, sugarG, "sugar")) }
        guard !objects.isEmpty else { return }
        try await store.save(objects)   // all-or-nothing; works while locked (journaled until unlock)
    }
}
```
```
// Delete one entry (only samples THIS app/device saved can be deleted)
extension HealthService {
    @discardableResult
    func deleteEntry(_ entryID: UUID) async throws -> Int {
        let p = HKQuery.predicateForObjects(withMetadataKey: HKDrinkTypes.entryIDKey,
                                            allowedValues: [entryID.uuidString])
        var deleted = 0
        for t in [HKDrinkTypes.water, HKDrinkTypes.caffeine, HKDrinkTypes.energy, HKDrinkTypes.sugar]
        where canWrite(t) {
            deleted += try await store.deleteObjects(of: t, predicate: p)   // async throws -> Int
        }
        return deleted   // 0 => probably written by the other device or not synced yet
    }
}
```
```
// Today's total (iOS 15.4 / watchOS 8.5 descriptors). Falls back to 0 on no data; rethrows locked error.
extension HealthService {
    func todayTotal(_ type: HKQuantityType, unit: HKUnit, onlyThisApp: Bool = false) async throws -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        var predicate: NSPredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        if onlyThisApp {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate, HKQuery.predicateForObjects(withMetadataKey: HKDrinkTypes.entryIDKey)])
        }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum)
        do {
            return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit) ?? 0
        } catch let error as HKError where error.code == .errorNoData {
            return 0
        } // HKError.Code.errorDatabaseInaccessible => device locked: caller uses local cache
    }

    func dailyTotals(_ type: HKQuantityType, unit: HKUnit, days: Int) async throws -> [(Date, Double)] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let from = cal.date(byAdding: .day, value: -(days - 1), to: todayStart)!
        let to = cal.date(byAdding: .day, value: 1, to: todayStart)!
        let d = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: from, end: to)),
            options: .cumulativeSum, anchorDate: todayStart, intervalComponents: DateComponents(day: 1))
        let collection = try await d.result(for: store)
        var out: [(Date, Double)] = []
        collection.enumerateStatistics(from: from, to: to) { stats, _ in
            out.append((stats.startDate, stats.sumQuantity()?.doubleValue(for: unit) ?? 0))
        }
        return out
    }
}
```
```
// Recent samples written by this app (iOS 15.4 / watchOS 8.5)
let recent = HKSampleQueryDescriptor(
    predicates: [.quantitySample(type: HKDrinkTypes.water,
                                 predicate: HKQuery.predicateForObjects(withMetadataKey: HKDrinkTypes.entryIDKey))],
    sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
    limit: 50)
// let samples: [HKQuantitySample] = try await recent.result(for: store)
// samples[i].metadata?[HKDrinkTypes.entryIDKey] as? String
```
```
# XcodeGen: entitlements + usage strings for EVERY target that touches HKHealthStore
# (iOS app, iOS widget ext, watch app, watch widget ext)
targets:
  SayoneHealth:
    entitlements:
      path: Config/SayoneHealth.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []        # empty = no clinical records (what Xcode writes)
        com.apple.security.application-groups: [group.com.sayoneone.sayonehealth]
    info:
      path: Config/SayoneHealth-Info.plist
      properties:
        NSHealthShareUsageDescription: "SayoneHealth reads your water and drink history to show daily totals."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log (water, caffeine, energy, sugar) to Apple Health."
# Localize via ru.lproj/InfoPlist.strings:
# "NSHealthShareUsageDescription" = "SayoneHealth читает историю воды и напитков, чтобы показывать дневные итоги.";
# "NSHealthUpdateUsageDescription" = "SayoneHealth сохраняет выпитое (воду, кофеин, калории, сахар) в Здоровье.";
```
```
// iOS-only: run widget button intent in the APP process (uses the app's HealthKit entitlement/authorization)
// LiveActivityIntent: iOS 17+, NOT available on watchOS -> must be guarded.
import AppIntents

struct LogDrinkIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Drink"
    // default authenticationPolicy == .alwaysAllowed -> Siri can log while locked (HK save is journaled)
    @Parameter(title: "Preset") var presetID: String
    init() {}
    init(presetID: String) { self.presetID = presetID }
    func perform() async throws -> some IntentResult {
        // 1) append entry to App Group JSON store (source of truth for UI/widgets/Siri dialog)
        // 2) try HealthService.save(...); on error enqueue for later flush (sync ids make it idempotent)
        return .result()
    }
}
#if os(iOS)
extension LogDrinkIntent: LiveActivityIntent {}
#endif
```

### Recommendations
- Keep HealthKit out of the Linux Swift package. The package holds the pure model: DrinkKind, per-100 mL nutrients, preset volume, entry UUID, originating device and sync version. One thin HealthService file in an Apple-only shared folder (compiled into the app, widget, watch app and watch widget) converts entries to HKQuantitySamples.
- Use flat HKQuantitySamples, not HKCorrelation(.food). Each logical entry becomes one dietaryWater sample in mL, plus optional dietaryCaffeine in mg, dietaryEnergyConsumed in kcal and dietarySugar in g. Coke Zero is roughly 0 kcal, 0 g sugar and about 12 mg caffeine per 100 mL, so check exact values against a label. All samples share the metadata: SyncIdentifier "<uuid>.<type>", SyncVersion NSNumber(1), FoodType = localized drink name, WasUserEntered = true, SayoneEntryID = uuid string, SayoneDrinkKind = kind.
- Only the device that was tapped writes an entry to HealthKit. Cross-device UI totals come from the local stores synced over WatchConnectivity, because HealthKit sync between Watch and iPhone is not real-time. A re-save with the same sync id and version is ignored, which makes retries and pending-queue flushes safe.
- The source of truth for everything displayed (widgets, Siri dialog, complication, lock-state paths) is the App Group JSON store on each device. HealthKit is write-mostly. Read it only optionally, in the foreground app, for an 'all sources' total, and treat .errorDatabaseInaccessible and .errorNoData as 'use cache / 0'.
- Before a multi-sample save, filter the samples by authorizationStatus(for:) == .sharingAuthorized. save([...]) is all-or-nothing, so a denied caffeine permission would otherwise drop the water sample too.
- Request authorization only from the foreground iOS app and, separately, the foreground watch app (for example on first launch or from a 'Connect Apple Health' button). Widgets and intents never call requestAuthorization. When writing is not possible, they queue the entry and return a dialog such as 'Откройте приложение, чтобы разрешить доступ к Здоровью'.
- On iOS, the interactive widget and Control buttons run LogDrinkIntent in the app process, either by conforming it to LiveActivityIntent under #if os(iOS) or by putting the intent only in the app target and using the Siri/App Shortcuts path. Even so, give the iOS widget extension the HealthKit entitlement and usage strings as a fallback. On watchOS there is no LiveActivityIntent, so the watch widget extension needs the HealthKit entitlement plus a pending-queue fallback that the watch app flushes.
- Undo/delete: delete locally with deleteObjects(of:predicate: SayoneEntryID == id) only when entry.originDevice == this device. Otherwise send a delete request over WatchConnectivity. If deleteObjects returns 0, keep a 'pendingHealthDelete' flag and retry when the app is foregrounded. For edits, re-save with the same sync id and version + 1 instead of deleting.
- Entitlements for all four targets: com.apple.developer.healthkit = true, plus an empty com.apple.developer.healthkit.access array or no key (never 'health-records'), plus the App Group. Never add com.apple.developer.siri, iCloud, push or associated domains, because a free Personal Team cannot sign them (verified in Apple's capability tables). App Intents/App Shortcuts do not need the SiriKit entitlement.
- Compile-safety rules for CI: guard handleAuthorizationForExtension, UIApplicationDelegate and LiveActivityIntent with #if os(iOS), or better, drop handleAuthorizationForExtension entirely. Do not use iOS 27 APIs (earliestAuthorizedSampleDate) or HealthKitUI's healthDataAccessRequest. Declare type sets explicitly as Set<HKSampleType> / Set<HKObjectType>. Use the descriptor APIs, which need iOS 15.4 / watchOS 8.5, with deployment targets of iOS 17 / watchOS 10 or higher. Catch HKError with `catch let e as HKError where e.code == .errorNoData`.
- Testing tomorrow: in the iOS Simulator, run from Xcode with automatic signing, which embeds the entitlements, and check samples in the simulator's Health app. The watch simulator's HealthKit works on its own. Do not expect Health data to sync between the iPhone sim and the watch sim; verify Watch-to-iPhone sync on real devices and allow minutes for it. Test locked-iPhone Siri logging on the device: the entry appears in Health after unlock.

### Open risks
- Not verified: can the iPhone app delete (or replace via sync id) a sample that its own watchOS app saved? The sources differ by bundle id. The design routes deletes to the originating device so it does not depend on the answer.
- Not verified: whether HealthKit scopes sync-identifier matching per source or per sample type. The design uses per-type sync ids, and only one device writes each entry.
- Signing a HealthKit entitlement on a watchOS widget extension with a free Personal Team has not been checked on a device. A 2021 forum report said Xcode refused HealthKit on a watch Intents extension. The fallback is the pending queue in the watch App Group, flushed by the watch app.
- Not documented: whether a re-save with an equal sync version returns success or an error. Handle both as 'already saved'.
- The LiveActivityIntent trick for running widget intents in the app process is a documented behaviour, but using it for a non-Live-Activity action is unconventional. It is irrelevant for a personal/dev build, but App Review could question it later.
- iOS 27 limited-history authorization may restrict HealthKit reads of older days if the user picks a short window. Writes and the local-store totals are unaffected.
- Free provisioning limits, from memory and not re-verified: profiles expire after 7 days, and there are caps on App IDs per week and on installed apps per device. The four targets need four App IDs (iOS app, iOS widget, watch app, watch widget), which should fit.
- Reported regression: in iOS 26.4, HKWorkoutBuilder saves on a locked device fail silently. It concerns workouts only, but test a plain HKQuantitySample save on the locked device via Siri tomorrow.
- The Info.plist usage strings are required in widget extensions, going by forum evidence (a 2020 WidgetKit report). Add them to every HealthKit-touching target to be safe.

## App Intents, Siri and App Shortcuts for SayoneHealth (iOS + watchOS): verified API facts, availability, localization (en and ru), target placement and metadata extraction

- **[high]** `protocol AppShortcutsProvider : Sendable` is available on iOS 16.0, iPadOS 16.0, Mac Catalyst 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0 and visionOS. Its requirement is `@AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }`. It also has `static var shortcutTileColor: ShortcutTileColor { get }` (iOS 16 / watchOS 9), `static func updateAppShortcutParameters()` (iOS 16 / watchOS 9) and `static var negativePhrases: NegativeAppShortcutPhrases { get }` (iOS 17 / watchOS 10).  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appshortcutsprovider.json (and the /appshortcuts, /updateappshortcutparameters(), /shortcuttilecolor, /negativephrases pages)  
  _implication_: The provider can be compiled into both the iOS app and the watch app. Implement `updateAppShortcutParameters()` nowhere: the framework provides it. Call it in `App.init()` and again whenever the presets change.
- **[high]** `AppShortcut` has three initializers. (1) `init<Intent>(intent: Intent, phrases: [AppShortcutPhrase<Intent>], shortTitle: LocalizedStringResource, systemImageName: String) where Intent : AppIntent` is iOS 17.0 / watchOS 10.0 / macOS 14.0. (2) The same signature with `parameterPresentation: AppShortcutParameterPresentation<...>` is iOS 17 / watchOS 10. (3) A variant with `shortTitle: LocalizedStringResource? = nil, systemImageName: String? = nil` is marked iOS 16 / watchOS 9. WWDC23 says 'every app shortcut now requires a short title and system image'.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appshortcut.json ; WWDC23 session 10102 transcript  
  _implication_: Always pass `shortTitle:` and `systemImageName:`. Set deployment targets to iOS 17+ and watchOS 10+ or higher so that the non-optional overload resolves.
- **[high]** Every phrase must contain `\(.applicationName)` (`AppShortcutPhraseToken.applicationName`), which in string catalogs is written as `${applicationName}`. The token matches the app's display name and any INAlternativeAppNames synonyms. Build-time validation fails with the message "Invalid Utterance. Every App Shortcut utterance should have '${applicationName}' in it". A community lint also requires the token to appear exactly once per phrase.  
  _src_: WWDC22 10170 and WWDC23 10102 transcripts; https://sowenjub.me/writes/localizing-app-shortcuts-with-app-intents/ ; Apple sample TrailShortcuts.swift  
  _implication_: Every English phrase in Swift and every Russian phrase in the catalog must contain exactly one `${applicationName}`. Add a CI lint that parses AppShortcuts.xcstrings and checks this.
- **[high]** Limits: an app can have at most 10 App Shortcuts. appintentsmetadataprocessor enforces this at build time with "error: Found N App Shortcuts, but each app may have at most 10". Each app can have at most 1,000 trigger phrases, counting every parameter-value expansion. DTS clarified (Dec 2025) that the 1,000 limit applies per locale, not across all locales.  
  _src_: WWDC22 10170 ('maximum of 10 app shortcuts'); WWDC23 10102 ('at most 1,000 trigger phrases'); https://developer.apple.com/forums/thread/807411 (Ed Ford, DTS); github.com/xoloUno/claude-code-ios-playbook packs/ios/rules/app-intents.md (error text)  
  _implication_: Keep about 4 to 6 AppShortcut entries. This is a build-time error, not a Swift compile error, so it only appears in the full xcodebuild log.
- **[high]** A parameter in a phrase must be an AppEnum or an AppEntity. Open-ended values (String, Int, Double, Measurement) are not supported. A phrase can have only one dynamic parameter. DTS: an Int parameter in a phrase makes the App Shortcuts not appear at all, and the log says 'couldn't find the AppShortcutsProvider'.  
  _src_: WWDC23 10102 ('parameters that are App Enums ... or App Entities'); WWDC22 10169 ('only have one dynamic parameter in your phrase'); https://developer.apple.com/forums/thread/771507 (Ed Ford, DTS)  
  _implication_: Do not put `\(\.$amountMl)` or a `Measurement<UnitVolume>` in a phrase. Put a DrinkKind AppEnum or a DrinkPreset AppEntity in phrases. Siri asks for the amount in a follow-up prompt, or it comes from the preset.
- **[high]** For an AppEntity parameter in a phrase, the values come from the query's `suggestedEntities()`. WWDC22 says that without it there are no parameterized shortcuts. `updateAppShortcutParameters()` makes the framework query again. Signatures: `func entities(for identifiers: [Self.Entity.ID]) async throws -> [Self.Entity]`, `func suggestedEntities() async throws -> Self.Result`, and for `EntityStringQuery : EntityQuery`, `func entities(matching string: String) async throws -> Self.Result`. All are iOS 16 / watchOS 9.  
  _src_: WWDC22 10170 transcript; https://developer.apple.com/tutorials/data/documentation/appintents/entityquery.json ; .../entitystringquery.json  
  _implication_: The presets query must read presets from the App Group store synchronously in both the app and the watch app. Call `SayoneShortcuts.updateAppShortcutParameters()` after every preset edit.
- **[high]** The Xcode 16+ metadata processor requires globally unique type names for entity query types. Two nested types both named `Query` produce "Found multiple, identical identifiers for query: Query". The processor also needs `typeDisplayRepresentation` to directly instantiate `TypeDisplayRepresentation(...)`. With `.init(name:)` you get a WARNING: "At least one halting error produced during export. No AppIntents metadata have been exported". The build still succeeds, but Siri and Shortcuts see nothing.  
  _src_: https://marcpalmer.net/changes-in-app-intents-pre-processing-causing-confusing-errors-in-xcode-16/ ; https://developer.apple.com/forums/thread/727811  
  _implication_: Name queries uniquely, for example `DrinkPresetQuery`. Write `TypeDisplayRepresentation(name: ...)` explicitly. In CI, grep the xcodebuild log for 'appintentsmetadataprocessor' warnings and 'No AppIntents metadata have been exported' and fail the job if they appear.
- **[high]** Localizing phrases: DTS (2025) says string catalogs are the supported technique and the older .strings form isn't supported for App Shortcut phrases. The file must be named exactly `AppShortcuts.xcstrings`. Format, verified in Apple's sample and ProtonVPN: each key is the FIRST English phrase of an AppShortcut, with `${applicationName}` and `${<parameterPropertyName>}` (for example `\(\.$drink)` becomes `${drink}`). Each locale holds `"stringSet": {"state": "translated", "values": [ ...all phrases for that locale... ]}`. Catalog `version` "1.0" works. A locale may list a different number of phrases (iOS 17+ string catalogs lifted the 1:1 limit).  
  _src_: https://developer.apple.com/forums/thread/775638 (Ed Ford, DTS); https://developer.apple.com/forums/thread/768900 (Ed Ford, DTS); WWDC23 10102; Apple sample AcceleratingAppInteractionsWithAppIntents/AppShortcuts.xcstrings; github.com/ProtonVPN/ios-mac-app apps/ios/ProtonVPN/Resources/AppShortcuts.xcstrings  
  _implication_: Hand-write AppShortcuts.xcstrings with `sourceLanguage` "en", an `en` stringSet and a `ru` stringSet per shortcut. Put it in the resources of the SAME targets as the AppShortcutsProvider (iOS app and watch app), never in widget extensions. Intent titles, shortTitle and dialogs go in a separate Localizable.xcstrings (the default table).
- **[medium]** Russian: no Apple document lists which Siri languages App Shortcuts support. Siri supports Russian, and shipping apps (ProtonVPN, openHAB, sing-box, MeshCoreOne) include `ru` stringSets in AppShortcuts.xcstrings. An unanswered forum post (thread 737272) reports App Shortcuts misbehaving with Russian Siri. Community evidence (a PR on a third-party app) shows that when a locale has no localized phrases, the ENGLISH phrases end up in Siri's model for that language. Phrase selection follows the system and Siri language, not any in-app language switcher.  
  _src_: github.com/ProtonVPN/ios-mac-app, openhab/openhab-ios, SagerNet/sing-box-for-apple AppShortcuts.xcstrings (ru entries); https://developer.apple.com/forums/thread/737272 ; github.com/cli-pulse/cli-pulse-private/pull/567  
  _implication_: Ship real Russian phrases, not literal translations, and several variants covering gender (выпил / выпила) and case (воду / воды). If the user's Siri is English, the English phrases apply. Test on the device with Siri set to Russian and again with Siri set to English.
- **[high]** Flexible matching (on-device semantic similarity, iOS 17+) is controlled by the build setting `APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING`. WWDC23: 'Flexible matching with Siri is not available on Apple Watch, so phrases must be spoken exactly.' App Shortcuts Preview (Product > App Shortcuts Preview) needs Xcode on macOS.  
  _src_: Xcode build settings reference JSON (APP_SHORTCUTS_ENABLE_FLEXIBLE_MATCHING); WWDC23 10102 transcript  
  _implication_: On the watch the user must say an exact phrase, so keep the phrases short and natural and include the most likely Russian forms literally. The agent cannot run App Shortcuts Preview (no Mac), so the phrases can only be validated on a device.
- **[medium]** `@Parameter` for Measurement<UnitVolume> exists. For example: `convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, defaultValue: Double? = nil, defaultUnit: IntentParameter<Value>.Volume? = nil, defaultUnitAdjustForLocale: Bool = false, supportsNegativeNumbers: Bool = true, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default)` where `Value.ValueType == Measurement<UnitVolume>`, iOS 16 / watchOS 9. `IntentParameter.Volume` has cases such as `.milliliters`, `.liters` and `.fluidOunces`. No Apple doc says how Siri parses 'half a litre' or 'пол-литра'.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/intentparameter-measurements-volume.json and the linked init pages  
  _implication_: A Measurement parameter compiles but its Siri voice parsing is untested, and in Russian especially. The safer primary design is an Int millilitre parameter with a range, plus presets. If you use a Measurement parameter, note that the label is `defaultValue:` (a Double), not `default:`.
- **[high]** `@Parameter` for Int: `convenience init(title: LocalizedStringResource, description: LocalizedStringResource? = nil, default defaultValue: Value.UnwrappedType? = nil, controlStyle: IntentParameter<Value>.IntControlStyle = .stepper, inclusiveRange: IntentParameter<Value>.InclusiveRange<Value.ValueType>? = nil, requestValueDialog: IntentDialog? = nil, inputConnectionBehavior: InputConnectionBehavior = .default)` where `Value.ValueType == Int`, iOS 16 / watchOS 9. `typealias InclusiveRange<Bound> = (lowerBound: Bound, upperBound: Bound)`. `IntControlStyle` has `.field` and `.stepper`.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/intentparameter-int.json and the -2wjbq init page  
  _implication_: Use `@Parameter(title: "Amount (ml)", default: 250, inclusiveRange: (1, 5000)) var amountMl: Int`. The label is `default:`.
- **[high]** `@Parameter` for AppEnum: `convenience init(title:description:default:requestValueDialog:requestDisambiguationDialog:inputConnectionBehavior:supportedValues:)`, iOS 16 / watchOS 9, with `supportedValues` defaulting to `Array(Value.ValueType.allCases)`. For AppEntity, `init(title:description:default:requestValueDialog:requestDisambiguationDialog:inputConnectionBehavior:)` is iOS 18 / watchOS 11, and the iOS 16 variant is deprecated at iOS 18 (warning only). `func requestValue(_ dialog: IntentDialog? = nil) async throws -> Value.ValueType` and `func needsValueError(_ dialog: IntentDialog? = nil) -> AppIntentError` are iOS 16 / watchOS 9. `static var parameterSummary: Self.SummaryContent { get }` is written as `static var parameterSummary: some ParameterSummary { Summary("...\(\.$x)...") }`.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/intentparameter-app-enum.json ; intentparameter-app-entity.json ; requestvalue(_:)-592nd ; needsvalueerror(_:)  
  _implication_: The plain `@Parameter(title: "Drink", default: .water)` works. Deprecation warnings are not errors in Swift 5 mode, as long as warnings are not treated as errors.
- **[high]** `protocol AppEnum : AppValue, StaticDisplayRepresentable, RawRepresentable where Self.RawValue : LosslessStringConvertible`. It requires `static var typeDisplayRepresentation: TypeDisplayRepresentation { get }` and `static var caseDisplayRepresentations: [Self : DisplayRepresentation] { get }`. `DisplayRepresentation(title:subtitle:image:synonyms:)` is iOS 17 / watchOS 10, and `synonyms` is `[LocalizedStringResource]`. `TypeDisplayRepresentation(name:numericFormat:synonyms:)` is iOS 17 / watchOS 10. `DisplayRepresentation.Image(systemName:isTemplate:)` is iOS 16 / watchOS 9. Apple warns: don't adopt AppEntity and AppEnum in the same type.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appenum.json ; displayrepresentation.json ; typedisplayrepresentation.json ; displayrepresentation/image-swift.struct.json  
  _implication_: Use `static let caseDisplayRepresentations: [DrinkKind: DisplayRepresentation] = [...]` (Apple's sample uses static let). Russian synonyms such as 'воду', 'воды' and 'колу' help matching on iPhone. On the watch, matching is exact, so the case title itself must fit the phrase.
- **[high]** AppIntent basics: `static var title: LocalizedStringResource { get }`, `static var description: IntentDescription? { get }`, `func perform() async throws -> Self.PerformResult`. `IntentDescription(_:categoryName:searchKeywords:)` is iOS 16 / watchOS 9. `IntentDialog` conforms to ExpressibleByStringLiteral and ExpressibleByStringInterpolation. Its initializers are `init(_ string: LocalizedStringResource)`, `init(full:supporting:)` and others. Result factories: `static func result(dialog: IntentDialog)`, `result<Value>(value: Value, dialog: IntentDialog)` and `result<Content: View>(dialog: IntentDialog, view: Content = EmptyView())`. The return types are composed as `some IntentResult & ProvidesDialog`, `some ReturnsValue<Int> & ProvidesDialog` or `... & ShowsSnippetView`. All of these are iOS 16 / watchOS 9.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appintent.json ; intentresult.json ; intentdialog.json ; providesdialog.json ; returnsvalue.json ; showssnippetview.json  
  _implication_: The logging intent should return `some IntentResult & ProvidesDialog` with a spoken confirmation. Snippet views are optional, and Apple notes Siri AI may not display them or the dialog.
- **[high]** The foreground and background API changed in the iOS 26 SDK. `static var openAppWhenRun: Bool` is deprecated at iOS 26.0 / watchOS 26.0 ('Please provide supportedModes instead'). This is a warning, and setting it to true errors if the intent runs in an app extension. `static var supportedModes: IntentModes` is iOS 26.0 / watchOS 26.0 (values `.background`, `.foreground(.immediate/.dynamic/.deferred)`). `ForegroundContinuableIntent` is deprecated at 26. `continueInForeground(_:alwaysConfirm:)` and `needsToContinueInForegroundError(_:alwaysConfirm:)` are iOS 26 / watchOS 26. If you declare neither property, the intent runs without bringing the app forward.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appintent/openappwhenrun.json (deprecatedAt 26.0); .../supportedmodes.json; .../foregroundcontinuableintent.json  
  _implication_: For 'log a drink', do not declare openAppWhenRun or supportedModes, so it runs in the background with no UI. If the deployment target is below 26, any use of supportedModes needs `@available` guards, so avoid it.
- **[high]** `static var authenticationPolicy: IntentAuthenticationPolicy` defaults to `.alwaysAllowed`, which lets the intent run while the device is locked. Other values are `.requiresAuthentication` and `.requiresLocalDeviceAuthentication`. HealthKit docs: when the device is locked the HealthKit store is encrypted and reads may fail, but 'your app can still write to the store, even when the phone is locked. HealthKit temporarily caches the data'.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appintent/authenticationpolicy.json ; https://developer.apple.com/tutorials/data/documentation/healthkit/protecting-user-privacy.json  
  _implication_: Siri can log a drink on a locked iPhone. HealthKit can store the sample, but today's total must be read from the local App Group store, not from HealthKit. Health permission must be granted beforehand inside the app, because the background intent cannot show the permission prompt.
- **[high]** No Siri entitlement is needed. DTS says Apple's App Intents sample 'does not add the Siri capability or privacy description strings, as they aren't needed with App Intents (they are needed for SiriKit intents)'. The sample's iOS .entitlements file is an empty dict. The watch app has only com.apple.developer.healthkit.  
  _src_: https://developer.apple.com/forums/thread/775638 (Ed Ford, DTS); Apple sample AppIntentsSampleApp.entitlements  
  _implication_: Do not add com.apple.developer.siri or NSSiriUsageDescription. App Intents and App Shortcuts should therefore work with a free Personal Team, since the only restricted capabilities involved are HealthKit and App Groups.
- **[high]** watchOS: App Shortcuts on Apple Watch must come from a watchOS app installed on the watch. Shortcuts from the paired iPhone app cannot run on the watch. Support started in watchOS 9.2. The watchOS Shortcuts app lists App Shortcuts. Apple's sample compiles the SAME AppShortcutsProvider file (TrailShortcuts.swift), the same intents, AppShortcuts.xcstrings and Localizable.xcstrings into BOTH the iOS app and the watch app targets.  
  _src_: WWDC23 10102 transcript; Apple sample AppIntentsSampleApp.xcodeproj/project.pbxproj (target membership)  
  _implication_: Add the provider, intents and both catalogs to the watch app target, and call `updateAppShortcutParameters()` in the watch app's `App.init()`. Siri on the watch runs the intent in the watch app process, so the watch app writes to HealthKit itself (its entitlements must include HealthKit).
- **[high]** `SiriTipView` is `@MainActor struct`, with `nonisolated init<Intent>(intent: Intent, isVisible: Binding<Bool>? = nil) where Intent : AppIntent`. It is available on iOS 16, iPadOS 16, tvOS 16, watchOS 9 and visionOS, but NOT macOS. `View.siriTipViewStyle(_:)` has the same availability, with styles `.automatic`, `.dark` and `.light`. The view is empty if the intent isn't used in an AppShortcut. `ShortcutsLink` has `@MainActor init(action: @escaping () -> Void = {})` and `View.shortcutsLinkStyle(_:)`. It is available on iOS 16, iPadOS 16, Mac Catalyst 16 and visionOS only, NOT watchOS.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/siritipview.json ; shortcutslink.json ; swiftui/view/siritipviewstyle(_:) ; swiftui/view/shortcutslinkstyle(_:)  
  _implication_: Wrap ShortcutsLink in `#if os(iOS)`. Apple's sample wraps both views in `#if os(iOS) || os(visionOS)`. Using ShortcutsLink in shared SwiftUI code compiled for watchOS is a compile error.
- **[medium]** INAlternativeAppNames is a top-level Info.plist array of dicts with `INAlternativeAppName` (required) and `INAlternativeAppNamePronunciationHint` (optional). The limit is 3 dicts per localization. To localize, set variable names as values and define them in each `InfoPlist.strings`; the base localization is required. A watch app does not inherit the iOS synonyms, so it must declare identical ones. Apple's App Intents sample says the `applicationName` placeholder covers 'any app name synonyms you declare in the INAlternativeAppNames key', and ships the key in both the iOS and watch Info.plist.  
  _src_: https://developer.apple.com/tutorials/data/documentation/sirikit/specifying-synonyms-for-your-app-name.json ; Apple sample TrailShortcuts.swift comments, Resources/Info.plist, AppIntentsSample-Watch-App-Info.plist ; QA1950  
  _implication_: 'SayoneHealth' is a Latin-script name that Russian Siri may transcribe badly. Add Cyrillic synonyms through InfoPlist.strings, for example 'Сейон' or 'Сэйон Хелс', and optionally a localized CFBundleDisplayName. Confidence is medium because the older SiriKit page says synonyms need an Intents extension; the newer App Intents sample contradicts that.
- **[high]** Placement: DTS says 'AppShortcutsProvider needs to be in the main app target, and the app intents declared by this provider also need to be in the same target'. If they are not, the build fails with "The action X referenced in App Shortcut does not exist" (catalog) or "This AppShortcut does not map to a known action" (.strings). Putting the provider in an extension gives the runtime error "Couldn't find AppShortcutsProvider". An intent that merely also appears in a widget extension is fine: 'include the source file in multiple targets, like a main app target and an app extension target'.  
  _src_: https://developer.apple.com/forums/thread/759160 (Ed Ford, DTS); https://developer.apple.com/forums/thread/768900 (Ed Ford, DTS); https://developer.apple.com/forums/thread/710552  
  _implication_: Keep intents, entities and enums as source files in the app targets. Compile shared intent files into the iOS app, the iOS widget extension, the watch app and the watch widget extension. Compile the AppShortcutsProvider and AppShortcuts.xcstrings only into the iOS app and watch app. Never put intents in the Linux-buildable Swift package (AppIntents doesn't exist on Linux, and statically linked package intents can be dropped from archives).
- **[medium]** Each target that compiles App Intents gets its own `Metadata.appintents/extract.actionsdata`, which is JSON at the root of an iOS or watchOS .app. It has top-level keys `actions` (keyed by intent type name) and `autoShortcuts` (items with `actionIdentifier`, `shortTitle.key`, `systemImageName` and phrase templates). `AppIntentsPackage` is only needed to share AppEntity types across module boundaries. A developer report (not confirmed with Apple) says that with Xcode 26 it can create duplicate metadata.  
  _src_: github.com/fastrepl/anarlog apps/mobile/scripts/verify-ios-shortcuts.mjs ; github.com/Rheosoph/flow-like apps/desktop/scripts/verify-apple-intents.py ; github.com/as19git67/fk-encore/pull/1271 ; forum thread 759160 (search-result excerpt)  
  _implication_: CI can check the built .app without a device: extract.actionsdata exists, `autoShortcuts` has the expected actionIdentifiers, and the widget bundles have `actions` but no autoShortcuts. Do not declare AppIntentsPackage.
- **[high]** `allowedExecutionTargets` / `IntentExecutionTargets` (`.main`, `.appIntentsExtension`, `.widgetKitExtension`, `.default`) are iOS 27.0 / watchOS 27.0. Apple's documentation now shows iOS 27.x APIs, so the newest SDK may be 27, while CI may still have Xcode 26.  
  _src_: https://developer.apple.com/tutorials/data/documentation/appintents/appintent/allowedexecutiontargets.json ; intentexecutiontargets.json ; Updates/AppIntents (June 2026)  
  _implication_: Do not use iOS 26 or 27-only App Intents APIs unless you guard them. Target API levels that compile with both Xcode 26 and Xcode 27 SDKs.
- **[medium]** Build settings: `SWIFT_ENABLE_EMIT_CONST_VALUES` ('Emit the extracted compile-time known values', -emit-const-values) feeds App Intents metadata extraction. A developer found that `SWIFT_REFLECTION_METADATA_LEVEL = none` broke App Shortcuts, which then showed 'internal error'. `SWIFT_DEFAULT_ACTOR_ISOLATION` and `SWIFT_APPROACHABLE_CONCURRENCY` exist in Xcode 26. `BUILD_ONLY_KNOWN_LOCALIZATIONS` builds only knownRegions when enabled.  
  _src_: Xcode build settings reference JSON; https://developer.apple.com/forums/thread/775428  
  _implication_: In XcodeGen, leave SWIFT_ENABLE_EMIT_CONST_VALUES and SWIFT_REFLECTION_METADATA_LEVEL at their defaults. Do not set SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor. Make sure 'ru' is in knownRegions, for example by adding a ru.lproj/InfoPlist.strings file that XcodeGen will detect.
- **[low]** Reported: App Shortcut dispatch from Spotlight or the Shortcuts app can fail on the iOS 26.5 simulator ('Unable to run app shortcut') even for builds that work on a device. Metadata extraction is still verifiable offline.  
  _src_: github.com/xoloUno/claude-code-ios-playbook packs/ios/rules/app-intents.md  
  _implication_: Tomorrow's test plan: test Siri and App Shortcuts on the real iPhone and Watch, and use the simulator only for UI and Shortcuts-app listing.

### Snippets

```
// DrinkKind.swift  (compile into: iOS app, iOS widget ext, watch app, watch widget ext)
import AppIntents

enum DrinkKind: String, AppEnum, CaseIterable, Codable, Sendable {
    case water, colaZero, other

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Drink")          // direct instantiation, NOT .init(...)
    }
    static let caseDisplayRepresentations: [DrinkKind: DisplayRepresentation] = [
        .water:    DisplayRepresentation(title: "Water",    subtitle: nil,
                                         image: DisplayRepresentation.Image(systemName: "drop.fill"),
                                         synonyms: ["Still water"]),                 // iOS 17 / watchOS 10
        .colaZero: DisplayRepresentation(title: "Coke Zero", subtitle: nil,
                                         image: DisplayRepresentation.Image(systemName: "takeoutbag.and.cup.and.straw.fill"),
                                         synonyms: ["Cola Zero", "Diet cola"]),
        .other:    DisplayRepresentation(title: "Other drink", subtitle: nil,
                                         image: DisplayRepresentation.Image(systemName: "cup.and.saucer.fill"),
                                         synonyms: [])
    ]
}
// Localizable.xcstrings: add ru for "Drink", "Water" ("Вода"), "Coke Zero" ("Кола без сахара"), and synonyms ("воду", "воды", "колу", "колы").
```
```
// LogDrinkIntent.swift  (iOS app + watch app + both widget exts)
import AppIntents

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Drink"
    static let description = IntentDescription("Logs a drink to Apple Health.")   // same form as Apple's sample
    // No openAppWhenRun / supportedModes -> runs in background (openAppWhenRun deprecated in 26; supportedModes is iOS/watchOS 26+)

    @Parameter(title: "Drink", default: .water)
    var drink: DrinkKind

    @Parameter(title: "Amount (ml)", default: 250, inclusiveRange: (1, 5000),
               requestValueDialog: IntentDialog("How many millilitres?"))
    var amountMl: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amountMl) ml of \(\.$drink)")
    }

    init() {}
    init(drink: DrinkKind, amountMl: Int) { self.drink = drink; self.amountMl = amountMl }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message: String = try await DrinkLogger.shared.log(drink: drink, ml: amountMl) // returns an already-localized String
        return .result(dialog: "\(message)")   // key "%@" is not in the table -> shows message
    }
}
```
```
// DrinkPresetEntity.swift  (iOS app + watch app + widget exts) - dynamic presets usable in phrases
import AppIntents

struct DrinkPresetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { TypeDisplayRepresentation(name: "Preset") }
    static let defaultQuery = DrinkPresetQuery()            // globally unique type name (Xcode 16+ rule)

    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct DrinkPresetQuery: EntityStringQuery {
    func entities(for identifiers: [DrinkPresetEntity.ID]) async throws -> [DrinkPresetEntity] {
        PresetStore.shared.all().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [DrinkPresetEntity] {   // REQUIRED for parameterized phrases
        PresetStore.shared.all()
    }
    func entities(matching string: String) async throws -> [DrinkPresetEntity] {
        PresetStore.shared.all().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
}

struct LogPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Preset"
    @Parameter(title: "Preset") var preset: DrinkPresetEntity
    init() {}
    init(preset: DrinkPresetEntity) { self.preset = preset }   // used by widget Button(intent:)
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = try await DrinkLogger.shared.log(presetID: preset.id)
        return .result(dialog: "\(message)")
    }
}
```
```
// SayoneShortcuts.swift  (iOS app target + watch app target ONLY; never widget extensions)
import AppIntents

struct SayoneShortcuts: AppShortcutsProvider {
    static let shortcutTileColor = ShortcutTileColor.blue

    static var appShortcuts: [AppShortcut] {           // max 10 entries; builder has no for-loops
        AppShortcut(intent: LogWaterIntent(), phrases: [  // dedicated intent types beat pre-filled parameters
            "Log water in \(.applicationName)",
            "I drank water with \(.applicationName)"
        ], shortTitle: "Log Water", systemImageName: "drop.fill")

        AppShortcut(intent: LogDrinkIntent(), phrases: [
            "Log \(\.$drink) in \(.applicationName)",    // AppEnum param: OK (ONE param per phrase)
            "Log a drink in \(.applicationName)"
        ], shortTitle: "Log Drink", systemImageName: "cup.and.saucer.fill")

        AppShortcut(intent: LogPresetIntent(), phrases: [
            "Log \(\.$preset) with \(.applicationName)"   // AppEntity param: OK; values from suggestedEntities()
        ], shortTitle: "Log Preset", systemImageName: "star.fill")
    }
}
// Never write \(\.$amountMl) (Int) or a Measurement param in a phrase.
// In App.init(): SayoneShortcuts.updateAppShortcutParameters(); call it again after presets change.
```
```
// AppShortcuts.xcstrings (key = FIRST English phrase of each AppShortcut; tokens ${applicationName}, ${drink}, ${preset})
{
  "sourceLanguage" : "en",
  "strings" : {
    "Log water in ${applicationName}" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringSet" : { "state" : "translated", "values" : [
          "Log water in ${applicationName}", "I drank water with ${applicationName}" ] } },
        "ru" : { "stringSet" : { "state" : "translated", "values" : [
          "Запиши воду в ${applicationName}", "Добавь воду в ${applicationName}",
          "Выпил воды в ${applicationName}", "Выпила воды в ${applicationName}", "${applicationName} вода" ] } }
      }
    },
    "Log ${drink} in ${applicationName}" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringSet" : { "state" : "translated", "values" : [
          "Log ${drink} in ${applicationName}", "Log a drink in ${applicationName}" ] } },
        "ru" : { "stringSet" : { "state" : "translated", "values" : [
          "Запиши напиток ${drink} в ${applicationName}", "${applicationName} ${drink}", "Запиши напиток в ${applicationName}" ] } }
      }
    }
  },
  "version" : "1.0"
}
```
```
<!-- Info.plist of BOTH the iOS app and the watch app (watch does not inherit), max 3 per localization -->
<key>INAlternativeAppNames</key>
<array>
  <dict>
    <key>INAlternativeAppName</key><string>APP_NAME_SYNONYM_1</string>
    <key>INAlternativeAppNamePronunciationHint</key><string>APP_NAME_SYNONYM_1_HINT</string>
  </dict>
</array>
<!-- en.lproj/InfoPlist.strings:  "APP_NAME_SYNONYM_1" = "Sayone"; "APP_NAME_SYNONYM_1_HINT" = "say own";
     ru.lproj/InfoPlist.strings:  "APP_NAME_SYNONYM_1" = "Сейон";  "APP_NAME_SYNONYM_1_HINT" = "сэйон";
     (a ru.lproj folder also helps XcodeGen add 'ru' to knownRegions) -->
```
```
// SwiftUI discoverability
import AppIntents
import SwiftUI

struct SiriHelpSection: View {
    @State private var showTip = true
    var body: some View {
        VStack {
            SiriTipView(intent: LogWaterIntent(), isVisible: $showTip)   // iOS 16 / watchOS 9; intent must be in an AppShortcut
                .siriTipViewStyle(.automatic)
            #if os(iOS)
            ShortcutsLink()                                               // iOS/iPadOS/Catalyst/visionOS only - NOT watchOS
                .shortcutsLinkStyle(.automatic)
            #endif
        }
    }
}
```
```
# CI post-build check (GitHub Actions, macOS runner) - catch silent metadata failures
set -o pipefail
xcodebuild -project SayoneHealth.xcodeproj -scheme SayoneHealth -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build.log
if grep -E "appintentsmetadataprocessor.*(error|warning)|No AppIntents metadata have been exported" build.log; then
  echo 'App Intents metadata problem'; exit 1; fi
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator/SayoneHealth.app' -maxdepth 6 | head -1)
python3 - "$APP/Metadata.appintents/extract.actionsdata" <<'EOF'
import json,sys
m=json.load(open(sys.argv[1]))
ids={s['actionIdentifier'] for s in m.get('autoShortcuts',[])}
need={'LogWaterIntent','LogDrinkIntent','LogPresetIntent'}
assert need<=ids, f'missing App Shortcuts: {need-ids}'
assert len(m.get('autoShortcuts',[]))<=10
print('App Shortcuts OK:', sorted(ids))
EOF
```

### Recommendations
- Put the AppShortcutsProvider (SayoneShortcuts.swift) and AppShortcuts.xcstrings only in the iOS app target and the watch app target. Compile the intent, enum and entity sources into all four Apple targets (iOS app, iOS widget extension, watch app, watch widget extension) through XcodeGen `sources`. Put Localizable.xcstrings in every one of those targets, because titles and dialogs are resolved from each bundle.
- Do not use AppIntentsPackage, frameworks or the SwiftPM package for intents. Keep AppIntents code in target sources, and let the Linux-buildable package contain only pure logic that the intents call.
- Do not add com.apple.developer.siri, the Siri capability or NSSiriUsageDescription. App Intents need none of them, which keeps the project compatible with a free team.
- Phrase parameters must be AppEnum (DrinkKind) or AppEntity (DrinkPresetEntity), one per phrase. Amounts come from the preset, the intent's default, or a Siri follow-up (`requestValueDialog`). Never put Int or Measurement parameters in phrases.
- For the 'one tap: 0.5 L water' preset flow, use a dedicated intent type per fixed shortcut (for example LogWaterIntent) instead of AppShortcut(intent: LogDrinkIntent(drink: .water)). It is unverified whether the metadata processor accepts pre-filled parameter values.
- Keep 3 to 6 AppShortcut entries and stay well under 10. The cap is enforced only at the appintentsmetadataprocessor step of a full xcodebuild.
- Write TypeDisplayRepresentation(name:) explicitly (not .init), give query types unique names, and use `static let` for title, description and caseDisplayRepresentations, as Apple's sample does. This avoids silent metadata 'halting errors' and Swift-6-style mutable-static diagnostics.
- In CI, fail the build on 'appintentsmetadataprocessor' warnings and 'No AppIntents metadata have been exported'. Also assert that `<App>.app/Metadata.appintents/extract.actionsdata` contains the expected `autoShortcuts`.
- Leave openAppWhenRun and supportedModes undeclared for logging intents, so they run in the background. Do not use iOS 26 or 27-only APIs (supportedModes, continueInForeground, allowedExecutionTargets) unless `if #available` / `@available` guards and CI both show they compile.
- Write natural Russian phrases in AppShortcuts.xcstrings with several variants covering gender (выпил / выпила) and case (воду / воды / колу). Pick phrase templates where the nominative case title still sounds right, because the watch matches phrases exactly. Add Russian DisplayRepresentation synonyms, which help on iPhone.
- Add Cyrillic INAlternativeAppNames through InfoPlist.strings variables, and consider a localized CFBundleDisplayName in ru.lproj/InfoPlist.strings, so Russian Siri recognizes the app name. Put identical synonyms in the watch app's Info.plist.
- Call SayoneShortcuts.updateAppShortcutParameters() in App.init() on both iOS and watchOS and after every preset change. Implement suggestedEntities() so preset phrases get generated.
- Ask for HealthKit permission inside the app UI on the first launch, on both the iPhone and the watch. Siri runs intents in the background and cannot show the permission prompt. If permission is missing, return a dialog telling the user to open the app, rather than failing silently.
- Show SiriTipView on the main screen (iOS and watchOS). Show ShortcutsLink only under `#if os(iOS)`.
- Device test checklist for tomorrow: open the app once on the iPhone and the watch. Check Settings > Apps > SayoneHealth > Siri is enabled. Test with the Siri language set to Russian and again set to English. Check the Shortcuts app lists the shortcuts on both devices. Speak the exact phrases on the watch.

### Open risks
- Russian: Apple does not document which Siri languages App Shortcuts support. One forum report (unanswered) describes Russian Siri running a system shortcut instead of the app's. Whether flexible matching is available for Russian is unknown.
- A Latin app name such as 'SayoneHealth' may be transcribed badly by Russian Siri. Whether a localized CFBundleDisplayName or INAlternativeAppNames works for App Shortcuts in ru can only be confirmed on the device. The older SiriKit doc says synonyms require an Intents extension; Apple's newer App Intents sample says they apply to App Shortcuts.
- It is untested that the metadata processor accepts a hand-written AppShortcuts.xcstrings (extractionState 'manual', stringSet). A malformed catalog may make Xcode rewrite or ignore entries, or fail the build ('does not exist' or 'does not map to a known action' errors).
- It is not verified that parameterized phrases with AppEntity or AppEnum values work on watchOS, nor that Russian inflected forms match without flexible matching on the watch.
- It is unverified whether AppShortcut(intent: SomeIntent(prefilled: value)) with pre-filled parameters is extracted correctly. A community note says mixing pre-baked and parameterized variants of one intent type may misbehave.
- The Xcode version on GitHub macOS runners (26.x vs 27.x) changes available APIs and deprecations. openAppWhenRun and some AppEntity @Parameter initializers produce deprecation warnings that would fail the build if warnings were treated as errors.
- `static let description = IntentDescription(...)` matches Apple's samples, but the requirement is typed `IntentDescription?`. It compiles, but you could skip description entirely to avoid any witness ambiguity.
- The simulator may not run App Shortcuts dispatch reliably (reported for iOS 26.5), and App Shortcuts Preview needs a Mac. Phrase validation is therefore only possible on the real devices tomorrow.
- Intents triggered from widget buttons run in the widget extension process by default. HealthKit writes from widget extensions and cross-process App Group consistency are outside this topic but directly affect the one-tap widget flow.
- XcodeGen's knownRegions detection for xcstrings-only localizations is unverified. Without a ru.lproj folder, 'ru' might be missing from knownRegions.

## Build infrastructure for SayoneHealth: XcodeGen spec (iOS app, single-target watchOS app, iOS and watchOS WidgetKit extensions, local SwiftPM package), xcodebuild CI commands, GitHub Actions macOS runners (September 2026), free Personal Team limits, and required Info.plist keys. The project.yml below was generated successfully with XcodeGen 2.46.0 built on Linux with Swift 6.4.

- **[high]** XcodeGen embeds a watchOS app into the iOS app automatically. It needs no extra YAML: when a target of `type: application` + `platform: watchOS` is listed under the iOS app's `dependencies: - target: X`, XcodeGen emits a PBXCopyFilesBuildPhase named "Embed Watch Content" with dstSubfolderSpec = 16 (productsDirectory), dstPath = "$(CONTENTS_FOLDER_PATH)/Watch" and build-file ATTRIBUTES = (RemoveHeadersOnCopy). Embedding is on by default because the depending target is an app (`shouldEmbed` returns true for isApp). The code path is `dependencyTarget.type.isApp && dependencyTarget.platform == .watchOS`, which checks the .app extension and so covers plain `application`. It was added in commit 5c39cf4e (Oct 2017, first tag 1.3.0) and the phase got its name in 1.11.0. Confirmed by generating a test project with 2.46.0.  
  _src_: XcodeGen source Sources/XcodeGenKit/PBXProjGenerator.swift L787-788, L1297-1306; Sources/ProjectSpec/XCProjExtensions.swift shouldEmbed; git log; local run of xcodegen 2.46.0  
  _implication_: Write only `- target: SayoneHealthWatch` in the iOS app's dependencies. Do not add `embed:` or `copy:` overrides.
- **[high]** Apple's own Xcode 27.0 template output for an iOS app with a single-target watch app still uses exactly this phase: 'Embed Watch Content', dstPath "$(CONTENTS_FOLDER_PATH)/Watch", dstSubfolderSpec 16, productType com.apple.product-type.application, ATTRIBUTES (RemoveHeadersOnCopy). The example is NodePassProject/Anywhere, whose watch target has CreatedOnToolsVersion = 27.0 and LastUpgradeCheck 2640. XcodeGen 2.46.0 generates the same pbxproj structure.  
  _src_: https://raw.githubusercontent.com/NodePassProject/Anywhere/HEAD/Anywhere.xcodeproj/project.pbxproj  
  _implication_: XcodeGen issue #1613 claims Xcode 26 needs the watch app in PlugIns/ (error 'is a Foundation extension and must be embedded in the parent app bundle's PlugIns directory'). It is open, has one reporter and no confirmation, and Apple's template contradicts it. Do NOT apply its sed postGenCommand. That error most likely means the watch app's Info.plist contained an NSExtension key, so keep NSExtension only in the widget plists.
- **[high]** Use the modern single-target watch app: `type: application` + `platform: watchOS`, not `application.watchapp2`/`watchkit2-extension`. The ProjectSpec says: 'App targets currently do not support the watchOS destination. Create a separate target using `platform` for watchOS apps', so `supportedDestinations` cannot be used for the watch app. XcodeGen's watchOS platform preset sets SDKROOT=watchos, SKIP_INSTALL=YES and TARGETED_DEVICE_FAMILY=4. application_watchOS adds ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon.  
  _src_: XcodeGen Docs/ProjectSpec.md (Supported Destinations); SettingPresets/Platforms/watchOS.yml; SettingPresets/Product_Platform/application_watchOS.yml  
  _implication_: The watch target needs only type, platform, sources, info, entitlements and PRODUCT_BUNDLE_IDENTIFIER. SKIP_INSTALL and the device family come from the presets.
- **[high]** An `app-extension` target that is a dependency of an app target (iOS or watchOS) is embedded automatically in an 'Embed Foundation Extensions' phase (dstSubfolderSpec = 13 = PlugIns, dstPath ""). Confirmed for both the iOS widget in the iOS app and the watchOS widget in the watch app. The app-extension preset adds LD_RUNPATH_SEARCH_PATHS ($(inherited), @executable_path/Frameworks, @executable_path/../../Frameworks). XcodeGen does NOT set SKIP_INSTALL for iOS app-extensions, but it does for watchOS ones through the platform preset. It sets TARGETED_DEVICE_FAMILY '1,2' for iOS targets.  
  _src_: PBXProjGenerator.swift L1231-1238; SettingPresets/Products/app-extension.yml; SettingPresets/Platforms/iOS.yml; local generation  
  _implication_: Put the watch widget under the watch app's dependencies and the iOS widget under the iOS app's. Set SKIP_INSTALL: YES and TARGETED_DEVICE_FAMILY: "1" explicitly on the iOS widget to match an iPhone-only app.
- **[high]** The target `info: {path, properties}` writes the plist on every `xcodegen generate` and sets INFOPLIST_FILE. It adds these keys automatically: CFBundleIdentifier=$(PRODUCT_BUNDLE_IDENTIFIER), CFBundleExecutable, CFBundleName, CFBundleDevelopmentRegion=$(DEVELOPMENT_LANGUAGE), CFBundleInfoDictionaryVersion, CFBundlePackageType (APPL for application, XPC! for app-extension). It hardcodes CFBundleShortVersionString='1.0' and CFBundleVersion='1' unless you override them. `entitlements: {path, properties}` writes the file and sets CODE_SIGN_ENTITLEMENTS; you must provide every property.  
  _src_: XcodeGen Docs/ProjectSpec.md (Target.info, Plist); Sources/XcodeGenKit/InfoPlistGenerator.swift  
  _implication_: Set CFBundleShortVersionString: $(MARKETING_VERSION) and CFBundleVersion: $(CURRENT_PROJECT_VERSION) in all 4 plists so the extension and watch versions match the parent app. Commit the generated plists and entitlements too: they are regenerated anyway, and committing them lets the user open the project without XcodeGen.
- **[high]** XcodeGen generates schemes only for targets that have a `scheme:` key (an empty `scheme: {}` is valid and used in XcodeGen's own fixtures) or that appear in top-level `schemes:`. For a plain `application` watchOS target, the scheme builds only the watch app. Only the legacy watchApp/watch2App types add the host app to the scheme.  
  _src_: Sources/XcodeGenKit/SchemeGenerator.swift L43-95, L533-545; Tests/Fixtures/TestProject/project.yml  
  _implication_: Add `scheme: {}` to SayoneHealth and SayoneHealthWatch. That produces shared schemes SayoneHealth.xcscheme and SayoneHealthWatch.xcscheme (confirmed), which xcodebuild -scheme needs in CI.
- **[high]** For local Swift packages, declare `packages: HydrationCore: {path: Packages/HydrationCore}`, which becomes an XCLocalSwiftPackageReference. Targets depend on it with `- package: HydrationCore`; the product defaults to the package key, so the key must equal the library product name. Package products are linked but never embedded unless `embed: true`. The same product can be linked into iOS and watchOS targets and Xcode builds it once per platform.  
  _src_: ProjectSpec.md (Swift Package, Dependency); PBXProjGenerator.swift L953-998; local generation  
  _implication_: Link HydrationCore into all 4 targets as a static library with no embedding. If the product name does not match, Xcode fails with 'Missing package product'.
- **[high]** PackageDescription platform enum availability depends on swift-tools-version, tested with the Linux Swift 6.4 toolchain. With tools 5.9, .iOS(.v17), .watchOS(.v10) and .macOS(.v14) work, but .v18 errors with ''v18' is unavailable'. .iOS(.v18)/.watchOS(.v11)/.macOS(.v15) need tools 6.0, and .v26 needs 6.2. Tools-version 6.0+ defaults package targets to the Swift 6 language mode unless you set `swiftLanguageModes: [.v5]`. Linux ignores `platforms`, and `swift build`/`swift test` passed with XCTest and swift-testing both available.  
  _src_: Local experiment with /opt/swift/swift-6.4.0-RELEASE-ubuntu24.04 (swift package dump-package, swift build, swift test)  
  _implication_: Use `// swift-tools-version: 5.9` with platforms [.iOS(.v17), .watchOS(.v10), .macOS(.v14)]. It stays in Swift 5 mode with no strict-concurrency errors and works with Xcode 26+ and Linux. The package minimums must be at or below the app deployment targets (iOS 17 / watchOS 10); otherwise Xcode fails with 'requires minimum platform version'.
- **[high]** XcodeGen 2.46.0 (tag dated 2026-07-16) is the latest release. The Homebrew formula is 2.46.0 with bottles for arm64_tahoe (macOS 26), arm64_sequoia, arm64_sonoma and arm64_golden_gate. The release asset https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip contains xcodegen/bin/xcodegen and xcodegen/share/xcodegen/SettingPresets, and the binary finds presets at bundlePath + '../share/xcodegen'. Unreleased 'Next Version' changes scheme default buildArchitectures, so pin 2.46.0.  
  _src_: https://github.com/yonaskolb/XcodeGen CHANGELOG.md; https://formulae.brew.sh/api/formula/xcodegen.json; SettingsBuilder.swift L231  
  _implication_: In CI, download the pinned zip (deterministic, no brew auto-update). Locally the user can run `brew install xcodegen`.
- **[high]** XcodeGen 2.46.0 builds and runs on Linux with the local Swift 6.4 toolchain (`swift build -c release --product xcodegen`, about 100 s). It needs the USER or LOGNAME env var, or it exits with 'Couldn't find current username'. Output was byte-identical across runs and contained no absolute paths. A binary is already built at /tmp/claude-0/-home-user-sayonehealth/d849792d-41f7-5614-bc43-7df4368374ac/scratchpad/xcodegen/.build/release/xcodegen, and the validated sample project is at /tmp/claude-0/-home-user-sayonehealth/d849792d-41f7-5614-bc43-7df4368374ac/scratchpad/infra/proj.  
  _src_: Local build and generation run  
  _implication_: The agent can check project.yml, the generated plists and entitlements, and the pbxproj phases on Linux before spending a macOS CI round-trip. It can also commit the generated .xcodeproj so the user can open it tomorrow without installing XcodeGen.
- **[high]** XcodeGen supports .xcstrings String Catalogs (2.39.0) and adds the locales found in a catalog's `localizations` to the project's knownRegions. .lproj folders add their regions too; `ru` showed up in knownRegions in the test. Unknown file types in source folders (.md, .json, other .plist) default to the Copy Bundle Resources phase; files named Info.plist and .entitlements are excluded.  
  _src_: CHANGELOG 2.39.0; Sources/XcodeGenKit/SourceGenerator.swift L526-600; Sources/ProjectSpec/FileType.swift  
  _implication_: Use Localizable.xcstrings, AppShortcuts.xcstrings and InfoPlist.xcstrings with en and ru entries. Exclude **/*.md from source paths, because two README.md files in one target cause a 'Multiple commands produce' error.
- **[high]** GitHub runner labels (Sept 2026): `macos-latest` = `macos-26` = macOS 26 arm64, image 20260907. Default Xcode is 26.6 (17F113) at /Applications/Xcode_26.6.app, also symlinked as /Applications/Xcode.app. Xcode 26.0.1, 26.1.1, 26.2, 26.3, 26.4.1 and 26.5 are also installed. Xcode 26.5/26.6 use SDKs iphonesimulator26.5 and watchsimulator26.5, and the installed simulator runtimes are iOS 26.2, 26.4.1 and 26.5 and watchOS 26.2, 26.4 and 26.5 (devices include iPhone 17 and Apple Watch Series 11 46mm). `macos-15` defaults to Xcode 16.4 and has 26.0.1–26.3 installed. macOS 14 images are deprecated and unsupported from Nov 2. A preview image `xcode-27` (macOS 27, Xcode 27.0 default, plus 27.1 and 27.2 beta) exists, with queueing caveats. xcbeautify 3.2.1 is preinstalled on the macOS images and Swift 6.4 on ubuntu-24.04.  
  _src_: https://github.com/actions/runner-images README.md, images/macos/macos-26-arm64-Readme.md, macos-15-arm64-Readme.md, xcode-27-arm64-Readme.md, Ubuntu2404-Readme.md; issue #14404  
  _implication_: Use `runs-on: macos-26` with its default Xcode. Add an optional `runs-on: xcode-27` job with continue-on-error, because the user's devices may be on iOS/watchOS 27 and so need Xcode 27 locally.
- **[high]** Runner-image Xcode policy: 'only one major version of Xcode will be supported per macOS version … when a new patch version is released, the previous patch version will be replaced'. A mismatch between the Xcode SDK and the installed simulator runtimes causes actool/xcodebuild failures such as 'No simulator runtime version from [...] available to use with iphonesimulator SDK version ...' (runner-images #13317).  
  _src_: runner-images README (Software and image support); https://github.com/actions/runner-images/issues/13317  
  _implication_: Don't hardcode patch paths like Xcode_26.6.app. Use the default Xcode or pick the newest Xcode_26*.app by glob, and print `xcrun simctl list runtimes` and `xcodebuild -showsdks` for diagnosis.
- **[high]** GitHub Actions is free on standard GitHub-hosted runners for public repositories, including macOS. The Free plan allows 20 concurrent jobs, at most 5 of them macOS. A job can run up to 6 hours. Larger runners (-xlarge/-large) are always billed.  
  _src_: https://docs.github.com/en/billing/concepts/product-billing/github-actions; https://docs.github.com/en/actions/reference/limits  
  _implication_: Keep sayoneone/sayonehealth public. Use only `macos-26`, `ubuntu-24.04` and optionally `xcode-27`, never the `-xlarge` labels.
- **[high]** Capabilities for a free 'Apple Developer' account (Personal Team), from Apple's capability tables. iOS allows: App groups, Background modes, Data protection, HealthKit, HomeKit, Inter-App Audio, Keychain sharing, Maps, Wireless Accessory Configuration. iOS does NOT allow: Siri, Push notifications, all iCloud (CloudKit/documents/KVS), Associated domains, Sign in with Apple, In-App Purchase, Game Center, Time Sensitive Notifications, WeatherKit, HealthKit Estimate Recalibration, and others. watchOS allows: App groups, Background modes, Data protection, HealthKit, HomeKit, Keychain sharing, Maps. watchOS does NOT allow Siri, Push or iCloud.  
  _src_: https://developer.apple.com/help/account/reference/supported-capabilities-ios and .../supported-capabilities-watchos (table column 'Apple Developer')  
  _implication_: Use HealthKit and App Groups on all 4 targets. Never add com.apple.developer.siri, aps-environment, iCloud or associated-domains entitlements, or free-team signing fails.
- **[high]** Apple's doc for com.apple.developer.siri says: 'The App Store requires the presence of this entitlement for iOS or watchOS apps containing Intents app extensions that handle any Siri requests other than shortcut requests.' The Siri capability configures SiriKit (Intents framework) handling. App Intents / AppShortcutsProvider need no Siri entitlement.  
  _src_: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.siri ; https://developer.apple.com/documentation/xcode/configuring-siri-support  
  _implication_: Build the Siri integration with App Intents plus AppShortcutsProvider, with Russian and English phrases in AppShortcuts.xcstrings, and no entitlement. One unverified report (Redth/Maui.Apple.PlatformFeature.Samples#1) says Siri voice did not invoke intents without the entitlement; see open risks.
- **[medium]** Free Personal Team limits: provisioning profiles expire after 7 days; 'You may create up to 10 App IDs every 7 days'; at most 3 free-provisioned apps can be installed per device ('The maximum number of apps for free development profiles has been reached'). In one forum report, an iOS app plus its watch app counted as one app. App IDs registered by a personal team cannot be deleted by the user.  
  _src_: https://developer.apple.com/forums/thread/49304 ; https://developer.apple.com/forums/thread/658196 ; https://developer.apple.com/forums/thread/675347 ; https://github.com/Brian-Egan/StillMotions/pull/41  
  _implication_: The project uses 4 App IDs (app, .widget, .watchkitapp, .watchkitapp.widget) plus the app group. Pick the bundle prefix once, because each prefix change burns 4 of the 10 weekly IDs. A free team can install the iOS app, the watch app and both widgets, but the user should delete other sideloaded apps first and rebuild after 7 days.
- **[medium]** Embedded-binary validation rules (ValidateEmbeddedBinary step). An extension's or watch app's bundle ID must be prefixed by its parent's bundle ID ('Embedded binary's bundle identifier is not prefixed with the parent app's bundle identifier'). The watch app's WKCompanionAppBundleIdentifier must equal the iOS app's CFBundleIdentifier. Extension and watch CFBundleShortVersionString/CFBundleVersion should match the parent: a mismatch is a warning for extensions and can be an error for watch apps.  
  _src_: https://developer.apple.com/forums/thread/5956 ; https://developer.apple.com/documentation/bundleresources/information-property-list/wkcompanionappbundleidentifier ; memory  
  _implication_: Use the IDs $(BUNDLE_ID_PREFIX), $(BUNDLE_ID_PREFIX).widget, $(BUNDLE_ID_PREFIX).watchkitapp and $(BUNDLE_ID_PREFIX).watchkitapp.widget, set WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX), and share the version variables through the xcconfig.
- **[high]** Info.plist keys. WKApplication (Boolean, watchOS 7.0+) marks a single-target watch app. WKCompanionAppBundleIdentifier (watchOS 1.0+) must equal the iOS CFBundleIdentifier. WKRunsIndependentlyOfCompanionApp (watchOS 6.0+) is optional; YES allows installing and running without the iPhone app. NSHealthShareUsageDescription / NSHealthUpdateUsageDescription are required when the app reads or writes HealthKit. Widget extensions need NSExtension.NSExtensionPointIdentifier = com.apple.widgetkit-extension (same value on watchOS, with no principal class). UIBackgroundModes and NSSupportsLiveActivities are not needed. The iOS app needs UILaunchScreen: {} to avoid legacy letterboxed mode.  
  _src_: developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/{wkapplication,wkcompanionappbundleidentifier,wkrunsindependentlyofcompanionapp,nshealthshareusagedescription,nshealthupdateusagedescription}.json; philipwilson/trees project.yml (real XcodeGen spec with watch app and watch widget); memory for UILaunchScreen  
  _implication_: Put the Health usage strings in both the iOS and watch app plists (the watch requests authorization itself) and localize them through InfoPlist.xcstrings (ru). Keep NSExtension out of both app plists.
- **[medium]** Apple's Xcode 27 template settings for a companion watch app (as found in Anywhere): GENERATE_INFOPLIST_FILE=YES, INFOPLIST_KEY_WKCompanionAppBundleIdentifier=<ios id>, PRODUCT_BUNDLE_IDENTIFIER=<ios id>.watchkitapp, SDKROOT=watchos, SKIP_INSTALL=YES, TARGETED_DEVICE_FAMILY=4, LD_RUNPATH_SEARCH_PATHS=@executable_path/Frameworks, REGISTER_APP_GROUPS=YES. New templates also set SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor and SWIFT_APPROACHABLE_CONCURRENCY=YES, but XcodeGen does not set them.  
  _src_: NodePassProject/Anywhere project.pbxproj (watch target CreatedOnToolsVersion 27.0)  
  _implication_: The XcodeGen output matches Apple's layout. Do NOT enable MainActor default isolation, because it would change semantics against the Swift 5 package code.
- **[medium]** Real-device watch builds include arm64_32 (Series 4–8 / SE, watchOS 10 deployment target), where Swift `Int` is 32-bit. Simulator builds (arm64/x86_64) do not catch literal overflows such as 'integer literal overflows when stored into Int' or 32-bit arithmetic overflow.  
  _src_: memory  
  _implication_: Add an unsigned `generic/platform=iOS` device build in CI; it also builds the embedded watch app for device architectures. Use Double or Int64 in HydrationCore for millilitres, timestamps and sums.
- **[high]** actions/checkout@v4 runs on node20, while v5, v6 and v7 run on node24. The Swift 6.4 toolchain is preinstalled on ubuntu-24.04, so no setup-swift action is needed there.  
  _src_: raw action.yml of actions/checkout tags; runner-images Ubuntu2404-Readme.md  
  _implication_: Use actions/checkout@v5 to avoid Node 20 deprecation warnings.

### Snippets

```
# project.yml (generated successfully with XcodeGen 2.46.0; produces 'Embed Watch Content' -> $(CONTENTS_FOLDER_PATH)/Watch, two 'Embed Foundation Extensions' (PlugIns) phases, and shared schemes SayoneHealth + SayoneHealthWatch)
name: SayoneHealth
options:
  minimumXcodeGenVersion: 2.44.1
  xcodeVersion: "26.0"          # LastUpgradeCheck 2600, avoids 'update settings' prompt
  developmentLanguage: en
  deploymentTarget:
    iOS: "17.0"
    watchOS: "10.0"
  createIntermediateGroups: true
configFiles:
  Debug: Config/Base.xcconfig
  Release: Config/Base.xcconfig
settings:
  base:
    SWIFT_VERSION: "5.0"
    SWIFT_STRICT_CONCURRENCY: minimal
packages:
  HydrationCore:
    path: Packages/HydrationCore
targets:
  SayoneHealth:
    type: application
    platform: iOS
    sources:
      - path: App/Sources
      - path: App/Resources
      - path: Shared
        excludes: ["**/*.md"]
    dependencies:
      - package: HydrationCore
      - target: SayoneHealthWidget      # -> Embed Foundation Extensions (PlugIns)
      - target: SayoneHealthWatch       # -> Embed Watch Content ($(CONTENTS_FOLDER_PATH)/Watch)
    info:
      path: App/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        LSRequiresIPhoneOS: true
        UILaunchScreen: {}
        UISupportedInterfaceOrientations: [UIInterfaceOrientationPortrait]
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show daily progress."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log to Apple Health."
        SHAppGroupIdentifier: $(APP_GROUP_ID)   # read at runtime via Bundle.main.object(forInfoDictionaryKey:)
    entitlements:
      path: App/SayoneHealth.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX)
        TARGETED_DEVICE_FAMILY: "1"
    scheme: {}
  SayoneHealthWidget:
    type: app-extension
    platform: iOS
    sources:
      - path: Widget/Sources
      - path: Shared
        excludes: ["**/*.md"]
    dependencies:
      - package: HydrationCore
    info:
      path: Widget/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        SHAppGroupIdentifier: $(APP_GROUP_ID)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: Widget/SayoneHealthWidget.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).widget
        TARGETED_DEVICE_FAMILY: "1"
        SKIP_INSTALL: YES
  SayoneHealthWatch:
    type: application
    platform: watchOS
    sources:
      - path: Watch/Sources
      - path: Shared
        excludes: ["**/*.md"]
    dependencies:
      - package: HydrationCore
      - target: SayoneHealthWatchWidget # -> Embed Foundation Extensions (PlugIns) inside the watch app
    info:
      path: Watch/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        WKApplication: true
        WKCompanionAppBundleIdentifier: $(BUNDLE_ID_PREFIX)
        WKRunsIndependentlyOfCompanionApp: true
        NSHealthShareUsageDescription: "SayoneHealth reads your water intake to show daily progress."
        NSHealthUpdateUsageDescription: "SayoneHealth saves the drinks you log to Apple Health."
        SHAppGroupIdentifier: $(APP_GROUP_ID)
    entitlements:
      path: Watch/SayoneHealthWatch.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp
    scheme: {}
  SayoneHealthWatchWidget:
    type: app-extension
    platform: watchOS
    sources:
      - path: WatchWidget/Sources
      - path: Shared
        excludes: ["**/*.md"]
    dependencies:
      - package: HydrationCore
    info:
      path: WatchWidget/Info.plist
      properties:
        CFBundleDisplayName: SayoneHealth
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        SHAppGroupIdentifier: $(APP_GROUP_ID)
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
    entitlements:
      path: WatchWidget/SayoneHealthWatchWidget.entitlements
      properties:
        com.apple.developer.healthkit: true
        com.apple.developer.healthkit.access: []
        com.apple.security.application-groups: [$(APP_GROUP_ID)]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID_PREFIX).watchkitapp.widget
```
```
// Config/Base.xcconfig  (project-level configFiles; all targets inherit these)
// If the bundle ID is taken for your Personal Team, change BUNDLE_ID_PREFIX and APP_GROUP_ID together.
BUNDLE_ID_PREFIX = com.sayoneone.sayonehealth
APP_GROUP_ID = group.com.sayoneone.sayonehealth
MARKETING_VERSION = 1.0
CURRENT_PROJECT_VERSION = 1
DEVELOPMENT_TEAM =
CODE_SIGN_STYLE = Automatic
```
```
// Packages/HydrationCore/Package.swift  (builds and tests with Linux Swift 6.4 and Xcode 26+; Swift 5 language mode by default)
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HydrationCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],   // .v18/.v11/.v15 need tools 6.0; .v26 needs 6.2
    products: [.library(name: "HydrationCore", targets: ["HydrationCore"])],
    targets: [
        .target(name: "HydrationCore"),
        .testTarget(name: "HydrationCoreTests", dependencies: ["HydrationCore"]),
    ]
)
// With swift-tools-version 6.0 instead, add:  swiftLanguageModes: [.v5]
```
```
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  core-linux:
    runs-on: ubuntu-24.04            # Swift 6.4 preinstalled
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
      - run: swift --version
      - run: swift test --package-path Packages/HydrationCore

  apple:
    runs-on: macos-26                # arm64, default Xcode 26.6 (SDK 26.5, runtimes 26.5 installed)
    timeout-minutes: 60
    env:
      XCODEGEN_VERSION: "2.46.0"
    steps:
      - uses: actions/checkout@v5
      - name: Show toolchain
        run: |
          xcode-select -p
          xcodebuild -version
          xcodebuild -showsdks | grep -E 'iphonesimulator|watchsimulator|iphoneos|watchos'
          xcrun simctl list runtimes
      - name: Install XcodeGen (pinned release zip)
        run: |
          curl -fsSL -o "$RUNNER_TEMP/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
          unzip -q "$RUNNER_TEMP/xcodegen.zip" -d "$RUNNER_TEMP"
          echo "$RUNNER_TEMP/xcodegen/bin" >> "$GITHUB_PATH"
      - name: Generate project
        run: xcodegen --version && xcodegen generate
      - name: HydrationCore tests (macOS)
        run: swift test --package-path Packages/HydrationCore
      - name: Build iOS app + iOS widget + embedded watch app + watch widget (Simulator)
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -configuration Debug \
            -destination 'generic/platform=iOS Simulator' -derivedDataPath "$RUNNER_TEMP/dd-sim" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            | xcbeautify --renderer github-actions
      - name: Build watch app standalone (watchOS Simulator)
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealthWatch -configuration Debug \
            -destination 'generic/platform=watchOS Simulator' -derivedDataPath "$RUNNER_TEMP/dd-sim" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            | xcbeautify --renderer github-actions
      - name: Build for real devices, unsigned (catches arm64_32 / device-only issues)
        continue-on-error: true      # make blocking once it is green
        run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth -configuration Debug \
            -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/dd-dev" \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" COMPILER_INDEX_STORE_ENABLE=NO \
            | xcbeautify --renderer github-actions

  apple-xcode27:                     # preview image; may queue. Same steps as 'apple' job.
    runs-on: xcode-27
    continue-on-error: true
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v5
      - run: |
          curl -fsSL -o "$RUNNER_TEMP/xg.zip" https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip
          unzip -q "$RUNNER_TEMP/xg.zip" -d "$RUNNER_TEMP" && "$RUNNER_TEMP/xcodegen/bin/xcodegen" generate
      - run: |
          set -o pipefail
          xcodebuild build -project SayoneHealth.xcodeproj -scheme SayoneHealth \
            -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO | xcbeautify --renderer github-actions
```
```
# Local (Linux) pre-flight before pushing, so a bad project.yml never reaches macOS CI
export PATH=/opt/swift/swift-6.4.0-RELEASE-ubuntu24.04/usr/bin:$PATH
# one-time build of XcodeGen (~100 s); an already-built binary exists at
# /tmp/claude-0/-home-user-sayonehealth/d849792d-41f7-5614-bc43-7df4368374ac/scratchpad/xcodegen/.build/release/xcodegen
git clone --depth 1 --branch 2.46.0 https://github.com/yonaskolb/XcodeGen.git /tmp/xcodegen-src
(cd /tmp/xcodegen-src && swift build -c release --product xcodegen)
cd /home/user/sayonehealth
USER=ci LOGNAME=ci /tmp/xcodegen-src/.build/release/xcodegen generate --spec project.yml   # USER is required on Linux
grep -A8 'Embed Watch Content \*/ = {' SayoneHealth.xcodeproj/project.pbxproj             # expect dstSubfolderSpec = 16, dstPath $(CONTENTS_FOLDER_PATH)/Watch
grep -c 'Embed Foundation Extensions \*/ = {' SayoneHealth.xcodeproj/project.pbxproj       # expect 2
ls SayoneHealth.xcodeproj/xcshareddata/xcschemes                                           # SayoneHealth.xcscheme SayoneHealthWatch.xcscheme
python3 -c "import plistlib,glob;[plistlib.load(open(f,'rb')) for f in glob.glob('**/*.plist',recursive=True)+glob.glob('**/*.entitlements',recursive=True)];print('plists ok')"
swift test --package-path Packages/HydrationCore
```

### Recommendations
- Use `type: application` + `platform: watchOS` for the watch app and list it as a plain `- target:` dependency of the iOS app. XcodeGen then emits Apple's own 'Embed Watch Content' phase, identical to Xcode 27's template. Ignore the sed workaround in XcodeGen #1613.
- Give each of the 4 targets its own `info:` and `entitlements:` block. Drive the bundle IDs, app group and versions from one project-level xcconfig (BUNDLE_ID_PREFIX, APP_GROUP_ID, MARKETING_VERSION, CURRENT_PROJECT_VERSION) so the user can change the prefix in one place if it is taken for their Personal Team. Expose the app group to Swift through a custom Info.plist key (SHAppGroupIdentifier = $(APP_GROUP_ID)) rather than hardcoding it.
- Add `scheme: {}` to SayoneHealth and SayoneHealthWatch; XcodeGen generates no schemes without it.
- Keep HydrationCore at swift-tools-version 5.9 with platforms [.iOS(.v17), .watchOS(.v10), .macOS(.v14)]. It must import only Foundation (no HealthKit, SwiftUI or os). Use Double/Int64 for amounts and timestamps because watch devices are arm64_32.
- Before every push, run XcodeGen 2.46.0 on Linux (already built in the scratchpad; set USER=ci) and grep the pbxproj phases and schemes. This catches spec errors without a macOS round-trip. Commit the generated SayoneHealth.xcodeproj, Info.plists and entitlements so the user can open the project tomorrow without installing XcodeGen. Generation is deterministic, so CI can regenerate and optionally run `git diff --exit-code`.
- CI: run `swift test` on ubuntu-24.04. On macos-26 (default Xcode 26.6, not patch-pinned), run three xcodebuild builds with CODE_SIGNING_ALLOWED=NO: iOS scheme to generic iOS Simulator (also builds the embedded watch app for watchsimulator), watch scheme to generic watchOS Simulator, and iOS scheme to generic iOS device (catches arm64_32 issues). Pipe through the preinstalled `xcbeautify --renderer github-actions` with `set -o pipefail`. Add a non-blocking `xcode-27` job, because the user's iPhone/Watch may already be on iOS/watchOS 27 and so need Xcode 27 locally.
- Install XcodeGen in CI from the pinned release zip (xcodegen/bin/xcodegen) rather than `brew install`, which avoids brew auto-update latency and version drift. For the user's Mac, document `brew install xcodegen && xcodegen generate` (brew currently ships 2.46.0 with an arm64_tahoe bottle).
- Entitlements: use only HealthKit (com.apple.developer.healthkit=true, com.apple.developer.healthkit.access=[]) and App Groups on all 4 targets; both are allowed for free accounts on iOS and watchOS. Never add Siri, Push, iCloud or Associated Domains entitlements. Build Siri support with App Intents plus AppShortcutsProvider, which needs no entitlement. Put the ru/en phrases in AppShortcuts.xcstrings, and CFBundleDisplayName and the Health usage strings in InfoPlist.xcstrings.
- Include NSHealthShareUsageDescription and NSHealthUpdateUsageDescription in both the iOS and watch app plists. Keep NSExtension only in the two widget plists. Add UILaunchScreen: {} to the iOS plist. UIBackgroundModes and NSSupportsLiveActivities are not needed.
- README checklist for tomorrow's device test: enable Developer Mode on the iPhone and on the Apple Watch (Settings > Privacy & Security). In Xcode, set the Personal Team on all 4 targets, or put DEVELOPMENT_TEAM in Config/Base.xcconfig. Remove other sideloaded apps (3-app limit). Trust the developer profile under Settings > General > VPN & Device Management. Run the SayoneHealth scheme on the iPhone first, which installs the watch app, then the SayoneHealthWatch scheme on the watch for debugging. Rebuild after 7 days because free profiles expire.
- Do not use `-xlarge`/`-large` runner labels (always billed), and keep the repo public so macOS minutes stay free.

### Open risks
- The iOS-simulator build of an iOS scheme with an embedded single-target watch app has not been executed on a real macOS runner in this research. The pbxproj matches Apple's Xcode 27 template, but the first CI run is still the real test, including whether ValidateEmbeddedBinary passes with CODE_SIGNING_ALLOWED=NO for the generic iOS device build (that step is kept non-blocking for this reason).
- XcodeGen #1613 (open, one reporter, Xcode 26.4) claims the watch app must be in PlugIns/. It is contradicted by Apple's Xcode 27 template, but if CI shows 'is a Foundation extension and must be embedded in the parent app bundle's PlugIns directory', first check that no NSExtension key leaked into Watch/Info.plist before changing the embed destination.
- Expansion of $(APP_GROUP_ID) inside .entitlements during automatic signing and capability registration on a free team is from memory (medium confidence). Fallback: hardcode group.com.sayoneone.sayonehealth in the entitlements via XcodeGen properties.
- Free Personal Team: it is unclear whether widget extensions count toward the 3-installed-apps-per-device limit. App IDs claimed by a personal team cannot be released, and com.sayoneone.sayonehealth may already be registered to another team, in which case the user must change BUNDLE_ID_PREFIX and APP_GROUP_ID in the xcconfig. Each new prefix consumes 4 of the 10 App IDs allowed per 7 days.
- Siri: Apple's docs say App Shortcuts need no com.apple.developer.siri entitlement, and a free team cannot get it anyway. One unverified community report says Siri voice invocation of App Intents failed without it. If voice phrases don't trigger tomorrow, test through the Shortcuts app and Spotlight first.
- HealthKit writes from interactive widget buttons: if the App Intent runs in the widget extension process, the extension needs the HealthKit entitlement (included above), and whether an extension may save to HealthKit before the containing app has been authorized needs verification in the HealthKit/WidgetKit research track. App Groups do NOT share data between iPhone and Watch (they are separate devices), so cross-device sync must go through HealthKit or WatchConnectivity.
- The runner image contents are a snapshot (macos-26 image 20260907). Xcode patch versions get replaced over time, so avoid hardcoded /Applications/Xcode_26.x.app paths. The xcode-27 image is a preview with possible queueing and instability.
- If the user builds locally with Xcode 27 (likely if their devices run iOS/watchOS 27), new compiler diagnostics may appear that the Xcode 26.6 CI job does not catch; the xcode-27 CI job mitigates this only if it gets scheduled.
