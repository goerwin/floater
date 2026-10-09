import AppKit
import SwiftUI

struct MultilineInput: View {
    @Binding var text: String
    let placeholder: String
    let label: String
    let isFocused: Bool
    let onFocus: () -> Void
    let onMoveFocus: (Bool) -> Void
    let onSubmit: () -> Void

    var body: some View {
        NativeInput(
            text: $text,
            label: label,
            isFocused: isFocused,
            onFocus: onFocus,
            onMoveFocus: onMoveFocus,
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
    let onFocus: () -> Void
    let onMoveFocus: (Bool) -> Void
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
        view.onMoveFocus = onMoveFocus
        view.onSubmit = onSubmit
        view.wantsFocus = isFocused
        view.focusIfNeeded()
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
    var onFocus: (() -> Void)?
    var onMoveFocus: ((Bool) -> Void)?
    var onSubmit: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfNeeded()
    }

    func focusIfNeeded() {
        guard wantsFocus, let window, window.firstResponder !== self else { return }
        window.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if event.keyCode == 48, modifiers.subtracting(.shift).isEmpty {
            onMoveFocus?(modifiers.contains(.shift))
        } else if event.keyCode == 36 || event.keyCode == 76 {
            if modifiers == .shift {
                insertNewline(nil)
            } else if modifiers.isEmpty || modifiers == .command {
                onSubmit?()
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}
