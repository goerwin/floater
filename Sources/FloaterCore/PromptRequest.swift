import Foundation

public struct PromptRequest: Equatable, Sendable {
    public let prompt: String
    public let input: String
    public let title: String?

    public init(prompt: String, input: String = "", title: String? = nil) {
        self.prompt = prompt
        self.input = input
        self.title = title
    }
}

public struct RoutedPrompt: Equatable, Sendable {
    public let request: PromptRequest
    public let previousProcessID: Int32?

    public init(request: PromptRequest, previousProcessID: Int32? = nil) {
        self.request = request
        self.previousProcessID = previousProcessID
    }
}

public enum PromptURL {
    public static let scheme = "floater"
    public static let host = "prompt"

    public static func makeURL(
        for request: PromptRequest,
        previousProcessID: Int32? = nil
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var queryItems = [
            URLQueryItem(name: "prompt", value: request.prompt),
            URLQueryItem(name: "input", value: request.input)
        ]

        if let title = request.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }

        components.queryItems = queryItems

        if let previousProcessID {
            components.queryItems?.append(
                URLQueryItem(name: "previousPID", value: String(previousProcessID))
            )
        }

        return components.url
    }

    public static func parse(_ url: URL) -> RoutedPrompt? {
        guard url.scheme == scheme, url.host == host,
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let prompt = queryItems.first(where: { $0.name == "prompt" })?.value,
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let input = queryItems.first(where: { $0.name == "input" })?.value ?? ""
        let title = queryItems.first(where: { $0.name == "title" })?.value
        let previousProcessID = queryItems
            .first(where: { $0.name == "previousPID" })?
            .value
            .flatMap(Int32.init)

        return RoutedPrompt(
            request: PromptRequest(prompt: prompt, input: input, title: title),
            previousProcessID: previousProcessID
        )
    }
}
