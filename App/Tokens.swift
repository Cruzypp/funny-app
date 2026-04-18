import SwiftUI

// MARK: - Hex color initializer
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: UInt64
        switch h.count {
        case 6: (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

// MARK: - Design tokens (mirrors tokens.jsx)
enum T {
    // Base surfaces
    static let ink   = Color(hex: "0F1420")
    static let ink2  = Color(hex: "1A2132")
    static let cream = Color(hex: "F7F4EE")
    static let paper = Color(hex: "FFFCF6")

    // Typography
    static let textPrimary   = Color(hex: "0F1420")
    static let textSecondary = Color(hex: "0F1420").opacity(0.62)

    // Safety — traffic-light palette
    static let safe     = Color(hex: "2E7D5B")
    static let safeTint = Color(hex: "D9ECDF")
    static let warn     = Color(hex: "C98A2B")
    static let warnTint = Color(hex: "F3E6C9")
    static let risk     = Color(hex: "C4452E")
    static let riskTint = Color(hex: "F1D5CD")

    // Brand accent — terracotta
    static let accent = Color(hex: "E07856")

    // Radii
    static let r1: CGFloat = 10
    static let r2: CGFloat = 16
    static let r3: CGFloat = 20
    static let r4: CGFloat = 28

    // Night-mode helpers
    static func bg(_ n: Bool) -> Color       { n ? ink   : cream }
    static func surface(_ n: Bool) -> Color  { n ? ink2  : paper }
    static func pri(_ n: Bool) -> Color      { n ? cream : textPrimary }
    static func sec(_ n: Bool) -> Color      { n ? cream.opacity(0.6) : textSecondary }
    static func line(_ n: Bool) -> Color     { n ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
}

// MARK: - Shadow modifier
extension View {
    func caminosCard(hi: Bool = false) -> some View {
        self
            .shadow(color: Color.black.opacity(hi ? 0.10 : 0.06), radius: hi ? 32 : 18, x: 0, y: hi ? 12 : 6)
            .shadow(color: Color.black.opacity(hi ? 0.06 : 0.04), radius: hi ?  4 :  2, x: 0, y: hi ?  2 : 1)
    }
}

// MARK: - Typography shortcuts
extension Font {
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let base = Font.system(size: size, weight: .light, design: .serif)
        return italic ? base.italic() : base
    }
    static func mono(_ size: CGFloat) -> Font {
        Font.system(size: size, design: .monospaced)
    }
}
