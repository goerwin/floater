import AppKit
import Carbon.HIToolbox
import FloaterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let historyStore = HistoryStore()
    let settings = AppSettings()
    let accessibility = AccessibilityAccess()
    private lazy var state = FloaterState(
        provider: FoundationModelsProvider(), historyStore: historyStore
    )
    private lazy var panelController = FloatingPanelController(
        state: state, historyStore: historyStore, settings: settings, accessibility: accessibility
    )
    private var activationObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?
    private var recentExternalApplications: [NSRunningApplication] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
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
        } else if (arguments.contains("--show-new-request") || arguments.contains("--show-composer")) || isDefaultLaunch {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.showNewRequest()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showNewRequest()
        return false
    }

    func showNewRequest() {
        panelController.showNewRequest(previousApplication: activeExternalApplication)
    }

    func openWindow() {
        panelController.open(previousApplication: activeExternalApplication)
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
        if let application = NSWorkspace.shared.frontmostApplication {
            rememberExternalApplication(application)
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
                guard let application = NSRunningApplication(processIdentifier: processID) else { return }
                self?.rememberExternalApplication(application)
            }
        }
    }

    private func rememberExternalApplication(_ application: NSRunningApplication) {
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        if let bundleIdentifier = application.bundleIdentifier,
           TargetRouting.excludedBundleIdentifiers.contains(bundleIdentifier) {
            return
        }
        let identifier = application.bundleIdentifier ?? "pid:\(application.processIdentifier)"
        let identifiers = recentExternalApplications.map {
            $0.bundleIdentifier ?? "pid:\($0.processIdentifier)"
        }
        recentExternalApplications = RecentAppMemory.remember(identifier, recent: identifiers, isOwnApp: false).compactMap { id in
            if id == identifier { return application }
            return recentExternalApplications.first {
                ($0.bundleIdentifier ?? "pid:\($0.processIdentifier)") == id
            }
        }
        lastExternalApplication = application
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.panelController.handle(
                url,
                fallbackApplication: self.activeExternalApplication,
                recentApplications: self.recentExternalApplications
            )
        }
    }
}
