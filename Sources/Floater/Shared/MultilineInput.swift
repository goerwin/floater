import AppKit
import SwiftUI

struct MultilineInput: View {
    @Binding var text: String
    let placeholder: String
    let label: String
    let isFocused: Bool
    var prefersInitialFocus = false
    var identifier: String?
    var visibleLineCount: Int?
    var trailingContentWidth: CGFloat = 0
    let onFocus: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        NativeInput(
            text: $text,
            label: label,
            isFocused: isFocused,
            prefersInitialFocus: prefersInitialFocus,
            identifier: identifier,
            visibleLineCount: visibleLineCount,
            trailingContentWidth: trailingContentWidth,
            onFocus: onFocus,
            onSubmit: onSubmit
        )
        .overlay(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: ReadingTextStyle.body.fontSize))
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
    let visibleLineCount: Int?
    let trailingContentWidth: CGFloat
    let onFocus: () -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(input: self)
    }

    func makeNSView(context: Context) -> InputScrollView {
        let scroll = InputScrollView()
        let view = InputTextView()
        view.delegate = context.coordinator
        view.isRichText = false
        view.allowsUndo = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.drawsBackground = false
        view.font = ReadingTextStyle.body.font
        view.defaultParagraphStyle = ReadingTextStyle.body.paragraphStyle
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.setAccessibilityLabel(label)
        view.autoresizingMask = [.width]
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: InputScrollView, context: Context) {
        context.coordinator.input = self
        guard let view = scroll.documentView as? InputTextView else { return }
        scroll.hasVerticalScroller = visibleLineCount != nil
        scroll.trailingContentWidth = trailingContentWidth
        view.textContainer?.widthTracksTextView = trailingContentWidth == 0
        if view.string != text {
            view.string = text
            scroll.resizeDocument()
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

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: InputScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? FloaterPanelLayout.contentWidth
        guard let view = nsView.documentView as? InputTextView,
              let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let lineHeight = ReadingTextStyle.body.lineHeight(using: layout)
        if let visibleLineCount {
            return CGSize(width: width, height: ceil(lineHeight * CGFloat(visibleLineCount)) + 16)
        }
        container.containerSize = NSSize(width: max(1, width - 16 - trailingContentWidth), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let textHeight = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
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
            (view.enclosingScrollView as? InputScrollView)?.resizeDocument()
            view.scrollRangeToVisible(view.selectedRange())
        }
    }
}

private final class InputScrollView: NSScrollView {
    var trailingContentWidth: CGFloat = 0

    override func layout() {
        super.layout()
        resizeDocument()
    }

    func resizeDocument() {
        guard contentSize.width > 0, let view = documentView as? NSTextView,
              let container = view.textContainer, let layout = view.layoutManager else { return }
        view.setFrameSize(NSSize(width: contentSize.width, height: view.frame.height))
        container.containerSize = NSSize(width: max(1, contentSize.width - 16 - trailingContentWidth), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = ceil(max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)) + 16
        view.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, height)))
        reflectScrolledClipView(contentView)
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
        if [36, 76].contains(event.keyCode), modifiers.isEmpty, !hasMarkedText() {
            onSubmit?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(sender)
    }
}
