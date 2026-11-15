import Foundation

public enum PromptCommand {
    public static func parse(
        _ arguments: [String],
        previousProcessID: Int32? = nil,
        readStandardInput: () -> String
    ) throws -> RoutedPrompt {
        var prompt: String?
        var template: String?
        var input: String?
        var title: String?
        var ignoredBundleIdentifiers: [String] = []
        var captureInput = false
        var index = 0

        while index < arguments.count {
            let parts = arguments[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let option = String(parts[0])
            if option == "--capture-input" {
                guard parts.count == 1 else { throw PromptCommandError.unexpectedValue(option) }
                captureInput = true
                index += 1
                continue
            }
            guard ["--prompt", "--prompt-template", "--input", "--title", "--ignore"].contains(option) else {
                throw PromptCommandError.unknownOption(option)
            }
            let value: String
            if parts.count == 2 {
                value = String(parts[1])
            } else {
                index += 1
                guard index < arguments.count else { throw PromptCommandError.missingValue(option) }
                value = arguments[index]
            }
            switch option {
            case "--prompt": prompt = value
            case "--prompt-template": template = value
            case "--input": input = value
            case "--ignore":
                guard !value.isEmpty else { throw PromptCommandError.missingValue(option) }
                ignoredBundleIdentifiers.append(value)
            default: title = value
            }
            index += 1
        }

        guard prompt != nil || template != nil else { throw PromptInputError.promptRequired }
        if template != nil {
            guard prompt == nil else { throw PromptInputError.conflictingPrompts }
            guard (input != nil) != captureInput else { throw PromptInputError.inputSource }
            if template == "-", input == "-" { throw PromptCommandError.sharedStandardInput }
        }
        if prompt == "-" || template == "-" || input == "-" {
            let text = readStandardInput()
            if prompt == "-" { prompt = text }
            if template == "-" { template = text }
            if input == "-" { input = text }
        }
        return try RoutedPrompt(
            prompt: prompt, template: template, input: input, title: title,
            previousProcessID: previousProcessID,
            ignoredBundleIdentifiers: ignoredBundleIdentifiers, captureInput: captureInput
        )
    }
}

public enum PromptCommandError: LocalizedError {
    case missingValue(String)
    case unexpectedValue(String)
    case unknownOption(String)
    case sharedStandardInput

    public var errorDescription: String? {
        switch self {
        case .missingValue(let option): "\(option) needs a value."
        case .unexpectedValue(let option): "\(option) does not take a value."
        case .unknownOption(let option): "Unknown option: \(option). Run 'floater --help' for usage."
        case .sharedStandardInput: "Read either the template or its input from standard input, not both."
        }
    }
}
