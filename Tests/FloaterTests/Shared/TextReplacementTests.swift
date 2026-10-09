import AppKit
import FloaterCore
import XCTest
@testable import Floater

@MainActor
final class TextReplacementTests: XCTestCase {
    func testReplaceHidesPanelPreventsDuplicateWritesAndRestoresResultAfterFailure() async throws {
        let model = FloaterState(provider: TestProvider())
        let request = PromptRequest(prompt: "Test prompt")
        model.restore(request: request, response: "Replacement")
        var calls = 0
        var pending: CheckedContinuation<Void, any Error>?
        let target = NativePasteTarget(makeEditor("Original"), pasteboard: testPasteboard())
        var captures = 0
        let controller = FloatingPanelController(
            state: model,
            accessibility: AccessibilityAccess(isTrusted: { true }, requestAccess: {}),
            captureTarget: { _ in
                captures += 1
                return target
            },
            replaceText: { text, capturedTarget, _, _ in
                calls += 1
                XCTAssertEqual(text, "Replacement")
                XCTAssertTrue(capturedTarget as? NativePasteTarget === target)
                try await withCheckedThrowingContinuation { pending = $0 }
            }
        )
        controller.show(previousApplication: .current)
        defer { controller.hide() }
        XCTAssertEqual(captures, 1)
        XCTAssertFalse(try XCTUnwrap(controller.window).canBecomeMain)
        XCTAssertFalse(try XCTUnwrap(controller.window).styleMask.contains(.nonactivatingPanel))
        controller.replaceAndDismiss()
        XCTAssertFalse(controller.isVisible)
        controller.replaceAndDismiss()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(calls, 1)
        try XCTUnwrap(pending).resume(throwing: TextReplacementError.unsupported)
        pending = nil
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(model.currentRequest, request)
        XCTAssertEqual(model.response, "Replacement")
        XCTAssertEqual(model.actionErrorMessage, TextReplacementError.unsupported.localizedDescription)

        controller.replaceAndDismiss()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(calls, 2)
        try XCTUnwrap(pending).resume()
        pending = nil
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(model.actionErrorMessage)
        XCTAssertEqual(captures, 1)
    }

    func testPasteUpdatesOnlySelectionKeepsClipboardAndSupportsUndo() async throws {
        let editor = makeEditor("Before 👋🏽 selected after")
        let window = NSWindow(contentRect: editor.frame, styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        defer { window.close() }
        editor.setSelectedRange((editor.string as NSString).range(of: "👋🏽 selected"))
        let pasteboard = testPasteboard()
        pasteboard.setString("Previous clipboard", forType: .string)
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        try await TextReplacement.apply("result", to: target, allowWholeField: false, pasteboard: pasteboard)
        XCTAssertEqual(editor.string, "Before result after")
        XCTAssertEqual(target.commands, [.paste])
        XCTAssertEqual(pasteboard.string(forType: .string), "result")
        try XCTUnwrap(editor.undoManager).undo()
        XCTAssertEqual(editor.string, "Before 👋🏽 selected after")
    }

    func testPasteWithoutSelectionOverwritesWholeFieldWhenEnabled() async throws {
        let editor = makeEditor("Original\nfield contents")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        try await TextReplacement.apply("New\nresponse", to: target, allowWholeField: true, pasteboard: pasteboard)
        XCTAssertEqual(editor.string, "New\nresponse")
        XCTAssertEqual(target.commands, [.selectAll, .paste])
        XCTAssertEqual(pasteboard.string(forType: .string), "New\nresponse")
    }

    func testPasteIntoEmptyField() async throws {
        let editor = makeEditor("")
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        try await TextReplacement.apply("result", to: target, allowWholeField: true, pasteboard: pasteboard)
        XCTAssertEqual(editor.string, "result")
    }

    func testNoSelectionLeavesFieldUntouchedWhenWholeFieldIsDisabled() async throws {
        let editor = makeEditor("Original contents")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        do {
            try await TextReplacement.apply("result", to: target, allowWholeField: false, pasteboard: pasteboard)
            XCTFail("Expected selectionRequired")
        } catch {
            XCTAssertEqual(error as? TextReplacementError, .selectionRequired)
        }
        XCTAssertEqual(editor.string, "Original contents")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertTrue(target.commands.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "result")
    }

    func testUnreadableSelectionCopiesResultWithoutSendingSelectAllOrPaste() async throws {
        let editor = makeEditor("Original contents")
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        target.selectionOverride = .unavailable
        do {
            try await TextReplacement.apply("result", to: target, allowWholeField: true, pasteboard: pasteboard)
            XCTFail("Expected invalidSelection")
        } catch {
            XCTAssertEqual(error as? TextReplacementError, .invalidSelection)
        }
        XCTAssertEqual(editor.string, "Original contents")
        XCTAssertTrue(target.commands.isEmpty)
        XCTAssertEqual(pasteboard.string(forType: .string), "result")
    }

    func testReadOnlyFieldIsNotChanged() async throws {
        let editor = makeEditor("Read only")
        editor.isEditable = false
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        do {
            try await TextReplacement.apply("result", to: target, allowWholeField: true, pasteboard: pasteboard)
            XCTFail("Expected notEditable")
        } catch {
            XCTAssertEqual(error as? TextReplacementError, .notEditable)
        }
        XCTAssertEqual(editor.string, "Read only")
        XCTAssertTrue(target.commands.isEmpty)
    }

    func testFocusChangeAfterSelectAllPreventsPaste() async throws {
        let editor = makeEditor("Original contents")
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        target.loseFocusAfterSelectAll = true
        do {
            try await TextReplacement.apply("result", to: target, allowWholeField: true, pasteboard: pasteboard)
            XCTFail("Expected noFocusedField")
        } catch {
            XCTAssertEqual(error as? TextReplacementError, .noFocusedField)
        }
        XCTAssertEqual(editor.string, "Original contents")
        XCTAssertEqual(target.commands, [.selectAll])
        XCTAssertEqual(pasteboard.string(forType: .string), "result")
    }

    func testSelectionOnlyPasteDoesNotSelectAllWhenTheSelectionIsGone() async throws {
        let editor = makeEditor("Whole field")
        let pasteboard = testPasteboard()
        let target = NativePasteTarget(editor, pasteboard: pasteboard)
        target.selectionOverride = TextSelection.none
        do {
            try await TextReplacement.apply(
                "result", to: target, allowWholeField: true, selectionOnly: true, pasteboard: pasteboard
            )
            XCTFail("Expected selectionRequired")
        } catch {
            XCTAssertEqual(error as? TextReplacementError, .selectionRequired)
        }
        XCTAssertTrue(target.commands.isEmpty)
        XCTAssertEqual(editor.string, "Whole field")
        XCTAssertEqual(pasteboard.string(forType: .string), "result")
    }

    func testSelectionMetadataDoesNotDependOnFullDocumentValue() {
        XCTAssertEqual(TextSelection.read(range: NSRange(location: 1000, length: 10), selectedText: nil), .selected)
        XCTAssertEqual(TextSelection.read(range: NSRange(location: 1000, length: 0), selectedText: nil), .none)
        XCTAssertEqual(TextSelection.read(range: nil, selectedText: "selected"), .selected)
        XCTAssertEqual(TextSelection.read(range: NSRange(location: 0, length: 0), selectedText: "selected"), .selected)
        XCTAssertEqual(TextSelection.read(range: nil, selectedText: ""), .unavailable)
        XCTAssertEqual(TextSelection.read(range: nil, selectedText: nil), .unavailable)
        XCTAssertEqual(TextSelection.read(range: NSRange(location: NSNotFound, length: 0), selectedText: nil), .unavailable)
    }

    func testConfigurationPersistsAcrossInstances() throws {
        let suite = "FloaterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.replaceWholeFieldWhenUnselected)
        settings.replaceWholeFieldWhenUnselected = false
        XCTAssertFalse(AppSettings(defaults: defaults).replaceWholeFieldWhenUnselected)
        settings.replaceWholeFieldWhenUnselected = true
        XCTAssertTrue(AppSettings(defaults: defaults).replaceWholeFieldWhenUnselected)
    }

    private func testPasteboard() -> NSPasteboard {
        NSPasteboard.withUniqueName()
    }

    private func makeEditor(_ text: String) -> NSTextView {
        _ = NSApplication.shared
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = text
        return editor
    }
}

@MainActor
private final class NativePasteTarget: TextPasteTarget {
    let editor: NSTextView
    let pasteboard: NSPasteboard
    var commands: [PasteCommand] = []
    var selectionOverride: TextSelection?
    var loseFocusAfterSelectAll = false
    private var isFocused = false

    init(_ editor: NSTextView, pasteboard: NSPasteboard) {
        self.editor = editor
        self.pasteboard = pasteboard
    }

    var selection: TextSelection {
        guard isFocused else { return .unavailable }
        return selectionOverride ?? TextSelection.read(range: editor.selectedRange(), selectedText: nil)
    }

    func focus() async throws {
        guard editor.isEditable else { throw TextReplacementError.notEditable }
        isFocused = true
    }

    func checkFocus() throws {
        guard isFocused else { throw TextReplacementError.noFocusedField }
    }

    func send(_ command: PasteCommand) throws {
        try checkFocus()
        commands.append(command)
        switch command {
        case .selectAll:
            editor.selectAll(nil)
            if loseFocusAfterSelectAll { isFocused = false }
        case .paste:
            XCTAssertTrue(editor.readSelection(from: pasteboard, type: .string))
        }
    }
}
