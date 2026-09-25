import SwiftUI
import SayoneCore

/// Digital Crown volume picker (50…2000 ml, step 50). Pushed by navigation, never inside a List.
struct VolumePickerView: View {
    let drink: Drink
    let onLogged: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var ml: Double
    @FocusState private var crownFocused: Bool

    private static let minML: Double = 50
    private static let maxML: Double = 2000
    private static let stepML: Double = 50

    init(drink: Drink, onLogged: @escaping () -> Void = {}) {
        self.drink = drink
        self.onLogged = onLogged
        let start = min(VolumePickerView.maxML, max(VolumePickerView.minML, Double(drink.defaultVolumeML)))
        _ml = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 6) {
            header
            HStack(spacing: 4) {
                stepButton(-VolumePickerView.stepML, symbol: "minus.circle.fill", label: "Less")
                volumeText
                stepButton(VolumePickerView.stepML, symbol: "plus.circle.fill", label: "More")
            }
            Button("Log") { logNow() }
                .buttonStyle(.borderedProminent)
                .tint(drink.tint.color)
        }
        .onAppear { crownFocused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: drink.symbol)
                .foregroundStyle(drink.tint.color)
            Text(verbatim: drink.displayName)
                .font(.footnote)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    private var volumeText: some View {
        Text(verbatim: VolumeText.short(Int(ml.rounded())))
            .font(.title2)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .focusable()
            .focused($crownFocused)
            .digitalCrownRotation($ml, from: VolumePickerView.minML, through: VolumePickerView.maxML,
                                  by: VolumePickerView.stepML, sensitivity: .medium,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
    }

    private func stepButton(_ delta: Double, symbol: String, label: LocalizedStringKey) -> some View {
        Button {
            ml = min(VolumePickerView.maxML, max(VolumePickerView.minML, ml + delta))
        } label: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(drink.tint.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    /// Pops to the root first (the banner and ring live there), then logs. The Task outlives this
    /// view, so it captures the model object itself rather than the view's environment wrapper.
    private func logNow() {
        let appModel = model
        let drinkID = drink.id
        let volume = Int(ml.rounded())
        onLogged()
        Task { await appModel.log(drinkID: drinkID, volumeML: volume) }
    }
}
