import AppKit
import FloaterCore
import SwiftUI

struct FloaterWindowView: View {
    @ObservedObject var state: FloaterState
    @ObservedObject var accessibility = AccessibilityAccess()
    let onSubmit: (PromptRequest) -> Void
    let onCopy: () -> Void
    let onReplace: () -> Void
    let onDismiss: () -> Void
    let onContentChange: () -> Void
    var onHistory: () -> Void = {}
    let history: HistoryView
    @State private var focusedControl: PanelControl?

    private var canReplace: Bool {
        !state.response.isEmpty && state.canReplace && accessibility.isGranted
    }

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.regularMaterial)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            }
            .onReceive(state.objectWillChange) { _ in onContentChange() }
            .onChange(of: state.currentRequest) { _, _ in focusRequest() }
            .onChange(of: state.screen) { _, _ in focusRequest() }
            .onChange(of: accessibility.isGranted) { _, _ in onContentChange() }
    }

    @ViewBuilder
    private var content: some View {
        if state.screen == .history {
            history
        } else {
            VStack(spacing: 0) {
                header
                VStack(spacing: 8) {
                    Divider()
                    if state.screen == .newRequest {
                        NewRequestView(
                            prompt: $state.prompt, input: $state.input, canSubmit: state.canSubmit, focusedControl: $focusedControl,
                            onSubmit: submit, onDismiss: onDismiss, onContentChange: onContentChange
                        )
                    } else {
                        ResultsView(
                            state: state, canReplace: canReplace, focusedControl: $focusedControl,
                            onCopy: onCopy, onReplace: onReplace, onDismiss: onDismiss
                        )
                    }
                }
                .padding([.horizontal, .bottom], FloaterPanelLayout.padding)
            }
            .frame(width: FloaterPanelLayout.width, alignment: .top)
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
            .background {
                PanelKeyboardHandler(onKeyDown: handleKeyDown)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear(perform: focusRequest)
        }
    }

    private var header: some View {
        PanelHeader {
            HStack(spacing: 8) {
                Image(systemName: FloaterSymbol.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("AI")
                Text(state.windowTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                if state.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Generating response")
                }
                Spacer(minLength: 4)
            }
            PanelButton("New", control: .new, focus: $focusedControl, action: newRequest)
                .help("New request (Command+N)")
            PanelButton("History", control: .history, focus: $focusedControl, action: onHistory)
                .help("Open history (Command+H)")
        }
    }

    private func focusRequest() {
        guard state.screen != .history else { return }
        focusedControl = state.screen == .newRequest ? .prompt : .copy
    }

    private func newRequest() {
        state.showNewRequest()
        focusedControl = .prompt
        onContentChange()
    }

    private func submit() {
        guard let request = state.requestForSubmission() else { return }
        focusedControl = nil
        onSubmit(request)
    }

    private func handleKeyDown(_ event: NSEvent, window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if event.keyCode == 48, modifiers.subtracting([.option, .shift]).isEmpty {
            if !modifiers.contains(.option), let editor = window.firstResponder as? NSTextView, editor.isEditable {
                return false
            }
            moveFocus(backwards: modifiers.contains(.shift), in: window)
            return true
        }
        if event.keyCode == 53, modifiers.isEmpty {
            onDismiss()
            return true
        }
        if PanelShortcut.new.matches(event) {
            newRequest()
            return true
        }
        if state.screen == .newRequest, modifiers == .command, [36, 76].contains(event.keyCode) {
            submit()
            return true
        }
        if PanelShortcut.history.matches(event) {
            onHistory()
            return true
        }
        if state.screen == .newRequest, PanelShortcut.run.matches(event) {
            submit()
            return true
        }
        if state.screen == .results, PanelShortcut.replace.matches(event) {
            if canReplace { onReplace() }
            return true
        }
        guard state.screen == .results, modifiers == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            let action = #selector(NSText.copy(_:))
            let item = NSMenuItem(title: "Copy", action: action, keyEquivalent: "c")
            if let target = NSApp.target(forAction: action, to: nil, from: nil),
               (target as? NSUserInterfaceValidations)?.validateUserInterfaceItem(item) == true
                || (target as? NSMenuItemValidation)?.validateMenuItem(item) == true {
                NSApp.sendAction(action, to: target, from: nil)
            } else {
                onCopy()
            }
            return true
        case "e":
            DispatchQueue.main.async(execute: state.beginEditing)
            return true
        default:
            return false
        }
    }

    private func moveFocus(backwards: Bool, in window: NSWindow) {
        let controls: [PanelControl]
        if state.screen == .newRequest {
            controls = [.prompt, .input, .dismiss] + (state.canSubmit ? [.run] : []) + [.history, .new]
        } else {
            controls = [.copy, .edit]
                + (canReplace ? [.replace] : [])
                + [.dismiss, .history, .new]
        }
        if let identifier = PanelKeyboardHandler.moveFocus(
            in: window, identifiers: controls.map(\.rawValue), backwards: backwards,
            fallback: focusedControl?.rawValue
        ) {
            focusedControl = PanelControl(rawValue: identifier)
        }
    }
}
