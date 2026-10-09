import AppKit
import XCTest
@testable import Floater

@MainActor
final class AppLaunchTests: XCTestCase {
    func testOpeningAppIconShowsEmptyComposer() async throws {
        let application = NSApplication.shared
        let existingWindows = application.windows
        let delegate = AppDelegate()
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification, object: application))
        defer {
            for window in application.windows where !existingWindows.contains(window) {
                window.orderOut(nil)
            }
        }

        delegate.applicationDidFinishLaunching(Notification(
            name: NSApplication.didFinishLaunchingNotification,
            object: application,
            userInfo: [NSApplication.launchIsDefaultUserInfoKey: true]
        ))
        try await Task.sleep(for: .milliseconds(200))

        let window = try XCTUnwrap(application.windows.first { $0.isVisible && !existingWindows.contains($0) })
        let prompt = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "prompt" }) as? NSTextView)
        let input = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "input" }) as? NSTextView)
        XCTAssertEqual(prompt.string, "")
        XCTAssertEqual(input.string, "")
        XCTAssertTrue(window.firstResponder === prompt)

        for mode in ["composer", "history", "hidden"] {
            if mode == "history" {
                delegate.showHistory()
            } else {
                let editor = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "prompt" }) as? NSTextView)
                editor.insertText("Previous draft", replacementRange: editor.selectedRange())
                if mode == "hidden" { window.orderOut(nil) }
            }

            XCTAssertFalse(delegate.applicationShouldHandleReopen(application, hasVisibleWindows: window.isVisible))
            try await Task.sleep(for: .milliseconds(200))

            XCTAssertTrue(window.isVisible, mode)
            let reopenedPrompt = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "prompt" }) as? NSTextView)
            let reopenedInput = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "input" }) as? NSTextView)
            XCTAssertEqual(reopenedPrompt.string, "", mode)
            XCTAssertEqual(reopenedInput.string, "", mode)
            XCTAssertTrue(window.firstResponder === reopenedPrompt, mode)
        }
    }

    func testNonDefaultLaunchDoesNotOpenEmptyComposer() async throws {
        let application = NSApplication.shared
        let existingWindows = application.windows
        let delegate = AppDelegate()
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification, object: application))
        defer {
            for window in application.windows where !existingWindows.contains(window) {
                window.orderOut(nil)
            }
        }

        delegate.applicationDidFinishLaunching(Notification(
            name: NSApplication.didFinishLaunchingNotification,
            object: application,
            userInfo: [NSApplication.launchIsDefaultUserInfoKey: false]
        ))
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(application.windows.contains { $0.isVisible && !existingWindows.contains($0) })
    }
}
