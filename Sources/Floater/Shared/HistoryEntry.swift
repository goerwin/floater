import Foundation
import FloaterCore

struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let request: PromptRequest
    var messages: [ChatMessage]
    var draft: String
    var summary: ConversationSummary?

    init(request: PromptRequest, response: String = "", createdAt: Date = .now) {
        id = UUID()
        self.createdAt = createdAt
        updatedAt = createdAt
        self.request = request
        messages = [ChatMessage(role: .user, content: request.prompt)]
        if !response.isEmpty { messages.append(ChatMessage(role: .assistant, content: response)) }
        draft = ""
    }

    var response: String { messages.last(where: { $0.role == .assistant })?.content ?? "" }

    var title: String {
        let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? request.prompt
    }

    func contextMessages(before endIndex: Int? = nil) -> [ChatMessage] {
        let end = endIndex ?? messages.count
        var start = 0
        var context: [ChatMessage] = []
        if let summary, let index = messages.firstIndex(where: { $0.id == summary.throughMessageID }), index < end {
            start = index + 1
            context.append(ChatMessage(role: .user, content: "Earlier conversation, summarized at my request:\n\(summary.content)"))
        }
        context += messages[start..<end]
        return ChatMessage.context(context)
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || ([request.title ?? "", request.prompt, draft] + messages.map(\.content))
            .contains { $0.localizedStandardContains(query) }
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, updatedAt, request, response, messages, draft, summary
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        request = try values.decode(PromptRequest.self, forKey: .request)
        draft = try values.decodeIfPresent(String.self, forKey: .draft) ?? ""
        summary = try values.decodeIfPresent(ConversationSummary.self, forKey: .summary)
        if let saved = try values.decodeIfPresent([ChatMessage].self, forKey: .messages) {
            messages = saved.map { message in
                var message = message
                if message.status == .generating { message.status = .stopped }
                return message
            }
        } else {
            messages = [ChatMessage(role: .user, content: request.prompt),
                        ChatMessage(role: .assistant, content: try values.decode(String.self, forKey: .response))]
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(request, forKey: .request)
        try values.encode(messages, forKey: .messages)
        try values.encode(draft, forKey: .draft)
        try values.encodeIfPresent(summary, forKey: .summary)
    }
}
