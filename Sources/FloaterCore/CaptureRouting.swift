import Foundation

public struct TargetCandidate: Equatable, Sendable {
    public let name: String?
    public let bundleIdentifier: String?
    public let isRunning: Bool

    public init(name: String?, bundleIdentifier: String?, isRunning: Bool) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.isRunning = isRunning
    }
}

public enum SelectedTarget: Equatable, Sendable {
    case previous
    case recent(Int)
}

public enum TargetRouting {
    public static let excludedBundleIdentifiers: Set<String> = [
        "com.apple.UserNotificationCenter"
    ]

    public static func select(
        previous: TargetCandidate?,
        recent: [TargetCandidate],
        ignoredBundleIdentifiers: [String],
        ownBundleIdentifier: String?
    ) -> SelectedTarget? {
        if let previous, isUsable(previous, ignored: ignoredBundleIdentifiers, own: ownBundleIdentifier) {
            return .previous
        }
        for (index, app) in recent.prefix(2).enumerated() where isUsable(
            app, ignored: ignoredBundleIdentifiers, own: ownBundleIdentifier
        ) {
            return .recent(index)
        }
        return nil
    }

    public static func considered(
        previous: TargetCandidate?,
        recent: [TargetCandidate],
        ownBundleIdentifier: String?
    ) -> [TargetCandidate] {
        var result: [TargetCandidate] = []
        func append(_ app: TargetCandidate) {
            guard isReportable(app, own: ownBundleIdentifier) else { return }
            if let bundleIdentifier = app.bundleIdentifier,
               result.contains(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return
            }
            result.append(app)
        }
        if let previous { append(previous) }
        for app in recent.prefix(2) { append(app) }
        return result
    }

    private static func isUsable(
        _ app: TargetCandidate, ignored: [String], own: String?
    ) -> Bool {
        guard app.isRunning else { return false }
        if let bundleIdentifier = app.bundleIdentifier {
            if excludedBundleIdentifiers.contains(bundleIdentifier) { return false }
            if bundleIdentifier == own { return false }
            if ignored.contains(bundleIdentifier) { return false }
        }
        return true
    }

    private static func isReportable(_ app: TargetCandidate, own: String?) -> Bool {
        if let bundleIdentifier = app.bundleIdentifier {
            if excludedBundleIdentifiers.contains(bundleIdentifier) { return false }
            if bundleIdentifier == own { return false }
        }
        return true
    }
}

public enum RecentAppMemory {
    public static func remember<ID: Equatable>(
        _ app: ID, recent: [ID], isOwnApp: Bool, limit: Int = 2
    ) -> [ID] {
        guard !isOwnApp else { return recent }
        var updated = recent.filter { $0 != app }
        updated.insert(app, at: 0)
        if updated.count > limit { updated.removeLast(updated.count - limit) }
        return updated
    }
}

public enum FieldRead: Equatable, Sendable {
    case failed
    case unreadable
    case empty
    case selection(String)
    case field(String)
}

public enum LineExpansion {
    public static func shouldExpand(
        elementFound: Bool,
        isSecure: Bool,
        role: String?,
        selectedText: String?,
        selectionUnreadable: Bool
    ) -> Bool {
        guard elementFound, !isSecure, roleAllowsExpansion(role), !selectionUnreadable else { return false }
        guard let selectedText else { return true }
        return selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public static func roleAllowsExpansion(_ role: String?) -> Bool {
        role == "AXTextField" || role == "AXTextArea" || role == "AXComboBox"
    }
}

public enum FieldTextChoice {
    public static func interpret(
        elementFound: Bool,
        isSecure: Bool,
        selectedText: String?,
        fieldValue: String?,
        selectionUnreadable: Bool = false
    ) -> FieldRead {
        guard elementFound else { return .failed }
        if isSecure { return .unreadable }
        if let selectedText, hasContent(selectedText) { return .selection(selectedText) }
        if selectionUnreadable { return .failed }
        if let fieldValue, hasContent(fieldValue) { return .field(fieldValue) }
        if fieldValue != nil { return .empty }
        return .failed
    }

    private static func hasContent(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

public enum CaptureMessages {
    public static func noApplication(ignoredAny: Bool, considered: [TargetCandidate]) -> String {
        let list = considered.compactMap(label).joined(separator: ", ")
        if ignoredAny {
            guard !list.isEmpty else {
                return "Floater could not find the app behind the ignored ones. Switch to that app and try again."
            }
            return "Floater could not find the app behind the ignored ones: \(list). Switch to that app and try again."
        }
        guard !list.isEmpty else {
            return "Floater could not find an app to use. Switch to that app and try again."
        }
        return "Floater could not find an app to use: \(list). Switch to that app and try again."
    }

    public static func accessibility(for app: TargetCandidate) -> String {
        withSkipHint(
            "Allow Floater in System Settings > Privacy & Security > Accessibility, then try again.",
            bundleIdentifier: app.bundleIdentifier
        )
    }

    public static func emptyField(for app: TargetCandidate) -> String {
        withSkipHint(
            "Select some text, or focus a field that has text.",
            bundleIdentifier: app.bundleIdentifier
        )
    }

    public static func unreadableField(for app: TargetCandidate) -> String {
        withSkipHint(
            "Floater could not read the focused field.",
            bundleIdentifier: app.bundleIdentifier
        )
    }

    private static func withSkipHint(_ message: String, bundleIdentifier: String?) -> String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return message }
        return "\(message) To skip it, pass \(bundleIdentifier) to --ignore."
    }

    private static func label(for app: TargetCandidate) -> String? {
        let name = app.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleIdentifier = app.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name?.isEmpty == false ? name : nil
        let identifier = bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
        switch (displayName, identifier) {
        case let (displayName?, identifier?):
            return "\(displayName) (\(identifier))"
        case let (displayName?, nil):
            return displayName
        case let (nil, identifier?):
            return identifier
        case (nil, nil):
            return nil
        }
    }
}
