import SwiftUI

/// The digit-font chooser, inline in Settings. A pop-up menu covered the very
/// clock preview it was meant to drive and spilled outside the window; this
/// grid stays inside its card, shows each face on a sample, and reports the
/// hovered or arrowed-to font so the preview shows it before it's chosen.
struct FontGridPicker: View {
    @Binding var selection: WidgetFont
    /// The font being previewed, not chosen; `nil` hands the preview back to `selection`.
    @Binding var highlighted: WidgetFont?

    static let columns = 3
    private static let fonts = WidgetFont.all
    /// Decorative faces differ wildly at one point size, so every sample is
    /// sized to the same cap height instead.
    private static let sampleCapHeight: CGFloat = 15
    private static let cornerRadius: CGFloat = 9

    @FocusState private var focused: Bool
    /// Keyboard position; starts at the selection on the first arrow press.
    @State private var cursor: Int?

    static func moved(from index: Int, by key: KeyEquivalent, count: Int, columns: Int) -> Int {
        switch key {
        case .leftArrow: return max(index - 1, 0)
        case .rightArrow: return min(index + 1, count - 1)
        case .upArrow: return index >= columns ? index - columns : index
        case .downArrow: return min(index + columns, count - 1)
        default: return index
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: Self.columns), spacing: 8) {
                    ForEach(Array(Self.fonts.enumerated()), id: \.element.id) { index, font in
                        tile(font, index: index)
                    }
                }
                .padding(2)
                .padding(.bottom, 12)
            }
            .frame(height: 236)
            // Fades the cut-off row so the grid reads as scrollable, not clipped.
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20)
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                let start = cursor ?? Self.fonts.firstIndex(of: selection) ?? 0
                let next = Self.moved(from: start, by: press.key, count: Self.fonts.count, columns: Self.columns)
                cursor = next
                highlighted = Self.fonts[next]
                proxy.scrollTo(Self.fonts[next].id)
                return .handled
            }
            .onKeyPress(.return) {
                guard let cursor else { return .ignored }
                choose(Self.fonts[cursor])
                return .handled
            }
            .onHover { inside in
                if !inside { highlighted = focused ? cursor.map { Self.fonts[$0] } : nil }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { cursor = nil; highlighted = nil }
            }
            .onAppear { proxy.scrollTo(selection.id, anchor: .center) }
        }
    }

    private func tile(_ font: WidgetFont, index: Int) -> some View {
        let isSelected = font == selection
        let isLit = font == highlighted
        let isCursor = focused && cursor == index
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return Button { choose(font) } label: {
            VStack(spacing: 5) {
                Text("10:09")
                    .font(Font(Self.sampleFace(for: font)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: 30)
                Text(font.label)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 8)
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.14)
                                   : Color.primary.opacity(isLit ? 0.08 : 0.03)))
            .overlay(shape.strokeBorder(isSelected ? Color.accentColor
                                        : Color.accentColor.opacity(isCursor ? 0.6 : 0),
                                        lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = font } }
        .id(font.id)
        .help(font.label)
        .accessibilityLabel(font.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ font: WidgetFont) {
        selection = font
        cursor = Self.fonts.firstIndex(of: font)
        highlighted = nil
        focused = true
    }

    private static func sampleFace(for font: WidgetFont) -> NSFont {
        let reference: CGFloat = 20
        guard let name = font.postscriptName, let face = NSFont(name: name, size: reference), face.capHeight > 0 else {
            return .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        }
        let size = min(max(sampleCapHeight * reference / face.capHeight, 12), 30)
        return NSFont(name: name, size: size) ?? face
    }
}
