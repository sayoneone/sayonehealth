import Foundation
import SwiftUI
import SayoneCore

/// Drink buttons: reorder, delete, edit, add (max 12).
struct PresetsListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(model.catalog.presets) { preset in
                    NavigationLink {
                        PresetEditorView(preset: preset)
                    } label: {
                        PresetListRow(preset: preset, drink: model.catalog.drink(id: preset.drinkID))
                    }
                }
                .onMove { source, destination in
                    move(source, destination)
                }
                .onDelete { offsets in
                    delete(offsets)
                }
            } footer: {
                Text("The first 4 buttons appear in the Favorites widget, the first 3 on Apple Watch.")
            }
            Section {
                NavigationLink {
                    PresetEditorView(preset: nil)
                } label: {
                    Label("Add button", systemImage: "plus.circle.fill")
                }
                .disabled(isFull)
            } footer: {
                Text("Up to 12 buttons")
            }
        }
        .navigationTitle("Drink buttons")
        .toolbar {
            EditButton()
        }
    }

    private var isFull: Bool {
        model.catalog.presets.count >= Catalog.maxPresets
    }

    private func move(_ source: IndexSet, _ destination: Int) {
        model.edit { CatalogEditor.movePresets(in: &$0, from: source, to: destination) }
    }

    private func delete(_ offsets: IndexSet) {
        let presets = model.catalog.presets
        let ids: [String] = offsets.compactMap { index in
            index < presets.count ? presets[index].id : nil
        }
        guard !ids.isEmpty else { return }
        model.edit { c in
            for id in ids {
                CatalogEditor.removePreset(from: &c, id: id)
            }
        }
    }
}

private struct PresetListRow: View {
    let preset: Preset
    let drink: Drink?

    private var name: String {
        drink?.displayName ?? Phrasebook.genericDrink(.current)
    }

    private var symbol: String {
        drink?.symbol ?? "cup.and.saucer.fill"
    }

    private var tintColor: Color {
        drink?.tint.color ?? Color.gray
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tintColor)
                .frame(width: 28)
            Text(verbatim: name)
                .lineLimit(1)
            Spacer()
            Text(verbatim: VolumeText.short(preset.volumeML))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
