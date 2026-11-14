import SwiftUI

struct NewRequestView: View {
    @Binding var prompt: String
    @Binding var input: String
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
                    fieldLabel("Instructions")

                    editor(text: $prompt, placeholder: "What should Floater do?", label: "Instructions", control: .prompt)

                    fieldLabel("Prompt (optional)")

                    editor(text: $input, placeholder: "Add text to process (optional)", label: "Prompt (optional)", control: .input)
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

    private func editor(
        text: Binding<String>, placeholder: String, label: String, control: PanelControl
    ) -> some View {
        MultilineInput(
            text: text,
            placeholder: placeholder,
            label: label,
            isFocused: focusedControl == control,
            prefersInitialFocus: control == .prompt,
            identifier: control.rawValue,
            onFocus: { if focusedControl != control { focusedControl = control } },
            onSubmit: onSubmit
        )
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
    }
}
