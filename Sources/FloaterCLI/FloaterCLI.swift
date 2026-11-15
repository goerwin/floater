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
            Usage: floater --prompt <text> [--input <text>] [--capture-input] [--title <text>] [--ignore <bundle-id>]...
                   floater --prompt-template <text> (--input <text> | --capture-input) [--title <text>] [--ignore <bundle-id>]...

            Use - to read a prompt, template, or input from standard input.
            Templates require exactly one {{input}} marker and one non-empty input source.
            Input replaces the marker literally, once. Plain prompts remain literal.
            Repeat --ignore to skip those apps when choosing where to read and replace.
            --capture-input reads selected text, or the focused field when nothing is selected.
            Example: floater --prompt-template "Translate: {{input}}" --capture-input
            """)
            return
        }

        do {
            let routed = try PromptCommand.parse(
                arguments,
                previousProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier
            ) {
                String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
            }
            guard let url = PromptURL.makeURL(for: routed) else {
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
}

private enum CLIError: LocalizedError {
    case appNotAvailable
    case invalidRequest

    var errorDescription: String? {
        switch self {
        case .appNotAvailable:
            "Floater could not open the request. Launch Floater.app once to register its URL scheme."
        case .invalidRequest:
            "The request could not be encoded as a Floater URL."
        }
    }
}
