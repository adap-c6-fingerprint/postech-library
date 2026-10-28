//
//  BookSearchTabView.swift
//  fingerprint-library
//
//  Created by Codex on 10/27/26.
//

import ComposableArchitecture
import SwiftUI

struct BookSearchTabView: View {
    @State private var store: StoreOf<BookSearchFeature>
    @State private var isBasketPresented = false
    @Environment(\.isSearching) private var isSearching

    init(store: StoreOf<BookSearchFeature>? = nil) {
        _store = State(initialValue: store ?? Store(
            initialState: BookSearchFeature.State()
        ) { BookSearchFeature() })
    }

    var body: some View {
        NavigationStack {
            BookSearchView(
                store: store,
                isEditingSearch: isSearching,
                onSelectRecentQuery: { keyword in
                    store.send(.queryChanged(keyword))
                    submitSearch()
                },
                onShowBasket: {
                    isBasketPresented = true
                }
            )
            .navigationTitle("도서 검색")
            .navigationDestination(isPresented: $isBasketPresented) {
                BookBasketView(
                    books: store.basketBooks,
                    onDeletedSelected: { bookIDs in
                        store.send(.removeFromBasket(bookIDs))
                    },
                    onShowDirections: { bookIDs in
                        store.send(.basketDirectionsButtonTapped(bookIDs))
                    }
                )
            }
            .navigationDestination(
                item: $store.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailView(store: detailStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.shelfMap, action: \.shelfMap)
            ) { shelfMapStore in
                BookShelfMapView(store: shelfMapStore)
            }
        }
        .searchable(
            text: Binding(
                get: { store.query },
                set: { store.send(.queryChanged($0)) }
            ),
            prompt: "책 제목이나 저자를 검색하세요"
        )
        .onSubmit(of: .search, submitSearch)
        .task {
            store.send(.task)
        }
    }

    private func submitSearch() {
        guard !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        store.send(.searchButtonTapped)
    }
}
