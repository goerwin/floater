import AppKit
import SwiftUI

struct PanelButton: NSViewRepresentable {
    let title: String
    var symbol: String?
    var shortcut: PanelShortcut?
    var keyHint: String?
    var isEnabled = true
    var isPrimary = false
    var isSmall = false
    let isFocused: Bool
    var prefersInitialFocus = false
    var identifier: String?
    let onFocus: () -> Void
    let action: () -> Void

    func makeNSView(context: Context) -> ActionButton {
        let button = ActionButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(ActionButton.activate(_:))
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: ActionButton, context: Context) {
        button.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        button.imagePosition = symbol == nil ? .noImage : .imageLeading
        button.isEnabled = isEnabled && context.environment.isEnabled
        button.controlSize = isSmall ? .small : .regular
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: button.controlSize))
        button.font = font
        let label = NSMutableAttributedString(string: title, attributes: [.font: font])
        if let hint = shortcut?.label ?? keyHint {
            let color: NSColor = button.isEnabled
                ? (isPrimary ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.75) : .secondaryLabelColor)
                : .disabledControlTextColor
            label.append(NSAttributedString(string: " " + hint, attributes: [
                .font: NSFont.systemFont(ofSize: font.pointSize - 2),
                .foregroundColor: color,
            ]))
        }
        button.attributedTitle = label
        button.keyEquivalent = shortcut?.keyEquivalent ?? ""
        button.keyEquivalentModifierMask = shortcut?.modifiers ?? []
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(shortcut.map { "Keyboard shortcut: " + $0.label })
        button.bezelColor = isPrimary ? .controlAccentColor : nil
        button.onFocus = onFocus
        button.onActivate = action
        let focusChanged = button.wantsFocus != isFocused || button.prefersInitialFocus != prefersInitialFocus
        button.wantsFocus = isFocused
        button.prefersInitialFocus = prefersInitialFocus
        button.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
        if focusChanged { button.focusIfNeeded() }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ActionButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    final class ActionButton: NSButton {
        var onFocus: (() -> Void)?
        var onActivate: (() -> Void)?
        var wantsFocus = false
        var prefersInitialFocus = false

        override var acceptsFirstResponder: Bool { isEnabled }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusIfNeeded()
        }

        func focusIfNeeded() {
            guard let window else { return }
            if prefersInitialFocus { window.initialFirstResponder = self }
            if wantsFocus, isEnabled, window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window?.firstResponder === self else { return }
                    self.onFocus?()
                }
            }
            return accepted
        }

        override func keyDown(with event: NSEvent) {
            if !handleActivation(event) { super.keyDown(with: event) }
        }

        func handleActivation(_ event: NSEvent) -> Bool {
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            if isEnabled, modifiers.isEmpty, [36, 76, 49].contains(event.keyCode) {
                performClick(nil)
                return true
            }
            return false
        }

        @objc func activate(_ sender: Any?) {
            onActivate?()
        }
    }
}
