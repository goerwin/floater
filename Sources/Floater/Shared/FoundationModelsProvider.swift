import Foundation
import FoundationModels
import FloaterCore

@MainActor
protocol AIProvider {
    var preparationMessage: String { get }
    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws
}

extension AIProvider {
    var preparationMessage: String { "Generating response…" }
}

@MainActor
final class FoundationModelsProvider: AIProvider {
    var preparationMessage: String { "Thinking with Apple Intelligence…" }

    func generate(
        _ request: PromptRequest,
        onUpdate: @MainActor (String) -> Void
    ) async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw availabilityError()
        }

        let session = LanguageModelSession()

        do {
            for try await snapshot in session.streamResponse(to: request.prompt) {
                try Task.checkCancellation()
                onUpdate(snapshot.content)
            }
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw ProviderError.inputTooLong
        }
    }

    private func availabilityError() -> LocalizedError {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ProviderError.unavailable("Apple Intelligence is unavailable right now.")
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return ProviderError.unavailable("This Mac does not support Apple Intelligence.")
            case .appleIntelligenceNotEnabled:
                return ProviderError.unavailable("Turn on Apple Intelligence in System Settings, then try again.")
            case .modelNotReady:
                return ProviderError.unavailable("The Apple Intelligence model is still downloading. Try again shortly.")
            @unknown default:
                return ProviderError.unavailable("Apple Intelligence is unavailable: \(String(describing: reason))")
            }
        }
    }
}

private enum ProviderError: LocalizedError {
    case unavailable(String)
    case inputTooLong

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        case .inputTooLong: "This request is too long for Apple Intelligence. Shorten the prompt and try again."
        }
    }
}
