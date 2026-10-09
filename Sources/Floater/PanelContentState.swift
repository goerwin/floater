import Combine
import Foundation

@MainActor
final class PanelContentState: ObservableObject {
    @Published var prompt = ""
    @Published var input = ""
    @Published var title: String?
    @Published var isPromptExpanded = false

    func clear() {
        prompt = ""
        input = ""
        title = nil
        isPromptExpanded = false
    }
}

@MainActor
final class PanelNavigation: ObservableObject {
    @Published var isShowingHistory = false
}

@MainActor
final class HistoryViewState: ObservableObject {
    @Published var query = ""
    @Published var selection: UUID?
    var focusedControlIdentifier = "historySearch"
}
