import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class HistoryViewTests: XCTestCase {
    private var controller: FloatingPanelController?
    private var model: FloaterViewModel?

    func testTabIntoListSelectsAnEdgeRowInTheTraversalDirection() throws {
        for modifiers: NSEvent.ModifierFlags in [[], .option, .shift, [.option, .shift]] {
            let store = HistoryStore(fileURL: nil)
            for index in 1...3 {
                store.record(PromptRequest(prompt: "Sample \(index)"), response: "Result \(index)")
            }
            let window = makeWindow(store: store)
            defer { window.close() }
            let root = try XCTUnwrap(window.contentView)
            let list = try XCTUnwrap(descendants(of: NSTableView.self, in: root).first)
            XCTAssertEqual(list.selectedRow, -1)
            let backwards = modifiers.contains(.shift)
            let source = backwards
                ? try XCTUnwrap(root.firstDescendant(where: { $0.identifier?.rawValue == "clearHistory" }))
                : try XCTUnwrap(root.firstDescendant(where: { $0.identifier?.rawValue == "historySearch" }))
            window.makeFirstResponder(source)
            sendKey("\t", code: 48, modifiers: modifiers, to: window)
            let expectedRow = backwards ? store.entries.count - 1 : 0
            XCTAssertTrue(window.firstResponder === list)
            XCTAssertEqual(list.selectedRow, expectedRow)
            sendKey("\r", code: 36, to: window)
            XCTAssertEqual(model?.currentRequest, store.entries[expectedRow].request)
        }
    }

    func testTabIntoListPreservesAnExistingSelection() throws {
        let store = HistoryStore(fileURL: nil)
        for index in 1...3 {
            store.record(PromptRequest(prompt: "Sample \(index)"), response: "Result \(index)")
        }
        let window = makeWindow(store: store)
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView)
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: root).first)
        list.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        settle(window)
        for modifiers: NSEvent.ModifierFlags in [[], .option, .shift, [.option, .shift]] {
            let source = modifiers.contains(.shift)
                ? try XCTUnwrap(root.firstDescendant(where: { $0.identifier?.rawValue == "clearHistory" }))
                : try XCTUnwrap(root.firstDescendant(where: { $0.identifier?.rawValue == "historySearch" }))
            window.makeFirstResponder(source)
            sendKey("\t", code: 48, modifiers: modifiers, to: window)
            XCTAssertTrue(window.firstResponder === list)
            XCTAssertEqual(list.selectedRow, 1)
        }
    }

    func testTabIntoAnEmptyListKeepsSelectionEmpty() throws {
        let window = makeWindow(store: HistoryStore(fileURL: nil))
        defer { window.close() }
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        sendKey("\t", code: 48, to: window)
        XCTAssertTrue(window.firstResponder === list)
        XCTAssertEqual(list.selectedRow, -1)
    }

    func testDismissSavedResponseReturnsToHistoryWithSearchAndSelection() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Translate", input: "Hola"), response: "Hello")
        store.record(PromptRequest(prompt: "Other"), response: "Other result")
        let window = makeWindow(store: store)
        defer { controller?.hide() }
        let search = try XCTUnwrap(descendants(of: NSSearchField.self, in: window.contentView!).first)
        window.makeFirstResponder(search)
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        editor.insertText("Hola", replacementRange: editor.selectedRange())
        settle(window)
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        window.makeFirstResponder(list)
        list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        sendKey("\r", code: 36, to: window)
        XCTAssertFalse(controller?.isShowingHistory ?? true)
        let dismiss = try XCTUnwrap(descendants(of: NSButton.self, in: window.contentView!).first { $0.accessibilityLabel() == "Dismiss" })
        window.makeFirstResponder(dismiss)
        let enter = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r",
            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        )!
        if !window.performKeyEquivalent(with: enter) { window.sendEvent(enter) }
        settle(window)
        XCTAssertTrue(controller?.isShowingHistory ?? false)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(descendants(of: NSSearchField.self, in: window.contentView!).first?.stringValue, "Hola")
        let restoredList = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        XCTAssertEqual(restoredList.numberOfRows, 1)
        XCTAssertEqual(restoredList.selectedRow, 0)
        XCTAssertTrue(window.firstResponder === restoredList, "Returning from a result should restore list focus")
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertFalse(window.isVisible)
    }

    func testCancelClearHistoryRestoresTheFocusedButton() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Sample"), response: "Sample result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let clear = try XCTUnwrap(descendants(of: NSButton.self, in: window.contentView!).first { $0.identifier?.rawValue == "clearHistory" })
        window.makeFirstResponder(clear)
        sendKey("\r", code: 36, to: window)
        let alert = try XCTUnwrap(NSApp.windows.first {
            $0 !== window && $0.isVisible && descendants(of: NSButton.self, in: $0.contentView ?? NSView()).contains { $0.title == "Clear history" }
        })
        let cancel = try XCTUnwrap(descendants(of: NSButton.self, in: alert.contentView!).first { $0.title == "Cancel" })
        cancel.performClick(nil)
        settle(window)
        window.becomeKey()
        settle(window)
        XCTAssertFalse(alert.isVisible)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertTrue(window.firstResponder === clear, "Canceling Clear history should restore its button focus")
    }

    func testDismissSavedResponseRestoresOpenButtonFocus() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Sample"), response: "Sample result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        settle(window)
        let open = try XCTUnwrap(descendants(of: NSButton.self, in: window.contentView!).first { $0.identifier?.rawValue == "historyOpen" })
        window.makeFirstResponder(open)
        sendKey("\r", code: 36, to: window)
        XCTAssertFalse(controller?.isShowingHistory ?? true)
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertTrue(controller?.isShowingHistory ?? false)
        XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "historyOpen")
    }

    func testConfirmClearHistoryKeepsFocusOutOfSearch() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Sample"), response: "Sample result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let clear = try XCTUnwrap(descendants(of: NSButton.self, in: window.contentView!).first { $0.identifier?.rawValue == "clearHistory" })
        window.makeFirstResponder(clear)
        sendKey("\r", code: 36, to: window)
        let alert = try XCTUnwrap(NSApp.windows.first {
            $0 !== window && $0.isVisible && descendants(of: NSButton.self, in: $0.contentView ?? NSView()).contains { $0.title == "Clear history" }
        })
        let confirm = try XCTUnwrap(descendants(of: NSButton.self, in: alert.contentView!).first { $0.title == "Clear history" })
        confirm.performClick(nil)
        settle(window)
        window.becomeKey()
        settle(window)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(clear.isEnabled)
        let search = try XCTUnwrap(descendants(of: NSSearchField.self, in: window.contentView!).first)
        XCTAssertNil(search.currentEditor(), "Clearing history should not focus Search")
        XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "Dismiss", "Actual: \(String(describing: window.firstResponder))")
        sendKey("\t", code: 48, to: window)
        XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "New")
    }

    func testTabFromHistoryListFocusesClearHistoryWithOnePress() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Sample"), response: "Sample result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        window.makeFirstResponder(list)
        sendKey("\t", code: 48, to: window)
        XCTAssertEqual((window.firstResponder as? NSButton)?.accessibilityLabel(), "Clear history…", "Actual responder: \(String(describing: window.firstResponder))")
    }

    func testOptionTabUsesTheNativeHistoryFocusOrder() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Prompt"), response: "Result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        for backwards in [false, true] {
            window.makeFirstResponder(list)
            settle(window)
            let plain: NSEvent.ModifierFlags = backwards ? .shift : []
            sendKey("\t", code: 48, modifiers: plain, to: window)
            let expected = try XCTUnwrap(window.firstResponder)
            window.makeFirstResponder(list)
            settle(window)
            sendKey("\t", code: 48, modifiers: plain.union(.option), to: window)
            XCTAssertTrue(window.firstResponder === expected, "Backward \(backwards): expected \(expected), got \(String(describing: window.firstResponder))")
        }
    }
    func testCommandFFocusesSearchAndEscapeClosesHistory() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Prompt"), response: "Result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView?.superview)
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: root).first)
        let search = try XCTUnwrap(descendants(of: NSSearchField.self, in: root).first)
        window.makeFirstResponder(list)
        let find = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "f",
            charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3
        )!
        if !window.performKeyEquivalent(with: find) { window.sendEvent(find) }
        settle(window)
        XCTAssertNotNil(search.currentEditor())
        sendKey("\u{1b}", code: 53, to: window)
        XCTAssertFalse(window.isVisible)
    }
    func testSelectedHistoryResultOpensWithReturn() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Translate", input: "Hola", title: "Translation"), response: "Hello")
        let window = makeWindow(store: store)
        defer { window.close() }
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        XCTAssertEqual(list.numberOfRows, 1)
        window.makeFirstResponder(list)
        list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        settle(window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(model?.currentRequest, store.entries.first?.request)
        XCTAssertEqual(model?.response, store.entries.first?.response)
        XCTAssertFalse(controller?.isShowingHistory ?? true)
        XCTAssertTrue(window.isVisible)
    }

    func testSelectedHistoryResultCanBeDeletedWithKeyboard() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "First"), response: "First result")
        store.record(PromptRequest(prompt: "Second"), response: "Second result")
        let window = makeWindow(store: store)
        defer { window.close() }
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: window.contentView!).first)
        window.makeFirstResponder(list)
        list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        settle(window)
        sendKey("\u{7f}", code: 51, to: window)
        XCTAssertEqual(store.entries.map(\.request.prompt), ["First"])
        XCTAssertEqual(list.numberOfRows, 1)
    }

    func testSearchFiltersHistoryByOriginalInput() throws {
        let store = HistoryStore(fileURL: nil)
        store.record(PromptRequest(prompt: "Translate", input: "Hola"), response: "Hello")
        store.record(PromptRequest(prompt: "Summarize", input: "Other text"), response: "Summary")
        let window = makeWindow(store: store)
        defer { window.close() }
        let root = try XCTUnwrap(window.contentView?.superview)
        let search = try XCTUnwrap(descendants(of: NSSearchField.self, in: root).first)
        let list = try XCTUnwrap(descendants(of: NSTableView.self, in: root).first)
        XCTAssertEqual(list.numberOfRows, 2)
        window.makeFirstResponder(search)
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        editor.insertText("Hola", replacementRange: editor.selectedRange())
        settle(window)
        XCTAssertEqual(list.numberOfRows, 1)
        window.makeFirstResponder(list)
        list.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        settle(window)
        sendKey("\r", code: 36, to: window)
        XCTAssertEqual(model?.currentRequest?.input, "Hola")
    }

    private func makeWindow(
        store: HistoryStore
    ) -> NSWindow {
        _ = NSApplication.shared
        let model = FloaterViewModel(provider: HistoryTestProvider())
        self.model = model
        let controller = FloatingPanelController(viewModel: model, historyStore: store)
        controller.showHistory()
        self.controller = controller
        let window = controller.window!
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        settle(window)
        return window
    }

    private func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<3 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    private func sendKey(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], to window: NSWindow) {
        window.sendEvent(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code
        )!)
        settle(window)
    }
}

@MainActor
private struct HistoryTestProvider: AIProvider {
    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        XCTFail("Opening history must not generate a response")
    }
}
