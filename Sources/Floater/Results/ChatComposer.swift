import SwiftUI

struct ChatComposer: View {
    @ObservedObject var state: FloaterState
    @Binding var focusedControl: PanelControl?

    var body: some View {
        MultilineInput(
            text: $state.followUp, placeholder: "Continue the conversation…", label: "Message",
            isFocused: focusedControl == .composer, prefersInitialFocus: true,
            identifier: PanelControl.composer.rawValue, visibleLineCount: 3,
            trailingContentWidth: state.isGenerating || state.canRetry ? 70 : 36,
            onFocus: { if focusedControl != .composer { focusedControl = .composer } },
            onSubmit: state.sendFollowUp
        )
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                if state.isGenerating {
                    PanelButton("Stop", control: .stop, focus: $focusedControl, systemImage: "stop.fill", action: state.stop)
                        .help("Stop generating")
                } else if state.canRetry {
                    PanelButton("Retry", control: .retry, focus: $focusedControl, systemImage: "arrow.clockwise", action: state.retry)
                        .help("Retry the last reply")
                }
                PanelButton(
                    "Send", control: .send, focus: $focusedControl,
                    isEnabled: state.canSend, isPrimary: true, systemImage: "arrow.up"
                ) {
                    state.sendFollowUp()
                    focusedControl = .composer
                }
                .help("Send message (Enter). Add a new line with Shift+Enter.")
            }
            .padding(6)
        }
    }
}
