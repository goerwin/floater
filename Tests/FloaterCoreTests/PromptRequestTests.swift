import XCTest
@testable import FloaterCore

final class PromptRequestTests: XCTestCase {
    func testPromptURLRoundTripsFullPromptAndPreviousProcessID() throws {
        let request = PromptRequest(
            prompt: "  Translate this to Spanish:\n\nHello, world! 🌎\nSecond line.\n"
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

    func testPromptURLRoundTripsIgnoreListAndCaptureFlag() throws {
        let request = PromptRequest(prompt: "Fix grammar", title: "Fix Grammar")
        let url = try XCTUnwrap(PromptURL.makeURL(
            for: request,
            previousProcessID: 7,
            ignoredBundleIdentifiers: ["com.example.one", "com.example.two"],
            captureInput: true
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
            RoutedPrompt(request: PromptRequest(prompt: "Fix"), captureInput: false)
        )

        let otherFlag = try XCTUnwrap(URL(string: "floater://prompt?prompt=Fix&capture=true"))
        XCTAssertEqual(
            PromptURL.parse(otherFlag),
            RoutedPrompt(request: PromptRequest(prompt: "Fix"), captureInput: false)
        )
    }

    func testLegacyURLInputIsAppendedWithoutTagsAndOverridesCapture() throws {
        let url = try XCTUnwrap(URL(string: "floater://prompt?prompt=Rewrite&input=%20hello%0Aworld%20&capture=1"))
        XCTAssertEqual(
            PromptURL.parse(url),
            RoutedPrompt(request: PromptRequest(prompt: "Rewrite\n\n hello\nworld "))
        )
    }

    func testLegacyHistoryRequestDecodesIntoOnePromptAndSavesWithoutInput() throws {
        let data = Data(#"{"prompt":"Rewrite","input":"  hello\nworld  ","title":"Saved"}"#.utf8)
        let request = try JSONDecoder().decode(PromptRequest.self, from: data)
        XCTAssertEqual(request, PromptRequest(prompt: "Rewrite\n\n  hello\nworld  ", title: "Saved"))
        let encoded = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["input"])
        XCTAssertEqual(try JSONDecoder().decode(PromptRequest.self, from: encoded), request)
    }

    func testSinglePromptPreservesCallerDelimitersAndWhitespace() throws {
        let request = PromptRequest(prompt: "  Rewrite only this:\n<text>\nhello\n</text>\n")
        let data = try JSONEncoder().encode(request)
        XCTAssertEqual(try JSONDecoder().decode(PromptRequest.self, from: data), request)
        XCTAssertEqual(request.appending(""), request)
    }
}
