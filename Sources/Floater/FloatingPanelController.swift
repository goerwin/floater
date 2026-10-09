import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import FloaterCore
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    private let viewModel: FloaterViewModel
    private var panel: FloaterPanel?
    private var hostingView: NSHostingView<FloaterPanelView>?
    private var previousApplication: NSRunningApplication?
    private var resizeScheduled = false

    init(viewModel: FloaterViewModel) {
        self.viewModel = viewModel
    }

    func show(previousApplication: NSRunningApplication?) {
        self.previousApplication = previousApplication
        viewModel.setCanReplace(previousApplication != nil && previousApplication?.isTerminated == false)

        let panel = panel ?? makePanel()
        panel.title = windowTitle(for: viewModel.currentRequest)
        fitPanelToContent()
        if !panel.isVisible {
            panel.center()
        }

        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        restorePreviousApplication()
    }

    func copyAndDismiss() {
        guard !viewModel.response.isEmpty else { return }
        writeToPasteboard(viewModel.response)
        dismiss()
    }

    func replaceAndDismiss() {
        guard !viewModel.response.isEmpty,
              let application = previousApplication,
              !application.isTerminated else { return }
        guard requestAccessibilityAccessIfNeeded() else { return }

        writeToPasteboard(viewModel.response)
        panel?.orderOut(nil)
        application.activate()

        let processID = application.processIdentifier
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            postPaste(to: processID)
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
        viewModel.start(request)
        show(previousApplication: fallbackApplication)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
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
        panel.title = windowTitle(for: viewModel.currentRequest)
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.minSize = NSSize(width: FloaterPanelLayout.width, height: FloaterPanelLayout.minimumHeight)
        panel.maxSize = NSSize(width: FloaterPanelLayout.width, height: FloaterPanelLayout.maximumHeight)
        panel.delegate = self

        let hostingView = NSHostingView(
            rootView: FloaterPanelView(
                viewModel: viewModel,
                onSubmit: { [weak self] request in self?.start(request) },
                onCopy: { [weak self] in self?.copyAndDismiss() },
                onReplace: { [weak self] in self?.replaceAndDismiss() },
                onDismiss: { [weak self] in self?.dismiss() },
                onContentChange: { [weak self] in self?.schedulePanelResize() }
            )
        )
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView
        return panel
    }

    private func start(_ request: PromptRequest) {
        viewModel.start(request)
        panel?.title = windowTitle(for: request)
        schedulePanelResize()
    }

    private func windowTitle(for request: PromptRequest?) -> String {
        guard let title = request?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return "Floater"
        }
        return title
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

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let maximumHeight = viewModel.currentRequest == nil
            ? FloaterPanelLayout.maximumEditingHeight
            : FloaterPanelLayout.maximumHeight
        panel.maxSize = NSSize(width: FloaterPanelLayout.width, height: maximumHeight)
        let height = min(
            maximumHeight,
            max(FloaterPanelLayout.minimumHeight, ceil(hostingView.fittingSize.height))
        )

        var frame = panel.frame
        frame.origin.y = frame.maxY - height
        if let screen = panel.screen {
            frame.origin.y = max(screen.visibleFrame.minY + 12, frame.origin.y)
        }
        frame.size.width = FloaterPanelLayout.width
        frame.size.height = height
        panel.setFrame(frame, display: true)
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

    private func requestAccessibilityAccessIfNeeded() -> Bool {
        guard !AXIsProcessTrusted() else { return true }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        return false
    }

    private func postPaste(to processID: pid_t) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(kVK_ANSI_V),
                keyDown: false
              ) else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processID)
        keyUp.postToPid(processID)
    }
}

private final class FloaterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
