import SwiftUI
import ComposableArchitecture

struct ContentView: View {

    @State private var store = Store(
        initialState: BookSearchFeature.State()
    ) {
        BookSearchFeature()
    }

    var body: some View {
        BookSearchView(store: store)
    }
}

#Preview {
    ContentView()
}
