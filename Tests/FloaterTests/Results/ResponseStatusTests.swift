import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class ResponseStatusTests: XCTestCase {
    func testFailureWithoutAResponseShowsOnlyAStatusAndAllowsRetry() throws {
        let state = FloaterState(provider: TestProvider(), historyStore: HistoryStore(fileURL: nil))
        var entry = HistoryEntry(request: PromptRequest(prompt: "Hello"))
        var failed = ChatMessage(role: .assistant, content: "", status: .failed)
        failed.error = "The model is unavailable. Try again."
        entry.messages.append(failed)
        state.restore(entry)
        let window = makeWindow(state: state)
        defer { window.close() }
        let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let status = try XCTUnwrap(textViews(in: chat).first { $0.accessibilityLabel() == "Response status" })
        XCTAssertEqual(status.string, "The model is unavailable. Try again.")
        XCTAssertTrue(status.isSelectable)
        XCTAssertFalse(textViews(in: chat).contains { $0.accessibilityLabel() == "Reply" })
        XCTAssertTrue(buttons(in: chat).isEmpty)
        XCTAssertTrue(buttons(in: window.contentView!).contains { $0.accessibilityLabel() == "Retry" && $0.isEnabled })
    }

    func testStoppedAndFailedRepliesShowStatusBelowTheActualContent() throws {
        for status in [ChatMessage.Status.stopped, .failed] {
            let state = FloaterState(provider: TestProvider(), historyStore: HistoryStore(fileURL: nil))
            var entry = HistoryEntry(request: PromptRequest(prompt: "Hello"), response: "A **partial** reply")
            entry.messages[entry.messages.count - 1].status = status
            if status == .failed { entry.messages[entry.messages.count - 1].error = "The model stopped unexpectedly." }
            state.restore(entry)
            let window = makeWindow(state: state)
            defer { window.close() }
            let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
            let reply = try XCTUnwrap(textViews(in: chat).first { $0.accessibilityLabel() == "Reply" })
            let notice = try XCTUnwrap(textViews(in: chat).first { $0.accessibilityLabel() == "Response status" })
            XCTAssertEqual(reply.string, "A partial reply")
            XCTAssertEqual(notice.string, status == .stopped ? "Response stopped" : "The model stopped unexpectedly.")
            let replyBounds = reply.convert(reply.bounds, to: chat.documentView)
            let statusBounds = notice.convert(notice.bounds, to: chat.documentView)
            XCTAssertGreaterThan(statusBounds.minY, replyBounds.maxY)
            var copied = ""
            chat.onCopyMessage = { copied = $0 }
            let copy = try XCTUnwrap(buttons(in: chat).first { $0.accessibilityLabel() == "Copy message" })
            copy.performClick(nil)
            XCTAssertEqual(copied, "A **partial** reply")
        }
    }

    func testStoppingBeforeAnyTextShowsOnlyTheStoppedStatus() throws {
        let state = FloaterState(provider: TestProvider(), historyStore: HistoryStore(fileURL: nil))
        var entry = HistoryEntry(request: PromptRequest(prompt: "Hello"))
        entry.messages.append(ChatMessage(role: .assistant, content: "", status: .stopped))
        state.restore(entry)
        let window = makeWindow(state: state)
        defer { window.close() }
        let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        XCTAssertEqual(textViews(in: chat).map(\.string), ["Response stopped"])
        XCTAssertTrue(buttons(in: chat).isEmpty)
    }
}
