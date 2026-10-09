import SwiftUI

struct FloaterWindowView: View {
    @ObservedObject var navigation: PanelNavigation
    let panel: FloaterPanelView
    let history: HistoryView
    let onContentChange: () -> Void

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.regularMaterial)
                    .contentShape(Rectangle())
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            }
            .onChange(of: navigation.isShowingHistory) { _, _ in onContentChange() }
    }

    @ViewBuilder
    private var content: some View {
        if navigation.isShowingHistory {
            history
        } else {
            panel
        }
    }
}
