import ComposableArchitecture
import SwiftUI

/// 같은 서가의 찜한 책을 기존 경로 미리보기의 탭·페이징 카드로 탐색한다.
struct FavoriteShelfBooksView: View {
    let store: StoreOf<BookShelfMapFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @State private var guidanceBook: Book?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        BookRouteBooksPreviewView(
            books: store.books,
            shelfStore: store,
            session: nil,
            isLoadingRoute: false,
            routeError: nil,
            canStart: true,
            onBack: { dismiss() },
            onStart: { guidanceBook = $0 },
            onRetry: {},
            guidesSelectedBook: true,
            homeAnnotations: mapStore.homeAnnotations
        )
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .fullScreenCover(item: $guidanceBook) { book in
            BookRoutePreviewView(books: [book], entryMode: .direct)
                .environment(\.indoorRouteMapStore, mapStore)
        }
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.map(.disappeared)) }
        .accessibilityIdentifier("favoriteShelfBooks")
    }
}
