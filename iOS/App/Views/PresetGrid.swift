import Foundation
import SwiftUI
import SayoneCore

/// Two-column grid of one-tap preset buttons. Long press: Edit / Delete.
struct PresetGrid: View {
    @EnvironmentObject private var model: AppModel
    let onEdit: (PresetDisplay) -> Void

    init(onEdit: @escaping (PresetDisplay) -> Void) {
        self.onEdit = onEdit
    }

    private static let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        if model.presets.isEmpty {
            Text("No drink buttons yet. Add them in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        } else {
            LazyVGrid(columns: Self.columns, spacing: 12) {
                ForEach(model.presets) { preset in
                    tile(for: preset)
                }
            }
        }
    }

    private func tile(for preset: PresetDisplay) -> some View {
        PresetGridTile(preset: preset, action: { log(preset) })
            .contextMenu {
                Button {
                    onEdit(preset)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    remove(preset)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func log(_ preset: PresetDisplay) {
        Task { await model.log(preset) }
    }

    private func remove(_ preset: PresetDisplay) {
        let id = preset.id
        model.edit { CatalogEditor.removePreset(from: &$0, id: id) }
    }
}

private struct PresetGridTile: View {
    let preset: PresetDisplay
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: preset.symbol)
                    .font(.title2)
                    .foregroundStyle(preset.tint.color)
                Text(verbatim: preset.drinkName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: VolumeText.plus(preset.volumeML))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(preset.tint.color)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(preset.tint.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PresetGridButtonStyle())
        .accessibilityLabel(Text(verbatim: preset.title))
    }
}

/// Custom style: gives press feedback and keeps each tile's tap separate inside a List row.
private struct PresetGridButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
