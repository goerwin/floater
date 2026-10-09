import Combine
import Foundation
import FloaterCore

@MainActor
final class FloaterState: ObservableObject {
    enum Screen {
        case newRequest, history, results
    }

    @Published private(set) var screen: Screen = .newRequest
    @Published var prompt = ""
    @Published var input = ""
    @Published var title: String?
    @Published var isPromptExpanded = false
    @Published private(set) var currentRequest: PromptRequest?
    @Published private(set) var response = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var canReplace = false

    private struct ResultState {
        let request: PromptRequest?
        let response: String
        let errorMessage: String?
        let actionErrorMessage: String?
    }

    private struct RequestState {
        let result: ResultState
        let editingResult: ResultState?
        let prompt: String
        let input: String
        let title: String?
        let isPromptExpanded: Bool
    }

    private struct HistorySession {
        let returnsToRequest: Bool
        var originalRequest: RequestState?
    }

    private var editingResult: ResultState?
    private var historySession: HistorySession?
    private let provider: any AIProvider
    private let historyStore: HistoryStore?
    private var generationTask: Task<Void, Never>?
    private var activeGenerationID: UUID?

    var canSubmit: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var windowTitle: String {
        if screen == .history { return "History" }
        let title = currentRequest?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? "Floater"
    }

    private var resultState: ResultState {
        ResultState(request: currentRequest, response: response, errorMessage: errorMessage, actionErrorMessage: actionErrorMessage)
    }

    init(provider: any AIProvider, historyStore: HistoryStore? = nil) {
        self.provider = provider
        self.historyStore = historyStore
    }

    func setCanReplace(_ value: Bool) { canReplace = value }
    func setActionError(_ message: String?) { actionErrorMessage = message }

    func showRequest() {
        historySession = nil
        screen = currentRequest == nil ? .newRequest : .results
    }

    func showNewRequest() {
        clearResult()
        prompt = ""
        input = ""
        title = nil
        showRequest()
    }

    func requestForSubmission() -> PromptRequest? {
        guard canSubmit else { return nil }
        let request = PromptRequest(prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines), input: input, title: title)
        title = nil
        return request
    }

    func beginEditing() {
        guard let request = currentRequest else { return }
        let result = resultState
        clearResult()
        editingResult = result
        prompt = request.prompt
        input = request.input
        title = request.title
        screen = .newRequest
    }

    @discardableResult
    func cancelEditing() -> Bool {
        guard let result = editingResult else { return false }
        restore(result)
        return true
    }

    func showHistory(returnToRequest: Bool) {
        if historySession == nil { historySession = HistorySession(returnsToRequest: returnToRequest) }
        screen = .history
    }

    func openHistoryEntry(_ entry: HistoryEntry) {
        if historySession?.returnsToRequest == true, historySession?.originalRequest == nil {
            historySession?.originalRequest = RequestState(
                result: resultState, editingResult: editingResult,
                prompt: prompt, input: input, title: title, isPromptExpanded: isPromptExpanded
            )
        }
        restore(entry)
    }

    @discardableResult
    func dismiss() -> Bool {
        if screen != .history, cancelEditing() { return true }
        if screen == .history {
            guard let session = historySession, session.returnsToRequest else { return false }
            if let original = session.originalRequest {
                restore(original.result)
                editingResult = original.editingResult
                prompt = original.prompt
                input = original.input
                title = original.title
                isPromptExpanded = original.isPromptExpanded
            }
            showRequest()
            return true
        }
        if historySession != nil {
            screen = .history
            return true
        }
        title = nil
        return false
    }

    func presentFailure(_ request: PromptRequest, message: String) {
        clearResult()
        currentRequest = request
        errorMessage = message
        screen = .results
    }

    func start(_ request: PromptRequest) {
        clearResult()
        let generationID = UUID()
        activeGenerationID = generationID
        currentRequest = request
        screen = .results
        isGenerating = true

        let provider = self.provider
        generationTask = Task { [weak self] in
            do {
                try await provider.generate(request) { [weak self] partialResponse in
                    guard let self, self.activeGenerationID == generationID else { return }
                    self.response = partialResponse
                }
                guard let self, self.activeGenerationID == generationID, !Task.isCancelled else { return }
                self.isGenerating = false
                self.historyStore?.record(request, response: self.response)
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.activeGenerationID == generationID, !Task.isCancelled else { return }
                self.isGenerating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func restore(_ entry: HistoryEntry) {
        restore(request: entry.request, response: entry.response)
    }

    func restore(request: PromptRequest?, response: String, errorMessage: String? = nil) {
        restore(ResultState(request: request, response: response, errorMessage: errorMessage, actionErrorMessage: nil))
    }

    private func restore(_ result: ResultState) {
        clearResult()
        currentRequest = result.request
        response = result.response
        errorMessage = result.errorMessage
        actionErrorMessage = result.actionErrorMessage
        screen = currentRequest == nil ? .newRequest : .results
    }

    private func clearResult() {
        generationTask?.cancel()
        generationTask = nil
        activeGenerationID = nil
        currentRequest = nil
        response = ""
        isGenerating = false
        errorMessage = nil
        actionErrorMessage = nil
        editingResult = nil
        isPromptExpanded = false
    }
}
