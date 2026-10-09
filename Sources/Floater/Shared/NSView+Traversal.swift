import AppKit

extension NSView {
    func firstDescendant(where predicate: (NSView) -> Bool) -> NSView? {
        if predicate(self) { return self }
        for child in subviews {
            if let match = child.firstDescendant(where: predicate) { return match }
        }
        return nil
    }
}
