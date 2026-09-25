import SwiftUI
import SayoneCore

/// Static help: adding a drink button to the watch face (watchOS 11 and 26) and the Smart Stack.
struct ComplicationHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("How to add to the watch face")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "watchOS 11")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HelpStep(symbol: "1.circle.fill", text: Text("Touch and hold the watch face, then tap Edit."))
                HelpStep(symbol: "2.circle.fill", text: Text("Swipe to Complications and tap a slot."))
                HelpStep(symbol: "3.circle.fill", text: Text("Choose SayoneHealth, then a drink, for example \(exampleTitle)."))
                Text(verbatim: "watchOS 26")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                HelpStep(symbol: "plus.circle.fill", text: Text("On watchOS 26, add Quick Log, then choose the drink."))
                HelpStep(symbol: "square.stack.fill", text: Text("Smart Stack: add Quick Log or Favorites. Double tap logs the drink."))
                HelpStep(symbol: "iphone", text: Text("Open the watch app once after editing buttons on iPhone."))
            }
        }
        .navigationTitle("Watch Face")
    }

    /// «Вода · 500 мл» / "Water · 500 ml", the complication option the user looks for.
    private var exampleTitle: String {
        Phrasebook.drinkName(.water, .current) + " · " + VolumeText.short(500)
    }
}

private struct HelpStep: View {
    let symbol: String
    let text: Text

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.blue)
            text
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
