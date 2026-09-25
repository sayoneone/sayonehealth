import AppIntents

/// Per-instance configuration of the Quick Log widget (Home Screen, Lock Screen, watch face, Smart Stack).
struct SelectPresetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Drink"
    @Parameter(title: "Drink") var preset: PresetEntity?
    init() {}
    init(preset: PresetEntity) { self.preset = preset }
}
