import AppKit
import SwiftUI

struct PanelKeyboardHandler: NSViewRepresentable {
    let onKeyDown: (NSEvent, NSWindow) -> Bool

    @discardableResult
    static func moveFocus(
        in window: NSWindow, identifiers: [String], backwards: Bool, fallback: String? = nil
    ) -> String? {
        guard let root = window.contentView else { return nil }
        let controls = identifiers.compactMap { identifier in
            root.firstDescendant(where: {
                $0.identifier?.rawValue == identifier && ($0 as? NSControl)?.isEnabled != false
            })
        }
        guard !controls.isEmpty else { return nil }
        let responder = window.firstResponder
        let current = (responder as? NSTextView)?.isFieldEditor == true
            ? controls.first(where: { ($0 as? NSControl)?.currentEditor() === responder })
            : responder as? NSView
        let index = controls.firstIndex(where: { $0 === current })
            ?? controls.firstIndex(where: { $0.identifier?.rawValue == fallback })
        let destination = index.map { controls[($0 + (backwards ? controls.count - 1 : 1)) % controls.count] }
            ?? (backwards ? controls.last! : controls.first!)
        guard window.makeFirstResponder(destination) else { return nil }
        if let table = destination as? NSTableView, table.selectedRow == -1, table.numberOfRows > 0 {
            let row = backwards ? table.numberOfRows - 1 : 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        return destination.identifier?.rawValue
    }

    func makeNSView(context: Context) -> KeyEventView {
        let view = KeyEventView()
        view.onKeyDown = onKeyDown
        return view
    }

    func updateNSView(_ view: KeyEventView, context: Context) {
        view.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ view: KeyEventView, coordinator: ()) {
        view.stopHandling()
    }

    final class KeyEventView: NSView {
        var onKeyDown: ((NSEvent, NSWindow) -> Bool)? {
            didSet { updateHandler() }
        }
        private weak var panel: FloaterPanel?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopHandling()
            panel = window as? FloaterPanel
            updateHandler()
        }

        private func updateHandler() {
            guard let panel else { return }
            panel.keyboardHandlerOwner = self
            panel.onKeyDown = { [weak self, weak panel] event in
                guard let self, let panel else { return false }
                return self.onKeyDown?(event, panel) == true
            }
        }

        func stopHandling() {
            if panel?.keyboardHandlerOwner === self {
                panel?.onKeyDown = nil
                panel?.keyboardHandlerOwner = nil
            }
            panel = nil
        }

        isolated deinit {
            stopHandling()
        }
    }
}
