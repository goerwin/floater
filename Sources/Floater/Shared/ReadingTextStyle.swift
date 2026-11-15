import AppKit

struct ReadingTextStyle: Sendable {
    static let body = ReadingTextStyle(fontSize: 14, lineSpacing: 4)
    static let caption = ReadingTextStyle(fontSize: 12, lineSpacing: 2)

    let fontSize: CGFloat
    let lineSpacing: CGFloat

    var font: NSFont { .systemFont(ofSize: fontSize) }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        return style
    }

    func lineHeight(using layout: NSLayoutManager) -> CGFloat {
        layout.defaultLineHeight(for: font) + lineSpacing
    }
}
