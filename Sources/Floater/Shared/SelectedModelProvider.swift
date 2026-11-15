import FloaterCore

@MainActor
final class SelectedModelProvider: AIProvider {
    private let settings: AppSettings
    private let apple: any AIProvider
    private let gemma: any AIProvider

    var preparationMessage: String { provider.preparationMessage }
    var compactionChunkSize: Int { provider.compactionChunkSize }

    private var provider: any AIProvider {
        switch settings.selectedModel {
        case .appleIntelligence: apple
        case .gemma4E4B: gemma
        }
    }

    init(
        settings: AppSettings,
        apple: any AIProvider = FoundationModelsProvider(),
        gemma: any AIProvider = LlamaCPPProvider()
    ) {
        self.settings = settings
        self.apple = apple
        self.gemma = gemma
    }

    func generate(messages: [ChatMessage], onUpdate: @MainActor (String) -> Void) async throws {
        let provider = self.provider
        try await provider.generate(messages: messages, onUpdate: onUpdate)
    }
}
