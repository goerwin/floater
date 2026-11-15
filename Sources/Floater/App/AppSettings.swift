import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    private static let replaceWholeFieldKey = "replaceWholeFieldWhenUnselected"
    private static let selectedModelKey = "selectedModel"

    @Published var selectedModel: AIModel {
        didSet { defaults.set(selectedModel.rawValue, forKey: Self.selectedModelKey) }
    }

    @Published var replaceWholeFieldWhenUnselected: Bool {
        didSet { defaults.set(replaceWholeFieldWhenUnselected, forKey: Self.replaceWholeFieldKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedModel = defaults.string(forKey: Self.selectedModelKey).flatMap(AIModel.init(rawValue:)) ?? .gemma4E4B
        replaceWholeFieldWhenUnselected = defaults.object(forKey: Self.replaceWholeFieldKey) as? Bool ?? true
    }
}
