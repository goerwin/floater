import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class FloaterStateTests: XCTestCase {
    func testCompletedGenerationSavesOnlyFinalResponseAndRestoreDoesNotRerun() async throws {
        let store = HistoryStore(fileURL: nil)
        let provider = ControlledProvider()
        let model = FloaterState(provider: provider, historyStore: store)
        let request = PromptRequest(prompt: "First\n\nInput", title: "Title")
        model.start(request)
        await waitUntil { provider.pending[request.prompt] != nil }
        XCTAssertEqual(model.response, "Partial response")
        XCTAssertFalse(model.canUseResponse)
        XCTAssertTrue(store.entries.isEmpty)
        provider.complete(request.prompt, response: "Final response")
        await waitUntil { !model.isGenerating }
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.request, request)
        XCTAssertEqual(entry.response, "Final response")
        XCTAssertTrue(model.canUseResponse)

        model.showNewRequest()
        model.restore(entry)
        XCTAssertEqual(model.currentRequest, request)
        XCTAssertEqual(model.response, "Final response")
        XCTAssertFalse(model.isGenerating)
        XCTAssertTrue(model.canUseResponse)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testStaleAndFailedGenerationsAreNotSaved() async {
        let store = HistoryStore(fileURL: nil)
        let provider = ControlledProvider()
        let model = FloaterState(provider: provider, historyStore: store)
        model.start(PromptRequest(prompt: "Old"))
        await waitUntil { provider.pending["Old"] != nil }
        model.start(PromptRequest(prompt: "New"))
        await waitUntil { provider.pending["New"] != nil }
        provider.complete("New", response: "New result")
        await waitUntil { !model.isGenerating }
        provider.complete("Old", response: "Stale result")
        await waitUntil { provider.completedCount == 2 }
        XCTAssertEqual(store.entries.map(\.response), ["New result"])
        XCTAssertEqual(model.response, "New result")

        model.start(PromptRequest(prompt: "Failure"))
        await waitUntil { provider.pending["Failure"] != nil }
        provider.fail("Failure")
        await waitUntil { !model.isGenerating }
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.canUseResponse)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testPartialResponseCannotBeCopiedOrReplacedWhileStreamingOrAfterFailure() async throws {
        let provider = ControlledProvider()
        let model = FloaterState(provider: provider)
        model.setCanReplace(true)
        model.start(PromptRequest(prompt: "Failure"))
        await waitUntil { provider.pending["Failure"] != nil }
        var copies = 0
        var replacements = 0
        let window = makeWindow(state: model, onCopy: { copies += 1 }, onReplace: { replacements += 1 })
        defer { window.close() }
        let copy = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Copy" })
        let replace = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Replace" })
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(replace.isEnabled)
        sendKey("c", code: 8, modifiers: .command, to: window)
        sendKey("s", code: 1, modifiers: .command, to: window)
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(replacements, 0)

        provider.fail("Failure")
        await waitUntil { !model.isGenerating }
        settle(window)
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(replace.isEnabled)
        sendKey("c", code: 8, modifiers: .command, to: window)
        sendKey("s", code: 1, modifiers: .command, to: window)
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(replacements, 0)

        model.start(PromptRequest(prompt: "Success"))
        await waitUntil { provider.pending["Success"] != nil }
        provider.complete("Success", response: "Complete result")
        await waitUntil { model.canUseResponse }
        settle(window)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(replace.isEnabled)
        sendKey("c", code: 8, modifiers: .command, to: window)
        sendKey("s", code: 1, modifiers: .command, to: window)
        XCTAssertEqual(copies, 1)
        XCTAssertEqual(replacements, 1)
    }

    func testCancellingAnEditCannotTurnAnInterruptedPreviewIntoACompletedResult() async {
        let provider = ControlledProvider()
        let store = HistoryStore(fileURL: nil)
        let model = FloaterState(provider: provider, historyStore: store)
        model.start(PromptRequest(prompt: "Interrupted"))
        await waitUntil { provider.pending["Interrupted"] != nil }
        model.beginEditing()
        XCTAssertTrue(model.cancelEditing())
        XCTAssertEqual(model.response, "Partial response")
        XCTAssertFalse(model.isGenerating)
        XCTAssertFalse(model.canUseResponse)
        provider.complete("Interrupted", response: "Late result")
        await waitUntil { provider.completedCount == 1 }
        XCTAssertFalse(model.canUseResponse)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testCancelledAndEmptyResponsesAreNotActionableOrSaved() async {
        let provider = ControlledProvider()
        let store = HistoryStore(fileURL: nil)
        let model = FloaterState(provider: provider, historyStore: store)
        model.start(PromptRequest(prompt: "Cancelled"))
        await waitUntil { provider.pending["Cancelled"] != nil }
        provider.pending.removeValue(forKey: "Cancelled")?.resume(throwing: CancellationError())
        await waitUntil { !model.isGenerating }
        XCTAssertTrue(model.response.isEmpty)
        XCTAssertFalse(model.canUseResponse)
        XCTAssertTrue(store.entries.isEmpty)

        model.start(PromptRequest(prompt: "Empty"))
        await waitUntil { provider.pending["Empty"] != nil }
        provider.complete("Empty", response: " \n\t")
        await waitUntil { !model.isGenerating }
        XCTAssertFalse(model.canUseResponse)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRestoringHistoryCancelsActiveGeneration() async {
        let store = HistoryStore(fileURL: nil)
        let provider = ControlledProvider()
        let model = FloaterState(provider: provider, historyStore: store)
        let entry = HistoryEntry(request: PromptRequest(prompt: "Saved"), response: "Saved result")
        model.start(PromptRequest(prompt: "Canceled"))
        await waitUntil { provider.pending["Canceled"] != nil }
        model.restore(entry)
        provider.complete("Canceled", response: "Canceled result")
        await waitUntil { provider.completedCount == 1 }
        XCTAssertEqual(model.currentRequest, entry.request)
        XCTAssertEqual(model.response, entry.response)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(model.isGenerating)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for generation")
    }
}

@MainActor
private final class ControlledProvider: AIProvider {
    var pending: [String: CheckedContinuation<String, any Error>] = [:]
    var callCount = 0
    var completedCount = 0

    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        callCount += 1
        onUpdate("Partial response")
        let response = try await withCheckedThrowingContinuation { continuation in
            pending[request.prompt] = continuation
        }
        onUpdate(response)
        completedCount += 1
    }

    func complete(_ prompt: String, response: String) {
        pending.removeValue(forKey: prompt)?.resume(returning: response)
    }

    func fail(_ prompt: String) {
        pending.removeValue(forKey: prompt)?.resume(throwing: TestError.failed)
    }

    private enum TestError: Error {
        case failed
    }
}
