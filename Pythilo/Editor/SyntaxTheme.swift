import SwiftUI
import UIKit

/// Token colours, shared by the editor and by every code sample in a lesson.
enum SyntaxTheme {
    static var background: Color { AppTheme.editor }

    static func uiColor(for kind: SyntaxTokenKind) -> UIColor {
        switch kind {
        case .comment: dynamic(light: 0x55606E, dark: 0x8593A3)
        case .string: dynamic(light: 0x0A7A57, dark: 0x7BDCB5)
        case .keyword, .section: dynamic(light: 0x8A5A00, dark: 0xFFC94D)
        case .type, .key, .macro: dynamic(light: 0x0B62C4, dark: 0x6CB6FF)
        case .number: dynamic(light: 0xA3480A, dark: 0xF2A65A)
        case .attribute: dynamic(light: 0x6D3FC4, dark: 0xC4A5FF)
        }
    }

    static func color(for kind: SyntaxTokenKind) -> Color {
        Color(uiColor: uiColor(for: kind))
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}
