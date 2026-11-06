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
    let mapStore: StoreOf<IndoorMapFeature>
    @State private var isSearchPresented = false

    var body: some View {
        NavigationStack {
            BookSearchView(
                store: store,
                onShowBasket: {
                    store.send(.basketButtonTapped)
                },
                onShowFavorites: {
                    store.send(.favoritesButtonTapped)
                },
                onShowProfile: {
                    store.send(.profileButtonTapped)
                }
            )
            .navigationDestination(
                item: $store.scope(state: \.favorites, action: \.favorites)
            ) { favoritesStore in
                BookFavoritesView(store: favoritesStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.basket, action: \.basket)
            ) { basketStore in
                BookBasketView(store: basketStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $store.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailMapView(
                    store: detailStore,
                    mapStore: mapStore
                )
            }
            .navigationDestination(
                item: $store.scope(state: \.shelfMap, action: \.shelfMap)
            ) { shelfMapStore in
                BookShelfMapView(store: shelfMapStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $store.scope(state: \.myPage, action: \.myPage)
            ) { myPageStore in
                MyPageView(store: myPageStore, mapStore: mapStore)
            }
        }
        .searchable(
            text: Binding(
                get: { store.query },
                set: { store.send(.queryChanged($0)) }
            ),
            isPresented: $isSearchPresented,
            prompt: "책 제목이나 저자를 검색하세요"
        )
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .onSubmit(of: .search, submitSearch)
        .task {
            store.send(.task)
        }
    }

    private func submitSearch() {
        guard !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        store.send(.searchButtonTapped)
        if store.query.isEmpty {
            isSearchPresented = false
        }
    }
}
