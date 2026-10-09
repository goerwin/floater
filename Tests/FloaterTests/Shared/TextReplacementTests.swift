import AppKit
import XCTest
@testable import Floater

@MainActor
final class TextReplacementTests: XCTestCase {
    func testReplaceUpdatesOnlySelectionAndSupportsUndo() throws {
        let editor = makeEditor("Before 👋🏽 selected after")
        let window = NSWindow(contentRect: editor.frame, styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        defer { window.close() }
        editor.setSelectedRange((editor.string as NSString).range(of: "👋🏽 selected"))
        try TextReplacement.apply("result", to: NativeTextTarget(editor), allowWholeField: false)
        XCTAssertEqual(editor.string, "Before result after")
        let undoManager = try XCTUnwrap(editor.undoManager)
        undoManager.undo()
        XCTAssertEqual(editor.string, "Before 👋🏽 selected after")
    }

    func testReplaceWithoutSelectionOverwritesWholeFieldWhenEnabled() throws {
        let editor = makeEditor("Original\nfield contents")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        try TextReplacement.apply("New\nresponse", to: NativeTextTarget(editor), allowWholeField: true)
        XCTAssertEqual(editor.string, "New\nresponse")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 12, length: 0))
    }

    func testReplaceWithoutSelectionLeavesFieldUntouchedWhenDisabled() {
        let editor = makeEditor("Original contents")
        editor.setSelectedRange(NSRange(location: 8, length: 0))
        XCTAssertThrowsError(try TextReplacement.apply("result", to: NativeTextTarget(editor), allowWholeField: false)) {
            XCTAssertEqual($0 as? TextReplacementError, .selectionRequired)
        }
        XCTAssertEqual(editor.string, "Original contents")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 8, length: 0))
    }

    func testReadOnlyFieldIsNotChanged() {
        let editor = makeEditor("Read only")
        editor.isEditable = false
        XCTAssertThrowsError(try TextReplacement.apply("result", to: NativeTextTarget(editor), allowWholeField: true)) {
            XCTAssertEqual($0 as? TextReplacementError, .notEditable)
        }
        XCTAssertEqual(editor.string, "Read only")
    }

    func testInvalidSelectionIsRejected() {
        let target = InvalidTextTarget()
        XCTAssertThrowsError(try TextReplacement.apply("result", to: target, allowWholeField: true)) {
            XCTAssertEqual($0 as? TextReplacementError, .invalidSelection)
        }
        XCTAssertFalse(target.wasWritten)
    }

    func testConfigurationPersistsAcrossInstances() throws {
        let suite = "FloaterTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.replaceWholeFieldWhenUnselected)
        settings.replaceWholeFieldWhenUnselected = false
        XCTAssertFalse(AppSettings(defaults: defaults).replaceWholeFieldWhenUnselected)
        settings.replaceWholeFieldWhenUnselected = true
        XCTAssertTrue(AppSettings(defaults: defaults).replaceWholeFieldWhenUnselected)
    }

    private func makeEditor(_ text: String) -> NSTextView {
        _ = NSApplication.shared
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        editor.isRichText = false
        editor.allowsUndo = true
        editor.string = text
        return editor
    }
}

@MainActor
private struct NativeTextTarget: EditableTextTarget {
    let editor: NSTextView
    init(_ editor: NSTextView) { self.editor = editor }
    var text: String { editor.string }
    var selectedRange: NSRange { editor.selectedRange() }
    var isEditable: Bool { editor.isEditable }
    func replaceCharacters(in range: NSRange, with replacement: String) throws {
        editor.insertText(replacement, replacementRange: range)
    }
}

@MainActor
private final class InvalidTextTarget: EditableTextTarget {
    let text = "Text"
    let selectedRange = NSRange(location: Int.max, length: Int.max)
    let isEditable = true
    var wasWritten = false
    func replaceCharacters(in range: NSRange, with replacement: String) throws { wasWritten = true }
}
