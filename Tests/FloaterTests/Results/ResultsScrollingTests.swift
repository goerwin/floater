import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class ResultsScrollingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { _ = NSApplication.shared }
    }

    func testConversationCanBeFocusedFromComposerAndScrolledWithArrowKeys() throws {
        let state = FloaterState(provider: TestProvider())
        state.restore(HistoryEntry(
            request: PromptRequest(prompt: "A long conversation"),
            response: String(repeating: "A line in the conversation.\n", count: 100)
        ))
        let window = makeWindow(state: state)
        defer { window.close() }
        let composer = try XCTUnwrap(window.firstResponder as? NSTextView)
        let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let bottom = scroll.contentView.bounds.minY
        XCTAssertGreaterThan(bottom, 0)

        sendKey("\u{19}", code: 48, modifiers: .shift, to: window)
        let focusedView = try XCTUnwrap(window.firstResponder as? NSView)
        XCTAssertTrue(focusedView.isDescendant(of: scroll), "Shift+Tab should focus the conversation from the composer")
        sendKey("\u{f700}", code: 126, to: window)
        let scrolledUp = scroll.contentView.bounds.minY
        XCTAssertLessThan(scrolledUp, bottom, "Up Arrow should scroll to earlier messages")
        sendKey("\u{f701}", code: 125, to: window)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, scrolledUp, "Down Arrow should scroll to later messages")

        sendKey("\t", code: 48, to: window)
        XCTAssertTrue(window.firstResponder === composer, "Tab should return to the composer")
        XCTAssertEqual(state.followUp, "")
    }

    func testPreparationIndicatorKeepsItsSizeAndGivesWayToTheReply() async throws {
        let provider = StreamingTestProvider()
        let state = FloaterState(provider: provider)
        state.start(PromptRequest(prompt: "Hello"))
        let window = makeWindow(state: state)
        defer { window.close(); provider.finish() }
        let waitingText = try XCTUnwrap(textViews(in: window.contentView!).first {
            $0.string == provider.preparationMessage
        })
        XCTAssertEqual(waitingText.accessibilityLabel(), "Response status")
        XCTAssertFalse(buttons(in: window.contentView!).contains { $0.accessibilityLabel() == "Copy message" })
        let indicator = try XCTUnwrap(waitingText.superview)
        let indicatorSize = indicator.frame.size
        let windowSize = window.frame.size
        for _ in 0..<5 {
            try await Task.sleep(for: .milliseconds(100))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(indicator.frame.size, indicatorSize, "The preparation indicator must not resize while animating")
            XCTAssertEqual(window.frame.size, windowSize)
        }
        provider.send(" \n")
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        XCTAssertFalse(textViews(in: window.contentView!).contains { $0.accessibilityLabel() == "Reply" })
        XCTAssertEqual(waitingText.string, provider.preparationMessage)
        provider.send("Hello there.")
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        let reply = try XCTUnwrap(textViews(in: window.contentView!).first { $0.accessibilityLabel() == "Reply" })
        XCTAssertEqual(reply.string, "Hello there.")
        XCTAssertTrue(reply.isSelectable)
        XCTAssertFalse(textViews(in: window.contentView!).contains { $0.string == provider.preparationMessage })
        XCTAssertTrue(buttons(in: window.contentView!).contains { $0.accessibilityLabel() == "Copy message" })
        provider.finish()
    }

    func testOpeningSavedConversationsStartsAtLatestMessageAndAllowsScrollingUp() throws {
        let state = FloaterState(provider: TestProvider())
        let window = makeWindow(state: state)
        defer { window.close() }
        let response = String(repeating: "Earlier message content.\n", count: 100) + "Latest reply"
        for title in ["First conversation", "Second conversation"] {
            state.showHistory(returnToRequest: true)
            settle(window)
            state.openHistoryEntry(HistoryEntry(request: PromptRequest(prompt: title), response: response))
            settle(window)
            let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
            XCTAssertGreaterThan(scroll.documentView!.bounds.height, scroll.contentView.bounds.height)
            XCTAssertTrue(isAtBottom(scroll), "Opening a saved chat should reveal the latest reply")

            scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
            scroll.reflectScrolledClipView(scroll.contentView)
            state.followUp = "A draft"
            settle(window)
            XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 2, "Editing a draft must preserve the reading position")
        }
    }

    func testStreamingFollowsBottomAndPausesWhileReadingEarlierText() async throws {
        let provider = StreamingTestProvider()
        let state = FloaterState(provider: provider)
        state.start(PromptRequest(prompt: "Write a long response"))
        let window = makeWindow(state: state)
        defer { window.close(); provider.finish() }

        var response = (1...100).map { "Line \($0): A sentence in a growing response.\n" }.joined()
        provider.send(response)
        try await Task.sleep(for: .milliseconds(150))
        settle(window)
        let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        XCTAssertGreaterThan(scroll.documentView!.bounds.height, scroll.contentView.bounds.height)
        XCTAssertTrue(isAtBottom(scroll), "Streaming should reveal the latest text: \(scroll.contentView.bounds), document: \(scroll.documentView!.bounds)")

        for _ in 0..<3 {
            response += "The latest generated sentence.\n"
            provider.send(response)
            try await Task.sleep(for: .milliseconds(50))
            settle(window)
            XCTAssertTrue(isAtBottom(scroll), "Each streaming update should keep the latest text visible")
        }

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        let pausedOffset = scroll.contentView.bounds.minY
        response += String(repeating: "More generated text.\n", count: 20)
        provider.send(response)
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        XCTAssertEqual(scroll.contentView.bounds.minY, pausedOffset, accuracy: 2)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.documentView!.bounds.height))
        scroll.reflectScrolledClipView(scroll.contentView)
        response += String(repeating: "The response continues.\n", count: 20)
        provider.send(response)
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        XCTAssertTrue(isAtBottom(scroll), "Returning to the bottom should resume following")
        provider.finish()
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        XCTAssertTrue(isAtBottom(scroll))
        XCTAssertEqual(state.response, response)
    }

    func testWindowGrowsUntilTheResponseViewportIsFull() async throws {
        let provider = StreamingTestProvider()
        let state = FloaterState(provider: provider)
        state.start(PromptRequest(prompt: "Write a long response"))
        let controller = FloatingPanelController(state: state)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { controller.hide(); provider.finish() }
        var initialHeight: CGFloat = 0
        for count in [1, 5, 15, 30, 100] {
            provider.send(String(repeating: "A generated sentence.\n", count: count))
            try await Task.sleep(for: .milliseconds(75))
            settle(window)
            let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
            XCTAssertTrue(isAtBottom(scroll))
            XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumHeight)
            if count == 1 { initialHeight = window.frame.height }
        }
        XCTAssertGreaterThan(window.frame.height, initialHeight)
    }

    func testNewGenerationResetsFollowingForTheSamePrompt() async throws {
        let provider = StreamingTestProvider()
        let state = FloaterState(provider: provider)
        let request = PromptRequest(prompt: "Write a long response")
        let response = String(repeating: "A sentence in the response.\n", count: 100)
        state.restore(request: request, response: response)
        let window = makeWindow(state: state)
        defer { window.close(); provider.finish() }
        let originalScroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        XCTAssertTrue(isAtBottom(originalScroll), "Saved results start at the latest reply")

        state.start(request)
        provider.send(response)
        try await Task.sleep(for: .milliseconds(150))
        settle(window)
        let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        XCTAssertFalse(scroll === originalScroll)
        XCTAssertTrue(isAtBottom(scroll))

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100))
        scroll.reflectScrolledClipView(scroll.contentView)
        provider.finish()
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        XCTAssertEqual(scroll.contentView.bounds.minY, 100, accuracy: 2, "Finishing must preserve the reader's position")
        let text = try XCTUnwrap(textViews(in: scroll).first)
        XCTAssertTrue(text.isSelectable)
        XCTAssertEqual(text.string, response)
    }

    func testLongStreamingResponseRemainsScrollable() async throws {
        let provider = StreamingTestProvider()
        let state = FloaterState(provider: provider)
        state.start(PromptRequest(prompt: "Write a long response"))
        let controller = FloatingPanelController(state: state)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { controller.hide(); provider.finish() }
        var response = String(repeating: "A complete sentence in a longer generated response.\n", count: 1000)
        provider.send(response)
        try await Task.sleep(for: .milliseconds(200))
        let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let started = ContinuousClock.now
        for index in 0..<100 {
            response += "Another generated sentence.\n"
            provider.send(response)
            try await Task.sleep(for: .milliseconds(1))
            window.contentView?.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(index * 4)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        print("STREAMING_SCROLL_DURATION: \(started.duration(to: .now))")
        provider.finish()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(state.response, response)
        XCTAssertFalse(isAtBottom(scroll))
    }

    func testBilingualMarkdownReplyKeepsItsWidthAndDoesNotShrinkWhileStreaming() async throws {
        let provider = StreamingTestProvider()
        let state = FloaterState(provider: provider)
        state.start(PromptRequest(prompt: "give multiple ways of saying this in spanish and english: yeah i can do that but let me know if u need anything from me, does that sound good?"))
        let controller = FloatingPanelController(state: state)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { controller.hide(); provider.finish() }
        settle(window)

        let options = [
            ("Yeah, I can do that! Let me know if you need anything from me. Does that work for you?", "Sí, puedo hacerlo. Avísame si necesitas algo de mi parte. ¿Te parece bien?"),
            ("Sure, happy to help. Just let me know if you need anything else. Sound good?", "Claro, con gusto. Dime si necesitas algo más. ¿Te parece?"),
            ("Absolutely, I can take care of it. Let me know what you need from me. Is that okay?", "Por supuesto, puedo encargarme. Avísame qué necesitas de mi parte. ¿Está bien?"),
            ("Yes, that works for me. Please let me know if there's anything you need. How does that sound?", "Sí, me parece bien. Por favor, dime si necesitas algo. ¿Qué te parece?"),
            ("Of course! I can handle that. Give me a shout if you need anything. All good?", "¡Claro! Yo me encargo. Avísame si necesitas algo. ¿Todo bien?"),
            ("I'd be happy to do that. Please let me know if you need any further information. Would that work?", "Con mucho gusto. Avísame si necesitas más información. ¿Te vendría bien?")
        ]
        let response = "Here are several natural ways to say it in both languages.\n\n"
            + ["Friendly options", "Polite options", "Short and relaxed options"].map { title in
                "### \(title)\n\n" + options.enumerated().map { index, pair in
                    "\(index + 1). **English:** \(pair.0)\n   **Spanish:** \(pair.1)\n"
                }.joined(separator: "\n")
            }.joined(separator: "\n\n")
        let characters = Array(response)
        var widths: [CGFloat] = []
        var heights: [CGFloat] = []
        var filledViewportSizes: [NSSize] = []
        for end in Array(stride(from: 8, to: characters.count, by: 8)) + [characters.count] {
            provider.send(String(characters.prefix(end)))
            try await Task.sleep(for: .milliseconds(8))
            window.contentView?.layoutSubtreeIfNeeded()
            let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
            let reply = try XCTUnwrap(textViews(in: scroll).first { $0.accessibilityLabel() == "Reply" })
            let bubble = try XCTUnwrap(reply.superview)
            widths.append(bubble.frame.width)
            heights.append(bubble.frame.height)
            if scroll.documentView!.bounds.height > scroll.contentView.bounds.height + 30 {
                filledViewportSizes.append(scroll.contentView.bounds.size)
            }
        }
        let contractions = zip(heights, heights.dropFirst()).filter { $1 < $0 - 1 }.count
        print("BILINGUAL_STREAM_LAYOUT: widths=\(Set(widths.map { Int($0.rounded()) }).count), height contractions=\(contractions), filled viewport sizes=\(Set(filledViewportSizes.map { Int($0.height.rounded()) }).count)")
        XCTAssertEqual(Set(widths.map { Int($0.rounded()) }).count, 1, "The response width should stay fixed as tokens arrive")
        XCTAssertEqual(contractions, 0, "Resolving Markdown must not make the response box repeatedly shrink")
        XCTAssertFalse(filledViewportSizes.isEmpty, "This reply must fill the viewport")
        XCTAssertEqual(Set(filledViewportSizes.map { Int($0.height.rounded()) }).count, 1, "A full response viewport should keep its height")
        let lastWidth = widths.last
        let lastHeight = heights.last
        provider.finish()
        try await Task.sleep(for: .milliseconds(100))
        settle(window)
        let reply = try XCTUnwrap(textViews(in: window.contentView!).first { $0.accessibilityLabel() == "Reply" })
        XCTAssertEqual(reply.superview?.frame.width, lastWidth)
        XCTAssertEqual(reply.superview?.frame.height, lastHeight)
    }

    private func isAtBottom(_ scroll: NSScrollView) -> Bool {
        scroll.contentView.bounds.maxY >= (scroll.documentView?.bounds.maxY ?? 0) - 3
    }
}

@MainActor
private final class StreamingTestProvider: AIProvider {
    private let updates: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        (updates, continuation) = AsyncStream.makeStream(of: String.self)
    }

    func send(_ text: String) { continuation.yield(text) }
    func finish() { continuation.finish() }

    func generate(messages: [ChatMessage], onUpdate: @MainActor (String) -> Void) async throws {
        for await text in updates { onUpdate(text) }
    }
}
