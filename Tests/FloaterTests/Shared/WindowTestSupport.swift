import AppKit
import FloaterCore
import SwiftUI
import XCTest
@testable import Floater

@MainActor
func makeNewRequest(
    onSubmit: @escaping (PromptRequest) -> Void = { _ in },
    onDismiss: @escaping () -> Void = {},
    onHistory: @escaping () -> Void = {}
) -> NSWindow {
    makeWindow(
        state: FloaterState(provider: TestProvider()), onSubmit: onSubmit,
        onDismiss: onDismiss, onHistory: onHistory
    )
}

@MainActor
func makeWindow(
    state: FloaterState,
    onSubmit: @escaping (PromptRequest) -> Void = { _ in },
    onCopy: @escaping () -> Void = {},
    onReplace: @escaping () -> Void = {},
    onDismiss: @escaping () -> Void = {},
    onHistory: @escaping () -> Void = {},
    accessibility: AccessibilityAccess = AccessibilityAccess(isTrusted: { true }, requestAccess: {})
) -> NSWindow {
    _ = NSApplication.shared
    let view = FloaterWindowView(
        state: state, accessibility: accessibility,
        onSubmit: onSubmit,
        onCopy: onCopy,
        onReplace: onReplace,
        onDismiss: onDismiss,
        onContentChange: {},
        onHistory: onHistory,
        history: HistoryView(store: HistoryStore(fileURL: nil), onOpen: { _ in }, onClear: {})
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

@MainActor
func settle(_ window: NSWindow) {
    for _ in 0..<3 {
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    }
}

@MainActor
func sendKey(
    _ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], to window: NSWindow
) {
    let event = keyEvent(characters, code: code, modifiers: modifiers, window: window)
    if !modifiers.contains(.command) || !window.performKeyEquivalent(with: event) {
        window.sendEvent(event)
    }
    settle(window)
}

@MainActor
func descendants<T: NSView>(of type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants(of: type, in: $0) }
}

@MainActor
func textViews(in view: NSView) -> [NSTextView] { descendants(of: NSTextView.self, in: view) }

@MainActor
func buttons(in view: NSView) -> [NSButton] { descendants(of: NSButton.self, in: view) }

@MainActor
func keyEvent(
    _ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [], window: NSWindow
) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: code
    )!
}

@MainActor
struct TestProvider: AIProvider {
    func generate(_ request: PromptRequest, onUpdate: @MainActor (String) -> Void) async throws {
        onUpdate("Test response")
    }
}
