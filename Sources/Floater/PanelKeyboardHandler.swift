import AppKit
import SwiftUI

struct PanelKeyboardHandler: NSViewRepresentable {
    let onKeyDown: (NSEvent, NSWindow) -> Bool

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
