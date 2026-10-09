import AppKit
import SwiftUI

struct HistorySearchField: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.placeholderString = "Search prompts, input, and responses (\(PanelShortcut.find.label))"
        field.identifier = NSUserInterfaceItemIdentifier("historySearch")
        field.setAccessibilityLabel("Search history")
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.field = self
        if field.stringValue != text { field.stringValue = text }
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
