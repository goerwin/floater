import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class NewRequestViewTests: XCTestCase {
    func testButtonLabelsShowShortcutsAndCommandRSubmitsFromAnEditor() throws {
        var requests: [PromptRequest] = []
        let window = makeNewRequest(onSubmit: { requests.append($0) })
        defer { window.close() }
        let controls = buttons(in: window.contentView!)
        XCTAssertTrue(controls.contains { $0.title == "New ⌘N" })
        XCTAssertTrue(controls.contains { $0.title == "History ⌘H" })
        XCTAssertTrue(controls.contains { $0.title == "Run ⌘R" })
        XCTAssertFalse(try XCTUnwrap(controls.first { $0.title == "Run ⌘R" }).isEnabled)
        let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
        let text = "  Summarize this:\n<source>\nhello\n</source>\n"
        prompt.insertText(text, replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("r", code: 15, modifiers: .command, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: text)])
    }

    func testNewClearsDraftAndResults() throws {
        let model = FloaterState(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt\n\nInput", title: "Title"), response: "Result"))
        let window = makeWindow(state: model)
        defer { window.close() }
        let new = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "New" })
        window.makeFirstResponder(new)
        sendKey("\r", code: 36, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).map(\.string), [""])
        let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
        prompt.insertText("Draft", replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("n", code: 45, modifiers: .command, to: window)
        XCTAssertEqual(prompt.string, "")
        XCTAssertTrue(window.firstResponder === prompt)
    }

    func testTabAndShiftTabNavigateWithoutChangingPrompt() throws {
        let window = makeNewRequest()
        defer { window.close() }
        for editor in textViews(in: window.contentView!) {
            window.makeFirstResponder(editor)
            settle(window)
            sendKey("\t", code: 48, to: window)
            XCTAssertFalse(window.firstResponder === editor)
            sendKey("\u{19}", code: 48, modifiers: .shift, to: window)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(editor.string, "")
        }
    }

    func testTabAndShiftTabMoveBetweenPromptAndActionsOnce() throws {
        var dismissals = 0
        var requests: [PromptRequest] = []
        let window = makeNewRequest(onSubmit: { requests.append($0) }, onDismiss: { dismissals += 1 })
        defer { window.close() }
        let editors = textViews(in: window.contentView!)
        XCTAssertEqual(editors.count, 1)
        let prompt = try XCTUnwrap(editors.first)

        window.makeFirstResponder(prompt)
        prompt.insertText("Summarize", replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("\t", code: 48, to: window)
        XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "dismiss")
        sendKey("\u{19}", code: 48, modifiers: .shift, to: window)
        XCTAssertTrue(window.firstResponder === prompt)
        sendKey("\t", code: 48, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(dismissals, 1)
        sendKey("\t", code: 48, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: "Summarize")])
        sendKey("\u{19}", code: 48, modifiers: .shift, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(dismissals, 2)
        XCTAssertEqual(requests.count, 1)
    }

    func testNativeWordMovementAndSelectionStayInsideEditors() throws {
        let window = makeNewRequest()
        defer { window.close() }
        for editor in textViews(in: window.contentView!) {
            window.makeFirstResponder(editor)
            editor.insertText("First second", replacementRange: editor.selectedRange())
            settle(window)
            sendKey("\u{f702}", code: 123, modifiers: .option, to: window)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 6, length: 0))
            sendKey("\u{f702}", code: 123, modifiers: [.option, .shift], to: window)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 6))
            XCTAssertEqual(editor.string, "First second")
            XCTAssertTrue(window.firstResponder === editor)
        }
    }

    func testEnterSubmitsThePromptAndShiftEnterAddsANewline() throws {
        for (characters, code) in [("\r", UInt16(36)), ("\u{3}", UInt16(76))] {
            var requests: [PromptRequest] = []
            let window = makeNewRequest(onSubmit: { requests.append($0) })
            defer { window.close() }
            let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
            sendKey(characters, code: code, to: window)
            XCTAssertTrue(requests.isEmpty)
            XCTAssertEqual(editor.string, "")

            editor.insertText("First", replacementRange: editor.selectedRange())
            settle(window)
            sendKey("\r", code: 36, modifiers: .shift, to: window)
            XCTAssertTrue(requests.isEmpty)
            editor.insertText("Second", replacementRange: editor.selectedRange())
            settle(window)
            sendKey(characters, code: code, to: window)
            XCTAssertEqual(requests, [PromptRequest(prompt: "First\nSecond")])
            XCTAssertEqual(editor.string, "First\nSecond")
        }
    }

    func testPromptEditorGrowsWithLongText() throws {
        let window = makeNewRequest()
        defer { window.close() }
        let editors = textViews(in: window.contentView!)
        XCTAssertEqual(editors.count, 1)
        let prompt = try XCTUnwrap(editors.first)

        let initialHeight = window.contentView!.fittingSize.height
        for editor in editors {
            editor.insertText(String(repeating: "A line of text\n", count: 36), replacementRange: editor.selectedRange())
        }
        settle(window)
        XCTAssertGreaterThan(window.contentView!.fittingSize.height, initialHeight)
        XCTAssertLessThanOrEqual(window.contentView!.fittingSize.height, FloaterPanelLayout.maximumEditingHeight)
        XCTAssertGreaterThan(prompt.frame.height, 100)
    }
}
