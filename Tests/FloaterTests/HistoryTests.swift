import Foundation
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class HistoryTests: XCTestCase {
    func testHistorySurvivesRestartAndDeletion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("Floater/history.json")
        let store = HistoryStore(fileURL: fileURL)
        let request = PromptRequest(prompt: "Translate\nthis", input: "Hola 👋", title: "Translation")
        store.record(request, response: "Hello 👋\nWorld")
        store.record(PromptRequest(prompt: "Second"), response: "Another result")

        let restarted = HistoryStore(fileURL: fileURL)
        XCTAssertNil(restarted.errorMessage)
        XCTAssertEqual(restarted.entries, store.entries)
        XCTAssertEqual(restarted.entries.last?.request, request)
        XCTAssertEqual(restarted.entries.last?.response, "Hello 👋\nWorld")
        let id = try XCTUnwrap(restarted.entries.first?.id)
        restarted.delete(id)
        XCTAssertEqual(HistoryStore(fileURL: fileURL).entries, [store.entries[1]])

        restarted.clear()
        XCTAssertTrue(HistoryStore(fileURL: fileURL).entries.isEmpty)
    }

    func testOnlyLatest100ResultsAreRetained() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let store = HistoryStore(fileURL: fileURL)
        for index in 0..<105 {
            store.record(PromptRequest(prompt: "Request \(index)"), response: "Result \(index)")
        }
        let restarted = HistoryStore(fileURL: fileURL)
        XCTAssertEqual(restarted.entries.count, 100)
        XCTAssertEqual(restarted.entries.first?.request.prompt, "Request 104")
        XCTAssertEqual(restarted.entries.last?.request.prompt, "Request 5")
        store.record(PromptRequest(prompt: "Empty"), response: " \n")
        XCTAssertEqual(store.entries, restarted.entries)
    }

    func testSearchIncludesTitlePromptInputAndResponse() {
        let entry = HistoryEntry(
            request: PromptRequest(prompt: "Translate", input: "Hola", title: "Spanish"),
            response: "Hello"
        )
        for query in ["", "  ", "SPANISH", "translate", " hola ", "hello"] {
            XCTAssertTrue(entry.matches(query), query)
        }
        XCTAssertFalse(entry.matches("missing"))
        XCTAssertEqual(entry.title, "Spanish")
        XCTAssertEqual(HistoryEntry(request: PromptRequest(prompt: "Prompt", title: " "), response: "Result").title, "Prompt")
    }

    func testCorruptHistoryIsPreservedUntilExplicitlyCleared() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("history.json")
        let originalData = Data("invalid history".utf8)
        try originalData.write(to: fileURL)
        let store = HistoryStore(fileURL: fileURL)
        XCTAssertNotNil(store.errorMessage)
        store.record(PromptRequest(prompt: "New"), response: "Result")
        XCTAssertEqual(try Data(contentsOf: fileURL), originalData)
        XCTAssertTrue(store.entries.isEmpty)

        store.clear()
        XCTAssertNil(store.errorMessage)
        store.record(PromptRequest(prompt: "New"), response: "Result")
        XCTAssertEqual(HistoryStore(fileURL: fileURL).entries.count, 1)
    }

    func testWriteFailureIsReportedAndCanRecover() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("Floater")
        try Data().write(to: blocker)
        let store = HistoryStore(fileURL: blocker.appendingPathComponent("history.json"))
        store.record(PromptRequest(prompt: "New"), response: "Result")
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(store.entries.isEmpty)

        try FileManager.default.removeItem(at: blocker)
        store.record(PromptRequest(prompt: "New"), response: "Result")
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.entries.count, 1)
    }

    func testCompletedGenerationSavesOnlyFinalResponseAndRestoreDoesNotRerun() async throws {
        let store = HistoryStore(fileURL: nil)
        let provider = ControlledProvider()
        let model = FloaterViewModel(provider: provider, historyStore: store)
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

        model.showComposer()
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
        let model = FloaterViewModel(provider: provider, historyStore: store)
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
        let model = FloaterViewModel(provider: provider, historyStore: store)
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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
