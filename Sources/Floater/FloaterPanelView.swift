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

    @State private var draftPrompt = ""
    @State private var draftInput = ""
    @State private var draftTitle: String?
    @State private var isPromptExpanded = false
    @State private var composerFieldsHeight: CGFloat = 160
    @FocusState private var focusedControl: FocusedControl?

    private enum FocusedControl: Hashable {
        case prompt
        case input
        case run
        case copy
        case edit
        case replace
        case dismiss
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
        .onChange(of: viewModel.currentRequest) { _, request in
            isPromptExpanded = false
            DispatchQueue.main.async {
                focusedControl = viewModel.currentRequest == nil ? .prompt : .copy
            }
            onContentChange()
        }
        .onChange(of: viewModel.response) { _, _ in onContentChange() }
        .onChange(of: viewModel.isGenerating) { _, _ in onContentChange() }
        .onChange(of: viewModel.errorMessage) { _, _ in onContentChange() }
        .onChange(of: isPromptExpanded) { _, _ in onContentChange() }
        .onChange(of: composerFieldsHeight) { _, _ in onContentChange() }
        .onKeyPress(.tab, phases: .down) { keyPress in
            moveFocus(backwards: keyPress.modifiers.contains(.shift))
            return .handled
        }
    }

    private var header: some View {
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
        .frame(height: 20)
        .gesture(WindowDragGesture())
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

                    editor(text: $draftPrompt, placeholder: "What should Floater do?", label: "Prompt", control: .prompt)

                    Text("Optional input")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    editor(text: $draftInput, placeholder: "Add input (optional)", label: "Optional input", control: .input)
                }
                .padding(1)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerFieldsHeight = $0 }
            }
            .frame(height: min(composerFieldsHeight, FloaterPanelLayout.maximumEditingHeight - 120))

            HStack(spacing: 8) {
                Spacer()
                Button("Dismiss", action: dismissComposer)
                    .keyboardShortcut(.escape, modifiers: [])
                    .focusable()
                    .focused($focusedControl, equals: .dismiss)
                    .onKeyPress(.return) {
                        dismissComposer()
                        return .handled
                    }

                Button(action: submit) {
                    Label("Run", systemImage: "arrow.up.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .focusable()
                .focused($focusedControl, equals: .run)
                .onKeyPress(.return) {
                    submit()
                    return .handled
                }
                .keyboardShortcut(.return, modifiers: .command)
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
            onFocus: { focusedControl = control },
            onMoveFocus: { moveFocus(from: control, backwards: $0) },
            onSubmit: submit
        )
        .focused($focusedControl, equals: control)
    }

    private func moveFocus(from control: FocusedControl? = nil, backwards: Bool) {
        let controls: [FocusedControl]
        if viewModel.currentRequest == nil {
            controls = [.prompt, .input, .dismiss]
                + (draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [.run])
        } else {
            controls = [.copy, .edit]
                + (viewModel.response.isEmpty || !viewModel.canReplace ? [] : [.replace])
                + [.dismiss]
        }
        guard let current = control ?? focusedControl, let index = controls.firstIndex(of: current) else {
            focusedControl = backwards ? controls.last : controls.first
            return
        }
        focusedControl = controls[(index + (backwards ? controls.count - 1 : 1)) % controls.count]
    }

    private var responseView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = viewModel.currentRequest {
                Button {
                    isPromptExpanded.toggle()
                } label: {
                    Text(request.prompt)
                        .font(.system(size: 12))
                        .lineLimit(isPromptExpanded ? nil : 2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: promptHeight(for: request.prompt), alignment: .topLeading)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(isPromptExpanded ? "Collapse prompt" : "Show full prompt")
            }

            responseContent
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
        guard isPromptExpanded, let prompt = viewModel.currentRequest?.prompt else {
            return FloaterPanelLayout.maximumResponseHeight
        }

        let expandedPromptHeight = promptHeight(for: prompt)
        let collapsedPromptHeight = summaryHeight(for: prompt)
        let extraPromptHeight = max(0, expandedPromptHeight - collapsedPromptHeight)
        return max(18, FloaterPanelLayout.maximumResponseHeight - extraPromptHeight)
    }

    private func summaryHeight(for text: String) -> CGFloat {
        let measured = measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 12)
        let font = NSFont.systemFont(ofSize: 12)
        let twoLineMaximum = (font.ascender - font.descender + font.leading) * 2
        return min(twoLineMaximum, measured)
    }

    private func promptHeight(for text: String) -> CGFloat {
        isPromptExpanded
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

            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .focusable()
            .focused($focusedControl, equals: .copy)
            .onKeyPress(.return) {
                onCopy()
                return .handled
            }

            Button(action: editRequest) {
                Label("Edit", systemImage: "pencil")
            }
            .help("Edit the prompt and run it again.")
            .focusable()
            .focused($focusedControl, equals: .edit)
            .onKeyPress(.return) {
                DispatchQueue.main.async(execute: editRequest)
                return .handled
            }

            Button(action: onReplace) {
                Label("Replace", systemImage: "arrow.uturn.down")
            }
            .disabled(viewModel.response.isEmpty || !viewModel.canReplace)
            .help("Paste the result into the previous app. Requires Accessibility access.")
            .focusable()
            .focused($focusedControl, equals: .replace)
            .onKeyPress(.return) {
                onReplace()
                return .handled
            }

            Button("Dismiss", action: onDismiss)
                .keyboardShortcut(.escape, modifiers: [])
                .focusable()
                .focused($focusedControl, equals: .dismiss)
                .onKeyPress(.return) {
                    onDismiss()
                    return .handled
                }
        }
    }

    private func submit() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let request = PromptRequest(prompt: prompt, input: draftInput, title: draftTitle)
        draftTitle = nil
        focusedControl = nil
        onSubmit(request)
    }

    private func editRequest() {
        guard let request = viewModel.currentRequest else { return }
        draftPrompt = request.prompt
        draftInput = request.input
        draftTitle = request.title
        isPromptExpanded = false
        viewModel.showComposer()
    }

    private func dismissComposer() {
        draftTitle = nil
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
