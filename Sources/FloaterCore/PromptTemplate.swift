import Foundation

public struct PromptTemplate: Equatable, Sendable {
    public static let marker = "{{input}}"
    public let source: String

    public init(_ source: String) throws {
        guard source.components(separatedBy: Self.marker).count == 2 else {
            throw PromptInputError.templateMarker
        }
        self.source = source
    }

    public func render(input: String) throws -> String {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PromptInputError.emptyInput
        }
        let parts = source.components(separatedBy: Self.marker)
        return parts[0] + input + parts[1]
    }
}

public enum PromptInputError: LocalizedError {
    case promptRequired
    case conflictingPrompts
    case templateMarker
    case inputSource
    case emptyInput

    public var errorDescription: String? {
        switch self {
        case .promptRequired:
            "Provide a non-empty --prompt or --prompt-template value."
        case .conflictingPrompts:
            "Use either --prompt or --prompt-template, not both."
        case .templateMarker:
            "A prompt template must contain exactly one {{input}} marker."
        case .inputSource:
            "A prompt template needs exactly one input source: --input or --capture-input (input or capture=1 in a URL)."
        case .emptyInput:
            "Template input must contain text. Select or supply non-empty text."
        }
    }
}
