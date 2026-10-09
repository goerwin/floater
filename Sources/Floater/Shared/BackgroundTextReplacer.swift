import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum TextSelection: Equatable {
    case selected
    case none
    case unavailable

    static func read(range: NSRange?, selectedText: String?) -> Self {
        if selectedText?.isEmpty == false { return .selected }
        if let range {
            guard range.location != NSNotFound, range.location >= 0, range.length >= 0 else {
                return .unavailable
            }
            return range.length > 0 ? .selected : .none
        }
        return .unavailable
    }
}

enum PasteCommand {
    case selectAll
    case paste
}

@MainActor
protocol TextPasteTarget {
    var selection: TextSelection { get }
    func focus() async throws
    func checkFocus() throws
    func send(_ command: PasteCommand) throws
}

enum TextReplacementError: LocalizedError {
    case noFocusedField
    case notEditable
    case selectionRequired
    case invalidSelection
    case clipboardUnavailable
    case unsupported

    var errorDescription: String? {
        switch self {
        case .noFocusedField:
            "The original editor is no longer focused. The result is copied; focus the editor and paste it."
        case .notEditable:
            "The focused field cannot be edited. The result is copied; paste it into an editable field."
        case .selectionRequired:
            "Select text in the previous app, or enable Configuration > Replace entire focused field. The result is copied."
        case .invalidSelection:
            "The previous app did not provide a readable selection. The result is copied; paste it into your editor."
        case .clipboardUnavailable:
            "Floater could not copy the result. Try Copy again."
        case .unsupported:
            "Floater could not send Paste to the previous app. The result is copied; paste it into your editor."
        }
    }
}

@MainActor
enum TextReplacement {
    static func apply(
        _ text: String, to target: any TextPasteTarget, allowWholeField: Bool,
        pasteboard: NSPasteboard = .general
    ) async throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextReplacementError.clipboardUnavailable
        }
        try await target.focus()
        switch target.selection {
        case .selected:
            break
        case .none:
            guard allowWholeField else { throw TextReplacementError.selectionRequired }
            try target.checkFocus()
            try target.send(.selectAll)
            // Let the editor handle Select All before it receives Paste.
            try await Task.sleep(for: .milliseconds(80))
        case .unavailable:
            throw TextReplacementError.invalidSelection
        }
        try target.checkFocus()
        try target.send(.paste)
        try? await Task.sleep(for: .milliseconds(100))
    }
}

@MainActor
enum BackgroundTextReplacer {
    static func capture(in application: NSRunningApplication) -> any TextPasteTarget {
        AccessibilityPasteTarget(application: application)
    }

    static func replace(_ text: String, in target: any TextPasteTarget, allowWholeField: Bool) async throws {
        try await TextReplacement.apply(text, to: target, allowWholeField: allowWholeField)
    }
}

@MainActor
private final class AccessibilityPasteTarget: TextPasteTarget {
    let application: NSRunningApplication
    let appElement: AXUIElement
    let window: AXUIElement?
    private var element: AXUIElement?

    init(application: NSRunningApplication) {
        self.application = application
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        self.appElement = appElement
        AXUIElementSetMessagingTimeout(appElement, 0.5)
        // Chromium and Electron build their Accessibility tree on request.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        window = Self.element(kAXFocusedWindowAttribute, from: appElement)
        element = Self.element(kAXFocusedUIElementAttribute, from: appElement)
        if let window { AXUIElementSetMessagingTimeout(window, 0.5) }
        if let element { AXUIElementSetMessagingTimeout(element, 0.5) }
    }

    var selection: TextSelection {
        guard let element else { return .unavailable }
        let selectedText = Self.attribute(kAXSelectedTextAttribute, from: element) as? String
        if selectedText?.isEmpty == false { return .selected }
        if let marker = Self.attribute(kAXSelectedTextMarkerRangeAttribute, from: element),
           CFGetTypeID(marker) == AXTextMarkerRangeGetTypeID() {
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForTextMarkerRangeParameterizedAttribute as CFString, marker, &value
            ) == .success, let text = value as? String else { return .unavailable }
            return text.isEmpty ? .none : .selected
        }
        var range: NSRange?
        if let value = Self.attribute(kAXSelectedTextRangeAttribute, from: element),
           CFGetTypeID(value) == AXValueGetTypeID() {
            let axValue = unsafeDowncast(value, to: AXValue.self)
            var cfRange = CFRange()
            if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &cfRange) {
                range = NSRange(location: cfRange.location, length: cfRange.length)
            }
        }
        return TextSelection.read(
            range: range, selectedText: selectedText
        )
    }

    func focus() async throws {
        guard !application.isTerminated, let window else {
            throw TextReplacementError.noFocusedField
        }
        guard application.activate(),
              AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            throw TextReplacementError.noFocusedField
        }
        var requestedFocus = false
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(25))
            guard !application.isTerminated else { break }
            guard application.isActive,
                  let focusedWindow = Self.attribute(kAXFocusedWindowAttribute, from: appElement),
                  CFEqual(focusedWindow, window) else { continue }
            // URL delivery can activate Floater before the external editor is readable.
            if element == nil {
                element = Self.element(kAXFocusedUIElementAttribute, from: appElement)
                if let element { AXUIElementSetMessagingTimeout(element, 0.5) }
            }
            guard let element else { continue }
            if (try? checkFocus()) != nil {
                try checkEditable(element)
                return
            }
            if !requestedFocus {
                AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                requestedFocus = true
            }
        }
        throw TextReplacementError.noFocusedField
    }

    private func checkEditable(_ element: AXUIElement) throws {
        let role = Self.attribute(kAXRoleAttribute, from: element) as? String
        let subrole = Self.attribute(kAXSubroleAttribute, from: element) as? String
        guard let role, [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              subrole != kAXSecureTextFieldSubrole,
              Self.attribute(kAXEnabledAttribute, from: element) as? Bool != false,
              Self.attribute("AXEditable", from: element) as? Bool != false else {
            throw TextReplacementError.notEditable
        }
        guard Self.isSettable(kAXValueAttribute, on: element) ||
              Self.isSettable(kAXSelectedTextAttribute, on: element) ||
              Self.attribute("AXEditable", from: element) as? Bool == true ||
              Self.attribute(kAXSelectedTextMarkerRangeAttribute, from: element) != nil else {
            throw TextReplacementError.notEditable
        }
    }

    func checkFocus() throws {
        guard !application.isTerminated, application.isActive, let window, let element,
              let focusedWindow = Self.attribute(kAXFocusedWindowAttribute, from: appElement),
              CFEqual(focusedWindow, window),
              let focused = Self.attribute(kAXFocusedUIElementAttribute, from: appElement),
              CFEqual(focused, element) else {
            throw TextReplacementError.noFocusedField
        }
    }

    func send(_ command: PasteCommand) throws {
        try checkFocus()
        let key = CGKeyCode(command == .selectAll ? kVK_ANSI_A : kVK_ANSI_V)
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw TextReplacementError.unsupported
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(application.processIdentifier)
        up.postToPid(application.processIdentifier)
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ name: String, from appElement: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, from: appElement), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func isSettable(_ name: String, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
}
