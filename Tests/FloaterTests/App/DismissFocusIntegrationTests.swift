import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class DismissFocusIntegrationTests: XCTestCase {
    func testDismissalKeepsTheCurrentAppAfterSwitchingAwayFromTheRequestSource() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FLOATER_TEST_DISMISS_FOCUS"] == "1", "Requires Chrome and Cursor running")
        let apps = NSWorkspace.shared.runningApplications
        let source = try XCTUnwrap(apps.first { $0.localizedName == "Cursor" })
        let browser = try XCTUnwrap(apps.first { $0.bundleIdentifier == "com.google.Chrome" })
        let originalApp = NSWorkspace.shared.frontmostApplication
        defer { originalApp?.activate() }

        for useEscape in [true, false] {
            let state = FloaterState(provider: TestProvider())
            state.restore(request: PromptRequest(prompt: "Focus regression"), response: "Completed response")
            let controller = FloatingPanelController(
                state: state, accessibility: AccessibilityAccess(isTrusted: { false }, requestAccess: {})
            )
            defer { controller.hide() }
            await BackgroundTextReplacer.activateForCapture(source)
            controller.show(previousApplication: source)
            let window = try XCTUnwrap(controller.window)
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))

            await BackgroundTextReplacer.activateForCapture(browser)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, browser.processIdentifier)
            window.makeKeyAndOrderFront(nil)
            settle(window)
            XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, browser.processIdentifier)

            if useEscape {
                sendKey("\u{1b}", code: 53, to: window)
            } else {
                let dismiss = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Dismiss" })
                dismiss.performClick(nil)
                settle(window)
            }
            XCTAssertFalse(controller.isVisible)
            XCTAssertEqual(
                NSWorkspace.shared.frontmostApplication?.processIdentifier, browser.processIdentifier,
                "Dismissing Floater must leave Chrome active instead of activating the old request source"
            )
        }
    }
}
