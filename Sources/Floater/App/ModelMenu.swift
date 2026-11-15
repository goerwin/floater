import SwiftUI

struct ModelMenu: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Menu(settings.selectedModel.title) {
            Picker("Model", selection: $settings.selectedModel) {
                ForEach(AIModel.allCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}
