import AppKit
import SwiftUI

struct PanelButton: View {
    let title: String
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

    var body: some View {
        NativeButton(configuration: self)
            .disabled(!isEnabled)
            .overlay {
                if !isEnabled {
                    // Block background dragging over disabled buttons.
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0))
                        .disabled(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private struct NativeButton: NSViewRepresentable {
        let configuration: PanelButton

        func makeNSView(context: Context) -> ActionButton {
            let button = ActionButton()
            button.cell = ActionButtonCell(textCell: "")
            button.bezelStyle = .rounded
            button.imagePosition = .noImage
            button.setButtonType(.momentaryPushIn)
            button.target = button
            button.action = #selector(ActionButton.activate(_:))
            updateNSView(button, context: context)
            return button
        }

        func updateNSView(_ button: ActionButton, context: Context) {
            button.isEnabled = configuration.isEnabled && context.environment.isEnabled
            button.controlSize = configuration.isSmall ? .small : .regular
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: button.controlSize))
            button.font = font
            let textColor: NSColor = button.isEnabled
                ? (configuration.isPrimary ? .alternateSelectedControlTextColor : .controlTextColor)
                : .disabledControlTextColor
            let label = NSMutableAttributedString(string: configuration.title, attributes: [.font: font, .foregroundColor: textColor])
            if let hint = configuration.shortcut?.label ?? configuration.keyHint {
                let color: NSColor = button.isEnabled
                    ? (configuration.isPrimary ? textColor.withAlphaComponent(0.5) : .tertiaryLabelColor)
                    : .disabledControlTextColor.withAlphaComponent(0.15)
                label.append(NSAttributedString(string: " " + hint, attributes: [
                    .font: NSFont.systemFont(ofSize: font.pointSize - 2),
                    .foregroundColor: color,
                ]))
            }
            button.attributedTitle = label
            button.keyEquivalent = configuration.shortcut?.keyEquivalent ?? ""
            button.keyEquivalentModifierMask = configuration.shortcut?.modifiers ?? []
            button.setAccessibilityLabel(configuration.title)
            button.setAccessibilityHelp(configuration.shortcut.map { "Keyboard shortcut: " + $0.label })
            button.bezelColor = configuration.isPrimary && button.isEnabled ? .controlAccentColor : nil
            button.onFocus = configuration.onFocus
            button.onActivate = configuration.action
            let focusChanged = button.wantsFocus != configuration.isFocused || button.prefersInitialFocus != configuration.prefersInitialFocus
            button.wantsFocus = configuration.isFocused
            button.prefersInitialFocus = configuration.prefersInitialFocus
            button.identifier = configuration.identifier.map { NSUserInterfaceItemIdentifier($0) }
            if focusChanged { button.focusIfNeeded() }
        }

        func sizeThatFits(_ proposal: ProposedViewSize, nsView: ActionButton, context: Context) -> CGSize? {
            nsView.intrinsicContentSize
        }
    }

    final class ActionButtonCell: NSButtonCell {
        override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
            // Draw the attributed text directly so AppKit preserves each range's color.
            let size = attributedTitle.size()
            let bounds = NSRect(
                x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                width: size.width, height: size.height
            )
            attributedTitle.draw(in: bounds)
            return bounds
        }
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
