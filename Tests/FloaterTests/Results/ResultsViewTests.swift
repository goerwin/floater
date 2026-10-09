import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class ResultsViewTests: XCTestCase {
    func testReplaceIsDisabledUntilAccessibilityIsGrantedAndCanRequestAccess() throws {
        var granted = false
        var requests = 0
        var replacements = 0
        let access = AccessibilityAccess(isTrusted: { granted }, requestAccess: { requests += 1 })
        let model = FloaterState(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        let window = makeWindow(state: model, onReplace: { replacements += 1 }, accessibility: access)
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

    func testRapidTabPressesMoveNativeFocusImmediately() throws {
        let model = FloaterState(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        let window = makeWindow(state: model)
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

    func testPlainAndOptionTabUseSameFocusOrderInBothDirections() throws {
        for option: NSEvent.ModifierFlags in [[], .option] {
            let model = FloaterState(provider: TestProvider())
            model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
            model.setCanReplace(true)
            let window = makeWindow(state: model)
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

    func testResultsActionsActivateWithEnterAndSpace() throws {
        for (characters, code) in [("\r", UInt16(36)), (" ", UInt16(49))] {
            let model = FloaterState(provider: TestProvider())
            model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
            model.setCanReplace(true)
            var copies = 0
            var replacements = 0
            var dismissals = 0
            var historyOpenings = 0
            let window = makeWindow(
                state: model, onCopy: { copies += 1 }, onReplace: { replacements += 1 },
                onDismiss: { dismissals += 1 }, onHistory: { historyOpenings += 1 }
            )
            defer { window.close() }
            sendKey(characters, code: code, to: window)
            XCTAssertEqual(copies, 1)
            sendKey("\t", code: 48, to: window)
            sendKey("\t", code: 48, to: window)
            sendKey(characters, code: code, to: window)
            XCTAssertEqual(replacements, 1)
            sendKey("\t", code: 48, to: window)
            sendKey(characters, code: code, to: window)
            XCTAssertEqual(dismissals, 1)
            sendKey("\t", code: 48, to: window)
            sendKey(characters, code: code, to: window)
            XCTAssertEqual(historyOpenings, 1)
        }
    }

    func testResultsCopyAndEditShortcuts() throws {
        let model = FloaterState(provider: TestProvider())
        let request = PromptRequest(prompt: "Translate", input: "Hola\nMundo", title: "Translation")
        model.restore(HistoryEntry(request: request, response: "Hello\nWorld"))
        var copies = 0
        let window = makeWindow(state: model, onCopy: { copies += 1 })
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

    func testSavedResultOpensAndCanBeEditedWithOriginalInput() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
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
}
