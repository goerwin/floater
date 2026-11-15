import Foundation

enum AIModel: String, CaseIterable, Identifiable {
    case gemma4E4B
    case appleIntelligence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gemma4E4B: "Gemma 4 E4B"
        case .appleIntelligence: "Apple Intelligence"
        }
    }
}
