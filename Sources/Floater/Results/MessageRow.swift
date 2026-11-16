import AppKit

final class MessageRow: NSView {
    private let bubble: MessageBubble
    private let statusView = MessageStatusView()
    private(set) var role: ChatMessage.Role

    override var isFlipped: Bool { true }

    init(message: ChatMessage, onCopy: @escaping (String) -> Void) {
        role = message.role
        bubble = MessageBubble(message: message, onCopy: onCopy)
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("messageRow-\(message.id)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ message: ChatMessage, preparationMessage: String) {
        role = message.role
        let hasContent = message.content.contains { !$0.isWhitespace }
        if !hasContent {
            bubble.removeFromSuperview()
        } else {
            if bubble.superview == nil { addSubview(bubble) }
            bubble.update(message)
        }
        let status: MessageStatusView.Status?
        if let error = message.error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .failed(ChatGenerationError.displayMessage(error))
        } else {
            switch message.status {
            case .generating: status = hasContent ? nil : .preparing(preparationMessage)
            case .stopped: status = .stopped
            case .failed: status = .failed("Couldn't generate a response. Try again.")
            case .complete: status = nil
            }
        }
        if let status {
            statusView.update(status)
            if statusView.superview == nil { addSubview(statusView) }
        } else {
            statusView.removeFromSuperview()
        }
    }

    func sizeThatFits(maximumWidth: CGFloat) -> NSSize {
        var size = NSSize.zero
        if bubble.superview != nil {
            size = bubble.sizeThatFits(maximumWidth: maximumWidth)
            bubble.frame = NSRect(origin: .zero, size: size)
        }
        if statusView.superview != nil {
            let x: CGFloat = bubble.superview == nil ? 0 : 12
            let y = size.height > 0 ? size.height + 6 : 0
            let statusSize = statusView.sizeThatFits(maximumWidth: max(1, maximumWidth - x))
            statusView.frame = NSRect(x: x, y: y, width: statusSize.width, height: statusSize.height)
            size = NSSize(width: max(size.width, x + statusSize.width), height: y + statusSize.height)
        }
        return size
    }
}
