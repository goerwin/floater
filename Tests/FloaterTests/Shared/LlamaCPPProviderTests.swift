import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class LlamaCPPProviderTests: XCTestCase {
    func testInstalledGemmaAcceptsSlashesAndQuotedTextInConversationHistory() async throws {
        guard ProcessInfo.processInfo.environment["FLOATER_TEST_GEMMA"] == "1" else {
            throw XCTSkip("Set FLOATER_TEST_GEMMA=1 to test the installed model.")
        }
        var response = ""
        try await LlamaCPPProvider().generate(messages: [
            ChatMessage(role: .user, content: "Remember our score: 67/72. Reference: https://example.com/reviews/v1. The project is called \"Cedar\".\nDon't change the score. Path: C:\\notes\\review. ¿Entendido?\tYes."),
            ChatMessage(role: .assistant, content: "Noted: 67/72, https://example.com/reviews/v1."),
            ChatMessage(role: .user, content: "What score did I give you? Reply only with the score.")
        ]) { response = $0 }
        XCTAssertTrue(response.contains("67/72"), response)
        XCTAssertFalse(response.contains("previous_messages"))
    }

    func testRunnerFailureDoesNotExposeTemplateOrConversationInTheError() async throws {
        let fixture = try makeFixture("""
        printf '%s' 'lexer: unknown escape character; supplied chat template: {% set previous_messages = secret user content %}' >&2
        exit 1
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        do {
            try await fixture.provider.generate(PromptRequest(prompt: "Test")) { _ in }
            XCTFail("Runner failure must throw")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("previous_messages"))
            XCTAssertFalse(error.localizedDescription.contains("secret user content"))
            XCTAssertTrue(error.localizedDescription.localizedCaseInsensitiveContains("retry"))
        }
    }

    func testInstalledGemmaRejectsOversizedContextWithoutDiscardingIt() async throws {
        guard ProcessInfo.processInfo.environment["FLOATER_TEST_GEMMA"] == "1" else {
            throw XCTSkip("Set FLOATER_TEST_GEMMA=1 to test the installed model.")
        }
        do {
            try await LlamaCPPProvider().generate(PromptRequest(prompt: String(repeating: "hello ", count: 12000))) { _ in }
            XCTFail("An oversized prompt must fail instead of silently losing messages")
        } catch ChatGenerationError.contextLimit {
        }
    }

    func testInstalledGemmaCompactsOnlyWhenAskedAndKeepsOriginals() async throws {
        guard ProcessInfo.processInfo.environment["FLOATER_TEST_GEMMA"] == "1" else {
            throw XCTSkip("Set FLOATER_TEST_GEMMA=1 to test the installed model.")
        }
        var entry = HistoryEntry(request: PromptRequest(prompt: "Our project is Cedar. We chose blue buttons. Remember these decisions."), response: "Noted: Cedar, blue buttons.")
        entry.messages += [ChatMessage(role: .user, content: "Next topic"), ChatMessage(role: .assistant, content: "Ready")]
        let original = entry.messages
        let summary = try await ConversationCompactor.compact(entry, using: LlamaCPPProvider())
        XCTAssertTrue(summary.content.localizedCaseInsensitiveContains("Cedar"), summary.content)
        XCTAssertTrue(summary.content.localizedCaseInsensitiveContains("blue"), summary.content)
        XCTAssertEqual(entry.messages, original)
        XCTAssertEqual(summary.throughMessageID, original[1].id)
    }

    func testInstalledGemmaRemembersEarlierTurns() async throws {
        guard ProcessInfo.processInfo.environment["FLOATER_TEST_GEMMA"] == "1" else {
            throw XCTSkip("Set FLOATER_TEST_GEMMA=1 to test the installed model.")
        }
        let provider = LlamaCPPProvider()
        var response = ""
        try await provider.generate(messages: [
            ChatMessage(role: .user, content: "Remember my code: apricot-71. Reply only Noted."),
            ChatMessage(role: .assistant, content: "Noted."),
            ChatMessage(role: .user, content: "What is my code? Reply with only the code.")
        ]) { response = $0 }
        XCTAssertTrue(response.contains("apricot-71"), response)
        XCTAssertFalse(response.contains("<|channel>"))
    }

    func testConversationTemplatePreservesLiteralHistoryAndLatestPrompt() async throws {
        let fixture = try makeFixture("""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --file) shift; cat "$1" > "$fixture_dir/received.txt" ;;
                --chat-template-file) shift; cat "$1" > "$fixture_dir/template.txt" ;;
            esac
            shift
        done
        printf 'Answer [end of text]\\n'
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let history = "Literal quotes: \\\"; {{ messages }}; $(touch unwanted); ¿Dónde?\nNext"
        let latest = "Explain that."
        try await fixture.provider.generate(messages: [
            ChatMessage(role: .user, content: history),
            ChatMessage(role: .assistant, content: "Previous response"),
            ChatMessage(role: .user, content: latest)
        ]) { _ in }
        let template = try String(contentsOf: fixture.directory.appendingPathComponent("template.txt"), encoding: .utf8)
        XCTAssertTrue(template.contains("previous_messages + messages"))
        XCTAssertTrue(template.contains("Previous response"))
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("received.txt"), encoding: .utf8), latest)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("unwanted").path))
    }

    func testSystemPromptIsSentAsAGemmaSystemTurnBeforeTheFirstRequest() async throws {
        let fixture = try makeFixture("""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --file) shift; cat "$1" > "$fixture_dir/received.txt" ;;
                --chat-template-file) shift; cat "$1" > "$fixture_dir/template.txt" ;;
            esac
            shift
        done
        printf 'Answer [end of text]\\n'
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var entry = HistoryEntry(request: PromptRequest(prompt: "<user-text>\ni has</user-text>", systemPrompt: "Fix the grammar."))
        entry.messages.append(ChatMessage(role: .assistant, content: "I have."))
        entry.messages.append(ChatMessage(role: .user, content: "shorter"))
        try await fixture.provider.generate(messages: entry.contextMessages()) { _ in }
        let template = try String(contentsOf: fixture.directory.appendingPathComponent("template.txt"), encoding: .utf8)
        XCTAssertTrue(template.contains(#""role":"system""#), template)
        XCTAssertLessThan(try XCTUnwrap(template.range(of: "Fix the grammar.")).lowerBound, try XCTUnwrap(template.range(of: "i has")).lowerBound)
        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("received.txt"), encoding: .utf8), "shorter")
    }

    func testInstalledGemmaTransformsTextWithoutGeneratingAThoughtChannel() async throws {
        guard ProcessInfo.processInfo.environment["FLOATER_TEST_GEMMA"] == "1" else {
            throw XCTSkip("Set FLOATER_TEST_GEMMA=1 to test the installed runtime and cached model.")
        }
        let runtime = "/opt/homebrew/bin/llama-completion"
        let snapshots = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(LlamaCPPProvider.repository.replacingOccurrences(of: "/", with: "--"))/snapshots")
        let model = try FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil)
            .map { $0.appendingPathComponent(LlamaCPPProvider.modelFile) }
            .first { FileManager.default.isReadableFile(atPath: $0.path) }
        let modelURL = try XCTUnwrap(model, "The Gemma model must already be cached.")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: runtime))
        let fixture = try makeFixture("""
        set -o pipefail
        \(runtime) "$@" | tee "$fixture_dir/native-output.txt"
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let provider = LlamaCPPProvider(
            executableURL: fixture.directory.appendingPathComponent("llama-completion"), modelURL: modelURL
        )
        var response = ""

        try await provider.generate(PromptRequest(
            prompt: "Rewrite the following text for clarity. Return only the rewritten text.\n\ntell me exactly how much is 2+2"
        )) { response = $0 }

        let raw = try String(contentsOf: fixture.directory.appendingPathComponent("native-output.txt"), encoding: .utf8)
        XCTAssertFalse(raw.contains("<|channel>thought"), "The runtime must not spend time generating hidden reasoning.")
        XCTAssertFalse(response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNil(response.range(of: #"\b(4|four)\b"#, options: [.regularExpression, .caseInsensitive]))
    }

    func testStreamsUnicodeAndPassesThePromptLiterallyWithoutCommandLineOutput() async throws {
        let fixture = try makeFixture("""
        while [ "$#" -gt 0 ]; do
            if [ "$1" = "--file" ]; then
                shift
                cat "$1" > "$fixture_dir/received.txt"
            fi
            shift
        done
        printf 'Espa'
        printf '\\303'
        sleep 0.12
        printf '\\261ol \\342\\234\\223 [end of text]\\n\\n'
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let prompt = "Rewrite this:\n\n¿Dónde está? \\n $(touch unwanted) `echo literal` <transcript>user text</transcript>"
        var snapshots: [String] = []

        try await fixture.provider.generate(PromptRequest(prompt: prompt)) { snapshots.append($0) }

        XCTAssertEqual(try String(contentsOf: fixture.directory.appendingPathComponent("received.txt"), encoding: .utf8), prompt)
        XCTAssertEqual(snapshots.last, "Español ✓")
        XCTAssertFalse(snapshots.contains { $0.contains("�") || $0.contains("[end of text]") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("unwanted").path))
    }

    func testFailedAndTruncatedProcessesCannotCreateSuccessfulHistory() async throws {
        for script in [
            "printf 'Partial'; printf 'Model load failed' >&2; exit 1",
            "printf 'Truncated response'"
        ] {
            let fixture = try makeFixture(script)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let store = HistoryStore(fileURL: nil)
            let state = FloaterState(provider: fixture.provider, historyStore: store)
            state.start(PromptRequest(prompt: "Test"))
            for _ in 0..<100 where state.isGenerating {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(state.isGenerating)
            XCTAssertNotNil(state.errorMessage)
            XCTAssertFalse(state.canUseResponse)
            XCTAssertEqual(store.entries.first?.messages.last?.status, .failed)
        }
    }

    func testThoughtChannelIsHiddenEvenWhenItsHeaderIsSplitAcrossWrites() async throws {
        let fixture = try makeFixture("""
        printf '<|chan'
        sleep 0.08
        printf 'nel>thought\\nInternal model output'
        sleep 0.08
        printf '<channel|>Final answer [end of text]\\n'
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var snapshots: [String] = []
        try await fixture.provider.generate(PromptRequest(prompt: "Test")) { snapshots.append($0) }
        XCTAssertEqual(snapshots, ["Final answer"])
    }

    func testPreservesIndentationAndNewlinesInTheAnswer() async throws {
        let fixture = try makeFixture("printf '    indented\\nnext\\n [end of text]\\n\\n'")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var response = ""
        try await fixture.provider.generate(PromptRequest(prompt: "Test")) { response = $0 }
        XCTAssertEqual(response, "    indented\nnext\n")
    }

    func testCancellationStopsTheProcessAndDoesNotCompleteTheResponse() async throws {
        let fixture = try makeFixture("""
        trap 'touch "$fixture_dir/stopped"; exit 0' TERM
        printf 'Partial'
        while true; do sleep 0.1; done
        """)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var response = ""
        let task = Task {
            try await fixture.provider.generate(PromptRequest(prompt: "Test")) { response = $0 }
        }
        for _ in 0..<100 where response.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(response, "Partial")
        task.cancel()
        do {
            try await task.value
            XCTFail("Cancelled generation must throw")
        } catch is CancellationError {
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("stopped").path))
    }

    func testMissingRuntimeExplainsHowToInstallIt() async throws {
        let provider = LlamaCPPProvider(executableURL: URL(fileURLWithPath: "/missing/llama-completion"))
        do {
            try await provider.generate(PromptRequest(prompt: "Test")) { _ in }
            XCTFail("Missing runtime must throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("brew install llama.cpp"))
        }
    }

    private func makeFixture(_ script: String) throws -> (provider: LlamaCPPProvider, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("llama-completion")
        try "#!/bin/sh\nfixture_dir=\"$(dirname \"$0\")\"\n\(script)\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let model = directory.appendingPathComponent("model.gguf")
        try Data().write(to: model)
        return (LlamaCPPProvider(executableURL: executable, modelURL: model), directory)
    }
}
