import AppKit
import SwiftUI

struct ResultsView: View {
    @ObservedObject var state: FloaterState
    let canReplace: Bool
    @Binding var focusedControl: PanelControl?
    let onCopy: () -> Void
    let onReplace: () -> Void
    let onDismiss: () -> Void
    @State private var composerHeight: CGFloat = 64
    @State private var promptHeight: CGFloat = 0

    private var noticeMessage: String? {
        state.actionErrorMessage ?? state.persistenceError
            ?? (state.messages.last?.error != state.errorMessage ? state.errorMessage.map(ChatGenerationError.displayMessage) : nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let request = state.currentRequest {
                PromptPreview(text: request.prompt, isExpanded: $state.isPromptExpanded) { copyMessage(request.prompt) }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { promptHeight = $0 }
            }
            ResponseText(
                messages: Array(state.messages.dropFirst()), preparationMessage: state.preparationMessage,
                maximumHeight: max(72, FloaterPanelLayout.maximumResponseHeight - composerHeight - promptHeight - noticeHeight),
                onCopyMessage: copyMessage
            )
            .id(state.resultID)

            if let message = noticeMessage {
                ScrollView { notice(message, isError: true) }.frame(maxHeight: 54)
            }
            ChatComposer(state: state, focusedControl: $focusedControl)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var noticeHeight: CGFloat {
        noticeMessage != nil ? 62 : 0
    }

    private func notice(_ message: String, isError: Bool = false) -> some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(isError ? Color.red : Color.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func copyMessage(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if state.isCompacting {
                Text("Compacting…").font(.caption).foregroundStyle(.secondary)
            } else if state.conversation?.summary != nil {
                Text("Earlier messages summarized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("The model uses a summary of earlier messages. The full conversation is still shown here.")
            }
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
