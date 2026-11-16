import AppKit
import SwiftUI

struct ResponseText: NSViewRepresentable {
    let messages: [ChatMessage]
    let preparationMessage: String
    let maximumHeight: CGFloat
    let onCopyMessage: (String) -> Void

    func makeNSView(context: Context) -> ResponseScrollView { ResponseScrollView() }

    func updateNSView(_ view: ResponseScrollView, context: Context) {
        view.onCopyMessage = onCopyMessage
        view.update(messages: messages, preparationMessage: preparationMessage)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ResponseScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? FloaterPanelLayout.contentWidth
        return CGSize(width: width, height: min(maximumHeight, max(32, nsView.contentHeight(width: width))))
    }
}

final class ResponseScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }

    var onCopyMessage: (String) -> Void = { _ in }
    private let messagesView = MessageListView()
    private var rows: [UUID: MessageRow] = [:]
    private var orderedRows: [MessageRow] = []
    private var followsBottom = true
    private var updateDepth = 0
    private var turnID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        identifier = NSUserInterfaceItemIdentifier("responseText")
        setAccessibilityLabel("Conversation")
        documentView = messagesView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: contentView
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Keep focus here instead of forwarding it to the document view.
    override func becomeFirstResponder() -> Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        guard modifiers.isEmpty, [125, 126].contains(event.keyCode) else {
            super.keyDown(with: event)
            return
        }
        var offset = contentView.bounds.origin
        offset.y = min(bottomOffset.y, max(0, offset.y + (event.keyCode == 125 ? verticalLineScroll : -verticalLineScroll)))
        contentView.scroll(to: offset)
        reflectScrolledClipView(contentView)
    }

    func update(messages: [ChatMessage], preparationMessage: String) {
        updateDepth += 1
        defer { updateDepth -= 1 }
        if turnID != messages.last?.id { followsBottom = true; turnID = messages.last?.id }
        let previousOffset = contentView.bounds.origin
        let ids = Set(messages.map(\.id))
        for (id, row) in rows where !ids.contains(id) { row.removeFromSuperview() }
        rows = rows.filter { ids.contains($0.key) }
        orderedRows = messages.map { message in
            let row: MessageRow
            if let existing = rows[message.id] {
                row = existing
            } else {
                row = MessageRow(message: message) { [weak self] in self?.onCopyMessage($0) }
                rows[message.id] = row
                messagesView.addSubview(row)
            }
            row.update(message, preparationMessage: preparationMessage)
            return row
        }
        resizeDocument(width: contentSize.width)
        contentView.scroll(to: followsBottom ? bottomOffset : previousOffset)
        reflectScrolledClipView(contentView)
    }

    func contentHeight(width: CGFloat) -> CGFloat {
        updateDepth += 1
        defer { updateDepth -= 1 }
        return resizeDocument(width: width)
    }

    override func layout() {
        updateDepth += 1
        defer { updateDepth -= 1 }
        super.layout()
        resizeDocument(width: contentSize.width)
        if followsBottom {
            contentView.scroll(to: bottomOffset)
            reflectScrolledClipView(contentView)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        updateDepth += 1
        defer { updateDepth -= 1 }
        super.setFrameSize(newSize)
        resizeDocument(width: contentSize.width)
        if followsBottom {
            contentView.scroll(to: bottomOffset)
            reflectScrolledClipView(contentView)
        }
    }

    @discardableResult
    private func resizeDocument(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 32 }
        var y: CGFloat = 0
        for row in orderedRows {
            let size = row.sizeThatFits(maximumWidth: width * (row.role == .user ? 0.85 : 0.94))
            guard size.height > 0 else { row.frame = .zero; continue }
            let x = row.role == .user ? width - size.width : 0
            row.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
            y += size.height + 12
        }
        let height = max(32, y - 12)
        let size = NSSize(width: width, height: max(contentSize.height, height))
        if messagesView.frame.size != size { messagesView.setFrameSize(size) }
        return height
    }

    private var bottomOffset: NSPoint {
        NSPoint(x: 0, y: max(0, messagesView.frame.height - contentView.bounds.height))
    }

    @objc private func didScroll() {
        guard updateDepth == 0 else { return }
        followsBottom = contentView.bounds.maxY >= messagesView.frame.height - 8
    }
}

private final class MessageListView: NSView {
    override var isFlipped: Bool { true }
}
