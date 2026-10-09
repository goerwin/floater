import Foundation
import FoundationModels
import FloaterCore

@MainActor
protocol AIProvider {
    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws
}

@MainActor
final class FoundationModelsProvider: AIProvider {
    func generate(
        _ request: PromptRequest,
        onUpdate: @MainActor (String) -> Void
    ) async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw availabilityError()
        }

        let session = LanguageModelSession(
            instructions: "Follow the user's prompt and return the requested result."
        )
        let prompt = request.input.isEmpty
            ? request.prompt
            : "\(request.prompt)\n\n<transcript>\n\(request.input)\n</transcript>"

        for try await snapshot in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            onUpdate(snapshot.content)
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

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): message
        }
    }
}
