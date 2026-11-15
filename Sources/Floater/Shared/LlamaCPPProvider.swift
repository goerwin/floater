import AppKit
import FloaterCore
import OSLog

@MainActor
final class LlamaCPPProvider: AIProvider {
    static let repository = "google/gemma-4-E4B-it-qat-q4_0-gguf"
    static let modelFile = "gemma-4-E4B_q4_0-it.gguf"
    private static let endMarker = " [end of text]"
    private static let logger = Logger(subsystem: "com.goerwin.Floater", category: "ModelRunner")
    // Gemma's text-only format omits the token that enables thinking.
    private static let chatTemplate = #"""
    {{- bos_token -}}
    {%- for message in messages -%}
    {{- '<|turn>' + ('model' if message['role'] == 'assistant' else message['role']) + '\n' + message['content'] + '<turn|>\n' -}}
    {%- endfor -%}
    {%- if add_generation_prompt -%}
    {{- '<|turn>model\n' -}}
    {%- endif -%}
    """#

    private let executableURL: URL?
    private let modelURL: URL?
    var compactionChunkSize: Int { 3000 }

    var preparationMessage: String {
        cachedModelURL == nil ? "Downloading Gemma 4 E4B on first use…" : "Preparing Gemma 4 E4B…"
    }

    init(executableURL: URL? = nil, modelURL: URL? = nil) {
        self.executableURL = executableURL
        self.modelURL = modelURL
    }

    func generate(messages: [ChatMessage], onUpdate: @MainActor (String) -> Void) async throws {
        try Task.checkCancellation()
        let messages = ChatMessage.context(messages)
        guard let prompt = messages.last, prompt.role == .user else { throw ChatGenerationError.emptyResponse }
        guard let executable = executableURL ?? Self.homebrewExecutable,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw GenerationError.failed("Install llama.cpp with Homebrew to use Gemma: brew install llama.cpp")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let promptFile = directory.appendingPathComponent("prompt.txt")
        try Data(prompt.content.utf8).write(to: promptFile, options: .atomic)
        var historyTemplate: URL?
        if messages.count > 1 {
            let history = messages.dropLast().map { ["role": $0.role.rawValue, "content": $0.content] }
            let encoder = JSONEncoder()
            // JSON's optional slash escape is not a valid Jinja string escape.
            encoder.outputFormatting = .withoutEscapingSlashes
            let data = try encoder.encode(history)
            let json = String(decoding: data, as: UTF8.self)
            let template = "{% set previous_messages = \(json) %}\n" + Self.chatTemplate
                .replacingOccurrences(of: "in messages", with: "in previous_messages + messages")
            let file = directory.appendingPathComponent("conversation.jinja")
            try Data(template.utf8).write(to: file, options: .atomic)
            historyTemplate = file
        }
        let outputFile = directory.appendingPathComponent("response.txt")
        let errorFile = directory.appendingPathComponent("error.txt")
        FileManager.default.createFile(atPath: outputFile.path, contents: nil)
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputFile)
        let errors = try FileHandle(forWritingTo: errorFile)
        let reader = try FileHandle(forReadingFrom: outputFile)
        defer {
            try? output.close()
            try? errors.close()
            try? reader.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments(promptFile: promptFile, historyTemplate: historyTemplate)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            if process.isRunning { process.terminate() }
        }
        defer {
            NotificationCenter.default.removeObserver(terminationObserver)
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        var bytes = Data()
        var previousResponse = ""
        while true {
            try Task.checkCancellation()
            if let chunk = try reader.readToEnd() { bytes.append(chunk) }
            if let text = String(data: bytes, encoding: .utf8) {
                let response = Self.responseText(text)
                if response != previousResponse {
                    previousResponse = response
                    onUpdate(response)
                }
            }
            if !process.isRunning { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        process.waitUntilExit()
        if let chunk = try reader.readToEnd() { bytes.append(chunk) }
        try Task.checkCancellation()

        let diagnostic = (try? String(contentsOf: errorFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if diagnostic.localizedCaseInsensitiveContains("exceeds the context")
            || diagnostic.localizedCaseInsensitiveContains("context size exceeded")
            || diagnostic.localizedCaseInsensitiveContains("context window is full")
            || diagnostic.localizedCaseInsensitiveContains("prompt is too long") {
            throw ChatGenerationError.contextLimit
        }
        guard process.terminationStatus == 0 else {
            Self.logger.error("llama-completion failed with exit status \(process.terminationStatus).")
            throw ChatGenerationError.runnerFailed
        }
        guard let text = String(data: bytes, encoding: .utf8) else {
            throw GenerationError.failed("Gemma returned unreadable text. Try again.")
        }
        guard text.trimmingCharacters(in: .newlines).hasSuffix(Self.endMarker) else {
            throw ChatGenerationError.failed("Gemma reached its response or context limit. Start a new conversation, or Retry for another attempt.")
        }
        let response = Self.responseText(text)
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GenerationError.failed("Gemma returned an empty response. Try again.")
        }
        if response != previousResponse { onUpdate(response) }
    }

    private func arguments(promptFile: URL, historyTemplate: URL?) -> [String] {
        var arguments = [
            "--conversation", "--single-turn", "--jinja",
            "--temp", "0",
            "--no-display-prompt", "--simple-io", "--color", "off", "--log-colors", "off",
            "--no-perf", "--log-verbosity", "1", "--no-escape", "--no-context-shift",
            "--ctx-size", "8192", "--predict", "4096", "--file", promptFile.path
        ]
        if let historyTemplate {
            arguments += ["--chat-template-file", historyTemplate.path]
        } else {
            arguments += ["--chat-template", Self.chatTemplate]
        }
        if let model = cachedModelURL {
            arguments += ["--model", model.path, "--offline"]
        } else {
            arguments += ["--hf-repo", Self.repository, "--hf-file", Self.modelFile]
        }
        return arguments
    }

    private var cachedModelURL: URL? {
        if let modelURL { return modelURL }
        let environment = ProcessInfo.processInfo.environment
        let hub: URL
        if let path = environment["HF_HUB_CACHE"], !path.isEmpty {
            hub = URL(fileURLWithPath: path)
        } else {
            let home = environment["HF_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/huggingface")
            hub = home.appendingPathComponent("hub")
        }
        let snapshots = hub.appendingPathComponent("models--\(Self.repository.replacingOccurrences(of: "/", with: "--"))/snapshots")
        guard let revisions = try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil) else {
            return nil
        }
        return revisions.map { $0.appendingPathComponent(Self.modelFile) }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
    }

    private static var homebrewExecutable: URL? {
        ["/opt/homebrew/bin/llama-completion", "/usr/local/bin/llama-completion"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func responseText(_ output: String) -> String {
        var response = output
        let thoughtPrefix = "<|channel>thought\n"
        if thoughtPrefix.hasPrefix(response) { return "" }
        if response.hasPrefix(thoughtPrefix) {
            guard let end = response.range(of: "<channel|>") else { return "" }
            response = String(response[end.upperBound...])
        }
        let withoutNewlines = response.trimmingCharacters(in: .newlines)
        if withoutNewlines.hasSuffix(endMarker) {
            let end = response.range(of: endMarker, options: .backwards)!.lowerBound
            return String(response[..<end])
        }
        for count in stride(from: endMarker.count, through: 1, by: -1) {
            let suffix = String(endMarker.prefix(count))
            if response.hasSuffix(suffix) {
                response.removeLast(count)
                break
            }
        }
        return response
    }

    private enum GenerationError: LocalizedError {
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .failed(let message): message
            }
        }
    }
}
