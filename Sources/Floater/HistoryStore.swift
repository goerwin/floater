import Combine
import Foundation
import FloaterCore

@MainActor
final class HistoryStore: ObservableObject {
    static let limit = 100

    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var errorMessage: String?

    private let fileURL: URL?
    private var loadFailed = false

    init(fileURL: URL? = HistoryStore.defaultFileURL) {
        self.fileURL = fileURL
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            entries = Array(try JSONDecoder().decode([HistoryEntry].self, from: data).prefix(Self.limit))
        } catch {
            loadFailed = true
            errorMessage = "History couldn't be loaded. Clear history to start again. \(error.localizedDescription)"
        }
    }

    func record(_ request: PromptRequest, response: String) {
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !loadFailed else { return }
        let entry = HistoryEntry(request: request, response: response)
        save(Array(([entry] + entries).prefix(Self.limit)))
    }

    func delete(_ id: UUID) {
        guard !loadFailed else { return }
        save(entries.filter { $0.id != id })
    }

    func clear() {
        if save([]) {
            loadFailed = false
        }
    }

    @discardableResult
    private func save(_ updatedEntries: [HistoryEntry]) -> Bool {
        do {
            if let fileURL {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let data = try JSONEncoder().encode(updatedEntries)
                try data.write(to: fileURL, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
            entries = updatedEntries
            errorMessage = nil
            return true
        } catch {
            errorMessage = "History couldn't be saved. \(error.localizedDescription)"
            return false
        }
    }

    private static var defaultFileURL: URL {
        if let path = ProcessInfo.processInfo.environment["FLOATER_HISTORY_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return URL.applicationSupportDirectory
            .appendingPathComponent("Floater", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
