import UIKit
import Combine
import SwiftUI

/// Owns only the terminal prompt's responder. Keyboard insets remain owned by
/// the system, including the existing Duo layout beside the hinge.
@MainActor
final class TerminalKeyboardController: ObservableObject {
    @Published private(set) var isFocused = false
    private weak var field: UITextField?
    private var wantsFocus = false

    var hasFirstResponder: Bool { field?.isFirstResponder == true }

    func toggle() {
        if isFocused || wantsFocus { dismiss() }
        else { focus() }
    }

    func focus() {
        wantsFocus = true
        guard let field else { return }
        focusWhenAttached(field)
    }

    func dismiss() {
        wantsFocus = false
        // Run during the button action, before SwiftUI starts another layout
        // transaction, so the system restores the workspace's full safe area.
        field?.resignFirstResponder()
    }

    func attach(_ field: UITextField) {
        self.field = field
    }

    func insert(_ text: String) {
        field?.insertText(text)
        field?.sendActions(for: .editingChanged)
        focus()
    }

    func moveCursor(by offset: Int) {
        guard let field, let selected = field.selectedTextRange,
              let position = field.position(from: offset < 0 ? selected.start : selected.end, offset: offset),
              let range = field.textRange(from: position, to: position) else { return }
        field.selectedTextRange = range
    }

    func detach(_ field: UITextField) {
        guard self.field === field else { return }
        self.field = nil
        wantsFocus = false
        field.resignFirstResponder()
        synchronizeFocus()
    }

    func focusWhenAttached(_ field: UITextField) {
        // Switching away from Code removes its first responder in this run
        // loop. Recheck the latest request so Hide or a tab switch cancels any
        // queued focus rather than bringing the keyboard straight back.
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.field === field,
                  self.wantsFocus, field.window != nil,
                  !field.isFirstResponder else { return }
            field.becomeFirstResponder()
        }
    }

    func didBeginEditing(_ field: UITextField) {
        guard self.field === field else { return }
        wantsFocus = true
        synchronizeFocus()
    }

    func didEndEditing(_ field: UITextField) {
        guard self.field === field else { return }
        wantsFocus = false
        synchronizeFocus()
    }

    private func synchronizeFocus() {
        // UIKit can end editing while SwiftUI dismantles a tab. Publish after
        // that update, and read the current field so an older callback cannot
        // overwrite the state of a newly mounted terminal.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let focused = self.field?.isFirstResponder == true
            if self.isFocused != focused { self.isFocused = focused }
        }
    }
}

final class TerminalTextField: UITextField {
    weak var keyboardController: TerminalKeyboardController?
    var terminalAccessory: UIView?

    @discardableResult override func becomeFirstResponder() -> Bool {
        inputAccessoryView = terminalAccessory
        return super.becomeFirstResponder()
    }

    @discardableResult override func resignFirstResponder() -> Bool {
        guard isFirstResponder else { return super.resignFirstResponder() }
        inputAccessoryView = nil
        reloadInputViews()
        let resigned = super.resignFirstResponder()
        if !resigned { inputAccessoryView = terminalAccessory; reloadInputViews() }
        return resigned
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { keyboardController?.focusWhenAttached(self) }
    }
}

/// Owns the terminal's accessory on its actual responder, including on iPhone
/// where the workspace dock is hidden while the software keyboard is visible.
struct TerminalPrompt: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let keyboard: TerminalKeyboardController
    let onSubmit: () -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onStop: () -> Void

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: TerminalPrompt
        init(_ parent: TerminalPrompt) { self.parent = parent }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool { parent.onSubmit(); return false }
        func textFieldDidBeginEditing(_ textField: UITextField) { parent.keyboard.didBeginEditing(textField) }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.keyboard.didEndEditing(textField) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> TerminalTextField {
        let field = TerminalTextField()
        field.keyboardController = keyboard
        field.delegate = context.coordinator
        field.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        field.textColor = UIColor(AppTheme.primary)
        field.tintColor = UIColor(AppTheme.blue)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .go
        field.accessibilityLabel = "Terminal command"
        field.accessibilityIdentifier = "terminal-field"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let control = KeyboardShortcutAccessoryView.key(title: "Ctrl-C", label: "Stop terminal command",
            identifier: "terminal-key-stop", tint: .systemRed) { [weak coordinator = context.coordinator] in coordinator?.parent.onStop() }
        var keys = [
            KeyboardShortcutAccessoryView.key(title: "↑", label: "Previous command", identifier: "terminal-key-previous") { [weak coordinator = context.coordinator] in coordinator?.parent.onPrevious() },
            KeyboardShortcutAccessoryView.key(title: "↓", label: "Next command", identifier: "terminal-key-next") { [weak coordinator = context.coordinator] in coordinator?.parent.onNext() },
            KeyboardShortcutAccessoryView.key(title: "←", label: "Move cursor left", identifier: "terminal-key-left") { [weak keyboard] in keyboard?.moveCursor(by: -1) },
            KeyboardShortcutAccessoryView.key(title: "→", label: "Move cursor right", identifier: "terminal-key-right") { [weak keyboard] in keyboard?.moveCursor(by: 1) },
        ]
        for symbol in ["/", "-", "~", "|", "&", ";", ">", "<", "$", "\"", "'", "\\", "=", "(", ")", "[", "]", "{", "}", "_", ".", ":", "*", "?", "`"] {
            keys.append(KeyboardShortcutAccessoryView.key(title: symbol, identifier: "terminal-key-" + symbol) { [weak keyboard] in keyboard?.insert(symbol) })
        }
        let hide = KeyboardShortcutAccessoryView.key(image: "keyboard.chevron.compact.down",
            label: "Hide terminal keyboard", identifier: "terminal-keyboard-hide", tint: .systemBlue) { [weak keyboard] in keyboard?.dismiss() }
        field.terminalAccessory = KeyboardShortcutAccessoryView(leading: [control], shortcuts: keys,
            hide: hide, identifier: "terminal-keyboard-accessory")
        field.inputAccessoryView = field.terminalAccessory
        keyboard.attach(field)
        return field
    }

    func updateUIView(_ field: TerminalTextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.placeholder = placeholder
        field.textColor = UIColor(AppTheme.primary)
        field.tintColor = UIColor(AppTheme.blue)
    }

    static func dismantleUIView(_ field: TerminalTextField, coordinator: Coordinator) {
        coordinator.parent.keyboard.detach(field)
    }
}
