#if canImport(SwiftUI)
import FaceEngine
import SwiftUI

/// Resolves the engine's semantic paints to real colours.
///
/// Both themes are built from the same table the SVG exporter uses, so a still
/// exported from the app matches what is on screen.
public struct CatPalette: Sendable {
    public var table: PaintTable

    public init(table: PaintTable) {
        self.table = table
    }

    public static let light = CatPalette(table: .light)
    public static let dark = CatPalette(table: .dark)

    public static func forScheme(_ scheme: ColorScheme) -> CatPalette {
        scheme == .dark ? .dark : .light
    }

    public func color(_ paint: Paint) -> Color {
        Color(hex: table[paint])
    }

    public var background: Color { Color(hex: table.background) }
}

extension Color {
    /// Parses `#RRGGBB`. Falls back to a visible magenta rather than clear, so a
    /// bad token shows up instead of silently disappearing.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = Color(red: 1, green: 0, blue: 1)
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
#endif
