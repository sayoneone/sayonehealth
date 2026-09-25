import Foundation
import SwiftUI
import SayoneCore

/// Edits a drink (built-ins: everything except the name) or creates a custom drink.
struct DrinkEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let original: Drink?
    @State private var name: String
    @State private var symbol: String
    @State private var tint: DrinkTint
    @State private var hydrationPercent: Double
    @State private var caffeineText: String
    @State private var energyText: String
    @State private var sugarText: String
    @State private var defaultVolume: Int
    @State private var addButton: Bool = true
    @State private var confirmArchive: Bool = false

    init(drink: Drink?) {
        original = drink
        _name = State(initialValue: drink?.customName ?? "")
        _symbol = State(initialValue: drink?.symbol ?? DrinkEditorView.newDrinkSymbol)
        _tint = State(initialValue: drink?.tint ?? DrinkTint.purple)
        _hydrationPercent = State(initialValue: ((drink?.hydrationFactor ?? 1.0) * 100).rounded())
        _caffeineText = State(initialValue: DrinkEditorView.text(drink?.per100ML.caffeineMG ?? 0))
        _energyText = State(initialValue: DrinkEditorView.text(drink?.per100ML.energyKcal ?? 0))
        _sugarText = State(initialValue: DrinkEditorView.text(drink?.per100ML.sugarG ?? 0))
        _defaultVolume = State(initialValue: drink?.defaultVolumeML ?? 330)
    }

    private static let newDrinkSymbol: String = "takeoutbag.and.cup.and.straw.fill"
    private static let symbolColumns: [GridItem] = [GridItem(.adaptive(minimum: 44), spacing: 10)]
    private static let tintColumns: [GridItem] = [GridItem(.adaptive(minimum: 34), spacing: 10)]

    var body: some View {
        Form {
            nameSection
            symbolSection
            colorSection
            hydrationSection
            nutrientsSection
            volumeSection
            if isNew {
                addButtonSection
            }
            if canArchive {
                archiveSection
            }
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .confirmationDialog("Archive this drink?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive", role: .destructive) { archive() }
        } message: {
            Text("Its buttons will be removed. Past entries stay in Health.")
        }
    }

    // MARK: - State helpers

    private var isNew: Bool { original == nil }
    private var isBuiltIn: Bool { original?.builtIn != nil }
    private var canArchive: Bool { original != nil && !isBuiltIn }

    private var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    private var canSave: Bool {
        isBuiltIn || !trimmedName.isEmpty
    }

    private var presetsFull: Bool {
        model.catalog.presets.count >= Catalog.maxPresets
    }

    private var titleText: Text {
        if let drink = original {
            return Text(verbatim: drink.displayName)
        }
        return Text("Custom drink")
    }

    private var symbolChoices: [String] {
        let base = BuiltInCatalog.customSymbols
        if let current = original?.symbol, !base.contains(current) {
            return [current] + base
        }
        return base
    }

    private var hydrationText: String {
        (hydrationPercent / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section {
            if isBuiltIn {
                Text(verbatim: original?.displayName ?? "")
                    .foregroundStyle(.secondary)
            } else {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.sentences)
            }
        } header: {
            Text("Name")
        } footer: {
            if isBuiltIn {
                Text("Built-in drink names cannot be changed.")
            }
        }
    }

    private var symbolSection: some View {
        Section {
            LazyVGrid(columns: Self.symbolColumns, spacing: 10) {
                ForEach(symbolChoices, id: \.self) { s in
                    symbolButton(s)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Symbol")
        }
    }

    private var colorSection: some View {
        Section {
            LazyVGrid(columns: Self.tintColumns, spacing: 10) {
                ForEach(DrinkTint.allCases, id: \.self) { t in
                    tintButton(t)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Color")
        }
    }

    private var hydrationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Counts as water")
                    Spacer()
                    Text(verbatim: hydrationText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $hydrationPercent, in: 10...100, step: 5)
            }
        } footer: {
            Text("Share of the volume saved to Health as water.")
        }
    }

    private var nutrientsSection: some View {
        Section {
            nutrientField("Caffeine, mg per 100 ml", text: $caffeineText)
            nutrientField("Calories, kcal per 100 ml", text: $energyText)
            nutrientField("Sugar, g per 100 ml", text: $sugarText)
        } footer: {
            Text("Values are approximate and can be edited.")
        }
    }

    private var volumeSection: some View {
        Section {
            Stepper(value: $defaultVolume, in: NutrientMath.volumeRange, step: 10) {
                HStack {
                    Text("Default volume")
                    Spacer()
                    Text(verbatim: VolumeText.short(defaultVolume))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var addButtonSection: some View {
        Section {
            Toggle("Add a drink button", isOn: presetsFull ? .constant(false) : $addButton)
                .disabled(presetsFull)
        } footer: {
            if presetsFull {
                Text("Up to 12 buttons")
            }
        }
    }

    private var archiveSection: some View {
        Section {
            Button("Archive", role: .destructive) {
                confirmArchive = true
            }
        }
    }

    // MARK: - Row builders

    private func nutrientField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        LabeledContent {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        } label: {
            Text(title)
        }
    }

    private func symbolButton(_ s: String) -> some View {
        let selected: Bool = s == symbol
        return Button {
            symbol = s
        } label: {
            Image(systemName: s)
                .font(.title3)
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? Color.white : tint.color)
                .background(selected ? tint.color : tint.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func tintButton(_ t: DrinkTint) -> some View {
        let selected: Bool = t == tint
        return Button {
            tint = t
        } label: {
            Circle()
                .fill(t.color)
                .frame(width: 32, height: 32)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(DrinkEditorView.tintName(t)))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Actions

    private func save() {
        let per100 = NutrientsPer100ML(caffeineMG: Self.parse(caffeineText),
                                       energyKcal: Self.parse(energyText),
                                       sugarG: Self.parse(sugarText))
        let factor: Double = NutrientMath.clampHydration(hydrationPercent / 100)
        let volume: Int = NutrientMath.clampVolume(defaultVolume)
        let chosenSymbol: String = symbol
        let chosenTint: DrinkTint = tint

        if let drink = original {
            var updated = drink
            if drink.builtIn == nil {
                updated.customName = trimmedName
            }
            updated.symbol = chosenSymbol
            updated.tint = chosenTint
            updated.hydrationFactor = factor
            updated.per100ML = per100
            updated.defaultVolumeML = volume
            let edited: Drink = updated
            model.edit { CatalogEditor.updateDrink(in: &$0, edited) }
        } else {
            let newName: String = trimmedName
            let wantsButton: Bool = addButton && !presetsFull
            model.edit { c in
                let created = CatalogEditor.addCustomDrink(to: &c, name: newName, symbol: chosenSymbol, tint: chosenTint,
                                                           hydrationFactor: factor, per100ML: per100, defaultVolumeML: volume)
                if wantsButton {
                    _ = CatalogEditor.addPreset(to: &c, drinkID: created.id, volumeML: created.defaultVolumeML)
                }
            }
        }
        dismiss()
    }

    private func archive() {
        guard let drink = original else { return }
        let id: String = drink.id
        model.edit { CatalogEditor.archiveDrink(in: &$0, id: id) }
        dismiss()
    }

    // MARK: - Number text

    /// Locale-aware, no grouping, up to 2 fraction digits; empty for zero so the "0" placeholder shows.
    private static func text(_ value: Double) -> String {
        if value == 0 { return "" }
        return value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    /// Accepts "9,6" and "9.6"; anything unparsable or negative becomes 0.
    private static func parse(_ text: String) -> Double {
        let cleaned = text
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0 else { return 0 }
        return min(value, 10_000)
    }

    static func tintName(_ t: DrinkTint) -> LocalizedStringKey {
        switch t {
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .brown: return "Brown"
        case .red: return "Red"
        case .orange: return "Orange"
        case .green: return "Green"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }
}
