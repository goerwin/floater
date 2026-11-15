import AppKit
import ApplicationServices
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class SlackCaptureIntegrationTests: XCTestCase {
    func testCapturesDraftAndSelectionWithoutChangingDraftOrClipboard() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FLOATER_TEST_SLACK"] == "1", "Requires an open Slack chat with a draft")
        let app = try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.localizedName == "Slack" })
        let previousApp = NSWorkspace.shared.frontmostApplication
        defer { previousApp?.activate() }
        app.activate()
        for _ in 0..<20 where !app.isActive { try await Task.sleep(for: .milliseconds(25)) }

        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.5)
        AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        let focused = try XCTUnwrap(attribute(kAXFocusedUIElementAttribute, from: application))
        XCTAssertEqual(CFGetTypeID(focused), AXUIElementGetTypeID())
        let editor = unsafeDowncast(focused, to: AXUIElement.self)
        let original = try XCTUnwrap(attribute(kAXValueAttribute, from: editor) as? String)
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return XCTFail("The Slack composer must have a draft to test")
        }
        let rangeValue = try XCTUnwrap(attribute(kAXSelectedTextRangeAttribute, from: editor))
        XCTAssertEqual(CFGetTypeID(rangeValue), AXValueGetTypeID())
        let originalRange = unsafeDowncast(rangeValue, to: AXValue.self)
        defer {
            if attribute(kAXValueAttribute, from: editor) as? String == original {
                AXUIElementSetAttributeValue(editor, kAXSelectedTextRangeAttribute as CFString, originalRange)
            }
        }
        try setSelection(CFRange(location: 0, length: 0), in: editor)
        try await Task.sleep(for: .milliseconds(100))
        let clipboardChangeCount = NSPasteboard.general.changeCount
        let provider = SlackCaptureProvider()
        let state = FloaterState(provider: provider)
        let controller = FloatingPanelController(state: state)
        defer { controller.hide() }
        let url = try XCTUnwrap(PromptURL.makeURL(
            for: PromptRequest(prompt: "Fix grammar"), previousProcessID: app.processIdentifier, captureInput: true
        ))
        await controller.handle(url, fallbackApplication: nil)
        for _ in 0..<50 where provider.prompt == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(provider.prompt, "Fix grammar\n\n" + original)
        print("SLACK_WHOLE_DRAFT_CAPTURE: \(provider.prompt == "Fix grammar\n\n" + original), characters: \(original.count)")

        controller.hide()
        let word = try XCTUnwrap(original.split(whereSeparator: \.isWhitespace).first.map(String.init))
        let range = (original as NSString).range(of: word)
        try setSelection(CFRange(location: range.location, length: range.length), in: editor)
        try await Task.sleep(for: .milliseconds(100))
        provider.prompt = nil
        await controller.handle(url, fallbackApplication: nil)
        for _ in 0..<50 where provider.prompt == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(provider.prompt, "Fix grammar\n\n" + word)
        XCTAssertEqual(attribute(kAXValueAttribute, from: editor) as? String, original)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)
        print("SLACK_SELECTION_CAPTURE: \(provider.prompt == "Fix grammar\n\n" + word)")
    }

    private func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func setSelection(_ range: CFRange, in element: AXUIElement) throws {
        var range = range
        let value = try XCTUnwrap(AXValueCreate(.cfRange, &range))
        XCTAssertEqual(AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value), .success)
    }
}

@MainActor
private final class SlackCaptureProvider: AIProvider {
    var prompt: String?

    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        prompt = request.prompt
        onUpdate("Captured")
    }
}
