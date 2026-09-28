import Foundation
import SwiftUI
import SayoneCore

/// Built-in and custom drinks; tap to edit, add a custom drink at the bottom.
struct DrinksListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(builtInDrinks) { drink in
                    link(drink)
                }
            } header: {
                Text("Built-in drinks")
            }
            Section {
                ForEach(customDrinks) { drink in
                    link(drink)
                }
                NavigationLink {
                    DrinkEditorView(drink: nil)
                } label: {
                    Label("Add a custom drink", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("My drinks")
            } footer: {
                Text("Values are approximate and can be edited.")
            }
        }
        .navigationTitle("Drinks")
    }

    private var builtInDrinks: [Drink] {
        model.catalog.activeDrinks.filter { $0.builtIn != nil }
    }

    private var customDrinks: [Drink] {
        model.catalog.activeDrinks.filter { $0.builtIn == nil }
    }

    private func link(_ drink: Drink) -> some View {
        NavigationLink {
            DrinkEditorView(drink: drink)
        } label: {
            DrinkListRow(drink: drink)
        }
    }
}

private struct DrinkListRow: View {
    let drink: Drink

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: drink.symbol)
                .font(.body)
                .foregroundStyle(drink.tint.color)
                .frame(width: 34, height: 34)
                .background(drink.tint.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: drink.displayName)
                    .lineLimit(1)
                Text(verbatim: VolumeText.short(drink.defaultVolumeML))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
