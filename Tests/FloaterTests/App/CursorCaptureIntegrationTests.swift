import AppKit
import ApplicationServices
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class CursorCaptureIntegrationTests: XCTestCase {
    func testCapturesOpenMarkdownDocumentAndSelectionWithoutClipboard() async throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipIf(environment["FLOATER_CAPTURE_FIXTURE"] == nil, "Requires a dedicated temporary document in Cursor")
        let path = try XCTUnwrap(environment["FLOATER_CAPTURE_FIXTURE"].flatMap { $0.isEmpty ? nil : $0 }, "Set FLOATER_CAPTURE_FIXTURE to a temporary file open in Cursor")
        let expected = try String(contentsOfFile: path, encoding: .utf8)
        let app = try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.localizedName == "Cursor" })
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var focusedWindow: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        var title: CFTypeRef?
        if let focusedWindow, CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            AXUIElementCopyAttributeValue(unsafeDowncast(focusedWindow, to: AXUIElement.self), kAXTitleAttribute as CFString, &title)
        }
        guard (title as? String)?.contains(URL(fileURLWithPath: path).lastPathComponent) == true else {
            XCTFail("Focus the dedicated capture-test document before running this test")
            return
        }
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused)
        let editor = try XCTUnwrap(focused)
        guard CFGetTypeID(editor) == AXUIElementGetTypeID() else { return XCTFail("Expected the test editor") }
        let textElement = unsafeDowncast(editor, to: AXUIElement.self)
        var originalSelection: CFTypeRef?
        AXUIElementCopyAttributeValue(textElement, kAXSelectedTextRangeAttribute as CFString, &originalSelection)
        defer {
            if let originalSelection {
                AXUIElementSetAttributeValue(textElement, kAXSelectedTextRangeAttribute as CFString, originalSelection)
            }
        }
        try setSelection(CFRange(location: 0, length: 0), in: textElement)
        try await Task.sleep(for: .milliseconds(100))
        let clipboardChangeCount = NSPasteboard.general.changeCount
        let provider = CaptureCheckProvider()
        let state = FloaterState(provider: provider)
        let controller = FloatingPanelController(state: state)
        defer { controller.hide() }
        let url = try XCTUnwrap(PromptURL.makeURL(
            for: PromptRequest(prompt: "Fix grammar"), previousProcessID: app.processIdentifier, captureInput: true
        ))
        await controller.handle(url, fallbackApplication: nil)
        for _ in 0..<50 where provider.prompt == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(provider.prompt, "Fix grammar\n\n" + expected)

        controller.hide()
        let selection = try XCTUnwrap(expected.split(separator: "\n").first.map(String.init))
        let range = (expected as NSString).range(of: selection)
        try setSelection(CFRange(location: range.location, length: range.length), in: textElement)
        try await Task.sleep(for: .milliseconds(100))
        provider.prompt = nil
        await controller.handle(url, fallbackApplication: nil)
        for _ in 0..<50 where provider.prompt == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(state.errorMessage)
        XCTAssertEqual(provider.prompt, "Fix grammar\n\n" + selection)
        XCTAssertEqual(NSPasteboard.general.changeCount, clipboardChangeCount)
    }

    private func setSelection(_ range: CFRange, in element: AXUIElement) throws {
        var range = range
        let value = try XCTUnwrap(AXValueCreate(.cfRange, &range))
        XCTAssertEqual(AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value), .success)
    }
}

@MainActor
private final class CaptureCheckProvider: AIProvider {
    var prompt: String?

    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        prompt = request.prompt
        onUpdate("Captured")
    }
}
