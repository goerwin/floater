import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    private static let replaceWholeFieldKey = "replaceWholeFieldWhenUnselected"

    @Published var replaceWholeFieldWhenUnselected: Bool {
        didSet { defaults.set(replaceWholeFieldWhenUnselected, forKey: Self.replaceWholeFieldKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        replaceWholeFieldWhenUnselected = defaults.object(forKey: Self.replaceWholeFieldKey) as? Bool ?? true
    }
}
