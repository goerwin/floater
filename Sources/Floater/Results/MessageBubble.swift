import AppKit

final class MessageBubble: NSView {
    private let textView = SelectableTextView(style: .body)
    private let copyButton = NSButton()
    private let thinkingIndicator = NSProgressIndicator()
    private let shimmerMask = CAGradientLayer()
    private var isThinking = false
    private var message: ChatMessage
    private let onCopy: (String) -> Void
    private var needsMeasurement = true
    private var measuredWidth: CGFloat = 0
    private var measuredSize = NSSize.zero

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
        thinkingIndicator.style = .spinning
        thinkingIndicator.controlSize = .small
        thinkingIndicator.isIndeterminate = true
        thinkingIndicator.isDisplayedWhenStopped = false
        thinkingIndicator.setAccessibilityLabel("Waiting for response")
        addSubview(thinkingIndicator)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(updateThinkingEffect),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ message: ChatMessage, preparationMessage: String) {
        self.message = message
        var text = message.content
        switch message.status {
        case .generating:
            if text.isEmpty { text = preparationMessage }
        case .stopped: text += "\n[Stopped]"
        case .failed: text += "\n[Failed]"
        case .complete: break
        }
        if let error = message.error { text += "\n" + ChatGenerationError.displayMessage(error) }
        if textView.update(text) { needsMeasurement = true }
        copyButton.isEnabled = !message.content.isEmpty
        let waiting = message.role == .assistant && message.status == .generating && message.content.isEmpty
        if isThinking != waiting {
            isThinking = waiting
            updateThinkingEffect()
        }
    }

    func sizeThatFits(maximumWidth: CGFloat) -> NSSize {
        if !needsMeasurement, measuredWidth == maximumWidth { return measuredSize }
        let natural = textView.measuredSize(width: max(1, maximumWidth - 48))
        let width = min(maximumWidth, max(88, natural.width + 48))
        let textSize = textView.measuredSize(width: max(1, width - 48))
        let height = max(40, textSize.height + 20)
        textView.frame = NSRect(x: 12, y: 10, width: max(1, width - 48), height: textSize.height)
        copyButton.frame = NSRect(x: width - 26, y: 11, width: 18, height: 18)
        let indicatorSize = ReadingTextStyle.body.fontSize
        thinkingIndicator.frame = NSRect(
            x: copyButton.frame.midX - indicatorSize / 2, y: copyButton.frame.midY - indicatorSize / 2,
            width: indicatorSize, height: indicatorSize
        )
        updateThinkingEffect()
        measuredWidth = maximumWidth
        measuredSize = NSSize(width: width, height: height)
        needsMeasurement = false
        return measuredSize
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateThinkingEffect()
    }

    @objc private func updateThinkingEffect() {
        copyButton.isHidden = isThinking
        guard isThinking, window != nil else {
            if !thinkingIndicator.isHidden {
                thinkingIndicator.stopAnimation(nil)
                thinkingIndicator.isHidden = true
            }
            shimmerMask.removeAnimation(forKey: "thinking")
            textView.layer?.mask = nil
            return
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        thinkingIndicator.isHidden = !reduceMotion
        if reduceMotion {
            thinkingIndicator.startAnimation(nil)
        } else {
            thinkingIndicator.stopAnimation(nil)
        }
        let width = textView.bounds.width
        guard !reduceMotion, width > 0 else {
            shimmerMask.removeAnimation(forKey: "thinking")
            textView.layer?.mask = nil
            return
        }
        let size = NSSize(width: width * 3, height: textView.bounds.height)
        guard shimmerMask.bounds.size != size || shimmerMask.animation(forKey: "thinking") == nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shimmerMask.frame = NSRect(origin: textView.bounds.origin, size: size)
        let base = CGColor(gray: 1, alpha: 0.72)
        shimmerMask.colors = [base, base, CGColor(gray: 1, alpha: 1), base, base]
        shimmerMask.locations = [0, 0.35, 0.5, 0.65, 1]
        shimmerMask.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerMask.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerMask.transform = CATransform3DMakeTranslation(-2 * width, 0, 0)
        textView.layer?.mask = shimmerMask
        CATransaction.commit()
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = -2 * width
        animation.toValue = 0
        animation.duration = 2
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmerMask.add(animation, forKey: "thinking")
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
