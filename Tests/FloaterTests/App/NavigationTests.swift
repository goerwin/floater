import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class NavigationTests: XCTestCase {
    func testOpenCreatesNewRequestAndPreservesDraftHistoryAndResults() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
        controller.open(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hide() }
        settle(window)

        let prompt = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "prompt" }) as? NSTextView)
        XCTAssertEqual(prompt.string, "")
        prompt.insertText("Draft prompt", replacementRange: prompt.selectedRange())
        settle(window)
        controller.hide()
        controller.open(previousApplication: nil)
        settle(window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(prompt.string, "Draft prompt")

        controller.showHistory()
        settle(window)
        controller.open(previousApplication: nil)
        XCTAssertTrue(controller.isShowingHistory)
        controller.hide()
        controller.open(previousApplication: nil)
        settle(window)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(controller.isShowingHistory)

        let entry = HistoryEntry(request: PromptRequest(prompt: "Saved prompt"), response: "Saved response")
        controller.openHistoryEntry(entry)
        settle(window)
        controller.hide()
        controller.open(previousApplication: nil)
        settle(window)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(controller.isShowingHistory)
        XCTAssertEqual(model.currentRequest, entry.request)
        XCTAssertEqual(model.response, entry.response)
    }

    func testNewRequestResetsFocusWhileRefocusingAnExistingRequestDoesNot() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
        controller.showNewRequest(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hide() }
        settle(window)
        let input = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == "input" }))
        window.makeFirstResponder(input)
        settle(window)
        window.resignKey()
        window.becomeKey()
        settle(window)
        XCTAssertTrue(window.firstResponder === input)
        controller.showNewRequest(previousApplication: nil)
        settle(window)
        XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "prompt")
    }

    func testNavigationKeepsWindowWidthAndHorizontalPosition() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
        controller.showNewRequest(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hide() }
        settle(window)
        let originalFrame = window.frame
        controller.showHistory()
        settle(window)
        XCTAssertEqual(window.frame.width, originalFrame.width)
        XCTAssertEqual(window.frame.midX, originalFrame.midX)
        controller.openHistoryEntry(HistoryEntry(request: PromptRequest(prompt: "Sample"), response: "Sample result"))
        settle(window)
        XCTAssertEqual(window.frame.width, originalFrame.width)
        XCTAssertEqual(window.frame.midX, originalFrame.midX)
        controller.dismiss()
        settle(window)
        XCTAssertEqual(window.frame.width, originalFrame.width)
        XCTAssertEqual(window.frame.midX, originalFrame.midX)
    }

    func testRefocusingWindowPreservesFocusInAllThreeViews() throws {
        for mode in ["newRequest", "results", "history"] {
            let model = FloaterState(provider: TestProvider())
            if mode == "results" {
                model.restore(HistoryEntry(request: PromptRequest(prompt: "Sample"), response: "Sample result"))
            }
            let controller = FloatingPanelController(state: model)
            if mode == "history" {
                controller.showHistory()
            } else {
                controller.show(previousApplication: nil)
            }
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            if mode == "newRequest" {
                XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "prompt")
            } else if mode == "results" {
                XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "copy")
            } else {
                XCTAssertNotNil(window.contentView?.firstDescendant(where: { $0 is NSSearchField }).flatMap { ($0 as? NSSearchField)?.currentEditor() })
            }
            let target = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == (mode == "newRequest" ? "input" : mode == "results" ? "edit" : "historyList") }))
            window.makeFirstResponder(target)
            settle(window)
            window.resignKey()
            window.becomeKey()
            settle(window)
            XCTAssertTrue(window.firstResponder === target, "\(mode) should keep its focus after switching apps")
        }
    }

    func testHistoryBrowsingAndEditingPreserveTheOriginatingDraftOrResponse() throws {
        for resultsMode in [false, true] {
            let model = FloaterState(provider: TestProvider())
            let original = HistoryEntry(request: PromptRequest(prompt: "Original prompt", input: "Original input"), response: "Original response")
            if resultsMode {
                model.restore(original)
                model.setActionError("Original action error")
                model.isPromptExpanded = true
            }
            let controller = FloatingPanelController(state: model)
            controller.show(previousApplication: nil)
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            if !resultsMode {
                for (editor, text) in zip(textViews(in: window.contentView!), ["Original draft", "Draft input"]) {
                    editor.insertText(text, replacementRange: editor.selectedRange())
                }
                settle(window)
            }
            controller.showHistory()
            controller.openHistoryEntry(HistoryEntry(request: PromptRequest(prompt: "Saved prompt", input: "Saved input"), response: "Saved result"))
            settle(window)
            sendKey("e", code: 14, modifiers: .command, to: window)
            XCTAssertEqual(textViews(in: window.contentView!).filter { !$0.isFieldEditor }.map(\.string), ["Saved prompt", "Saved input"])
            sendKey("\u{1b}", code: 53, to: window)
            XCTAssertFalse(controller.isShowingHistory)
            XCTAssertTrue(controller.isVisible)
            XCTAssertEqual(model.currentRequest?.prompt, "Saved prompt")
            XCTAssertEqual(model.response, "Saved result")
            sendKey("\u{1b}", code: 53, to: window)
            XCTAssertTrue(controller.isShowingHistory)
            sendKey("\u{1b}", code: 53, to: window)
            XCTAssertFalse(controller.isShowingHistory)
            XCTAssertTrue(controller.isVisible)
            if resultsMode {
                XCTAssertEqual(model.currentRequest, original.request)
                XCTAssertEqual(model.response, original.response)
                XCTAssertEqual(model.actionErrorMessage, "Original action error")
                XCTAssertTrue(model.isPromptExpanded)
            } else {
                XCTAssertNil(model.currentRequest)
                XCTAssertEqual(textViews(in: window.contentView!).filter { !$0.isFieldEditor }.map(\.string), ["Original draft", "Draft input"])
            }
        }
    }

    func testCancelEditingReturnsToTheOriginalResult() throws {
        for useEscape in [true, false] {
            let model = FloaterState(provider: TestProvider())
            let request = PromptRequest(prompt: "Original prompt", input: "Original input", title: "Original title")
            model.restore(request: request, response: "Original response", errorMessage: "Original error")
            model.setActionError("Original action error")
            let controller = FloatingPanelController(state: model)
            controller.show(previousApplication: nil)
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            sendKey("e", code: 14, modifiers: .command, to: window)
            let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
            prompt.selectAll(nil)
            prompt.insertText("Changed draft", replacementRange: prompt.selectedRange())
            settle(window)
            if useEscape {
                sendKey("\u{1b}", code: 53, to: window)
            } else {
                let dismiss = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Dismiss" })
                dismiss.performClick(nil)
                settle(window)
            }
            XCTAssertTrue(controller.isVisible)
            XCTAssertFalse(controller.isShowingHistory)
            XCTAssertEqual(model.currentRequest, request)
            XCTAssertEqual(model.response, "Original response")
            XCTAssertEqual(model.errorMessage, "Original error")
            XCTAssertEqual(model.actionErrorMessage, "Original action error")
            XCTAssertEqual(window.title, "Original title")
            XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "copy")
            XCTAssertFalse(model.isGenerating)
            sendKey("\u{1b}", code: 53, to: window)
            XCTAssertFalse(controller.isVisible)
        }
    }

    func testEditingReturnSurvivesOpeningAndEditingAHistoryEntry() throws {
        let model = FloaterState(provider: TestProvider())
        let original = HistoryEntry(request: PromptRequest(prompt: "Original prompt"), response: "Original result")
        let saved = HistoryEntry(request: PromptRequest(prompt: "Saved prompt"), response: "Saved result")
        model.restore(original)
        let controller = FloatingPanelController(state: model)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hide() }
        settle(window)
        sendKey("e", code: 14, modifiers: .command, to: window)
        let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
        prompt.selectAll(nil)
        prompt.insertText("Changed draft", replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("h", code: 4, modifiers: .command, to: window)
        controller.openHistoryEntry(saved)
        settle(window)
        sendKey("e", code: 14, modifiers: .command, to: window)
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertEqual(model.currentRequest, saved.request)
        XCTAssertEqual(model.response, saved.response)
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertTrue(controller.isShowingHistory)
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).first?.string, "Changed draft")
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(model.currentRequest, original.request)
        XCTAssertEqual(model.response, original.response)
    }

    func testNewAndRunDiscardThePreviousEditingResult() throws {
        for runEdit in [false, true] {
            let model = FloaterState(provider: TestProvider())
            model.restore(HistoryEntry(request: PromptRequest(prompt: "Original prompt"), response: "Original result"))
            let controller = FloatingPanelController(state: model)
            controller.show(previousApplication: nil)
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            sendKey("e", code: 14, modifiers: .command, to: window)
            let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
            prompt.selectAll(nil)
            prompt.insertText("Changed prompt", replacementRange: prompt.selectedRange())
            settle(window)
            sendKey(runEdit ? "r" : "n", code: runEdit ? 15 : 45, modifiers: .command, to: window)
            if runEdit {
                XCTAssertEqual(model.currentRequest?.prompt, "Changed prompt")
                XCTAssertEqual(model.response, "Test response")
            } else {
                XCTAssertNil(model.currentRequest)
                XCTAssertEqual(textViews(in: window.contentView!).first?.string, "")
            }
            sendKey("\u{1b}", code: 53, to: window)
            XCTAssertFalse(controller.isVisible)
        }
    }

    func testNewKeepsTheSameFontAndSizeAcrossAllThreeViews() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
        controller.showNewRequest(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hide() }
        settle(window)
        let original = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "New" })
        let font = original.font
        let size = original.frame.size
        controller.showHistory()
        settle(window)
        let historyNew = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "New" })
        XCTAssertEqual(historyNew.font, font)
        XCTAssertEqual(historyNew.frame.size, size)
        controller.openHistoryEntry(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Sample result"))
        settle(window)
        let responseNew = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "New" })
        XCTAssertEqual(responseNew.font, font)
        XCTAssertEqual(responseNew.frame.size, size)
    }

    func testHeaderButtonsKeepTheirSizeWhenGenerationStartsWithALongTitle() throws {
        let model = FloaterState(provider: TestProvider())
        let window = makeWindow(state: model)
        defer { window.close() }
        let initial = buttons(in: window.contentView!).filter { ["New", "History"].contains($0.accessibilityLabel() ?? "") }
        let sizes = Dictionary(uniqueKeysWithValues: initial.map { ($0.accessibilityLabel() ?? "", $0.frame.size) })
        model.start(PromptRequest(prompt: "Prompt", title: String(repeating: "Long title ", count: 30)))
        settle(window)
        for button in buttons(in: window.contentView!).filter({ ["New", "History"].contains($0.accessibilityLabel() ?? "") }) {
            let size = try XCTUnwrap(sizes[button.accessibilityLabel() ?? ""])
            XCTAssertEqual(button.frame.width, size.width, accuracy: 1)
            XCTAssertEqual(button.frame.height, size.height, accuracy: 1)
        }
    }

    func testHistoryEnterAndSpaceReturnToNewRequestAndResultsWithEscape() throws {
        for resultsMode in [false, true] {
            let model = FloaterState(provider: TestProvider())
            let entry = HistoryEntry(request: PromptRequest(prompt: "Original prompt", input: "Original input"), response: "Original response")
            if resultsMode { model.restore(entry) }
            let controller = FloatingPanelController(state: model)
            controller.show(previousApplication: nil)
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            if !resultsMode {
                let editors = textViews(in: window.contentView!)
                for (editor, text) in zip(editors, ["Draft prompt", "Draft input"]) {
                    editor.insertText(text, replacementRange: editor.selectedRange())
                }
                settle(window)
            }
            for (characters, code) in [("\r", UInt16(36)), (" ", UInt16(49))] {
                let button = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "History" })
                window.makeFirstResponder(button)
                settle(window)
                let event = keyEvent(characters, code: code, window: window)
                if !window.performKeyEquivalent(with: event) { window.sendEvent(event) }
                settle(window)
                XCTAssertTrue(controller.isShowingHistory)
                XCTAssertTrue(controller.isVisible)
                XCTAssertTrue(window === controller.window)
                XCTAssertEqual(window.level, .floating)
                XCTAssertFalse((window as? NSPanel)?.hidesOnDeactivate ?? true)
                sendKey("\u{1b}", code: 53, to: window)
                XCTAssertFalse(controller.isShowingHistory)
                XCTAssertTrue(controller.isVisible)
                if resultsMode {
                    XCTAssertEqual(model.currentRequest, entry.request)
                    XCTAssertEqual(model.response, entry.response)
                    XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "Copy")
                } else {
                    XCTAssertNil(model.currentRequest)
                    XCTAssertEqual(textViews(in: window.contentView!).filter { !$0.isFieldEditor }.map(\.string), ["Draft prompt", "Draft input"])
                }
            }
        }
    }

    func testHistoryShortcutWorksInNewRequestAndResults() throws {
        let model = FloaterState(provider: TestProvider())
        var historyOpenings = 0
        let window = makeWindow(state: model, onHistory: { historyOpenings += 1 })
        defer { window.close() }
        sendKey("h", code: 4, modifiers: .command, to: window)
        XCTAssertEqual(historyOpenings, 1)
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        settle(window)
        sendKey("h", code: 4, modifiers: .command, to: window)
        XCTAssertEqual(historyOpenings, 2)
    }

    func testShortcutsAreScopedToThePanelWindow() throws {
        var firstOpenings = 0
        var secondOpenings = 0
        let first = makeNewRequest(onHistory: { firstOpenings += 1 })
        defer { first.close() }
        let second = makeNewRequest(onHistory: { secondOpenings += 1 })
        sendKey("h", code: 4, modifiers: .command, to: second)
        XCTAssertEqual(firstOpenings, 0)
        XCTAssertEqual(secondOpenings, 1)
        second.close()
        first.makeKey()
        settle(first)
        sendKey("h", code: 4, modifiers: .command, to: first)
        XCTAssertEqual(firstOpenings, 1)
        XCTAssertEqual(secondOpenings, 1)
    }

    func testEditingLongRequestLiftsPanelHeightLimitAndRestoresItOnRun() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
        let request = PromptRequest(
            prompt: String(repeating: "Instruction\n", count: 18),
            input: String(repeating: "Input text\n", count: 18), title: "Long request"
        )
        model.start(request)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.dismiss() }
        settle(window)
        XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumHeight)

        sendKey("\t", code: 48, modifiers: .option, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertNil(model.currentRequest)
        let editors = textViews(in: window.contentView!)
        XCTAssertEqual(editors.map(\.string), [request.prompt, request.input])
        XCTAssertGreaterThan(window.frame.height, FloaterPanelLayout.maximumHeight)
        XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumEditingHeight)

        sendKey("\r", code: 36, modifiers: .command, to: window)
        XCTAssertEqual(model.currentRequest?.title, request.title)
        XCTAssertEqual(model.currentRequest?.input, request.input)
        XCTAssertLessThanOrEqual(window.frame.height, FloaterPanelLayout.maximumHeight)
    }
}
