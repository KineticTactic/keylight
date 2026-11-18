import SwiftUI

extension RGB {
    var displayColor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent)
    }
}

struct KeyboardThumbnail: View {
    let color: (Key) -> Color

    var body: some View {
        Canvas { context, size in
            let unit = size.width / Board.width
            for key in Board.keys {
                let rect = CGRect(x: key.x * unit, y: (size.height - Board.height * unit) / 2 + key.y * unit,
                                  width: key.width * unit - 0.45, height: unit - 0.45)
                context.fill(Path(roundedRect: rect, cornerRadius: 0.35), with: .color(color(key)))
            }
        }
        .accessibilityHidden(true)
    }
}

struct KeyboardPreview: View {
    let colors: [RGB]
    var mask: Set<Int>? = nil
    var editable = false
    var select: (Int) -> Void = { _ in }

    var body: some View {
        GeometryReader { geometry in
            let unit = min(geometry.size.width / Board.width, geometry.size.height / Board.height)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    for key in Board.keys {
                        let color = colors[key.id]
                        let included = mask?.contains(key.id) ?? true
                        let inset = max(1, unit * 0.045)
                        let rect = CGRect(x: key.x * unit, y: key.y * unit, width: key.width * unit, height: unit)
                            .insetBy(dx: inset, dy: inset)
                        let radius = key.id == 81 ? rect.height / 2 : unit * 0.13
                        let path = Path(roundedRect: rect, cornerRadius: radius)
                        // A charcoal floor keeps silent keys visible against the workspace.
                        let face = RGB(r: max(0.13, color.r), g: max(0.13, color.g), b: max(0.15, color.b))
                        let fill = included ? face : RGB(r: 0.10, g: 0.10, b: 0.12).mix(face, 0.10)
                        ctx.fill(path, with: .color(fill.displayColor))
                        if editable && included {
                            ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                        }

                        func linear(_ value: Double) -> Double {
                            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                        }
                        let luminance = 0.2126 * linear(fill.r) + 0.7152 * linear(fill.g) + 0.0722 * linear(fill.b)
                        let legend: Color = included ? (luminance > 0.179 ? .black : .white) : .gray
                        let title = Text(key.label).font(.system(size: max(8, unit * 0.25), weight: .medium))
                            .foregroundColor(legend)
                        ctx.draw(title, at: CGPoint(x: rect.midX, y: rect.midY))
                    }
                }
                if editable {
                    ForEach(Board.keys) { key in
                        Button { select(key.id) } label: { Color.clear.contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel(key.label)
                            .accessibilityValue((mask?.contains(key.id) ?? true) ? "Selected" : "Unselected")
                            .frame(width: unit * key.width, height: unit)
                            .position(x: unit * (key.x + key.width / 2), y: unit * (key.y + 0.5))
                    }
                }
            }
        }
        .aspectRatio(Board.width / Board.height, contentMode: .fit)
        .padding(14)
        .background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .strokeBorder(.white.opacity(0.19), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel("Core75 lighting preview")
    }
}
