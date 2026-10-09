import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    let onOpen: (HistoryEntry) -> Void
    let onClear: () -> Void
    var onDismiss: () -> Void = {}
    var onNew: () -> Void = {}
    @ObservedObject var state = HistoryViewState()
    @State private var isConfirmingClear = false

    private var filteredEntries: [HistoryEntry] {
        store.entries.filter { $0.matches(state.query) }
    }

    private var selectedEntry: HistoryEntry? {
        filteredEntries.first { $0.id == state.selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader {
                Text("History")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                historyButton("New", shortcut: .new, identifier: "historyNew", action: onNew)
            }
            VStack(spacing: 8) {
                HistorySearchField(text: $state.query)
                    .frame(height: 28)
                VStack(spacing: 0) {
                    if let errorMessage = store.errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }

                    HistoryList(
                        entries: filteredEntries, selection: $state.selection,
                        onOpen: open, onDelete: store.delete
                    )
                    .overlay {
                        if filteredEntries.isEmpty {
                            ContentUnavailableView(
                                state.query.isEmpty ? "No history yet" : "No matching results",
                                systemImage: "clock.arrow.circlepath",
                                description: Text(state.query.isEmpty
                                    ? "Completed requests will appear here."
                                    : "Try a different search.")
                            )
                            .allowsHitTesting(false)
                        }
                    }

                    Divider()
                    HStack {
                        Text("\(store.entries.count) of \(HistoryStore.limit) saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        historyButton("Clear history…", identifier: "clearHistory", enabled: !store.entries.isEmpty || store.errorMessage != nil) {
                            isConfirmingClear = true
                        }
                        Spacer()
                        historyButton("Dismiss", shortcut: .dismiss, identifier: "historyDismiss", action: onDismiss)
                        historyButton("Delete", keyHint: "⌫", identifier: "historyDelete", enabled: selectedEntry != nil, action: deleteSelection)
                        historyButton("Open result", keyHint: "↩", identifier: "historyOpen", enabled: selectedEntry != nil) {
                            if let selectedEntry { open(selectedEntry) }
                        }
                    }
                    .padding(12)
                }
            }
            .padding([.horizontal, .bottom], FloaterPanelLayout.padding)
        }
        .frame(width: FloaterPanelLayout.width, height: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .background {
            PanelKeyboardHandler(onKeyDown: handleKeyDown)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .alert("Clear all history?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear history", role: .destructive, action: onClear)
        } message: {
            Text("This deletes all saved prompts, input, and responses from this Mac.")
        }
    }

    private func historyButton(
        _ title: String, shortcut: PanelShortcut? = nil, keyHint: String? = nil,
        identifier: String, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        PanelButton(
            title: title, shortcut: shortcut, keyHint: keyHint, isEnabled: enabled,
            isFocused: false, identifier: identifier, onFocus: {}, action: action
        )
        .fixedSize()
        .controlSize(.regular)
        .disabled(!enabled)
    }

    private func handleKeyDown(_ event: NSEvent, window: NSWindow) -> Bool {
        guard window.attachedSheet == nil else { return false }
        if PanelShortcut.dismiss.matches(event) { onDismiss(); return true }
        if PanelShortcut.new.matches(event) { onNew(); return true }
        if PanelShortcut.history.matches(event) { return true }
        if PanelShortcut.find.matches(event),
           let search = window.contentView?.firstDescendant(where: { $0 is NSSearchField }) {
            window.makeFirstResponder(search)
            return true
        }
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if event.keyCode == 48, modifiers.subtracting([.option, .shift]).isEmpty {
            moveFocus(in: window, backwards: modifiers.contains(.shift))
            return true
        }
        if [36, 76].contains(event.keyCode), modifiers.isEmpty, window.firstResponder is NSTableView {
            if let selectedEntry { open(selectedEntry) }
            return true
        }
        return false
    }

    private func moveFocus(in window: NSWindow, backwards: Bool) {
        guard let root = window.contentView,
              let search = root.firstDescendant(where: { $0 is NSSearchField }),
              let list = root.firstDescendant(where: { $0 is NSTableView }) else { return }
        let identifiers = ["clearHistory", "historyDismiss", "historyDelete", "historyOpen", "historyNew"]
        let buttons = identifiers.compactMap { identifier in
            root.firstDescendant(where: { $0.identifier?.rawValue == identifier && ($0 as? NSControl)?.isEnabled == true })
        }
        let controls = [search, list] + buttons
        let current = window.firstResponder
        let currentView = (current as? NSTextView)?.isFieldEditor == true ? search : current as? NSView
        let destination: NSView
        if let index = controls.firstIndex(where: { $0 === currentView }) {
            destination = controls[(index + (backwards ? controls.count - 1 : 1)) % controls.count]
        } else {
            destination = backwards ? controls.last! : controls.first!
        }
        if window.makeFirstResponder(destination), let table = destination as? NSTableView,
           table.selectedRow == -1, table.numberOfRows > 0 {
            let row = backwards ? table.numberOfRows - 1 : 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
    }

    private func deleteSelection() {
        guard let selectedEntry else { return }
        store.delete(selectedEntry.id)
    }

    private func open(_ entry: HistoryEntry) {
        onOpen(entry)
    }
}
