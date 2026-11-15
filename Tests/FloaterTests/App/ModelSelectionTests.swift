import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class ModelSelectionTests: XCTestCase {
    func testModelSelectionPersistsAcrossLaunchesAndUnknownValuesUseGemma() throws {
        let name = "FloaterModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.selectedModel, .gemma4E4B)
        settings.selectedModel = .appleIntelligence
        XCTAssertEqual(AppSettings(defaults: defaults).selectedModel, .appleIntelligence)
        settings.selectedModel = .gemma4E4B
        XCTAssertEqual(AppSettings(defaults: defaults).selectedModel, .gemma4E4B)
        defaults.set("removed-model", forKey: "selectedModel")
        XCTAssertEqual(AppSettings(defaults: defaults).selectedModel, .gemma4E4B)
    }

    func testChangingModelAppliesToNextRequestWithoutChangingTheActiveRequest() async throws {
        let name = "FloaterModelTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        let apple = RecordingModel()
        let gemma = RecordingModel()
        let provider = SelectedModelProvider(settings: settings, apple: apple, gemma: gemma)
        let request = PromptRequest(prompt: "Keep this prompt exactly as written.\n\n¿Dónde está?")

        let activeRequest = Task { try await provider.generate(request) { _ in } }
        for _ in 0..<100 where gemma.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(gemma.requests, [request])
        XCTAssertTrue(apple.requests.isEmpty)

        settings.selectedModel = .appleIntelligence
        gemma.complete()
        try await activeRequest.value
        XCTAssertTrue(apple.requests.isEmpty)

        apple.waitsForCompletion = false
        var response = ""
        try await provider.generate(request) { response = $0 }
        XCTAssertEqual(apple.requests, [request])
        XCTAssertEqual(response, "Complete")
        XCTAssertEqual(gemma.requests.count, 1)
    }
}

@MainActor
private final class RecordingModel: AIProvider {
    var requests: [PromptRequest] = []
    var waitsForCompletion = true
    private var continuation: CheckedContinuation<Void, Never>?

    func generate(messages: [ChatMessage], onUpdate: @MainActor (String) -> Void) async throws {
        let request = PromptRequest(prompt: messages.last?.content ?? "")
        requests.append(request)
        if waitsForCompletion {
            await withCheckedContinuation { continuation = $0 }
        }
        onUpdate("Complete")
    }

    func complete() {
        continuation?.resume()
        continuation = nil
    }
}
