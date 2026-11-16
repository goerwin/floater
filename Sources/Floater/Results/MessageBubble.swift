import AppKit

final class MessageBubble: NSView {
    private let textView = SelectableTextView(style: .body)
    private let copyButton = NSButton()
    private var message: ChatMessage
    private let onCopy: (String) -> Void
    private var needsMeasurement = true
    private var measuredWidth: CGFloat = 0
    private var measuredSize = NSSize.zero
    private var minimumStreamingHeight: CGFloat = 0

    var role: ChatMessage.Role { message.role }
    override var isFlipped: Bool { true }

    init(message: ChatMessage, onCopy: @escaping (String) -> Void) {
        self.message = message
        self.onCopy = onCopy
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("message-\(message.id)")
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        textView.identifier = NSUserInterfaceItemIdentifier("messageText-\(message.id)")
        textView.setAccessibilityLabel(message.role == .user ? "Your message" : "Reply")
        // Creating the text layer later can scroll a saved reply away from the bottom.
        textView.wantsLayer = true
        addSubview(textView)
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        copyButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        copyButton.imagePosition = .imageOnly
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.identifier = NSUserInterfaceItemIdentifier("messageCopy-\(message.id)")
        copyButton.setAccessibilityLabel("Copy message")
        copyButton.toolTip = "Copy message"
        copyButton.target = self
        copyButton.action = #selector(copyMessage)
        addSubview(copyButton)
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ message: ChatMessage) {
        if !message.content.hasPrefix(self.message.content) { minimumStreamingHeight = 0 }
        self.message = message
        if textView.update(message.content, rendersMarkdown: message.role == .assistant) { needsMeasurement = true }
    }

    func sizeThatFits(maximumWidth: CGFloat) -> NSSize {
        if !needsMeasurement, measuredWidth == maximumWidth { return measuredSize }
        if measuredWidth != maximumWidth { minimumStreamingHeight = 0 }
        let width: CGFloat
        if role == .assistant {
            width = maximumWidth
        } else {
            let natural = textView.measuredSize(width: max(1, maximumWidth - 48))
            width = min(maximumWidth, max(88, natural.width + 48))
        }
        let textSize = textView.measuredSize(width: max(1, width - 48))
        // Closing Markdown markers can remove a wrapped line mid-stream.
        let height = max(minimumStreamingHeight, max(40, textSize.height + 20))
        if role == .assistant, message.status == .generating { minimumStreamingHeight = height }
        textView.frame = NSRect(x: 12, y: 10, width: max(1, width - 48), height: textSize.height)
        copyButton.frame = NSRect(x: width - 26, y: 11, width: 18, height: 18)
        measuredWidth = maximumWidth
        measuredSize = NSSize(width: width, height: height)
        needsMeasurement = false
        return measuredSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let base = NSColor.controlBackgroundColor
            let tint = role == .user ? NSColor.controlAccentColor : NSColor.labelColor
            let surface = base.blended(withFraction: role == .user ? 0.18 : 0.12, of: tint) ?? base
            layer?.backgroundColor = surface.withAlphaComponent(1).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    @objc private func copyMessage() { onCopy(message.content) }
}
