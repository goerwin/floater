import AppKit
import ApplicationServices

@MainActor
protocol EditableTextTarget {
    var text: String { get }
    var selectedRange: NSRange { get }
    var isEditable: Bool { get }
    func replaceCharacters(in range: NSRange, with replacement: String) throws
}

enum TextReplacementError: LocalizedError {
    case noFocusedField
    case notEditable
    case selectionRequired
    case invalidSelection
    case changed
    case unsupported

    var errorDescription: String? {
        switch self {
        case .noFocusedField:
            "Focus an editable text field in the previous app, then try Replace again."
        case .notEditable:
            "The focused field cannot be edited. Focus an editable text field and try again."
        case .selectionRequired:
            "Select text in the previous app, or enable Configuration > Replace entire focused field."
        case .invalidSelection:
            "The previous app did not provide a valid text selection. Select text and try again."
        case .changed:
            "The text changed before it could be replaced. Try Replace again."
        case .unsupported:
            "The previous app does not support replacing this field through Accessibility."
        }
    }
}

@MainActor
enum TextReplacement {
    static func apply(_ replacement: String, to target: any EditableTextTarget, allowWholeField: Bool) throws {
        guard target.isEditable else { throw TextReplacementError.notEditable }
        let length = (target.text as NSString).length
        let selection = target.selectedRange
        guard selection.location >= 0, selection.location <= length,
              selection.length >= 0, selection.length <= length - selection.location else {
            throw TextReplacementError.invalidSelection
        }
        let range: NSRange
        if selection.length > 0 {
            range = selection
        } else {
            guard allowWholeField else { throw TextReplacementError.selectionRequired }
            range = NSRange(location: 0, length: length)
        }
        try target.replaceCharacters(in: range, with: replacement)
    }
}

@MainActor
enum BackgroundTextReplacer {
    static func replace(_ text: String, in application: NSRunningApplication, allowWholeField: Bool) throws {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw TextReplacementError.noFocusedField
        }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        let target = try AccessibilityTextTarget(element: element)
        try TextReplacement.apply(text, to: target, allowWholeField: allowWholeField)
    }
}

@MainActor
private struct AccessibilityTextTarget: EditableTextTarget {
    let element: AXUIElement
    let text: String
    let selectedRange: NSRange
    let isEditable: Bool
    private let canSetValue: Bool
    private let canSetSelection: Bool
    private let canSetSelectedText: Bool

    init(element: AXUIElement) throws {
        self.element = element
        let role = Self.attribute(kAXRoleAttribute, from: element) as? String
        let subrole = Self.attribute(kAXSubroleAttribute, from: element) as? String
        guard let role, [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              subrole != kAXSecureTextFieldSubrole,
              Self.attribute(kAXEnabledAttribute, from: element) as? Bool != false else {
            throw TextReplacementError.notEditable
        }
        guard let text = Self.attribute(kAXValueAttribute, from: element) as? String else {
            throw TextReplacementError.unsupported
        }
        self.text = text
        guard let selection = Self.attribute(kAXSelectedTextRangeAttribute, from: element),
              CFGetTypeID(selection) == AXValueGetTypeID() else {
            throw TextReplacementError.invalidSelection
        }
        let selectionValue = unsafeDowncast(selection, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(selectionValue) == .cfRange,
              AXValueGetValue(selectionValue, .cfRange, &range) else {
            throw TextReplacementError.invalidSelection
        }
        selectedRange = NSRange(location: range.location, length: range.length)
        canSetValue = Self.isSettable(kAXValueAttribute, on: element)
        canSetSelection = Self.isSettable(kAXSelectedTextRangeAttribute, on: element)
        canSetSelectedText = Self.isSettable(kAXSelectedTextAttribute, on: element)
        isEditable = canSetValue || canSetSelectedText
    }

    func replaceCharacters(in range: NSRange, with replacement: String) throws {
        guard Self.attribute(kAXValueAttribute, from: element) as? String == text else {
            throw TextReplacementError.changed
        }
        if canSetSelectedText, range == selectedRange || canSetSelection {
            if range != selectedRange { try setSelection(range) }
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement as CFString)
            if result == .success { return }
            if range != selectedRange { try setSelection(selectedRange) }
        }
        guard canSetValue else { throw TextReplacementError.unsupported }
        guard Self.attribute(kAXValueAttribute, from: element) as? String == text else {
            throw TextReplacementError.changed
        }
        let updated = (text as NSString).replacingCharacters(in: range, with: replacement)
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, updated as CFString) == .success else {
            throw TextReplacementError.unsupported
        }
        if canSetSelection {
            try? setSelection(NSRange(location: range.location + (replacement as NSString).length, length: 0))
        }
    }

    private func setSelection(_ range: NSRange) throws {
        var range = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &range),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw TextReplacementError.unsupported
        }
    }

    private static func attribute(_ name: String, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func isSettable(_ name: String, on element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
}
