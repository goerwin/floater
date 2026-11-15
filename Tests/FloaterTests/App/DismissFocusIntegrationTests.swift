import AppKit
import ApplicationServices
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class DismissFocusIntegrationTests: XCTestCase {
    func testActivatedFloaterReturnsKeyboardFocusToTheLastAppOnDismiss() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FLOATER_TEST_DISMISS_FOCUS"] == "1", "Requires Chrome and Cursor running")
        _ = NSApplication.shared
        let apps = NSWorkspace.shared.runningApplications
        let cursor = try XCTUnwrap(apps.first { $0.localizedName == "Cursor" })
        let chrome = try XCTUnwrap(apps.first { $0.bundleIdentifier == "com.google.Chrome" })
        let originalApp = NSWorkspace.shared.frontmostApplication
        let originalPolicy = NSApp.activationPolicy()
        let wasHidden = NSApp.isHidden
        NSApp.setActivationPolicy(.accessory)
        defer {
            if !wasHidden { NSApp.unhideWithoutActivation() }
            NSApp.setActivationPolicy(originalPolicy)
            originalApp?.activate()
        }

        let controller = FloatingPanelController(
            state: FloaterState(provider: TestProvider()),
            accessibility: AccessibilityAccess(isTrusted: { false }, requestAccess: {})
        )
        defer { controller.hide() }
        for target in [cursor, chrome] {
            for useEscape in [true, false] {
                await BackgroundTextReplacer.activateForCapture(target)
                let appElement = AXUIElementCreateApplication(target.processIdentifier)
                var focusedBefore: CFTypeRef?
                AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedBefore)
                let originalFocus = try XCTUnwrap(focusedBefore)
                var originalSelection: CFTypeRef?
                if CFGetTypeID(originalFocus) == AXUIElementGetTypeID() {
                    AXUIElementCopyAttributeValue(
                        unsafeDowncast(originalFocus, to: AXUIElement.self),
                        kAXSelectedTextRangeAttribute as CFString, &originalSelection
                    )
                }

                controller.show(previousApplication: cursor)
                let window = try XCTUnwrap(controller.window)
                window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
                NSApp.activate(ignoringOtherApps: true)
                await waitUntil { NSApp.isActive }
                XCTAssertTrue(NSApp.isActive)
                window.makeKeyAndOrderFront(nil)
                settle(window)

                if useEscape {
                    sendKey("\u{1b}", code: 53, to: window)
                } else {
                    let dismiss = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Dismiss" })
                    dismiss.performClick(nil)
                }
                await waitUntil { target.isActive }
                XCTAssertFalse(controller.isVisible)
                XCTAssertTrue(target.isActive, "Dismiss must return keyboard focus to \(target.localizedName ?? "the last app")")
                await waitUntil {
                    var focused: CFTypeRef?
                    AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
                    return focused.map { CFEqual(originalFocus, $0) } == true
                }
                var focusedAfter: CFTypeRef?
                AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedAfter)
                XCTAssertTrue(focusedAfter.map { CFEqual(originalFocus, $0) } == true, "Dismiss must preserve the focused input in \(target.localizedName ?? "the last app") (Escape: \(useEscape))")
                if let originalSelection {
                    var selectionAfter: CFTypeRef?
                    AXUIElementCopyAttributeValue(
                        unsafeDowncast(originalFocus, to: AXUIElement.self),
                        kAXSelectedTextRangeAttribute as CFString, &selectionAfter
                    )
                    XCTAssertTrue(selectionAfter.map { CFEqual(originalSelection, $0) } == true, "Dismiss must preserve the caret and selection")
                }
            }
        }
    }

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

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
