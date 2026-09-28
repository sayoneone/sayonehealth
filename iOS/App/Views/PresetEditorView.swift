import Foundation
import SwiftUI
import SayoneCore

/// Edits one drink button (drink + volume) or creates a new one. Works pushed or inside a sheet's NavigationStack.
struct PresetEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private let original: Preset?
    @State private var drinkID: String
    @State private var volumeML: Int

    init(preset: Preset?) {
        original = preset
        _drinkID = State(initialValue: preset?.drinkID ?? BuiltInCatalog.fallbackDrinkID)
        _volumeML = State(initialValue: preset?.volumeML ?? 250)
    }

    var body: some View {
        Form {
            drinkSection
            volumeSection
            if original != nil {
                deleteSection
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
        .onChange(of: drinkID) { _, newID in
            applyDefaultVolume(for: newID)
        }
    }

    private var isNew: Bool { original == nil }

    private var titleText: Text {
        isNew ? Text("New button") : Text("Drink Button")
    }

    private var drinks: [Drink] {
        model.catalog.activeDrinks
    }

    private var canSave: Bool {
        guard model.catalog.drink(id: drinkID) != nil else { return false }
        return !isNew || model.catalog.presets.count < Catalog.maxPresets
    }

    private var drinkSection: some View {
        Section {
            Picker("Drink", selection: $drinkID) {
                ForEach(drinks) { drink in
                    Label {
                        Text(verbatim: drink.displayName)
                    } icon: {
                        Image(systemName: drink.symbol)
                    }
                    .tag(drink.id)
                }
            }
        } footer: {
            if isNew && !canSave {
                Text("Up to 12 buttons")
            }
        }
    }

    private var volumeSection: some View {
        Section {
            VolumeChipsPicker(volumeML: $volumeML)
        } header: {
            Text("Volume")
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete", role: .destructive) {
                delete()
            }
        }
    }

    /// New buttons follow the chosen drink's default volume; existing buttons keep their volume.
    private func applyDefaultVolume(for id: String) {
        guard isNew, let drink = model.catalog.drink(id: id) else { return }
        volumeML = drink.defaultVolumeML
    }

    private func save() {
        let id: String = drinkID
        let ml: Int = NutrientMath.clampVolume(volumeML)
        if let preset = original {
            let updated = Preset(id: preset.id, drinkID: id, volumeML: ml)
            model.edit { CatalogEditor.updatePreset(in: &$0, updated) }
        } else {
            model.edit { _ = CatalogEditor.addPreset(to: &$0, drinkID: id, volumeML: ml) }
        }
        dismiss()
    }

    private func delete() {
        guard let preset = original else { return }
        let id: String = preset.id
        model.edit { CatalogEditor.removePreset(from: &$0, id: id) }
        dismiss()
    }
}
