import Foundation

public struct PromptRequest: Codable, Equatable, Sendable {
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
    public let ignoredBundleIdentifiers: [String]
    public let captureInput: Bool

    public init(
        request: PromptRequest,
        previousProcessID: Int32? = nil,
        ignoredBundleIdentifiers: [String] = [],
        captureInput: Bool = false
    ) {
        self.request = request
        self.previousProcessID = previousProcessID
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers
        self.captureInput = captureInput
    }
}

public enum PromptURL {
    public static let scheme = "floater"
    public static let host = "prompt"

    public static func makeURL(
        for request: PromptRequest,
        previousProcessID: Int32? = nil,
        ignoredBundleIdentifiers: [String] = [],
        captureInput: Bool = false,
        includesInput: Bool = true
    ) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var queryItems = [URLQueryItem(name: "prompt", value: request.prompt)]
        if includesInput {
            queryItems.append(URLQueryItem(name: "input", value: request.input))
        }

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
        for bundleIdentifier in ignoredBundleIdentifiers where !bundleIdentifier.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "ignore", value: bundleIdentifier))
        }
        if captureInput {
            components.queryItems?.append(URLQueryItem(name: "capture", value: "1"))
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

        let inputItem = queryItems.first(where: { $0.name == "input" })
        let input = inputItem?.value ?? ""
        let title = queryItems.first(where: { $0.name == "title" })?.value
        let previousProcessID = queryItems
            .first(where: { $0.name == "previousPID" })?
            .value
            .flatMap(Int32.init)
        let ignoredBundleIdentifiers = queryItems.compactMap { item -> String? in
            guard item.name == "ignore", let value = item.value, !value.isEmpty else { return nil }
            return value
        }
        let captureInput = inputItem == nil && queryItems.contains { $0.name == "capture" && $0.value == "1" }

        return RoutedPrompt(
            request: PromptRequest(prompt: prompt, input: input, title: title),
            previousProcessID: previousProcessID,
            ignoredBundleIdentifiers: ignoredBundleIdentifiers,
            captureInput: captureInput
        )
    }
}
