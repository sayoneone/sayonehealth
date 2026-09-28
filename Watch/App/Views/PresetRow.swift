import SwiftUI
import SayoneCore

/// One big one-tap row: "+250 мл" over the drink name. `isPrimary` gives the row the double tap.
struct PresetRow: View {
    let preset: PresetDisplay
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: preset.symbol)
                    .font(.title3)
                    .foregroundStyle(preset.tint.color)
                    .frame(width: 30, height: 30)
                    .background(preset.tint.background, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: VolumeText.plus(preset.volumeML))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(verbatim: preset.drinkName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
        .watchPrimaryAction(enabled: isPrimary)
    }
}
