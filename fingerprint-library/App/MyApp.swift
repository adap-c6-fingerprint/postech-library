import SwiftUI
import ComposableArchitecture

@main struct MyApp: App {
    @State private var store = Store(initialState: AppFeature.State()) { AppFeature() }

    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
