import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class LlamaCPPProviderTests: XCTestCase {
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
            XCTAssertTrue(store.entries.isEmpty)
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
