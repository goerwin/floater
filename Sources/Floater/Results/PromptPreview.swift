import AppKit
import SwiftUI

struct PromptPreview: View {
    let text: String
    @Binding var isExpanded: Bool
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.alignleft")
                        Text(isExpanded ? "Hide prompt" : "Show prompt")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(isExpanded ? "Hide prompt" : "Show full prompt")
                .accessibilityIdentifier("togglePrompt")
                Spacer()
                if isExpanded {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .accessibilityLabel("Copy prompt")
                    .help("Copy prompt")
                }
            }
            if isExpanded {
                PromptText(text: text)
                    .padding(.leading, 18)
            }
            Divider()
                .padding(.top, 2)
        }
        .padding(.bottom, 8)
    }
}

private struct PromptText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> PromptScrollView { PromptScrollView() }

    func updateNSView(_ view: PromptScrollView, context: Context) { view.update(text) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PromptScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? FloaterPanelLayout.contentWidth
        return CGSize(width: width, height: nsView.previewHeight(width: width))
    }
}

private final class PromptScrollView: NSScrollView {
    private let textView = SelectableTextView(style: .caption)
    private let edgeMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        identifier = NSUserInterfaceItemIdentifier("promptText")
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textColor = .secondaryLabelColor
        textView.setAccessibilityLabel("Prompt")
        documentView = textView
        contentView.wantsLayer = true
        contentView.layer?.mask = edgeMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func previewHeight(width: CGFloat) -> CGFloat {
        let lineHeight = textView.layoutManager.map { ReadingTextStyle.caption.lineHeight(using: $0) } ?? 17
        return min(ceil(lineHeight * 6) + 8, max(lineHeight + 8, textHeight(width: width)))
    }

    func update(_ text: String) {
        if textView.update(text) {
            textHeight(width: contentSize.width)
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
        }
    }

    @discardableResult
    func textHeight(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 26 }
        let size = textView.measuredSize(width: width)
        textView.setFrameSize(NSSize(width: width, height: max(contentSize.height, size.height)))
        return size.height
    }

    override func layout() {
        super.layout()
        textHeight(width: contentSize.width)
        updateEdgeMask()
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
        updateEdgeMask()
    }

    private func updateEdgeMask() {
        let bounds = contentView.bounds
        guard bounds.height > 0 else { return }
        let above = bounds.minY > 1
        let below = bounds.maxY < textView.frame.height - 1
        let opaque = CGColor(gray: 0, alpha: 1)
        let clear = CGColor(gray: 0, alpha: 0)
        let fade = min(12 / bounds.height, 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = bounds
        edgeMask.startPoint = CGPoint(x: 0.5, y: 0)
        edgeMask.endPoint = CGPoint(x: 0.5, y: 1)
        edgeMask.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
        edgeMask.colors = [above ? clear : opaque, opaque, opaque, below ? clear : opaque]
        CATransaction.commit()
    }
}
