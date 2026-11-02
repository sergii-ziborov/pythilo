import SwiftUI
import UIKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// The colors from the design's token board. Yellow only ever means run; red
/// only ever means stop or error.
enum AppTheme {
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    static var background: Color { adaptive(light: 0xF5F7FA, dark: 0x0B1016) }
    static var editor: Color { adaptive(light: 0xF7F9FB, dark: 0x0B1016) }
    static var rail: Color { adaptive(light: 0xEEF2F6, dark: 0x0D141C) }
    static var panel: Color { adaptive(light: 0xFFFFFF, dark: 0x121922) }
    static var raised: Color { adaptive(light: 0xE8EDF3, dark: 0x1A2330) }
    static var border: Color { adaptive(light: 0xD5DCE5, dark: 0x232D3A) }
    static var primary: Color { adaptive(light: 0x141A22, dark: 0xF2F5F8) }
    static var secondary: Color { adaptive(light: 0x3D4753, dark: 0xC9D2DC) }
    static var muted: Color { adaptive(light: 0x55606E, dark: 0x9AA6B4) }
    static var blue: Color { adaptive(light: 0x0B62C4, dark: 0x5AA9FF) }
    static var selection: Color { adaptive(light: 0xDCEAFB, dark: 0x16263A) }
    static var selectionInk: Color { adaptive(light: 0x0B62C4, dark: 0x8CC4FF) }
    static var mint: Color { adaptive(light: 0x0A7A57, dark: 0x5FD6A8) }
    static var amber: Color { adaptive(light: 0x8A5A00, dark: 0xF2C25A) }
    static var violet: Color { adaptive(light: 0x6D3FC4, dark: 0xB79CFF) }
    static var coral: Color { adaptive(light: 0xC22A22, dark: 0xFF7A70) }
    static var coralInk: Color { adaptive(light: 0xA3201A, dark: 0xFF9A92) }
    static var coralFill: Color { adaptive(light: 0xFBE9E7, dark: 0x2A1A1C) }
    static var dangerPanel: Color { adaptive(light: 0xFBE9E7, dark: 0x241618) }
    static var dangerBorder: Color { adaptive(light: 0xE8B4AF, dark: 0x6B3338) }
    static var warnPanel: Color { adaptive(light: 0xFBF3DC, dark: 0x1D1A0E) }
    static let run = Color(uiColor: UIColor(hex: 0xFFD43B))
    static let onRun = Color(uiColor: UIColor(hex: 0x14110A))
    static var onBlue: Color { adaptive(light: 0xFFFFFF, dark: 0x07121F) }

    static let mono = Font.system(size: 13, design: .monospaced)
}

extension View {
    func panelCard(cornerRadius: CGFloat = 14) -> some View {
        background(AppTheme.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(AppTheme.border, lineWidth: 1) }
    }

    func sectionLabel() -> some View {
        font(.system(size: 12, weight: .bold)).kerning(0.7).foregroundStyle(AppTheme.muted)
    }
}

/// The round toolbar control that sits beside the camera.
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = AppTheme.primary
    var fill: Color = AppTheme.raised
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
