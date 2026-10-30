//
//  BookSearchTabView.swift
//  fingerprint-library
//
//  Created by Codex on 10/27/26.
//

import ComposableArchitecture
import SwiftUI

struct BookSearchTabView: View {
    @Bindable var store: StoreOf<BookSearchFeature>
    @Environment(\.isSearching) private var isSearching

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
                    store.send(.basketButtonTapped)
                }
            )
            .navigationDestination(
                item: $store.scope(state: \.basket, action: \.basket)
            ) { basketStore in
                BookBasketView(store: basketStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $store.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailView(store: detailStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $store.scope(state: \.shelfMap, action: \.shelfMap)
            ) { shelfMapStore in
                BookShelfMapView(store: shelfMapStore)
                    .toolbar(.visible, for: .navigationBar)
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
