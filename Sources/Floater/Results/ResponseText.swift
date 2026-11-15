import AppKit
import SwiftUI

struct ResponseText: NSViewRepresentable {
    let text: String
    let isSelectable: Bool
    let isError: Bool
    let maximumHeight: CGFloat
    var scrollRequestID: UUID?
    var promptIsExpanded = false

    func makeNSView(context: Context) -> ResponseScrollView { ResponseScrollView() }

    func updateNSView(_ view: ResponseScrollView, context: Context) {
        view.beginTurn(scrollRequestID)
        view.revealPrompt(promptIsExpanded)
        view.update(text: text, isSelectable: isSelectable, isError: isError)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ResponseScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? FloaterPanelLayout.contentWidth
        return CGSize(width: width, height: min(maximumHeight, max(18, nsView.textHeight(width: width))))
    }
}

final class ResponseScrollView: NSScrollView {
    private let responseView = NSTextView()
    private var followsBottom = true
    private var updateDepth = 0
    private var hasText = false
    private var turnID: UUID?
    private var promptIsExpanded = false

    func beginTurn(_ id: UUID?) {
        if turnID != id { followsBottom = true; turnID = id }
    }

    func revealPrompt(_ expanded: Bool) {
        updateDepth += 1
        defer { updateDepth -= 1 }
        if expanded && !promptIsExpanded {
            followsBottom = false
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
        }
        promptIsExpanded = expanded
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        setAccessibilityIdentifier("responseText")

        responseView.isEditable = false
        responseView.isRichText = false
        responseView.drawsBackground = false
        responseView.font = .systemFont(ofSize: 13)
        responseView.textContainerInset = NSSize(width: 0, height: 2)
        responseView.textContainer?.lineFragmentPadding = 0
        responseView.isHorizontallyResizable = false
        responseView.isVerticallyResizable = true
        responseView.textContainer?.widthTracksTextView = true
        responseView.autoresizingMask = [.width]
        documentView = responseView
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(didScroll), name: NSView.boundsDidChangeNotification, object: contentView
        )
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(text: String, isSelectable: Bool, isError: Bool) {
        updateDepth += 1
        defer { updateDepth -= 1 }
        let shouldFollow = followsBottom
        let previousOffset = contentView.bounds.origin
        let color: NSColor = isError ? .systemRed : .labelColor
        responseView.isSelectable = isSelectable
        if responseView.string != text, let storage = responseView.textStorage {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color]
            if hasText, text.hasPrefix(responseView.string) {
                let suffix = (text as NSString).substring(from: storage.length)
                storage.append(NSAttributedString(string: suffix, attributes: attributes))
            } else {
                storage.setAttributedString(NSAttributedString(string: text, attributes: attributes))
            }
        }
        if responseView.textColor != color { responseView.textColor = color }
        hasText = true
        resizeDocument(width: contentSize.width)
        contentView.scroll(to: shouldFollow ? bottomOffset : previousOffset)
        reflectScrolledClipView(contentView)
    }

    func textHeight(width: CGFloat) -> CGFloat {
        updateDepth += 1
        defer { updateDepth -= 1 }
        return resizeDocument(width: width)
    }

    override func layout() {
        updateDepth += 1
        defer { updateDepth -= 1 }
        let shouldFollow = followsBottom
        super.layout()
        resizeDocument(width: contentSize.width)
        if shouldFollow {
            contentView.scroll(to: bottomOffset)
            reflectScrolledClipView(contentView)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        updateDepth += 1
        defer { updateDepth -= 1 }
        super.setFrameSize(newSize)
        if followsBottom {
            contentView.scroll(to: bottomOffset)
            reflectScrolledClipView(contentView)
        }
    }

    @discardableResult
    private func resizeDocument(width: CGFloat) -> CGFloat {
        guard width > 0, let container = responseView.textContainer, let layout = responseView.layoutManager else { return 18 }
        if responseView.frame.width != width { responseView.setFrameSize(NSSize(width: width, height: responseView.frame.height)) }
        if container.containerSize.width != width {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        let height = ceil(max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)) + 4
        let size = NSSize(width: width, height: max(contentSize.height, height))
        if responseView.frame.size != size { responseView.setFrameSize(size) }
        return height
    }

    private var bottomOffset: NSPoint {
        NSPoint(x: 0, y: max(0, responseView.frame.height - contentView.bounds.height))
    }

    @objc private func didScroll() {
        guard updateDepth == 0 else { return }
        followsBottom = contentView.bounds.maxY >= responseView.frame.height - 8
    }
}
