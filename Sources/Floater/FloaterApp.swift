import AppKit
import SwiftUI

@main
struct FloaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Floater", systemImage: "sparkles") {
            Button("New…") {
                AppDelegate.shared?.showComposer()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("History…") {
                appDelegate.showHistory()
            }
            .keyboardShortcut("h", modifiers: .command)

            Divider()

            ReplacementSetting(settings: appDelegate.settings)
            AccessibilityMenu(accessibility: appDelegate.accessibility)

            Divider()

            Button(quitLabel) {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appVisibility) {}
        }
    }

    private var quitLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return "Quit Floater"
        }
        return "Quit Floater \(version)"
    }
}

private struct AccessibilityMenu: View {
    @ObservedObject var accessibility: AccessibilityAccess

    var body: some View {
        Button(accessibility.isGranted ? "Accessibility enabled" : "Enable Accessibility…", action: accessibility.request)
            .disabled(accessibility.isGranted)
    }
}

private struct ReplacementSetting: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Toggle("Replace entire text", isOn: $settings.replaceWholeFieldWhenUnselected)
            .help("When no text is selected, Replace overwrites the entire focused field.")
    }
}
