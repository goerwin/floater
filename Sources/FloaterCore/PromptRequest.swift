import Foundation

public struct PromptRequest: Codable, Equatable, Sendable {
    public let prompt: String
    public let title: String?
    /// Standing instructions sent as the system message before every turn of the conversation.
    public let systemPrompt: String?

    public init(prompt: String, title: String? = nil, systemPrompt: String? = nil) {
        self.prompt = prompt
        self.title = title
        self.systemPrompt = systemPrompt.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }
    }

    public func appending(_ text: String) -> PromptRequest {
        guard !text.isEmpty else { return self }
        return PromptRequest(prompt: prompt.isEmpty ? text : "\(prompt)\n\n\(text)", title: title, systemPrompt: systemPrompt)
    }

    private enum CodingKeys: String, CodingKey {
        case prompt, title, systemPrompt, input
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self = try PromptRequest(
            prompt: values.decode(String.self, forKey: .prompt),
            title: values.decodeIfPresent(String.self, forKey: .title),
            systemPrompt: values.decodeIfPresent(String.self, forKey: .systemPrompt)
        ).appending(values.decodeIfPresent(String.self, forKey: .input) ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(prompt, forKey: .prompt)
        try values.encodeIfPresent(title, forKey: .title)
        try values.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
    }
}

public struct RoutedPrompt: Equatable, Sendable {
    public let request: PromptRequest
    public let previousProcessID: Int32?
    public let ignoredBundleIdentifiers: [String]
    public let captureInput: Bool
    public let promptTemplate: PromptTemplate?

    public init(
        request: PromptRequest,
        previousProcessID: Int32? = nil,
        ignoredBundleIdentifiers: [String] = [],
        captureInput: Bool = false,
        promptTemplate: PromptTemplate? = nil
    ) {
        self.request = request
        self.previousProcessID = previousProcessID
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers
        self.captureInput = captureInput
        self.promptTemplate = promptTemplate
    }

    public init(
        prompt: String?,
        template: String?,
        input: String?,
        title: String? = nil,
        systemPrompt: String? = nil,
        previousProcessID: Int32? = nil,
        ignoredBundleIdentifiers: [String] = [],
        captureInput: Bool = false
    ) throws {
        guard prompt == nil || template == nil else { throw PromptInputError.conflictingPrompts }
        guard let text = template ?? prompt,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptInputError.promptRequired
        }
        let promptTemplate = try template.map(PromptTemplate.init)
        if let promptTemplate {
            guard (input != nil) != captureInput else { throw PromptInputError.inputSource }
            let resolved = try input.map { try promptTemplate.render(input: $0) }
            self.init(
                request: PromptRequest(prompt: resolved ?? text, title: title, systemPrompt: systemPrompt),
                previousProcessID: previousProcessID,
                ignoredBundleIdentifiers: ignoredBundleIdentifiers,
                captureInput: captureInput,
                promptTemplate: resolved == nil ? promptTemplate : nil
            )
        } else {
            self.init(
                request: PromptRequest(prompt: text, title: title, systemPrompt: systemPrompt).appending(input ?? ""),
                previousProcessID: previousProcessID,
                ignoredBundleIdentifiers: ignoredBundleIdentifiers,
                captureInput: captureInput && input == nil
            )
        }
    }

    public func resolving(input: String) throws -> PromptRequest {
        guard let promptTemplate else { return request.appending(input) }
        return PromptRequest(
            prompt: try promptTemplate.render(input: input), title: request.title, systemPrompt: request.systemPrompt
        )
    }
}

public enum PromptURL {
    public static let scheme = "floater"
    public static let host = "prompt"

    public static func makeURL(
        for request: PromptRequest,
        previousProcessID: Int32? = nil,
        ignoredBundleIdentifiers: [String] = [],
        captureInput: Bool = false
    ) -> URL? {
        makeURL(for: RoutedPrompt(
            request: request,
            previousProcessID: previousProcessID,
            ignoredBundleIdentifiers: ignoredBundleIdentifiers,
            captureInput: captureInput
        ))
    }

    public static func makeURL(for routed: RoutedPrompt) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var queryItems = [URLQueryItem(
            name: routed.promptTemplate == nil ? "prompt" : "template",
            value: routed.promptTemplate?.source ?? routed.request.prompt
        )]

        if let title = routed.request.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }
        if let systemPrompt = routed.request.systemPrompt {
            queryItems.append(URLQueryItem(name: "system", value: systemPrompt))
        }

        components.queryItems = queryItems

        if let previousProcessID = routed.previousProcessID {
            components.queryItems?.append(
                URLQueryItem(name: "previousPID", value: String(previousProcessID))
            )
        }
        for bundleIdentifier in routed.ignoredBundleIdentifiers where !bundleIdentifier.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "ignore", value: bundleIdentifier))
        }
        if routed.captureInput {
            components.queryItems?.append(URLQueryItem(name: "capture", value: "1"))
        }

        return components.url
    }

    public static func parse(_ url: URL) -> RoutedPrompt? {
        try? decode(url)
    }

    public static func decode(_ url: URL) throws -> RoutedPrompt? {
        guard url.scheme == scheme, url.host == host,
              let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }

        let prompt = queryItems.first(where: { $0.name == "prompt" }).map { $0.value ?? "" }
        let template = queryItems.first(where: { $0.name == "template" }).map { $0.value ?? "" }
        let inputItem = queryItems.first(where: { $0.name == "input" })
        let input = inputItem.map { $0.value ?? "" }
        let title = queryItems.first(where: { $0.name == "title" })?.value
        let systemPrompt = queryItems.first(where: { $0.name == "system" })?.value
        let previousProcessID = queryItems
            .first(where: { $0.name == "previousPID" })?
            .value
            .flatMap(Int32.init)
        let ignoredBundleIdentifiers = queryItems.compactMap { item -> String? in
            guard item.name == "ignore", let value = item.value, !value.isEmpty else { return nil }
            return value
        }
        let captureInput = queryItems.contains { $0.name == "capture" && $0.value == "1" }

        return try RoutedPrompt(
            prompt: prompt,
            template: template,
            input: input,
            title: title,
            systemPrompt: systemPrompt,
            previousProcessID: previousProcessID,
            ignoredBundleIdentifiers: ignoredBundleIdentifiers,
            captureInput: captureInput
        )
    }
}
