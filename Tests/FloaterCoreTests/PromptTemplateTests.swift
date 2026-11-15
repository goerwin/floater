import XCTest
@testable import FloaterCore

final class PromptTemplateTests: XCTestCase {
    private let template = "<user-text>\n{{input}}\n</user-text>"

    func testTypedAndCapturedInputProduceTheSameLiteralPromptThroughURLs() throws {
        let input = "  ¿Dónde? `code` & <tag> {{input}} </user-text>\nhttps://example.com/?a=1&b=2  "
        let typed = try command(["--prompt-template", template, "--input", input, "--title", "Fix"])
        let captured = try command(["--prompt-template", template, "--capture-input", "--title", "Fix"])
        let url = try XCTUnwrap(PromptURL.makeURL(for: captured))
        let received = try XCTUnwrap(PromptURL.decode(url))
        let resolved = try received.resolving(input: input)

        XCTAssertEqual(resolved, typed.request)
        XCTAssertEqual(resolved.prompt, "<user-text>\n" + input + "\n</user-text>")
        XCTAssertEqual(resolved.title, "Fix")
        let typedURL = try XCTUnwrap(PromptURL.makeURL(for: typed))
        XCTAssertEqual(try PromptURL.decode(typedURL)?.request, resolved)
        XCTAssertNil(try PromptURL.decode(typedURL)?.promptTemplate)
    }

    func testURLTemplateWithExplicitInputRendersOnce() throws {
        var components = URLComponents()
        components.scheme = "floater"
        components.host = "prompt"
        components.queryItems = [
            URLQueryItem(name: "template", value: template),
            URLQueryItem(name: "input", value: "literal {{input}} & quotes \"'"),
            URLQueryItem(name: "title", value: "Title"),
            URLQueryItem(name: "ignore", value: "com.example.launcher"),
        ]
        let routed = try XCTUnwrap(PromptURL.decode(try XCTUnwrap(components.url)))
        XCTAssertEqual(routed.request.prompt, "<user-text>\nliteral {{input}} & quotes \"'\n</user-text>")
        XCTAssertEqual(routed.request.title, "Title")
        XCTAssertEqual(routed.ignoredBundleIdentifiers, ["com.example.launcher"])
        XCTAssertFalse(routed.captureInput)
        XCTAssertNil(routed.promptTemplate)
    }

    func testTemplateModeRejectsInvalidMarkersSourcesAndBlankInput() throws {
        let invalid = [
            ["--prompt-template", "no marker", "--input", "text"],
            ["--prompt-template", "{{input}} {{input}}", "--capture-input"],
            ["--prompt-template", template],
            ["--prompt-template", template, "--input", "text", "--capture-input"],
            ["--prompt-template", template, "--input", ""],
            ["--prompt-template", template, "--input", " \n\t"],
            ["--prompt", "literal", "--prompt-template", template, "--input", "text"],
        ]
        for arguments in invalid {
            XCTAssertThrowsError(try command(arguments), arguments.description) { error in
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
        let captured = try command(["--prompt-template", template, "--capture-input"])
        XCTAssertThrowsError(try captured.resolving(input: "\n\t "))
    }

    func testURLValidationMatchesTemplateCommandValidation() throws {
        for query in [
            "template=no-marker&input=text",
            "template=%7B%7Binput%7D%7D",
            "template=%7B%7Binput%7D%7D&input=text&capture=1",
            "template=%7B%7Binput%7D%7D&input=",
            "template=%7B%7Binput%7D%7D&input=%20%0A",
            "prompt=literal&template=%7B%7Binput%7D%7D&input=text",
        ] {
            let url = try XCTUnwrap(URL(string: "floater://prompt?" + query))
            XCTAssertThrowsError(try PromptURL.decode(url), query)
            XCTAssertNil(PromptURL.parse(url))
        }
    }

    func testPlainPromptsKeepLiteralMarkersAndLegacyInputPrecedence() throws {
        let plain = try command(["--prompt", template])
        XCTAssertEqual(plain.request.prompt, template)
        XCTAssertNil(plain.promptTemplate)
        let legacy = try command(["--prompt", template, "--input", "", "--capture-input"])
        XCTAssertEqual(legacy.request.prompt, template)
        XCTAssertFalse(legacy.captureInput)
    }

    func testTemplateAndInputCanIndividuallyReadStandardInput() throws {
        var reads = 0
        let fromTemplate = try PromptCommand.parse(["--prompt-template", "-", "--input", "hello"]) {
            reads += 1
            return self.template
        }
        XCTAssertEqual(fromTemplate.request.prompt, "<user-text>\nhello\n</user-text>")
        let fromInput = try PromptCommand.parse(["--prompt-template=" + template, "--input=-"]) {
            reads += 1
            return "  literal {{input}}\n"
        }
        XCTAssertEqual(fromInput.request.prompt, "<user-text>\n  literal {{input}}\n\n</user-text>")
        XCTAssertEqual(reads, 2)
        XCTAssertThrowsError(try PromptCommand.parse(["--prompt-template", "-", "--input", "-"]) {
            XCTFail("An ambiguous input stream must not be read")
            return ""
        })
    }

    func testCommandReportsMissingValuesAndUnknownOptionsWithoutReadingInput() {
        for arguments in [["--prompt-template"], ["--unknown"], ["--capture-input=yes"], ["--input", "-"]] {
            XCTAssertThrowsError(try command(arguments))
        }
    }

    private func command(_ arguments: [String]) throws -> RoutedPrompt {
        try PromptCommand.parse(arguments) {
            XCTFail("Unexpected standard input read")
            return ""
        }
    }
}
