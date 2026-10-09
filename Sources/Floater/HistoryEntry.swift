import Foundation
import FloaterCore

struct HistoryEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let request: PromptRequest
    let response: String

    init(request: PromptRequest, response: String, createdAt: Date = .now) {
        id = UUID()
        self.createdAt = createdAt
        self.request = request
        self.response = response
    }

    var title: String {
        let title = request.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? request.prompt
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || [request.title ?? "", request.prompt, request.input, response]
            .contains { $0.localizedStandardContains(query) }
    }
}
