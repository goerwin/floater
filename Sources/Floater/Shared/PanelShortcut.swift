import AppKit

enum PanelShortcut {
    case copy, edit, replace, dismiss, history, run, new, find

    var label: String {
        switch self {
        case .dismiss: "⎋"
        case .replace: "⌘⇧R"
        default: "⌘" + keyEquivalent.uppercased()
        }
    }

    var keyEquivalent: String {
        switch self {
        case .copy: "c"
        case .edit: "e"
        case .replace: "r"
        case .dismiss: "\u{1b}"
        case .history: "h"
        case .run: "r"
        case .new: "n"
        case .find: "f"
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .dismiss: []
        case .replace: [.command, .shift]
        default: .command
        }
    }

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if self == .dismiss { return event.keyCode == 53 && flags.isEmpty }
        return flags == modifiers && event.charactersIgnoringModifiers?.lowercased() == keyEquivalent
    }
}
