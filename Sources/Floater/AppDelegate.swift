import AppKit
import Carbon.HIToolbox
import FloaterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    let historyStore = HistoryStore()
    let settings = AppSettings()
    let accessibility = AccessibilityAccess()
    private lazy var viewModel = FloaterViewModel(
        provider: FoundationModelsProvider(), historyStore: historyStore
    )
    private lazy var panelController = FloatingPanelController(
        viewModel: viewModel, historyStore: historyStore, settings: settings, accessibility: accessibility
    )
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?

    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        NSApp.setActivationPolicy(.accessory)
        observeExternalApplications()
        registerURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true
        if let request = developmentRequest(from: arguments) {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self else { return }
                self.panelController.handle(request, fallbackApplication: self.activeExternalApplication)
            }
        } else if arguments.contains("--show-composer") || isDefaultLaunch {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.showComposer()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showComposer()
        return false
    }

    func showComposer() {
        panelController.showComposer(previousApplication: activeExternalApplication)
    }

    func openWindow() {
        panelController.open(previousApplication: activeExternalApplication)
    }

    func openHistoryEntry(_ entry: HistoryEntry) {
        panelController.openHistoryEntry(entry)
    }

    func showHistory() {
        panelController.showHistory(previousApplication: activeExternalApplication)
    }

    private var activeExternalApplication: NSRunningApplication? {
        if let lastExternalApplication, !lastExternalApplication.isTerminated {
            return lastExternalApplication
        }
        return nil
    }

    private func developmentRequest(from arguments: [String]) -> PromptRequest? {
        guard let prompt = argumentValue(after: "--prompt", in: arguments),
              !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return PromptRequest(
            prompt: prompt,
            input: argumentValue(after: "--input", in: arguments) ?? "",
            title: argumentValue(after: "--title", in: arguments)
        )
    }

    private func argumentValue(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    private func observeExternalApplications() {
        if let application = NSWorkspace.shared.frontmostApplication,
           application.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApplication = application
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let processID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier else {
                return
            }

            Task { @MainActor [weak self] in
                self?.accessibility.refresh()
                guard let application = NSRunningApplication(processIdentifier: processID),
                      application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self?.lastExternalApplication = application
            }
        }
    }

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else { return }
        panelController.handle(url, fallbackApplication: activeExternalApplication)
    }
}
