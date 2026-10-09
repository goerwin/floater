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
        .onChange(of: viewModel.currentRequest) { _, _ in onContentChange() }
        .onChange(of: viewModel.response) { _, _ in onContentChange() }
        .onChange(of: viewModel.isGenerating) { _, _ in onContentChange() }
        .onChange(of: viewModel.errorMessage) { _, _ in onContentChange() }
    }

    private var header: some View {
        HStack(spacing: 8) {
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
            Text("Prompt")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("What should Floater do?", text: $draftPrompt, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .onSubmit(submit)

            Text("Optional input")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            TextEditor(text: $draftInput)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 72)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel("Optional input")

            HStack {
                Spacer()
                Button(action: submit) {
                    Label("Run", systemImage: "arrow.up.right")
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var responseView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = viewModel.currentRequest {
                Text(request.prompt)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
                    .frame(height: summaryHeight(for: request.prompt), alignment: .topLeading)
            }

            responseContent
            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        if viewModel.errorMessage == nil && viewModel.isGenerating && viewModel.response.isEmpty {
            return 36
        }

        let text = viewModel.errorMessage
            ?? (viewModel.response.isEmpty ? "No response was returned." : viewModel.response)
        let height = measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 13) + 4
        return min(FloaterPanelLayout.maximumResponseHeight, max(18, height))
    }

    private func summaryHeight(for text: String) -> CGFloat {
        let measured = measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 12)
        let font = NSFont.systemFont(ofSize: 12)
        let twoLineMaximum = (font.ascender - font.descender + font.leading) * 2
        return min(twoLineMaximum, measured)
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
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.response.isEmpty)

            Button(action: onReplace) {
                Label("Replace", systemImage: "arrow.uturn.down")
            }
            .disabled(viewModel.response.isEmpty || !viewModel.canReplace)
            .help("Paste the result into the previous app. Requires Accessibility access.")

            Spacer()

            Button("Dismiss", action: onDismiss)
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private func submit() {
        let prompt = draftPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        onSubmit(PromptRequest(prompt: prompt, input: draftInput))
    }
}

enum FloaterPanelLayout {
    static let width: CGFloat = 460
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 440
    static let maximumResponseHeight: CGFloat = 300
    static let padding: CGFloat = 14
    static let contentWidth = width - padding * 2
}
