import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
final class ResultsViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated { _ = NSApplication.shared }
    }

    func testLongPromptHasItsOwnScrollableAreaAboveTheChat() throws {
        let state = FloaterState(provider: TestProvider())
        let prompt = String(repeating: "Detailed instructions that must remain readable.\n", count: 100)
        state.restore(HistoryEntry(request: PromptRequest(prompt: prompt), response: String(repeating: "Reply\n", count: 100)))
        state.isPromptExpanded = true
        let controller = FloatingPanelController(state: state)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        defer { controller.hide() }
        settle(window)
        let promptScroll = try XCTUnwrap(descendants(of: NSScrollView.self, in: window.contentView!).first {
            $0.identifier?.rawValue == "promptText"
        })
        let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        XCTAssertEqual(textViews(in: promptScroll).first?.string, prompt)
        XCTAssertEqual(promptScroll.contentView.bounds.minY, 0, accuracy: 1, "The prompt should open at its beginning")
        let promptText = try XCTUnwrap(textViews(in: promptScroll).first)
        let lineHeight = try XCTUnwrap(promptText.layoutManager).defaultLineHeight(for: try XCTUnwrap(promptText.font))
            + (promptText.defaultParagraphStyle?.lineSpacing ?? 0)
        XCTAssertEqual(promptScroll.contentView.bounds.height, ceil(lineHeight * 6) + 8, accuracy: 1)
        let promptBounds = promptScroll.convert(promptScroll.bounds, to: window.contentView)
        let chatBounds = chat.convert(chat.bounds, to: window.contentView)
        let gap = max(chatBounds.minY - promptBounds.maxY, promptBounds.minY - chatBounds.maxY)
        XCTAssertGreaterThanOrEqual(gap, 24, "The prompt and conversation need clear separation")
        XCTAssertGreaterThan(promptScroll.documentView!.frame.height, promptScroll.contentSize.height)
        let chatOffset = chat.contentView.bounds.origin
        promptScroll.contentView.scroll(to: NSPoint(x: 0, y: promptScroll.documentView!.frame.height))
        promptScroll.reflectScrolledClipView(promptScroll.contentView)
        settle(window)
        XCTAssertGreaterThan(promptScroll.contentView.bounds.minY, 0)
        XCTAssertEqual(chat.contentView.bounds.origin, chatOffset)
        XCTAssertFalse(textViews(in: chat).contains { $0.string.contains("Detailed instructions") })
    }

    func testChatMessagesUseOppositeSidesWithoutSpeakerLabels() throws {
        let state = FloaterState(provider: TestProvider())
        var entry = HistoryEntry(request: PromptRequest(prompt: "Instructions"), response: "First reply")
        entry.messages += [ChatMessage(role: .user, content: "My follow-up"), ChatMessage(role: .assistant, content: "Second reply")]
        state.restore(entry)
        let window = makeWindow(state: state)
        defer { window.close() }
        let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let texts = textViews(in: chat)
        XCTAssertEqual(texts.map(\.string), ["First reply", "My follow-up", "Second reply"])
        XCTAssertEqual(buttons(in: chat).filter { $0.identifier?.rawValue.hasPrefix("messageCopy-") == true }.count, 3)
        guard texts.count == 3 else { return }
        let replyBounds = texts[0].convert(texts[0].bounds, to: chat.documentView)
        let userBounds = texts[1].convert(texts[1].bounds, to: chat.documentView)
        XCTAssertGreaterThan(userBounds.minX, replyBounds.maxX)
        XCTAssertTrue(texts.allSatisfy(\.isSelectable))
    }

    func testComposerShowsThreeLinesAndScrollsLongDrafts() throws {
        let state = FloaterState(provider: TestProvider())
        state.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        let window = makeWindow(state: state)
        defer { window.close() }
        let editor = try XCTUnwrap(textViews(in: window.contentView!).first { $0.identifier?.rawValue == "composer" })
        let scroll = try XCTUnwrap(editor.enclosingScrollView)
        let send = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Send" })
        let response = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let composerBounds = scroll.convert(scroll.bounds, to: window.contentView)
        let sendBounds = send.convert(send.bounds, to: window.contentView)
        XCTAssertTrue(composerBounds.contains(sendBounds), "Send should sit inside the message box")
        XCTAssertNil(buttons(in: window.contentView!).first { $0.identifier?.rawValue == "compact" })
        XCTAssertEqual(composerBounds.width, response.frame.width, accuracy: 1)
        XCTAssertTrue(send.title.isEmpty, "Send should show only its icon")
        XCTAssertNotNil(send.image)
        let layout = try XCTUnwrap(editor.layoutManager)
        let lineHeight = layout.defaultLineHeight(for: try XCTUnwrap(editor.font))
            + (editor.defaultParagraphStyle?.lineSpacing ?? 0)
        let expectedHeight = ceil(lineHeight * 3) + editor.textContainerInset.height * 2
        XCTAssertEqual(scroll.contentView.bounds.height, expectedHeight, accuracy: 1)

        let draft = (1...12).map { "Line \($0): a draft message." }.joined(separator: "\n")
        editor.insertText(draft, replacementRange: NSRange(location: 0, length: 0))
        settle(window)
        XCTAssertEqual(state.followUp, draft)
        XCTAssertEqual(scroll.contentView.bounds.height, expectedHeight, accuracy: 1)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "Typing should keep the caret visible")
        XCTAssertGreaterThan(scroll.documentView!.bounds.height, scroll.contentView.bounds.height)

        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        settle(window)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
        editor.scrollRangeToVisible(NSRange(location: (draft as NSString).length, length: 0))
        settle(window)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0, "The last line should be reachable")

        state.followUp = ""
        settle(window)
        XCTAssertEqual(scroll.contentView.bounds.height, expectedHeight, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
    }

    func testMessageCopyUsesOriginalContentWithoutChangingTheConversation() throws {
        let state = FloaterState(provider: TestProvider(), historyStore: HistoryStore(fileURL: nil))
        var entry = HistoryEntry(request: PromptRequest(prompt: "Instructions"), response: "First reply")
        let followUp = ChatMessage(role: .user, content: "My follow-up")
        let partial = ChatMessage(role: .assistant, content: "Partial reply", status: .stopped)
        entry.messages += [followUp, partial]
        state.restore(entry)
        state.followUp = "Unsent draft"
        var dismissals = 0
        let window = makeWindow(state: state, onDismiss: { dismissals += 1 })
        defer { window.close() }
        let chat = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        var copied: [String] = []
        chat.onCopyMessage = { copied.append($0) }
        let original = state.conversation
        for message in entry.messages.dropFirst() {
            let button = try XCTUnwrap(buttons(in: chat).first {
                $0.identifier?.rawValue == "messageCopy-\(message.id)"
            })
            XCTAssertTrue(button.isEnabled)
            button.performClick(nil)
        }
        XCTAssertEqual(copied, ["First reply", "My follow-up", "Partial reply"])
        XCTAssertEqual(state.conversation, original)
        XCTAssertEqual(state.followUp, "Unsent draft")
        XCTAssertEqual(dismissals, 0)
    }

    func testSavedRunnerErrorDoesNotDisplayTheRawTemplate() throws {
        var entry = HistoryEntry(request: PromptRequest(prompt: "Original"), response: "First reply")
        entry.messages.append(ChatMessage(role: .user, content: "Follow up"))
        var failed = ChatMessage(role: .assistant, content: "", status: .failed)
        failed.error = "Gemma could not finish this request. lexer failed; {% set previous_messages = secret user prompt %}"
        entry.messages.append(failed)
        let state = FloaterState(provider: TestProvider())
        state.restore(entry)
        let window = makeWindow(state: state)
        defer { window.close() }
        let text = try XCTUnwrap(descendants(of: ResponseScrollView.self, in: window.contentView!).first)
        let displayed = textViews(in: text).map(\.string).joined(separator: "\n")
        XCTAssertTrue(displayed.contains("First reply"))
        XCTAssertTrue(displayed.contains("Follow up"))
        XCTAssertTrue(displayed.contains("[Failed]"))
        XCTAssertFalse(displayed.contains("previous_messages"))
        XCTAssertFalse(displayed.contains("secret user prompt"))
    }

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
        sendKey("s", code: 1, modifiers: .command, to: window)
        XCTAssertEqual(replacements, 0)
        granted = true
        access.refresh()
        settle(window)
        XCTAssertTrue(replace.isEnabled)
        XCTAssertNil(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Enable Accessibility" })
        sendKey("r", code: 15, modifiers: [.command, .shift], to: window)
        XCTAssertEqual(replacements, 0)
        sendKey("s", code: 1, modifiers: .command, to: window)
        XCTAssertEqual(replacements, 1)
        granted = false
        access.refresh()
        settle(window)
        XCTAssertFalse(replace.isEnabled)
    }

    func testOptionTabTraversesComposerAndActionsInBothDirections() throws {
        let model = FloaterState(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        model.setCanReplace(true)
        let window = makeWindow(state: model)
        defer { window.close() }
        let order = ["composer", "copy", "edit", "replace", "dismiss", "history", "new"]
        for identifier in order.dropFirst() + ["composer"] {
            window.sendEvent(keyEvent("\t", code: 48, modifiers: .option, window: window))
            XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, identifier)
        }
        for identifier in order.dropFirst().reversed() + ["composer"] {
            sendKey("\t", code: 48, modifiers: [.option, .shift], to: window)
            XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, identifier)
        }
    }

    func testPlainTabStaysInTheComposer() throws {
        let model = FloaterState(provider: TestProvider())
        model.restore(HistoryEntry(request: PromptRequest(prompt: "Prompt"), response: "Result"))
        let window = makeWindow(state: model)
        defer { window.close() }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        sendKey("\t", code: 48, to: window)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertEqual(model.followUp, "\t")
        sendKey("\t", code: 48, modifiers: .option, to: window)
        XCTAssertEqual((window.firstResponder as? NSView)?.identifier?.rawValue, "copy")
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
            for title in ["Copy", "Replace", "Dismiss", "History"] {
                let button = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == title })
                window.makeFirstResponder(button)
                sendKey(characters, code: code, to: window)
            }
            XCTAssertEqual(copies, 1)
            XCTAssertEqual(replacements, 1)
            XCTAssertEqual(dismissals, 1)
            XCTAssertEqual(historyOpenings, 1)
        }
    }

    func testResultsCopyAndEditShortcuts() throws {
        let model = FloaterState(provider: TestProvider())
        let request = PromptRequest(prompt: "Translate\n\nHola\nMundo", title: "Translation")
        model.restore(HistoryEntry(request: request, response: "Hello\nWorld"))
        var copies = 0
        let window = makeWindow(state: model, onCopy: { copies += 1 })
        defer { window.close() }
        let copy = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Copy" })
        window.makeFirstResponder(copy)
        sendKey("c", code: 8, modifiers: .command, to: window)
        XCTAssertEqual(copies, 1)
        sendKey("e", code: 14, modifiers: .command, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).map(\.string), [request.prompt])
        sendKey("e", code: 14, modifiers: .command, to: window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(copies, 1)
    }

    func testSavedResultCanBeUsedAsANewPrompt() throws {
        let model = FloaterState(provider: TestProvider())
        let controller = FloatingPanelController(state: model)
        let entry = HistoryEntry(request: PromptRequest(prompt: "Translate\n\nHola\nMundo", title: "Saved translation"), response: "Hello\nWorld")
        model.restore(entry)
        controller.show(previousApplication: nil)
        let window = try XCTUnwrap(controller.window)
        defer { controller.hide() }
        settle(window)
        XCTAssertEqual(window.title, "Saved translation")
        let edit = try XCTUnwrap(buttons(in: window.contentView!).first { $0.accessibilityLabel() == "Edit as New" })
        edit.performClick(nil)
        settle(window)
        XCTAssertNil(model.currentRequest)
        XCTAssertEqual(textViews(in: window.contentView!).map(\.string), [entry.request.prompt])
        sendKey("\r", code: 36, modifiers: .command, to: window)
        XCTAssertEqual(model.currentRequest, entry.request)
        XCTAssertNotEqual(model.conversation?.id, entry.id)
    }
}
