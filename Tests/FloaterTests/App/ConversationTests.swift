import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class ConversationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testFollowUpsSendRolesAndUpdateOneHistoryEntry() async throws {
        let provider = ChatTestProvider()
        let store = HistoryStore(fileURL: nil)
        let state = FloaterState(provider: provider, historyStore: store)
        state.start(PromptRequest(prompt: "Rewrite this: hello", title: "Rewrite"))
        await wait { provider.requests.count == 1 }
        provider.finish("Hello.")
        await wait { !state.isGenerating }
        let original = try XCTUnwrap(store.entries.first)

        state.followUp = "Explain the change."
        state.sendFollowUp()
        await wait { provider.requests.count == 2 }
        XCTAssertEqual(provider.requests[1].map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(provider.requests[1].map(\.content), ["Rewrite this: hello", "Hello.", "Explain the change."])
        XCTAssertEqual(state.followUp, "")
        XCTAssertEqual(state.responseForActions, "Hello.")
        provider.finish("I capitalized the greeting.")
        await wait { !state.isGenerating }
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries[0].id, original.id)
        XCTAssertEqual(store.entries[0].createdAt, original.createdAt)
        XCTAssertEqual(store.entries[0].messages.count, 4)
        XCTAssertTrue(store.entries[0].matches("capitalized"))
    }

    func testStopRetainsPartialForContextAndRetryReplacesOnlyTheAttempt() async {
        let provider = ChatTestProvider()
        let state = FloaterState(provider: provider, historyStore: HistoryStore(fileURL: nil))
        state.start(PromptRequest(prompt: "First"))
        await wait { provider.requests.count == 1 }
        provider.update("Unfinished answer")
        await wait { state.response == "Unfinished answer" }
        state.stop()
        XCTAssertEqual(state.messages.last?.status, .stopped)
        XCTAssertFalse(state.canUseResponse)
        XCTAssertTrue(state.canRetry)
        state.followUp = "Continue"
        state.sendFollowUp()
        await wait { provider.requests.count == 2 }
        XCTAssertEqual(provider.requests[1].map(\.content), ["First", "Unfinished answer", "Continue"])
        state.stop()
        state.retry()
        await wait { provider.requests.count == 3 }
        XCTAssertEqual(provider.requests[2].map(\.content), ["First", "Unfinished answer", "Continue"])
        XCTAssertEqual(state.messages.filter { $0.role == .user }.count, 2)
        provider.finish("Finished answer")
        await wait { !state.isGenerating }
        XCTAssertEqual(state.messages.count, 4)
        XCTAssertEqual(state.responseForActions, "Finished answer")
    }

    func testSwitchingConversationSavesProgressAndDraftAcrossRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: url)
        let provider = ChatTestProvider()
        let state = FloaterState(provider: provider, historyStore: store)
        state.start(PromptRequest(prompt: "First"))
        await wait { provider.requests.count == 1 }
        provider.update("Saved partial")
        await wait { state.response == "Saved partial" }
        state.followUp = "Unsent draft"
        state.start(PromptRequest(prompt: "Second"))
        await wait { provider.requests.count == 2 }
        provider.finish("Second reply")
        await wait { !state.isGenerating }
        let restarted = HistoryStore(fileURL: url)
        let first = try XCTUnwrap(restarted.entries.first { $0.request.prompt == "First" })
        XCTAssertEqual(first.draft, "Unsent draft")
        XCTAssertEqual(first.messages.last?.content, "Saved partial")
        XCTAssertEqual(first.messages.last?.status, .stopped)
        state.restore(first)
        XCTAssertEqual(state.followUp, "Unsent draft")
        XCTAssertEqual(state.messages, first.messages)
        XCTAssertEqual(provider.requests.count, 2)
    }

    func testContextFailureDoesNotAutomaticallyCompactOrDropMessages() async {
        let provider = ChatTestProvider()
        provider.failure = ChatGenerationError.contextLimit
        let state = FloaterState(provider: provider)
        let prompt = String(repeating: "Keep this. ", count: 1000)
        state.start(PromptRequest(prompt: prompt))
        await wait { !state.isGenerating }
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(state.messages.first?.content, prompt)
        XCTAssertEqual(state.messages.last?.status, .failed)
        XCTAssertNil(state.conversation?.summary)
        XCTAssertTrue(state.errorMessage?.localizedCaseInsensitiveContains("start a new conversation") == true)
        XCTAssertTrue(state.canRetry)
    }

    func testManualCompactionPreservesMessagesAndDraftAndCanBeCancelled() async throws {
        let provider = ChatTestProvider()
        let store = HistoryStore(fileURL: nil)
        let state = FloaterState(provider: provider, historyStore: store)
        var saved = HistoryEntry(request: PromptRequest(prompt: "The project is Cedar"), response: "Noted")
        saved.messages += [ChatMessage(role: .user, content: "Use blue"), ChatMessage(role: .assistant, content: "Blue it is")]
        state.restore(saved)
        state.followUp = "My draft"
        state.compact()
        await wait { provider.requests.count == 1 }
        state.stop()
        XCTAssertNil(state.conversation?.summary)
        XCTAssertEqual(state.messages, saved.messages)
        XCTAssertEqual(state.followUp, "My draft")

        state.compact()
        await wait { provider.requests.count == 2 }
        provider.finish("The project is named Cedar.")
        await wait { !state.isGenerating }
        XCTAssertEqual(state.messages, saved.messages)
        XCTAssertEqual(state.followUp, "My draft")
        XCTAssertEqual(state.conversation?.summary?.throughMessageID, saved.messages[1].id)
        XCTAssertEqual(store.entries.first?.summary?.content, "The project is named Cedar.")
        state.sendFollowUp()
        await wait { provider.requests.count == 3 }
        XCTAssertTrue(provider.requests[2][0].content.contains("The project is named Cedar."))
        XCTAssertFalse(provider.requests[2].contains { $0.content == "The project is Cedar" })
        XCTAssertTrue(provider.requests[2].contains { $0.content.contains("Use blue") })
        XCTAssertEqual(provider.requests[2].last?.content, "My draft")
        provider.finish("Done")
        await wait { !state.isGenerating }
    }

    func testFailedCompactionLeavesExistingMemoryAndMessagesUnchanged() async {
        let provider = ChatTestProvider()
        provider.failure = ChatGenerationError.failed("Test failure")
        let state = FloaterState(provider: provider)
        var entry = HistoryEntry(request: PromptRequest(prompt: "Original"), response: "Reply")
        entry.summary = ConversationSummary(content: "Existing summary", throughMessageID: entry.messages[1].id)
        state.restore(entry)
        state.compact()
        await wait { !state.isGenerating }
        XCTAssertEqual(state.conversation, entry)
        XCTAssertNotNil(state.actionErrorMessage)
    }

    func testEditAsNewKeepsOriginalConversationAndDraft() {
        let store = HistoryStore(fileURL: nil)
        let state = FloaterState(provider: TestProvider(), historyStore: store)
        let entry = HistoryEntry(request: PromptRequest(prompt: "Original", title: "Title"), response: "Reply")
        state.restore(entry)
        state.followUp = "Draft"
        state.beginEditing()
        XCTAssertEqual(state.prompt, "Original")
        XCTAssertEqual(state.screen, .newRequest)
        XCTAssertNil(state.currentRequest)
        XCTAssertEqual(store.entries.first?.draft, "Draft")
        XCTAssertTrue(state.cancelEditing())
        XCTAssertEqual(state.conversation?.id, entry.id)
        XCTAssertEqual(state.followUp, "Draft")
    }

    func testComposerEnterSendsShiftEnterAddsNewlineAndSendingWaitsForReply() async throws {
        let provider = ChatTestProvider()
        let state = FloaterState(provider: provider)
        state.restore(request: PromptRequest(prompt: "Original"), response: "First reply")
        let window = makeWindow(state: state)
        defer { window.close(); state.stop() }
        let editor = try XCTUnwrap(textViews(in: window.contentView!).first { $0.isEditable })
        XCTAssertTrue(window.firstResponder === editor)
        state.followUp = "Next"
        settle(window)
        sendKey("\r", code: 36, modifiers: .shift, to: window)
        XCTAssertTrue(state.followUp.contains("\n"))
        sendKey("\r", code: 36, to: window)
        await wait { provider.requests.count == 1 }
        XCTAssertTrue(state.isGenerating)
        XCTAssertEqual(state.messages.filter { $0.role == .user }.count, 2)
        state.followUp = "Draft while waiting"
        settle(window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertEqual(state.followUp, "Draft while waiting")
        provider.finish("Second reply")
        await wait { !state.isGenerating }
        settle(window)
        XCTAssertTrue(window.firstResponder === editor, "Completion must not steal the composer's focus")
        XCTAssertTrue(buttons(in: window.contentView!).contains { $0.accessibilityLabel() == "Send" && $0.isEnabled })
    }

    func testLegacyHistoryMigrationAndInterruptedRestart() throws {
        let legacy = Data("""
        [{"id":"00000000-0000-0000-0000-000000000001","createdAt":0,"request":{"prompt":"Translate","input":"Hola"},"response":"Hello"}]
        """.utf8)
        let old = try JSONDecoder().decode([HistoryEntry].self, from: legacy)[0]
        XCTAssertEqual(old.messages.map(\.content), ["Translate\n\nHola", "Hello"])
        XCTAssertEqual(old.updatedAt, old.createdAt)
        var generating = old
        generating.messages.append(ChatMessage(role: .assistant, content: "Partial", status: .generating))
        let restored = try JSONDecoder().decode(HistoryEntry.self, from: JSONEncoder().encode(generating))
        XCTAssertEqual(restored.messages.last?.status, .stopped)
        XCTAssertEqual(restored.id, old.id)
    }

    func testExpandingTheOriginalPromptWhileStreamingShowsItsBeginning() async throws {
        let provider = ChatTestProvider()
        let state = FloaterState(provider: provider)
        state.start(PromptRequest(prompt: String(repeating: "Original prompt line.\n", count: 100)))
        state.isPromptExpanded = false
        await wait { provider.requests.count == 1 }
        let controller = FloatingPanelController(state: state)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { controller.hide(); state.stop() }
        provider.update(String(repeating: "Generated reply line.\n", count: 100))
        await wait { !state.response.isEmpty }
        settle(window)
        let scroll = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        state.isPromptExpanded = true
        settle(window)
        let prompt = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first {
            $0.identifier?.rawValue == "promptText"
        })
        XCTAssertEqual(prompt.contentView.bounds.minY, 0, accuracy: 2)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        let nextReply = state.response + "More text"
        provider.update(nextReply)
        await wait { state.response == nextReply }
        settle(window)
        XCTAssertEqual(prompt.contentView.bounds.minY, 0, accuracy: 2)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.maxY, scroll.documentView!.bounds.maxY - 3)
    }

    func testLongErrorsLeaveTheComposerAndActionsInsideTheWindow() throws {
        let state = FloaterState(provider: TestProvider())
        state.presentFailure(PromptRequest(prompt: "Original"), message: String(repeating: "A detailed capture error. ", count: 100))
        let controller = FloatingPanelController(state: state)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { controller.hide() }
        settle(window)
        let dismiss = try XCTUnwrap(buttons(in: window.contentView!).first { $0.identifier?.rawValue == "dismiss" })
        let bounds = window.contentView!.convert(dismiss.bounds, from: dismiss)
        XCTAssertGreaterThanOrEqual(bounds.minY, 0)
        XCTAssertLessThanOrEqual(bounds.maxY, window.contentView!.bounds.height)
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for conversation state")
    }
}

@MainActor
private final class ChatTestProvider: AIProvider {
    var requests: [[ChatMessage]] = []
    var failure: (any Error)?
    private var continuation: AsyncThrowingStream<String, any Error>.Continuation?

    func generate(messages: [ChatMessage], onUpdate: @MainActor (String) -> Void) async throws {
        requests.append(messages)
        if let failure { throw failure }
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        self.continuation = continuation
        for try await text in stream { onUpdate(text) }
        try Task.checkCancellation()
    }

    func update(_ text: String) { continuation?.yield(text) }
    func finish(_ text: String) { continuation?.yield(text); continuation?.finish() }
}
