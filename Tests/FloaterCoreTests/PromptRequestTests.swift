import XCTest
@testable import FloaterCore

final class PromptRequestTests: XCTestCase {
    func testPromptURLRoundTripsPromptInputAndPreviousProcessID() throws {
        let request = PromptRequest(
            prompt: "Translate this to Spanish",
            input: "Hello, world! 🌎\nSecond line."
        )
        let url = try XCTUnwrap(PromptURL.makeURL(for: request, previousProcessID: 42))

        XCTAssertEqual(
            PromptURL.parse(url),
            RoutedPrompt(request: request, previousProcessID: 42)
        )
    }

    func testParseRequiresFloaterPromptURLAndNonemptyPrompt() throws {
        let wrongScheme = try XCTUnwrap(URL(string: "https://prompt?prompt=hello"))
        let wrongHost = try XCTUnwrap(URL(string: "floater://other?prompt=hello"))
        let emptyPrompt = try XCTUnwrap(URL(string: "floater://prompt?prompt=%20%20"))

        XCTAssertNil(PromptURL.parse(wrongScheme))
        XCTAssertNil(PromptURL.parse(wrongHost))
        XCTAssertNil(PromptURL.parse(emptyPrompt))
    }

    func testParseDefaultsMissingInputAndIgnoresInvalidPreviousProcessID() throws {
        let url = try XCTUnwrap(
            URL(string: "floater://prompt?prompt=Summarize&previousPID=not-a-number")
        )

        XCTAssertEqual(
            PromptURL.parse(url),
            RoutedPrompt(request: PromptRequest(prompt: "Summarize"))
        )
    }

    func testPromptURLRoundTripsIgnoreListAndCapturesOnlyWhenInputIsOmitted() throws {
        let request = PromptRequest(prompt: "Fix grammar", title: "Fix Grammar")
        let url = try XCTUnwrap(PromptURL.makeURL(
            for: request,
            previousProcessID: 7,
            ignoredBundleIdentifiers: ["com.example.one", "com.example.two"],
            captureInput: true,
            includesInput: false
        ))

        XCTAssertEqual(
            PromptURL.parse(url),
            RoutedPrompt(
                request: request,
                previousProcessID: 7,
                ignoredBundleIdentifiers: ["com.example.one", "com.example.two"],
                captureInput: true
            )
        )
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "input" })
    }

    func testCaptureStaysOffWhenInputIsPresentOrTheFlagIsNotOne() throws {
        let provided = try XCTUnwrap(URL(string: "floater://prompt?prompt=Fix&input=&capture=1&ignore="))
        XCTAssertEqual(
            PromptURL.parse(provided),
            RoutedPrompt(request: PromptRequest(prompt: "Fix", input: ""), captureInput: false)
        )

        let otherFlag = try XCTUnwrap(URL(string: "floater://prompt?prompt=Fix&capture=true"))
        XCTAssertEqual(
            PromptURL.parse(otherFlag),
            RoutedPrompt(request: PromptRequest(prompt: "Fix"), captureInput: false)
        )
    }
}
