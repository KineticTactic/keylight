import SwiftUI

struct LayerStackRow: View {
    static let height: CGFloat = 49

    let layer: Layer
    let selected: Bool
    let select: () -> Void

    private var coverage: String {
        guard let keys = layer.keys else { return "All keys" }
        if keys == Board.perimeter { return "Perimeter" }
        if keys == Board.numberRow { return "Number row" }
        if keys == Board.interior { return "Interior" }
        if keys.isEmpty { return "No keys" }
        return keys.count == 1 ? "1 key" : "\(keys.count) keys"
    }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 11) {
                KeyboardThumbnail { key in
                    let included = layer.keys?.contains(key.id) ?? true
                    let ink = layer.effect.usesScreen ? Color.white : layer.color.mix(RGB(r: 1, g: 1, b: 1), 0.20).displayColor
                    return included ? ink : Color(white: 0.22)
                }
                .padding(4).frame(width: 66, height: 32)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 5))

                VStack(alignment: .leading, spacing: 1) {
                    Text(layer.effect.rawValue).font(.callout.weight(.semibold))
                    Text(coverage).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Text(layer.opacity, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Layer opacity")
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(StudioStyle.lilac).opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: Self.height)
            .background(selected ? StudioStyle.lilac.opacity(0.14) : .clear)
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(StudioStyle.lilac).frame(width: 3).padding(.vertical, 8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layer.effect.rawValue)
        .accessibilityValue("\(coverage), \(layer.opacity.formatted(.percent)) opacity")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
