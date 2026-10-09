import AppKit
import Combine
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
                PanelButton(title: "New", shortcut: .new, identifier: "historyNew", action: onNew)
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
                        onOpen: onOpen, onDelete: store.delete
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
                        PanelButton(title: "Clear history…", isEnabled: !store.entries.isEmpty || store.errorMessage != nil, identifier: "clearHistory") {
                            isConfirmingClear = true
                        }
                        Spacer()
                        PanelButton(title: "Dismiss", shortcut: .dismiss, identifier: "historyDismiss", action: onDismiss)
                        PanelButton(title: "Delete", keyHint: "⌫", isEnabled: selectedEntry != nil, identifier: "historyDelete", action: deleteSelection)
                        PanelButton(title: "Open result", keyHint: "↩", isEnabled: selectedEntry != nil, identifier: "historyOpen") {
                            if let selectedEntry { onOpen(selectedEntry) }
                        }
                    }
                    .padding(12)
                }
            }
            .padding([.horizontal, .bottom], FloaterPanelLayout.padding)
        }
        .frame(width: FloaterPanelLayout.width, height: 500)
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
            if let selectedEntry { onOpen(selectedEntry) }
            return true
        }
        return false
    }

    private func moveFocus(in window: NSWindow, backwards: Bool) {
        PanelKeyboardHandler.moveFocus(
            in: window,
            identifiers: ["historySearch", "historyList", "clearHistory", "historyDismiss", "historyDelete", "historyOpen", "historyNew"],
            backwards: backwards
        )
    }

    private func deleteSelection() {
        guard let selectedEntry else { return }
        store.delete(selectedEntry.id)
    }
}

@MainActor
final class HistoryViewState: ObservableObject {
    @Published var query = ""
    @Published var selection: UUID?
    var focusedControlIdentifier = "historySearch"
}
