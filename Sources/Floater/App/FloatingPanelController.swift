import AppKit
import FloaterCore
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let state: FloaterState
    private let historyStore: HistoryStore
    private let settings: AppSettings
    private let accessibility: AccessibilityAccess
    private let captureTarget: @MainActor (NSRunningApplication) -> any TextPasteTarget
    private let readFocusedField: @MainActor (NSRunningApplication) -> FieldCapture
    private let activateForCapture: @MainActor (NSRunningApplication) async -> Void
    private let replaceText: @MainActor (String, any TextPasteTarget, Bool, Bool) async throws -> Void
    private let historyState = HistoryViewState()
    private var panel: FloaterPanel?
    private var hostingView: NSHostingView<FloaterWindowView>?
    private var previousApplication: NSRunningApplication?
    private var replacementTarget: (any TextPasteTarget)?
    private var selectionOnlyRequest: PromptRequest?
    private var resizeScheduled = false
    private var historyFocusNeedsRestore = false
    private var isReplacing = false
    private var didBecomeActiveObserver: NSObjectProtocol?

    init(
        state: FloaterState, historyStore: HistoryStore = HistoryStore(fileURL: nil),
        settings: AppSettings = AppSettings(), accessibility: AccessibilityAccess = AccessibilityAccess(),
        captureTarget: @escaping @MainActor (NSRunningApplication) -> any TextPasteTarget = {
            BackgroundTextReplacer.capture(in: $0)
        },
        readFocusedField: @escaping @MainActor (NSRunningApplication) -> FieldCapture = {
            BackgroundTextReplacer.readFocusedField(in: $0)
        },
        activateForCapture: @escaping @MainActor (NSRunningApplication) async -> Void = { application in
            guard !application.isTerminated else { return }
            application.activate()
            for _ in 0..<20 {
                if application.isActive { return }
                try? await Task.sleep(for: .milliseconds(25))
            }
        },
        replaceText: @escaping @MainActor (String, any TextPasteTarget, Bool, Bool) async throws -> Void = {
            try await BackgroundTextReplacer.replace($0, in: $1, allowWholeField: $2, selectionOnly: $3)
        }
    ) {
        self.state = state
        self.historyStore = historyStore
        self.settings = settings
        self.accessibility = accessibility
        self.captureTarget = captureTarget
        self.readFocusedField = readFocusedField
        self.activateForCapture = activateForCapture
        self.replaceText = replaceText
    }

    private func ensureActiveObserver() {
        guard didBecomeActiveObserver == nil else { return }
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.claimKeyIfVisible()
            }
        }
    }

    func show(previousApplication: NSRunningApplication?, preservingReplacementTarget: Bool = false) {
        state.showRequest()
        rememberTarget(in: previousApplication, preservingReplacementTarget: preservingReplacementTarget)
        showPanel()
        if let initialFirstResponder = panel?.initialFirstResponder {
            panel?.makeFirstResponder(initialFirstResponder)
        }
    }

    func open(previousApplication: NSRunningApplication?) {
        if panel == nil {
            showNewRequest(previousApplication: previousApplication)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        accessibility.refresh()
        ensureActiveObserver()

        let panel = panel ?? makePanel()
        fitPanelToContent()
        if !panel.isVisible {
            panel.center()
        }

        // The panel only opens from an explicit user action (menu, CLI/URL, submit,
        // history, or a failed Replace), so taking focus here is always expected.
        // Plain activate() can be declined when another app just activated, which is
        // exactly what capture does before showing the panel.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        // Activation is asynchronous when Floater was in the background, so the
        // make-key above can land before the app is active and never take effect.
        // didBecomeActive re-asserts it once activation completes.
        claimKeyIfVisible()
    }

    private func claimKeyIfVisible() {
        guard let panel, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
        if let initialFirstResponder = panel.initialFirstResponder {
            panel.makeFirstResponder(initialFirstResponder)
        }
    }

    func dismiss() {
        rememberHistoryFocus()
        if state.dismiss() {
            historyFocusNeedsRestore = state.screen == .history
            fitPanelToContent()
        } else {
            closeAndRestoreApplication()
        }
    }

    private func closeAndRestoreApplication() {
        hide()
        restorePreviousApplication()
    }

    func hide() {
        rememberHistoryFocus()
        panel?.orderOut(nil)
    }

    var isVisible: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }
    var isShowingHistory: Bool { state.screen == .history }

    func showHistory(previousApplication: NSRunningApplication? = nil) {
        guard !isShowingHistory else { showPanel(); return }
        if !isVisible {
            rememberTarget(in: previousApplication)
        }
        state.showHistory(returnToRequest: isVisible)
        historyFocusNeedsRestore = true
        showPanel()
    }

    func openHistoryEntry(_ entry: HistoryEntry) {
        rememberHistoryFocus()
        state.openHistoryEntry(entry)
        showPanel()
    }

    func showNewRequest(previousApplication: NSRunningApplication?) {
        state.showNewRequest()
        show(previousApplication: previousApplication)
    }

    func copyAndDismiss() {
        guard !state.response.isEmpty else { return }
        writeToPasteboard(state.response)
        closeAndRestoreApplication()
    }

    func replaceAndDismiss() {
        guard !isReplacing, !state.response.isEmpty,
              let application = previousApplication,
              !application.isTerminated else { return }
        state.setActionError(nil)
        accessibility.refresh()
        guard accessibility.isGranted else {
            writeToPasteboard(state.response)
            state.setActionError("Allow Floater in System Settings > Privacy & Security > Accessibility, then try Replace again. The result is copied.")
            return
        }
        let target = replacementTarget ?? captureTarget(application)
        replacementTarget = target
        let response = state.response
        let allowWholeField = settings.replaceWholeFieldWhenUnselected
        let selectionOnly = state.currentRequest == selectionOnlyRequest
        isReplacing = true
        hide()
        Task { @MainActor [self] in
            defer { isReplacing = false }
            do {
                try await replaceText(response, target, allowWholeField, selectionOnly)
            } catch {
                state.setActionError(error.localizedDescription)
                showPanel()
            }
        }
    }

    func handle(
        _ url: URL,
        fallbackApplication: NSRunningApplication?,
        recentApplications: [NSRunningApplication] = []
    ) async {
        guard let routedPrompt = PromptURL.parse(url) else { return }
        let resolution = resolve(
            routedPrompt, fallback: fallbackApplication, recent: recentApplications
        )
        guard routedPrompt.captureInput else {
            handle(routedPrompt.request, fallbackApplication: resolution.application)
            return
        }
        await capture(
            routedPrompt.request,
            application: resolution.application,
            considered: resolution.considered,
            ignoredAny: resolution.ignoredAny
        )
    }

    func handle(_ request: PromptRequest, fallbackApplication: NSRunningApplication?) {
        selectionOnlyRequest = nil
        state.start(request)
        show(previousApplication: fallbackApplication)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        accessibility.refresh()
    }

    private func makePanel() -> FloaterPanel {
        let panel = FloaterPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: FloaterPanelLayout.width,
                height: FloaterPanelLayout.minimumHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = state.windowTitle
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: FloaterPanelLayout.width, height: FloaterPanelLayout.minimumHeight)
        panel.maxSize = NSSize(width: FloaterPanelLayout.width, height: FloaterPanelLayout.maximumHeight)
        panel.delegate = self

        let hostingView = NSHostingView(rootView: FloaterWindowView(
            state: state, accessibility: accessibility,
            onSubmit: { [weak self] request in
                self?.selectionOnlyRequest = nil
                self?.state.start(request)
            },
            onCopy: { [weak self] in self?.copyAndDismiss() },
            onReplace: { [weak self] in self?.replaceAndDismiss() },
            onDismiss: { [weak self] in self?.dismiss() },
            onContentChange: { [weak self] in self?.schedulePanelResize() },
            onHistory: { [weak self] in self?.showHistory() },
            history: HistoryView(
                store: historyStore, onOpen: { [weak self] entry in self?.openHistoryEntry(entry) },
                onClear: { [weak self] in self?.clearHistory() },
                onDismiss: { [weak self] in self?.dismiss() },
                onNew: { [weak self] in self?.showNewRequest(previousApplication: self?.previousApplication) },
                state: historyState
            )
        ))
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func schedulePanelResize() {
        guard !resizeScheduled else { return }
        resizeScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizeScheduled = false
            self.fitPanelToContent()
        }
    }

    private func fitPanelToContent() {
        guard let panel, let hostingView else { return }
        panel.title = state.windowTitle

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let maximumHeight = isShowingHistory
            ? max(360, (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 900) - 24
            : state.screen == .newRequest
            ? FloaterPanelLayout.maximumEditingHeight
            : FloaterPanelLayout.maximumHeight
        let width = FloaterPanelLayout.width
        panel.minSize = NSSize(width: width, height: FloaterPanelLayout.minimumHeight)
        panel.maxSize = NSSize(width: width, height: maximumHeight)
        let height = min(
            maximumHeight,
            max(FloaterPanelLayout.minimumHeight, ceil(hostingView.fittingSize.height))
        )

        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        frame.size.width = width
        frame.size.height = height
        if let screen = panel.screen {
            frame.origin.y = max(screen.visibleFrame.minY + 12, frame.origin.y)
            frame.origin.x = min(
                max(screen.visibleFrame.minX + 12, frame.origin.x),
                screen.visibleFrame.maxX - width - 12
            )
        }
        panel.setFrame(frame, display: true)
        if isShowingHistory, historyFocusNeedsRestore {
            restoreHistoryFocus()
        }
    }

    private func rememberHistoryFocus() {
        guard isShowingHistory, let responder = panel?.firstResponder else { return }
        if let editor = responder as? NSTextView, editor.isFieldEditor {
            historyState.focusedControlIdentifier = "historySearch"
        } else if let identifier = (responder as? NSView)?.identifier?.rawValue {
            historyState.focusedControlIdentifier = identifier
        }
    }

    private func clearHistory() {
        rememberHistoryFocus()
        let previousIdentifier = historyState.focusedControlIdentifier
        if previousIdentifier == "clearHistory" {
            historyState.focusedControlIdentifier = "historyDismiss"
        }
        restoreHistoryFocus()
        historyStore.clear()
        if previousIdentifier == "clearHistory", !historyStore.entries.isEmpty || historyStore.errorMessage != nil {
            historyState.focusedControlIdentifier = previousIdentifier
            restoreHistoryFocus()
        }
    }

    private func restoreHistoryFocus() {
        guard let panel, let root = panel.contentView,
              let search = root.firstDescendant(where: { $0.identifier?.rawValue == "historySearch" }) else { return }
        let remembered = root.firstDescendant(where: { $0.identifier?.rawValue == historyState.focusedControlIdentifier })
        let target: NSView
        if let remembered, (remembered as? NSControl)?.isEnabled != false {
            target = remembered
        } else {
            target = root.firstDescendant(where: { $0 is NSTableView }) ?? search
        }
        panel.initialFirstResponder = target
        if panel.makeFirstResponder(target) { historyFocusNeedsRestore = false }
    }

    private func writeToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func restorePreviousApplication() {
        guard let application = previousApplication, !application.isTerminated else { return }
        application.activate()
    }

    private func rememberTarget(
        in application: NSRunningApplication?, preservingReplacementTarget: Bool = false
    ) {
        accessibility.refresh()
        previousApplication = application
        if !preservingReplacementTarget {
            selectionOnlyRequest = nil
            replacementTarget = accessibility.isGranted ? application.map(captureTarget) : nil
        }
        state.setCanReplace(application != nil && application?.isTerminated == false)
    }

    private struct AppResolution {
        var application: NSRunningApplication?
        var considered: [TargetCandidate]
        var ignoredAny: Bool
    }

    private func resolve(
        _ routed: RoutedPrompt,
        fallback: NSRunningApplication?,
        recent: [NSRunningApplication]
    ) -> AppResolution {
        guard !routed.ignoredBundleIdentifiers.isEmpty else {
            let application = routed.previousProcessID.flatMap(NSRunningApplication.init(processIdentifier:)) ?? fallback
            return AppResolution(application: application, considered: [], ignoredAny: false)
        }

        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        let previousApplication = routed.previousProcessID.flatMap(NSRunningApplication.init(processIdentifier:))
        let previous = previousApplication.map(candidate)
        let recentCandidates = recent.map(candidate)
        let considered = TargetRouting.considered(
            previous: previous, recent: recentCandidates, ownBundleIdentifier: ownBundleIdentifier
        )
        let selected = TargetRouting.select(
            previous: previous,
            recent: recentCandidates,
            ignoredBundleIdentifiers: routed.ignoredBundleIdentifiers,
            ownBundleIdentifier: ownBundleIdentifier
        )
        let application: NSRunningApplication?
        switch selected {
        case .previous:
            application = previousApplication
        case .recent(let index):
            application = recent.indices.contains(index) ? recent[index] : nil
        case nil:
            application = nil
        }
        return AppResolution(application: application, considered: considered, ignoredAny: true)
    }

    private func candidate(_ application: NSRunningApplication) -> TargetCandidate {
        TargetCandidate(
            name: application.localizedName,
            bundleIdentifier: application.bundleIdentifier,
            isRunning: !application.isTerminated
        )
    }

    private func capture(
        _ request: PromptRequest,
        application: NSRunningApplication?,
        considered: [TargetCandidate],
        ignoredAny: Bool
    ) async {
        guard let application, !application.isTerminated else {
            let named = considered.isEmpty ? [application].compactMap { $0 }.map(candidate) : considered
            fail(
                request,
                CaptureMessages.noApplication(ignoredAny: ignoredAny, considered: named),
                application: nil
            )
            return
        }
        accessibility.refresh()
        guard accessibility.isGranted else {
            fail(request, CaptureMessages.accessibility(for: candidate(application)), application: application)
            return
        }

        var read = readFocusedField(application)
        var outcome = FieldTextChoice.interpret(
            elementFound: read.elementFound,
            isSecure: read.isSecure,
            selectedText: read.selectedText,
            fieldValue: read.fieldValue,
            selectionUnreadable: read.selectionUnreadable
        )
        if outcome == .failed {
            await activateForCapture(application)
            read = readFocusedField(application)
            outcome = FieldTextChoice.interpret(
                elementFound: read.elementFound,
                isSecure: read.isSecure,
                selectedText: read.selectedText,
                fieldValue: read.fieldValue,
                selectionUnreadable: read.selectionUnreadable
            )
            if outcome == .failed { outcome = .unreadable }
        }

        switch outcome {
        case .selection(let text):
            startCaptured(request, input: text, application: application, target: read.target, selectionOnly: true)
        case .field(let text):
            startCaptured(request, input: text, application: application, target: read.target, selectionOnly: false)
        case .empty:
            fail(request, CaptureMessages.emptyField(for: candidate(application)), application: application)
        case .unreadable, .failed:
            fail(request, CaptureMessages.unreadableField(for: candidate(application)), application: application)
        }
    }

    private func startCaptured(
        _ request: PromptRequest,
        input: String,
        application: NSRunningApplication,
        target: any TextPasteTarget,
        selectionOnly: Bool
    ) {
        let captured = PromptRequest(prompt: request.prompt, input: input, title: request.title)
        selectionOnlyRequest = selectionOnly ? captured : nil
        replacementTarget = target
        state.start(captured)
        show(previousApplication: application, preservingReplacementTarget: true)
    }

    private func fail(_ request: PromptRequest, _ message: String, application: NSRunningApplication?) {
        selectionOnlyRequest = nil
        state.presentFailure(request, message: message)
        show(previousApplication: application)
    }
}

final class FloaterPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    weak var keyboardHandlerOwner: AnyObject?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if attachedSheet == nil, event.type == .keyDown, onKeyDown?(event) == true { return }
        if attachedSheet == nil, event.type == .keyDown,
           let button = firstResponder as? PanelButton.ActionButton, button.handleActivation(event) { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if attachedSheet == nil, event.type == .keyDown, onKeyDown?(event) == true { return true }
        if attachedSheet == nil, event.type == .keyDown,
           let button = firstResponder as? PanelButton.ActionButton, button.handleActivation(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
