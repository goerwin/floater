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
        let request = PromptRequest(prompt: "First", input: "Input", title: "Title")
        model.start(request)
        await waitUntil { provider.pending["First"] != nil }
        XCTAssertEqual(model.response, "Partial response")
        XCTAssertTrue(store.entries.isEmpty)
        provider.complete("First", response: "Final response")
        await waitUntil { !model.isGenerating }
        let entry = try XCTUnwrap(store.entries.first)
        XCTAssertEqual(entry.request, request)
        XCTAssertEqual(entry.response, "Final response")

        model.showNewRequest()
        model.restore(entry)
        XCTAssertEqual(model.currentRequest, request)
        XCTAssertEqual(model.response, "Final response")
        XCTAssertFalse(model.isGenerating)
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
        XCTAssertEqual(store.entries.count, 1)
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
