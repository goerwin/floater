import Combine
import Foundation
import FloaterCore

@MainActor
final class FloaterState: ObservableObject {
    enum Screen { case newRequest, history, results }

    @Published private(set) var screen: Screen = .newRequest
    @Published var prompt = ""
    @Published var title: String?
    @Published var isPromptExpanded = false
    @Published private(set) var conversation: HistoryEntry?
    @Published private(set) var resultID = UUID()
    @Published private(set) var isGenerating = false
    @Published private(set) var isCompacting = false
    @Published private(set) var preparationMessage = "Generating response…"
    @Published private(set) var errorMessage: String?
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var canReplace = false
    @Published var followUp = "" {
        didSet {
            guard conversation != nil, conversation?.draft != followUp else { return }
            conversation?.draft = followUp
            conversation?.updatedAt = .now
            scheduleSave()
        }
    }

    private struct ResultState {
        let conversation: HistoryEntry?
        let errorMessage: String?
        let actionErrorMessage: String?
    }

    private struct RequestState {
        let result: ResultState
        let editingResult: ResultState?
        let prompt: String
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
    private var saveTask: Task<Void, Never>?

    var currentRequest: PromptRequest? { conversation?.request }
    var messages: [ChatMessage] { conversation?.messages ?? [] }
    var response: String { conversation?.response ?? "" }
    var responseForActions: String {
        messages.last(where: { $0.role == .assistant && $0.status == .complete })?.content ?? ""
    }
    var canSubmit: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canSend: Bool { !isGenerating && !followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canUseResponse: Bool { !responseForActions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canRetry: Bool {
        !isGenerating && messages.last?.role == .assistant && [.failed, .stopped].contains(messages.last?.status)
    }
    var canCompact: Bool { !isGenerating && !messages.isEmpty }
    var persistenceError: String? { historyStore?.errorMessage }

    var windowTitle: String {
        if screen == .history { return "History" }
        let title = currentRequest?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.flatMap { $0.isEmpty ? nil : $0 } ?? "Floater"
    }

    private var resultState: ResultState {
        ResultState(conversation: conversation, errorMessage: errorMessage, actionErrorMessage: actionErrorMessage)
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
        historySession = nil
        prompt = ""
        title = nil
        showRequest()
    }

    func requestForSubmission() -> PromptRequest? {
        guard canSubmit else { return nil }
        let request = PromptRequest(prompt: prompt, title: title)
        title = nil
        return request
    }

    func beginEditing() {
        guard let request = currentRequest else { return }
        stop()
        let result = resultState
        clearResult()
        editingResult = result
        prompt = request.prompt
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
        if entry.id != conversation?.id { stop() }
        if historySession?.returnsToRequest == true, historySession?.originalRequest == nil {
            historySession?.originalRequest = RequestState(
                result: resultState, editingResult: editingResult,
                prompt: prompt, title: title, isPromptExpanded: isPromptExpanded
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
                title = original.title
                isPromptExpanded = original.isPromptExpanded
            }
            showRequest()
            return true
        }
        // Escape in a conversation always hides it, including when opened from History.
        historySession = nil
        title = nil
        return false
    }

    func presentFailure(_ request: PromptRequest, message: String) {
        clearResult()
        historySession = nil
        conversation = HistoryEntry(request: request)
        errorMessage = message
        screen = .results
    }

    func start(_ request: PromptRequest) {
        clearResult()
        historySession = nil
        conversation = HistoryEntry(request: request)
        screen = .results
        generateReply()
    }

    func sendFollowUp() {
        guard canSend, conversation != nil else { return }
        conversation?.messages.append(ChatMessage(role: .user, content: followUp))
        followUp = ""
        generateReply()
    }

    func retry() {
        guard canRetry else { return }
        conversation?.messages.removeLast()
        generateReply()
    }

    func stop() {
        activeGenerationID = nil
        generationTask?.cancel()
        generationTask = nil
        if isGenerating, !isCompacting, conversation?.messages.last?.status == .generating,
           let index = conversation?.messages.indices.last {
            conversation?.messages[index].status = .stopped
            conversation?.updatedAt = .now
        }
        isGenerating = false
        isCompacting = false
        persist()
    }

    func compact() {
        guard canCompact, let original = conversation else { return }
        actionErrorMessage = nil
        let generationID = UUID()
        activeGenerationID = generationID
        isGenerating = true
        isCompacting = true
        preparationMessage = "Compacting conversation…"
        let provider = self.provider
        generationTask = Task { [weak self] in
            do {
                let summary = try await ConversationCompactor.compact(original, using: provider)
                guard let self, self.activeGenerationID == generationID, !Task.isCancelled else { return }
                self.conversation?.summary = summary
                self.conversation?.updatedAt = .now
                self.isGenerating = false
                self.isCompacting = false
                self.activeGenerationID = nil
                self.generationTask = nil
                self.persist()
            } catch {
                guard let self, self.activeGenerationID == generationID else { return }
                self.isGenerating = false
                self.isCompacting = false
                self.activeGenerationID = nil
                self.generationTask = nil
                self.actionErrorMessage = "Compaction didn't finish. Your conversation is unchanged. \(error.localizedDescription)"
            }
        }
    }

    private func generateReply() {
        guard let context = conversation?.contextMessages(), !context.isEmpty else { return }
        let generationID = UUID()
        activeGenerationID = generationID
        conversation?.messages.append(ChatMessage(role: .assistant, content: "", status: .generating))
        conversation?.updatedAt = .now
        errorMessage = nil
        actionErrorMessage = nil
        isGenerating = true
        preparationMessage = provider.preparationMessage
        persist()
        let provider = self.provider
        generationTask = Task { [weak self] in
            do {
                try await provider.generate(messages: context) { [weak self] partial in
                    guard let self, self.activeGenerationID == generationID, let index = self.conversation?.messages.indices.last else { return }
                    self.conversation?.messages[index].content = partial
                    self.scheduleSave()
                }
                guard let self, self.activeGenerationID == generationID, !Task.isCancelled else { return }
                guard !self.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ChatGenerationError.emptyResponse
                }
                self.finishReply(status: .complete)
            } catch is CancellationError {
                guard let self, self.activeGenerationID == generationID else { return }
                self.finishReply(status: .stopped)
            } catch {
                guard let self, self.activeGenerationID == generationID, !Task.isCancelled else { return }
                self.finishReply(status: .failed, error: error.localizedDescription)
            }
        }
    }

    private func finishReply(status: ChatMessage.Status, error: String? = nil) {
        if let index = conversation?.messages.indices.last {
            conversation?.messages[index].status = status
            conversation?.messages[index].error = error
        }
        conversation?.updatedAt = .now
        errorMessage = error
        isGenerating = false
        activeGenerationID = nil
        generationTask = nil
        persist()
    }

    func restore(_ entry: HistoryEntry) {
        if conversation?.id == entry.id { screen = .results; return }
        restore(ResultState(conversation: entry, errorMessage: entry.messages.last?.error, actionErrorMessage: nil))
    }

    func restore(request: PromptRequest?, response: String, errorMessage: String? = nil) {
        var entry = request.map { HistoryEntry(request: $0, response: response) }
        if errorMessage != nil, let index = entry?.messages.indices.last {
            entry?.messages[index].status = .failed
            entry?.messages[index].error = errorMessage
        }
        restore(ResultState(conversation: entry, errorMessage: errorMessage, actionErrorMessage: nil))
    }

    private func restore(_ result: ResultState) {
        clearResult()
        conversation = result.conversation
        followUp = result.conversation?.draft ?? ""
        errorMessage = result.errorMessage
        actionErrorMessage = result.actionErrorMessage
        screen = currentRequest == nil ? .newRequest : .results
    }

    private func clearResult() {
        stop()
        resultID = UUID()
        conversation = nil
        followUp = ""
        errorMessage = nil
        actionErrorMessage = nil
        editingResult = nil
        isPromptExpanded = false
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            self?.persist()
        }
    }

    private func persist() {
        saveTask?.cancel()
        saveTask = nil
        if let conversation { historyStore?.upsert(conversation) }
    }
}
