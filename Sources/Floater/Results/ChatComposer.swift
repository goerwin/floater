import SwiftUI

struct ChatComposer: View {
    @ObservedObject var state: FloaterState
    @Binding var focusedControl: PanelControl?

    var body: some View {
        MultilineInput(
            text: $state.followUp, placeholder: "Continue the conversation…", label: "Message",
            isFocused: focusedControl == .composer, prefersInitialFocus: true,
            identifier: PanelControl.composer.rawValue, sendsOnReturn: true, visibleLineCount: 3,
            trailingContentWidth: 36,
            onFocus: { if focusedControl != .composer { focusedControl = .composer } },
            onSubmit: state.sendFollowUp
        )
        .overlay(alignment: .bottomTrailing) {
            PanelButton(
                "Send", control: .send, focus: $focusedControl,
                isEnabled: state.canSend, isPrimary: true, systemImage: "arrow.up"
            ) {
                state.sendFollowUp()
                focusedControl = .composer
            }
            .help("Send message (Enter). Add a new line with Shift+Enter.")
            .padding(6)
        }
    }
}
