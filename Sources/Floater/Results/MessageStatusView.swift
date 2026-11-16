import AppKit

final class MessageStatusView: NSView {
    enum Status: Equatable {
        case preparing(String), stopped, failed(String)

        var text: String {
            switch self {
            case .preparing(let text), .failed(let text): text
            case .stopped: "Response stopped"
            }
        }
    }

    private let textView = SelectableTextView(style: .caption)
    private let spinner = NSProgressIndicator()
    private let icon = NSImageView()
    private var status: Status?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.setAccessibilityLabel("Response status")
        addSubview(textView)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.setAccessibilityLabel("Waiting for response")
        addSubview(spinner)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        icon.setAccessibilityElement(false)
        addSubview(icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ status: Status) {
        guard self.status != status else { return }
        self.status = status
        let color: NSColor
        switch status {
        case .preparing:
            color = .secondaryLabelColor
            icon.isHidden = true
            spinner.isHidden = false
        case .stopped:
            color = .secondaryLabelColor
            icon.image = NSImage(systemSymbolName: "stop.circle", accessibilityDescription: nil)
            icon.isHidden = false
            spinner.isHidden = true
        case .failed:
            color = .systemRed
            icon.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
            icon.isHidden = false
            spinner.isHidden = true
        }
        textView.textColor = color
        icon.contentTintColor = color
        textView.update(status.text)
        updateAnimation()
    }

    func sizeThatFits(maximumWidth: CGFloat) -> NSSize {
        let natural = textView.measuredSize(width: max(1, maximumWidth - 22))
        let width = min(maximumWidth, natural.width + 22)
        let textWidth = max(1, width - 22)
        let textSize = textView.measuredSize(width: textWidth)
        textView.frame = NSRect(x: 22, y: 2, width: textWidth, height: textSize.height)
        let iconFrame = NSRect(x: 0, y: 3, width: 14, height: 14)
        spinner.frame = iconFrame
        icon.frame = iconFrame
        return NSSize(width: width, height: max(20, textSize.height + 4))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimation()
    }

    private func updateAnimation() {
        if case .preparing = status, window != nil {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }
}
