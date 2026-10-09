import AppKit
import ApplicationServices
import Combine

@MainActor
final class AccessibilityAccess: ObservableObject {
    @Published private(set) var isGranted: Bool
    private let isTrusted: () -> Bool
    private let requestAccess: () -> Void

    init(
        isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        requestAccess: @escaping () -> Void = {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    ) {
        self.isTrusted = isTrusted
        self.requestAccess = requestAccess
        isGranted = isTrusted()
    }

    func refresh() {
        let granted = isTrusted()
        if isGranted != granted { isGranted = granted }
    }

    func request() {
        requestAccess()
        refresh()
    }
}
