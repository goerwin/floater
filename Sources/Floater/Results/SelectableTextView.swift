import AppKit

final class SelectableTextView: NSTextView {
    init(style: ReadingTextStyle) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        isEditable = false
        isRichText = false
        drawsBackground = false
        font = style.font
        defaultParagraphStyle = style.paragraphStyle
        textColor = .labelColor
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainer?.widthTracksTextView = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func update(_ text: String) -> Bool {
        guard string != text, let storage = textStorage else { return false }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? ReadingTextStyle.body.font, .foregroundColor: textColor ?? NSColor.labelColor,
            .paragraphStyle: defaultParagraphStyle ?? NSParagraphStyle.default,
        ]
        if !string.isEmpty, text.hasPrefix(string) {
            storage.append(NSAttributedString(string: (text as NSString).substring(from: storage.length), attributes: attributes))
        } else {
            storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
        }
        return true
    }

    func measuredSize(width: CGFloat) -> NSSize {
        guard let container = textContainer, let layout = layoutManager else { return NSSize(width: width, height: 18) }
        if frame.width != width { setFrameSize(NSSize(width: width, height: frame.height)) }
        container.containerSize = NSSize(width: max(1, width - textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        return NSSize(
            width: ceil(used.width) + textContainerInset.width * 2,
            height: ceil(max(used.maxY, layout.extraLineFragmentRect.maxY)) + textContainerInset.height * 2
        )
    }
}
