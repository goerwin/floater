import AppKit
import SwiftUI

struct ResultsView: View {
    @ObservedObject var state: FloaterState
    let canReplace: Bool
    @Binding var focusedControl: PanelControl?
    let onCopy: () -> Void
    let onReplace: () -> Void
    let onDismiss: () -> Void
    @State private var composerHeight: CGFloat = 50

    private var transcript: String {
        var parts: [String] = []
        for (index, message) in state.messages.enumerated() {
            if index == 0 && !state.isPromptExpanded { continue }
            let label = message.role == .user ? "You" : "Floater"
            var text = label + "\n" + message.content
            switch message.status {
            case .stopped: text += "\n[Stopped]"
            case .failed: text += "\n[Failed]"
            case .generating:
                if message.content.isEmpty { text += state.preparationMessage }
            case .complete: break
            }
            if let error = message.error { text += "\n" + ChatGenerationError.displayMessage(error) }
            parts.append(text)
        }
        if let error = state.errorMessage, state.messages.last?.error != error {
            parts.append("Error\n" + ChatGenerationError.displayMessage(error))
        }
        return parts.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = state.currentRequest {
                Button {
                    state.isPromptExpanded.toggle()
                } label: {
                    Text(state.isPromptExpanded ? "Hide full prompt" : request.prompt)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(state.isPromptExpanded ? "Collapse prompt" : "Show full prompt")
            }
            ResponseText(
                text: transcript,
                isSelectable: true, isError: false,
                maximumHeight: max(60, FloaterPanelLayout.maximumResponseHeight - composerHeight - 88 - noticeHeight),
                scrollRequestID: state.messages.last?.id,
                promptIsExpanded: state.isPromptExpanded
            )
            .id(state.resultID)

            if let message = state.actionErrorMessage ?? state.persistenceError {
                ScrollView { notice(message, isError: true) }.frame(maxHeight: 54)
            }
            conversationActions
            ChatComposer(state: state, focusedControl: $focusedControl)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var noticeHeight: CGFloat {
        state.actionErrorMessage != nil || state.persistenceError != nil ? 62 : 0
    }

    private func notice(_ message: String, isError: Bool = false) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var conversationActions: some View {
        HStack(spacing: 8) {
            PanelButton("Compact", control: .compact, focus: $focusedControl, isEnabled: state.canCompact, action: state.compact)
                .help("Summarize earlier messages for the model. Original messages stay saved.")
            if state.isGenerating {
                PanelButton("Stop", control: .stop, focus: $focusedControl, action: state.stop)
            } else if state.canRetry {
                PanelButton("Retry", control: .retry, focus: $focusedControl, action: state.retry)
            }
            Spacer(minLength: 0)
            if state.isCompacting {
                Text("Compacting…").font(.caption).foregroundStyle(.secondary)
            } else if state.conversation?.summary != nil {
                Text("Earlier messages summarized").font(.caption).foregroundStyle(.secondary)
                    .help("The model uses a summary of earlier messages. The full conversation is still shown here.")
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Spacer()
            PanelButton("Copy", control: .copy, focus: $focusedControl, isEnabled: state.canUseResponse, action: onCopy)
                .help("Copy the latest completed reply (Command+C)")
            PanelButton("Edit as New", control: .edit, focus: $focusedControl, action: state.beginEditing)
                .help("Copy the original prompt into a new draft (Command+E)")
            PanelButton("Replace", control: .replace, focus: $focusedControl, isEnabled: canReplace, action: onReplace)
                .help("Replace text in the source editor (Command+S)")
            PanelButton("Dismiss", control: .dismiss, focus: $focusedControl, action: onDismiss)
        }
    }
}
