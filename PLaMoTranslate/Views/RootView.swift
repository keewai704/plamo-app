import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var model = appModel
        let errorMessage = appModel.errorMessage

        TranslateView()
            .sheet(isPresented: $model.isShowingModelSheet) {
                ModelListView()
                    .environment(appModel)
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { appModel.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { appModel.errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
