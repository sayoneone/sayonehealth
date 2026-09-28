import SwiftUI
import SayoneCore

/// «Другой напиток…»: every active drink; a tap pushes the Digital Crown volume picker.
struct DrinkPickerView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(model.catalog.activeDrinks) { drink in
            NavigationLink(value: WatchRoute.volume(drink)) {
                DrinkPickerRow(drink: drink)
            }
        }
        .navigationTitle("Drinks")
    }
}

private struct DrinkPickerRow: View {
    let drink: Drink

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: drink.symbol)
                .foregroundStyle(drink.tint.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: drink.displayName)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(verbatim: VolumeText.short(drink.defaultVolumeML))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
