import Combine
import Foundation
import FloaterCore

@MainActor
final class FloaterViewModel: ObservableObject {
    @Published private(set) var currentRequest: PromptRequest?
    @Published private(set) var response = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var canReplace = false
    private(set) var editingResponse: ResponseState?

    struct ResponseState {
        let request: PromptRequest
        let response: String
        let errorMessage: String?
        let actionErrorMessage: String?
    }

    private let provider: any AIProvider
    private let historyStore: HistoryStore?
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?

    init(provider: any AIProvider, historyStore: HistoryStore? = nil) {
        self.provider = provider
        self.historyStore = historyStore
    }

    func setCanReplace(_ value: Bool) {
        canReplace = value
    }

    func setActionError(_ message: String?) {
        actionErrorMessage = message
    }

    func showComposer() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        currentRequest = nil
        response = ""
        isGenerating = false
        errorMessage = nil
        actionErrorMessage = nil
        editingResponse = nil
    }

    func beginEditing() {
        guard let request = currentRequest else { return }
        let state = ResponseState(
            request: request, response: response,
            errorMessage: errorMessage, actionErrorMessage: actionErrorMessage
        )
        showComposer()
        editingResponse = state
    }

    @discardableResult
    func cancelEditing() -> Bool {
        guard let state = editingResponse else { return false }
        restore(request: state.request, response: state.response, errorMessage: state.errorMessage)
        actionErrorMessage = state.actionErrorMessage
        return true
    }

    func start(_ request: PromptRequest) {
        generationTask?.cancel()
        editingResponse = nil

        let generationID = UUID()
        activeGenerationID = generationID
        currentRequest = request
        response = ""
        errorMessage = nil
        actionErrorMessage = nil
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
                self.historyStore?.record(request, response: self.response)
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

    func restore(_ entry: HistoryEntry) {
        restore(request: entry.request, response: entry.response)
    }

    func restore(
        request: PromptRequest?, response: String, errorMessage: String? = nil,
        editingResponse: ResponseState? = nil
    ) {
        showComposer()
        currentRequest = request
        self.response = response
        self.errorMessage = errorMessage
        self.editingResponse = editingResponse
    }
}
