import AppKit
import SwiftUI

struct PanelHeader<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
        }
        .frame(minHeight: 24)
        .padding(.horizontal, FloaterPanelLayout.padding)
        .padding(.top, FloaterPanelLayout.padding)
        .padding(.bottom, 8)
    }
}

enum FloaterPanelLayout {
    static let width: CGFloat = 620
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 480
    static var maximumEditingHeight: CGFloat {
        max(minimumHeight, (NSScreen.main?.visibleFrame.height ?? 900) - 24)
    }
    static let maximumResponseHeight: CGFloat = 340
    static let padding: CGFloat = 14
    static let contentWidth = width - padding * 2
}
