import XCTest
@testable import FloaterCore

final class CaptureRoutingTests: XCTestCase {
    func testRecentMemoryKeepsTwoDistinctAppsAndSkipsFloater() {
        var recent: [String] = []
        recent = RecentAppMemory.remember("editor", recent: recent, isOwnApp: false)
        recent = RecentAppMemory.remember("alfred", recent: recent, isOwnApp: false)
        recent = RecentAppMemory.remember("alfred", recent: recent, isOwnApp: false)
        XCTAssertEqual(recent, ["alfred", "editor"])
        recent = RecentAppMemory.remember("floater", recent: recent, isOwnApp: true)
        XCTAssertEqual(recent, ["alfred", "editor"])
        recent = RecentAppMemory.remember("finder", recent: recent, isOwnApp: false)
        XCTAssertEqual(recent, ["finder", "alfred"])
    }

    func testRoutingUsesPreviousAppThenStopsAfterTwoRememberedApps() {
        let alfred = TargetCandidate(name: "Alfred", bundleIdentifier: "com.runningwithcrayons.Alfred", isRunning: true)
        let editor = TargetCandidate(name: "Code", bundleIdentifier: "com.microsoft.VSCode", isRunning: true)
        let older = TargetCandidate(name: "Notes", bundleIdentifier: "com.apple.Notes", isRunning: true)
        let ignored = ["com.runningwithcrayons.Alfred"]

        XCTAssertEqual(
            TargetRouting.select(
                previous: alfred, recent: [alfred, editor, older],
                ignoredBundleIdentifiers: ignored, ownBundleIdentifier: "com.floater"
            ),
            .recent(1)
        )
        XCTAssertNil(
            TargetRouting.select(
                previous: alfred, recent: [alfred, editor],
                ignoredBundleIdentifiers: ignored + ["com.microsoft.VSCode"], ownBundleIdentifier: "com.floater"
            )
        )
        XCTAssertEqual(
            TargetRouting.select(
                previous: editor, recent: [alfred],
                ignoredBundleIdentifiers: ignored, ownBundleIdentifier: "com.floater"
            ),
            .previous
        )
        XCTAssertEqual(
            TargetRouting.considered(previous: alfred, recent: [alfred, editor, older], ownBundleIdentifier: "com.floater"),
            [alfred, editor]
        )
    }

    func testRoutingSkipsNotificationCenterWithoutBeingAsked() {
        let center = TargetCandidate(
            name: "Notification Center", bundleIdentifier: "com.apple.UserNotificationCenter", isRunning: true
        )
        let editor = TargetCandidate(name: "Code", bundleIdentifier: "com.microsoft.VSCode", isRunning: true)

        XCTAssertEqual(
            TargetRouting.select(
                previous: center, recent: [center, editor],
                ignoredBundleIdentifiers: [], ownBundleIdentifier: "com.floater"
            ),
            .recent(1)
        )
        XCTAssertEqual(
            TargetRouting.considered(previous: center, recent: [center], ownBundleIdentifier: "com.floater"),
            []
        )
    }

    func testFieldChoicePrefersSelectionAndDoesNotTreatABlankFieldAsUnread() {
        XCTAssertEqual(
            FieldTextChoice.interpret(elementFound: true, isSecure: false, selectedText: "  hi  ", fieldValue: "all"),
            .selection("  hi  ")
        )
        XCTAssertEqual(
            FieldTextChoice.interpret(elementFound: true, isSecure: false, selectedText: " \n", fieldValue: "hello"),
            .field("hello")
        )
        XCTAssertEqual(
            FieldTextChoice.interpret(elementFound: true, isSecure: false, selectedText: " ", fieldValue: " "),
            .empty
        )
        XCTAssertEqual(
            FieldTextChoice.interpret(elementFound: true, isSecure: false, selectedText: "", fieldValue: nil),
            .failed
        )
        XCTAssertEqual(
            FieldTextChoice.interpret(elementFound: false, isSecure: false, selectedText: nil, fieldValue: nil),
            .failed
        )
        XCTAssertEqual(
            FieldTextChoice.interpret(
                elementFound: true, isSecure: false, selectedText: nil, fieldValue: "all", selectionUnreadable: true
            ),
            .failed
        )
        XCTAssertEqual(
            FieldTextChoice.interpret(elementFound: true, isSecure: true, selectedText: "secret", fieldValue: "secret"),
            .unreadable
        )
    }

    func testCaptureMessagesNameBundleIdentifiersAndStayQuietWithoutOne() {
        let alfred = TargetCandidate(name: "Alfred", bundleIdentifier: "com.runningwithcrayons.Alfred", isRunning: true)
        let helper = TargetCandidate(name: "Helper", bundleIdentifier: nil, isRunning: true)
        let unnamed = TargetCandidate(name: nil, bundleIdentifier: "com.example.tool", isRunning: true)

        XCTAssertEqual(
            CaptureMessages.noApplication(ignoredAny: true, considered: [alfred, helper]),
            "Floater could not find the app behind the ignored ones: Alfred (com.runningwithcrayons.Alfred), Helper. Switch to that app and try again."
        )
        XCTAssertEqual(
            CaptureMessages.noApplication(ignoredAny: true, considered: []),
            "Floater could not find the app behind the ignored ones. Switch to that app and try again."
        )
        XCTAssertEqual(
            CaptureMessages.noApplication(ignoredAny: false, considered: [unnamed]),
            "Floater could not find an app to use: com.example.tool. Switch to that app and try again."
        )
        XCTAssertEqual(
            CaptureMessages.noApplication(ignoredAny: false, considered: []),
            "Floater could not find an app to use. Switch to that app and try again."
        )
        XCTAssertEqual(
            CaptureMessages.emptyField(for: alfred),
            "Select some text, or focus a field that has text. To skip it, pass com.runningwithcrayons.Alfred to --ignore."
        )
        XCTAssertEqual(
            CaptureMessages.unreadableField(for: helper),
            "Floater could not read the focused field."
        )
        XCTAssertEqual(
            CaptureMessages.accessibility(for: alfred),
            "Allow Floater in System Settings > Privacy & Security > Accessibility, then try again. To skip it, pass com.runningwithcrayons.Alfred to --ignore."
        )
    }
}
