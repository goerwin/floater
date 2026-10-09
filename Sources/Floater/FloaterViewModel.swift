import Combine
import Foundation
import FloaterCore

@MainActor
final class FloaterViewModel: ObservableObject {
    @Published private(set) var currentRequest: PromptRequest?
    @Published private(set) var response = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canReplace = false

    private let provider: any AIProvider
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?

    init(provider: any AIProvider) {
        self.provider = provider
    }

    func setCanReplace(_ value: Bool) {
        canReplace = value
    }

    func showComposer() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        currentRequest = nil
        response = ""
        isGenerating = false
        errorMessage = nil
    }

    func start(_ request: PromptRequest) {
        generationTask?.cancel()

        let generationID = UUID()
        activeGenerationID = generationID
        currentRequest = request
        response = ""
        errorMessage = nil
        isGenerating = true

        let provider = self.provider
        generationTask = Task { [weak self] in
            do {
                try await provider.generate(request) { [weak self] partialResponse in
                    guard let self, self.activeGenerationID == generationID else { return }
                    self.response = partialResponse
                }

                guard let self, self.activeGenerationID == generationID,
                      !Task.isCancelled else { return }
                self.isGenerating = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeGenerationID == generationID,
                      !Task.isCancelled else { return }
                self.isGenerating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }
}
