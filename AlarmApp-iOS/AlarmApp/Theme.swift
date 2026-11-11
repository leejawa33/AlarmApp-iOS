import SwiftUI

/// 기획서 디자인 토큰 (Phase 1 라이트 고정)
enum Theme {
    static let bg = Color(hex: 0xFFF8F0)
    static let bgDeep = Color(hex: 0xFFE8D6)
    static let sun = Color(hex: 0xFFC107)
    static let sunDeep = Color(hex: 0xFFB300)
    static let cta = Color(hex: 0xFF5A5F)
    static let ctaPress = Color(hex: 0xE8454A)
    static let text = Color(hex: 0x1A1A1A)
    static let textMuted = Color(hex: 0x6B6560)
    static let line = Color(hex: 0x1A1A1A).opacity(0.08)
    static let chipOn = Color(hex: 0xFFF3CD)
    static let chipOff = Color(hex: 0xF3EEE8)
    static let dayOff = Color(hex: 0xEEE7DF)

    /// SF Rounded 볼드 계열
    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
