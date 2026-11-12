import ComposableArchitecture
import SwiftUI

struct FavoriteShelfBooksView: View {
    let store: StoreOf<BookShelfMapFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BookRouteBooksPreviewView(
            books: store.books,
            shelfStore: store,
            routePlan: nil,
            isLoadingRoute: false,
            routeError: nil,
            canStart: true,
            onBack: { dismiss() },
            onStart: { store.send(.guidanceRequested($0)) },
            onRetry: {},
            guidesSelectedBook: true,
            homeAnnotations: mapStore.homeAnnotations
        )
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.map(.disappeared)) }
        .accessibilityIdentifier("favoriteShelfBooks")
    }
}
