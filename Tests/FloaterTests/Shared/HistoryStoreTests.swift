import Foundation
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class HistoryStoreTests: XCTestCase {
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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

}
