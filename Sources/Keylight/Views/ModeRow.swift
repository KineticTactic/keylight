import SwiftUI

struct ModeRow: View {
    let scene: LightingScene
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let mode = scene.factoryMode, let colors = FactoryMode.thumbnails[mode] {
                    KeyboardThumbnail { colors[$0.id].displayColor }
                    .padding(3).frame(width: 46, height: 26)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                } else {
                    Image(systemName: "square.3.layers.3d").frame(width: 46).foregroundStyle(StudioStyle.lilac)
                }
                Text(scene.name.isEmpty ? "Untitled mode" : scene.name)
                    .font(.callout.weight(selected ? .bold : .medium)).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background {
                if selected { Color.clear.opticalGlass(in: RoundedRectangle(cornerRadius: 11), tint: .purple.opacity(0.23)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
