import AppKit
import Combine
import FloaterCore

@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var isChecking = false

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                guard let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                      let current = ReleaseVersion(value) else {
                    throw URLError(.cannotParseResponse)
                }
                let latest = try await latestVersion()
                showResult(current: current, latest: latest)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "Please try again later. \(error.localizedDescription)"
                alert.addButton(withTitle: "OK")
                present(alert)
            }
        }
    }

    private func latestVersion() async throws -> ReleaseVersion {
        let url = URL(string: "https://api.github.com/repos/goerwin/floater/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decoder.decode(Release.self, from: data)
        guard let version = ReleaseVersion(release.tagName) else {
            throw URLError(.cannotParseResponse)
        }
        return version
    }

    private func showResult(current: ReleaseVersion, latest: ReleaseVersion) {
        let hasUpdate = latest > current
        let alert = NSAlert()
        if hasUpdate {
            alert.messageText = "A new version of Floater is available"
            alert.informativeText = "Floater \(latest) is available. You're using \(current)."
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Not Now")
        } else {
            alert.messageText = "You're up to date"
            alert.informativeText = "Floater \(current) is the latest version available for you."
            alert.addButton(withTitle: "OK")
        }
        if present(alert) == .alertFirstButtonReturn, hasUpdate,
           let url = URL(string: "https://github.com/goerwin/floater/releases/tag/v\(latest)") {
            NSWorkspace.shared.open(url)
        }
    }

    @discardableResult
    private func present(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    private struct Release: Decodable {
        let tagName: String
    }
}
