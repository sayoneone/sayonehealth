import Foundation
import SwiftUI
import SayoneCore

/// "Other drink…": pick any active drink and a volume, then log it.
struct LogDrinkSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var drinkID: String = BuiltInCatalog.fallbackDrinkID
    @State private var volumeML: Int = 250

    private static let columns: [GridItem] = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    drinkGrid
                } header: {
                    Text("Drink")
                }
                Section {
                    VolumeChipsPicker(volumeML: $volumeML)
                } header: {
                    Text("Volume")
                }
            }
            .navigationTitle("Other drink…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { logBar }
        }
    }

    private var selectedName: String {
        model.catalog.drink(id: drinkID)?.displayName ?? Phrasebook.genericDrink(.current)
    }

    private var summaryText: String {
        selectedName + ", " + VolumeText.short(volumeML)
    }

    private var drinkGrid: some View {
        LazyVGrid(columns: Self.columns, spacing: 10) {
            ForEach(model.catalog.activeDrinks) { drink in
                LogDrinkChoice(drink: drink, isSelected: drink.id == drinkID, action: { select(drink) })
            }
        }
        .padding(.vertical, 6)
    }

    private var logBar: some View {
        VStack(spacing: 8) {
            Text(verbatim: summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                log()
            } label: {
                Text("Log")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func select(_ drink: Drink) {
        drinkID = drink.id
        volumeML = drink.defaultVolumeML
    }

    private func log() {
        let id = drinkID
        let ml = NutrientMath.clampVolume(volumeML)
        dismiss()
        Task { await model.log(drinkID: id, volumeML: ml) }
    }
}

private struct LogDrinkChoice: View {
    let drink: Drink
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: drink.symbol)
                    .font(.title2)
                    .foregroundStyle(drink.tint.color)
                Text(verbatim: drink.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .padding(6)
            .background(drink.tint.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? drink.tint.color : Color.clear, lineWidth: 2.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Volume chips 150…1000 ml plus a ±10 ml stepper (10…5000). Shared with PresetEditorView.
struct VolumeChipsPicker: View {
    @Binding var volumeML: Int

    init(volumeML: Binding<Int>) {
        _volumeML = volumeML
    }

    static let chips: [Int] = [150, 200, 250, 330, 500, 750, 1000]
    private static let columns: [GridItem] = [GridItem(.adaptive(minimum: 72), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Self.chips, id: \.self) { ml in
                    chip(ml)
                }
            }
            Stepper(value: $volumeML, in: NutrientMath.volumeRange, step: 10) {
                Text(verbatim: VolumeText.short(volumeML))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
    }

    private func chip(_ ml: Int) -> some View {
        let selected: Bool = ml == volumeML
        return Button {
            volumeML = ml
        } label: {
            Text(verbatim: VolumeText.short(ml))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
