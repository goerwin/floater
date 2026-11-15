import Foundation

struct ChatMessage: Codable, Equatable, Identifiable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    enum Status: String, Codable, Sendable { case complete, generating, stopped, failed }

    let id: UUID
    let role: Role
    var content: String
    var status: Status
    var error: String?

    init(role: Role, content: String, status: Status = .complete) {
        id = UUID()
        self.role = role
        self.content = content
        self.status = status
    }

    static func context(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result: [ChatMessage] = []
        for message in messages where !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if result.last?.role == message.role {
                result[result.count - 1].content += "\n\n" + message.content
            } else {
                result.append(message)
            }
        }
        return result
    }
}

struct ConversationSummary: Codable, Equatable {
    let content: String
    let throughMessageID: UUID
}

enum ChatGenerationError: LocalizedError {
    case contextLimit, emptyResponse, runnerFailed, failed(String)

    static func displayMessage(_ message: String) -> String {
        if message.hasPrefix("Gemma could not finish this request.") { return Self.runnerFailed.localizedDescription }
        return message
    }

    var errorDescription: String? {
        switch self {
        case .contextLimit: "This conversation has reached the model's context limit. Start a new conversation. Your messages and draft are saved."
        case .emptyResponse: "The model returned an empty reply. Try again."
        case .runnerFailed: "Gemma couldn't finish this reply. Retry or choose another model."
        case .failed(let message): message
        }
    }
}
