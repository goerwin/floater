import AppKit
import SwiftUI

struct HistorySearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeNSView(context: Context) -> SearchField {
        let field = SearchField()
        field.delegate = context.coordinator
        field.placeholderString = "Search prompts, input, and responses (\(PanelShortcut.find.label))"
        field.identifier = NSUserInterfaceItemIdentifier("historySearch")
        field.setAccessibilityLabel("Search history")
        return field
    }

    func updateNSView(_ field: SearchField, context: Context) {
        context.coordinator.field = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class SearchField: NSSearchField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.initialFirstResponder = self
            window?.makeFirstResponder(self)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var field: HistorySearchField
        init(field: HistorySearchField) { self.field = field }
        func controlTextDidChange(_ notification: Notification) {
            guard let search = notification.object as? NSSearchField else { return }
            field.text = search.stringValue
        }
    }
}
