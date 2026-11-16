import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class ResponseMarkdownTests: XCTestCase {
    func testRepliesRenderMarkdownWhileUserMessagesStayLiteralAndCopyKeepsTheSource() throws {
        let markdown = """
        # A useful reply

        Some **bold**, *italic*, ~~removed~~ and `inline code` with a [link](https://example.com).

        - First item
        - Second item
          - Nested item

        3. Third item
        4. Fourth item

        > A quoted sentence.

        ```swift
        let greeting = "Hello"
        print(greeting)
        ```

        | Name | Value |
        | :--- | ---: |
        | Greeting | Hello |
        """
        let state = FloaterState(provider: TestProvider(), historyStore: HistoryStore(fileURL: nil))
        var entry = HistoryEntry(request: PromptRequest(prompt: "Help"), response: markdown)
        entry.messages.append(ChatMessage(role: .user, content: "Keep **this** and `that` literal."))
        state.restore(entry)
        let window = makeWindow(state: state)
        defer { window.close() }
        let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let reply = try XCTUnwrap(textViews(in: chat).first { $0.accessibilityLabel() == "Reply" })
        XCTAssertTrue(reply.string.hasPrefix("A useful reply\n"))
        XCTAssertFalse(reply.string.contains("**"))
        XCTAssertFalse(reply.string.contains("```"))
        XCTAssertTrue(reply.string.contains("•\tFirst item\n•\tSecond item"))
        XCTAssertTrue(reply.string.contains("3.\tThird item\n4.\tFourth item"))
        XCTAssertTrue(reply.string.contains("let greeting = \"Hello\"\nprint(greeting)"))
        XCTAssertEqual(textViews(in: chat).last?.string, "Keep **this** and `that` literal.")
        XCTAssertTrue(reply.isSelectable)
        let content = reply.attributedString()
        let boldFont = try XCTUnwrap(content.attribute(.font, at: (reply.string as NSString).range(of: "bold").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        let headingFont = try XCTUnwrap(content.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertGreaterThan(headingFont.pointSize, ReadingTextStyle.body.fontSize)
        let link = content.attribute(.link, at: (reply.string as NSString).range(of: "link").location, effectiveRange: nil) as? URL
        XCTAssertEqual(link?.absoluteString, "https://example.com")
        let codeFont = try XCTUnwrap(content.attribute(.font, at: (reply.string as NSString).range(of: "let greeting").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(codeFont.isFixedPitch)
        let italicFont = try XCTUnwrap(content.attribute(.font, at: (reply.string as NSString).range(of: "italic").location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertEqual(content.attribute(.strikethroughStyle, at: (reply.string as NSString).range(of: "removed").location, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        let layout = try XCTUnwrap(reply.layoutManager)
        let container = try XCTUnwrap(reply.textContainer)
        func bounds(of text: String) -> NSRect {
            let range = (reply.string as NSString).range(of: text)
            return layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
        }
        XCTAssertEqual(bounds(of: "Name").minY, bounds(of: "Value").minY, accuracy: 1)
        XCTAssertLessThan(bounds(of: "Name").maxX, bounds(of: "Value").minX)
        XCTAssertLessThan(bounds(of: "Name").minY, bounds(of: "Greeting").minY)
        XCTAssertLessThanOrEqual(bounds(of: "Greeting").maxY, reply.bounds.maxY)
        var copied = ""
        chat.onCopyMessage = { copied = $0 }
        let copy = try XCTUnwrap(buttons(in: chat).first { $0.accessibilityLabel() == "Copy message" })
        copy.performClick(nil)
        XCTAssertEqual(copied, markdown)
    }

    func testGrowingReplyReformatsCompletedMarkdownAndKeepsStatusVisible() throws {
        var message = ChatMessage(role: .assistant, content: "A **growing", status: .generating)
        let scroll = ResponseScrollView()
        scroll.update(messages: [message], preparationMessage: "Thinking")
        message.content = "A **growing reply**"
        scroll.update(messages: [message], preparationMessage: "Thinking")
        let text = try XCTUnwrap(textViews(in: scroll).first)
        XCTAssertEqual(text.string, "A growing reply")
        message.content = "```swift\nlet value = 1"
        message.status = .stopped
        scroll.update(messages: [message], preparationMessage: "Thinking")
        XCTAssertTrue(text.string.contains("let value = 1"))
        XCTAssertFalse(text.string.contains("Response stopped"))
        let status = try XCTUnwrap(textViews(in: scroll).first { $0.accessibilityLabel() == "Response status" })
        XCTAssertEqual(status.string, "Response stopped")
        let statusFont = try XCTUnwrap(status.font)
        XCTAssertFalse(statusFont.isFixedPitch, "An unfinished code block must not swallow the status")
    }
}
