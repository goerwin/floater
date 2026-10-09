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

            Divider()

            Button("Quit Floater") {
                NSApp.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
