import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class ComposerTests: XCTestCase {
    func testInputTabMovesFocusWithoutInsertingText() throws {
        let window = makeComposer()
        defer { window.close() }
        let input = try XCTUnwrap(textViews(in: window.contentView!).last)
        window.makeFirstResponder(input)
        settle(window)
        input.keyDown(with: keyEvent("\t", code: 48, window: window))
        settle(window)

        XCTAssertEqual(input.string, "")
        XCTAssertFalse(window.firstResponder === input)
    }

    func testTabAndShiftTabMoveBetweenEditorsAndActions() throws {
        var dismissals = 0
        var requests: [PromptRequest] = []
        let window = makeComposer(onSubmit: { requests.append($0) }, onDismiss: { dismissals += 1 })
        defer { window.close() }
        let editors = textViews(in: window.contentView!)
        XCTAssertEqual(editors.count, 2)
        let prompt = try XCTUnwrap(editors.first)
        let input = try XCTUnwrap(editors.last)

        window.makeFirstResponder(prompt)
        prompt.insertText("Summarize", replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("\t", code: 48, to: window)
        XCTAssertTrue(window.firstResponder === input)
        sendKey("\t", code: 48, modifiers: .shift, to: window)
        XCTAssertTrue(window.firstResponder === prompt)
        sendKey("\t", code: 48, to: window)
        sendKey("\t", code: 48, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(dismissals, 1)
        sendKey("\t", code: 48, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: "Summarize")])
    }

    func testShiftEnterInBothEditorsPreservesNewlinesWhenSubmitted() throws {
        var requests: [PromptRequest] = []
        let window = makeComposer(onSubmit: { requests.append($0) })
        defer { window.close() }
        let editors = textViews(in: window.contentView!)
        for editor in editors {
            window.makeFirstResponder(editor)
            editor.insertText("First", replacementRange: editor.selectedRange())
            settle(window)
            sendKey("\r", code: 36, modifiers: .shift, to: window)
            editor.insertText("Second", replacementRange: editor.selectedRange())
            settle(window)
            XCTAssertEqual(editor.string, "First\nSecond")
        }
        XCTAssertTrue(requests.isEmpty)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: "First\nSecond", input: "First\nSecond")])
    }

    func testEditorsShareTypographyAndGrowWithLongText() throws {
        let window = makeComposer()
        defer { window.close() }
        let editors = textViews(in: window.contentView!)
        XCTAssertEqual(editors.count, 2)
        let prompt = try XCTUnwrap(editors.first)
        let input = try XCTUnwrap(editors.last)
        XCTAssertEqual(prompt.font, input.font)
        XCTAssertEqual(prompt.textContainerInset, input.textContainerInset)
        XCTAssertEqual(prompt.textContainer?.lineFragmentPadding, input.textContainer?.lineFragmentPadding)

        let initialHeight = window.contentView!.fittingSize.height
        for editor in editors {
            editor.insertText(String(repeating: "A line of text\n", count: 18), replacementRange: editor.selectedRange())
        }
        settle(window)
        XCTAssertGreaterThan(window.contentView!.fittingSize.height, initialHeight)
        XCTAssertGreaterThan(window.contentView!.fittingSize.height, FloaterPanelLayout.maximumHeight)
        XCTAssertEqual(prompt.frame.height, input.frame.height, accuracy: 1)
    }

    func testEditingLongRequestLiftsPanelHeightLimitAndRestoresItOnRun() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let controller = FloatingPanelController(viewModel: model)
        let request = PromptRequest(
            prompt: String(repeating: "Instruction\n", count: 18),
            input: String(repeating: "Input text\n", count: 18), title: "Long request"
        )
        model.start(request)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(NSApp.windows.first { $0.contentView is NSHostingView<FloaterPanelView> })
        defer { controller.dismiss() }
        settle(window)
        XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumHeight)

        sendKey("\t", code: 48, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertNil(model.currentRequest)
        let editors = textViews(in: window.contentView!)
        XCTAssertEqual(editors.map(\.string), [request.prompt, request.input])
        XCTAssertGreaterThan(window.frame.height, FloaterPanelLayout.maximumHeight)
        XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumEditingHeight)

        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(model.currentRequest?.title, request.title)
        XCTAssertEqual(model.currentRequest?.input, request.input)
        XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumHeight)
    }

    private func makeComposer(
        onSubmit: @escaping (PromptRequest) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {}
    ) -> NSWindow {
        _ = NSApplication.shared
        let model = FloaterViewModel(provider: TestProvider())
        let view = FloaterPanelView(
            viewModel: model,
            onSubmit: onSubmit,
            onCopy: {},
            onReplace: {},
            onDismiss: onDismiss,
            onContentChange: {}
        )
        let hostingView = NSHostingView(rootView: view)
        let window = TestWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        window.makeKey()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        return window
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<3 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func sendKey(
        _ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], to window: NSWindow
    ) {
        window.sendEvent(keyEvent(characters, code: code, modifiers: modifiers, window: window))
        settle(window)
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }

    private func keyEvent(
        _ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], window: NSWindow
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        )!
    }
}

@MainActor
private final class TestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
private struct TestProvider: AIProvider {
    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        onUpdate("Test response")
    }
}
