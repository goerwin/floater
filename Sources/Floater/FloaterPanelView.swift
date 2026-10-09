import AppKit
import FloaterCore
import SwiftUI

struct FloaterPanelView: View {
    @ObservedObject var viewModel: FloaterViewModel
    let onSubmit: (PromptRequest) -> Void
    let onCopy: () -> Void
    let onReplace: () -> Void
    let onDismiss: () -> Void
    let onContentChange: () -> Void
    var onHistory: () -> Void = {}

    @ObservedObject var contentState = PanelContentState()
    @ObservedObject var accessibility = AccessibilityAccess()
    var onNew: () -> Void = {}
    @State private var composerFieldsHeight: CGFloat = 160
    @State private var focusedControl: FocusedControl?

    private enum FocusedControl: String {
        case prompt
        case input
        case run
        case copy
        case edit
        case replace
        case dismiss
        case history
        case new
        case accessibility
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            Divider()

            if viewModel.currentRequest == nil {
                composer
            } else {
                responseView
            }
        }
        .padding(FloaterPanelLayout.padding)
        .frame(width: FloaterPanelLayout.width, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
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
        .onChange(of: viewModel.currentRequest) { _, request in
            contentState.isPromptExpanded = false
            DispatchQueue.main.async {
                focusedControl = viewModel.currentRequest == nil ? .prompt : .copy
            }
            onContentChange()
        }
        .onChange(of: viewModel.response) { _, _ in onContentChange() }
        .onChange(of: viewModel.isGenerating) { _, _ in onContentChange() }
        .onChange(of: viewModel.errorMessage) { _, _ in onContentChange() }
        .onChange(of: accessibility.isGranted) { _, _ in onContentChange() }
        .onChange(of: viewModel.actionErrorMessage) { _, _ in onContentChange() }
        .onChange(of: contentState.isPromptExpanded) { _, _ in onContentChange() }
        .onChange(of: composerFieldsHeight) { _, _ in onContentChange() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("AI")

                Text(windowTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if viewModel.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Generating response")
                }
            }
            .gesture(WindowDragGesture())

            panelButton("New", symbol: "plus", control: .new, action: newRequest)
                .help("New request (Command+N)")

            panelButton("History", symbol: "clock.arrow.circlepath", control: .history, action: onHistory)
                .help("Open history (Command+H)")
        }
        .frame(minHeight: 24)
    }

    private var windowTitle: String {
        guard let title = viewModel.currentRequest?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return "Floater"
        }
        return title
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    editor(text: $contentState.prompt, placeholder: "What should Floater do?", label: "Prompt", control: .prompt)

                    Text("Optional input")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    editor(text: $contentState.input, placeholder: "Add input (optional)", label: "Optional input", control: .input)
                }
                .padding(1)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerFieldsHeight = $0 }
            }
            .frame(height: min(composerFieldsHeight, FloaterPanelLayout.maximumEditingHeight - 120))

            HStack(spacing: 8) {
                Spacer()
                panelButton("Dismiss", control: .dismiss, action: dismissComposer)
                panelButton(
                    "Run", symbol: "arrow.up.right", control: .run,
                    enabled: !contentState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    primary: true, action: submit
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            DispatchQueue.main.async { focusedControl = .prompt }
        }
    }

    private func editor(
        text: Binding<String>, placeholder: String, label: String, control: FocusedControl
    ) -> some View {
        MultilineInput(
            text: text,
            placeholder: placeholder,
            label: label,
            isFocused: focusedControl == control,
            prefersInitialFocus: control == .prompt,
            identifier: control.rawValue,
            onFocus: { if focusedControl != control { focusedControl = control } },
            onSubmit: submit
        )
    }

    private func panelButton(
        _ title: String, symbol: String? = nil, control: FocusedControl,
        enabled: Bool = true, primary: Bool = false, small: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        PanelButton(
            title: title, symbol: symbol, shortcut: shortcut(for: control), isEnabled: enabled, isPrimary: primary, isSmall: small,
            isFocused: focusedControl == control,
            prefersInitialFocus: control == .copy && viewModel.currentRequest != nil,
            identifier: control.rawValue,
            onFocus: { if focusedControl != control { focusedControl = control } }, action: action
        )
        .fixedSize()
        .controlSize(small ? .small : .regular)
        .disabled(!enabled)
    }

    private func shortcut(for control: FocusedControl) -> PanelShortcut? {
        switch control {
        case .copy: .copy
        case .edit: .edit
        case .replace: .replace
        case .dismiss: .dismiss
        case .history: .history
        case .run: .run
        case .new: .new
        default: nil
        }
    }

    private func handleKeyDown(_ event: NSEvent, window: NSWindow) -> Bool {
        let modifiers = event.modifierFlags.intersection([.shift, .command, .option, .control])
        if event.keyCode == 48, modifiers.subtracting([.option, .shift]).isEmpty {
            if !modifiers.contains(.option), let editor = window.firstResponder as? NSTextView, editor.isEditable {
                return false
            }
            let current = (window.firstResponder as? NSView)?.identifier
                .flatMap { FocusedControl(rawValue: $0.rawValue) }
            moveFocus(from: current, backwards: modifiers.contains(.shift), in: window)
            return true
        }
        if event.keyCode == 53, modifiers.isEmpty {
            viewModel.currentRequest == nil ? dismissComposer() : onDismiss()
            return true
        }
        if PanelShortcut.new.matches(event) {
            newRequest()
            return true
        }
        if viewModel.currentRequest == nil, modifiers == .command, [36, 76].contains(event.keyCode) {
            submit()
            return true
        }
        if PanelShortcut.history.matches(event) {
            onHistory()
            return true
        }
        if viewModel.currentRequest == nil, PanelShortcut.run.matches(event) {
            submit()
            return true
        }
        if viewModel.currentRequest != nil, PanelShortcut.replace.matches(event) {
            if accessibility.isGranted && viewModel.canReplace && !viewModel.response.isEmpty { onReplace() }
            return true
        }
        guard viewModel.currentRequest != nil, modifiers == .command else { return false }
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
            DispatchQueue.main.async(execute: editRequest)
            return true
        default:
            return false
        }
    }

    private func moveFocus(from current: FocusedControl?, backwards: Bool, in window: NSWindow) {
        let controls: [FocusedControl]
        if viewModel.currentRequest == nil {
            controls = [.prompt, .input, .dismiss]
                + (contentState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.run])
                + [.history, .new]
        } else {
            controls = [.copy, .edit]
                + (viewModel.response.isEmpty || !viewModel.canReplace || !accessibility.isGranted ? [] : [.replace])
                + (accessibility.isGranted ? [] : [.accessibility])
                + [.dismiss]
                + [.history, .new]
        }
        let destination: FocusedControl?
        if let current = current ?? focusedControl, let index = controls.firstIndex(of: current) {
            destination = controls[(index + (backwards ? controls.count - 1 : 1)) % controls.count]
        } else {
            destination = backwards ? controls.last : controls.first
        }
        guard let destination, let root = window.contentView,
              let view = root.firstDescendant(where: { $0.identifier?.rawValue == destination.rawValue }) else { return }
        focusedControl = destination
        window.makeFirstResponder(view)
    }

    private var responseView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = viewModel.currentRequest {
                Button {
                    contentState.isPromptExpanded.toggle()
                } label: {
                    Text(request.prompt)
                        .font(.system(size: 12))
                        .lineLimit(contentState.isPromptExpanded ? nil : 2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: promptHeight(for: request.prompt), alignment: .topLeading)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(contentState.isPromptExpanded ? "Collapse prompt" : "Show full prompt")
            }

            responseContent
            if let message = viewModel.actionErrorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            if !accessibility.isGranted {
                HStack {
                    Text("Replace requires Accessibility access.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    panelButton("Enable Accessibility", control: .accessibility, small: true, action: accessibility.request)
                }
            }
            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear(perform: focusCopyAction)
    }

    @ViewBuilder
    private var responseContent: some View {
        let height = responseContentHeight

        if let errorMessage = viewModel.errorMessage {
            ScrollView {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            }
            .frame(height: height)
        } else if viewModel.response.isEmpty && viewModel.isGenerating {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking with Apple Intelligence…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
        } else {
            ScrollView {
                Text(viewModel.response.isEmpty ? "No response was returned." : viewModel.response)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            }
            .frame(height: height)
            .accessibilityIdentifier("responseText")
        }
    }

    private var responseContentHeight: CGFloat {
        let maximumHeight = responseContentHeightLimit

        if viewModel.errorMessage == nil && viewModel.isGenerating && viewModel.response.isEmpty {
            return min(36, maximumHeight)
        }

        let text = viewModel.errorMessage
            ?? (viewModel.response.isEmpty ? "No response was returned." : viewModel.response)
        let height = measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 13) + 4
        return min(maximumHeight, max(18, height))
    }

    private var responseContentHeightLimit: CGFloat {
        let errorHeight = viewModel.actionErrorMessage.map {
            measuredTextHeight($0, width: FloaterPanelLayout.contentWidth, fontSize: 12) + 8
        } ?? 0
        let permissionHeight: CGFloat = accessibility.isGranted ? 0 : 36
        let maximumHeight = max(18, FloaterPanelLayout.maximumResponseHeight - errorHeight - permissionHeight)
        guard contentState.isPromptExpanded, let prompt = viewModel.currentRequest?.prompt else {
            return maximumHeight
        }

        let expandedPromptHeight = promptHeight(for: prompt)
        let collapsedPromptHeight = summaryHeight(for: prompt)
        let extraPromptHeight = max(0, expandedPromptHeight - collapsedPromptHeight)
        return max(18, maximumHeight - extraPromptHeight)
    }

    private func summaryHeight(for text: String) -> CGFloat {
        let measured = measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 12)
        let font = NSFont.systemFont(ofSize: 12)
        let twoLineMaximum = (font.ascender - font.descender + font.leading) * 2
        return min(twoLineMaximum, measured)
    }

    private func promptHeight(for text: String) -> CGFloat {
        contentState.isPromptExpanded
            ? measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 12)
            : summaryHeight(for: text)
    }

    private func focusCopyAction() {
        guard viewModel.currentRequest != nil else { return }
        focusedControl = .copy
    }

    private func measuredTextHeight(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let lineHeight = font.ascender - font.descender + font.leading
        return ceil(max(lineHeight, bounds.height))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Spacer()
            panelButton("Copy", symbol: "doc.on.doc", control: .copy, action: onCopy)
                .help("Copy the response (Command+C)")
            panelButton("Edit", symbol: "pencil", control: .edit, action: editRequest)
                .help("Edit the prompt and run it again (Command+E)")
            panelButton(
                "Replace", symbol: "arrow.uturn.down", control: .replace,
                enabled: !viewModel.response.isEmpty && viewModel.canReplace && accessibility.isGranted, action: onReplace
            )
            .help("Replace text in the previous app. Requires Accessibility access.")
            panelButton("Dismiss", control: .dismiss, action: onDismiss)
        }
    }

    private func newRequest() {
        contentState.prompt = ""
        contentState.input = ""
        contentState.title = nil
        contentState.isPromptExpanded = false
        viewModel.showComposer()
        focusedControl = .prompt
        onNew()
        onContentChange()
    }

    private func submit() {
        let prompt = contentState.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let request = PromptRequest(prompt: prompt, input: contentState.input, title: contentState.title)
        contentState.title = nil
        focusedControl = nil
        onSubmit(request)
    }

    private func editRequest() {
        guard let request = viewModel.currentRequest else { return }
        contentState.prompt = request.prompt
        contentState.input = request.input
        contentState.title = request.title
        contentState.isPromptExpanded = false
        viewModel.showComposer()
    }

    private func dismissComposer() {
        contentState.title = nil
        onDismiss()
    }
}

enum FloaterPanelLayout {
    static let width: CGFloat = 500
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 480
    static var maximumEditingHeight: CGFloat {
        max(minimumHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 24)
    }
    static let maximumResponseHeight: CGFloat = 340
    static let padding: CGFloat = 14
    static let contentWidth = width - padding * 2
}
