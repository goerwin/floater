import AppKit
import SwiftUI

@main
struct FloaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Floater", systemImage: "sparkles") {
            Button("New request") {
                AppDelegate.shared?.showComposer()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("History…") {
                appDelegate.showHistory()
            }
            .keyboardShortcut("h", modifiers: .command)

            ConfigurationMenu(settings: appDelegate.settings)
            AccessibilityMenu(accessibility: appDelegate.accessibility)

            Divider()

            Button("Quit Floater") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appVisibility) {}
        }
    }
}

private struct AccessibilityMenu: View {
    @ObservedObject var accessibility: AccessibilityAccess

    var body: some View {
        if accessibility.isGranted {
            Text("Accessibility access enabled")
        } else {
            Button("Enable Accessibility…", action: accessibility.request)
        }
    }
}

private struct ConfigurationMenu: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Menu("Configuration") {
            Section("When no text is selected") {
                Toggle("Replace entire focused field", isOn: $settings.replaceWholeFieldWhenUnselected)
            }
        }
    }
}
