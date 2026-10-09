import AppKit
import SwiftUI

struct ResultsView: View {
    @ObservedObject var state: FloaterState
    let canReplace: Bool
    @Binding var focusedControl: PanelControl?
    let onCopy: () -> Void
    let onReplace: () -> Void
    let onDismiss: () -> Void

    private var displayedText: String {
        state.errorMessage ?? (state.response.isEmpty ? "No response was returned." : state.response)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = state.currentRequest {
                Button {
                    state.isPromptExpanded.toggle()
                } label: {
                    Text(request.prompt)
                        .font(.system(size: 12))
                        .lineLimit(state.isPromptExpanded ? nil : 2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: promptHeight(for: request.prompt), alignment: .topLeading)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(state.isPromptExpanded ? "Collapse prompt" : "Show full prompt")
            }

            resultContent
            if let message = state.actionErrorMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var resultContent: some View {
        let height = resultContentHeight

        if state.errorMessage == nil && state.response.isEmpty && state.isGenerating {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Thinking with Apple Intelligence…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
        } else {
            ScrollView {
                Text(displayedText)
                    .font(.system(size: 13))
                    .foregroundStyle(state.errorMessage == nil ? Color.primary : Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            }
            .frame(height: height)
            .accessibilityIdentifier("responseText")
        }
    }

    private var resultContentHeight: CGFloat {
        let maximumHeight = resultContentHeightLimit

        if state.errorMessage == nil && state.isGenerating && state.response.isEmpty {
            return min(36, maximumHeight)
        }

        let height = measuredTextHeight(displayedText, width: FloaterPanelLayout.contentWidth, fontSize: 13) + 4
        return min(maximumHeight, max(18, height))
    }

    private var resultContentHeightLimit: CGFloat {
        let errorHeight = state.actionErrorMessage.map {
            measuredTextHeight($0, width: FloaterPanelLayout.contentWidth, fontSize: 12) + 8
        } ?? 0
        let maximumHeight = max(18, FloaterPanelLayout.maximumResponseHeight - errorHeight)
        guard state.isPromptExpanded, let prompt = state.currentRequest?.prompt else {
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
        state.isPromptExpanded
            ? measuredTextHeight(text, width: FloaterPanelLayout.contentWidth, fontSize: 12)
            : summaryHeight(for: text)
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
            PanelButton("Copy", control: .copy, focus: $focusedControl, action: onCopy)
                .help("Copy the response (Command+C)")
            PanelButton("Edit", control: .edit, focus: $focusedControl, action: state.beginEditing)
                .help("Edit the prompt and run it again (Command+E)")
            PanelButton(
                "Replace", control: .replace, focus: $focusedControl,
                isEnabled: canReplace, action: onReplace
            )
            .help("Replace text in the previous app. Enable Accessibility from Floater's menu to allow this.")
            PanelButton("Dismiss", control: .dismiss, focus: $focusedControl, action: onDismiss)
        }
    }
}
