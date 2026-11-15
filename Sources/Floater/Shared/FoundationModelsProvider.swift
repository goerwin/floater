import Foundation
import FoundationModels
import FloaterCore

@MainActor
protocol AIProvider {
    var preparationMessage: String { get }
    var compactionChunkSize: Int { get }
    func generate(messages: [ChatMessage], onUpdate: @MainActor (String) -> Void) async throws
}

extension AIProvider {
    var preparationMessage: String { "Generating response…" }
    var compactionChunkSize: Int { 1000 }

    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        try await generate(messages: [ChatMessage(role: .user, content: request.prompt)], onUpdate: onUpdate)
    }
}

@MainActor
final class FoundationModelsProvider: AIProvider {
    var preparationMessage: String { "Thinking with Apple Intelligence…" }

    func generate(
        messages: [ChatMessage],
        onUpdate: @MainActor (String) -> Void
    ) async throws {
        guard case .available = SystemLanguageModel.default.availability else {
            throw availabilityError()
        }

        let messages = ChatMessage.context(messages)
        guard let prompt = messages.last, prompt.role == .user else { throw ChatGenerationError.emptyResponse }
        let entries: [Transcript.Entry] = messages.dropLast().map { message in
            let segments: [Transcript.Segment] = [.text(.init(content: message.content))]
            return message.role == .user
                ? .prompt(.init(segments: segments))
                : .response(.init(assetIDs: [], segments: segments))
        }
        let session = LanguageModelSession(transcript: Transcript(entries: entries))

        do {
            for try await snapshot in session.streamResponse(to: prompt.content) {
                try Task.checkCancellation()
                onUpdate(snapshot.content)
            }
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            throw ChatGenerationError.contextLimit
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
