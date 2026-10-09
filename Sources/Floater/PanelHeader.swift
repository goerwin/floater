import SwiftUI

struct PanelDragRegion: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
    }
}

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
