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
        let scroll = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first)
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
            let scroll = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first)
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
        let originalScroll = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first)
        XCTAssertTrue(isAtBottom(originalScroll), "Saved results start at the latest reply")

        state.start(request)
        provider.send(response)
        try await Task.sleep(for: .milliseconds(150))
        settle(window)
        let scroll = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first)
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
        XCTAssertEqual(text.string, "Floater\n" + response)
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
        let scroll = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first)
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
