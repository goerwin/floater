import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class ComposerTests: XCTestCase {
    func testOpeningMenuRefreshesAccessibilityStatusWithoutWindowActivation() {
        _ = NSApplication.shared
        var granted = false
        let access = AccessibilityAccess(isTrusted: { granted }, requestAccess: {})
        XCTAssertFalse(access.isGranted)
        granted = true
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        XCTAssertTrue(access.isGranted)
        granted = false
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: NSMenu())
        XCTAssertFalse(access.isGranted)
    }

    func testNewRequestResetsFocusWhileRefocusingAnExistingRequestDoesNot() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let controller = FloatingPanelController(viewModel: model)
        controller.showComposer(previousApplication: nil)
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
        controller.showComposer(previousApplication: nil)
        settle(window)
        XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "prompt")
    }

    func testNavigationKeepsWindowWidthAndHorizontalPosition() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let controller = FloatingPanelController(viewModel: model)
        controller.showComposer(previousApplication: nil)
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
        for mode in ["composer", "response", "history"] {
            let model = FloaterViewModel(provider: TestProvider())
            if mode == "response" {
                model.restore(HistoryEntry(request: PromptRequest(prompt: "Sample"), response: "Sample result"))
            }
            let controller = FloatingPanelController(viewModel: model)
            if mode == "history" {
                controller.showHistory()
            } else {
                controller.show(previousApplication: nil)
            }
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            if mode == "composer" {
                XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "prompt")
            } else if mode == "response" {
                XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "copy")
            } else {
                XCTAssertNotNil(window.contentView?.firstDescendant(where: { $0 is NSSearchField }).flatMap { ($0 as? NSSearchField)?.currentEditor() })
            }
            let target = try XCTUnwrap(window.contentView?.firstDescendant(where: { $0.identifier?.rawValue == (mode == "composer" ? "input" : mode == "response" ? "edit" : "historyList") }))
            window.makeFirstResponder(target)
            settle(window)
            window.resignKey()
            window.becomeKey()
            settle(window)
            XCTAssertTrue(window.firstResponder === target, "\(mode) should keep its focus after switching apps")
        }
    }

    func testHistoryBrowsingAndEditingPreserveTheOriginatingDraftOrResponse() throws {
        for responseMode in [false, true] {
            let model = FloaterViewModel(provider: TestProvider())
            let original = HistoryEntry(request: PromptRequest(prompt: "Original prompt", input: "Original input"), response: "Original response")
            if responseMode { model.restore(original) }
            let controller = FloatingPanelController(viewModel: model)
            controller.show(previousApplication: nil)
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            if !responseMode {
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
            XCTAssertTrue(controller.isShowingHistory)
            sendKey("\u{1b}", code: 53, to: window)
            XCTAssertFalse(controller.isShowingHistory)
            XCTAssertTrue(controller.isVisible)
            if responseMode {
                XCTAssertEqual(model.currentRequest, original.request)
                XCTAssertEqual(model.response, original.response)
            } else {
                XCTAssertNil(model.currentRequest)
                XCTAssertEqual(textViews(in: window.contentView!).filter { !$0.isFieldEditor }.map(\.string), ["Original draft", "Draft input"])
            }
        }
    }

    func testNewKeepsTheSameFontAndSizeAcrossAllThreeViews() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let controller = FloatingPanelController(viewModel: model)
        controller.showComposer(previousApplication: nil)
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

    func testReplaceIsDisabledUntilAccessibilityIsGrantedAndCanRequestAccess() throws {
        var granted = false
        var requests = 0
        var replacements = 0
        let access = AccessibilityAccess(isTrusted: { granted }, requestAccess: { requests += 1 })
        let model = FloaterViewModel(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        let window = makePanel(model: model, onReplace: { replacements += 1 }, accessibility: access)
        defer { window.close() }
        let replace = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Replace" })
        XCTAssertFalse(replace.isEnabled)
        XCTAssertNil(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Enable Accessibility" })
        access.request()
        XCTAssertEqual(requests, 1)
        sendKey("r", code: 15, modifiers: [.command, .shift], to: window)
        XCTAssertEqual(replacements, 0)
        granted = true
        access.refresh()
        settle(window)
        XCTAssertTrue(replace.isEnabled)
        XCTAssertNil(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Enable Accessibility" })
        sendKey("r", code: 15, modifiers: [.command, .shift], to: window)
        XCTAssertEqual(replacements, 1)
        granted = false
        access.refresh()
        settle(window)
        XCTAssertFalse(replace.isEnabled)
    }

    func testButtonLabelsShowShortcutsAndCommandRSubmitsFromAnEditor() throws {
        var requests: [PromptRequest] = []
        let window = makeComposer(onSubmit: { requests.append($0) })
        defer { window.close() }
        let controls = buttons(in: window.contentView!)
        XCTAssertTrue(controls.contains { $0.title == "New ⌘N" })
        XCTAssertTrue(controls.contains { $0.title == "History ⌘H" })
        XCTAssertTrue(controls.contains { $0.title == "Run ⌘R" })
        XCTAssertFalse(try XCTUnwrap(controls.first { $0.title == "Run ⌘R" }).isEnabled)
        let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
        prompt.insertText("Summarize", replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("r", code: 15, modifiers: .command, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: "Summarize")])
    }

    func testHeaderButtonsKeepTheirSizeWhenGenerationStartsWithALongTitle() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let window = makePanel(model: model)
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

    func testRapidTabPressesMoveNativeFocusImmediately() throws {
        let model = FloaterViewModel(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        let window = makePanel(model: model)
        defer { window.close() }
        for expected in ["Edit", "Replace", "Dismiss", "History", "New", "Copy"] {
            window.sendEvent(keyEvent("\t", code: 48, window: window))
            XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), expected)
        }
        for expected in ["New", "History", "Dismiss", "Replace", "Edit", "Copy"] {
            window.sendEvent(keyEvent("\t", code: 48, modifiers: [.option, .shift], window: window))
            XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), expected)
        }
        settle(window)
        XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "Copy")
    }

    func testHistoryEnterAndSpaceReturnToComposerAndResponseWithEscape() throws {
        for responseMode in [false, true] {
            let model = FloaterViewModel(provider: TestProvider())
            let entry = HistoryEntry(request: PromptRequest(prompt: "Original prompt", input: "Original input"), response: "Original response")
            if responseMode { model.restore(entry) }
            let controller = FloatingPanelController(viewModel: model)
            controller.show(previousApplication: nil)
            let window = try XCTUnwrap(controller.window)
            defer { controller.hide() }
            settle(window)
            if !responseMode {
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
                if responseMode {
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

    func testNewClearsTheComposerAndResponse() throws {
        let model = FloaterViewModel(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt", input: "Input", title: "Title"), response: "Result"))
        let window = makePanel(model: model)
        defer { window.close() }
        sendKey("\t", code: 48, modifiers: .shift, to: window)
        XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "New")
        sendKey("\r", code: 36, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).map(\.string), ["", ""])
        let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
        prompt.insertText("Draft", replacementRange: prompt.selectedRange())
        settle(window)
        sendKey("n", code: 45, modifiers: .command, to: window)
        XCTAssertEqual(prompt.string, "")
        XCTAssertTrue(window.firstResponder === prompt)
    }

    func testPlainAndOptionTabUseSameFocusOrderInBothDirections() throws {
        for option: NSEvent.ModifierFlags in [[], .option] {
            let model = FloaterViewModel(provider: TestProvider())
            model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
            model.setCanReplace(true)
            let window = makePanel(model: model)
            defer { window.close() }
            let order = ["Copy", "Edit", "Replace", "Dismiss", "History", "New"]
            for title in order.dropFirst() + ["Copy"] {
                sendKey("\t", code: 48, modifiers: option, to: window)
                XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), title)
            }
            for title in order.dropFirst().reversed() + ["Copy"] {
                sendKey("\t", code: 48, modifiers: option.union(.shift), to: window)
                XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), title)
            }
        }
    }

    func testPlainTabMovesBetweenResponseActionsAndSpaceOpensHistory() throws {
        let model = FloaterViewModel(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        var copies = 0
        var replacements = 0
        var dismissals = 0
        var historyOpenings = 0
        let window = makePanel(
            model: model, onCopy: { copies += 1 }, onReplace: { replacements += 1 },
            onDismiss: { dismissals += 1 }, onHistory: { historyOpenings += 1 }
        )
        defer { window.close() }
        sendKey(" ", code: 49, to: window)
        XCTAssertEqual(copies, 1)
        sendKey("\t", code: 48, to: window)
        sendKey("\t", code: 48, to: window)
        sendKey(" ", code: 49, to: window)
        XCTAssertEqual(replacements, 1)
        sendKey("\t", code: 48, to: window)
        sendKey(" ", code: 49, to: window)
        XCTAssertEqual(dismissals, 1)
        sendKey("\t", code: 48, to: window)
        sendKey(" ", code: 49, to: window)
        XCTAssertEqual(historyOpenings, 1)
    }
    func testTabAndShiftTabStayInsideEditors() throws {
        let window = makeComposer()
        defer { window.close() }
        for editor in textViews(in: window.contentView!) {
            window.makeFirstResponder(editor)
            settle(window)
            sendKey("\t", code: 48, to: window)
            XCTAssertTrue(window.firstResponder === editor)
            sendKey("\t", code: 48, modifiers: .shift, to: window)
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(editor.string, "\t\t")
        }
    }

    func testOptionTabAndOptionShiftTabMoveBetweenEditorsAndActionsOnce() throws {
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
        sendKey("\t", code: 48, modifiers: .option, to: window)
        XCTAssertTrue(window.firstResponder === input)
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        XCTAssertTrue(window.firstResponder === prompt)
        sendKey("\t", code: 48, modifiers: .option, to: window)
        sendKey("\t", code: 48, modifiers: .option, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(dismissals, 1)
        sendKey("\t", code: 48, modifiers: .option, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: "Summarize")])
    }

    func testOptionShiftTabMovesFromRunToDismissWithOnePress() throws {
        var dismissals = 0
        var requests: [PromptRequest] = []
        let window = makeComposer(onSubmit: { requests.append($0) }, onDismiss: { dismissals += 1 })
        defer { window.close() }
        let prompt = try XCTUnwrap(textViews(in: window.contentView!).first)
        window.makeFirstResponder(prompt)
        prompt.insertText("Summarize", replacementRange: prompt.selectedRange())
        settle(window)
        for _ in 0..<3 { sendKey("\t", code: 48, modifiers: .option, to: window) }
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(dismissals, 1)
        XCTAssertTrue(requests.isEmpty)
    }

    func testOptionShiftTabMovesBetweenResponseActionsWithOnePress() throws {
        let model = FloaterViewModel(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        var copies = 0
        var replacements = 0
        var dismissals = 0
        var historyOpenings = 0
        let window = makePanel(
            model: model, onCopy: { copies += 1 }, onReplace: { replacements += 1 },
            onDismiss: { dismissals += 1 }, onHistory: { historyOpenings += 1 }
        )
        defer { window.close() }
        sendKey("\t", code: 48, modifiers: .option, to: window)
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(copies, 1)
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "New")
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(historyOpenings, 1)
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(dismissals, 1)
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(replacements, 1)
        sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertNil(model.currentRequest)
    }

    func testResponseCopyAndEditShortcuts() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let request = PromptRequest(prompt: "Translate", input: "Hola\nMundo", title: "Translation")
        model.restore(HistoryEntry(request: request, response: "Hello\nWorld"))
        var copies = 0
        let window = makePanel(model: model, onCopy: { copies += 1 })
        defer { window.close() }
        sendKey("c", code: 8, modifiers: .command, to: window)
        XCTAssertEqual(copies, 1)
        sendKey("e", code: 14, modifiers: .command, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).map(\.string), [request.prompt, request.input])
        sendKey("e", code: 14, modifiers: .command, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(copies, 1)
    }

    func testHistoryShortcutWorksInComposerAndResponse() throws {
        let model = FloaterViewModel(provider: TestProvider())
        var historyOpenings = 0
        let window = makePanel(model: model, onHistory: { historyOpenings += 1 })
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
        let first = makeComposer(onHistory: { firstOpenings += 1 })
        defer { first.close() }
        let second = makeComposer(onHistory: { secondOpenings += 1 })
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

    func testNativeWordMovementAndSelectionStayInsideEditors() throws {
        let window = makeComposer()
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

    func testEnterAndShiftEnterInBothEditorsPreserveNewlinesWhenSubmitted() throws {
        var requests: [PromptRequest] = []
        let window = makeComposer(onSubmit: { requests.append($0) })
        defer { window.close() }
        let editors = textViews(in: window.contentView!)
        for editor in editors {
            window.makeFirstResponder(editor)
            editor.insertText("First", replacementRange: editor.selectedRange())
            settle(window)
            sendKey("\r", code: 36, to: window)
            XCTAssertTrue(requests.isEmpty)
            editor.insertText("Second", replacementRange: editor.selectedRange())
            settle(window)
            sendKey("\r", code: 36, modifiers: .shift, to: window)
            editor.insertText("Third", replacementRange: editor.selectedRange())
            settle(window)
            XCTAssertEqual(editor.string, "First\nSecond\nThird")
        }
        XCTAssertTrue(requests.isEmpty)
        sendKey("\r", code: 36, modifiers: .command, to: window)
        XCTAssertEqual(requests, [PromptRequest(prompt: "First\nSecond\nThird", input: "First\nSecond\nThird")])
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

    func testSavedResultOpensAndCanBeEditedWithOriginalInput() throws {
        let model = FloaterViewModel(provider: TestProvider())
        let controller = FloatingPanelController(viewModel: model)
        let entry = HistoryEntry(
            request: PromptRequest(prompt: "Translate", input: "Hola\nMundo", title: "Saved translation"),
            response: "Hello\nWorld"
        )
        model.restore(entry)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.dismiss() }
        settle(window)
        XCTAssertEqual(window.title, "Saved translation")
        XCTAssertEqual(model.response, entry.response)
        XCTAssertFalse(model.isGenerating)

        sendKey("\t", code: 48, modifiers: .option, to: window)
        sendKey("\r", code: 36, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).map(\.string), [entry.request.prompt, entry.request.input])
        sendKey("\r", code: 36, modifiers: .command, to: window)
        XCTAssertEqual(model.currentRequest, entry.request)
    }

    private func makeComposer(
        onSubmit: @escaping (PromptRequest) -> Void = { _ in },
        onDismiss: @escaping () -> Void = {},
        onHistory: @escaping () -> Void = {}
    ) -> NSWindow {
        makePanel(
            model: FloaterViewModel(provider: TestProvider()), onSubmit: onSubmit,
            onDismiss: onDismiss, onHistory: onHistory
        )
    }

    private func makePanel(
        model: FloaterViewModel,
        onSubmit: @escaping (PromptRequest) -> Void = { _ in },
        onCopy: @escaping () -> Void = {},
        onReplace: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        onHistory: @escaping () -> Void = {},
        accessibility: AccessibilityAccess = AccessibilityAccess(isTrusted: { true }, requestAccess: {})
    ) -> NSWindow {
        _ = NSApplication.shared
        let view = FloaterPanelView(
            viewModel: model,
            onSubmit: onSubmit,
            onCopy: onCopy,
            onReplace: onReplace,
            onDismiss: onDismiss,
            onContentChange: {},
            onHistory: onHistory,
            accessibility: accessibility
        )
        let hostingView = NSHostingView(rootView: view)
        let window = FloaterPanel(
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
        let event = keyEvent(characters, code: code, modifiers: modifiers, window: window)
        if !modifiers.contains(.command) || !window.performKeyEquivalent(with: event) {
            window.sendEvent(event)
        }
        settle(window)
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }

    private func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
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
private struct TestProvider: AIProvider {
    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        onUpdate("Test response")
    }
}
