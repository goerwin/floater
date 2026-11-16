import AppKit

final class SelectableTextView: NSTextView {
    private let readingStyle: ReadingTextStyle
    private var sourceText: String?
    private var rendersMarkdown = false

    init(style: ReadingTextStyle) {
        readingStyle = style
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
    func update(_ text: String, rendersMarkdown: Bool = false) -> Bool {
        guard sourceText != text || self.rendersMarkdown != rendersMarkdown,
              let storage = textStorage else { return false }
        sourceText = text
        let wasMarkdown = self.rendersMarkdown
        self.rendersMarkdown = rendersMarkdown
        isRichText = rendersMarkdown
        let attributes: [NSAttributedString.Key: Any] = [
            .font: readingStyle.font, .foregroundColor: textColor ?? NSColor.labelColor,
            .paragraphStyle: readingStyle.paragraphStyle,
        ]
        if rendersMarkdown {
            let rendered = ResponseMarkdown.render(text, style: readingStyle)
            let previousRange = NSRange(location: 0, length: storage.length)
            if rendered.length >= storage.length, rendered.attributedSubstring(from: previousRange).isEqual(to: storage) {
                storage.append(rendered.attributedSubstring(from: NSRange(location: storage.length, length: rendered.length - storage.length)))
            } else {
                let selection = selectedRanges
                storage.setAttributedString(rendered)
                selectedRanges = selection.map {
                    let range = $0.rangeValue
                    let location = min(range.location, rendered.length)
                    return NSValue(range: NSRange(location: location, length: min(range.length, rendered.length - location)))
                }
            }
        } else if !wasMarkdown, !string.isEmpty, text.hasPrefix(string) {
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
