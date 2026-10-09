import AppKit
import Foundation
import FloaterCore

@main
@MainActor
struct FloaterCLI {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.contains("-h") {
            print("""
            Usage: floater --prompt <text> [--input <text>] [--title <text>]

            Use --input - to read input from standard input.
            Example: floater --prompt "Translate this" --input "hola mundo" --title "Translation"
            """)
            return
        }

        do {
            let request = try parse(arguments)
            let previousProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard let url = PromptURL.makeURL(
                for: request,
                previousProcessID: previousProcessID
            ) else {
                throw CLIError.invalidRequest
            }

            guard NSWorkspace.shared.open(url) else {
                throw CLIError.appNotAvailable
            }
        } catch {
            FileHandle.standardError.write(Data("floater: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func parse(_ arguments: [String]) throws -> PromptRequest {
        var prompt: String?
        var input = ""
        var title: String?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let option = String(parts[0])

            guard option == "--prompt" || option == "--input" || option == "--title" else {
                throw CLIError.unknownOption(option)
            }

            let value: String
            if parts.count == 2 {
                value = String(parts[1])
            } else {
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(option)
                }
                value = arguments[index]
            }

            if option == "--prompt" {
                prompt = value
            } else if option == "--input" {
                input = value
            } else {
                title = value
            }
            index += 1
        }

        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.promptRequired
        }

        if input == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            input = String(decoding: data, as: UTF8.self)
        }

        return PromptRequest(prompt: prompt, input: input, title: title)
    }
}

private enum CLIError: LocalizedError {
    case appNotAvailable
    case invalidRequest
    case missingValue(String)
    case promptRequired
    case unknownOption(String)

    var errorDescription: String? {
        switch self {
        case .appNotAvailable:
            return "Floater could not open the request. Launch Floater.app once to register its URL scheme."
        case .invalidRequest:
            return "The request could not be encoded as a Floater URL."
        case .missingValue(let option):
            return "\(option) needs a value."
        case .promptRequired:
            return "Provide a non-empty --prompt value."
        case .unknownOption(let option):
            return "Unknown option: \(option). Run 'floater --help' for usage."
        }
    }
}
