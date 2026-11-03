import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: alpha
        )
    }
}

enum AmigoColors {
    // Brand & Theme
    static let primary = Color(hex: 0x0F172A)
    static let primaryDark = Color(hex: 0x020617)
    static let accent = Color(hex: 0x2563EB)

    // Surfaces & Backgrounds
    static let background = Color(hex: 0xF1F5F9)
    static let cardBg = Color(hex: 0xFFFFFF)
    static let cardStroke = Color(hex: 0xCBD5E1)
    static let inputBg = Color(hex: 0xF8FAFC)

    // High-Contrast Typography
    static let textPrimary = Color(hex: 0x0F172A)
    static let textSecondary = Color(hex: 0x475569)
    static let textMuted = Color(hex: 0x64748B)
    static let textWhite = Color(hex: 0xFFFFFF)

    // State & Alert Colors
    static let stateGreen = Color(hex: 0x16A34A)
    static let stateGreenBg = Color(hex: 0xDCFCE7)
    static let stateBlue = Color(hex: 0x2563EB)
    static let stateBlueBg = Color(hex: 0xDBEAFE)
    static let stateRed = Color(hex: 0xDC2626)
    static let stateRedBg = Color(hex: 0xFEE2E2)
    static let stateAmber = Color(hex: 0xD97706)
    static let stateAmberBg = Color(hex: 0xFEF3C7)
    static let stateGray = Color(hex: 0x64748B)
    static let stateGrayBg = Color(hex: 0xE2E8F0)

    // Terminal Log
    static let logBg = Color(hex: 0x090D16)
    static let logText = Color(hex: 0x38BDF8)
}

