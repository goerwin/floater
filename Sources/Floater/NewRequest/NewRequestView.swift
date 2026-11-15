import SwiftUI

struct NewRequestView: View {
    @Binding var prompt: String
    let canSubmit: Bool
    @Binding var focusedControl: PanelControl?
    let onSubmit: () -> Void
    let onDismiss: () -> Void
    let onContentChange: () -> Void
    @State private var fieldsHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prompt")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    MultilineInput(
                        text: $prompt,
                        placeholder: "What should Floater do?",
                        label: "Prompt",
                        isFocused: focusedControl == .prompt,
                        prefersInitialFocus: true,
                        identifier: PanelControl.prompt.rawValue,
                        onFocus: { if focusedControl != .prompt { focusedControl = .prompt } },
                        onSubmit: onSubmit
                    )
                }
                .padding(1)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldsHeight = $0; onContentChange() }
            }
            .frame(height: min(fieldsHeight, FloaterPanelLayout.maximumEditingHeight - 120))

            HStack(spacing: 8) {
                Spacer()
                PanelButton("Dismiss", control: .dismiss, focus: $focusedControl, action: onDismiss)
                PanelButton(
                    "Run", control: .run, focus: $focusedControl,
                    isEnabled: canSubmit,
                    isPrimary: true, action: onSubmit
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
