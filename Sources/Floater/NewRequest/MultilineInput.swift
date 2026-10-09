import AppKit
import SwiftUI

struct MultilineInput: View {
    @Binding var text: String
    let placeholder: String
    let label: String
    let isFocused: Bool
    var prefersInitialFocus = false
    var identifier: String?
    let onFocus: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        NativeInput(
            text: $text,
            label: label,
            isFocused: isFocused,
            prefersInitialFocus: prefersInitialFocus,
            identifier: identifier,
            onFocus: onFocus,
            onSubmit: onSubmit
        )
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(isFocused ? Color.accentColor : .secondary.opacity(0.3), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct NativeInput: NSViewRepresentable {
    @Binding var text: String
    let label: String
    let isFocused: Bool
    let prefersInitialFocus: Bool
    let identifier: String?
    let onFocus: () -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(input: self)
    }

    func makeNSView(context: Context) -> InputTextView {
        let view = InputTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.setAccessibilityLabel(label)
        return view
    }

    func updateNSView(_ view: InputTextView, context: Context) {
        context.coordinator.input = self
        if view.string != text {
            view.string = text
        }
        view.onFocus = onFocus
        view.onSubmit = onSubmit
        let focusChanged = view.wantsFocus != isFocused || view.prefersInitialFocus != prefersInitialFocus
        view.wantsFocus = isFocused
        view.prefersInitialFocus = prefersInitialFocus
        view.identifier = identifier.map { NSUserInterfaceItemIdentifier($0) }
        if focusChanged { view.focusIfNeeded() }
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InputTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? FloaterPanelLayout.contentWidth
        guard let container = nsView.textContainer, let layout = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(1, width - 16), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let textHeight = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        let lineHeight = layout.defaultLineHeight(for: nsView.font ?? .systemFont(ofSize: 13))
        return CGSize(width: width, height: ceil(max(lineHeight * 2, textHeight)) + 16)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var input: NativeInput

        init(input: NativeInput) {
            self.input = input
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            input.text = view.string
        }
    }
}

private final class InputTextView: NSTextView {
    var wantsFocus = false
    var prefersInitialFocus = false
    var onFocus: (() -> Void)?
    var onSubmit: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    func focusIfNeeded() {
        guard let window else { return }
        if prefersInitialFocus { window.initialFirstResponder = self }
        guard wantsFocus, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
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
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if event.keyCode == 48 {
            if modifiers.isEmpty || modifiers == .shift {
                insertTab(nil)
            } else {
                super.keyDown(with: event)
            }
        } else if event.keyCode == 36 || event.keyCode == 76 {
            if modifiers.isEmpty || modifiers == .shift {
                insertNewline(nil)
            } else if modifiers == .command {
                onSubmit?()
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
