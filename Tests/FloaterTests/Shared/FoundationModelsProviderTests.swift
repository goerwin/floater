import FoundationModels
import XCTest
@testable import Floater

@MainActor
final class FoundationModelsProviderTests: XCTestCase {
    func testAppleIntelligenceRemembersEarlierMessages() async throws {
        guard ProcessInfo.processInfo.environment["FLOATER_TEST_APPLE"] == "1" else {
            throw XCTSkip("Set FLOATER_TEST_APPLE=1 to test Apple Intelligence.")
        }
        guard case .available = SystemLanguageModel.default.availability else {
            throw XCTSkip("Apple Intelligence is not ready on this Mac.")
        }
        var response = ""
        try await FoundationModelsProvider().generate(messages: [
            ChatMessage(role: .user, content: "My project is named Cedar. Remember the name."),
            ChatMessage(role: .assistant, content: "Your project is named Cedar."),
            ChatMessage(role: .user, content: "What is my project's name? Answer with the name only.")
        ]) { response = $0 }
        XCTAssertTrue(response.localizedCaseInsensitiveContains("Cedar"), response)
    }
}
