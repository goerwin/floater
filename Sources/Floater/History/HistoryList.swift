import AppKit
import SwiftUI

struct HistoryList: NSViewRepresentable {
    let entries: [HistoryEntry]
    @Binding var selection: UUID?
    let onOpen: (HistoryEntry) -> Void
    let onDelete: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(list: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 56
        table.style = .fullWidth
        table.backgroundColor = .clear
        table.allowsMultipleSelection = false
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.openSelection(_:))
        table.identifier = NSUserInterfaceItemIdentifier("historyList")
        table.setAccessibilityLabel("Saved requests")
        table.onOpen = { [weak coordinator = context.coordinator] in coordinator?.openSelection(nil) }
        table.onDelete = { [weak coordinator = context.coordinator] in coordinator?.deleteSelection(nil) }
        let menu = NSMenu()
        for (title, action) in [("Open result", #selector(Coordinator.openSelection(_:))), ("Delete", #selector(Coordinator.deleteSelection(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = context.coordinator
            menu.addItem(item)
        }
        table.menu = menu
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? NSTableView else { return }
        let coordinator = context.coordinator
        let entriesChanged = coordinator.list.entries != entries
        coordinator.list = self
        coordinator.isUpdating = true
        if entriesChanged || table.numberOfRows != entries.count { table.reloadData() }
        let index = entries.firstIndex { $0.id == selection }
        let selected = index.map { IndexSet(integer: $0) } ?? IndexSet()
        if table.selectedRowIndexes != selected { table.selectRowIndexes(selected, byExtendingSelection: false) }
        coordinator.isUpdating = false
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var list: HistoryList
        var isUpdating = false
        private weak var table: NSTableView?

        init(list: HistoryList) { self.list = list }

        func numberOfRows(in tableView: NSTableView) -> Int {
            table = tableView
            return list.entries.count
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("historyRow")
            let view = tableView.makeView(withIdentifier: identifier, owner: nil) as? RowView ?? RowView()
            view.identifier = identifier
            let entry = list.entries[row]
            view.title.stringValue = entry.title
            view.date.stringValue = entry.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
            view.preview.stringValue = entry.response.replacingOccurrences(of: "\n", with: " ")
            return view
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table = notification.object as? NSTableView else { return }
            list.selection = table.selectedRow >= 0 ? list.entries[table.selectedRow].id : nil
        }

        @objc func openSelection(_ sender: Any?) {
            guard let row = table?.selectedRow, list.entries.indices.contains(row) else { return }
            list.onOpen(list.entries[row])
        }

        @objc func deleteSelection(_ sender: Any?) {
            guard let row = table?.selectedRow, list.entries.indices.contains(row) else { return }
            list.onDelete(list.entries[row].id)
        }
    }

    final class TableView: NSTableView {
        var onOpen: (() -> Void)?
        var onDelete: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
            if modifiers.isEmpty, [36, 76].contains(event.keyCode) {
                onOpen?()
            } else if modifiers.isEmpty, [51, 117].contains(event.keyCode) {
                onDelete?()
            } else {
                super.keyDown(with: event)
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let row = row(at: convert(event.locationInWindow, from: nil))
            guard row >= 0 else { return nil }
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return super.menu(for: event)
        }
    }

    final class RowView: NSTableCellView {
        let title = NSTextField(labelWithString: "")
        let date = NSTextField(labelWithString: "")
        let preview = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            title.font = .systemFont(ofSize: 13, weight: .medium)
            date.font = .systemFont(ofSize: 11)
            date.textColor = .secondaryLabelColor
            preview.font = .systemFont(ofSize: 12)
            preview.textColor = .secondaryLabelColor
            for field in [title, preview] {
                field.lineBreakMode = .byTruncatingTail
                field.maximumNumberOfLines = 1
                field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            }
            let heading = NSStackView(views: [title, date])
            heading.distribution = .fill
            heading.alignment = .firstBaseline
            let stack = NSStackView(views: [heading, preview])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 4
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                stack.centerYAnchor.constraint(equalTo: centerYAnchor),
                heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
                preview.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
            textField = title
        }

        required init?(coder: NSCoder) { nil }
    }
}
