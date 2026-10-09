import AppKit
import FloaterCore
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let state: FloaterState
    private let historyStore: HistoryStore
    private let settings: AppSettings
    private let accessibility: AccessibilityAccess
    private let historyState = HistoryViewState()
    private var panel: FloaterPanel?
    private var hostingView: NSHostingView<FloaterWindowView>?
    private var previousApplication: NSRunningApplication?
    private var resizeScheduled = false
    private var historyFocusNeedsRestore = false

    init(
        state: FloaterState, historyStore: HistoryStore = HistoryStore(fileURL: nil),
        settings: AppSettings = AppSettings(), accessibility: AccessibilityAccess = AccessibilityAccess()
    ) {
        self.state = state
        self.historyStore = historyStore
        self.settings = settings
        self.accessibility = accessibility
    }

    func show(previousApplication: NSRunningApplication?) {
        state.showRequest()
        self.previousApplication = previousApplication
        state.setCanReplace(previousApplication != nil && previousApplication?.isTerminated == false)
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

        let panel = panel ?? makePanel()
        fitPanelToContent()
        if !panel.isVisible {
            panel.center()
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
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
            self.previousApplication = previousApplication
            state.setCanReplace(previousApplication != nil && previousApplication?.isTerminated == false)
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
        guard !state.response.isEmpty,
              let application = previousApplication,
              !application.isTerminated else { return }
        state.setActionError(nil)
        accessibility.refresh()
        guard accessibility.isGranted else {
            state.setActionError("Allow Floater in System Settings > Privacy & Security > Accessibility, then try Replace again.")
            return
        }
        do {
            try BackgroundTextReplacer.replace(
                state.response, in: application,
                allowWholeField: settings.replaceWholeFieldWhenUnselected
            )
            closeAndRestoreApplication()
        } catch {
            state.setActionError(error.localizedDescription)
        }
    }

    func handle(_ url: URL, fallbackApplication: NSRunningApplication?) {
        guard let routedPrompt = PromptURL.parse(url) else { return }

        let application = routedPrompt.previousProcessID
            .flatMap(NSRunningApplication.init(processIdentifier:))
            ?? fallbackApplication

        handle(routedPrompt.request, fallbackApplication: application)
    }

    func handle(_ request: PromptRequest, fallbackApplication: NSRunningApplication?) {
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
            styleMask: [.borderless, .nonactivatingPanel],
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
            onSubmit: { [weak self] request in self?.state.start(request) },
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
}

final class FloaterPanel: NSPanel {
    var onKeyDown: ((NSEvent) -> Bool)?
    weak var keyboardHandlerOwner: AnyObject?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
