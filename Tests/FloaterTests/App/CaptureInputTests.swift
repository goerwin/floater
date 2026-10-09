import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class CaptureInputTests: XCTestCase {
    func testCaptureReadsSelectionAndReplaceWillNotSelectAll() async throws {
        let app = try runningApp()
        let store = HistoryStore(fileURL: nil)
        let provider = CountingProvider()
        let model = FloaterState(provider: provider, historyStore: store)
        let target = StubPasteTarget(selection: .selected)
        var reads = 0
        var activations = 0
        var selectionOnly: Bool?
        let controller = makeController(model: model, read: { _ in
            reads += 1
            return FieldCapture(
                target: target, elementFound: true, isSecure: false,
                selectedText: "  hello  ", fieldValue: "whole field", selectionUnreadable: false
            )
        }, activate: { _ in
            activations += 1
        }, replace: { _, _, _, restrictToSelection in
            selectionOnly = restrictToSelection
            throw TextReplacementError.selectionRequired
        })
        defer { controller.hide() }

        try await controller.handle(captureURL(previous: app), fallbackApplication: nil)
        await waitUntil { store.entries.count == 1 }

        XCTAssertEqual(reads, 1)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(provider.requests.map(\.input), ["  hello  "])
        XCTAssertEqual(store.entries.map(\.request.input), ["  hello  "])
        XCTAssertEqual(model.currentRequest?.prompt, "Fix")

        target.selection = .none
        controller.replaceAndDismiss()
        await waitUntil { model.actionErrorMessage != nil }
        XCTAssertEqual(selectionOnly, true)
        XCTAssertEqual(model.actionErrorMessage, TextReplacementError.selectionRequired.localizedDescription)
    }

    func testFailedReadActivatesOnceAndThenUsesTheField() async throws {
        let app = try runningApp()
        let provider = CountingProvider()
        let model = FloaterState(provider: provider)
        var reads = 0
        var activations = 0
        let controller = makeController(model: model, read: { _ in
            reads += 1
            let found = reads > 1
            return FieldCapture(
                target: StubPasteTarget(selection: .none), elementFound: found, isSecure: false,
                selectedText: found ? " " : nil, fieldValue: found ? "field value" : nil, selectionUnreadable: false
            )
        }, activate: { _ in
            activations += 1
        })
        defer { controller.hide() }

        try await controller.handle(captureURL(previous: app), fallbackApplication: nil)
        await waitUntil { provider.requests.count == 1 }

        XCTAssertEqual(reads, 2)
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(provider.requests.first?.input, "field value")
    }

    func testEmptyFieldSkipsTheModelAndNamesTheApp() async throws {
        let app = try runningApp()
        let provider = CountingProvider()
        let store = HistoryStore(fileURL: nil)
        let model = FloaterState(provider: provider, historyStore: store)
        var activations = 0
        let controller = makeController(model: model, read: { _ in
            FieldCapture(
                target: StubPasteTarget(selection: .none), elementFound: true, isSecure: false,
                selectedText: " ", fieldValue: " ", selectionUnreadable: false
            )
        }, activate: { _ in
            activations += 1
        })
        defer { controller.hide() }

        try await controller.handle(captureURL(previous: app), fallbackApplication: nil)

        XCTAssertEqual(activations, 0)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(model.screen, .results)
        XCTAssertFalse(model.isGenerating)
        XCTAssertEqual(model.currentRequest?.prompt, "Fix")
        let bundleIdentifier = try XCTUnwrap(app.bundleIdentifier)
        XCTAssertEqual(
            model.errorMessage,
            "Select some text, or focus a field that has text. To skip it, pass \(bundleIdentifier) to --ignore."
        )
    }

    func testIgnoredPreviousAppUsesTheNextRememberedApp() async throws {
        let apps = try runningApps(2)
        let blocked = apps[0]
        let editor = apps[1]
        let provider = CountingProvider()
        let model = FloaterState(provider: provider)
        var readApp: NSRunningApplication?
        let controller = makeController(model: model, read: { app in
            readApp = app
            return FieldCapture(
                target: StubPasteTarget(selection: .selected), elementFound: true, isSecure: false,
                selectedText: "from editor", fieldValue: nil, selectionUnreadable: false
            )
        })
        defer { controller.hide() }

        let url = try XCTUnwrap(PromptURL.makeURL(
            for: PromptRequest(prompt: "Fix"),
            previousProcessID: blocked.processIdentifier,
            ignoredBundleIdentifiers: [try XCTUnwrap(blocked.bundleIdentifier)],
            captureInput: true,
            includesInput: false
        ))
        await controller.handle(url, fallbackApplication: blocked, recentApplications: [blocked, editor])
        await waitUntil { provider.requests.count == 1 }

        XCTAssertEqual(readApp?.processIdentifier, editor.processIdentifier)
        XCTAssertEqual(provider.requests.first?.input, "from editor")
    }

    func testNoEligibleAppDoesNotCallTheModel() async throws {
        let app = try runningApp()
        let provider = CountingProvider()
        let store = HistoryStore(fileURL: nil)
        let model = FloaterState(provider: provider, historyStore: store)
        var reads = 0
        let controller = makeController(model: model, read: { _ in
            reads += 1
            return FieldCapture(
                target: StubPasteTarget(selection: .none), elementFound: false, isSecure: false,
                selectedText: nil, fieldValue: nil, selectionUnreadable: false
            )
        })
        defer { controller.hide() }

        let url = try XCTUnwrap(PromptURL.makeURL(
            for: PromptRequest(prompt: "Fix", title: "Fix Grammar"),
            previousProcessID: app.processIdentifier,
            ignoredBundleIdentifiers: [try XCTUnwrap(app.bundleIdentifier)],
            captureInput: true,
            includesInput: false
        ))
        await controller.handle(url, fallbackApplication: app, recentApplications: [app])

        XCTAssertEqual(reads, 0)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(
            model.errorMessage,
            CaptureMessages.noApplication(ignoredAny: true, considered: [candidate(app)])
        )
    }

    func testAccessibilityDenialSkipsTheRead() async throws {
        let app = try runningApp()
        let provider = CountingProvider()
        let model = FloaterState(provider: provider)
        var reads = 0
        let controller = FloatingPanelController(
            state: model,
            accessibility: AccessibilityAccess(isTrusted: { false }, requestAccess: {}),
            readFocusedField: { _ in
                reads += 1
                return FieldCapture(
                    target: StubPasteTarget(selection: .none), elementFound: true, isSecure: false,
                    selectedText: "hidden", fieldValue: nil, selectionUnreadable: false
                )
            },
            activateForCapture: { _ in },
            replaceText: { _, _, _, _ in }
        )
        defer { controller.hide() }

        try await controller.handle(captureURL(previous: app), fallbackApplication: nil)

        XCTAssertEqual(reads, 0)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(model.errorMessage, CaptureMessages.accessibility(for: candidate(app)))
    }

    func testProvidedInputDoesNotCapture() async throws {
        let provider = CountingProvider()
        let model = FloaterState(provider: provider)
        var reads = 0
        let controller = makeController(model: model, read: { _ in
            reads += 1
            return FieldCapture(
                target: StubPasteTarget(selection: .none), elementFound: true, isSecure: false,
                selectedText: "captured", fieldValue: nil, selectionUnreadable: false
            )
        })
        defer { controller.hide() }

        let url = try XCTUnwrap(PromptURL.makeURL(
            for: PromptRequest(prompt: "Fix", input: ""),
            captureInput: true,
            includesInput: true
        ))
        await controller.handle(url, fallbackApplication: nil)
        await waitUntil { provider.requests.count == 1 }

        XCTAssertEqual(reads, 0)
        XCTAssertEqual(provider.requests.map(\.input), [""])
    }

    private func makeController(
        model: FloaterState,
        read: @escaping @MainActor (NSRunningApplication) -> FieldCapture,
        activate: @escaping @MainActor (NSRunningApplication) async -> Void = { _ in },
        replace: @escaping @MainActor (String, any TextPasteTarget, Bool, Bool) async throws -> Void = { _, _, _, _ in }
    ) -> FloatingPanelController {
        FloatingPanelController(
            state: model,
            accessibility: AccessibilityAccess(isTrusted: { true }, requestAccess: {}),
            readFocusedField: read,
            activateForCapture: activate,
            replaceText: replace
        )
    }

    private func captureURL(previous: NSRunningApplication) throws -> URL {
        try XCTUnwrap(PromptURL.makeURL(
            for: PromptRequest(prompt: "Fix", title: "Fix Grammar"),
            previousProcessID: previous.processIdentifier,
            captureInput: true,
            includesInput: false
        ))
    }

    private func runningApp() throws -> NSRunningApplication {
        try XCTUnwrap(runningApps(1).first)
    }

    private func runningApps(_ count: Int) throws -> [NSRunningApplication] {
        let own = Bundle.main.bundleIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier?.isEmpty == false && $0.bundleIdentifier != own && !$0.isTerminated
        }
        try XCTSkipIf(apps.count < count, "Need \(count) running apps")
        return Array(apps.prefix(count))
    }

    private func candidate(_ application: NSRunningApplication) -> TargetCandidate {
        TargetCandidate(
            name: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            isRunning: !application.isTerminated
        )
    }
}

@MainActor
private final class CountingProvider: AIProvider {
    var requests: [PromptRequest] = []

    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        requests.append(request)
        onUpdate("Done")
    }
}

@MainActor
private final class StubPasteTarget: TextPasteTarget {
    var selection: TextSelection

    init(selection: TextSelection) {
        self.selection = selection
    }

    func focus() async throws {}
    func checkFocus() throws {}
    func send(_ command: PasteCommand) throws {}
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<100 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Timed out")
}
