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
}
