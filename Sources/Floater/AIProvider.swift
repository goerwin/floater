import FloaterCore

@MainActor
protocol AIProvider {
    func generate(
        _ request: PromptRequest,
        onUpdate: @MainActor (String) -> Void
    ) async throws
}
